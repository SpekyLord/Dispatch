"""Mesh gateway API - batch ingest, sync-updates, topology, and survivor routes."""

from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.mesh import blueprint
from dispatch_api.services.mesh_service import MeshService


def _mesh_service() -> MeshService:
    return MeshService(current_app.extensions["supabase_client"])


def _priority_for(packet: dict) -> int:
    payload_type = packet.get("payloadType")
    return {
        "DISTRESS": 0,
        "SURVIVOR_SIGNAL": 0,
        "STATUS_UPDATE": 1,
        "ANNOUNCEMENT": 2,
        "INCIDENT_REPORT": 3,
        "SYNC_ACK": 4,
    }.get(payload_type, 5)


def _float_arg(name: str) -> float | None:
    raw_value = request.args.get(name)
    if raw_value in (None, ""):
        return None
    try:
        return float(raw_value)
    except ValueError as exc:
        raise ApiError(
            f"{name} must be a number.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        ) from exc


@blueprint.post("/ingest")
def ingest_packets():
    body = request.get_json(silent=True)
    if not body:
        raise ApiError(
            "Request body is required.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="missing_body",
        )

    packets = body.get("packets") or []
    topology_snapshot = body.get("topologySnapshot")

    if not isinstance(packets, list):
        raise ApiError(
            "packets must be an array.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )
    if topology_snapshot is not None and not isinstance(topology_snapshot, dict):
        raise ApiError(
            "topologySnapshot must be an object.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )
    if not packets and topology_snapshot is None:
        raise ApiError(
            "Request must include packets or topologySnapshot.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )

    svc = _mesh_service()
    ordered = sorted(packets, key=_priority_for)
    results = svc.ingest_packets(ordered)
    topology_ingested_count = (
        svc.upsert_topology_snapshot(topology_snapshot) if topology_snapshot else 0
    )

    acks = []
    for result in results:
        if result.get("status") == "processed":
            acks.append(
                {
                    "messageId": result["messageId"],
                    "payloadType": "SYNC_ACK",
                    "linkedRecordId": result.get("linkedRecordId"),
                    "synced": True,
                }
            )

    return jsonify(
        {
            "results": results,
            "acks": acks,
            "processed_count": sum(1 for result in results if result["status"] == "processed"),
            "duplicate_count": sum(1 for result in results if result["status"] == "duplicate"),
            "error_count": sum(1 for result in results if result["status"] == "error"),
            "topology_ingested_count": topology_ingested_count,
        }
    )


@blueprint.get("/sync-updates")
def get_sync_updates():
    since = request.args.get("since")
    svc = _mesh_service()
    updates = svc.get_sync_updates(since=since)
    return jsonify(updates)


@blueprint.get("/topology")
@require_role("department", "municipality")
def get_topology():
    current_user = get_current_user()
    svc = _mesh_service()
    topology = svc.list_topology_nodes(viewer_role=current_user.role if current_user else None)
    return jsonify(
        {
            "nodes": topology["nodes"],
            "responders": topology["responders"],
            "count": len(topology["nodes"]),
            "responder_count": len(topology["responders"]),
            "synced_at": topology["synced_at"],
        }
    )


@blueprint.get("/survivor-signals")
@require_role("department", "municipality")
def get_survivor_signals():
    svc = _mesh_service()
    survivor_signals = svc.list_survivor_signals(
        status=request.args.get("status"),
        detection_method=request.args.get("detection_method"),
        time_start=request.args.get("time_start"),
        time_end=request.args.get("time_end"),
        min_lat=_float_arg("min_lat"),
        max_lat=_float_arg("max_lat"),
        min_lng=_float_arg("min_lng"),
        max_lng=_float_arg("max_lng"),
    )
    return jsonify({"survivor_signals": survivor_signals, "count": len(survivor_signals)})


@blueprint.put("/survivor-signals/<signal_id>/resolve")
@require_role("department", "municipality")
def resolve_survivor_signal(signal_id: str):
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    signal = svc.resolve_survivor_signal(
        signal_id,
        resolved_by=current_user.id,
        note=body.get("note", ""),
    )
    return jsonify({"survivor_signal": signal})
