# Phase 4 - Mobile Mesh Networking & Offline-First Sync

## Overview

Phase 4 adds offline-first mesh networking so reports, announcements, distress signals, and status updates can propagate across nearby mobile devices without internet, then sync to the server when a gateway device reconnects.

## Mesh Packet Envelope

Every mesh message uses this canonical envelope:

```json
{
  "messageId": "uuid-v4",
  "originDeviceId": "device-fingerprint",
  "timestamp": "ISO-8601",
  "hopCount": 0,
  "maxHops": 7,
  "payloadType": "INCIDENT_REPORT | ANNOUNCEMENT | DISTRESS | STATUS_UPDATE | SYNC_ACK",
  "payload": {},
  "signature": "hmac-sha256-of-payload-using-device-key"
}
```

## Node Roles

| Role | Description |
|------|-------------|
| **Origin** | Device that created the packet (default when offline) |
| **Relay** | Device forwarding packets between peers |
| **Gateway** | Device with internet that uploads queued packets to server |

Role transitions automatically based on connectivity status.

## Transport Selection

- **BLE**: Default for payloads under 10 KB
- **WiFi Direct**: Automatically negotiated for payloads above 10 KB; falls back to BLE fragmentation if negotiation fails

## Payload Types & Conflict Rules

| Type | Behavior | Notes |
|------|----------|-------|
| `INCIDENT_REPORT` | Append-only | Creates new report with `is_mesh_origin=true` |
| `ANNOUNCEMENT` | Append-only | Requires valid offline dept verification token |
| `DISTRESS` | Immutable | `maxHops=15`, processed with highest priority |
| `STATUS_UPDATE` | Last-write-wins | Compares timestamps; stale updates silently skipped |
| `SYNC_ACK` | Informational | Rebroadcast so origin devices learn reports reached the server |

## Gateway Sync Lifecycle

1. Gateway device collects queued packets from local SQLite `mesh_queue`
2. Sends batch to `POST /api/mesh/ingest`
3. Server deduplicates by `messageId` in `mesh_messages` table
4. Server processes each packet idempotently and returns results
5. Gateway receives `SYNC_ACK` for each processed packet
6. Gateway rebroadcasts `SYNC_ACK` into local mesh range
7. Origin devices mark corresponding queue entries as synced

## API Endpoints

### `POST /api/mesh/ingest`

Gateway upload endpoint for batch packet ingestion.

**Request:**
```json
{
  "packets": [{ ... envelope ... }]
}
```

**Response:**
```json
{
  "results": [
    { "messageId": "...", "status": "processed|duplicate|error", "linkedRecordId": "..." }
  ],
  "acks": [
    { "messageId": "...", "payloadType": "SYNC_ACK", "linkedRecordId": "...", "synced": true }
  ],
  "processed_count": 1,
  "duplicate_count": 0,
  "error_count": 0
}
```

### `GET /api/mesh/sync-updates`

Pull server-side changes for gateway to rebroadcast into mesh.

**Query params:** `since` (ISO-8601 timestamp, optional)

**Response:**
```json
{
  "report_updates": [...],
  "distress_signals": [...],
  "status_history": [...],
  "synced_at": "ISO-8601"
}
```

## Mobile Permissions

Mesh networking requires:
- **Bluetooth**: For BLE discovery and small packet relay
- **Location**: Required by Android for BLE scanning
- **Nearby Wi-Fi Devices**: For WiFi Direct large payload transfer
- No permissions required for SOS (uses already-granted BLE)

## Offline Department Verification Token

- Verified departments cache a signed offline verification JWT with a 30-day TTL
- Token is refreshed on every successful online session
- If expired or missing, the device cannot originate `ANNOUNCEMENT` packets
- The server validates by checking the department's `verification_status` is `approved`
- Expired token -> announcement creation blocked on device; if somehow relayed, server rejects it

## SOS Distress Signal

- One-tap action reachable without login from both citizen and department home screens
- Broadcasts `DISTRESS` packets with `maxHops = 15` (wider than normal 7)
- Processed with highest priority at gateway (distress packets sorted to front of batch)
- Creates a `distress_signals` record and notifies municipality users
- Distress signals are immutable once created

