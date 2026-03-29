"""Phase 3 tests — analytics, assessments, timeline, and municipality report overview."""

from __future__ import annotations

from copy import deepcopy
from datetime import UTC, datetime, timedelta

import pytest

from dispatch_api.app import create_app
from dispatch_api.config import Settings
from dispatch_api.services.analytics_service import AnalyticsService

# ── Shared test helpers ──────────────────────────────────────


class FakeUser:
    def __init__(self, *, id: str, email: str, role: str | None) -> None:
        self.id = id
        self.email = email
        self.role = role


class FakeSupabaseClient:
    """In-memory Supabase stand-in for unit tests."""

    def __init__(self, *, user=None, db_rows=None) -> None:
        self._user = user
        self._db = {
            table: [deepcopy(row) for row in rows] for table, rows in (db_rows or {}).items()
        }
        self._inserts: list[tuple[str, dict]] = []
        self._updates: list[tuple[str, dict, dict]] = []
        self._counter = 0

    def check_readiness(self):
        return True, {}

    def get_user(self, token: str):
        return self._user if token == "valid-token" else None

    def sign_up(self, *, email, password, user_metadata=None):
        return {"user": {"id": "new-user-id", "email": email}, "access_token": "at"}

    def sign_in(self, *, email, password):
        return {"access_token": "at", "refresh_token": "rt", "user": {"id": "u1", "email": email}}

    def sign_out(self, token):
        return True

    def update_user_metadata(self, token, *, user_metadata):
        return {"id": "u1"}

    def db_query(self, table, *, token=None, params=None, use_service_role=False):
        rows = [deepcopy(r) for r in self._db.get(table, [])]
        for key, val in (params or {}).items():
            if key in ("select", "order"):
                continue
            if isinstance(val, str) and val.startswith("eq."):
                expected = val.removeprefix("eq.")
                rows = [r for r in rows if str(r.get(key, "")) == expected]
        order = (params or {}).get("order")
        if order:
            field, _, direction = order.partition(".")
            rows.sort(key=lambda r: r.get(field) or "", reverse=direction == "desc")
        return rows

    def db_insert(self, table, *, data, token=None, use_service_role=False, return_repr=True):
        payload = data if isinstance(data, list) else [data]
        inserted = []
        for row in payload:
            item = deepcopy(row)
            self._counter += 1
            item.setdefault("id", f"{table}-{self._counter}")
            item.setdefault("created_at", datetime.now(tz=UTC).isoformat())
            self._db.setdefault(table, []).append(item)
            self._inserts.append((table, deepcopy(item)))
            inserted.append(deepcopy(item))
        return inserted if return_repr else []

    def db_update(
        self, table, *, data, params, token=None, use_service_role=False, return_repr=True
    ):
        updated = []
        for row in self._db.get(table, []):
            if self._matches(row, params):
                row.update(deepcopy(data))
                self._updates.append((table, deepcopy(data), deepcopy(params)))
                updated.append(deepcopy(row))
        return updated if return_repr else []

    def db_delete(self, table, *, params, token=None, use_service_role=False, return_repr=True):
        deleted, kept = [], []
        for row in self._db.get(table, []):
            (deleted if self._matches(row, params) else kept).append(row)
        self._db[table] = kept
        return [deepcopy(r) for r in deleted] if return_repr else []

    def storage_upload(self, *, bucket, object_path, file_data, content_type):
        return {"Key": object_path}

    def storage_public_url(self, *, bucket, object_path):
        return f"https://storage.example.com/{bucket}/{object_path}"

    def _matches(self, row: dict, params: dict) -> bool:
        for key, val in params.items():
            if key in ("select", "order"):
                continue
            if not isinstance(val, str) or not val.startswith("eq."):
                continue
            expected = val.removeprefix("eq.")
            actual = row.get(key)
            if isinstance(actual, bool):
                if actual is not (expected.lower() == "true"):
                    return False
                continue
            if str(actual) != expected:
                return False
        return True

    def _now(self) -> str:
        return datetime.now(tz=UTC).isoformat()


