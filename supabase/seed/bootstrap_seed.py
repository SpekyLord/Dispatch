from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass


@dataclass(frozen=True)
class SeedUser:
    email: str
    password: str
    full_name: str
    role: str
    is_verified: bool
    department_name: str | None = None
    department_type: str | None = None


class SupabaseSeedClient:
    def __init__(self, url: str, service_role_key: str) -> None:
        self.url = url.rstrip("/")
        self.service_role_key = service_role_key

    def create_auth_user(self, seed_user: SeedUser) -> dict:
        payload = {
            "email": seed_user.email,
            "password": seed_user.password,
            "email_confirm": True,
            "app_metadata": {"role": seed_user.role},
            "user_metadata": {"role": seed_user.role, "full_name": seed_user.full_name},
        }
        return self._request("POST", "/auth/v1/admin/users", payload)

    def find_user_row_by_email(self, email: str) -> dict | None:
        encoded_email = urllib.parse.quote(email, safe="")
        rows = self._request(
            "GET",
            f"/rest/v1/users?select=id,email,role&email=eq.{encoded_email}",
        )
        if not rows:
            return None
        return rows[0]

    def upsert_table_rows(
        self,
        table: str,
        rows: list[dict],
        *,
        on_conflict: str | None = None,
    ) -> list[dict]:
        headers = {
            "Prefer": "resolution=merge-duplicates,return=representation",
        }
        path = f"/rest/v1/{table}"
        if on_conflict:
            encoded_conflict = urllib.parse.quote(on_conflict, safe=",")
            path = f"{path}?on_conflict={encoded_conflict}"
        return self._request("POST", path, rows, extra_headers=headers)

    def _request(
        self,
        method: str,
        path: str,
        payload: dict | list | None = None,
        *,
        extra_headers: dict[str, str] | None = None,
    ):
        request = urllib.request.Request(
          f"{self.url}{path}",
          method=method,
          headers={
              "apikey": self.service_role_key,
              "Authorization": f"Bearer {self.service_role_key}",
              "Content-Type": "application/json",
              **(extra_headers or {}),
          },
          data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        )

        try:
            with urllib.request.urlopen(request) as response:
                body = response.read().decode("utf-8")
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as error:
            message = error.read().decode("utf-8")
            raise RuntimeError(f"Supabase request failed ({error.code}): {message}") from error


def main() -> None:
    supabase_url = os.environ.get("SUPABASE_URL")
    service_role_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    default_password = os.environ.get("SEED_DEFAULT_PASSWORD", "Dispatch123!")

    if not supabase_url or not service_role_key:
        raise SystemExit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.")

    seed_users = [
        SeedUser(
            email="municipality.admin@dispatch.local",
            password=default_password,
            full_name="Municipality Administrator",
            role="municipality",
            is_verified=True,
        ),
        SeedUser(
            email="citizen.demo@dispatch.local",
            password=default_password,
            full_name="Demo Citizen",
            role="citizen",
            is_verified=False,
        ),
        SeedUser(
            email="fire.station@dispatch.local",
            password=default_password,
            full_name="BFP Station Commander",
            role="department",
            is_verified=True,
            department_name="BFP Central Station",
            department_type="fire",
        ),
        SeedUser(
            email="police.station@dispatch.local",
            password=default_password,
            full_name="PNP Operations Desk",
            role="department",
            is_verified=True,
            department_name="PNP Central Precinct",
            department_type="police",
        ),
        SeedUser(
            email="medical.response@dispatch.local",
            password=default_password,
            full_name="Medical Response Lead",
            role="department",
            is_verified=True,
            department_name="City Medical Rescue Unit",
            department_type="medical",
        ),
        SeedUser(
            email="mdrrmo.ops@dispatch.local",
            password=default_password,
            full_name="MDRRMO Operations Lead",
            role="department",
            is_verified=True,
            department_name="Municipal DRRMO",
            department_type="disaster",
        ),
    ]

    client = SupabaseSeedClient(supabase_url, service_role_key)
    created_users = []
    for seed_user in seed_users:
        try:
            created_users.append(client.create_auth_user(seed_user))
        except RuntimeError as error:
            error_message = str(error).casefold()
            if "already" not in error_message:
                raise

            existing_user = client.find_user_row_by_email(seed_user.email)
            if not existing_user:
                raise RuntimeError(
                    f"Seed user {seed_user.email} already exists in auth, but no matching public.users row was found."
                ) from error

            created_users.append(existing_user)
    municipality_id = created_users[0]["id"]

    user_rows = []
    department_rows = []
    for seed_user, auth_user in zip(seed_users, created_users, strict=True):
        user_rows.append(
            {
                "id": auth_user["id"],
                "email": seed_user.email,
                "role": seed_user.role,
                "full_name": seed_user.full_name,
                "is_verified": seed_user.is_verified,
            }
        )

        if seed_user.role == "department":
            department_rows.append(
                {
                    "user_id": auth_user["id"],
                    "name": seed_user.department_name,
                    "type": seed_user.department_type,
                    "description": "Phase 0 seeded department.",
                    "contact_number": "+63 000 000 0000",
                    "address": "Municipal operations center",
                    "area_of_responsibility": "Phase 0 demo coverage",
                    "verification_status": "approved",
                    "verified_by": municipality_id,
                }
            )

    client.upsert_table_rows("users", user_rows, on_conflict="id")
    client.upsert_table_rows("departments", department_rows, on_conflict="user_id")

    print("Seed bootstrap complete.")


if __name__ == "__main__":
    main()
