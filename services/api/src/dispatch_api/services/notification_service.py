from __future__ import annotations

from datetime import UTC, datetime
from typing import Any


def _utc_now_iso() -> str:
    return datetime.now(tz=UTC).isoformat()


class NotificationService:
    def __init__(self, client) -> None:
        self.client = client

    def list_for_user(self, user_id: str) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "notifications",
            params={"select": "*", "order": "created_at.desc"},
            use_service_role=True,
        )
        user_rows = [row for row in rows if row.get("user_id") == user_id]
        return sorted(
            user_rows,
            key=lambda row: (
                row.get("is_read", False),
                row.get("created_at") or "",
            ),
        )

    def mark_read(self, *, user_id: str, notification_id: str) -> dict[str, Any] | None:
        rows = self.client.db_query(
            "notifications",
            params={"select": "*", "id": f"eq.{notification_id}"},
            use_service_role=True,
        )
        notification = next((row for row in rows if row.get("user_id") == user_id), None)
        if notification is None:
            return None

        updated = self.client.db_update(
            "notifications",
            data={"is_read": True, "read_at": _utc_now_iso()},
            params={"id": f"eq.{notification_id}", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        return updated[0] if updated else None

    def mark_all_read(self, *, user_id: str) -> int:
        updated_count = 0
        for notification in self.list_for_user(user_id):
            if notification.get("is_read"):
                continue
            updated = self.mark_read(user_id=user_id, notification_id=notification["id"])
            if updated is not None:
                updated_count += 1
        return updated_count

    def create_notification(
        self,
        *,
        user_id: str,
        notification_type: str,
        title: str,
        message: str,
        reference_id: str | None = None,
        reference_type: str | None = None,
    ) -> None:
        self.client.db_insert(
            "notifications",
            data={
                "user_id": user_id,
                "type": notification_type,
                "title": title,
                "message": message,
                "reference_id": reference_id,
                "reference_type": reference_type,
            },
            use_service_role=True,
            return_repr=False,
        )

    def create_many(self, notifications: list[dict[str, Any]]) -> None:
        if not notifications:
            return

        self.client.db_insert(
            "notifications",
            data=notifications,
            use_service_role=True,
            return_repr=False,
        )

    def notify_relevant_departments(
        self,
        *,
        report: dict[str, Any],
        departments: list[dict[str, Any]],
        message: str | None = None,
    ) -> None:
        title = f"New {self._labelize(report.get('category', 'other'))} report"
        notifications = [
            {
                "user_id": department["user_id"],
                "type": "new_report",
                "title": title,
                "message": message or "A new incident report is visible to your department.",
                "reference_id": report["id"],
                "reference_type": "report",
            }
            for department in departments
        ]
        self.create_many(notifications)

    def notify_report_escalated(
        self, *, report: dict[str, Any], municipality_users: list[dict[str, Any]]
    ) -> None:
        category_label = self._labelize(report.get("category", "other"))
        notifications = [
            {
                "user_id": user["id"],
                "type": "new_report",
                "title": "Escalated incident requires attention",
                "message": f"The {category_label} report was escalated.",
                "reference_id": report["id"],
                "reference_type": "report",
            }
            for user in municipality_users
        ]
        self.create_many(notifications)

    def notify_reporter_status_update(
        self,
        *,
        report: dict[str, Any],
        message: str,
    ) -> None:
        self.create_notification(
            user_id=report["reporter_id"],
            notification_type="report_update",
            title="Report updated",
            message=message,
            reference_id=report["id"],
            reference_type="report",
        )

    def notify_verification_decision(self, *, department: dict[str, Any]) -> None:
        status = department.get("verification_status", "pending")
        message = "Your department verification request was updated."
        if status == "approved":
            message = "Your department was approved and can now access responder tools."
        elif status == "rejected":
            reason = department.get("rejection_reason")
            message = "Your department verification request was rejected."
            if reason:
                message = f"{message} Reason: {reason}"

        self.create_notification(
            user_id=department["user_id"],
            notification_type="verification_decision",
            title="Department verification updated",
            message=message,
            reference_id=department["id"],
            reference_type="department",
        )

    def notify_citizens_about_post(
        self, *, post: dict[str, Any], citizen_users: list[dict[str, Any]]
    ) -> None:
        notifications = [
            {
                "user_id": user["id"],
                "type": "announcement",
                "title": post["title"],
                "message": "A verified department published a new announcement.",
                "reference_id": post["id"],
                "reference_type": "post",
            }
            for user in citizen_users
        ]
        self.create_many(notifications)

    def list_users_by_role(self, role: str) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "users",
            params={"select": "*", "order": "created_at.asc"},
            use_service_role=True,
        )
        return [row for row in rows if row.get("role") == role]

    def _labelize(self, value: str) -> str:
        return value.replace("_", " ").strip().title()
