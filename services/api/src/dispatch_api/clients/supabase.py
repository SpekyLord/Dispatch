from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx

from dispatch_api.config import Settings


@dataclass(slots=True)
class SupabaseUser:
    id: str
    email: str
    role: str | None


class SupabaseClient:
    def __init__(self, settings: Settings, *, timeout: float = 10.0) -> None:
        self.settings = settings
        self._http_client = httpx.Client(timeout=timeout)

    def check_readiness(self) -> tuple[bool, dict[str, Any]]:
        missing_keys = self.settings.missing_supabase_keys
        if missing_keys:
            return False, {"missing_env": missing_keys}

        response = self._http_client.get(
            f"{self.settings.supabase_url}/auth/v1/settings",
            headers={
                "apikey": self.settings.supabase_anon_key or "",
            },
        )

        return response.is_success, {
            "status_code": response.status_code,
            "target": "supabase-auth-settings",
        }

    def get_user(self, token: str) -> SupabaseUser | None:
        if not token or self.settings.missing_supabase_keys:
            return None

        response = self._http_client.get(
            f"{self.settings.supabase_url}/auth/v1/user",
            headers={
                "apikey": self.settings.supabase_anon_key or "",
                "Authorization": f"Bearer {token}",
            },
        )

        if response.status_code == 401:
            return None

        response.raise_for_status()
        payload = response.json()
        role = (
            payload.get("app_metadata", {}).get("role")
            or payload.get("user_metadata", {}).get("role")
            or self._fetch_user_role(token=token, user_id=payload["id"])
        )

        return SupabaseUser(
            id=payload["id"],
            email=payload.get("email", ""),
            role=role,
        )

    def _fetch_user_role(self, *, token: str, user_id: str) -> str | None:
        response = self._http_client.get(
            f"{self.settings.supabase_url}/rest/v1/users",
            params={"select": "role", "id": f"eq.{user_id}"},
            headers={
                "apikey": self.settings.supabase_anon_key or "",
                "Authorization": f"Bearer {token}",
            },
        )

        if not response.is_success:
            return None

        payload = response.json()
        if not payload:
            return None
        return payload[0].get("role")
