from flask import Blueprint

blueprint = Blueprint("users", __name__, url_prefix="/api/users")

from dispatch_api.modules.users import routes  # noqa: E402, F401
