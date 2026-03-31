"""Mesh gateway service - idempotent ingest, dedup, sync, topology, and survivor workflows."""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
from datetime import UTC, datetime, timedelta
from typing import Any

from dispatch_api.errors import ApiError

log = logging.getLogger(__name__)

VALID_PAYLOAD_TYPES = {
    "INCIDENT_REPORT",
    "ANNOUNCEMENT",
    "DISTRESS",
    "SURVIVOR_SIGNAL",
    "STATUS_UPDATE",
    "SYNC_ACK",
}

MAX_HOPS_DEFAULT = 7
MAX_HOPS_DISTRESS = 15
MAX_HOPS_SURVIVOR_SIGNAL = 15
TOPOLOGY_STALE_AFTER_MINUTES = 5
TOPOLOGY_ACTIVE_WINDOW_MINUTES = 30


class MeshService:
    def __init__(self, client) -> None:
        self.client = client

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
        base_params: dict[str, str] = {"order": "updated_at.desc", "limit": "100"}
        if since:
            base_params["updated_at"] = f"gte.{since}"

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
        if since:
            distress_params["created_at"] = f"gte.{since}"
        distress = self.client.db_query(
            "distress_signals", params=distress_params, use_service_role=True
        )

        survivor_params: dict[str, str] = {
            "select": "*",
            "order": "created_at.desc",
            "limit": "100",
        }
        if since:
            survivor_params["created_at"] = f"gte.{since}"
        survivor_rows = self.client.db_query(
            "survivor_signals", params=survivor_params, use_service_role=True
        )

        history_params: dict[str, str] = {
            "select": "*",
            "order": "created_at.desc",
            "limit": "100",
        }
        if since:
            history_params["created_at"] = f"gte.{since}"
        history = self.client.db_query(
            "report_status_history", params=history_params, use_service_role=True
        )

        return {
            "report_updates": reports,
            "distress_signals": distress,
            "survivor_signals": [_decorate_survivor_signal(row) for row in survivor_rows],
            "status_history": history,
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
            elif payload_type == "STATUS_UPDATE":
                linked_id = self._process_status_update(payload)

            self.client.db_update(
                "mesh_messages",
                data={
                    "processing_state": "processed",
                    "linked_record_id": linked_id,
                    "linked_record_type": _record_type_for(payload_type),
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
        if not offline_token:
            raise ApiError(
                "Announcement missing offline verification token.",
                code="token_missing",
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
            "author_id": payload.get("author_id", depts[0].get("user_id", "")),
            "title": payload.get("title", "Offline Announcement"),
            "content": payload.get("content", ""),
            "category": payload.get("category", "update"),
            "image_urls": payload.get("image_urls", []),
            "is_mesh_origin": True,
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

    # -- status update: last-write-wins by timestamp --
    def _process_status_update(self, payload: dict[str, Any]) -> str | None:
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

    @staticmethod
    def verify_signature(payload: dict, signature: str, device_key: str) -> bool:
        """Verify HMAC-SHA256 signature of a mesh packet payload."""
        payload_bytes = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        expected = hmac.new(device_key.encode(), payload_bytes, hashlib.sha256).hexdigest()
        return hmac.compare_digest(expected, signature)


def _record_type_for(payload_type: str) -> str | None:
    return {
        "INCIDENT_REPORT": "incident_report",
        "ANNOUNCEMENT": "post",
        "DISTRESS": "distress_signal",
        "SURVIVOR_SIGNAL": "survivor_signal",
        "STATUS_UPDATE": "incident_report",
        "SYNC_ACK": None,
    }.get(payload_type)


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


def _build_topology_row(
    node: dict[str, Any],
    gateway_device_id: str,
    captured_at: str,
) -> dict[str, Any] | None:
    node_device_id = (
        node.get("nodeDeviceId")
        or node.get("deviceId")
        or node.get("originDeviceId")
        or ""
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
    last_seen_at = (
        node.get("lastSeenTimestamp")
        or node.get("lastSeenAt")
        or captured_at
    )

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


def _extract_coordinates(node_location: dict[str, Any]) -> tuple[float | None, float | None]:
    lat = node_location.get("lat")
    lng = node_location.get("lng")
    if lat is None or lng is None:
        return None, None
    try:
        return float(lat), float(lng)
    except (TypeError, ValueError):
        return None, None


def _parse_iso_datetime(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _error_result(message_id: str, error: str) -> dict[str, Any]:
    return {"messageId": message_id, "status": "error", "error": error}
