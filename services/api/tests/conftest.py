from __future__ import annotations

from collections.abc import Generator

import pytest
from flask import Blueprint, jsonify

from dispatch_api.app import create_app
from dispatch_api.auth import require_auth, require_role
from dispatch_api.config import Settings


@pytest.fixture
def settings() -> Settings:
    return Settings.model_validate(
        {
            "dispatch_env": "test",
            "cors_origins": ["http://localhost:5173"],
            "supabase_url": "https://example.supabase.co",
            "supabase_anon_key": "anon-key",
            "supabase_service_role_key": "service-role-key",
        }
    )


@pytest.fixture
def app(settings: Settings):
    app = create_app(settings)
    test_blueprint = Blueprint("test_auth", __name__, url_prefix="/api/test")

    @test_blueprint.get("/protected")
    @require_auth()
    def protected():
        return jsonify({"status": "ok"})

    @test_blueprint.get("/municipality")
    @require_role("municipality")
    def municipality():
        return jsonify({"status": "ok"})

    app.register_blueprint(test_blueprint)
    return app


@pytest.fixture
def client(app) -> Generator:
    with app.test_client() as test_client:
        yield test_client
