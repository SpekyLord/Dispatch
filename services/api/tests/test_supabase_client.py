from __future__ import annotations

import httpx

from dispatch_api.clients.supabase import SupabaseClient
from dispatch_api.config import Settings


class StubHttpClient:
    def __init__(self, response: httpx.Response) -> None:
        self.response = response

    def get(self, *_args, **_kwargs) -> httpx.Response:
        return self.response


def make_settings() -> Settings:
    return Settings.model_validate(
        {
            "dispatch_env": "test",
            "cors_origins": "http://localhost:5173",
            "supabase_url": "https://example.supabase.co",
            "supabase_anon_key": "anon-key",
            "supabase_service_role_key": "service-role-key",
        }
    )


def test_get_user_returns_none_for_forbidden_token():
    client = SupabaseClient(make_settings())
    client._http_client = StubHttpClient(
        httpx.Response(
            403,
            request=httpx.Request("GET", "https://example.supabase.co/auth/v1/user"),
            json={"message": "Forbidden"},
        )
    )

    assert client.get_user("expired-token") is None


def test_get_user_returns_none_for_unauthorized_token():
    client = SupabaseClient(make_settings())
    client._http_client = StubHttpClient(
        httpx.Response(
            401,
            request=httpx.Request("GET", "https://example.supabase.co/auth/v1/user"),
            json={"message": "Unauthorized"},
        )
    )

    assert client.get_user("missing-token") is None
