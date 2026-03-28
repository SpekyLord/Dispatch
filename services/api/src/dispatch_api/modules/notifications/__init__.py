from flask import Blueprint

blueprint = Blueprint("notifications", __name__, url_prefix="/api/notifications")

from dispatch_api.modules.notifications import routes  # noqa: E402, F401
