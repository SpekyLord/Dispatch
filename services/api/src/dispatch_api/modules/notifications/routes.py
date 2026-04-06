from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify

from dispatch_api.auth import get_current_user, require_auth
from dispatch_api.errors import ApiError
from dispatch_api.modules.notifications import blueprint
from dispatch_api.services.notification_service import NotificationService


def _notification_service() -> NotificationService:
    return NotificationService(current_app.extensions["supabase_client"])


@blueprint.get("")
@require_auth()
def list_notifications():
    user = get_current_user()
    notifications = _notification_service().list_for_user(user.id)
    unread_count = sum(1 for notification in notifications if not notification.get("is_read"))
    return jsonify({"notifications": notifications, "unread_count": unread_count})


@blueprint.put("/<notification_id>/read")
@require_auth()
def mark_notification_read(notification_id: str):
    user = get_current_user()
    notification = _notification_service().mark_read(
        user_id=user.id, notification_id=notification_id
    )
    if notification is None:
        raise ApiError(
            "Notification not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND
        )
    return jsonify({"notification": notification})


@blueprint.put("/read-all")
@require_auth()
def mark_all_notifications_read():
    user = get_current_user()
    updated_count = _notification_service().mark_all_read(user_id=user.id)
    return jsonify({"updated_count": updated_count})


@blueprint.delete("/<notification_id>")
@require_auth()
def delete_notification(notification_id: str):
    user = get_current_user()
    notification = _notification_service().delete(
        user_id=user.id, notification_id=notification_id
    )
    if notification is None:
        raise ApiError(
            "Notification not found.", code="not_found", status_code=HTTPStatus.NOT_FOUND
        )
    return jsonify({"deleted": True, "notification": notification}), HTTPStatus.OK
