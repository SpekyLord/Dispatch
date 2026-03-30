"""Mesh gateway API — batch ingest and sync-updates endpoints."""

from __future__ import annotations

from http import HTTPStatus

from flask import current_app, jsonify, request

from dispatch_api.errors import ApiError
from dispatch_api.modules.mesh import blueprint
from dispatch_api.services.mesh_service import MeshService


def _mesh_service() -> MeshService:
    return MeshService(current_app.extensions["supabase_client"])


# gateway upload endpoint for batch mesh packet ingestion
@blueprint.post("/ingest")
def ingest_packets():
    body = request.get_json(silent=True)
    if not body:
        raise ApiError(
            "Request body is required.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="missing_body",
        )

    packets = body.get("packets", [])
    if not isinstance(packets, list) or not packets:
        raise ApiError(
            "packets must be a non-empty array.",
            status_code=HTTPStatus.BAD_REQUEST,
            code="validation_error",
        )

    svc = _mesh_service()

    # prioritize DISTRESS packets first
    distress = [p for p in packets if p.get("payloadType") == "DISTRESS"]
    others = [p for p in packets if p.get("payloadType") != "DISTRESS"]
    ordered = distress + others

    results = svc.ingest_packets(ordered)

    # build SYNC_ACK responses for processed packets
    acks = []
    for r in results:
        if r.get("status") == "processed":
            acks.append(
                {
                    "messageId": r["messageId"],
                    "payloadType": "SYNC_ACK",
                    "linkedRecordId": r.get("linkedRecordId"),
                    "synced": True,
                }
            )

    return jsonify(
        {
            "results": results,
            "acks": acks,
            "processed_count": sum(1 for r in results if r["status"] == "processed"),
            "duplicate_count": sum(1 for r in results if r["status"] == "duplicate"),
            "error_count": sum(1 for r in results if r["status"] == "error"),
        }
    )


# pull server-side changes for gateway rebroadcast into mesh
@blueprint.get("/sync-updates")
def get_sync_updates():
    since = request.args.get("since")
    svc = _mesh_service()
    updates = svc.get_sync_updates(since=since)
    return jsonify(updates)
