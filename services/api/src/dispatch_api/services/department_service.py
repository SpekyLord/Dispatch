from __future__ import annotations

from typing import Any

from dispatch_api.errors import ApiError


class DepartmentService:
    def __init__(self, client) -> None:
        self.client = client

    def get_department_for_user(self, user_id: str) -> dict[str, Any]:
        rows = self.client.db_query(
            "departments",
            params={"select": "*", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Department profile not found.", code="not_found", status_code=404)
        return rows[0]

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
