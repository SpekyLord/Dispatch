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
  "payloadType": "INCIDENT_REPORT | ANNOUNCEMENT | DISTRESS | SURVIVOR_SIGNAL | MESH_MESSAGE | MESH_POST | LOCATION_BEACON | STATUS_UPDATE | SYNC_ACK",
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
| `MESH_MESSAGE` | Append-only | Same relay priority as `STATUS_UPDATE`; stored in `mesh_comms_messages` for thread recovery |
| `MESH_POST` | Append-only | Same relay priority as `ANNOUNCEMENT`; creates a normal `posts` row with `mesh_originated=true` |
| `LOCATION_BEACON` | Append-only | Same relay priority as `INCIDENT_REPORT`; retained for 72 hours by default |
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

### `GET /api/mesh/trail/:deviceFingerprint`

Returns the ordered location-beacon history for a single anonymized device fingerprint. Municipality and department users only.

### `GET /api/mesh/last-seen`

Returns the freshest active `LOCATION_BEACON` per device fingerprint so operators can render the latest endpoint pin before loading the full trail. Municipality and department users only.

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

### `mesh_comms_messages`
Stores server-side thread history for `MESH_MESSAGE` packets.
Fields: `thread_id`, `message_id`, `recipient_scope`, `recipient_identifier`, `body`, `author_display_name`, `author_role`, `author_identifier`, `author_department_id`, `created_at`.

### `device_location_trail`
Stores append-only `LOCATION_BEACON` points linked back to `mesh_messages.message_id`.
Fields: `message_id`, `device_fingerprint`, `display_name`, `location`, `accuracy_meters`, `battery_pct`, `app_state`, `recorded_at`.
Retention: 72 hours by default, configurable through the database cleanup setting.

### Mobile SQLite Tables
- `mesh_queue`: Queued outbound packets with status (`queued`, `synced`)
- `seen_messages`: Dedup log keyed by `message_id`
- `mesh_peers`: Discovered nearby device cache with `endpoint_id`, `device_name`, `is_gateway`, `last_seen_at`

## SAR Mode Extension (4-EXT.1)

### Permissions and operator scope

- SAR Mode is exposed from the mobile mesh status panel and should only be enabled by verified department responders.
- The toggle enables Android BLE passive scan intake, on-device acoustic classification intake, and SOS beacon visibility in the local SAR feed. The UI keeps Wi-Fi probe sniffing visible as an unavailable subsystem because standard mobile app sandboxes do not expose passive probe-request capture.
- SAR Mode defaults to off so routine mesh usage does not silently enable passive sensing.

### Battery and privacy notes

- Continuous passive scanning increases battery usage more than ordinary mesh relay because BLE scanning, microphone summaries, and optional SOS advertising stay warm while SAR Mode is active.
- Detected device identifiers are anonymized before persistence or relay. MAC-style identifiers keep the first four octets and zero the last two: `AA:BB:CC:DD:EE:FF` becomes `AA:BB:CC:DD:00:00`.
- Raw audio is never sent over mesh and is never uploaded to the backend. Only the on-device acoustic classification result is serialized into the survivor-signal packet.

### Acoustic model constraints

- Acoustic classification runs on 5-second windows and emits only `tapping`, `voice`, `anomalous_sound`, or `none`.
- The current implementation uses Android-side 5-second audio summaries plus a lightweight heuristic classifier so the pipeline can run locally without shipping a heavy model asset yet.
- A future model refresh should stay on-device, remain small enough for offline responders, and preserve the same output labels so packet consumers do not break.

### Survivor signal lifecycle

1. A SAR subsystem detects a nearby signal and normalizes it into the canonical `SURVIVOR_SIGNAL` payload. On Android this is currently driven by native BLE scan events, native SOS advertising/reception, and native 5-second microphone summaries.
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
- Resolve actions call the existing survivor-signal resolve API when the device is online. If the API is unavailable or the signal has not reached the backend yet, the compass screen emits a STATUS_UPDATE mesh packet targeted at SURVIVOR_SIGNAL so the gateway can resolve the signal once connectivity returns.

