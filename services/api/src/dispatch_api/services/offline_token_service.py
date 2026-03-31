from __future__ import annotations

import base64
import hashlib
import hmac
import json
from datetime import UTC, datetime, timedelta
from typing import Any

from dispatch_api.errors import ApiError


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _b64url_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode(f"{value}{padding}")


class OfflineTokenService:
    """Issues compact HMAC tokens that keep mesh author claims usable offline."""

    def __init__(self, *, secret: str, ttl_days: int = 30) -> None:
        self.secret = secret.encode()
        self.ttl_days = ttl_days

    def issue_token(
        self,
        *,
        user_id: str,
        role: str,
        department_id: str | None = None,
    ) -> str:
        now = datetime.now(tz=UTC)
        payload = {
            "sub": user_id,
            "role": role,
            "department_id": department_id,
            "kind": "mesh_offline_token",
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(days=self.ttl_days)).timestamp()),
        }
        header = {"alg": "HS256", "typ": "DOT"}
        signing_input = ".".join(
            (
                _b64url_encode(json.dumps(header, separators=(",", ":")).encode()),
                _b64url_encode(json.dumps(payload, separators=(",", ":")).encode()),
            )
        )
        signature = hmac.new(
            self.secret,
            signing_input.encode(),
            hashlib.sha256,
        ).digest()
        return f"{signing_input}.{_b64url_encode(signature)}"

    def validate_token(
        self,
        token: str,
        *,
        expected_role: str | None = None,
        expected_department_id: str | None = None,
    ) -> dict[str, Any]:
        if not token:
            raise ApiError("Offline verification token is required.", code="token_missing")

        try:
            header_b64, payload_b64, signature_b64 = token.split(".", 2)
        except ValueError as exc:
            raise ApiError("Offline verification token is invalid.", code="token_invalid") from exc

        signing_input = f"{header_b64}.{payload_b64}"
        expected_signature = hmac.new(
            self.secret,
            signing_input.encode(),
            hashlib.sha256,
        ).digest()
        provided_signature = _b64url_decode(signature_b64)
        if not hmac.compare_digest(expected_signature, provided_signature):
            raise ApiError("Offline verification token is invalid.", code="token_invalid")

        try:
            payload = json.loads(_b64url_decode(payload_b64).decode())
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ApiError("Offline verification token is invalid.", code="token_invalid") from exc

        exp = payload.get("exp")
        if not isinstance(exp, int):
            raise ApiError("Offline verification token is invalid.", code="token_invalid")
        if datetime.now(tz=UTC).timestamp() >= exp:
            raise ApiError("Offline verification token has expired.", code="token_expired")

        if payload.get("kind") != "mesh_offline_token":
            raise ApiError("Offline verification token is invalid.", code="token_invalid")

        if expected_role and payload.get("role") != expected_role:
            raise ApiError("Offline verification token role mismatch.", code="token_invalid")

        if expected_department_id and payload.get("department_id") != expected_department_id:
            raise ApiError(
                "Offline verification token department mismatch.",
                code="token_invalid",
            )

        return payload
