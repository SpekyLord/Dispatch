from flask import Blueprint

blueprint = Blueprint("auth", __name__, url_prefix="/api/auth")

from dispatch_api.modules.auth import routes  # noqa: E402, F401
