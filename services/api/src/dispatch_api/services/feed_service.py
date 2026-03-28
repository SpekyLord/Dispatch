from __future__ import annotations

from http import HTTPStatus
from typing import Any

from dispatch_api.errors import ApiError
from dispatch_api.services.notification_service import NotificationService

VALID_POST_CATEGORIES = {
    "alert",
    "warning",
    "safety_tip",
    "update",
    "situational_report",
}


class FeedService:
    def __init__(self, client, notification_service: NotificationService) -> None:
        self.client = client
        self.notification_service = notification_service

    def create_post(
        self,
        *,
        department: dict[str, Any],
        author_id: str,
        title: str,
        content: str,
        category: str,
        image_urls: list[str] | None = None,
        is_pinned: bool = False,
    ) -> dict[str, Any]:
        if not title:
            raise ApiError("Title is required.", code="validation_error")
        if not content:
            raise ApiError("Content is required.", code="validation_error")
        if category not in VALID_POST_CATEGORIES:
            raise ApiError(
                f"Category must be one of: {', '.join(sorted(VALID_POST_CATEGORIES))}.",
                code="validation_error",
            )

        rows = self.client.db_insert(
            "posts",
            data={
                "department_id": department["id"],
                "author_id": author_id,
                "title": title,
                "content": content,
                "category": category,
                "image_urls": image_urls or [],
                "is_pinned": is_pinned,
            },
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Failed to create post.", code="create_failed")

        post = rows[0]
        citizens = self.notification_service.list_users_by_role("citizen")
        self.notification_service.notify_citizens_about_post(post=post, citizen_users=citizens)
        return self._attach_department(post)

    def list_posts(self, *, category: str | None = None) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "posts",
            params={"select": "*", "order": "created_at.desc"},
            use_service_role=True,
        )
        if category:
            rows = [row for row in rows if row.get("category") == category]
        posts = [self._attach_department(row) for row in rows]
        return sorted(
            posts,
            key=lambda row: (
                not row.get("is_pinned", False),
                row.get("created_at") or "",
            ),
        )

    def get_post(self, post_id: str) -> dict[str, Any]:
        rows = self.client.db_query(
            "posts",
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)
        return self._attach_department(rows[0])

    def _attach_department(self, post: dict[str, Any]) -> dict[str, Any]:
        departments = self.client.db_query(
            "departments",
            params={"select": "*", "id": f"eq.{post['department_id']}"},
            use_service_role=True,
        )
        department = departments[0] if departments else None
        return {
            **post,
            "department": {
                "id": department.get("id"),
                "name": department.get("name"),
                "type": department.get("type"),
            }
            if department
            else None,
        }
