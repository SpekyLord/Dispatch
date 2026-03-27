from __future__ import annotations

import logging

from flask import Flask
from flask_cors import CORS

from dispatch_api.auth import load_current_user
from dispatch_api.clients.supabase import SupabaseClient
from dispatch_api.config import Settings, get_settings
from dispatch_api.errors import register_error_handlers
from dispatch_api.modules.analytics import blueprint as analytics_blueprint
from dispatch_api.modules.auth import blueprint as auth_blueprint
from dispatch_api.modules.departments import blueprint as departments_blueprint
from dispatch_api.modules.feed import blueprint as feed_blueprint
from dispatch_api.modules.mesh import blueprint as mesh_blueprint
from dispatch_api.modules.municipality import blueprint as municipality_blueprint
from dispatch_api.modules.notifications import blueprint as notifications_blueprint
from dispatch_api.modules.reports import blueprint as reports_blueprint
from dispatch_api.modules.users import blueprint as users_blueprint
from dispatch_api.services.storage import StorageService
from dispatch_api.system import blueprint as system_blueprint


def create_app(settings: Settings | None = None) -> Flask:
    app_settings = settings or get_settings()
    logging.basicConfig(
        level=logging.DEBUG if app_settings.debug else logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    app = Flask(__name__)
    app.config["JSON_SORT_KEYS"] = False
    app.config["SETTINGS"] = app_settings

    CORS(app, resources={r"/api/*": {"origins": app_settings.cors_origins}})

    app.extensions["supabase_client"] = SupabaseClient(app_settings)
    app.extensions["storage_service"] = StorageService(app_settings)

    app.before_request(load_current_user)

    app.register_blueprint(system_blueprint)
    app.register_blueprint(auth_blueprint)
    app.register_blueprint(users_blueprint)
    app.register_blueprint(municipality_blueprint)
    app.register_blueprint(departments_blueprint)
    app.register_blueprint(reports_blueprint)
    app.register_blueprint(feed_blueprint)
    app.register_blueprint(notifications_blueprint)
    app.register_blueprint(analytics_blueprint)
    app.register_blueprint(mesh_blueprint)

    register_error_handlers(app)
    return app
