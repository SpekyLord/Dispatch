from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.reports import blueprint

VALID_CATEGORIES = {
    "fire",
    "flood",
    "earthquake",
    "road_accident",
    "medical",
    "structural",
    "other",
}
VALID_SEVERITIES = {"low", "medium", "high", "critical"}
MAX_IMAGES_PER_REPORT = 3


@blueprint.post("")
@require_auth()
@require_role("citizen")
def create_report():
    """Create a new incident report. Starts as pending with an initial status history entry."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    body = request.get_json(silent=True) or {}

    description = (body.get("description") or "").strip()
    category = (body.get("category") or "").strip()
    severity = (body.get("severity") or "medium").strip()
    latitude = body.get("latitude")
    longitude = body.get("longitude")
    address = (body.get("address") or "").strip()

    if not description:
        raise ApiError("Description is required.", code="validation_error")
    if category not in VALID_CATEGORIES:
        raise ApiError(
            f"Category must be one of: {', '.join(sorted(VALID_CATEGORIES))}.",
            code="validation_error",
        )
    if severity not in VALID_SEVERITIES:
        raise ApiError(
            f"Severity must be one of: {', '.join(sorted(VALID_SEVERITIES))}.",
            code="validation_error",
        )

    report_data: dict = {
        "reporter_id": user.id,
        "description": description,
        "category": category,
        "severity": severity,
        "status": "pending",
        "is_escalated": False,
        "image_urls": body.get("image_urls", []),
    }

    # Location is optional — not all users grant GPS access
    if latitude is not None and longitude is not None:
        report_data["latitude"] = latitude
        report_data["longitude"] = longitude
    if address:
        report_data["address"] = address

    rows = client.db_insert("incident_reports", data=report_data, use_service_role=True)

    if not rows:
        raise ApiError("Failed to create report.", code="create_failed")

    report = rows[0]

    # Seed status history — best-effort, don't fail the request if this errors
    try:
        client.db_insert(
            "report_status_history",
            data={
                "report_id": report["id"],
                "status": "pending",
                "changed_by": user.id,
                "note": "Report submitted.",
            },
            use_service_role=True,
            return_repr=False,
        )
    except Exception:
        pass

    return jsonify({"report": report}), HTTPStatus.CREATED


@blueprint.get("")
@require_auth()
@require_role("citizen")
def list_reports():
    """List the citizen's own reports. Supports ?status= and ?category= filters."""
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
    return jsonify({"reports": rows})


@blueprint.get("/<report_id>")
@require_auth()
def get_report(report_id: str):
    """Get a report + status history. Citizens can only view their own reports."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]

    rows = client.db_query(
        "incident_reports",
        params={"select": "*", "id": f"eq.{report_id}"},
        use_service_role=True,
    )

    if not rows:
        raise ApiError("Report not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

    report = rows[0]

    # Citizens can only see their own; departments/municipality can see all
    if user.role == "citizen" and report.get("reporter_id") != user.id:
        raise ApiError(
            "You do not have permission to view this report.",
            code="forbidden",
            status_code=HTTPStatus.FORBIDDEN,
        )

    # Fetch timeline (oldest first for chronological display)
    history = []
    try:
        history = client.db_query(
            "report_status_history",
            params={
                "select": "*",
                "report_id": f"eq.{report_id}",
                "order": "created_at.asc",
            },
            use_service_role=True,
        )
    except Exception:
        pass

    return jsonify({"report": report, "status_history": history})


@blueprint.post("/<report_id>/upload")
@require_auth()
@require_role("citizen")
def upload_report_image(report_id: str):
    """Upload a photo to a report. Max 3 images per report."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    storage = current_app.extensions["storage_service"]

    # Verify ownership
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

    # Enforce image limit
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

    # Validate type and size
    storage.validate_upload(content_type=content_type, size_bytes=len(file_data))

    # Upload to Supabase Storage (path: {user_id}/reports/{uuid}_{filename})
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

    # Append new URL to the image_urls array and write it back
    public_url = client.storage_public_url(bucket="report-images", object_path=object_path)

    updated_images = [*existing_images, public_url]
    client.db_update(
        "incident_reports",
        data={"image_urls": updated_images},
        params={"id": f"eq.{report_id}"},
        use_service_role=True,
        return_repr=False,
    )

    return (
        jsonify({"image_url": public_url, "total_images": len(updated_images)}),
        HTTPStatus.CREATED,
    )
