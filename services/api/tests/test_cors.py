from __future__ import annotations

from dispatch_api.app import create_app
from dispatch_api.config import Settings


def make_settings(*, dispatch_env: str = "development", cors_origins: str = "http://localhost:5173") -> Settings:
    return Settings.model_validate(
        {
            "dispatch_env": dispatch_env,
            "cors_origins": cors_origins,
            "supabase_url": "https://example.supabase.co",
            "supabase_anon_key": "anon-key",
            "supabase_service_role_key": "service-role-key",
        }
    )


def test_development_cors_allows_localhost_ports_for_flutter_web():
    app = create_app(make_settings())

    with app.test_client() as client:
        response = client.get("/api/health", headers={"Origin": "http://localhost:49321"})

    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "http://localhost:49321"


def test_development_cors_allows_127001_ports_for_flutter_web():
    app = create_app(make_settings())

    with app.test_client() as client:
        response = client.get("/api/health", headers={"Origin": "http://127.0.0.1:38117"})

    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == "http://127.0.0.1:38117"


def test_production_cors_keeps_explicit_origins_only():
    settings = make_settings(
        dispatch_env="production",
        cors_origins="https://dispatch.example.com",
    )

    assert settings.cors_origins_list == ["https://dispatch.example.com"]
