from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from dispatch_api.errors import ApiError

VALID_DAMAGE_LEVELS = {"minor", "moderate", "severe", "critical"}


class AssessmentService:
    def __init__(self, client) -> None:
        self.client = client

    # -- create a damage assessment for a department --
    def create_assessment(
        self,
        *,
        department_id: str,
        report_id: str | None = None,
        affected_area: str,
        damage_level: str,
        estimated_casualties: int = 0,
        displaced_persons: int = 0,
        location: str = "",
        description: str = "",
        image_urls: list[str] | None = None,
    ) -> dict[str, Any]:
        if damage_level not in VALID_DAMAGE_LEVELS:
            raise ApiError(
                f"damage_level must be one of: {', '.join(sorted(VALID_DAMAGE_LEVELS))}.",
                code="validation_error",
            )
        if not affected_area:
            raise ApiError("affected_area is required.", code="validation_error")

        data: dict[str, Any] = {
            "department_id": department_id,
            "affected_area": affected_area,
            "damage_level": damage_level,
            "estimated_casualties": estimated_casualties,
            "displaced_persons": displaced_persons,
            "location": location,
            "description": description,
            "image_urls": image_urls or [],
            "created_at": datetime.now(tz=UTC).isoformat(),
        }
        if report_id:
            data["report_id"] = report_id

        rows = self.client.db_insert("damage_assessments", data=data, use_service_role=True)
        if not rows:
            raise ApiError("Failed to create assessment.", code="insert_failed")
        return rows[0]

    # -- list assessments belonging to a specific department --
    def list_department_assessments(self, department_id: str) -> list[dict[str, Any]]:
        return self.client.db_query(
            "damage_assessments",
            params={
                "select": "*",
                "department_id": f"eq.{department_id}",
                "order": "created_at.desc",
            },
            use_service_role=True,
        )

    # -- municipality view: all assessments --
    def list_all_assessments(self) -> list[dict[str, Any]]:
        return self.client.db_query(
            "damage_assessments",
            params={"select": "*", "order": "created_at.desc"},
            use_service_role=True,
        )
