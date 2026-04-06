from __future__ import annotations

import io
import json
from copy import deepcopy
from datetime import UTC, datetime, timedelta

import httpx
import pytest

from dispatch_api.app import create_app
from dispatch_api.config import Settings
from dispatch_api.services.notification_service import NotificationService
from dispatch_api.services.report_service import ReportService


class FakeUser:
    def __init__(self, *, id: str, email: str, role: str | None) -> None:
        self.id = id
        self.email = email
        self.role = role


class FakeSupabaseClient:
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
        return {
            "access_token": "login-token",
            "refresh_token": "refresh-token",
            "user": {"id": "user-1", "email": email, "user_metadata": {"role": "citizen"}},
        }

    def sign_out(self, token):
        return True

    def update_user_metadata(self, token, *, user_metadata):
        return {"id": "user-1"}

    def db_query(self, table, *, token=None, params=None, use_service_role=False):
        rows = [deepcopy(row) for row in self._db.get(table, [])]
        params = params or {}
        rows = [row for row in rows if self._matches(row, params)]

        order = params.get("order")
        if order:
            field, _, direction = order.partition(".")
            rows.sort(key=lambda row: row.get(field) or "", reverse=direction == "desc")
        return rows

    def db_insert(self, table, *, data, token=None, use_service_role=False, return_repr=True):
        payload = data if isinstance(data, list) else [data]
        inserted = []
        for row in payload:
            item = deepcopy(row)
            self._counter += 1
            item.setdefault("id", f"{table}-{self._counter}")
            if table == "department_feed_comment":
                item.setdefault("comment_id", self._counter)
            item.setdefault("created_at", self._now())
            if table == "department_responses":
                item.setdefault("responded_at", self._now())
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
        deleted = []
        kept = []
        for row in self._db.get(table, []):
            if self._matches(row, params):
                deleted.append(deepcopy(row))
            else:
                kept.append(row)
        self._db[table] = kept
        return deleted if return_repr else []

    def storage_upload(self, *, bucket, object_path, file_data, content_type):
        return {"Key": object_path}

    def storage_public_url(self, *, bucket, object_path):
        return f"https://storage.example.com/{bucket}/{object_path}"

    def _matches(self, row: dict, params: dict[str, str]) -> bool:
        for key, value in params.items():
            if key in {"select", "order"}:
                continue
            if not isinstance(value, str) or not value.startswith("eq."):
                continue
            expected = value.removeprefix("eq.")
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


def make_app(settings: Settings, fake_client: FakeSupabaseClient):
    app = create_app(settings)
    app.extensions["supabase_client"] = fake_client
    return app


def auth_header():
    return {"Authorization": "Bearer valid-token"}


def iso_now_minus(seconds: int) -> str:
    return (datetime.now(tz=UTC) - timedelta(seconds=seconds)).isoformat()


def test_keyword_categorization_supports_english_and_filipino(settings):
    fake = FakeSupabaseClient()
    service = ReportService(fake, NotificationService(fake))

    assert service.categorize_description("May sunog at makapal ang usok sa kanto") == "fire"
    assert service.categorize_description("Vehicular banggaan near the bridge") == "road_accident"
    assert service.categorize_description("Lindol at gumuho ang pader") == "earthquake"


def test_create_report_preserves_manual_category_override(settings):
    user = FakeUser(id="citizen-1", email="citizen@example.com", role="citizen")
    fake = FakeSupabaseClient(user=user)
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.post(
            "/api/reports",
            headers=auth_header(),
            json={
                "description": "May sunog pero maliwanag na flood override test",
                "category": "flood",
                "severity": "medium",
            },
        )

    assert response.status_code == 201
    assert response.json["report"]["category"] == "flood"


