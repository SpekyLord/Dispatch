"""Phase 4 API tests - mesh ingest, dedup, distress, sync, and token validation."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from dispatch_api.app import create_app
from dispatch_api.config import Settings
from dispatch_api.services.offline_token_service import OfflineTokenService


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
                "offline_verification_token": _offline_token(
                    settings,
                    user_id="u2",
                    role="department",
                    department_id="dept-2",
                ),
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
                "offline_verification_token": _offline_token(
                    settings,
                    user_id="u3",
                    role="department",
                    department_id="dept-3",
                ),
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


class TestMeshSurvivorSignal:
    def test_survivor_signal_ingested(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="sar-1",
            ptype="SURVIVOR_SIGNAL",
            max_hops=15,
            payload={
                "detectionMethod": "BLE_PASSIVE",
                "signalStrengthDbm": -68,
                "estimatedDistanceMeters": 4.2,
                "detectedDeviceIdentifier": "AA:BB:CC:DD:00:00",
                "lastSeenTimestamp": "2026-03-31T00:00:00Z",
                "nodeLocation": {"lat": 14.5, "lng": 121.0, "accuracyMeters": 8},
                "confidence": 0.88,
                "acousticPatternMatched": "none",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1
            assert data["results"][0]["status"] == "processed"

        survivor_inserts = [(t, d) for t, d in fake._inserts if t == "survivor_signals"]
        assert len(survivor_inserts) == 1
        assert survivor_inserts[0][1]["detection_method"] == "BLE_PASSIVE"

    def test_survivor_signal_prioritized_over_reports(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        packets = [
            _packet(msg_id="normal-incident", ptype="INCIDENT_REPORT"),
            _packet(
                msg_id="priority-sar",
                ptype="SURVIVOR_SIGNAL",
                max_hops=15,
                payload={
                    "detectionMethod": "SOS_BEACON",
                    "signalStrengthDbm": -52,
                    "estimatedDistanceMeters": 2.1,
                    "detectedDeviceIdentifier": "AA:BB:CC:DD:00:00",
                    "lastSeenTimestamp": "2026-03-31T00:00:00Z",
                    "nodeLocation": {"lat": 14.5, "lng": 121.0, "accuracyMeters": 5},
                    "confidence": 1.0,
                    "acousticPatternMatched": "none",
                },
            ),
        ]
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": packets})
            data = resp.get_json()
            assert data["results"][0]["messageId"] == "priority-sar"


class TestSurvivorSignalRoutes:
    def test_list_survivor_signals_filters_active_and_bbox(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="dept-1", email="dept@test.com", role="department"),
            db_rows={
                "survivor_signals": [
                    {
                        "id": "sig-1",
                        "detection_method": "BLE_PASSIVE",
                        "resolved": False,
                        "node_location": {"lat": 14.5, "lng": 121.0},
                        "last_seen_timestamp": "2026-03-31T00:10:00Z",
                    },
                    {
                        "id": "sig-2",
                        "detection_method": "WIFI_PROBE",
                        "resolved": True,
                        "node_location": {"lat": 9.0, "lng": 122.0},
                        "last_seen_timestamp": "2026-03-31T00:10:00Z",
                    },
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/survivor-signals?status=active&detection_method=BLE_PASSIVE&min_lat=14&max_lat=15&min_lng=120&max_lng=122",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["count"] == 1
            assert data["survivor_signals"][0]["id"] == "sig-1"

    def test_resolve_survivor_signal(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="muni-1", email="admin@test.com", role="municipality"),
            db_rows={
                "survivor_signals": [
                    {
                        "id": "sig-3",
                        "resolved": False,
                        "resolution_note": "",
                    }
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.put(
                "/api/mesh/survivor-signals/sig-3/resolve",
                headers={"Authorization": "Bearer valid-token"},
                json={"note": "Located and handed off to responders."},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["survivor_signal"]["resolved"] is True

        survivor_updates = [update for update in fake._updates if update[0] == "survivor_signals"]
        assert len(survivor_updates) == 1
        assert survivor_updates[0][1]["resolved"] is True
        assert survivor_updates[0][1]["resolution_note"] == "Located and handed off to responders."


class TestMeshLocationTrail:
    def test_location_beacon_ingest_persists_device_trail(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="trail-1",
            ptype="LOCATION_BEACON",
            payload={
                "deviceFingerprint": "AA:BB:CC:DD:00:00",
                "displayName": "Survivor A",
                "lat": 14.612,
                "lng": 121.004,
                "accuracyMeters": 8,
                "batteryPct": 34,
                "appState": "sos_active",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert resp.status_code == 200
            assert data["processed_count"] == 1

        trail_inserts = [(t, d) for t, d in fake._inserts if t == "device_location_trail"]
        assert len(trail_inserts) == 1
        assert trail_inserts[0][1]["device_fingerprint"] == "AA:BB:CC:DD:00:00"
        assert trail_inserts[0][1]["app_state"] == "sos_active"

    def test_trail_route_returns_ordered_points(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="dept-1", email="dept@test.com", role="department"),
            db_rows={
                "device_location_trail": [
                    {
                        "id": "trail-row-1",
                        "message_id": "trail-msg-1",
                        "device_fingerprint": "AA:BB:CC:DD:00:00",
                        "display_name": "Survivor A",
                        "location": {"lat": 14.611, "lng": 121.003},
                        "accuracy_meters": 9,
                        "battery_pct": 33,
                        "app_state": "foreground",
                        "recorded_at": "2026-03-31T03:00:00Z",
                    },
                    {
                        "id": "trail-row-2",
                        "message_id": "trail-msg-2",
                        "device_fingerprint": "AA:BB:CC:DD:00:00",
                        "display_name": "Survivor A",
                        "location": {"lat": 14.612, "lng": 121.004},
                        "accuracy_meters": 8,
                        "battery_pct": 31,
                        "app_state": "sos_active",
                        "recorded_at": "2026-03-31T03:02:00Z",
                    },
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/trail/AA%3ABB%3ACC%3ADD%3A00%3A00",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["count"] == 2
            assert data["points"][0]["coordinates"] == [121.003, 14.611]
            assert data["last_seen"]["app_state"] == "sos_active"

    def test_last_seen_route_returns_latest_active_beacon_per_device(self, settings):
        recent = (datetime.now(tz=UTC) - timedelta(minutes=4)).isoformat()
        fresher = (datetime.now(tz=UTC) - timedelta(minutes=2)).isoformat()
        stale = (datetime.now(tz=UTC) - timedelta(minutes=40)).isoformat()
        fake = FakeSupabaseClient(
            user=FakeUser(id="muni-1", email="admin@test.com", role="municipality"),
            db_rows={
                "device_location_trail": [
                    {
                        "id": "trail-last-1",
                        "message_id": "trail-last-msg-1",
                        "device_fingerprint": "device-1",
                        "display_name": "Responder One",
                        "location": {"lat": 14.615, "lng": 121.002},
                        "battery_pct": 56,
                        "app_state": "foreground",
                        "recorded_at": recent,
                    },
                    {
                        "id": "trail-last-2",
                        "message_id": "trail-last-msg-2",
                        "device_fingerprint": "device-1",
                        "display_name": "Responder One",
                        "location": {"lat": 14.616, "lng": 121.003},
                        "battery_pct": 54,
                        "app_state": "background",
                        "recorded_at": fresher,
                    },
                    {
                        "id": "trail-stale-1",
                        "message_id": "trail-stale-msg-1",
                        "device_fingerprint": "device-2",
                        "display_name": "Old device",
                        "location": {"lat": 14.5, "lng": 121.1},
                        "battery_pct": 10,
                        "app_state": "background",
                        "recorded_at": stale,
                    },
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/last-seen",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["count"] == 1
            assert data["devices"][0]["device_fingerprint"] == "device-1"
            assert data["devices"][0]["battery_pct"] == 54
            assert data["devices"][0]["coordinates"] == [121.003, 14.616]


class TestMeshTopologyIngest:
    def test_ingest_topology_snapshot_without_packets(self, settings):
        fake = FakeSupabaseClient()
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.post(
                "/api/mesh/ingest",
                json={
                    "topologySnapshot": {
                        "gatewayDeviceId": "gw-1",
                        "capturedAt": "2026-03-31T02:30:00Z",
                        "nodes": [
                            {
                                "nodeDeviceId": "gw-1",
                                "role": "gateway",
                                "lat": 14.601,
                                "lng": 120.982,
                                "peerCount": 5,
                                "queueDepth": 1,
                                "displayName": "Gateway Alpha",
                            },
                            {
                                "nodeDeviceId": "relay-2",
                                "role": "relay",
                                "lat": 14.603,
                                "lng": 120.985,
                                "peerCount": 2,
                                "queueDepth": 3,
                                "operatorRole": "department",
                                "departmentName": "MDRRMO Team 2",
                            },
                        ],
                    }
                },
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["topology_ingested_count"] == 2
            assert data["processed_count"] == 0

        topology_inserts = [
            (table, row) for table, row in fake._inserts if table == "mesh_topology_nodes"
        ]
        assert len(topology_inserts) == 2
        assert topology_inserts[0][1]["gateway_device_id"] == "gw-1"


class TestMeshTopologyRoutes:
    def test_topology_route_returns_active_nodes_and_responder_subset(self, settings):
        fresh_gateway_seen = (datetime.now(tz=UTC) - timedelta(minutes=2)).isoformat()
        fresh_responder_seen = (datetime.now(tz=UTC) - timedelta(minutes=1)).isoformat()
        stale_seen = (datetime.now(tz=UTC) - timedelta(minutes=45)).isoformat()
        fake = FakeSupabaseClient(
            user=FakeUser(id="muni-1", email="admin@test.com", role="municipality"),
            db_rows={
                "mesh_topology_nodes": [
                    {
                        "id": "node-1",
                        "node_device_id": "gw-1",
                        "node_role": "gateway",
                        "node_location": {"lat": 14.6, "lng": 120.98},
                        "peer_count": 5,
                        "queue_depth": 1,
                        "display_name": "Gateway Alpha",
                        "operator_role": "municipality",
                        "department_id": None,
                        "department_name": "",
                        "is_responder": False,
                        "last_seen_at": fresh_gateway_seen,
                        "last_sync_at": fresh_gateway_seen,
                    },
                    {
                        "id": "node-2",
                        "node_device_id": "relay-2",
                        "node_role": "relay",
                        "node_location": {"lat": 14.61, "lng": 120.99},
                        "peer_count": 3,
                        "queue_depth": 0,
                        "display_name": "Responder Bravo",
                        "operator_role": "department",
                        "department_id": "dept-2",
                        "department_name": "Fire Station 2",
                        "is_responder": True,
                        "last_seen_at": fresh_responder_seen,
                        "last_sync_at": fresh_gateway_seen,
                    },
                    {
                        "id": "node-3",
                        "node_device_id": "old-node",
                        "node_role": "origin",
                        "node_location": {"lat": 14.55, "lng": 120.95},
                        "peer_count": 1,
                        "queue_depth": 0,
                        "display_name": "Old snapshot",
                        "operator_role": "citizen",
                        "department_id": None,
                        "department_name": "",
                        "is_responder": False,
                        "last_seen_at": stale_seen,
                        "last_sync_at": stale_seen,
                    },
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get("/api/mesh/topology", headers={"Authorization": "Bearer valid-token"})
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["count"] == 2
            assert data["responder_count"] == 1
            assert data["nodes"][0]["geometry"]["type"] == "Point"
            assert data["nodes"][0]["coordinates"] == [120.98, 14.6]
            assert data["responders"][0]["department_name"] == "Fire Station 2"

    def test_survivor_signals_include_geojson_coordinates(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="dept-1", email="dept@test.com", role="department"),
            db_rows={
                "survivor_signals": [
                    {
                        "id": "sig-geo-1",
                        "detection_method": "BLE_PASSIVE",
                        "resolved": False,
                        "node_location": {"lat": 14.7, "lng": 121.01},
                        "estimated_distance_meters": 7.5,
                        "confidence": 0.91,
                        "last_seen_timestamp": "2026-03-31T02:25:00+00:00",
                    }
                ]
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/survivor-signals",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["survivor_signals"][0]["coordinates"] == [121.01, 14.7]
            assert data["survivor_signals"][0]["geometry"]["type"] == "Point"
            assert data["survivor_signals"][0]["accuracy_radius_meters"] == 7.5


class TestMeshSurvivorResolveStatusUpdate:
    def test_survivor_resolve_status_update_applied(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "survivor_signals": [
                    {
                        "id": "sig-res-1",
                        "message_id": "sar-msg-1",
                        "resolved": False,
                        "resolved_at": None,
                        "resolution_note": "",
                    }
                ]
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="sar-resolve-1",
            ptype="STATUS_UPDATE",
            max_hops=15,
            payload={
                "targetType": "SURVIVOR_SIGNAL",
                "survivorMessageId": "sar-msg-1",
                "signalId": "sig-res-1",
                "resolved": True,
                "resolutionNote": "Located under the north stairwell.",
                "resolvedByUserId": "dept-user-1",
                "timestamp": "2026-03-31T04:15:00Z",
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["processed_count"] == 1
            assert data["results"][0]["linkedRecordId"] == "sig-res-1"

        survivor_updates = [update for update in fake._updates if update[0] == "survivor_signals"]
        assert len(survivor_updates) == 1
        assert survivor_updates[0][1]["resolved"] is True
        assert survivor_updates[0][1]["resolution_note"] == "Located under the north stairwell."
        assert survivor_updates[0][1]["resolved_by"] == "dept-user-1"


def _offline_token(
    settings: Settings,
    *,
    user_id: str,
    role: str,
    department_id: str | None = None,
    ttl_days: int = 30,
) -> str:
    return OfflineTokenService(
        secret=settings.supabase_service_role_key,
        ttl_days=ttl_days,
    ).issue_token(user_id=user_id, role=role, department_id=department_id)


class TestMeshCommunicationsIngest:
    def test_mesh_message_ingested_and_direct_notification_created(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "users": [{"id": "citizen-recipient"}],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="mesh-msg-1",
            ptype="MESH_MESSAGE",
            payload={
                "threadId": "00000000-0000-4000-8000-000000000101",
                "recipientScope": "direct",
                "recipientIdentifier": "citizen-recipient",
                "body": "Evacuate northbound through the school gate.",
                "authorDisplayName": "Responder A",
                "authorRole": "citizen",
                "authorOfflineToken": _offline_token(
                    settings,
                    user_id="citizen-author",
                    role="citizen",
                ),
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1
            assert data["results"][0]["status"] == "processed"

        message_inserts = [(t, d) for t, d in fake._inserts if t == "mesh_comms_messages"]
        assert len(message_inserts) == 1
        assert message_inserts[0][1]["recipient_scope"] == "direct"
        assert message_inserts[0][1]["author_identifier"] == "citizen-author"

        notif_inserts = [(t, d) for t, d in fake._inserts if t == "notifications"]
        assert len(notif_inserts) == 1
        assert notif_inserts[0][1]["user_id"] == "citizen-recipient"
        assert notif_inserts[0][1]["title"] == "Direct mesh message"

    def test_mesh_post_rejects_expired_offline_token(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {"id": "dept-1", "verification_status": "approved", "user_id": "dept-user-1"}
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="mesh-post-expired",
            ptype="MESH_POST",
            payload={
                "postId": "00000000-0000-4000-8000-000000000201",
                "category": "alert",
                "title": "Bridge closure",
                "body": "Bridge is unsafe for crossing.",
                "authorDepartmentId": "dept-1",
                "authorOfflineToken": _offline_token(
                    settings,
                    user_id="dept-user-1",
                    role="department",
                    department_id="dept-1",
                    ttl_days=-1,
                ),
                "attachmentRefs": [],
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["error_count"] == 1
            assert "expired" in data["results"][0]["error"].lower()

    def test_mesh_post_persists_mesh_originated_flag(self, settings):
        fake = FakeSupabaseClient(
            db_rows={
                "departments": [
                    {"id": "dept-2", "verification_status": "approved", "user_id": "dept-user-2"}
                ],
            }
        )
        app = make_app(settings, fake)
        pkt = _packet(
            msg_id="mesh-post-1",
            ptype="MESH_POST",
            payload={
                "postId": "00000000-0000-4000-8000-000000000202",
                "category": "warning",
                "title": "River surge watch",
                "body": "Move equipment away from the floodplain.",
                "authorDepartmentId": "dept-2",
                "authorOfflineToken": _offline_token(
                    settings,
                    user_id="dept-user-2",
                    role="department",
                    department_id="dept-2",
                ),
                "attachmentRefs": ["mesh://photo-1"],
            },
        )
        with app.test_client() as c:
            resp = c.post("/api/mesh/ingest", json={"packets": [pkt]})
            data = resp.get_json()
            assert data["processed_count"] == 1

        post_inserts = [(t, d) for t, d in fake._inserts if t == "posts"]
        assert len(post_inserts) == 1
        assert post_inserts[0][1]["mesh_originated"] is True
        assert post_inserts[0][1]["is_mesh_origin"] is True


class TestMeshMessageRoutes:
    def test_get_mesh_messages_filters_visible_threads_for_direct_recipient(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="citizen-recipient", email="citizen@test.com", role="citizen"),
            db_rows={
                "mesh_comms_messages": [
                    {
                        "id": "msg-1",
                        "thread_id": "00000000-0000-4000-8000-000000000301",
                        "message_id": "mesh-msg-visible-1",
                        "recipient_scope": "broadcast",
                        "recipient_identifier": None,
                        "body": "Stay tuned to local advisories.",
                        "author_display_name": "Ops Center",
                        "author_role": "department",
                        "author_identifier": "dept-user-1",
                        "created_at": "2026-03-31T05:00:00Z",
                    },
                    {
                        "id": "msg-2",
                        "thread_id": "00000000-0000-4000-8000-000000000302",
                        "message_id": "mesh-msg-visible-2",
                        "recipient_scope": "direct",
                        "recipient_identifier": "citizen-recipient",
                        "body": "Nearest evacuation jeep is on Rizal Ave.",
                        "author_display_name": "Responder B",
                        "author_role": "department",
                        "author_identifier": "dept-user-2",
                        "created_at": "2026-03-31T05:01:00Z",
                    },
                    {
                        "id": "msg-3",
                        "thread_id": "00000000-0000-4000-8000-000000000303",
                        "message_id": "mesh-msg-hidden",
                        "recipient_scope": "direct",
                        "recipient_identifier": "another-user",
                        "body": "Hidden thread",
                        "author_display_name": "Responder C",
                        "author_role": "department",
                        "author_identifier": "dept-user-3",
                        "created_at": "2026-03-31T05:02:00Z",
                    },
                ],
                "posts": [
                    {
                        "id": "mesh-post-web-1",
                        "title": "Mesh advisory",
                        "mesh_originated": True,
                        "created_at": "2026-03-31T05:03:00Z",
                    }
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/messages",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert [message["id"] for message in data["messages"]] == ["msg-1", "msg-2"]
            assert len(data["mesh_posts"]) == 1

    def test_get_mesh_messages_returns_thread_history(self, settings):
        fake = FakeSupabaseClient(
            user=FakeUser(id="dept-user-1", email="dept@test.com", role="department"),
            db_rows={
                "departments": [{"id": "dept-1", "user_id": "dept-user-1"}],
                "mesh_comms_messages": [
                    {
                        "id": "msg-thread-1",
                        "thread_id": "00000000-0000-4000-8000-000000000401",
                        "message_id": "mesh-thread-1",
                        "recipient_scope": "department",
                        "recipient_identifier": "dept-1",
                        "body": "Stage water rescue gear at checkpoint bravo.",
                        "author_display_name": "Command",
                        "author_role": "department",
                        "author_identifier": "dept-user-1",
                        "author_department_id": "dept-1",
                        "created_at": "2026-03-31T05:10:00Z",
                    },
                    {
                        "id": "msg-thread-2",
                        "thread_id": "00000000-0000-4000-8000-000000000499",
                        "message_id": "mesh-thread-2",
                        "recipient_scope": "broadcast",
                        "recipient_identifier": None,
                        "body": "This belongs to another thread.",
                        "author_display_name": "Ops",
                        "author_role": "department",
                        "author_identifier": "dept-user-9",
                        "created_at": "2026-03-31T05:11:00Z",
                    },
                ],
            },
        )
        app = make_app(settings, fake)
        with app.test_client() as c:
            resp = c.get(
                "/api/mesh/messages?threadId=00000000-0000-4000-8000-000000000401",
                headers={"Authorization": "Bearer valid-token"},
            )
            assert resp.status_code == 200
            data = resp.get_json()
            assert data["count"] == 1
            assert data["messages"][0]["id"] == "msg-thread-1"
