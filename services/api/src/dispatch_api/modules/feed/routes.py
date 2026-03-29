from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.modules.feed import blueprint
from dispatch_api.services.feed_service import FeedService
from dispatch_api.services.notification_service import NotificationService


def _feed_service() -> FeedService:
    client = current_app.extensions["supabase_client"]
    return FeedService(client, NotificationService(client))


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
