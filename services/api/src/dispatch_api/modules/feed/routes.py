from __future__ import annotations

from flask import current_app, jsonify, request

from dispatch_api.modules.feed import blueprint
from dispatch_api.services.feed_service import FeedService
from dispatch_api.services.notification_service import NotificationService


def _feed_service() -> FeedService:
    client = current_app.extensions["supabase_client"]
    return FeedService(client, NotificationService(client))


@blueprint.get("")
def list_feed():
    posts = _feed_service().list_posts(category=request.args.get("category"))
    return jsonify({"posts": posts})


@blueprint.get("/<post_id>")
def get_feed_post(post_id: str):
    post = _feed_service().get_post(post_id)
    return jsonify({"post": post})
