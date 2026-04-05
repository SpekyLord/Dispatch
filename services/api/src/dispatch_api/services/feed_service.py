from __future__ import annotations

from http import HTTPStatus
from typing import Any

import httpx

from dispatch_api.errors import ApiError
from dispatch_api.services.assessment_service import VALID_DAMAGE_LEVELS
from dispatch_api.services.notification_service import NotificationService

VALID_POST_CATEGORIES = {
    "alert",
    "warning",
    "safety_tip",
    "update",
    "situational_report",
}
VALID_POST_KINDS = {"standard", "assessment"}

FEED_POSTS_TABLE = "department_feed_posts"
FEED_STORAGE_TABLE = "department_feed_storage"
FEED_COMMENTS_TABLE = "department_feed_comment"
FEED_REACTIONS_TABLE = "department_feed_reactions"


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
        location: str,
        post_kind: str = "standard",
        assessment_details: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if not title:
            raise ApiError("Title is required.", code="validation_error")
        if not content:
            raise ApiError("Content is required.", code="validation_error")
        if not location:
            raise ApiError("Location is required.", code="validation_error")
        if category not in VALID_POST_CATEGORIES:
            raise ApiError(
                f"Category must be one of: {', '.join(sorted(VALID_POST_CATEGORIES))}.",
                code="validation_error",
            )
        if post_kind not in VALID_POST_KINDS:
            raise ApiError(
                f"post_kind must be one of: {', '.join(sorted(VALID_POST_KINDS))}.",
                code="validation_error",
            )

        normalized_assessment_details = self._normalize_assessment_details(
            post_kind=post_kind,
            assessment_details=assessment_details,
        )

        try:
            rows = self.client.db_insert(
                FEED_POSTS_TABLE,
                data={
                    "uploader": author_id,
                    "title": title,
                    "content": content,
                    "category": category,
                    "location": location,
                    "post_kind": post_kind,
                    "assessment_details": normalized_assessment_details,
                },
                use_service_role=True,
            )
        except httpx.HTTPStatusError as error:
            self._raise_schema_migration_error(error)
        if not rows:
            raise ApiError("Failed to create post.", code="create_failed")

        post = rows[0]
        citizens = self.notification_service.list_users_by_role("citizen")
        self.notification_service.notify_citizens_about_post(post=post, citizen_users=citizens)
        return self._serialize_post(post=post, department=department)

    def attach_assets(
        self,
        *,
        post_id: Any,
        photo_urls: list[str],
        attachment_urls: list[str],
    ) -> None:
        rows_to_insert = [
            {"id": post_id, "photos": photo_url, "attachments": None} for photo_url in photo_urls
        ] + [
            {"id": post_id, "photos": None, "attachments": attachment_url}
            for attachment_url in attachment_urls
        ]
        if not rows_to_insert:
            return
        self.client.db_insert(
            FEED_STORAGE_TABLE,
            data=rows_to_insert,
            use_service_role=True,
            return_repr=False,
        )

    def list_comments(self, *, post_id: Any) -> list[dict[str, Any]]:
        self._require_post_exists(post_id)
        rows = self.client.db_query(
            FEED_COMMENTS_TABLE,
            params={"select": "*", "post_id": f"eq.{post_id}", "order": "created_at.asc"},
            use_service_role=True,
        )
        return [self._serialize_comment(row) for row in rows]

    def create_comment(
        self,
        *,
        post_id: Any,
        user_id: str,
        fallback_name: str,
        content: str,
    ) -> dict[str, Any]:
        self._require_post_exists(post_id)
        if not content:
            raise ApiError("Comment is required.", code="validation_error")

        rows = self.client.db_insert(
            FEED_COMMENTS_TABLE,
            data={
                "post_id": post_id,
                "user_id": user_id,
                "user_name": self._resolve_user_name(user_id=user_id, fallback_name=fallback_name),
                "comment": content,
            },
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Failed to create comment.", code="create_failed")
        return self._serialize_comment(rows[0])

    def toggle_reaction(self, *, post_id: Any, user_id: str) -> dict[str, Any]:
        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

        post = rows[0]
        existing_reaction_rows = self.client.db_query(
            FEED_REACTIONS_TABLE,
            params={"select": "*", "post_id": f"eq.{post_id}", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        liked_by_me = not existing_reaction_rows
        if existing_reaction_rows:
            self.client.db_delete(
                FEED_REACTIONS_TABLE,
                params={"post_id": f"eq.{post_id}", "user_id": f"eq.{user_id}"},
                use_service_role=True,
                return_repr=False,
            )
        else:
            self.client.db_insert(
                FEED_REACTIONS_TABLE,
                data={"post_id": post_id, "user_id": user_id},
                use_service_role=True,
                return_repr=False,
            )

        # Count actual reactions from the table to avoid race conditions
        # where concurrent requests read stale counts.
        reaction_rows = self.client.db_query(
            FEED_REACTIONS_TABLE,
            params={"select": "id", "post_id": f"eq.{post_id}"},
            use_service_role=True,
        )
        next_reaction = len(reaction_rows)
        updated_rows = self.client.db_update(
            FEED_POSTS_TABLE,
            data={"reaction": next_reaction},
            params={"id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not updated_rows:
            raise ApiError("Failed to update reaction.", code="update_failed")

        updated_post = updated_rows[0]
        department = self._department_for_uploader(updated_post.get("uploader"))
        assets = self._assets_for_post(updated_post.get("id"))
        comment_count = len(self.list_comments(post_id=updated_post.get("id")))
        return self._serialize_post(
            post=updated_post,
            department=department,
            assets=assets,
            comment_count=comment_count,
            liked_by_me=liked_by_me,
        )

    def delete_post(self, *, post_id: Any, author_id: str) -> None:
        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

        post = rows[0]
        if str(post.get("uploader")) != str(author_id):
            raise ApiError(
                "You can only delete your own post.",
                code="forbidden",
                status_code=HTTPStatus.FORBIDDEN,
            )

        self.client.db_delete(
            FEED_STORAGE_TABLE,
            params={"id": f"eq.{post_id}"},
            use_service_role=True,
            return_repr=False,
        )
        self.client.db_delete(
            FEED_COMMENTS_TABLE,
            params={"post_id": f"eq.{post_id}"},
            use_service_role=True,
            return_repr=False,
        )
        self.client.db_delete(
            FEED_REACTIONS_TABLE,
            params={"post_id": f"eq.{post_id}"},
            use_service_role=True,
            return_repr=False,
        )
        deleted_rows = self.client.db_delete(
            FEED_POSTS_TABLE,
            params={"id": f"eq.{post_id}", "uploader": f"eq.{author_id}"},
            use_service_role=True,
        )
        if not deleted_rows:
            raise ApiError("Failed to delete post.", code="delete_failed")

    def update_post(
        self,
        *,
        post_id: Any,
        author_id: str,
        title: str,
        content: str,
        category: str,
        location: str,
        post_kind: str = "standard",
        assessment_details: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        if not title:
            raise ApiError("Title is required.", code="validation_error")
        if not content:
            raise ApiError("Content is required.", code="validation_error")
        if not location:
            raise ApiError("Location is required.", code="validation_error")
        if category not in VALID_POST_CATEGORIES:
            raise ApiError(
                f"Category must be one of: {', '.join(sorted(VALID_POST_CATEGORIES))}.",
                code="validation_error",
            )
        if post_kind not in VALID_POST_KINDS:
            raise ApiError(
                f"post_kind must be one of: {', '.join(sorted(VALID_POST_KINDS))}.",
                code="validation_error",
            )

        normalized_assessment_details = self._normalize_assessment_details(
            post_kind=post_kind,
            assessment_details=assessment_details,
        )

        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

        post = rows[0]
        if str(post.get("uploader")) != str(author_id):
            raise ApiError(
                "You can only edit your own post.",
                code="forbidden",
                status_code=HTTPStatus.FORBIDDEN,
            )

        try:
            updated_rows = self.client.db_update(
                FEED_POSTS_TABLE,
                data={
                    "title": title,
                    "content": content,
                    "category": category,
                    "location": location,
                    "post_kind": post_kind,
                    "assessment_details": normalized_assessment_details,
                },
                params={"id": f"eq.{post_id}", "uploader": f"eq.{author_id}"},
                use_service_role=True,
            )
        except httpx.HTTPStatusError as error:
            self._raise_schema_migration_error(error)
        if not updated_rows:
            raise ApiError("Failed to update post.", code="update_failed")

        updated_post = updated_rows[0]
        department = self._department_for_uploader(updated_post.get("uploader"))
        assets = self._assets_for_post(updated_post.get("id"))
        comment_count = len(self.list_comments(post_id=updated_post.get("id")))
        return self._serialize_post(
            post=updated_post,
            department=department,
            assets=assets,
            comment_count=comment_count,
            liked_by_me=False,
        )

    def list_posts(
        self,
        *,
        category: str | None = None,
        uploader_id: str | None = None,
        viewer_user_id: str | None = None,
    ) -> list[dict[str, Any]]:
        params: dict[str, str] = {"select": "*", "order": "created_at.desc"}
        if category:
            params["category"] = f"eq.{category}"
        if uploader_id:
            params["uploader"] = f"eq.{uploader_id}"
        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params=params,
            use_service_role=True,
        )

        departments_by_user = self._departments_by_user_id(
            user_ids=[row.get("uploader") for row in rows if row.get("uploader")]
        )
        assets_by_post_id = self._assets_by_post_id(post_ids=[row.get("id") for row in rows])
        comment_counts_by_post_id = self._comment_counts_by_post_id(
            post_ids=[row.get("id") for row in rows]
        )
        liked_post_ids = self._liked_post_ids(
            post_ids=[row.get("id") for row in rows], user_id=viewer_user_id
        )
        return [
            self._serialize_post(
                post=row,
                department=departments_by_user.get(str(row.get("uploader"))),
                assets=assets_by_post_id.get(str(row.get("id"))),
                comment_count=comment_counts_by_post_id.get(str(row.get("id")), 0),
                liked_by_me=str(row.get("id")) in liked_post_ids,
            )
            for row in rows
        ]

    def get_post(self, post_id: str, *, viewer_user_id: str | None = None) -> dict[str, Any]:
        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)
        post = rows[0]
        department = self._department_for_uploader(post.get("uploader"))
        assets = self._assets_for_post(post.get("id"))
        comment_count = len(self.list_comments(post_id=post.get("id")))
        liked_post_ids = self._liked_post_ids(post_ids=[post.get("id")], user_id=viewer_user_id)
        return self._serialize_post(
            post=post,
            department=department,
            assets=assets,
            comment_count=comment_count,
            liked_by_me=str(post.get("id")) in liked_post_ids,
        )

    def _department_for_uploader(self, uploader_id: Any) -> dict[str, Any] | None:
        if not uploader_id:
            return None
        departments = self.client.db_query(
            "departments",
            params={"select": "*", "user_id": f"eq.{uploader_id}"},
            use_service_role=True,
        )
        return departments[0] if departments else None

    def _departments_by_user_id(self, *, user_ids: list[Any]) -> dict[str, dict[str, Any]]:
        unique_ids = {str(uid) for uid in user_ids if uid is not None}
        if not unique_ids:
            return {}
        departments = self.client.db_query(
            "departments",
            params={"select": "*", "user_id": f"in.({','.join(unique_ids)})"},
            use_service_role=True,
        )
        return {str(d["user_id"]): d for d in departments if d.get("user_id")}

    def _assets_for_post(self, post_id: Any) -> dict[str, list[str]]:
        if post_id is None:
            return {"photos": [], "attachments": []}
        rows = self.client.db_query(
            FEED_STORAGE_TABLE,
            params={"select": "*", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        return self._collect_assets(rows)

    def _assets_by_post_id(self, *, post_ids: list[Any]) -> dict[str, dict[str, list[str]]]:
        valid_post_ids = {str(post_id) for post_id in post_ids if post_id is not None}
        if not valid_post_ids:
            return {}

        rows = self.client.db_query(
            FEED_STORAGE_TABLE,
            params={"select": "*", "id": f"in.({','.join(valid_post_ids)})"},
            use_service_role=True,
        )
        grouped: dict[str, dict[str, list[str]]] = {}
        for row in rows:
            key = str(row.get("id"))
            bucket = grouped.setdefault(key, {"photos": [], "attachments": []})
            if row.get("photos"):
                bucket["photos"].append(row["photos"])
            if row.get("attachments"):
                bucket["attachments"].append(row["attachments"])
        return grouped

    def _comment_counts_by_post_id(self, *, post_ids: list[Any]) -> dict[str, int]:
        valid_post_ids = {str(post_id) for post_id in post_ids if post_id is not None}
        if not valid_post_ids:
            return {}

        rows = self.client.db_query(
            FEED_COMMENTS_TABLE,
            params={"select": "post_id", "post_id": f"in.({','.join(valid_post_ids)})"},
            use_service_role=True,
        )
        counts: dict[str, int] = {}
        for row in rows:
            key = str(row.get("post_id"))
            counts[key] = counts.get(key, 0) + 1
        return counts

    def _liked_post_ids(self, *, post_ids: list[Any], user_id: str | None) -> set[str]:
        valid_post_ids = {str(post_id) for post_id in post_ids if post_id is not None}
        if not valid_post_ids or not user_id:
            return set()

        rows = self.client.db_query(
            FEED_REACTIONS_TABLE,
            params={"select": "*", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        return {
            str(row.get("post_id"))
            for row in rows
            if row.get("post_id") is not None and str(row.get("post_id")) in valid_post_ids
        }

    def _collect_assets(self, rows: list[dict[str, Any]]) -> dict[str, list[str]]:
        photos = [row["photos"] for row in rows if row.get("photos")]
        attachments = [row["attachments"] for row in rows if row.get("attachments")]
        return {"photos": photos, "attachments": attachments}

    def _require_post_exists(self, post_id: Any) -> None:
        rows = self.client.db_query(
            FEED_POSTS_TABLE,
            params={"select": "id", "id": f"eq.{post_id}"},
            use_service_role=True,
        )
        if not rows:
            raise ApiError("Post not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND)

    def _resolve_user_name(self, *, user_id: str, fallback_name: str) -> str:
        rows = self.client.db_query(
            "users",
            params={"select": "full_name,email", "id": f"eq.{user_id}"},
            use_service_role=True,
        )
        if rows:
            return rows[0].get("full_name") or rows[0].get("email") or fallback_name
        return fallback_name

    def _serialize_comment(self, row: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": row.get("comment_id") or row.get("id"),
            "post_id": row.get("post_id"),
            "user_id": row.get("user_id"),
            "user_name": row.get("user_name"),
            "created_at": row.get("created_at"),
            "comment": row.get("comment"),
        }

    def _serialize_post(
        self,
        *,
        post: dict[str, Any],
        department: dict[str, Any] | None,
        assets: dict[str, list[str]] | None = None,
        comment_count: int = 0,
        liked_by_me: bool = False,
    ) -> dict[str, Any]:
        resolved_assets = assets or {"photos": [], "attachments": []}
        return {
            "id": post.get("id"),
            "uploader": post.get("uploader"),
            "created_at": post.get("created_at"),
            "title": post.get("title"),
            "content": post.get("content"),
            "category": post.get("category"),
            "location": post.get("location"),
            "post_kind": post.get("post_kind") or "standard",
            "assessment_details": post.get("assessment_details"),
            "reaction": post.get("reaction", 0),
            "liked_by_me": liked_by_me,
            "comment_count": comment_count,
            "is_pinned": False,
            "image_urls": resolved_assets["photos"],
            "photos": resolved_assets["photos"],
            "attachments": resolved_assets["attachments"],
            "department": {
                "id": department.get("id"),
                "name": department.get("name"),
                "type": department.get("type"),
                "description": department.get("description"),
                "address": department.get("address"),
                "area_of_responsibility": department.get("area_of_responsibility"),
                "contact_number": department.get("contact_number"),
                "verification_status": department.get("verification_status"),
                "profile_picture": post.get("profile_picture")
                or department.get("profile_picture")
                or department.get("profile_photo"),
            }
            if department
            else None,
        }

    def _normalize_assessment_details(
        self,
        *,
        post_kind: str,
        assessment_details: dict[str, Any] | None,
    ) -> dict[str, Any] | None:
        if post_kind != "assessment":
            return None

        if not isinstance(assessment_details, dict):
            raise ApiError(
                "assessment_details are required for assessment posts.",
                code="validation_error",
            )

        affected_area = str(assessment_details.get("affected_area") or "").strip()
        damage_level = str(assessment_details.get("damage_level") or "").strip()
        description = str(assessment_details.get("description") or "").strip()

        try:
            estimated_casualties = int(assessment_details.get("estimated_casualties") or 0)
            displaced_persons = int(assessment_details.get("displaced_persons") or 0)
        except (TypeError, ValueError) as error:
            raise ApiError(
                "estimated_casualties and displaced_persons must be integers.",
                code="validation_error",
            ) from error

        if not affected_area:
            raise ApiError(
                "affected_area is required for assessment posts.",
                code="validation_error",
            )
        if damage_level not in VALID_DAMAGE_LEVELS:
            raise ApiError(
                f"damage_level must be one of: {', '.join(sorted(VALID_DAMAGE_LEVELS))}.",
                code="validation_error",
            )
        if estimated_casualties < 0 or displaced_persons < 0:
            raise ApiError(
                "estimated_casualties and displaced_persons must be zero or greater.",
                code="validation_error",
            )

        return {
            "affected_area": affected_area,
            "damage_level": damage_level,
            "estimated_casualties": estimated_casualties,
            "displaced_persons": displaced_persons,
            "description": description,
        }

    def _raise_schema_migration_error(self, error: httpx.HTTPStatusError) -> None:
        payload: dict[str, Any] = {}
        try:
            payload = error.response.json()
        except ValueError:
            payload = {}

        diagnostic_text = " ".join(
            str(payload.get(field) or "")
            for field in ("message", "details", "hint")
        ).lower()

        if "department_feed_posts" in diagnostic_text and (
            "post_kind" in diagnostic_text or "assessment_details" in diagnostic_text
        ):
            raise ApiError(
                "Assessment posts need the latest database migration. Apply "
                "`supabase/migrations/20260404000000_feed_assessment_posts.sql` "
                "or run `npx supabase db push`, then try publishing again.",
                code="schema_outdated",
                status_code=HTTPStatus.INTERNAL_SERVER_ERROR,
            ) from error

        raise error
