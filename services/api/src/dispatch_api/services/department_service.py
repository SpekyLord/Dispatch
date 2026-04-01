from __future__ import annotations

from typing import Any

import httpx

from dispatch_api.errors import ApiError


class DepartmentService:
    def __init__(self, client) -> None:
        self.client = client

    def get_department_for_user(self, user_id: str) -> dict[str, Any]:
        rows: list[dict[str, Any]] = []
        base_rows = self.client.db_query(
            "departments",
            params={"select": "*", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        try:
            rows = self.client.db_query(
                "department_profile_summary",
                params={"select": "*", "user_id": f"eq.{user_id}"},
                use_service_role=True,
            )
        except httpx.HTTPStatusError:
            rows = []

        if not rows:
            rows = base_rows
        if not rows:
            raise ApiError("Department profile not found.", code="not_found", status_code=404)

        department = {**(base_rows[0] if base_rows else {}), **rows[0]}
        department.setdefault("post_count", self._post_count_for_user(user_id))
        return department

    def require_verified_department(self, department: dict[str, Any]) -> None:
        if department.get("verification_status") != "approved":
            raise ApiError(
                "Your department has not been verified yet. Contact the municipality for approval.",
                code="department_not_verified",
                status_code=403,
            )

    def list_approved_departments(self) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "departments",
            params={"select": "*", "order": "name.asc"},
            use_service_role=True,
        )
        return [row for row in rows if row.get("verification_status") == "approved"]

    def list_public_departments(self) -> list[dict[str, Any]]:
        base_rows = self.list_approved_departments()
        rows_by_user_id = {str(row.get("user_id") or ""): row for row in base_rows}

        try:
            summary_rows = self.client.db_query(
                "department_profile_summary",
                params={"select": "*", "order": "name.asc"},
                use_service_role=True,
            )
        except httpx.HTTPStatusError:
            summary_rows = []

        public_departments: list[dict[str, Any]] = []
        for row in summary_rows:
            user_id = str(row.get("user_id") or "")
            base = rows_by_user_id.get(user_id)
            if not base:
                continue
            department = {**base, **row}
            department.setdefault("post_count", self._post_count_for_user(user_id))
            public_departments.append(department)

        if public_departments:
            return public_departments

        for row in base_rows:
            department = {**row}
            user_id = str(department.get("user_id") or "")
            department.setdefault("post_count", self._post_count_for_user(user_id))
            public_departments.append(department)
        return public_departments

    def _post_count_for_user(self, user_id: str) -> int:
        rows = self.client.db_query(
            "department_feed_posts",
            params={"select": "id", "uploader": f"eq.{user_id}"},
            use_service_role=True,
        )
        return len(rows)
