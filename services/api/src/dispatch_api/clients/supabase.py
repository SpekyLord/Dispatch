from __future__ import annotations

from dataclasses import dataclass
from typing import Any
from urllib.parse import quote

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

    # ── Readiness ──────────────────────────────────────────────

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

    # ── Auth operations ────────────────────────────────────────

    def sign_up(
        self, *, email: str, password: str, user_metadata: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        body: dict[str, Any] = {"email": email, "password": password}
        if user_metadata:
            body["data"] = user_metadata
        response = self._http_client.post(
            f"{self.settings.supabase_url}/auth/v1/signup",
            headers=self._anon_headers(),
            json=body,
        )
        if not response.is_success:
            return {"error": response.json()}
        return response.json()

    def sign_in(self, *, email: str, password: str) -> dict[str, Any]:
        response = self._http_client.post(
            f"{self.settings.supabase_url}/auth/v1/token?grant_type=password",
            headers=self._anon_headers(),
            json={"email": email, "password": password},
        )
        if not response.is_success:
            return {"error": response.json()}
        return response.json()

    def refresh_session(self, *, refresh_token: str) -> dict[str, Any]:
        response = self._http_client.post(
            f"{self.settings.supabase_url}/auth/v1/token?grant_type=refresh_token",
            headers=self._anon_headers(),
            json={"refresh_token": refresh_token},
        )
        if not response.is_success:
            return {"error": response.json()}
        return response.json()

    def sign_out(self, token: str) -> bool:
        response = self._http_client.post(
            f"{self.settings.supabase_url}/auth/v1/logout",
            headers={
                "apikey": self.settings.supabase_anon_key or "",
                "Authorization": f"Bearer {token}",
            },
        )
        return response.is_success

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

        if response.status_code in (401, 403):
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

    def update_user_metadata(
        self, token: str, *, user_metadata: dict[str, Any]
    ) -> dict[str, Any] | None:
        response = self._http_client.put(
            f"{self.settings.supabase_url}/auth/v1/user",
            headers={
                "apikey": self.settings.supabase_anon_key or "",
                "Authorization": f"Bearer {token}",
            },
            json={"data": user_metadata},
        )
        if not response.is_success:
            return None
        return response.json()

    # ── Database (PostgREST) ───────────────────────────────────

    def db_query(
        self,
        table: str,
        *,
        token: str | None = None,
        params: dict[str, str] | None = None,
        use_service_role: bool = False,
    ) -> list[dict[str, Any]]:
        headers = self._service_headers() if use_service_role else self._bearer_headers(token or "")
        response = self._http_client.get(
            f"{self.settings.supabase_url}/rest/v1/{table}",
            params=params or {},
            headers=headers,
        )
        response.raise_for_status()
        return response.json()

    def db_insert(
        self,
        table: str,
        *,
        data: dict[str, Any] | list[dict[str, Any]],
        token: str | None = None,
        use_service_role: bool = False,
        return_repr: bool = True,
    ) -> list[dict[str, Any]]:
        headers = self._service_headers() if use_service_role else self._bearer_headers(token or "")
        if return_repr:
            headers["Prefer"] = "return=representation"
        response = self._http_client.post(
            f"{self.settings.supabase_url}/rest/v1/{table}",
            headers=headers,
            json=data,
        )
        response.raise_for_status()
        if return_repr:
            return response.json()
        return []

    def db_update(
        self,
        table: str,
        *,
        data: dict[str, Any],
        params: dict[str, str],
        token: str | None = None,
        use_service_role: bool = False,
        return_repr: bool = True,
    ) -> list[dict[str, Any]]:
        headers = self._service_headers() if use_service_role else self._bearer_headers(token or "")
        if return_repr:
            headers["Prefer"] = "return=representation"
        response = self._http_client.patch(
            f"{self.settings.supabase_url}/rest/v1/{table}",
            params=params,
            headers=headers,
            json=data,
        )
        response.raise_for_status()
        if return_repr:
            return response.json()
        return []

    def db_delete(
        self,
        table: str,
        *,
        params: dict[str, str],
        token: str | None = None,
        use_service_role: bool = False,
        return_repr: bool = True,
    ) -> list[dict[str, Any]]:
        headers = self._service_headers() if use_service_role else self._bearer_headers(token or "")
        if return_repr:
            headers["Prefer"] = "return=representation"
        response = self._http_client.delete(
            f"{self.settings.supabase_url}/rest/v1/{table}",
            params=params,
            headers=headers,
        )
        response.raise_for_status()
        if return_repr:
            return response.json()
        return []

    # ── Storage (direct upload) ────────────────────────────────

    def storage_upload(
        self,
        *,
        bucket: str,
        object_path: str,
        file_data: bytes,
        content_type: str,
    ) -> dict[str, Any]:
        response = self._http_client.post(
            f"{self.settings.supabase_url}/storage/v1/object/{bucket}/{object_path}",
            headers={
                "apikey": self.settings.supabase_service_role_key or "",
                "Authorization": f"Bearer {self.settings.supabase_service_role_key or ''}",
                "Content-Type": content_type,
            },
            content=file_data,
        )
        response.raise_for_status()
        return response.json()

    def storage_public_url(self, *, bucket: str, object_path: str) -> str:
        return f"{self.settings.supabase_url}/storage/v1/object/public/{bucket}/{object_path}"

    def storage_signed_url(
        self, *, bucket: str, object_path: str, expires_in: int = 3600
    ) -> str:
        encoded_path = quote(object_path, safe="/")
        response = self._http_client.post(
            f"{self.settings.supabase_url}/storage/v1/object/sign/{bucket}/{encoded_path}",
            headers=self._service_headers(),
            json={"expiresIn": expires_in},
        )
        response.raise_for_status()
        payload = response.json()
        signed_path = (
            payload.get("signedURL")
            or payload.get("signedUrl")
            or payload.get("url")
        )
        if not signed_path:
            raise ValueError("Signed storage URL was not returned by Supabase.")
        if signed_path.startswith("http://") or signed_path.startswith("https://"):
            return signed_path
        if signed_path.startswith("/storage/"):
            return f"{self.settings.supabase_url}{signed_path}"
        if signed_path.startswith("/"):
            return f"{self.settings.supabase_url}/storage/v1{signed_path}"
        return f"{self.settings.supabase_url}/storage/v1/{signed_path.lstrip('/')}"

    # ── Helpers ────────────────────────────────────────────────

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

    def _anon_headers(self) -> dict[str, str]:
        return {
            "apikey": self.settings.supabase_anon_key or "",
            "Content-Type": "application/json",
        }

    def _bearer_headers(self, token: str) -> dict[str, str]:
        return {
            "apikey": self.settings.supabase_anon_key or "",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }

    def _service_headers(self) -> dict[str, str]:
        return {
            "apikey": self.settings.supabase_service_role_key or "",
            "Authorization": f"Bearer {self.settings.supabase_service_role_key or ''}",
            "Content-Type": "application/json",
        }
