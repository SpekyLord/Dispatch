# Auth routes: register, login, logout, session restore (/me)

from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.auth import blueprint
from dispatch_api.services.offline_token_service import OfflineTokenService

# Municipality accounts are pre-seeded, not self-registered
VALID_ROLES = {"citizen", "department"}


def _offline_token_service() -> OfflineTokenService:
    settings = current_app.config["SETTINGS"]
    return OfflineTokenService(secret=settings.supabase_service_role_key)


def _issue_offline_token(
    *,
    user_id: str | None,
    role: str | None,
    department: dict | None = None,
) -> str | None:
    if not user_id or not role:
        return None
    return _offline_token_service().issue_token(
        user_id=user_id,
        role=role,
        department_id=(department or {}).get("id"),
    )


def _require_supabase_auth_config() -> None:
    settings = current_app.config["SETTINGS"]
    missing = settings.missing_supabase_keys
    if not missing:
        return
    raise ApiError(
        (
            "Supabase auth is not configured. Check services/api/.env and "
            "confirm the Supabase project is active."
        ),
        code="supabase_config_missing",
        details={"missing_env": missing},
        status_code=HTTPStatus.BAD_REQUEST,
    )


# Normalize the upstream Supabase payload once so web and mobile see the
# same error.code/error.message pair when signup is rejected.
def _extract_supabase_error(error: dict | None) -> tuple[str, str, dict]:
    payload = error or {}
    code = (
        payload.get("code")
        or payload.get("error_code")
        or payload.get("error")
        or "registration_failed"
    )
    message = (
        payload.get("msg")
        or payload.get("message")
        or payload.get("error_description")
        or "Registration failed."
    )
    return str(code), str(message), payload


@blueprint.post("/register")
def register():
    """Create a new citizen or department account and return the access token."""
    body = request.get_json(silent=True) or {}
    email = (body.get("email") or "").strip()
    password = body.get("password") or ""
    role = (body.get("role") or "").strip()
    full_name = (body.get("full_name") or "").strip()

    if not email or not password:
        raise ApiError("Email and password are required.", code="validation_error")
    if role not in VALID_ROLES:
        raise ApiError(
            f"Role must be one of: {', '.join(sorted(VALID_ROLES))}.",
            code="validation_error",
        )
    if len(password) < 6:
        raise ApiError("Password must be at least 6 characters.", code="validation_error")

    _require_supabase_auth_config()
    client = current_app.extensions["supabase_client"]

    # Create user in Supabase Auth (role stored in user_metadata for JWT access)
    result = client.sign_up(
        email=email,
        password=password,
        user_metadata={"role": role, "full_name": full_name},
    )

    if "error" in result:
        code, message, details = _extract_supabase_error(result.get("error"))
        raise ApiError(
            message,
            code=code,
            details={"supabase_error": details},
            status_code=HTTPStatus.BAD_REQUEST,
        )

    auth_user = result.get("user") or result
    user_id = auth_user.get("id")
    access_token = result.get("access_token") or (result.get("session") or {}).get("access_token")
    refresh_token = result.get("refresh_token") or (result.get("session") or {}).get(
        "refresh_token"
    )

    if not user_id:
        raise ApiError("Registration failed.", code="registration_failed")

    # Mirror to app users table (may already exist via DB trigger)
    try:
        client.db_insert(
            "users",
            data={
                "id": user_id,
                "email": email,
                "role": role,
                "full_name": full_name or None,
            },
            use_service_role=True,
        )
    except Exception:
        pass  # Row may already exist via DB trigger

    # For departments: create a departments row starting as "pending"
    dept_data = None
    if role == "department":
        org_name = (body.get("organization_name") or "").strip()
        dept_type = (body.get("department_type") or "other").strip()
        contact_number = (body.get("contact_number") or "").strip()
        address = (body.get("address") or "").strip()
        area_of_responsibility = (body.get("area_of_responsibility") or "").strip()

        if not org_name:
            raise ApiError(
                "Organization name is required for department registration.",
                code="validation_error",
            )

        try:
            rows = client.db_insert(
                "departments",
                data={
                    "user_id": user_id,
                    "name": org_name,
                    "type": dept_type,
                    "contact_number": contact_number or None,
                    "address": address or None,
                    "area_of_responsibility": area_of_responsibility or None,
                    "verification_status": "pending",
                },
                use_service_role=True,
            )
            dept_data = rows[0] if rows else None
        except Exception:
            pass

    return (
        jsonify(
            {
                "user": {
                    "id": user_id,
                    "email": email,
                    "role": role,
                    "full_name": full_name or None,
                },
                "department": dept_data,
                "access_token": access_token,
                "refresh_token": refresh_token,
                "offline_verification_token": _issue_offline_token(
                    user_id=user_id,
                    role=role,
                    department=dept_data,
                ),
            }
        ),
        HTTPStatus.CREATED,
    )