@pytest.fixture
def settings() -> Settings:
    return Settings.model_validate(
        {
            "dispatch_env": "test",
            "cors_origins": "http://localhost:5173",
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


def iso_ago(seconds: int) -> str:
    return (datetime.now(tz=UTC) - timedelta(seconds=seconds)).isoformat()


# ── Analytics service unit tests ─────────────────────────────


class TestAnalyticsService:
    def test_analytics_counts_by_status_and_category(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "pending",
                        "category": "fire",
                        "created_at": iso_ago(60),
                    },
                    {
                        "id": "r2",
                        "status": "accepted",
                        "category": "fire",
                        "created_at": iso_ago(120),
                    },
                    {
                        "id": "r3",
                        "status": "resolved",
                        "category": "flood",
                        "created_at": iso_ago(300),
                    },
                ],
                "report_status_history": [],
                "department_responses": [],
                "departments": [],
            }
        )
        analytics = AnalyticsService(fake).get_analytics()
        assert analytics["total_reports"] == 3
        assert analytics["by_status"]["pending"] == 1
        assert analytics["by_status"]["accepted"] == 1
        assert analytics["by_status"]["resolved"] == 1
        assert analytics["by_category"]["fire"] == 2
        assert analytics["by_category"]["flood"] == 1

    def test_analytics_response_time_computation(self, settings):
        now = datetime.now(tz=UTC)
        # History shows: pending at t-300, accepted at t-200, responding at t-100
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "responding",
                        "category": "fire",
                        "created_at": (now - timedelta(seconds=300)).isoformat(),
                    },
                ],
                "report_status_history": [
                    {
                        "report_id": "r1",
                        "new_status": "pending",
                        "created_at": (now - timedelta(seconds=300)).isoformat(),
                    },
                    {
                        "report_id": "r1",
                        "new_status": "accepted",
                        "created_at": (now - timedelta(seconds=200)).isoformat(),
                    },
                    {
                        "report_id": "r1",
                        "new_status": "responding",
                        "created_at": (now - timedelta(seconds=100)).isoformat(),
                    },
                ],
                "department_responses": [],
                "departments": [],
            }
        )
        analytics = AnalyticsService(fake).get_analytics()
        rt = analytics["response_times"]
        # ~100 seconds each
        assert rt["avg_create_to_accept"] is not None
        assert abs(rt["avg_create_to_accept"] - 100) < 2
        assert abs(rt["avg_accept_to_responding"] - 100) < 2

    def test_analytics_unattended_count(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "pending",
                        "category": "fire",
                        "created_at": iso_ago(7200),
                    },  # old, no acceptance → unattended
                    {
                        "id": "r2",
                        "status": "accepted",
                        "category": "flood",
                        "created_at": iso_ago(7200),
                    },  # accepted → not unattended
                ],
                "report_status_history": [],
                "department_responses": [
                    {"report_id": "r2", "department_id": "d1", "action": "accepted"},
                ],
                "departments": [],
            }
        )
        analytics = AnalyticsService(fake).get_analytics()
        assert analytics["unattended_reports"] == 1


# ── Municipality routes: reports, analytics, assessments ─────


class TestMunicipalityReportsEndpoint:
    def test_municipality_can_list_all_reports(self, settings):
        user = FakeUser(id="muni-1", email="muni@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "pending",
                        "category": "fire",
                        "is_escalated": False,
                        "created_at": iso_ago(100),
                    },
                    {
                        "id": "r2",
                        "status": "resolved",
                        "category": "flood",
                        "is_escalated": True,
                        "created_at": iso_ago(200),
                    },
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/reports", headers=auth_header())
            assert resp.status_code == 200
            assert len(resp.json["reports"]) == 2

    def test_municipality_reports_filter_by_status(self, settings):
        user = FakeUser(id="muni-1", email="muni@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "pending",
                        "category": "fire",
                        "is_escalated": False,
                        "created_at": iso_ago(100),
                    },
                    {
                        "id": "r2",
                        "status": "resolved",
                        "category": "flood",
                        "is_escalated": False,
                        "created_at": iso_ago(200),
                    },
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/reports?status=pending", headers=auth_header())
            assert resp.status_code == 200
            assert len(resp.json["reports"]) == 1
            assert resp.json["reports"][0]["id"] == "r1"


class TestMunicipalityAnalyticsEndpoint:
    def test_municipality_can_view_analytics(self, settings):
        user = FakeUser(id="muni-1", email="muni@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "status": "pending",
                        "category": "fire",
                        "created_at": iso_ago(100),
                    },
                ],
                "report_status_history": [
                    {"report_id": "r1", "new_status": "pending", "created_at": iso_ago(100)},
                ],
                "department_responses": [],
                "departments": [],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/analytics", headers=auth_header())
            assert resp.status_code == 200
            data = resp.json
            assert data["total_reports"] == 1
            assert "by_status" in data
            assert "by_category" in data
            assert "response_times" in data


