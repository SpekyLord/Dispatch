from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from functools import wraps
from http import HTTPStatus
from typing import ParamSpec, TypeVar, cast

from flask import current_app, g, request

from dispatch_api.errors import ApiError

P = ParamSpec("P")
R = TypeVar("R")


@dataclass(slots=True)
class AuthenticatedUser:
    id: str
    email: str
    role: str | None


def load_current_user() -> None:
    g.current_user = None

    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return

    token = header.removeprefix("Bearer ").strip()
    if not token:
        return

    client = current_app.extensions["supabase_client"]
    user = client.get_user(token)
    if user is None:
        return

    g.current_user = AuthenticatedUser(id=user.id, email=user.email, role=user.role)


def require_auth() -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorator(view: Callable[P, R]) -> Callable[P, R]:
        @wraps(view)
        def wrapped(*args: P.args, **kwargs: P.kwargs) -> R:
            if getattr(g, "current_user", None) is None:
                raise ApiError(
                    "Authentication is required to access this resource.",
                    status_code=HTTPStatus.UNAUTHORIZED,
                    code="authentication_required",
                )
            return view(*args, **kwargs)

        return wrapped

    return decorator


def require_role(*allowed_roles: str) -> Callable[[Callable[P, R]], Callable[P, R]]:
    def decorator(view: Callable[P, R]) -> Callable[P, R]:
        @wraps(view)
        def wrapped(*args: P.args, **kwargs: P.kwargs) -> R:
            user = cast(AuthenticatedUser | None, getattr(g, "current_user", None))
            if user is None:
                raise ApiError(
                    "Authentication is required to access this resource.",
                    status_code=HTTPStatus.UNAUTHORIZED,
                    code="authentication_required",
                )
            if user.role not in allowed_roles:
                raise ApiError(
                    "You do not have permission to access this resource.",
                    status_code=HTTPStatus.FORBIDDEN,
                    code="forbidden",
                    details={"allowed_roles": list(allowed_roles), "actual_role": user.role},
                )
            return view(*args, **kwargs)

        return wrapped

    return decorator


def get_current_user() -> AuthenticatedUser | None:
    return cast(AuthenticatedUser | None, getattr(g, "current_user", None))
