# Mesh gateway blueprint — batch ingest and sync-updates for offline-first sync.

from flask import Blueprint

blueprint = Blueprint("mesh", __name__, url_prefix="/api/mesh")

from dispatch_api.modules.mesh import routes  # noqa: E402, F401