class TestMunicipalityAssessmentsEndpoint:
    def test_municipality_can_view_all_assessments(self, settings):
        user = FakeUser(id="muni-1", email="muni@e.com", role="municipality")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "damage_assessments": [
                    {
                        "id": "a1",
                        "department_id": "d1",
                        "affected_area": "Brgy Centro",
                        "damage_level": "severe",
                        "estimated_casualties": 5,
                        "displaced_persons": 50,
                        "location": "Central St",
                        "created_at": iso_ago(100),
                    },
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/municipality/assessments", headers=auth_header())
            assert resp.status_code == 200
            assert len(resp.json["assessments"]) == 1


# ── Department assessment endpoints ──────────────────────────


class TestDepartmentAssessments:
    def _verified_dept_client(self, settings):
        user = FakeUser(id="dept-1", email="dept@e.com", role="department")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "departments": [
                    {
                        "id": "d1",
                        "user_id": "dept-1",
                        "name": "BFP Station",
                        "type": "fire",
                        "verification_status": "approved",
                    },
                ],
                "damage_assessments": [],
            },
        )
        return make_app(settings, fake), fake

    def test_department_can_create_assessment(self, settings):
        app, _fake = self._verified_dept_client(settings)
        with app.test_client() as c:
            resp = c.post(
                "/api/departments/assessments",
                headers=auth_header(),
                json={
                    "affected_area": "Brgy Poblacion",
                    "damage_level": "moderate",
                    "estimated_casualties": 2,
                    "displaced_persons": 30,
                    "location": "Main road",
                    "description": "Flooding damage to infrastructure",
                },
            )
            assert resp.status_code == 201
            assessment = resp.json["assessment"]
            assert assessment["affected_area"] == "Brgy Poblacion"
            assert assessment["damage_level"] == "moderate"

    def test_department_can_list_own_assessments(self, settings):
        app, fake = self._verified_dept_client(settings)
        # Seed an assessment
        fake._db["damage_assessments"] = [
            {
                "id": "a1",
                "department_id": "d1",
                "affected_area": "Brgy 1",
                "damage_level": "minor",
                "created_at": iso_ago(100),
            },
        ]
        with app.test_client() as c:
            resp = c.get("/api/departments/assessments", headers=auth_header())
            assert resp.status_code == 200
            assert len(resp.json["assessments"]) == 1

    def test_invalid_damage_level_rejected(self, settings):
        app, _ = self._verified_dept_client(settings)
        with app.test_client() as c:
            resp = c.post(
                "/api/departments/assessments",
                headers=auth_header(),
                json={
                    "affected_area": "Brgy X",
                    "damage_level": "invalid_level",
                },
            )
            assert resp.status_code == 400


# ── Report detail timeline expansion ─────────────────────────


class TestReportTimeline:
    def test_report_detail_includes_timeline_and_responses(self, settings):
        user = FakeUser(id="citizen-1", email="citizen@e.com", role="citizen")
        fake = FakeSupabaseClient(
            user=user,
            db_rows={
                "incident_reports": [
                    {
                        "id": "r1",
                        "reporter_id": "citizen-1",
                        "status": "accepted",
                        "category": "fire",
                        "is_escalated": False,
                        "created_at": iso_ago(300),
                    },
                ],
                "report_status_history": [
                    {
                        "id": "h1",
                        "report_id": "r1",
                        "new_status": "pending",
                        "old_status": None,
                        "notes": "Report submitted.",
                        "created_at": iso_ago(300),
                    },
                    {
                        "id": "h2",
                        "report_id": "r1",
                        "new_status": "accepted",
                        "old_status": "pending",
                        "notes": "First department accepted.",
                        "created_at": iso_ago(200),
                    },
                ],
                "department_responses": [
                    {
                        "id": "dr1",
                        "report_id": "r1",
                        "department_id": "d1",
                        "action": "accepted",
                        "notes": "On the way",
                        "responded_at": iso_ago(200),
                    },
                ],
                "departments": [
                    {"id": "d1", "name": "BFP Station 1"},
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/reports/r1", headers=auth_header())
            assert resp.status_code == 200
            data = resp.json
            # Timeline combines both history and responses
            assert "timeline" in data
            assert "department_responses" in data
            assert len(data["timeline"]) == 3  # 2 history + 1 response
            # Response should have department name
            assert data["department_responses"][0]["department_name"] == "BFP Station 1"
            # Timeline entries sorted by timestamp
            types = [e["type"] for e in data["timeline"]]
            assert "status_change" in types
            assert "department_response" in types
