from __future__ import annotations

from datetime import UTC, datetime
from http import HTTPStatus

from flask import Blueprint, current_app, jsonify

from dispatch_api.auth import require_auth, require_role
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService

blueprint = Blueprint("system", __name__, url_prefix="/api")


@blueprint.get("/health")
def health():
    return (
        jsonify(
            {
                "service": "dispatch-api",
                "status": "ok",
                "timestamp": datetime.now(tz=UTC).isoformat(),
            }
        ),
        HTTPStatus.OK,
    )


@blueprint.get("/ready")
def ready():
    supabase_client = current_app.extensions["supabase_client"]
    ready_state, diagnostics = supabase_client.check_readiness()
    status = HTTPStatus.OK if ready_state else HTTPStatus.SERVICE_UNAVAILABLE
    return (
        jsonify(
            {
                "service": "dispatch-api",
                "status": "ready" if ready_state else "not_ready",
                "diagnostics": diagnostics,
            }
        ),
        status,
    )


@blueprint.post("/system/report-escalations/scan")
@require_auth()
@require_role("municipality")
def scan_report_escalations():
    client = current_app.extensions["supabase_client"]
    report_service = ReportService(client, NotificationService(client))
    escalated_reports = report_service.scan_pending_timeouts()
    return jsonify({"count": len(escalated_reports), "reports": escalated_reports})
