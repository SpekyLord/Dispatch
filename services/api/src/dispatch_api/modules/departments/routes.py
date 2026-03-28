from __future__ import annotations

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.departments import blueprint
from dispatch_api.services.department_service import DepartmentService
from dispatch_api.services.feed_service import FeedService
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService


def _department_service() -> DepartmentService:
    return DepartmentService(current_app.extensions["supabase_client"])


def _report_service() -> ReportService:
    client = current_app.extensions["supabase_client"]
    return ReportService(client, NotificationService(client))


def _feed_service() -> FeedService:
    client = current_app.extensions["supabase_client"]
    return FeedService(client, NotificationService(client))


@blueprint.get("/profile")
@require_auth()
@require_role("department")
def get_department_profile():
    user = get_current_user()
    department = _department_service().get_department_for_user(user.id)
    return jsonify({"department": department})


@blueprint.put("/profile")
@require_auth()
@require_role("department")
def update_department_profile():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    client = current_app.extensions["supabase_client"]
    body = request.get_json(silent=True) or {}

    allowed_fields = {
        "name",
        "type",
        "contact_number",
        "address",
        "area_of_responsibility",
        "description",
    }
    update_data = {key: value for key, value in body.items() if key in allowed_fields}
    if not update_data:
        raise ApiError("No valid fields to update.", code="validation_error")

    if department.get("verification_status") == "rejected":
        update_data["verification_status"] = "pending"
        update_data["rejection_reason"] = None
        update_data["verified_at"] = None
        update_data["verified_by"] = None

    rows = client.db_update(
        "departments",
        data=update_data,
        params={"id": f"eq.{department['id']}"},
        use_service_role=True,
    )
    if not rows:
        raise ApiError("Failed to update department.", code="update_failed")

    return jsonify({"department": rows[0]})


@blueprint.get("/reports")
@require_auth()
@require_role("department")
def list_department_reports():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    reports = _report_service().list_department_reports(
        department=department,
        status=request.args.get("status"),
        category=request.args.get("category"),
    )
    return jsonify({"reports": reports})


@blueprint.post("/reports/<report_id>/accept")
@require_auth()
@require_role("department")
def accept_report(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    result = _report_service().accept_report(
        report_id=report_id,
        department=department,
        actor_user_id=user.id,
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify(result)


@blueprint.post("/reports/<report_id>/decline")
@require_auth()
@require_role("department")
def decline_report(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    result = _report_service().decline_report(
        report_id=report_id,
        department=department,
        decline_reason=(body.get("decline_reason") or "").strip(),
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify(result)


@blueprint.get("/reports/<report_id>/responses")
@require_auth()
@require_role("department")
def get_report_responses(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    result = _report_service().get_department_response_roster(
        report_id=report_id, department=department
    )
    return jsonify(result)


@blueprint.put("/reports/<report_id>/status")
@require_auth()
@require_role("department")
def update_report_status(report_id: str):
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    report = _report_service().update_status(
        report_id=report_id,
        department=department,
        actor_user_id=user.id,
        new_status=(body.get("status") or "").strip(),
        notes=(body.get("notes") or "").strip() or None,
    )
    return jsonify({"report": report})


@blueprint.post("/posts")
@require_auth()
@require_role("department")
def create_post():
    user = get_current_user()
    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    image_urls = body.get("image_urls") or []
    post = _feed_service().create_post(
        department=department,
        author_id=user.id,
        title=(body.get("title") or "").strip(),
        content=(body.get("content") or "").strip(),
        category=(body.get("category") or "").strip(),
        image_urls=image_urls if isinstance(image_urls, list) else [],
        is_pinned=bool(body.get("is_pinned", False)),
    )
    return jsonify({"post": post}), 201
