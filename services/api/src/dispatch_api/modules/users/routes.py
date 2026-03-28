from __future__ import annotations

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.users import blueprint


@blueprint.get("/profile")
@require_auth()
def get_profile():
    user = get_current_user()
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    client = current_app.extensions["supabase_client"]

    rows = client.db_query(
        "users",
        params={"select": "*", "id": f"eq.{user.id}"},
        token=token,
    )
    if not rows:
        raise ApiError("Profile not found.", code="not_found", status_code=404)

    return jsonify({"profile": rows[0]})


@blueprint.put("/profile")
@require_auth()
def update_profile():
    user = get_current_user()
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    client = current_app.extensions["supabase_client"]
    body = request.get_json(silent=True) or {}

    allowed_fields = {"full_name", "phone", "avatar_url"}
    update_data = {k: v for k, v in body.items() if k in allowed_fields}

    if not update_data:
        raise ApiError("No valid fields to update.", code="validation_error")

    rows = client.db_update(
        "users",
        data=update_data,
        params={"id": f"eq.{user.id}"},
        token=token,
    )

    if not rows:
        raise ApiError("Profile not found.", code="not_found", status_code=404)

    return jsonify({"profile": rows[0]})
