# Municipality routes: list departments, review pending, approve/reject verification

from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.municipality import blueprint

VALID_VERIFICATION_ACTIONS = {"approved", "rejected"}


@blueprint.get("/departments")
@require_auth()
@require_role("municipality")
def list_departments():
    """List all departments. Supports ?status= filter."""
    client = current_app.extensions["supabase_client"]
    params: dict[str, str] = {"select": "*", "order": "created_at.desc"}

    # Optional status filter
    status_filter = request.args.get("status")
    if status_filter:
        params["verification_status"] = f"eq.{status_filter}"

    rows = client.db_query("departments", params=params, use_service_role=True)
    return jsonify({"departments": rows})


@blueprint.get("/departments/pending")
@require_auth()
@require_role("municipality")
def list_pending_departments():
    """List pending departments, oldest first (FIFO review queue)."""
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


@blueprint.put("/departments/<dept_id>/verify")
@require_auth()
@require_role("municipality")
def verify_department(dept_id: str):
    """Approve or reject a department. Rejection requires a reason string."""
    body = request.get_json(silent=True) or {}
    action = (body.get("action") or "").strip()

    if action not in VALID_VERIFICATION_ACTIONS:
        raise ApiError(
            f"Action must be one of: {', '.join(sorted(VALID_VERIFICATION_ACTIONS))}.",
            code="validation_error",
        )

    # Rejection requires an explanation
    if action == "rejected":
        reason = (body.get("rejection_reason") or "").strip()
        if not reason:
            raise ApiError(
                "A rejection reason is required when rejecting a department.",
                code="validation_error",
            )

    client = current_app.extensions["supabase_client"]

    # Check department exists
    existing = client.db_query(
        "departments",
        params={"select": "id,verification_status", "id": f"eq.{dept_id}"},
        use_service_role=True,
    )
    if not existing:
        raise ApiError("Department not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

    # On approve: clear old rejection_reason. On reject: store the reason.
    update_data: dict[str, str | None] = {"verification_status": action}
    if action == "rejected":
        update_data["rejection_reason"] = body.get("rejection_reason", "").strip()
    else:
        update_data["rejection_reason"] = None

    rows = client.db_update(
        "departments",
        data=update_data,
        params={"id": f"eq.{dept_id}"},
        use_service_role=True,
    )

    if not rows:
        raise ApiError("Failed to update department.", code="update_failed")

    return jsonify({"department": rows[0]})
