"""Mesh gateway API - batch ingest, sync-updates, topology, survivor, and comms routes."""

from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.auth import get_current_user, require_auth, require_role
from dispatch_api.errors import ApiError
from dispatch_api.modules.mesh import blueprint
from dispatch_api.services.mesh_service import MeshService
from dispatch_api.services.offline_token_service import OfflineTokenService


def _mesh_service() -> MeshService:
    return MeshService(
        current_app.extensions["supabase_client"],
        offline_token_service=OfflineTokenService(
            secret=current_app.config["SETTINGS"].supabase_service_role_key,
        ),
    )


def _priority_for(packet: dict) -> int:
    payload_type = packet.get("payloadType")
    return {
        "DISTRESS": 0,
        "SURVIVOR_SIGNAL": 0,
        "STATUS_UPDATE": 1,
        "MESH_MESSAGE": 1,
        "ANNOUNCEMENT": 2,
        "MESH_POST": 2,
        "LOCATION_BEACON": 3,
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


def _int_arg(name: str, default: int) -> int:
    raw_value = request.args.get(name)
    if raw_value in (None, ""):
        return default
    try:
        return int(raw_value)
    except ValueError as exc:
        raise ApiError(
            f"{name} must be an integer.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        ) from exc


def _required_float_arg(name: str) -> float:
    value = _float_arg(name)
    if value is None:
        raise ApiError(
            f"{name} is required.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )
    return value


def _body_float(name: str) -> float:
    body = request.get_json(silent=True) or {}
    raw_value = body.get(name)
    if raw_value in (None, ""):
        raise ApiError(
            f"{name} is required.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )
    try:
        return float(raw_value)
    except ValueError as exc:
        raise ApiError(
            f"{name} must be a number.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        ) from exc


def _viewer_department_id(user_id: str) -> str | None:
    rows = current_app.extensions["supabase_client"].db_query(
        "departments",
        params={"select": "id", "user_id": f"eq.{user_id}"},
        use_service_role=True,
    )
    return rows[0].get("id") if rows else None


@blueprint.post("/ingest")
@require_auth()
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
@require_auth()
def get_sync_updates():
    since = request.args.get("since")
    svc = _mesh_service()
    updates = svc.get_sync_updates(since=since)
    return jsonify(updates)


@blueprint.get("/messages")
@require_auth()
def get_mesh_messages():
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    thread_id = request.args.get("threadId")
    include_posts = request.args.get("include_posts") == "1"
    department_id = (
        _viewer_department_id(current_user.id) if current_user.role == "department" else None
    )
    svc = _mesh_service()
    messages = svc.list_messages(
        thread_id=thread_id,
        viewer_user_id=current_user.id,
        viewer_role=current_user.role,
        viewer_department_id=department_id,
    )
    response = {"messages": messages, "count": len(messages)}
    if include_posts or not thread_id:
        response["mesh_posts"] = svc.list_mesh_posts()
    return jsonify(response)


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


@blueprint.get("/trail/<path:device_fingerprint>")
@require_role("department", "municipality")
def get_device_trail(device_fingerprint: str):
    svc = _mesh_service()
    points = svc.list_device_trail(
        device_fingerprint,
        time_start=request.args.get("time_start"),
        time_end=request.args.get("time_end"),
        limit=_int_arg("limit", 240),
    )
    return jsonify(
        {
            "device_fingerprint": device_fingerprint,
            "points": points,
            "count": len(points),
            "last_seen": points[-1] if points else None,
        }
    )


@blueprint.get("/last-seen")
@require_role("department", "municipality")
def get_last_seen_devices():
    svc = _mesh_service()
    devices = svc.list_last_seen_devices()
    return jsonify({"devices": devices, "count": len(devices)})


@blueprint.put("/citizen-presence")
@require_role("citizen")
def upsert_citizen_presence():
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    display_name = str(body.get("display_name") or "").strip()
    if not display_name:
        raise ApiError(
            "display_name is required.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )

    svc = _mesh_service()
    presence = svc.upsert_citizen_nearby_presence(
        user_id=current_user.id,
        display_name=display_name,
        latitude=_body_float("lat"),
        longitude=_body_float("lng"),
        accuracy_meters=_float_body_optional("accuracy_meters"),
        mesh_device_id=str(body.get("mesh_device_id") or "").strip() or None,
        mesh_identity_hash=str(body.get("mesh_identity_hash") or "").strip() or None,
        last_seen_at=body.get("last_seen_at"),
    )
    return jsonify({"presence": presence})


def _float_body_optional(name: str) -> float | None:
    body = request.get_json(silent=True) or {}
    raw_value = body.get(name)
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


@blueprint.get("/citizen-presence/nearby")
@require_role("citizen")
def get_nearby_citizen_presence():
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    nearby_users = svc.list_nearby_citizen_presence(
        viewer_user_id=current_user.id,
        center_lat=_required_float_arg("lat"),
        center_lng=_required_float_arg("lng"),
        radius_meters=float(_int_arg("radius_meters", 15)),
        freshness_seconds=_int_arg("freshness_seconds", 15),
        limit=_int_arg("limit", 100),
    )
    return jsonify({"users": nearby_users, "count": len(nearby_users)})


@blueprint.get("/citizen-ble-chat-sessions")
@require_role("citizen")
def list_citizen_ble_chat_sessions():
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    sessions = svc.list_citizen_ble_chat_sessions(
        viewer_user_id=current_user.id,
        limit=_int_arg("limit", 50),
    )
    return jsonify({"sessions": sessions, "count": len(sessions)})


@blueprint.get("/citizen-ble-chat-rooms")
@require_role("citizen")
def list_citizen_ble_chat_rooms():
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    rooms = svc.list_citizen_ble_chat_rooms(
        viewer_user_id=current_user.id,
        limit=_int_arg("limit", 50),
    )
    return jsonify({"rooms": rooms, "count": len(rooms)})


@blueprint.post("/citizen-ble-chat-sessions/request")
@require_role("citizen")
def request_citizen_ble_chat_session():
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    session = svc.request_citizen_ble_chat_session(
        requester_user_id=current_user.id,
        recipient_user_id=str(body.get("recipient_user_id") or "").strip(),
        requester_mesh_device_id=str(body.get("requester_mesh_device_id") or "").strip(),
        recipient_mesh_device_id=str(body.get("recipient_mesh_device_id") or "").strip(),
        requester_display_name=str(body.get("requester_display_name") or "").strip(),
        recipient_display_name=str(body.get("recipient_display_name") or "").strip(),
    )
    return jsonify({"session": session})


@blueprint.post("/citizen-ble-chat-rooms/<path:room_id>/join")
@require_role("citizen")
def join_citizen_ble_chat_room(room_id: str):
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    room = svc.join_citizen_ble_chat_room(
        room_id=room_id,
        actor_user_id=current_user.id,
        mesh_device_id=str(body.get("mesh_device_id") or "").strip(),
        display_name=str(body.get("display_name") or "").strip(),
    )
    return jsonify({"room": room})


@blueprint.post("/citizen-ble-chat-rooms/<path:room_id>/leave")
@require_role("citizen")
def leave_citizen_ble_chat_room(room_id: str):
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    room = svc.leave_citizen_ble_chat_room(
        room_id=room_id,
        actor_user_id=current_user.id,
    )
    return jsonify({"room": room})


@blueprint.get("/citizen-ble-chat-rooms/<path:room_id>/messages")
@require_role("citizen")
def list_citizen_ble_chat_room_messages(room_id: str):
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    messages = svc.list_citizen_ble_chat_room_messages(
        room_id=room_id,
        actor_user_id=current_user.id,
        limit=_int_arg("limit", 200),
    )
    return jsonify({"messages": messages, "count": len(messages)})


@blueprint.post("/citizen-ble-chat-rooms/<path:room_id>/messages")
@require_role("citizen")
def create_citizen_ble_chat_room_message(room_id: str):
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    raw_expires_in_seconds = body.get("expires_in_seconds")
    if raw_expires_in_seconds in (None, ""):
        expires_in_seconds = 1800
    else:
        try:
            expires_in_seconds = int(raw_expires_in_seconds)
        except (TypeError, ValueError) as exc:
            raise ApiError(
                "expires_in_seconds must be an integer.",
                status_code=HTTPStatus.BAD_REQUEST,
                code="validation_error",
            ) from exc
    message = svc.create_citizen_ble_chat_room_message(
        room_id=room_id,
        actor_user_id=current_user.id,
        author_display_name=str(body.get("author_display_name") or "").strip(),
        body=str(body.get("body") or "").strip(),
        expires_in_seconds=expires_in_seconds,
    )
    return jsonify({"message": message})


@blueprint.post("/citizen-ble-chat-sessions/<path:session_id>/respond")
@require_role("citizen")
def respond_to_citizen_ble_chat_session(session_id: str):
    body = request.get_json(silent=True) or {}
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    action = str(body.get("action") or "").strip().lower()
    if action not in {"accept", "reject"}:
        raise ApiError(
            "action must be either accept or reject.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )

    svc = _mesh_service()
    session = svc.respond_to_citizen_ble_chat_session(
        session_id=session_id,
        actor_user_id=current_user.id,
        accept=action == "accept",
    )
    payload = {"session": session}
    if isinstance(session, dict) and session.get("room") is not None:
        payload["room"] = session["room"]
    return jsonify(payload)


@blueprint.post("/citizen-ble-chat-sessions/<path:session_id>/close")
@require_role("citizen")
def close_citizen_ble_chat_session(session_id: str):
    current_user = get_current_user()
    if current_user is None:
        raise ApiError(
            "Authentication is required to access this resource.",
            status_code=HTTPStatus.UNAUTHORIZED,
            code="authentication_required",
        )

    svc = _mesh_service()
    session = svc.close_citizen_ble_chat_session(
        session_id=session_id,
        actor_user_id=current_user.id,
    )
    return jsonify({"session": session})
