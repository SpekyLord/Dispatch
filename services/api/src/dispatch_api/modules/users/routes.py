# User profile routes: read and update profile (full_name, phone, avatar_url, description, profile_picture, header_photo)

from __future__ import annotations

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.users import blueprint


def _coerce_bool(value) -> bool:
    return str(value).lower() in {"1", "true", "yes", "on"}


def _upload_user_profile_asset(*, file, owner_id: str, domain: str) -> str:
    storage = current_app.extensions["storage_service"]
    client = current_app.extensions["supabase_client"]
    file_data = file.read()
    content_type = file.content_type or "application/octet-stream"
    storage.validate_upload(content_type=content_type, size_bytes=len(file_data))
    object_path = storage.build_object_path(
        owner_id=owner_id,
        domain=f"{domain}/{owner_id}",
        filename=file.filename or "upload.bin",
    )
    client.storage_upload(
        bucket="department-feed-images",
        object_path=object_path,
        file_data=file_data,
        content_type=content_type,
    )
    return client.storage_public_url(bucket="department-feed-images", object_path=object_path)


@blueprint.get("/profile")
@require_auth()
def get_profile():
    """Fetch the authenticated user's profile. Uses their JWT for RLS."""
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
    """Update profile fields. Accepts JSON or multipart/form-data (for file uploads)."""
    user = get_current_user()
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    client = current_app.extensions["supabase_client"]

    has_form = request.files or request.form
    body = request.form if has_form else (request.get_json(silent=True) or {})

    allowed_fields = {"full_name", "phone", "avatar_url", "description"}
    update_data = {k: v for k, v in body.items() if k in allowed_fields}

    # Removal flags
    if _coerce_bool(body.get("remove_profile_picture")):
        update_data["profile_picture"] = None
    if _coerce_bool(body.get("remove_header_photo")):
        update_data["header_photo"] = None

    # File uploads
    profile_picture_file = request.files.get("profile_picture_file") if request.files else None
    header_photo_file = request.files.get("header_photo_file") if request.files else None

    if profile_picture_file and profile_picture_file.filename:
        update_data["profile_picture"] = _upload_user_profile_asset(
            file=profile_picture_file,
            owner_id=user.id,
            domain="user-profile/picture",
        )
    if header_photo_file and header_photo_file.filename:
        update_data["header_photo"] = _upload_user_profile_asset(
            file=header_photo_file,
            owner_id=user.id,
            domain="user-profile/header",
        )

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
