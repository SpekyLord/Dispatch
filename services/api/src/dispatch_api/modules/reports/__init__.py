from flask import Blueprint

blueprint = Blueprint("reports", __name__, url_prefix="/api/reports")

from dispatch_api.modules.reports import routes  # noqa: E402, F401
