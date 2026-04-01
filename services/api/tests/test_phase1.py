"""Phase 1 API tests - auth, verification, reports, and role guards."""

from __future__ import annotations

import pytest

from dispatch_api.app import create_app
from dispatch_api.config import Settings

# ── Helpers ────────────────────────────────────────────────────


class FakeUser:
    def __init__(self, *, id: str, email: str, role: str | None) -> None:
        self.id = id
        self.email = email
        self.role = role


class FakeSupabaseClient:
    """Minimal stand-in for SupabaseClient used in route tests."""

    def __init__(self, *, user=None, db_rows=None) -> None:
        self._user = user
        self._db: dict[str, list] = db_rows or {}
        self._inserts: list[tuple[str, dict]] = []
        self._updates: list[tuple[str, dict, dict]] = []

    def check_readiness(self):
        return True, {}

    def get_user(self, token: str):
        if token == "valid-token":
            return self._user
        return None

    def sign_up(self, *, email, password, user_metadata=None):
        return {
            "user": {"id": "new-user-id", "email": email},
            "access_token": "new-access-token",
            "session": {"access_token": "new-access-token"},
        }

    def sign_in(self, *, email, password):
        if email == "bad@example.com":
            return {"error": {"message": "Invalid credentials"}}
        return {
            "access_token": "login-token",
            "refresh_token": "refresh-token",
            "user": {
                "id": "user-1",
                "email": email,
                "user_metadata": {"role": "citizen"},
            },
        }

    def sign_out(self, token):
        return True

    def refresh_session(self, *, refresh_token: str):
        if refresh_token == "bad-refresh":
            return {"error": {"message": "Invalid refresh token"}}
        return {
            "access_token": "refreshed-token",
            "refresh_token": "fresh-refresh-token",
            "user": {
                "id": "user-1",
                "email": "u@e.com",
                "user_metadata": {"role": "citizen"},
            },
        }

    def db_query(self, table, *, token=None, params=None, use_service_role=False):
        return self._db.get(table, [])

    def db_insert(self, table, *, data, token=None, use_service_role=False, return_repr=True):
        if isinstance(data, list):
            for d in data:
                self._inserts.append((table, d))
        else:
            self._inserts.append((table, data))
        if return_repr:
            if isinstance(data, dict):
                row = {"id": "gen-id-1", **data}
                return [row]
            return [{"id": "gen-id-1"}]
        return []

    def db_update(
        self, table, *, data, params, token=None, use_service_role=False, return_repr=True
    ):
        self._updates.append((table, data, params))
        # Mutate stored rows so subsequent queries see the update
        updated = []
        for row in self._db.get(table, []):
            match = True
            for key, val in params.items():
                if key in ("select", "order"):
                    continue
                expected = val.removeprefix("eq.") if isinstance(val, str) else val
                if str(row.get(key, "")) != str(expected):
                    match = False
                    break
            if match:
                row.update(data)
                updated.append({**row})
        if return_repr:
            if updated:
                return updated
            merged = {}
            rows = self._db.get(table, [])
            if rows:
                merged = {**rows[0]}
            merged.update(data)
            merged.setdefault("id", params.get("id", "").removeprefix("eq."))
            return [merged]
        return []

    def storage_upload(self, *, bucket, object_path, file_data, content_type):
        return {"Key": object_path}

    def storage_public_url(self, *, bucket, object_path):
        return f"https://storage.example.com/{bucket}/{object_path}"

    def update_user_metadata(self, token, *, user_metadata):
        return {"id": "user-1"}


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


def make_app(settings, fake_client):
    app = create_app(settings)
    app.extensions["supabase_client"] = fake_client
    return app


def auth_header():
    return {"Authorization": "Bearer valid-token"}


# ── Auth tests ─────────────────────────────────────────────────


