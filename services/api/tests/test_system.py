from __future__ import annotations

from dispatch_api.services.storage import MAX_IMAGE_SIZE_BYTES, StorageService


class FakeSupabaseClient:
    def __init__(self, *, ready: bool, user=None) -> None:
        self.ready = ready
        self.user = user

    def check_readiness(self):
        return self.ready, {"target": "fake-supabase"}

    def get_user(self, token: str):
        if token == "valid-token":
            return self.user
        return None


class FakeUser:
    def __init__(self, *, id: str, email: str, role: str | None) -> None:
        self.id = id
        self.email = email
        self.role = role


def test_health_endpoint(client):
    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json["service"] == "dispatch-api"
    assert response.json["status"] == "ok"


def test_ready_endpoint_returns_service_unavailable_when_dependency_is_not_ready(app, client):
    app.extensions["supabase_client"] = FakeSupabaseClient(ready=False)

    response = client.get("/api/ready")

    assert response.status_code == 503
    assert response.json["status"] == "not_ready"


def test_ready_endpoint_returns_ok_when_dependency_is_ready(app, client):
    app.extensions["supabase_client"] = FakeSupabaseClient(ready=True)

    response = client.get("/api/ready")

    assert response.status_code == 200
    assert response.json["status"] == "ready"


def test_protected_route_requires_authentication(client):
    response = client.get("/api/test/protected")

    assert response.status_code == 401
    assert response.json["error"]["code"] == "authentication_required"


def test_role_guard_returns_forbidden_for_wrong_role(app, client):
    app.extensions["supabase_client"] = FakeSupabaseClient(
        ready=True, user=FakeUser(id="1", email="user@example.com", role="citizen")
    )

    response = client.get(
        "/api/test/municipality",
        headers={"Authorization": "Bearer valid-token"},
    )

    assert response.status_code == 403
    assert response.json["error"]["code"] == "forbidden"


def test_role_guard_allows_matching_role(app, client):
    app.extensions["supabase_client"] = FakeSupabaseClient(
        ready=True, user=FakeUser(id="1", email="user@example.com", role="municipality")
    )

    response = client.get(
        "/api/test/municipality",
        headers={"Authorization": "Bearer valid-token"},
    )

    assert response.status_code == 200
    assert response.json["status"] == "ok"


def test_storage_service_rejects_invalid_media_type(settings):
    storage_service = StorageService(settings)

    try:
        storage_service.validate_upload(content_type="image/gif", size_bytes=1024)
    except Exception as error:
        assert getattr(error, "code", None) == "unsupported_media_type"
    else:
        raise AssertionError("Expected upload validation to reject GIF uploads.")


def test_storage_service_rejects_large_files(settings):
    storage_service = StorageService(settings)

    try:
        storage_service.validate_upload(
            content_type="image/png",
            size_bytes=MAX_IMAGE_SIZE_BYTES + 1,
        )
    except Exception as error:
        assert getattr(error, "code", None) == "file_too_large"
    else:
        raise AssertionError("Expected upload validation to reject oversized files.")
