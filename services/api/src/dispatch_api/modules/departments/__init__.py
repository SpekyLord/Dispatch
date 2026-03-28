from flask import Blueprint

blueprint = Blueprint("departments", __name__, url_prefix="/api/departments")

from dispatch_api.modules.departments import routes  # noqa: E402, F401
