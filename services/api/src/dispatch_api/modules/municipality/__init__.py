from flask import Blueprint

blueprint = Blueprint("municipality", __name__, url_prefix="/api/municipality")

from dispatch_api.modules.municipality import routes  # noqa: E402, F401