## Interactive Mesh Map Extension (4-EXT.3)

- Gateways can attach a `topologySnapshot` payload to `POST /api/mesh/ingest`. The server persists the latest node state in `mesh_topology_nodes` and exposes it through `GET /api/mesh/topology` for municipality and department dashboards.
- `GET /api/mesh/topology` returns only nodes seen within the last 30 minutes and flags them as stale after 5 minutes without a fresh gateway upload. Operators should treat stale nodes as last-known positions rather than live peer discovery.
- Survivor-signal responses now include GeoJSON-ready `coordinates` and `geometry` fields so the web map can render signal markers directly.
- The municipality Mesh & SAR page overlays disaster reports, mesh nodes, responder markers, and survivor signals on the same Leaflet map. Topology refreshes every 30 seconds while survivor signals refresh through Supabase Realtime.


## Survivor Trail Extension (4-EXT.5)

- Mobile emits `LOCATION_BEACON` packets every 30 seconds while SAR Mode is active or the device is operating in mesh-only mode. The cadence tightens to 10 seconds while SOS advertising is active so responders get a denser breadcrumb trail during a live rescue.
- Device fingerprints remain anonymized before the beacon is queued. The same anonymized identifier is reused by survivor detection and trail rendering so the SAR feed, compass, and web map can converge on the same device history.
- Municipality and department users can fetch trail history through `/api/mesh/trail/:deviceFingerprint` and the active endpoint list through `/api/mesh/last-seen`. Citizens do not receive these location-history surfaces.
- The Survivor Compass minimap now layers breadcrumb trail points under the target marker. Points older than 10 minutes stay visible but render in a faded treatment so responders can distinguish stale movement from the current corridor.
- The municipality Mesh & SAR dashboard renders semi-transparent trail polylines, endpoint pins with last-seen metadata, and a trail sidebar styled to match the warm feed/comms cards already used elsewhere in the site.
- Trail data is retained for 72 hours by default and should be removed earlier when an approved privacy request or post-incident cleanup plan requires it. Early deletion should remove the matching `device_location_trail` rows and any exported copies derived from the same anonymized fingerprint.

## Mesh-Routed Communications Extension (4-EXT.4)

- `MESH_MESSAGE` and `MESH_POST` are now part of the canonical packet envelope. `MESH_MESSAGE` uses the same relay priority as `STATUS_UPDATE`; `MESH_POST` uses the same relay priority as `ANNOUNCEMENT`.
- The backend keeps using `mesh_messages` as the dedup and ingest audit log. Threaded server-side comms history lives in `mesh_comms_messages` so the original Phase 4 table name is not overloaded.
- `POST /api/mesh/ingest` now persists `MESH_MESSAGE` packets into `mesh_comms_messages` and `MESH_POST` packets into the normal `posts` table with `mesh_originated = true`.
- `GET /api/mesh/messages?threadId=` lets authenticated clients recover thread history and mesh-authored post context after connectivity returns.
- Department-authored `MESH_POST` packets require a valid cached offline verification token on both the mobile client and the gateway ingest path. If a queued post reaches the server after that token expires, the gateway rejects it with a token-expired error and the mobile inbox item remains unsynced until the user signs in again.
- Broadcast `MESH_MESSAGE` packets are intentionally relayed to all nodes in range, so operators should treat them as low-privacy traffic. Department and direct scopes narrow what is surfaced in the app UI, but broadcast payloads still move through nearby relays during a blackout.
- Sensitive mesh comms are retained in `mesh_comms_messages` and `posts` for incident audit until normal operational cleanup. Post-incident deletion should remove the corresponding `mesh_comms_messages` rows and any `mesh_originated` posts together when a conversation or advisory must be purged.
- Native mobile now persists the Offline Comms inbox through the shared `mesh_inbox` SQLite service. Flutter web keeps its browser localStorage adapter because the shared database wiring is native-only.
- The municipality Mesh & SAR dashboard now includes a feed-aligned Mesh Comms card so operators can review recent mesh messages and mesh-originated posts without leaving the map workflow.
