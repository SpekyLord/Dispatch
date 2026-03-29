from __future__ import annotations

from datetime import UTC, datetime
from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.municipality import blueprint
from dispatch_api.services.analytics_service import AnalyticsService
from dispatch_api.services.assessment_service import AssessmentService
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService

VALID_VERIFICATION_ACTIONS = {"approved", "rejected"}


def _report_service() -> ReportService:
    client = current_app.extensions["supabase_client"]
    return ReportService(client, NotificationService(client))


def _analytics_service() -> AnalyticsService:
    return AnalyticsService(current_app.extensions["supabase_client"])


def _assessment_service() -> AssessmentService:
    return AssessmentService(current_app.extensions["supabase_client"])


@blueprint.get("/departments")
@require_auth()
@require_role("municipality")
def list_departments():
    client = current_app.extensions["supabase_client"]
    params: dict[str, str] = {"select": "*", "order": "created_at.desc"}

    status_filter = request.args.get("status")
    if status_filter:
        params["verification_status"] = f"eq.{status_filter}"

    rows = client.db_query("departments", params=params, use_service_role=True)
    return jsonify({"departments": rows})


@blueprint.get("/departments/pending")
@require_auth()
@require_role("municipality")
def list_pending_departments():
    client = current_app.extensions["supabase_client"]
    rows = client.db_query(
        "departments",
        params={
            "select": "*",
            "verification_status": "eq.pending",
            "order": "created_at.asc",
        },
        use_service_role=True,
    )
    return jsonify({"departments": rows})


@blueprint.get("/reports/escalated")
@require_auth()
@require_role("municipality")
def list_escalated_reports():
    reports = _report_service().list_municipality_escalated_reports()
    return jsonify({"reports": reports})


@blueprint.put("/departments/<dept_id>/verify")
@require_auth()
@require_role("municipality")
def verify_department(dept_id: str):
    reviewer = get_current_user()
    body = request.get_json(silent=True) or {}
    action = (body.get("action") or "").strip()

    if action not in VALID_VERIFICATION_ACTIONS:
        raise ApiError(
            f"Action must be one of: {', '.join(sorted(VALID_VERIFICATION_ACTIONS))}.",
            code="validation_error",
        )

    rejection_reason = (body.get("rejection_reason") or "").strip()
    if action == "rejected" and not rejection_reason:
        raise ApiError(
            "A rejection reason is required when rejecting a department.",
            code="validation_error",
        )

    client = current_app.extensions["supabase_client"]
    existing = client.db_query(
        "departments",
        params={"select": "*", "id": f"eq.{dept_id}"},
        use_service_role=True,
    )
    if not existing:
        raise ApiError("Department not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

    update_data = {
        "verification_status": action,
        "rejection_reason": rejection_reason or None,
        "verified_by": reviewer.id if action == "approved" else None,
        "verified_at": datetime.now(tz=UTC).isoformat() if action == "approved" else None,
    }
    rows = client.db_update(
        "departments",
        data=update_data,
        params={"id": f"eq.{dept_id}"},
        use_service_role=True,
    )
    if not rows:
        raise ApiError("Failed to update department.", code="update_failed")

    department = rows[0]
    if existing[0].get("user_id"):
        client.db_update(
            "users",
            data={"is_verified": action == "approved"},
            params={"id": f"eq.{existing[0]['user_id']}"},
            use_service_role=True,
            return_repr=False,
        )

    if department.get("user_id"):
        NotificationService(client).notify_verification_decision(department=department)

    return jsonify({"department": department})


# -- Phase 3: municipality report overview with filters --
@blueprint.get("/reports")
@require_auth()
@require_role("municipality")
def list_municipality_reports():
    filters = {
        "status": request.args.get("status"),
        "category": request.args.get("category"),
        "is_escalated": request.args.get("is_escalated"),
        "date_from": request.args.get("date_from"),
        "date_to": request.args.get("date_to"),
    }
    reports = _analytics_service().get_municipality_reports(filters)
    return jsonify({"reports": reports})


# -- Phase 3: aggregate analytics for dashboard --
@blueprint.get("/analytics")
@require_auth()
@require_role("municipality")
def get_analytics():
    data = _analytics_service().get_analytics()
    return jsonify(data)


# -- Phase 3: all damage assessments across departments --
@blueprint.get("/assessments")
@require_auth()
@require_role("municipality")
def list_assessments():
    assessments = _assessment_service().list_all_assessments()
    return jsonify({"assessments": assessments})
