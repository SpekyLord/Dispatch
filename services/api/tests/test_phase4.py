"""Phase 4 API tests — mesh ingest, dedup, distress, sync, and token validation."""

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
    """In-memory mock for mesh endpoint tests."""

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

    def db_query(self, table, *, token=None, params=None, use_service_role=False):
        rows = self._db.get(table, [])
        if params:
            # simple filter by message_id or id
            for key, val in params.items():
                if key in ("select", "order", "limit"):
                    continue
                if isinstance(val, str) and val.startswith("eq."):
                    eq_val = val.removeprefix("eq.")
                    rows = [r for r in rows if str(r.get(key, "")) == eq_val]
                if isinstance(val, str) and val.startswith("gte."):
                    pass  # skip time filter in tests
        return rows

    def db_insert(self, table, *, data, token=None, use_service_role=False, return_repr=True):
        if isinstance(data, list):
            for d in data:
                self._inserts.append((table, d))
        else:
            self._inserts.append((table, data))
            # also store in _db for dedup lookups
            self._db.setdefault(table, []).append({"id": f"gen-{len(self._inserts)}", **data})
        if return_repr:
            if isinstance(data, dict):
                return [{"id": f"gen-{len(self._inserts)}", **data}]
            return [{"id": f"gen-{len(self._inserts)}"}]
        return []

    def db_update(
        self,
        table,
        *,
        data,
        params,
        token=None,
        use_service_role=False,
        return_repr=True,
    ):
        self._updates.append((table, data, params))
        # mutate stored rows
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
        if return_repr:
            return [data]
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


def _packet(
    msg_id="pkt-1",
    ptype="INCIDENT_REPORT",
    device="dev-001",
    hops=0,
    max_hops=7,
    payload=None,
):
    return {
        "messageId": msg_id,
        "payloadType": ptype,
        "originDeviceId": device,
        "hopCount": hops,
        "maxHops": max_hops,
        "timestamp": "2026-03-31T00:00:00Z",
        "payload": payload or {"description": "Test incident", "category": "fire"},
        "signature": "test-sig",
    }


# ── Ingest endpoint ──────────────────────────────────────────