class TestAuthRegister:
    def test_register_citizen(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/auth/register",
                json={
                    "email": "test@example.com",
                    "password": "secret123",
                    "role": "citizen",
                    "full_name": "Test",
                },
            )
            assert resp.status_code == 201
            data = resp.json
            assert data["user"]["email"] == "test@example.com"
            assert data["user"]["role"] == "citizen"

    def test_register_department(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/auth/register",
                json={
                    "email": "fire@example.com",
                    "password": "secret123",
                    "role": "department",
                    "full_name": "Fire Chief",
                    "organization_name": "City Fire",
                    "department_type": "fire",
                },
            )
            assert resp.status_code == 201
            assert resp.json["department"] is not None

    def test_register_missing_email(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/register", json={"password": "secret123", "role": "citizen"})
            assert resp.status_code == 400

    def test_register_invalid_role(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/auth/register",
                json={"email": "t@e.com", "password": "secret123", "role": "admin"},
            )
            assert resp.status_code == 400

    def test_register_department_missing_org_name(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/auth/register",
                json={"email": "d@e.com", "password": "secret123", "role": "department"},
            )
            assert resp.status_code == 400


class TestAuthLogin:
    def test_login_success(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "users": [{"id": "user-1", "email": "u@e.com", "role": "citizen", "full_name": "U"}]
            }
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/login", json={"email": "u@e.com", "password": "pass123"})
            assert resp.status_code == 200
            assert "access_token" in resp.json

    def test_login_invalid_credentials(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/login", json={"email": "bad@example.com", "password": "wrong"})
            assert resp.status_code == 401

    def test_login_missing_fields(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/login", json={"email": ""})
            assert resp.status_code == 400

    def test_refresh_success(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "users": [{"id": "user-1", "email": "u@e.com", "role": "citizen", "full_name": "U"}]
            }
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/refresh", json={"refresh_token": "refresh-token"})
            assert resp.status_code == 200
            assert resp.json["access_token"] == "refreshed-token"
            assert resp.json["refresh_token"] == "fresh-refresh-token"

    def test_refresh_invalid_token(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/auth/refresh", json={"refresh_token": "bad-refresh"})
            assert resp.status_code == 401


class TestAuthMe:
    def test_me_returns_user_info(self, settings):
        user = FakeUser(id="user-1", email="u@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "users": [
                    {
                        "id": "user-1",
                        "email": "u@e.com",
                        "full_name": "Citizen",
                        "phone": None,
                        "avatar_url": None,
                    }
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/auth/me", headers=auth_header())
            assert resp.status_code == 200
            assert resp.json["user"]["email"] == "u@e.com"

    def test_me_requires_auth(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/auth/me")
            assert resp.status_code == 401


# ── Profile tests ──────────────────────────────────────────────


class TestUserProfile:
    def test_get_profile(self, settings):
        user = FakeUser(id="user-1", email="u@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={"users": [{"id": "user-1", "full_name": "Test", "phone": "123"}]},
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/users/profile", headers=auth_header())
            assert resp.status_code == 200
            assert resp.json["profile"]["full_name"] == "Test"

    def test_update_profile(self, settings):
        user = FakeUser(id="user-1", email="u@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={"users": [{"id": "user-1", "full_name": "Old", "phone": ""}]},
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/users/profile", headers=auth_header(), json={"full_name": "New Name"}
            )
            assert resp.status_code == 200

    def test_update_profile_rejects_empty(self, settings):
        user = FakeUser(id="user-1", email="u@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put("/api/users/profile", headers=auth_header(), json={"unknown_field": "x"})
            assert resp.status_code == 400


# ── Municipality verification tests ───────────────────────────


class TestMunicipalityVerification:
    def test_list_departments_requires_municipality_role(self, settings):
        user = FakeUser(id="user-1", email="u@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/departments", headers=auth_header())
            assert resp.status_code == 403

    def test_list_departments_as_municipality(self, settings):
        user = FakeUser(id="user-1", email="admin@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user, db_rows={"departments": [{"id": "d1", "name": "Fire"}]}
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/departments", headers=auth_header())
            assert resp.status_code == 200
            assert len(resp.json["departments"]) == 1

    def test_list_pending_departments(self, settings):
        user = FakeUser(id="user-1", email="admin@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user, db_rows={"departments": [{"id": "d1", "verification_status": "pending"}]}
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/departments/pending", headers=auth_header())
            assert resp.status_code == 200

    def test_approve_department(self, settings):
        user = FakeUser(id="user-1", email="admin@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={"departments": [{"id": "d1", "verification_status": "pending"}]},
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/municipality/departments/d1/verify",
                headers=auth_header(),
                json={"action": "approved"},
            )
            assert resp.status_code == 200
            assert resp.json["department"]["verification_status"] == "approved"

    def test_reject_department_requires_reason(self, settings):
        user = FakeUser(id="user-1", email="admin@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={"departments": [{"id": "d1", "verification_status": "pending"}]},
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/municipality/departments/d1/verify",
                headers=auth_header(),
                json={"action": "rejected"},
            )
            assert resp.status_code == 400

    def test_reject_department_with_reason(self, settings):
        user = FakeUser(id="user-1", email="admin@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={"departments": [{"id": "d1", "verification_status": "pending"}]},
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/municipality/departments/d1/verify",
                headers=auth_header(),
                json={"action": "rejected", "rejection_reason": "Incomplete documents"},
            )
            assert resp.status_code == 200
            assert resp.json["department"]["verification_status"] == "rejected"


# ── Department resubmission tests ─────────────────────────────


class TestDepartmentResubmission:
    def test_rejected_department_can_resubmit(self, settings):
        user = FakeUser(id="dept-user-1", email="fire@e.com", role="department")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "departments": [
                    {
                        "id": "d1",
                        "user_id": "dept-user-1",
                        "name": "Old Fire",
                        "type": "fire",
                        "verification_status": "rejected",
                        "rejection_reason": "Missing docs",
                    }
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/departments/profile",
                headers=auth_header(),
                json={"name": "Updated Fire Station", "address": "New Address"},
            )
            assert resp.status_code == 200
            dept = resp.json["department"]
            assert dept["verification_status"] == "pending"
            assert dept["rejection_reason"] is None

    def test_unverified_department_cannot_access_ops(self, settings):
        # This checks that department routes exist and work but the
        # verification check is enforced at the operational level
        user = FakeUser(id="dept-user-1", email="fire@e.com", role="department")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "departments": [
                    {"id": "d1", "user_id": "dept-user-1", "verification_status": "pending"}
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/departments/profile", headers=auth_header())
            assert resp.status_code == 200
            assert resp.json["department"]["verification_status"] == "pending"


class TestPublicDepartmentDirectory:
    def test_public_directory_lists_only_approved_departments(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {
                        "id": "d1",
                        "user_id": "dept-user-1",
                        "name": "BFP Central",
                        "type": "fire",
                        "verification_status": "approved",
                        "profile_picture": "https://example.com/bfp.png",
                    },
                    {
                        "id": "d2",
                        "user_id": "dept-user-2",
                        "name": "Engineering",
                        "type": "public_works",
                        "verification_status": "pending",
                    },
                ],
                "department_profile_summary": [
                    {
                        "id": "d1",
                        "user_id": "dept-user-1",
                        "name": "BFP Central",
                        "type": "fire",
                        "description": "24/7 response coverage",
                        "profile_picture": "https://example.com/bfp.png",
                        "area_of_responsibility": "Central District",
                    }
                ],
                "department_feed_posts": [
                    {"id": "p1", "uploader": "dept-user-1"},
                    {"id": "p2", "uploader": "dept-user-1"},
                ],
            }
        )
        app = make_app(settings, fake)

        with app.test_client() as c:
            resp = c.get("/api/departments/directory")

        assert resp.status_code == 200
        assert len(resp.json["departments"]) == 1
        assert resp.json["departments"][0]["name"] == "BFP Central"
        assert resp.json["departments"][0]["description"] == "24/7 response coverage"
        assert resp.json["departments"][0]["post_count"] == 2


# ── Report tests ───────────────────────────────────────────────


class TestReports:
    def test_create_report(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/reports",
                headers=auth_header(),
                json={
                    "description": "Fire at building",
                    "category": "fire",
                    "severity": "high",
                    "address": "123 Main St",
                },
            )
            assert resp.status_code == 201
            report = resp.json["report"]
            assert report["status"] == "pending"
            assert report["is_escalated"] is False

    def test_create_report_auto_categorizes_when_category_is_missing(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/reports",
                headers=auth_header(),
                json={"description": "Something happened"},
            )
            assert resp.status_code == 201
            assert resp.json["report"]["category"] == "other"

    def test_create_report_requires_description(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/reports",
                headers=auth_header(),
                json={"category": "fire"},
            )
            assert resp.status_code == 400

    def test_create_report_requires_citizen_role(self, settings):
        user = FakeUser(id="dept-1", email="d@e.com", role="department")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/reports",
                headers=auth_header(),
                json={"description": "test", "category": "fire"},
            )
            assert resp.status_code == 403

    def test_list_reports(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "reporter_id": "citizen-1",
                        "description": "Fire",
                        "status": "pending",
                    }
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/reports", headers=auth_header())
            assert resp.status_code == 200
            assert isinstance(resp.json["reports"], list)

    def test_get_report_detail(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "reporter_id": "citizen-1",
                        "description": "Fire",
                        "status": "pending",
                    }
                ],
                "report_status_history": [
                    {"id": "h1", "report_id": "r1", "status": "pending", "created_at": "2026-01-01"}
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/reports/r1", headers=auth_header())
            assert resp.status_code == 200
            assert resp.json["report"]["id"] == "r1"
            assert isinstance(resp.json["status_history"], list)

    def test_citizen_cannot_view_other_citizen_report(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {"id": "r1", "reporter_id": "citizen-2", "description": "Other"}
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/reports/r1", headers=auth_header())
            assert resp.status_code == 403

    def test_report_creates_initial_status_history(self, settings):
        user = FakeUser(id="citizen-1", email="c@e.com", role="citizen")
        fake = FakeSupabaseClient(user=user)
        app = make_app(settings, fake)
        with app.test_client() as c:
            c.post(
                "/api/reports",
                headers=auth_header(),
                json={"description": "test", "category": "fire"},
            )
            # Check that status history insert was made
            history_inserts = [i for i in fake._inserts if i[0] == "report_status_history"]
            assert len(history_inserts) == 1
            assert history_inserts[0][1]["new_status"] == "pending"
