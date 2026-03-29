from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.reports import blueprint
from dispatch_api.services.department_service import DepartmentService
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService

MAX_IMAGES_PER_REPORT = 3


def _report_service() -> ReportService:
    client = current_app.extensions["supabase_client"]
    return ReportService(client, NotificationService(client))


def _department_service() -> DepartmentService:
    return DepartmentService(current_app.extensions["supabase_client"])


@blueprint.post("")
@require_auth()
@require_role("citizen")
def create_report():
    user = get_current_user()
    body = request.get_json(silent=True) or {}
    image_urls = body.get("image_urls") or []

    if not isinstance(image_urls, list):
        raise ApiError("image_urls must be a list.", code="validation_error")
    if len(image_urls) > MAX_IMAGES_PER_REPORT:
        raise ApiError(
            f"Maximum {MAX_IMAGES_PER_REPORT} images per report.",
            code="image_limit_exceeded",
        )

    report = _report_service().create_report(
        reporter_id=user.id,
        title=(body.get("title") or "").strip() or None,
        description=(body.get("description") or "").strip(),
        category=(body.get("category") or "").strip() or None,
        severity=(body.get("severity") or "medium").strip(),
        latitude=body.get("latitude"),
        longitude=body.get("longitude"),
        address=(body.get("address") or "").strip() or None,
        image_urls=image_urls,
    )
    return jsonify({"report": report}), HTTPStatus.CREATED


@blueprint.get("")
@require_auth()
@require_role("citizen")
def list_reports():
    user = get_current_user()
    client = current_app.extensions["supabase_client"]

    params: dict[str, str] = {
        "select": "*",
        "reporter_id": f"eq.{user.id}",
        "order": "created_at.desc",
    }

    status_filter = request.args.get("status")
    if status_filter:
        params["status"] = f"eq.{status_filter}"

    category_filter = request.args.get("category")
    if category_filter:
        params["category"] = f"eq.{category_filter}"

    rows = client.db_query("incident_reports", params=params, use_service_role=True)
    own_rows = [row for row in rows if row.get("reporter_id") == user.id]
    return jsonify({"reports": own_rows})


@blueprint.get("/<report_id>")
@require_auth()
def get_report(report_id: str):
    user = get_current_user()
    report_service = _report_service()
    report = report_service.get_report(report_id)

    if user.role == "citizen":
        if report.get("reporter_id") != user.id:
            raise ApiError(
                "You do not have permission to view this report.",
                code="forbidden",
                status_code=HTTPStatus.FORBIDDEN,
            )
    elif user.role == "department":
        department_service = _department_service()
        department = department_service.get_department_for_user(user.id)
        department_service.require_verified_department(department)
        report = report_service.get_report_for_department(
            report_id=report_id, department=department
        )

    client = current_app.extensions["supabase_client"]
    history = client.db_query(
        "report_status_history",
        params={
            "select": "*",
            "report_id": f"eq.{report_id}",
            "order": "created_at.asc",
        },
        use_service_role=True,
    )

    # Phase 3: include department responses and merged timeline
    dept_responses = client.db_query(
        "department_responses",
        params={
            "select": "*",
            "report_id": f"eq.{report_id}",
            "order": "responded_at.asc",
        },
        use_service_role=True,
    )
    # Enrich responses with department name
    dept_ids = {r["department_id"] for r in dept_responses if r.get("department_id")}
    dept_map: dict[str, str] = {}
    if dept_ids:
        depts = client.db_query("departments", params={"select": "id,name"}, use_service_role=True)
        dept_map = {d["id"]: d.get("name", "Unknown") for d in depts if d.get("id") in dept_ids}
    for r in dept_responses:
        r["department_name"] = dept_map.get(r.get("department_id", ""), "Unknown")

    # Build unified timeline sorted by timestamp
    timeline: list[dict] = []
    for h in history:
        timeline.append(
            {
                "type": "status_change",
                "timestamp": h.get("created_at"),
                "new_status": h.get("new_status"),
                "old_status": h.get("old_status"),
                "notes": h.get("notes"),
                "changed_by": h.get("changed_by"),
            }
        )
    for r in dept_responses:
        timeline.append(
            {
                "type": "department_response",
                "timestamp": r.get("responded_at") or r.get("created_at"),
                "action": r.get("action"),
                "department_name": r.get("department_name"),
                "notes": r.get("notes"),
                "decline_reason": r.get("decline_reason"),
            }
        )
    timeline.sort(key=lambda e: e.get("timestamp") or "")

    return jsonify(
        {
            "report": report,
            "status_history": history,
            "department_responses": dept_responses,
            "timeline": timeline,
        }
    )


@blueprint.post("/<report_id>/upload")
@require_auth()
@require_role("citizen")
def upload_report_image(report_id: str):
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    storage = current_app.extensions["storage_service"]

    rows = client.db_query(
        "incident_reports",
        params={"select": "id,reporter_id,image_urls", "id": f"eq.{report_id}"},
        use_service_role=True,
    )
    if not rows:
        raise ApiError("Report not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

    report = rows[0]
    if report.get("reporter_id") != user.id:
        raise ApiError("Forbidden.", code="forbidden", status_code=HTTPStatus.FORBIDDEN)

    existing_images = report.get("image_urls") or []
    if len(existing_images) >= MAX_IMAGES_PER_REPORT:
        raise ApiError(
            f"Maximum {MAX_IMAGES_PER_REPORT} images per report.",
            code="image_limit_exceeded",
        )

    if "file" not in request.files:
        raise ApiError("No file provided.", code="validation_error")

    file = request.files["file"]
    content_type = file.content_type or "application/octet-stream"
    file_data = file.read()
    storage.validate_upload(content_type=content_type, size_bytes=len(file_data))

    object_path = storage.build_object_path(
        owner_id=user.id,
        domain="reports",
        filename=file.filename or "image.jpg",
    )

    client.storage_upload(
        bucket="report-images",
        object_path=object_path,
        file_data=file_data,
        content_type=content_type,
    )

    public_url = client.storage_public_url(bucket="report-images", object_path=object_path)
    updated_images = [*existing_images, public_url]
    client.db_update(
        "incident_reports",
        data={"image_urls": updated_images},
        params={"id": f"eq.{report_id}"},
        use_service_role=True,
        return_repr=False,
    )

    return jsonify(
        {"image_url": public_url, "total_images": len(updated_images)}
    ), HTTPStatus.CREATED
