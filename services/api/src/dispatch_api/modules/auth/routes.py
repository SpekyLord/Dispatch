from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.auth import blueprint

VALID_ROLES = {"citizen", "department"}


@blueprint.post("/register")
def register():
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

    client = current_app.extensions["supabase_client"]

    # Sign up via Supabase Auth
    result = client.sign_up(
        email=email,
        password=password,
        user_metadata={"role": role, "full_name": full_name},
    )

    if "error" in result:
        err = result["error"]
        msg = err.get("msg") or err.get("message") or "Registration failed."
        raise ApiError(msg, code="registration_failed", status_code=HTTPStatus.BAD_REQUEST)

    auth_user = result.get("user") or result
    user_id = auth_user.get("id")
    access_token = result.get("access_token") or (result.get("session") or {}).get("access_token")

    if not user_id:
        raise ApiError("Registration failed.", code="registration_failed")

    # Create the application-level user row
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
        pass  # Row may already exist via trigger

    # If the role is department, also create a department record
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
            }
        ),
        HTTPStatus.CREATED,
    )


@blueprint.post("/login")
def login():
    body = request.get_json(silent=True) or {}
    email = (body.get("email") or "").strip()
    password = body.get("password") or ""

    if not email or not password:
        raise ApiError("Email and password are required.", code="validation_error")

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

    role = user_payload.get("app_metadata", {}).get("role") or user_payload.get(
        "user_metadata", {}
    ).get("role")

    # Fetch application profile
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

    # Fetch department info if department role
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
        }
    )


@blueprint.post("/logout")
@require_auth()
def logout():
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    client = current_app.extensions["supabase_client"]
    client.sign_out(token)
    return jsonify({"message": "Logged out successfully."}), HTTPStatus.OK


@blueprint.get("/me")
@require_auth()
def me():
    user = get_current_user()
    client = current_app.extensions["supabase_client"]
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()

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
        }
    )
