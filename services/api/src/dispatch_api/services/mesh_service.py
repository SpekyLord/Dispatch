"""Mesh gateway service - idempotent ingest, dedup, sync, topology, and survivor workflows."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import math
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from dispatch_api.errors import ApiError
from dispatch_api.services.offline_token_service import OfflineTokenService
from dispatch_api.validation import sanitize_postgrest_value

log = logging.getLogger(__name__)

VALID_PAYLOAD_TYPES = {
    "INCIDENT_REPORT",
    "ANNOUNCEMENT",
    "DISTRESS",
    "SURVIVOR_SIGNAL",
    "LOCATION_BEACON",
    "STATUS_UPDATE",
    "SYNC_ACK",
    "MESH_MESSAGE",
    "MESH_POST",
}

MAX_HOPS_DEFAULT = 7
MAX_HOPS_DISTRESS = 15
MAX_HOPS_SURVIVOR_SIGNAL = 15
TOPOLOGY_STALE_AFTER_MINUTES = 5
TOPOLOGY_ACTIVE_WINDOW_MINUTES = 30
LOCATION_BEACON_ACTIVE_WINDOW_MINUTES = 30

VALID_RECIPIENT_SCOPES = {"broadcast", "department", "direct"}
VALID_MESSAGE_AUTHOR_ROLES = {"citizen", "department", "anonymous"}


class MeshService:
    def __init__(self, client, offline_token_service: OfflineTokenService | None = None) -> None:
        self.client = client
        self.offline_token_service = offline_token_service

    # -- batch ingest from a gateway device --
    def ingest_packets(self, packets: list[dict[str, Any]]) -> list[dict[str, Any]]:
        return [self._process_single(pkt) for pkt in packets]

    def upsert_topology_snapshot(self, snapshot: dict[str, Any]) -> int:
        captured_at = snapshot.get("capturedAt") or datetime.now(tz=UTC).isoformat()
        gateway_device_id = snapshot.get("gatewayDeviceId") or ""
        nodes = snapshot.get("nodes") or []
        gateway_node = snapshot.get("gateway")

        if not isinstance(nodes, list):
            raise ApiError(
                "topologySnapshot.nodes must be an array.",
                code="validation_error",
            )

        if isinstance(gateway_node, dict):
            nodes = [gateway_node, *nodes]

        ingested = 0
        for node in nodes:
            if not isinstance(node, dict):
                continue

            row = _build_topology_row(node, gateway_device_id, captured_at)
            if row is None:
                continue

            existing = self.client.db_query(
                "mesh_topology_nodes",
                params={"select": "id", "node_device_id": f"eq.{row['node_device_id']}"},
                use_service_role=True,
            )
            if existing:
                self.client.db_update(
                    "mesh_topology_nodes",
                    data=row,
                    params={"node_device_id": f"eq.{row['node_device_id']}"},
                    use_service_role=True,
                    return_repr=False,
                )
            else:
                self.client.db_insert(
                    "mesh_topology_nodes",
                    data=row,
                    use_service_role=True,
                    return_repr=False,
                )
            ingested += 1

        return ingested

    def list_topology_nodes(self, *, viewer_role: str | None) -> dict[str, Any]:
        rows = self.client.db_query(
            "mesh_topology_nodes",
            params={"select": "*", "order": "last_seen_at.desc", "limit": "300"},
            use_service_role=True,
        )

        now = datetime.now(tz=UTC)
        nodes: list[dict[str, Any]] = []
        responders: list[dict[str, Any]] = []
        for row in rows:
            formatted = _format_topology_node(row, now)
            if formatted is None:
                continue
            nodes.append(formatted)
            if viewer_role == "municipality" and _is_responder_node(formatted):
                responders.append(formatted)

        return {
            "nodes": nodes,
            "responders": responders,
            "synced_at": now.isoformat(),
        }

    # -- pull server-side updates for gateway rebroadcast --
    def get_sync_updates(self, *, since: str | None = None) -> dict[str, Any]:
        safe_since = sanitize_postgrest_value(since)
        base_params: dict[str, str] = {"order": "updated_at.desc", "limit": "100"}
        if safe_since:
            base_params["updated_at"] = f"gte.{safe_since}"

        reports = self.client.db_query(
            "incident_reports",
            params={"select": "id,status,updated_at", **base_params},
            use_service_role=True,
        )

        distress_params: dict[str, str] = {
            "select": "*",
            "order": "created_at.desc",
            "limit": "50",
        }
        if safe_since:
            distress_params["created_at"] = f"gte.{safe_since}"
        distress = self.client.db_query(
            "distress_signals", params=distress_params, use_service_role=True
        )

        survivor_params: dict[str, str] = {
            "select": "*",
            "order": "created_at.desc",
            "limit": "100",
        }
        if safe_since:
            survivor_params["created_at"] = f"gte.{safe_since}"
        survivor_rows = self.client.db_query(
            "survivor_signals", params=survivor_params, use_service_role=True
        )

        history_params: dict[str, str] = {
            "select": "*",
            "order": "created_at.desc",
            "limit": "100",
        }
        if safe_since:
            history_params["created_at"] = f"gte.{safe_since}"
        history = self.client.db_query(
            "report_status_history", params=history_params, use_service_role=True
        )
        mesh_posts = [
            row
            for row in self.client.db_query(
                "posts",
                params={"select": "*", "order": "created_at.desc", "limit": "50"},
                use_service_role=True,
            )
            if row.get("is_mesh_origin")
        ]

        return {
            "report_updates": reports,
            "distress_signals": distress,
            "survivor_signals": [_decorate_survivor_signal(row) for row in survivor_rows],
            "status_history": history,
            "mesh_posts": mesh_posts,
            "synced_at": datetime.now(tz=UTC).isoformat(),
        }

    def list_survivor_signals(
        self,
        *,
        status: str | None = None,
        detection_method: str | None = None,
        time_start: str | None = None,
        time_end: str | None = None,
        min_lat: float | None = None,
        max_lat: float | None = None,
        min_lng: float | None = None,
        max_lng: float | None = None,
    ) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "survivor_signals",
            params={"select": "*", "order": "created_at.desc", "limit": "200"},
            use_service_role=True,
        )

        if status == "active":
            rows = [row for row in rows if not row.get("resolved", False)]
        elif status == "resolved":
            rows = [row for row in rows if row.get("resolved", False)]

        if detection_method:
            rows = [
                row
                for row in rows
                if (row.get("detection_method") or "").upper() == detection_method.upper()
            ]

        if time_start:
            rows = [
                row
                for row in rows
                if (row.get("last_seen_timestamp") or row.get("created_at") or "") >= time_start
            ]
        if time_end:
            rows = [
                row
                for row in rows
                if (row.get("last_seen_timestamp") or row.get("created_at") or "") <= time_end
            ]

        if None not in (min_lat, max_lat, min_lng, max_lng):
            rows = [
                row
                for row in rows
                if _location_in_bbox(
                    row.get("node_location") or {}, min_lat, max_lat, min_lng, max_lng
                )
            ]

        return [_decorate_survivor_signal(row) for row in rows]

    def resolve_survivor_signal(
        self,
        signal_id: str,
        *,
        resolved_by: str,
        note: str,
    ) -> dict[str, Any]:
        existing = self.client.db_query(
            "survivor_signals",
            params={"select": "*", "id": f"eq.{signal_id}"},
            use_service_role=True,
        )
        if not existing:
            raise ApiError("Survivor signal not found.", code="not_found")

        rows = self.client.db_update(
            "survivor_signals",
            data={
                "resolved": True,
                "resolved_by": resolved_by,
                "resolved_at": datetime.now(tz=UTC).isoformat(),
                "resolution_note": note.strip(),
            },
            params={"id": f"eq.{signal_id}"},
            use_service_role=True,
        )
        resolved_row = rows[0] if rows else existing[0]
        return _decorate_survivor_signal(resolved_row)

    def list_device_trail(
        self,
        device_fingerprint: str,
        *,
        time_start: str | None = None,
        time_end: str | None = None,
        limit: int = 240,
    ) -> list[dict[str, Any]]:
        rows = self.client.db_query(
            "device_location_trail",
            params={
                "select": "*",
                "device_fingerprint": f"eq.{device_fingerprint}",
                "order": "recorded_at.desc",
                "limit": str(limit),
            },
            use_service_role=True,
        )

        if time_start:
            rows = [row for row in rows if (row.get("recorded_at") or "") >= time_start]
        if time_end:
            rows = [row for row in rows if (row.get("recorded_at") or "") <= time_end]

        rows.sort(key=lambda row: str(row.get("recorded_at") or ""))
        return [_decorate_location_trail_point(row) for row in rows]

    def list_last_seen_devices(self) -> list[dict[str, Any]]:
        active_cutoff = datetime.now(tz=UTC) - timedelta(
            minutes=LOCATION_BEACON_ACTIVE_WINDOW_MINUTES
        )
        rows = self.client.db_query(
            "device_location_trail",
            params={
                "select": "*",
                "recorded_at": f"gte.{active_cutoff.isoformat()}",
                "order": "recorded_at.desc",
                "limit": "1200",
            },
            use_service_role=True,
        )
        rows.sort(key=lambda row: str(row.get("recorded_at") or ""), reverse=True)
        latest_by_device: dict[str, dict[str, Any]] = {}
        for row in rows:
            device_fingerprint = str(row.get("device_fingerprint") or "").strip()
            recorded_at = _parse_iso_datetime(row.get("recorded_at"))
            if not device_fingerprint or recorded_at is None or recorded_at < active_cutoff:
                continue
            if device_fingerprint not in latest_by_device:
                latest_by_device[device_fingerprint] = row

        return [_decorate_location_trail_point(row) for row in latest_by_device.values()]

    def upsert_citizen_nearby_presence(
        self,
        *,
        user_id: str,
        display_name: str,
        latitude: float,
        longitude: float,
        accuracy_meters: float | None,
        last_seen_at: str | None = None,
    ) -> dict[str, Any]:
        recorded_at = _parse_iso_datetime(last_seen_at) or datetime.now(tz=UTC)
        row = {
            "user_id": user_id,
            "display_name": display_name.strip(),
            "lat": latitude,
            "lng": longitude,
            "location": {
                "lat": latitude,
                "lng": longitude,
            },
            "accuracy_meters": accuracy_meters,
            "last_seen_at": recorded_at.isoformat(),
        }
        existing = self.client.db_query(
            "citizen_nearby_presence",
            params={"select": "*", "user_id": f"eq.{user_id}"},
            use_service_role=True,
        )
        if existing:
            rows = self.client.db_update(
                "citizen_nearby_presence",
                data=row,
                params={"user_id": f"eq.{user_id}"},
                use_service_role=True,
            )
            persisted = rows[0] if rows else {**existing[0], **row}
        else:
            rows = self.client.db_insert(
                "citizen_nearby_presence",
                data=row,
                use_service_role=True,
            )
            persisted = rows[0] if rows else row

        return _decorate_citizen_nearby_presence(persisted)

    def list_nearby_citizen_presence(
        self,
        *,
        viewer_user_id: str,
        center_lat: float,
        center_lng: float,
        radius_meters: float = 15,
        freshness_seconds: int = 15,
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        freshness_cutoff = datetime.now(tz=UTC) - timedelta(seconds=freshness_seconds)
        min_lat, max_lat, min_lng, max_lng = _bounding_box_for_radius_meters(
            center_lat,
            center_lng,
            radius_meters,
        )
        rows = self.client.db_query(
            "citizen_nearby_presence",
            params={
                "select": "*",
                "last_seen_at": f"gte.{freshness_cutoff.isoformat()}",
                "and": (
                    f"(lat.gte.{min_lat},lat.lte.{max_lat},"
                    f"lng.gte.{min_lng},lng.lte.{max_lng})"
                ),
                "order": "last_seen_at.desc",
                "limit": str(limit),
            },
            use_service_role=True,
        )

        nearby_rows: list[dict[str, Any]] = []
        for row in rows:
            if str(row.get("user_id") or "") == viewer_user_id:
                continue
            last_seen_at = _parse_iso_datetime(row.get("last_seen_at"))
            if last_seen_at is None or last_seen_at < freshness_cutoff:
                continue

            lat, lng = _extract_presence_coordinates(row)
            if lat is None or lng is None:
                continue
            if not (min_lat <= lat <= max_lat and min_lng <= lng <= max_lng):
                continue

            distance_meters = _distance_between_points_meters(
                center_lat,
                center_lng,
                lat,
                lng,
            )
            if distance_meters > radius_meters:
                continue

            nearby_rows.append(
                _decorate_citizen_nearby_presence(
                    row,
                    distance_meters=distance_meters,
                )
            )

        nearby_rows.sort(key=lambda row: float(row.get("distance_meters") or 0))
        return nearby_rows

    def list_messages(
        self,
        *,
        thread_id: str | None = None,
        viewer_user_id: str | None = None,
        viewer_role: str | None = None,
        viewer_department_id: str | None = None,
    ) -> list[dict[str, Any]]:
        params: dict[str, str] = {"select": "*", "order": "created_at.asc", "limit": "200"}
        safe_thread_id = sanitize_postgrest_value(thread_id)
        if safe_thread_id:
            params["thread_id"] = f"eq.{safe_thread_id}"

        rows = self.client.db_query(
            "mesh_comms_messages",
            params=params,
            use_service_role=True,
        )
        return [
            _serialize_mesh_message(row)
            for row in rows
            if self._viewer_can_access_message(
                row,
                viewer_user_id=viewer_user_id,
                viewer_role=viewer_role,
                viewer_department_id=viewer_department_id,
            )
        ]

    def list_mesh_posts(self) -> list[dict[str, Any]]:
        return self.client.db_query(
            "posts",
            params={
                "select": "*",
                "is_mesh_origin": "eq.true",
                "order": "created_at.desc",
                "limit": "50",
            },
            use_service_role=True,
        )

    def _viewer_can_access_message(
        self,
        row: dict[str, Any],
        *,
        viewer_user_id: str | None,
        viewer_role: str | None,
        viewer_department_id: str | None,
    ) -> bool:
        scope = str(row.get("recipient_scope") or "broadcast").lower()
        if scope == "broadcast":
            return True
        if scope == "department":
            return viewer_role == "municipality" or (
                viewer_role == "department"
                and viewer_department_id is not None
                and str(row.get("recipient_identifier") or "") == str(viewer_department_id)
            )
        if scope == "direct":
            participants = {
                str(row.get("author_identifier") or ""),
                str(row.get("recipient_identifier") or ""),
            }
            return viewer_role == "municipality" or (
                viewer_user_id is not None and str(viewer_user_id) in participants
            )
        return False

    # -- process one mesh packet --
    def _process_single(self, pkt: dict[str, Any]) -> dict[str, Any]:
        message_id = pkt.get("messageId", "")
        payload_type = pkt.get("payloadType", "")
        origin_device = pkt.get("originDeviceId", "")
        hop_count = pkt.get("hopCount", 0)
        max_hops = pkt.get("maxHops", MAX_HOPS_DEFAULT)
        payload = pkt.get("payload", {})
        signature = pkt.get("signature", "")

        if not message_id:
            return _error_result(message_id, "missing messageId")
        if payload_type not in VALID_PAYLOAD_TYPES:
            return _error_result(message_id, f"invalid payloadType: {payload_type}")
        if hop_count > max_hops:
            return _error_result(message_id, "hop limit exceeded")

        existing = self.client.db_query(
            "mesh_messages",
            params={
                "select": "id,processing_state,linked_record_id",
                "message_id": f"eq.{message_id}",
            },
            use_service_role=True,
        )
        if existing:
            return {
                "messageId": message_id,
                "status": "duplicate",
                "linkedRecordId": existing[0].get("linked_record_id"),
            }

        self.client.db_insert(
            "mesh_messages",
            data={
                "message_id": message_id,
                "payload_type": payload_type,
                "origin_device_id": origin_device,
                "hop_count": hop_count,
                "processing_state": "pending",
                "raw_payload": payload,
                "signature": signature,
                "created_at": datetime.now(tz=UTC).isoformat(),
            },
            use_service_role=True,
        )

        try:
            linked_id = None
            if payload_type == "INCIDENT_REPORT":
                linked_id = self._process_incident(message_id, payload)
            elif payload_type == "ANNOUNCEMENT":
                linked_id = self._process_announcement(message_id, payload)
            elif payload_type == "DISTRESS":
                linked_id = self._process_distress(message_id, origin_device, hop_count, payload)
            elif payload_type == "SURVIVOR_SIGNAL":
                linked_id = self._process_survivor_signal(
                    message_id,
                    origin_device,
                    hop_count,
                    payload,
                )
            elif payload_type == "LOCATION_BEACON":
                linked_id = self._process_location_beacon(
                    message_id,
                    pkt.get("timestamp"),
                    payload,
                )
            elif payload_type == "STATUS_UPDATE":
                linked_id = self._process_status_update(payload)
            elif payload_type == "MESH_MESSAGE":
                linked_id = self._process_mesh_message(message_id, payload)
            elif payload_type == "MESH_POST":
                linked_id = self._process_mesh_post(message_id, payload)

            self.client.db_update(
                "mesh_messages",
                data={
                    "processing_state": "processed",
                    "linked_record_id": linked_id,
                    "linked_record_type": _record_type_for(payload_type, payload),
                    "processed_at": datetime.now(tz=UTC).isoformat(),
                },
                params={"message_id": f"eq.{message_id}"},
                use_service_role=True,
            )
            return {
                "messageId": message_id,
                "status": "processed",
                "linkedRecordId": linked_id,
            }

        except Exception as exc:
            log.exception("Mesh processing failed: %s", message_id)
            self.client.db_update(
                "mesh_messages",
                data={
                    "processing_state": "failed",
                    "error_message": str(exc)[:500],
                    "processed_at": datetime.now(tz=UTC).isoformat(),
                },
                params={"message_id": f"eq.{message_id}"},
                use_service_role=True,
            )
            return _error_result(message_id, str(exc))

    # -- incident report: append-only --
    def _process_incident(self, message_id: str, payload: dict[str, Any]) -> str | None:
        description = payload.get("description", "")
        if not description:
            raise ApiError("Incident payload missing description.", code="validation_error")

        row = {
            "description": description,
            "category": payload.get("category", "other"),
            "severity": payload.get("severity", "medium"),
            "status": "pending",
            "is_escalated": False,
            "is_mesh_origin": True,
            "mesh_message_id": message_id,
            "reporter_id": payload.get("reporter_id", "00000000-0000-0000-0000-000000000000"),
            "address": payload.get("address", ""),
            "latitude": payload.get("latitude"),
            "longitude": payload.get("longitude"),
            "image_urls": payload.get("image_urls", []),
            "created_at": payload.get("timestamp", datetime.now(tz=UTC).isoformat()),
        }
        rows = self.client.db_insert("incident_reports", data=row, use_service_role=True)
        if rows:
            self.client.db_insert(
                "report_status_history",
                data={
                    "report_id": rows[0]["id"],
                    "new_status": "pending",
                    "notes": "Created via mesh relay",
                    "created_at": datetime.now(tz=UTC).isoformat(),
                },
                use_service_role=True,
            )
            return rows[0]["id"]
        return None

    # -- announcement: append-only, requires valid dept token --
    def _process_announcement(self, message_id: str, payload: dict[str, Any]) -> str | None:
        dept_id = payload.get("department_id")
        offline_token = payload.get("offline_verification_token")

        if not dept_id:
            raise ApiError("Announcement missing department_id.", code="validation_error")

        token_payload = self._validate_offline_token(
            offline_token,
            expected_role="department",
            expected_department_id=str(dept_id),
        )

        depts = self.client.db_query(
            "departments",
            params={"select": "id,verification_status,user_id", "id": f"eq.{dept_id}"},
            use_service_role=True,
        )
        if not depts or depts[0].get("verification_status") != "approved":
            raise ApiError(
                "Department not verified - announcement rejected.",
                code="token_invalid",
            )

        row = {
            "department_id": dept_id,
            "author_id": token_payload.get("sub")
            or payload.get("author_id")
            or depts[0].get("user_id", ""),
            "title": payload.get("title", "Offline Announcement"),
            "content": payload.get("content", ""),
            "category": payload.get("category", "update"),
            "image_urls": payload.get("image_urls", []),
            "is_mesh_origin": True,
            "mesh_originated": True,
            "mesh_message_id": message_id,
            "created_at": payload.get("timestamp", datetime.now(tz=UTC).isoformat()),
        }
        rows = self.client.db_insert("posts", data=row, use_service_role=True)
        return rows[0]["id"] if rows else None

    # -- distress: immutable, fast-path --
    def _process_distress(
        self,
        message_id: str,
        origin_device: str,
        hop_count: int,
        payload: dict[str, Any],
    ) -> str | None:
        row = {
            "message_id": message_id,
            "origin_device_id": origin_device,
            "latitude": payload.get("latitude"),
            "longitude": payload.get("longitude"),
            "description": payload.get("description", ""),
            "reporter_name": payload.get("reporter_name", ""),
            "contact_info": payload.get("contact_info", ""),
            "hop_count": hop_count,
            "created_at": payload.get("timestamp", datetime.now(tz=UTC).isoformat()),
        }
        rows = self.client.db_insert("distress_signals", data=row, use_service_role=True)
        if rows:
            self.client.db_insert(
                "notifications",
                data={
                    "user_id": "00000000-0000-0000-0000-000000000000",
                    "type": "new_report",
                    "title": "SOS Distress Signal",
                    "message": f"Distress signal via mesh from device {origin_device[:8]}...",
                    "reference_id": rows[0]["id"],
                    "reference_type": "distress_signal",
                    "created_at": datetime.now(tz=UTC).isoformat(),
                },
                use_service_role=True,
                return_repr=False,
            )
            return rows[0]["id"]
        return None

    def _process_survivor_signal(
        self,
        message_id: str,
        origin_device: str,
        hop_count: int,
        payload: dict[str, Any],
    ) -> str | None:
        detection_method = payload.get("detectionMethod")
        if not detection_method:
            raise ApiError(
                "Survivor signal missing detectionMethod.",
                code="validation_error",
            )

        row = {
            "message_id": message_id,
            "origin_device_id": origin_device,
            "detection_method": detection_method,
            "signal_strength_dbm": payload.get("signalStrengthDbm", -90),
            "estimated_distance_meters": payload.get("estimatedDistanceMeters", 0),
            "detected_device_identifier": payload.get("detectedDeviceIdentifier", "unknown"),
            "last_seen_timestamp": payload.get(
                "lastSeenTimestamp",
                datetime.now(tz=UTC).isoformat(),
            ),
            "node_location": payload.get("nodeLocation", {}),
            "confidence": payload.get("confidence", 0),
            "acoustic_pattern_matched": payload.get("acousticPatternMatched", "none"),
            "hop_count": hop_count,
            "created_at": datetime.now(tz=UTC).isoformat(),
        }
        rows = self.client.db_insert("survivor_signals", data=row, use_service_role=True)
        return rows[0]["id"] if rows else None

    def _process_location_beacon(
        self,
        message_id: str,
        packet_timestamp: str | None,
        payload: dict[str, Any],
    ) -> str | None:
        device_fingerprint = str(payload.get("deviceFingerprint") or "").strip()
        if not device_fingerprint:
            raise ApiError(
                "Location beacon missing deviceFingerprint.",
                code="validation_error",
            )

        lat = payload.get("lat")
        lng = payload.get("lng")
        if lat is None or lng is None:
            raise ApiError(
                "Location beacon requires lat and lng.",
                code="validation_error",
            )

        recorded_at = (
            packet_timestamp
            or payload.get("recordedAt")
            or payload.get("timestamp")
            or datetime.now(tz=UTC).isoformat()
        )
        row = {
            "message_id": message_id,
            "device_fingerprint": device_fingerprint,
            "display_name": payload.get("displayName"),
            "location": {"lat": lat, "lng": lng},
            "accuracy_meters": payload.get("accuracyMeters"),
            "battery_pct": payload.get("batteryPct"),
            "app_state": payload.get("appState", "foreground"),
            "recorded_at": recorded_at,
            "created_at": recorded_at,
        }
        rows = self.client.db_insert(
            "device_location_trail",
            data=row,
            use_service_role=True,
        )
        return rows[0]["id"] if rows else None

    def _process_mesh_message(self, message_id: str, payload: dict[str, Any]) -> str | None:
        thread_id = _require_uuid(payload.get("threadId"), field_name="threadId")
        recipient_scope = str(payload.get("recipientScope") or "").strip().lower()
        recipient_identifier = payload.get("recipientIdentifier")
        body = str(payload.get("body") or "").strip()
        author_display_name = str(payload.get("authorDisplayName") or "").strip()
        author_role = str(payload.get("authorRole") or "").strip().lower()
        author_token = payload.get("authorOfflineToken")

        if recipient_scope not in VALID_RECIPIENT_SCOPES:
            raise ApiError("Mesh message recipientScope is invalid.", code="validation_error")
        if recipient_scope in {"department", "direct"} and not recipient_identifier:
            raise ApiError(
                "Mesh message recipientIdentifier is required for this scope.",
                code="validation_error",
            )
        if not body or len(body) > 500:
            raise ApiError(
                "Mesh message body must be 1 to 500 characters.", code="validation_error"
            )
        if not author_display_name:
            raise ApiError("Mesh message authorDisplayName is required.", code="validation_error")
        if author_role not in VALID_MESSAGE_AUTHOR_ROLES:
            raise ApiError("Mesh message authorRole is invalid.", code="validation_error")
        if recipient_scope == "department" and author_role != "department":
            raise ApiError(
                "Only department responders can send department-scoped mesh messages.",
                code="validation_error",
            )

        author_identifier = None
        author_department_id = None
        if author_role != "anonymous":
            token_payload = self._validate_offline_token(author_token, expected_role=author_role)
            author_identifier = token_payload.get("sub")
            author_department_id = token_payload.get("department_id")

        row = {
            "thread_id": str(thread_id),
            "message_id": message_id,
            "recipient_scope": recipient_scope,
            "recipient_identifier": recipient_identifier,
            "body": body,
            "author_display_name": author_display_name,
            "author_role": author_role,
            "author_identifier": author_identifier,
            "author_department_id": author_department_id,
            "created_at": payload.get("timestamp", datetime.now(tz=UTC).isoformat()),
        }
        rows = self.client.db_insert("mesh_comms_messages", data=row, use_service_role=True)
        inserted = rows[0] if rows else None

        if recipient_scope == "direct" and recipient_identifier:
            self._notify_direct_mesh_recipient(
                recipient_identifier=str(recipient_identifier),
                body=body,
                thread_id=str(thread_id),
                linked_record_id=(inserted or {}).get("id"),
                author_display_name=author_display_name,
            )

        return (inserted or {}).get("id")

    def _process_mesh_post(self, message_id: str, payload: dict[str, Any]) -> str | None:
        post_id = _require_uuid(payload.get("postId"), field_name="postId")
        category = str(payload.get("category") or "").strip()
        title = str(payload.get("title") or "").strip()
        body = str(payload.get("body") or "").strip()
        department_id = payload.get("authorDepartmentId")
        author_token = payload.get("authorOfflineToken")
        attachment_refs = payload.get("attachmentRefs") or []

        if category not in {"alert", "warning", "safety_tip", "update", "situational_report"}:
            raise ApiError("Mesh post category is invalid.", code="validation_error")
        if not title or len(title) > 100:
            raise ApiError("Mesh post title must be 1 to 100 characters.", code="validation_error")
        if not body or len(body) > 1000:
            raise ApiError("Mesh post body must be 1 to 1000 characters.", code="validation_error")
        if not department_id:
            raise ApiError("Mesh post authorDepartmentId is required.", code="validation_error")
        if not isinstance(attachment_refs, list):
            raise ApiError("Mesh post attachmentRefs must be an array.", code="validation_error")

        token_payload = self._validate_offline_token(
            author_token,
            expected_role="department",
            expected_department_id=str(department_id),
        )
        departments = self.client.db_query(
            "departments",
            params={"select": "id,verification_status,user_id", "id": f"eq.{department_id}"},
            use_service_role=True,
        )
        if not departments or departments[0].get("verification_status") != "approved":
            raise ApiError(
                "Department not verified - mesh post rejected.",
                code="token_invalid",
            )

        row = {
            "id": str(post_id),
            "department_id": department_id,
            "author_id": token_payload.get("sub") or departments[0].get("user_id"),
            "title": title,
            "content": body,
            "category": category,
            "image_urls": attachment_refs,
            "mesh_message_id": message_id,
            "is_mesh_origin": True,
            "mesh_originated": True,
            "created_at": payload.get("timestamp", datetime.now(tz=UTC).isoformat()),
        }
        rows = self.client.db_insert("posts", data=row, use_service_role=True)
        return rows[0]["id"] if rows else None

    def _notify_direct_mesh_recipient(
        self,
        *,
        recipient_identifier: str,
        body: str,
        thread_id: str,
        linked_record_id: str | None,
        author_display_name: str,
    ) -> None:
        users = self.client.db_query(
            "users",
            params={"select": "id", "id": f"eq.{recipient_identifier}"},
            use_service_role=True,
        )
        if not users:
            return

        preview = body if len(body) <= 120 else f"{body[:117]}..."
        self.client.db_insert(
            "notifications",
            data={
                "user_id": recipient_identifier,
                "type": "announcement",
                "title": "Direct mesh message",
                "message": f"{author_display_name}: {preview}",
                "reference_id": linked_record_id,
                "reference_type": f"mesh_thread:{thread_id}",
                "created_at": datetime.now(tz=UTC).isoformat(),
            },
            use_service_role=True,
            return_repr=False,
        )

    def _validate_offline_token(
        self,
        token: str | None,
        *,
        expected_role: str | None = None,
        expected_department_id: str | None = None,
    ) -> dict[str, Any]:
        if self.offline_token_service is None:
            raise ApiError("Offline token verification is unavailable.", code="token_invalid")
        return self.offline_token_service.validate_token(
            token or "",
            expected_role=expected_role,
            expected_department_id=expected_department_id,
        )

    # -- status update: last-write-wins by timestamp --
    def _process_status_update(self, payload: dict[str, Any]) -> str | None:
        target_type = str(
            payload.get("targetType") or payload.get("target_type") or "INCIDENT_REPORT"
        ).upper()
        if target_type == "SURVIVOR_SIGNAL":
            return self._process_survivor_signal_status_update(payload)

        report_id = payload.get("report_id")
        new_status = payload.get("new_status")
        if not report_id or not new_status:
            raise ApiError(
                "Status update requires report_id and new_status.",
                code="validation_error",
            )

        timestamp = payload.get("timestamp", datetime.now(tz=UTC).isoformat())

        existing = self.client.db_query(
            "incident_reports",
            params={"select": "id,status,updated_at", "id": f"eq.{report_id}"},
            use_service_role=True,
        )
        if not existing:
            raise ApiError("Report not found.", code="not_found")

        current_updated = existing[0].get("updated_at", "")
        if timestamp < current_updated:
            return report_id

        self.client.db_update(
            "incident_reports",
            data={"status": new_status, "updated_at": timestamp},
            params={"id": f"eq.{report_id}"},
            use_service_role=True,
        )
        self.client.db_insert(
            "report_status_history",
            data={
                "report_id": report_id,
                "new_status": new_status,
                "notes": "Updated via mesh sync",
                "created_at": timestamp,
            },
            use_service_role=True,
        )
        return report_id

    def _process_survivor_signal_status_update(
        self,
        payload: dict[str, Any],
    ) -> str | None:
        signal_id = payload.get("signalId") or payload.get("signal_id")
        survivor_message_id = (
            payload.get("survivorMessageId")
            or payload.get("survivor_message_id")
            or payload.get("message_id")
        )
        if not signal_id and not survivor_message_id:
            raise ApiError(
                "Survivor resolve update requires signal_id or survivor_message_id.",
                code="validation_error",
            )

        timestamp = payload.get("timestamp", datetime.now(tz=UTC).isoformat())
        note = str(
            payload.get("resolutionNote")
            or payload.get("resolution_note")
            or payload.get("note")
            or ""
        ).strip()
        resolved_by = payload.get("resolvedByUserId") or payload.get("resolved_by_user_id")

        query_params = {"select": "*"}
        if signal_id:
            query_params["id"] = f"eq.{signal_id}"
        else:
            query_params["message_id"] = f"eq.{survivor_message_id}"

        existing = self.client.db_query(
            "survivor_signals",
            params=query_params,
            use_service_role=True,
        )
        if not existing:
            raise ApiError("Survivor signal not found.", code="not_found")

        current = existing[0]
        current_resolved_at = current.get("resolved_at") or ""
        if current_resolved_at and timestamp < current_resolved_at:
            return current.get("id")

        update_data: dict[str, Any] = {
            "resolved": True,
            "resolved_at": timestamp,
            "resolution_note": note,
        }
        if resolved_by:
            update_data["resolved_by"] = resolved_by

        self.client.db_update(
            "survivor_signals",
            data=update_data,
            params={"id": f"eq.{current['id']}"},
            use_service_role=True,
        )
        return current.get("id")

    @staticmethod
    def verify_signature(payload: dict, signature: str, device_key: str) -> bool:
        """Verify HMAC-SHA256 signature of a mesh packet payload."""
        payload_bytes = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        expected = hmac.new(device_key.encode(), payload_bytes, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)


def _record_type_for(
    payload_type: str,
    payload: dict[str, Any] | None = None,
) -> str | None:
    if payload_type == "STATUS_UPDATE":
        target_type = str(
            (payload or {}).get("targetType")
            or (payload or {}).get("target_type")
            or "INCIDENT_REPORT"
        ).upper()
        return "survivor_signal" if target_type == "SURVIVOR_SIGNAL" else "incident_report"

    return {
        "INCIDENT_REPORT": "incident_report",
        "ANNOUNCEMENT": "post",
        "DISTRESS": "distress_signal",
        "SURVIVOR_SIGNAL": "survivor_signal",
        "LOCATION_BEACON": "device_location_trail",
        "MESH_MESSAGE": "mesh_comm_message",
        "MESH_POST": "post",
        "SYNC_ACK": None,
    }.get(payload_type)


def _require_uuid(value: Any, *, field_name: str) -> UUID:
    if not isinstance(value, str) or not value.strip():
        raise ApiError(f"{field_name} is required.", code="validation_error")
    try:
        return UUID(value)
    except ValueError as exc:
        raise ApiError(f"{field_name} must be a valid UUID.", code="validation_error") from exc


def _serialize_mesh_message(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": row.get("id"),
        "thread_id": row.get("thread_id"),
        "message_id": row.get("message_id"),
        "recipient_scope": row.get("recipient_scope"),
        "recipient_identifier": row.get("recipient_identifier"),
        "body": row.get("body"),
        "author_display_name": row.get("author_display_name"),
        "author_role": row.get("author_role"),
        "author_identifier": row.get("author_identifier"),
        "author_department_id": row.get("author_department_id"),
        "created_at": row.get("created_at"),
    }


# GeoJSON helpers keep the web map thin and consistent across endpoints.
def _decorate_survivor_signal(row: dict[str, Any]) -> dict[str, Any]:
    lat, lng = _extract_coordinates(row.get("node_location") or {})
    enriched = dict(row)
    enriched["coordinates"] = [lng, lat] if lat is not None and lng is not None else None
    enriched["geometry"] = (
        {"type": "Point", "coordinates": [lng, lat]}
        if lat is not None and lng is not None
        else None
    )
    enriched["marker_state"] = "resolved" if row.get("resolved") else "active"
    enriched["accuracy_radius_meters"] = row.get("estimated_distance_meters", 0)
    return enriched


def _decorate_location_trail_point(row: dict[str, Any]) -> dict[str, Any]:
    lat, lng = _extract_coordinates(row.get("location") or {})
    enriched = dict(row)
    enriched["lat"] = lat
    enriched["lng"] = lng
    enriched["coordinates"] = [lng, lat] if lat is not None and lng is not None else None
    enriched["geometry"] = (
        {"type": "Point", "coordinates": [lng, lat]}
        if lat is not None and lng is not None
        else None
    )
    return enriched


def _decorate_citizen_nearby_presence(
    row: dict[str, Any],
    *,
    distance_meters: float | None = None,
) -> dict[str, Any]:
    lat, lng = _extract_presence_coordinates(row)
    enriched = dict(row)
    enriched["lat"] = lat
    enriched["lng"] = lng
    enriched["coordinates"] = [lng, lat] if lat is not None and lng is not None else None
    enriched["geometry"] = (
        {"type": "Point", "coordinates": [lng, lat]}
        if lat is not None and lng is not None
        else None
    )
    enriched["distance_meters"] = distance_meters
    return enriched


def _build_topology_row(
    node: dict[str, Any],
    gateway_device_id: str,
    captured_at: str,
) -> dict[str, Any] | None:
    node_device_id = (
        node.get("nodeDeviceId") or node.get("deviceId") or node.get("originDeviceId") or ""
    )
    if not node_device_id:
        return None

    location = node.get("nodeLocation") or node.get("location") or {}
    if not isinstance(location, dict):
        location = {}
    lat = node.get("lat", location.get("lat"))
    lng = node.get("lng", location.get("lng"))
    if lat is None or lng is None:
        return None

    accuracy = node.get("accuracyMeters", location.get("accuracyMeters"))
    node_role = str(
        node.get("role")
        or node.get("nodeRole")
        or ("gateway" if node_device_id == gateway_device_id and gateway_device_id else "relay")
    ).lower()
    if node_role not in {"origin", "relay", "gateway"}:
        node_role = "relay"

    operator_role = node.get("operatorRole")
    if operator_role not in {"citizen", "department", "municipality"}:
        operator_role = None

    department_id = node.get("departmentId")
    if not isinstance(department_id, str) or not department_id.strip():
        department_id = None

    department_name = str(node.get("departmentName") or "")
    display_name = str(node.get("displayName") or node.get("deviceName") or department_name)
    last_seen_at = node.get("lastSeenTimestamp") or node.get("lastSeenAt") or captured_at

    explicit_responder = node.get("isResponder")
    is_responder = bool(
        explicit_responder
        if explicit_responder is not None
        else operator_role == "department" or department_id
    )

    return {
        "node_device_id": node_device_id,
        "gateway_device_id": str(node.get("gatewayDeviceId") or gateway_device_id or ""),
        "node_role": node_role,
        "node_location": {
            "lat": float(lat),
            "lng": float(lng),
            "accuracyMeters": float(accuracy) if accuracy is not None else None,
        },
        "peer_count": int(node.get("peerCount") or 0),
        "queue_depth": int(node.get("queueDepth") or 0),
        "last_seen_at": last_seen_at,
        "last_sync_at": captured_at,
        "display_name": display_name,
        "operator_role": operator_role,
        "department_id": department_id,
        "department_name": department_name,
        "is_responder": is_responder,
        "metadata": _topology_metadata(node),
    }


def _format_topology_node(row: dict[str, Any], now: datetime) -> dict[str, Any] | None:
    lat, lng = _extract_coordinates(row.get("node_location") or {})
    if lat is None or lng is None:
        return None

    last_seen = _parse_iso_datetime(row.get("last_seen_at"))
    if last_seen is None:
        return None

    if last_seen < now - timedelta(minutes=TOPOLOGY_ACTIVE_WINDOW_MINUTES):
        return None

    enriched = dict(row)
    enriched["coordinates"] = [lng, lat]
    enriched["geometry"] = {"type": "Point", "coordinates": [lng, lat]}
    enriched["lat"] = lat
    enriched["lng"] = lng
    enriched["is_stale"] = last_seen < now - timedelta(minutes=TOPOLOGY_STALE_AFTER_MINUTES)
    return enriched


def _is_responder_node(node: dict[str, Any]) -> bool:
    return bool(
        node.get("is_responder")
        or node.get("department_id")
        or node.get("operator_role") == "department"
    )


def _topology_metadata(node: dict[str, Any]) -> dict[str, Any]:
    metadata = node.get("metadata")
    clean_metadata = dict(metadata) if isinstance(metadata, dict) else {}
    for key in ("batteryPct", "appState", "lastRelayHopCount"):
        if key in node:
            clean_metadata[key] = node[key]
    return clean_metadata


def _location_in_bbox(
    node_location: dict[str, Any],
    min_lat: float,
    max_lat: float,
    min_lng: float,
    max_lng: float,
) -> bool:
    lat = node_location.get("lat")
    lng = node_location.get("lng")
    if lat is None or lng is None:
        return False
    return min_lat <= float(lat) <= max_lat and min_lng <= float(lng) <= max_lng


def _bounding_box_for_radius_meters(
    center_lat: float,
    center_lng: float,
    radius_meters: float,
) -> tuple[float, float, float, float]:
    latitude_delta = radius_meters / 111111.0
    longitude_scale = abs(math.cos(math.radians(center_lat)))
    longitude_delta = radius_meters / max(111111.0 * longitude_scale, 1.0)
    return (
        center_lat - latitude_delta,
        center_lat + latitude_delta,
        center_lng - longitude_delta,
        center_lng + longitude_delta,
    )


def _distance_between_points_meters(
    lat_a: float,
    lng_a: float,
    lat_b: float,
    lng_b: float,
) -> float:
    earth_radius_meters = 6371000.0
    lat1 = math.radians(lat_a)
    lat2 = math.radians(lat_b)
    delta_lat = math.radians(lat_b - lat_a)
    delta_lng = math.radians(lng_b - lng_a)

    haversine = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lng / 2) ** 2
    )
    arc = 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine))
    return earth_radius_meters * arc


def _extract_coordinates(node_location: dict[str, Any]) -> tuple[float | None, float | None]:
    lat = node_location.get("lat")
    lng = node_location.get("lng")
    if lat is None or lng is None:
        return None, None
    try:
        return float(lat), float(lng)
    except (TypeError, ValueError):
        return None, None


def _extract_presence_coordinates(row: dict[str, Any]) -> tuple[float | None, float | None]:
    lat = row.get("lat")
    lng = row.get("lng")
    if lat is not None and lng is not None:
        try:
            return float(lat), float(lng)
        except (TypeError, ValueError):
            pass
    return _extract_coordinates(row.get("location") or {})


def _parse_iso_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _error_result(message_id: str, error: str) -> dict[str, Any]:
    return {"messageId": message_id, "status": "error", "error": error}