def test_department_board_only_returns_relevant_reports(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP Central",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-police",
                    "user_id": "dept-police-user",
                    "type": "police",
                    "name": "PNP Central",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-disaster",
                    "user_id": "dept-disaster-user",
                    "type": "disaster",
                    "name": "MDRRMO",
                    "verification_status": "approved",
                },
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                },
                {
                    "id": "report-road",
                    "reporter_id": "citizen-2",
                    "category": "road_accident",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                },
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.get("/api/departments/reports", headers=auth_header())

    assert response.status_code == 200
    assert [report["id"] for report in response.json["reports"]] == ["report-fire"]


def test_irrelevant_department_cannot_view_report_detail(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP Central",
                    "verification_status": "approved",
                }
            ],
            "incident_reports": [
                {
                    "id": "report-road",
                    "reporter_id": "citizen-2",
                    "category": "road_accident",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.get("/api/reports/report-road", headers=auth_header())

    assert response.status_code == 403


def test_first_acceptance_moves_report_to_accepted_and_records_history(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP Central",
                    "verification_status": "approved",
                }
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.post(
            "/api/departments/reports/report-fire/accept",
            headers=auth_header(),
            json={"notes": "Dispatching now"},
        )

    assert response.status_code == 200
    assert response.json["report"]["status"] == "accepted"
    history_rows = fake._db["report_status_history"]
    assert history_rows[-1]["old_status"] == "pending"
    assert history_rows[-1]["new_status"] == "accepted"


def test_multiple_departments_can_accept_the_same_report(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user-1", email="one@example.com", role="department"),
        db_rows={
            "departments": [
                {
                    "id": "dept-fire-1",
                    "user_id": "dept-fire-user-1",
                    "type": "fire",
                    "name": "BFP One",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-fire-2",
                    "user_id": "dept-fire-user-2",
                    "type": "fire",
                    "name": "BFP Two",
                    "verification_status": "approved",
                },
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        first = client.post("/api/departments/reports/report-fire/accept", headers=auth_header())
        fake._user = FakeUser(id="dept-fire-user-2", email="two@example.com", role="department")
        second = client.post("/api/departments/reports/report-fire/accept", headers=auth_header())

    assert first.status_code == 200
    assert second.status_code == 200
    assert fake._db["incident_reports"][0]["status"] == "accepted"
    assert len(fake._db["department_responses"]) == 2


def test_all_declines_escalate_without_marking_report_rejected(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user-1", email="one@example.com", role="department"),
        db_rows={
            "users": [
                {"id": "municipality-1", "role": "municipality", "email": "admin@example.com"}
            ],
            "departments": [
                {
                    "id": "dept-fire-1",
                    "user_id": "dept-fire-user-1",
                    "type": "fire",
                    "name": "BFP One",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-fire-2",
                    "user_id": "dept-fire-user-2",
                    "type": "fire",
                    "name": "BFP Two",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-disaster",
                    "user_id": "dept-disaster-user",
                    "type": "disaster",
                    "name": "MDRRMO",
                    "verification_status": "approved",
                },
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        client.post(
            "/api/departments/reports/report-fire/decline",
            headers=auth_header(),
            json={"decline_reason": "No water supply"},
        )
        fake._user = FakeUser(id="dept-fire-user-2", email="two@example.com", role="department")
        response = client.post(
            "/api/departments/reports/report-fire/decline",
            headers=auth_header(),
            json={"decline_reason": "Units unavailable"},
        )

    assert response.status_code == 200
    assert response.json["report"]["is_escalated"] is True
    assert response.json["report"]["status"] == "pending"
    assert fake._db["incident_reports"][0]["status"] != "rejected"
    assert any(
        notification["user_id"] == "municipality-1" for notification in fake._db["notifications"]
    )


def test_timeout_scan_escalates_old_pending_reports(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="municipality-1", email="admin@example.com", role="municipality"),
        db_rows={
            "users": [
                {"id": "municipality-1", "role": "municipality", "email": "admin@example.com"}
            ],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "is_escalated": False,
                    "created_at": iso_now_minus(121),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.post("/api/system/report-escalations/scan", headers=auth_header())

    assert response.status_code == 200
    assert response.json["count"] == 1
    assert fake._db["incident_reports"][0]["is_escalated"] is True


def test_verified_department_can_create_post_and_public_feed_can_read_it(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user", email="fire@example.com", role="department"),
        db_rows={
            "users": [{"id": "citizen-1", "role": "citizen", "email": "citizen@example.com"}],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        create_response = client.post(
            "/api/departments/posts",
            headers=auth_header(),
            data={
                "title": "Road Closure",
                "content": "Avoid the plaza.",
                "category": "alert",
                "location": "Town Plaza",
                "photos": [(io.BytesIO(b"\x89PNG\r\n\x1a\n"), "notice.png", "image/png")],
                "attachments": [(io.BytesIO(b"%PDF-1.4"), "tips.pdf", "application/pdf")],
            },
            content_type="multipart/form-data",
        )
        feed_response = client.get("/api/feed")
        detail_response = client.get(f"/api/feed/{create_response.json['post']['id']}")

    assert create_response.status_code == 201
    assert feed_response.status_code == 200
    assert detail_response.status_code == 200
    assert feed_response.json["posts"][0]["title"] == "Road Closure"
    assert feed_response.json["posts"][0]["location"] == "Town Plaza"
    assert len(feed_response.json["posts"][0]["photos"]) == 1
    assert len(feed_response.json["posts"][0]["attachments"]) == 1
    assert feed_response.json["posts"][0]["department"]["name"] == "BFP"
    assert detail_response.json["post"]["location"] == "Town Plaza"
    assert len(detail_response.json["post"]["photos"]) == 1
    assert len(detail_response.json["post"]["attachments"]) == 1
    assert fake._db["department_feed_posts"][0]["uploader"] == "dept-fire-user"
    assert len(fake._db["department_feed_storage"]) == 2
    assert any(notification["user_id"] == "citizen-1" for notification in fake._db["notifications"])


def test_verified_department_can_create_text_only_post(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user", email="fire@example.com", role="department"),
        db_rows={
            "users": [{"id": "citizen-1", "role": "citizen", "email": "citizen@example.com"}],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        create_response = client.post(
            "/api/departments/posts",
            headers=auth_header(),
            data={
                "title": "Heat Advisory",
                "content": "Stay hydrated and avoid open flames during peak heat hours.",
                "category": "warning",
                "location": "Central District",
            },
            content_type="multipart/form-data",
        )
        feed_response = client.get("/api/feed")

    assert create_response.status_code == 201
    assert feed_response.status_code == 200
    assert feed_response.json["posts"][0]["title"] == "Heat Advisory"
    assert feed_response.json["posts"][0]["photos"] == []
    assert feed_response.json["posts"][0]["attachments"] == []
    assert "department_feed_storage" not in fake._db or fake._db["department_feed_storage"] == []


def test_verified_department_can_create_assessment_style_post(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user", email="fire@example.com", role="department"),
        db_rows={
            "users": [{"id": "citizen-1", "role": "citizen", "email": "citizen@example.com"}],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
        },
    )
    app = make_app(settings, fake)

    assessment_details = {
        "affected_area": "Barangay Riverside",
        "damage_level": "critical",
        "estimated_casualties": 3,
        "displaced_persons": 14,
        "description": "Flood damage has cut road access.",
    }

    with app.test_client() as client:
        create_response = client.post(
            "/api/departments/posts",
            headers=auth_header(),
            data={
                "title": "Rapid damage assessment bulletin",
                "content": "Field teams are consolidating rescue priorities and relief staging plans.",
                "category": "situational_report",
                "location": "Floodplain",
                "post_kind": "assessment",
                "assessment_details": json.dumps(assessment_details),
            },
            content_type="multipart/form-data",
        )
        feed_response = client.get("/api/feed")

    assert create_response.status_code == 201
    assert feed_response.status_code == 200
    assert feed_response.json["posts"][0]["post_kind"] == "assessment"
    assert feed_response.json["posts"][0]["assessment_details"]["affected_area"] == "Barangay Riverside"
    assert feed_response.json["posts"][0]["assessment_details"]["estimated_casualties"] == 3
    assert fake._db["department_feed_posts"][0]["assessment_details"]["damage_level"] == "critical"


def test_assessment_post_returns_clear_error_when_feed_schema_is_outdated(settings):
    class OutdatedFeedSchemaClient(FakeSupabaseClient):
        def db_insert(self, table, *, data, token=None, use_service_role=False, return_repr=True):
            if table == "department_feed_posts":
                request = httpx.Request("POST", "https://example.supabase.co/rest/v1/department_feed_posts")
                response = httpx.Response(
                    400,
                    request=request,
                    json={
                        "code": "PGRST204",
                        "message": "Could not find the 'post_kind' column of 'department_feed_posts' in the schema cache",
                        "details": None,
                        "hint": None,
                    },
                )
                raise httpx.HTTPStatusError("schema cache miss", request=request, response=response)
            return super().db_insert(
                table,
                data=data,
                token=token,
                use_service_role=use_service_role,
                return_repr=return_repr,
            )

    fake = OutdatedFeedSchemaClient(
        user=FakeUser(id="dept-fire-user", email="fire@example.com", role="department"),
        db_rows={
            "users": [{"id": "citizen-1", "role": "citizen", "email": "citizen@example.com"}],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        create_response = client.post(
            "/api/departments/posts",
            headers=auth_header(),
            data={
                "title": "Rapid damage assessment bulletin",
                "content": "Field teams are consolidating rescue priorities and relief staging plans.",
                "category": "situational_report",
                "location": "Floodplain",
                "post_kind": "assessment",
                "assessment_details": json.dumps(
                    {
                        "affected_area": "Barangay Riverside",
                        "damage_level": "critical",
                        "estimated_casualties": 3,
                        "displaced_persons": 14,
                        "description": "Flood damage has cut road access.",
                    }
                ),
            },
            content_type="multipart/form-data",
        )

    assert create_response.status_code == 500
    assert create_response.json["error"]["code"] == "schema_outdated"
    assert "20260404000000_feed_assessment_posts.sql" in create_response.json["error"]["message"]


def test_authenticated_user_can_create_feed_comment_and_public_can_read_it(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="citizen-1", email="citizen@example.com", role="citizen"),
        db_rows={
            "users": [
                {
                    "id": "citizen-1",
                    "role": "citizen",
                    "email": "citizen@example.com",
                    "full_name": "Citizen One",
                }
            ],
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-fire-user",
                    "title": "Fire Safety",
                    "content": "Keep exits clear.",
                    "category": "safety_tip",
                    "location": "Central Station",
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        create_response = client.post(
            "/api/feed/1/comments",
            headers=auth_header(),
            json={"comment": "We shared this with our block leaders."},
        )
        list_response = client.get("/api/feed/1/comments")
        feed_response = client.get("/api/feed")

    assert create_response.status_code == 201
    assert create_response.json["comment"]["user_name"] == "Citizen One"
    assert list_response.status_code == 200
    assert list_response.json["comments"][0]["comment"] == "We shared this with our block leaders."
    assert feed_response.status_code == 200
    assert feed_response.json["posts"][0]["comment_count"] == 1


def test_authenticated_user_can_toggle_feed_reaction_per_user(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="citizen-1", email="citizen@example.com", role="citizen"),
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-fire-user",
                    "title": "Fire Safety",
                    "content": "Keep exits clear.",
                    "category": "safety_tip",
                    "location": "Central Station",
                    "reaction": 2,
                    "created_at": iso_now_minus(5),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        like_response = client.post("/api/feed/1/reaction", headers=auth_header())
        feed_after_like = client.get("/api/feed", headers=auth_header())

        assert like_response.status_code == 200
        assert like_response.json["post"]["reaction"] == 3
        assert like_response.json["post"]["liked_by_me"] is True
        assert feed_after_like.status_code == 200
        assert feed_after_like.json["posts"][0]["reaction"] == 3
        assert feed_after_like.json["posts"][0]["liked_by_me"] is True
        assert len(fake._db["department_feed_reactions"]) == 1

        unlike_response = client.post("/api/feed/1/reaction", headers=auth_header())
        feed_after_unlike = client.get("/api/feed", headers=auth_header())

    assert unlike_response.status_code == 200
    assert unlike_response.json["post"]["reaction"] == 2
    assert unlike_response.json["post"]["liked_by_me"] is False
    assert feed_after_unlike.status_code == 200
    assert feed_after_unlike.json["posts"][0]["reaction"] == 2
    assert feed_after_unlike.json["posts"][0]["liked_by_me"] is False
    assert fake._db["department_feed_reactions"] == []


def test_verified_department_can_delete_own_post_and_related_feed_rows(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-fire-user",
                    "title": "Road Closure",
                    "content": "Avoid the plaza.",
                    "category": "alert",
                    "location": "Town Plaza",
                    "reaction": 2,
                }
            ],
            "department_feed_storage": [
                {"id": 1, "photos": "https://example.com/photo.png", "attachments": None},
                {"id": 1, "photos": None, "attachments": "https://example.com/file.pdf"},
            ],
            "department_feed_comment": [
                {
                    "comment_id": 11,
                    "post_id": 1,
                    "user_id": "citizen-1",
                    "user_name": "Citizen One",
                    "comment": "Stay safe.",
                }
            ],
            "department_feed_reactions": [
                {"post_id": 1, "user_id": "citizen-1"},
                {"post_id": 1, "user_id": "citizen-2"},
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        delete_response = client.delete("/api/feed/1", headers=auth_header())
        feed_response = client.get("/api/feed")

    assert delete_response.status_code == 200
    assert delete_response.json["deleted"] is True
    assert feed_response.status_code == 200
    assert feed_response.json["posts"] == []
    assert fake._db["department_feed_posts"] == []
    assert fake._db["department_feed_storage"] == []
    assert fake._db["department_feed_comment"] == []
    assert fake._db["department_feed_reactions"] == []


def test_department_cannot_delete_someone_elses_post(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-other-user",
                    "title": "Road Closure",
                    "content": "Avoid the plaza.",
                    "category": "alert",
                    "location": "Town Plaza",
                    "reaction": 0,
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        delete_response = client.delete("/api/feed/1", headers=auth_header())

    assert delete_response.status_code == 403
    assert fake._db["department_feed_posts"][0]["uploader"] == "dept-other-user"


def test_verified_department_can_update_own_post(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-fire-user",
                    "title": "Road Closure",
                    "content": "Avoid the plaza.",
                    "category": "alert",
                    "location": "Town Plaza",
                    "reaction": 0,
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        update_response = client.put(
            "/api/feed/1",
            headers=auth_header(),
            json={
                "title": "Updated Road Closure",
                "content": "Road is now partially open.",
                "category": "update",
                "location": "North Avenue",
            },
        )

    assert update_response.status_code == 200
    assert update_response.json["post"]["title"] == "Updated Road Closure"
    assert update_response.json["post"]["content"] == "Road is now partially open."
    assert update_response.json["post"]["category"] == "update"
    assert update_response.json["post"]["location"] == "North Avenue"


def test_department_cannot_update_someone_elses_post(settings):
    user = FakeUser(id="dept-fire-user", email="fire@example.com", role="department")
    fake = FakeSupabaseClient(
        user=user,
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP",
                    "verification_status": "approved",
                }
            ],
            "department_feed_posts": [
                {
                    "id": 1,
                    "uploader": "dept-other-user",
                    "title": "Road Closure",
                    "content": "Avoid the plaza.",
                    "category": "alert",
                    "location": "Town Plaza",
                    "reaction": 0,
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        update_response = client.put(
            "/api/feed/1",
            headers=auth_header(),
            json={
                "title": "Updated Road Closure",
                "content": "Road is now partially open.",
                "category": "update",
                "location": "North Avenue",
            },
        )

    assert update_response.status_code == 403


def test_notification_endpoints_list_and_mark_items_read(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="citizen-1", email="citizen@example.com", role="citizen"),
        db_rows={
            "notifications": [
                {
                    "id": "notif-1",
                    "user_id": "citizen-1",
                    "title": "One",
                    "message": "One",
                    "type": "report_update",
                    "is_read": False,
                    "created_at": iso_now_minus(10),
                },
                {
                    "id": "notif-2",
                    "user_id": "citizen-1",
                    "title": "Two",
                    "message": "Two",
                    "type": "announcement",
                    "is_read": False,
                    "created_at": iso_now_minus(5),
                },
            ]
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        list_response = client.get("/api/notifications", headers=auth_header())
        mark_one_response = client.put("/api/notifications/notif-1/read", headers=auth_header())
        mark_all_response = client.put("/api/notifications/read-all", headers=auth_header())

    assert list_response.status_code == 200
    assert list_response.json["unread_count"] == 2
    assert mark_one_response.status_code == 200
    assert mark_one_response.json["notification"]["is_read"] is True
    assert mark_all_response.status_code == 200
    assert mark_all_response.json["updated_count"] == 1


def test_notification_endpoint_deletes_owned_item(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="citizen-1", email="citizen@example.com", role="citizen"),
        db_rows={
            "notifications": [
                {
                    "id": "notif-1",
                    "user_id": "citizen-1",
                    "title": "One",
                    "message": "One",
                    "type": "report_update",
                    "is_read": False,
                    "created_at": iso_now_minus(10),
                },
                {
                    "id": "notif-2",
                    "user_id": "citizen-1",
                    "title": "Two",
                    "message": "Two",
                    "type": "announcement",
                    "is_read": False,
                    "created_at": iso_now_minus(5),
                },
            ]
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        delete_response = client.delete("/api/notifications/notif-1", headers=auth_header())
        list_response = client.get("/api/notifications", headers=auth_header())

    assert delete_response.status_code == 200
    assert delete_response.json["deleted"] is True
    assert delete_response.json["notification"]["id"] == "notif-1"
    assert [notification["id"] for notification in fake._db["notifications"]] == ["notif-2"]
    assert [notification["id"] for notification in list_response.json["notifications"]] == ["notif-2"]


def test_department_response_roster_shows_accept_decline_and_pending_states(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user-1", email="one@example.com", role="department"),
        db_rows={
            "departments": [
                {
                    "id": "dept-fire-1",
                    "user_id": "dept-fire-user-1",
                    "type": "fire",
                    "name": "BFP One",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-fire-2",
                    "user_id": "dept-fire-user-2",
                    "type": "fire",
                    "name": "BFP Two",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-fire-3",
                    "user_id": "dept-fire-user-3",
                    "type": "fire",
                    "name": "BFP Three",
                    "verification_status": "approved",
                },
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "accepted",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
            "department_responses": [
                {
                    "id": "response-1",
                    "report_id": "report-fire",
                    "department_id": "dept-fire-1",
                    "action": "accepted",
                    "responded_at": iso_now_minus(4),
                },
                {
                    "id": "response-2",
                    "report_id": "report-fire",
                    "department_id": "dept-fire-2",
                    "action": "declined",
                    "decline_reason": "No water supply",
                    "responded_at": iso_now_minus(3),
                },
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.get(
            "/api/departments/reports/report-fire/responses",
            headers=auth_header(),
        )

    assert response.status_code == 200
    states = {item["department_id"]: item["state"] for item in response.json["responses"]}
    assert states == {
        "dept-fire-1": "accepted",
        "dept-fire-2": "declined",
        "dept-fire-3": "pending",
    }
    declined = next(
        item for item in response.json["responses"] if item["department_id"] == "dept-fire-2"
    )
    assert declined["decline_reason"] == "No water supply"


def test_department_status_updates_progress_from_accepted_to_responding_to_resolved(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="dept-fire-user", email="fire@example.com", role="department"),
        db_rows={
            "departments": [
                {
                    "id": "dept-fire",
                    "user_id": "dept-fire-user",
                    "type": "fire",
                    "name": "BFP Central",
                    "verification_status": "approved",
                }
            ],
            "incident_reports": [
                {
                    "id": "report-fire",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "accepted",
                    "is_escalated": False,
                    "created_at": iso_now_minus(5),
                }
            ],
            "department_responses": [
                {
                    "id": "response-1",
                    "report_id": "report-fire",
                    "department_id": "dept-fire",
                    "action": "accepted",
                    "responded_at": iso_now_minus(4),
                }
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        responding = client.put(
            "/api/departments/reports/report-fire/status",
            headers=auth_header(),
            json={"status": "responding"},
        )
        resolved = client.put(
            "/api/departments/reports/report-fire/status",
            headers=auth_header(),
            json={"status": "resolved"},
        )

    assert responding.status_code == 200
    assert resolved.status_code == 200
    assert fake._db["incident_reports"][0]["status"] == "resolved"
    history_statuses = [row["new_status"] for row in fake._db["report_status_history"]]
    assert history_statuses == ["responding", "resolved"]


def test_municipality_escalated_reports_endpoint_returns_open_escalations_with_summary(settings):
    fake = FakeSupabaseClient(
        user=FakeUser(id="municipality-1", email="admin@example.com", role="municipality"),
        db_rows={
            "departments": [
                {
                    "id": "dept-fire-1",
                    "user_id": "dept-fire-user-1",
                    "type": "fire",
                    "name": "BFP One",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-fire-2",
                    "user_id": "dept-fire-user-2",
                    "type": "fire",
                    "name": "BFP Two",
                    "verification_status": "approved",
                },
                {
                    "id": "dept-disaster",
                    "user_id": "dept-disaster-user",
                    "type": "disaster",
                    "name": "MDRRMO",
                    "verification_status": "approved",
                },
            ],
            "incident_reports": [
                {
                    "id": "report-escalated-open",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "pending",
                    "severity": "critical",
                    "is_escalated": True,
                    "created_at": iso_now_minus(20),
                },
                {
                    "id": "report-escalated-resolved",
                    "reporter_id": "citizen-1",
                    "category": "fire",
                    "status": "resolved",
                    "severity": "medium",
                    "is_escalated": True,
                    "created_at": iso_now_minus(10),
                },
            ],
            "department_responses": [
                {
                    "id": "response-1",
                    "report_id": "report-escalated-open",
                    "department_id": "dept-fire-1",
                    "action": "accepted",
                    "responded_at": iso_now_minus(19),
                },
                {
                    "id": "response-2",
                    "report_id": "report-escalated-open",
                    "department_id": "dept-fire-2",
                    "action": "declined",
                    "decline_reason": "Units unavailable",
                    "responded_at": iso_now_minus(18),
                },
            ],
        },
    )
    app = make_app(settings, fake)

    with app.test_client() as client:
        response = client.get("/api/municipality/reports/escalated", headers=auth_header())

    assert response.status_code == 200
    assert [report["id"] for report in response.json["reports"]] == ["report-escalated-open"]
    assert response.json["reports"][0]["response_summary"] == {
        "accepted": 1,
        "declined": 1,
        "pending": 1,
    }
