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


@blueprint.put("/departments/<dept_id>/verify")
@require_auth()
@require_role("municipality")
def verify_department(dept_id: str):
    body = request.get_json(silent=True) or {}
    action = (body.get("action") or "").strip()

    if action not in VALID_VERIFICATION_ACTIONS:
        raise ApiError(
            f"Action must be one of: {', '.join(sorted(VALID_VERIFICATION_ACTIONS))}.",
            code="validation_error",
        )

    if action == "rejected":
        reason = (body.get("rejection_reason") or "").strip()
        if not reason:
            raise ApiError(
                "A rejection reason is required when rejecting a department.",
                code="validation_error",
            )

    client = current_app.extensions["supabase_client"]

    # Verify the department exists
    existing = client.db_query(
        "departments",
        params={"select": "id,verification_status", "id": f"eq.{dept_id}"},
        use_service_role=True,
    )
    if not existing:
        raise ApiError("Department not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

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
