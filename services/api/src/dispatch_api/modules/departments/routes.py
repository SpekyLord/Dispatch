from __future__ import annotations

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.departments import blueprint


def _get_department_for_user(client, user_id: str):
    """Fetch the department row linked to this user. Uses service_role to bypass RLS."""
    rows = client.db_query(
        "departments",
        params={"select": "*", "user_id": f"eq.{user_id}"},
        use_service_role=True,
    )
    if not rows:
        raise ApiError("Department profile not found.", code="not_found", status_code=404)
    return rows[0]


def _require_verified_department(dept: dict) -> None:
    """Block access if the department isn't approved yet. Reusable guard for Phase 2."""
    if dept.get("verification_status") != "approved":
        raise ApiError(
            "Your department has not been verified yet. Contact the municipality for approval.",
            code="department_not_verified",
            status_code=403,
        )


@blueprint.get("/profile")
@require_auth()
@require_role("department")
def get_department_profile():
    """Return the authenticated department's profile."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    dept = _get_department_for_user(client, user.id)
    return jsonify({"department": dept})


@blueprint.put("/profile")
@require_auth()
@require_role("department")
def update_department_profile():
    """Update department profile. Auto-resubmits rejected departments back to pending."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    dept = _get_department_for_user(client, user.id)
    body = request.get_json(silent=True) or {}

    # Only allow safe fields — block id, user_id, verification_status from direct edits
    allowed_fields = {
        "name",
        "type",
        "contact_number",
        "address",
        "area_of_responsibility",
    }
    update_data = {k: v for k, v in body.items() if k in allowed_fields}

    if not update_data:
        raise ApiError("No valid fields to update.", code="validation_error")

    # Auto-resubmit: editing a rejected profile moves it back to pending
    if dept.get("verification_status") == "rejected":
        update_data["verification_status"] = "pending"
        update_data["rejection_reason"] = None

    rows = client.db_update(
        "departments",
        data=update_data,
        params={"id": f"eq.{dept['id']}"},
        use_service_role=True,
    )

    if not rows:
        raise ApiError("Failed to update department.", code="update_failed")

    return jsonify({"department": rows[0]})
