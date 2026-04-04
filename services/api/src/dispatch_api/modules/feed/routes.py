from __future__ import annotations

from http import HTTPStatus
import json

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.feed import blueprint
from dispatch_api.services.department_service import DepartmentService
from dispatch_api.services.feed_service import FeedService
from dispatch_api.services.notification_service import NotificationService


def _feed_service() -> FeedService:
    client = current_app.extensions["supabase_client"]
    return FeedService(client, NotificationService(client))


def _department_service() -> DepartmentService:
    return DepartmentService(current_app.extensions["supabase_client"])


@blueprint.get("")
def list_feed():
    current_user = get_current_user()
    posts = _feed_service().list_posts(
        category=request.args.get("category"),
        uploader_id=request.args.get("uploader"),
        viewer_user_id=current_user.id if current_user else None,
    )
    return jsonify({"posts": posts})


@blueprint.get("/<post_id>")
def get_feed_post(post_id: str):
    current_user = get_current_user()
    post = _feed_service().get_post(
        post_id, viewer_user_id=current_user.id if current_user else None
    )
    return jsonify({"post": post})


@blueprint.get("/<post_id>/comments")
def list_feed_comments(post_id: str):
    comments = _feed_service().list_comments(post_id=post_id)
    return jsonify({"comments": comments})


@blueprint.post("/<post_id>/comments")
@require_auth()
def create_feed_comment(post_id: str):
    user = get_current_user()
    body = request.get_json(silent=True) or {}
    comment = _feed_service().create_comment(
        post_id=post_id,
        user_id=user.id,
        fallback_name=user.email,
        content=(body.get("comment") or "").strip(),
    )
    return jsonify({"comment": comment}), HTTPStatus.CREATED


@blueprint.post("/<post_id>/reaction")
@require_auth()
def toggle_feed_reaction(post_id: str):
    user = get_current_user()
    post = _feed_service().toggle_reaction(post_id=post_id, user_id=user.id)
    return jsonify({"post": post}), HTTPStatus.OK


@blueprint.delete("/<post_id>")
@require_auth()
def delete_feed_post(post_id: str):
    user = get_current_user()
    if user.role != "department":
        raise ApiError(
            "Only department users can delete posts.",
            code="forbidden",
            status_code=HTTPStatus.FORBIDDEN,
        )

    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)
    _feed_service().delete_post(post_id=post_id, author_id=user.id)
    return jsonify({"deleted": True}), HTTPStatus.OK


@blueprint.put("/<post_id>")
@require_auth()
def update_feed_post(post_id: str):
    user = get_current_user()
    if user.role != "department":
        raise ApiError(
            "Only department users can edit posts.",
            code="forbidden",
            status_code=HTTPStatus.FORBIDDEN,
        )

    department_service = _department_service()
    department = department_service.get_department_for_user(user.id)
    department_service.require_verified_department(department)

    body = request.get_json(silent=True) or {}
    post = _feed_service().update_post(
        post_id=post_id,
        author_id=user.id,
        title=(body.get("title") or "").strip(),
        content=(body.get("content") or "").strip(),
        category=(body.get("category") or "").strip(),
        location=(body.get("location") or "").strip(),
        post_kind=(body.get("post_kind") or "standard").strip() or "standard",
        assessment_details=_parse_assessment_details(body),
    )
    return jsonify({"post": post}), HTTPStatus.OK


def _parse_assessment_details(body) -> dict | None:
    raw_value = body.get("assessment_details") if body else None
    if raw_value in (None, ""):
        return None

    if isinstance(raw_value, str):
        try:
            parsed = json.loads(raw_value)
        except json.JSONDecodeError as error:
            raise ApiError(
                "assessment_details must be valid JSON.",
                code="validation_error",
            ) from error
    else:
        parsed = raw_value

    if not isinstance(parsed, dict):
        raise ApiError(
            "assessment_details must be an object.",
            code="validation_error",
        )

    return parsed