class TestMeshIngest:
    def test_ingest_incident_report(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [_packet()]})
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["processed_count"] == 1
            assert data["error_count"] == 0
            assert data["results"][0]["status"] == "processed"

    def test_ingest_missing_body(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", content_type="application/json")
            assert resp.status_code == 400

    def test_ingest_empty_packets(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": []})
            assert resp.status_code == 400

    def test_ingest_invalid_payload_type(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(ptype="INVALID_TYPE")
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["error_count"] == 1
            assert "invalid payloadType" in data["results"][0]["error"]

    def test_ingest_missing_message_id(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(msg_id="")
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["error_count"] == 1

    def test_ingest_hop_limit_exceeded(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(hops=10, max_hops=7)
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["results"][0]["status"] == "error"
            assert "hop limit" in data["results"][0]["error"]


# ── Deduplication ─────────────────────────────────────────────


class TestMeshDedup:
    def test_duplicate_packet_rejected(self, settings):
        """Second ingest of same messageId returns duplicate status."""
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(msg_id="dup-1")
        with app.test_client() as c:
            resp1 = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            assert resp1.get_json()["processed_count"] == 1

            resp2 = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data2 = resp2.get_json()
            assert data2["duplicate_count"] == 1
            assert data2["processed_count"] == 0

    def test_different_message_ids_both_processed(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/mesh/ingest", json={"packets": [_packet(msg_id="a"), _packet(msg_id="b")]}
            )
            data = resp.get_json()
            assert data["processed_count"] == 2


# ── Distress signal ───────────────────────────────────────────


class TestMeshDistress:
    def test_distress_ingested_and_creates_notification(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="sos-1",
            ptype="DISTRESS",
            max_hops=15,
            payload={
                "description": "Trapped under debris",
                "reporter_name": "Juan",
                "contact_info": "09171234567",
                "latitude": 14.5,
                "longitude": 121.0,
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1
            assert data["results"][0]["status"] == "processed"

        # verify distress_signals insert
        distress_inserts = [(t, d) for t, d in fake._inserts if t == "distress_signals"]
        assert len(distress_inserts) == 1
        assert distress_inserts[0][1]["reporter_name"] == "Juan"

        # verify notification created
        notif_inserts = [(t, d) for t, d in fake._inserts if t == "notifications"]
        assert len(notif_inserts) == 1
        assert "SOS" in notif_inserts[0][1]["title"]

    def test_distress_prioritized_over_other_packets(self, settings):
        """DISTRESS packets should be processed before other types."""
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        packets = [
            _packet(msg_id="normal-1", ptype="INCIDENT_REPORT"),
            _packet(
                msg_id="sos-2",
                ptype="DISTRESS",
                max_hops=15,
                payload={
                    "description": "Help",
                    "reporter_name": "",
                    "contact_info": "",
                },
            ),
            _packet(msg_id="normal-2", ptype="INCIDENT_REPORT"),
        ]
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": packets})
            data = resp.get_json()
            # distress should be first in results (prioritized)
            assert data["results"][0]["messageId"] == "sos-2"


# ── Announcement token validation ─────────────────────────────


class TestMeshAnnouncement:
    def test_announcement_without_token_rejected(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {"id": "dept-1", "verification_status": "approved", "user_id": "u1"}
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="ann-1",
            ptype="ANNOUNCEMENT",
            payload={
                "department_id": "dept-1",
                "title": "Test",
                "content": "Body",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["error_count"] == 1
            assert "token" in data["results"][0]["error"].lower()

    def test_announcement_unverified_dept_rejected(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {"id": "dept-2", "verification_status": "pending", "user_id": "u2"}
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="ann-2",
            ptype="ANNOUNCEMENT",
            payload={
                "department_id": "dept-2",
                "offline_verification_token": "some-token",
                "title": "Test",
                "content": "Body",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["error_count"] == 1
            assert "not verified" in data["results"][0]["error"].lower()

    def test_announcement_verified_dept_accepted(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {"id": "dept-3", "verification_status": "approved", "user_id": "u3"}
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="ann-3",
            ptype="ANNOUNCEMENT",
            payload={
                "department_id": "dept-3",
                "offline_verification_token": "valid-token",
                "title": "Alert",
                "content": "Evacuation notice",
                "category": "alert",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1

        post_inserts = [(t, d) for t, d in fake._inserts if t == "posts"]
        assert len(post_inserts) == 1
        assert post_inserts[0][1]["is_mesh_origin"] is True


# ── Status update (last-write-wins) ──────────────────────────


class TestMeshStatusUpdate:
    def test_status_update_applied(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {
                        "id": "rpt-1",
                        "status": "pending",
                        "updated_at": "2026-03-30T00:00:00Z",
                    }
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="su-1",
            ptype="STATUS_UPDATE",
            payload={
                "report_id": "rpt-1",
                "new_status": "accepted",
                "timestamp": "2026-03-31T00:00:00Z",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1

        # verify status history was created
        history_inserts = [(t, d) for t, d in fake._inserts if t == "report_status_history"]
        assert len(history_inserts) == 1
        assert history_inserts[0][1]["new_status"] == "accepted"

    def test_stale_status_update_skipped(self, settings):
        """Older timestamp should not overwrite newer status."""
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {
                        "id": "rpt-2",
                        "status": "responding",
                        "updated_at": "2026-03-31T12:00:00Z",
                    }
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="su-2",
            ptype="STATUS_UPDATE",
            payload={
                "report_id": "rpt-2",
                "new_status": "accepted",
                "timestamp": "2026-03-30T00:00:00Z",  # older
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1
            # no db_update should have happened since timestamp is older
            assert len(fake._updates) == 1  # only the mesh_messages update


# ── Sync-updates endpoint ────────────────────────────────────


class TestMeshSyncUpdates:
    def test_sync_updates_returns_data(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [
                    {"id": "r1", "status": "pending", "updated_at": "2026-03-31T00:00:00Z"},
                ],
                "distress_signals": [],
                "report_status_history": [],
            }
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/mesh/sync-updates")
            assert resp.status_code == 200
            data = resp.get_json()
            assert "report_updates" in data
            assert "distress_signals" in data
            assert "status_history" in data
            assert "synced_at" in data

    def test_sync_updates_with_since_param(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "incident_reports": [],
                "distress_signals": [],
                "report_status_history": [],
            }
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/mesh/sync-updates?since=2026-03-30T00:00:00Z")
            assert resp.status_code == 200


# ── SYNC_ACK generation ──────────────────────────────────────


class TestSyncAcks:
    def test_acks_returned_for_processed_packets(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [_packet(msg_id="ack-test")]})
            data = resp.get_json()
            assert len(data["acks"]) == 1
            assert data["acks"][0]["messageId"] == "ack-test"
            assert data["acks"][0]["synced"] is True
