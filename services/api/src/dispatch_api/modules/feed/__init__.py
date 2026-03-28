from flask import Blueprint

blueprint = Blueprint("feed", __name__, url_prefix="/api/feed")

from dispatch_api.modules.feed import routes  # noqa: E402, F401