@blueprint.post("/login")
def login():
    """Authenticate and return tokens + profile + department info."""
    body = request.get_json(silent=True) or {}
    email = (body.get("email") or "").strip()
    password = body.get("password") or ""

    if not email or not password:
        raise ApiError("Email and password are required.", code="validation_error")

    _require_supabase_auth_config()
    client = current_app.extensions["supabase_client"]
    result = client.sign_in(email=email, password=password)

    if "error" in result:
        raise ApiError(
            "Invalid email or password.",
            code="invalid_credentials",
            status_code=HTTPStatus.UNAUTHORIZED,
        )

    access_token = result.get("access_token", "")
    user_payload = result.get("user", {})
    user_id = user_payload.get("id", "")
    user_email = user_payload.get("email", email)

    # Role priority: app_metadata > user_metadata > users table
    role = user_payload.get("app_metadata", {}).get("role") or user_payload.get(
        "user_metadata", {}
    ).get("role")

    # Fetch app-level profile for extra fields (full_name, phone, etc.)
    profile = None
    try:
        rows = client.db_query(
            "users",
            params={"select": "*", "id": f"eq.{user_id}"},
            use_service_role=True,
        )
        if rows:
            profile = rows[0]
            role = role or profile.get("role")
    except Exception:
        pass

    # Eagerly load department info so the client has verification status on login
    department = None
    if role == "department":
        try:
            dept_rows = client.db_query(
                "departments",
                params={"select": "*", "user_id": f"eq.{user_id}"},
                use_service_role=True,
            )
            if dept_rows:
                department = dept_rows[0]
        except Exception:
            pass

    return jsonify(
        {
            "access_token": access_token,
            "refresh_token": result.get("refresh_token", ""),
            "user": {
                "id": user_id,
                "email": user_email,
                "role": role,
                "full_name": (profile or {}).get("full_name"),
                "phone": (profile or {}).get("phone"),
                "avatar_url": (profile or {}).get("avatar_url"),
            },
            "department": department,
            "offline_verification_token": _issue_offline_token(
                user_id=user_id,
                role=role,
                department=department,
            ),
        }
    )


@blueprint.post("/refresh")
def refresh():
    body = request.get_json(silent=True) or {}
    refresh_token = (body.get("refresh_token") or "").strip()
    if not refresh_token:
        raise ApiError("Refresh token is required.", code="validation_error")

    _require_supabase_auth_config()
    client = current_app.extensions["supabase_client"]
    result = client.refresh_session(refresh_token=refresh_token)

    if "error" in result:
        raise ApiError(
            "Session refresh failed.",
            code="invalid_refresh_token",
            status_code=HTTPStatus.UNAUTHORIZED,
        )

    access_token = result.get("access_token", "")
    next_refresh_token = result.get("refresh_token", refresh_token)
    user_payload = result.get("user", {})
    user_id = user_payload.get("id", "")
    user_email = user_payload.get("email", "")

    role = user_payload.get("app_metadata", {}).get("role") or user_payload.get(
        "user_metadata", {}
    ).get("role")

    profile = None
    try:
        rows = client.db_query(
            "users",
            params={"select": "*", "id": f"eq.{user_id}"},
            use_service_role=True,
        )
        if rows:
            profile = rows[0]
            role = role or profile.get("role")
    except Exception:
        pass

    department = None
    if role == "department":
        try:
            dept_rows = client.db_query(
                "departments",
                params={"select": "*", "user_id": f"eq.{user_id}"},
                use_service_role=True,
            )
            if dept_rows:
                department = dept_rows[0]
        except Exception:
            pass

    return jsonify(
        {
            "access_token": access_token,
            "refresh_token": next_refresh_token,
            "user": {
                "id": user_id,
                "email": user_email,
                "role": role,
                "full_name": (profile or {}).get("full_name"),
                "phone": (profile or {}).get("phone"),
                "avatar_url": (profile or {}).get("avatar_url"),
            },
            "department": department,
            "offline_verification_token": _issue_offline_token(
                user_id=user_id,
                role=role,
                department=department,
            ),
        }
    )


@blueprint.post("/logout")
@require_auth()
def logout():
    """Invalidate the Supabase session server-side."""
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    client = current_app.extensions["supabase_client"]
    client.sign_out(token)
    return jsonify({"message": "Logged out successfully."}), HTTPStatus.OK


@blueprint.get("/me")
@require_auth()
def me():
    """Return current user profile + department info. Used for session restore on reload."""
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()

    # Fetch app-level profile
    profile = None
    try:
        rows = client.db_query(
            "users",
            params={"select": "*", "id": f"eq.{user.id}"},
            token=token,
        )
        if rows:
            profile = rows[0]
    except Exception:
        pass

    # Load department info if applicable
    department = None
    if user.role == "department":
        try:
            dept_rows = client.db_query(
                "departments",
                params={"select": "*", "user_id": f"eq.{user.id}"},
                token=token,
            )
            if dept_rows:
                department = dept_rows[0]
        except Exception:
            pass

    return jsonify(
        {
            "user": {
                "id": user.id,
                "email": user.email,
                "role": user.role,
                "full_name": (profile or {}).get("full_name"),
                "phone": (profile or {}).get("phone"),
                "avatar_url": (profile or {}).get("avatar_url"),
            },
            "department": department,
            "offline_verification_token": _issue_offline_token(
                user_id=user.id,
                role=user.role,
                department=department,
            ),
        }
    )