## Database Tables

### `mesh_messages` (dedup log)
Server-side record of every mesh packet received. Keyed by `message_id` (unique).
Fields: `message_id`, `payload_type`, `origin_device_id`, `hop_count`, `processing_state`, `linked_record_id`, `linked_record_type`, `raw_payload`, `signature`, `error_message`, `processed_at`.

### `distress_signals`
Persists SOS events uploaded through mesh sync.
Fields: `message_id`, `origin_device_id`, `latitude`, `longitude`, `description`, `reporter_name`, `contact_info`, `hop_count`, `is_resolved`, `resolved_by`, `resolved_at`.

### Mobile SQLite Tables
- `mesh_queue`: Queued outbound packets with status (`queued`, `synced`)
- `seen_messages`: Dedup log keyed by `message_id`
- `mesh_peers`: Discovered nearby device cache with `endpoint_id`, `device_name`, `is_gateway`, `last_seen_at`

## SAR Mode Extension (4-EXT.1)

### Permissions and operator scope

- SAR Mode is exposed from the mobile mesh status panel and should only be enabled by verified department responders.
- The toggle enables passive Wi-Fi probe parsing, BLE passive scan intake, acoustic classification intake, and SOS beacon visibility in the local SAR feed.
- SAR Mode defaults to off so routine mesh usage does not silently enable passive sensing.

### Battery and privacy notes

- Continuous passive scanning increases battery usage more than ordinary mesh relay because Wi-Fi, BLE, and acoustic checks stay warm while SAR Mode is active.
- Detected device identifiers are anonymized before persistence or relay. MAC-style identifiers keep the first four octets and zero the last two: `AA:BB:CC:DD:EE:FF` becomes `AA:BB:CC:DD:00:00`.
- Raw audio is never sent over mesh and is never uploaded to the backend. Only the on-device acoustic classification result is serialized into the survivor-signal packet.

### Acoustic model constraints

- Acoustic classification runs on 5-second windows and emits only `tapping`, `voice`, `anomalous_sound`, or `none`.
- The current implementation is a lightweight heuristic classifier/mock so the pipeline can be tested without shipping a heavy model asset yet.
- A future model refresh should stay on-device, remain small enough for offline responders, and preserve the same output labels so packet consumers do not break.

### Survivor signal lifecycle

1. A SAR subsystem detects a nearby signal and normalizes it into the canonical `SURVIVOR_SIGNAL` payload.
2. The mobile client deduplicates repeated detections from the same anonymized source inside a 60-second window before queueing a new packet.
3. The packet is enqueued at the same priority as `DISTRESS` and relayed through the existing mesh pipeline.
4. A gateway uploads the packet through `POST /api/mesh/ingest`, which records the dedup trace in `mesh_messages` and persists the detection in `survivor_signals`.
5. Municipality and department responders can review active detections through `GET /api/mesh/survivor-signals` and mark them resolved through `PUT /api/mesh/survivor-signals/:id/resolve` without deleting the audit record.

## Compass Navigation Extension (4-EXT.2)

- Survivor Compass is launched from the mobile SAR feed after a responder pins a target signal.
- Distance and bearing are computed from the rescuer's current GPS fix to the signal's `nodeLocation`.
- Android heading uses accelerometer + magnetometer fusion over the `dispatch_mobile/compass_heading` event channel; iOS uses the platform heading API over the same channel.
- Direct detections are treated as the tightest lock. Multi-hop relay signals surface hop count and a wider confidence band so responders treat them as search corridors rather than precise points.
- The minimap shows the rescuer position, estimated target point, and nearby mesh peers. Peer dots are rendered as a relative proximity ring until peer GPS coordinates are included in mesh sync uploads.
- When the rescuer closes to roughly 3 meters, the UI switches to a pulse animation and haptic cue to support a short-range sweep.
- Resolve actions call the existing survivor-signal resolve API when the device is online. If the request fails, the current mobile implementation keeps a local retry queue; it does not yet emit a dedicated mesh-relayed resolve packet.
