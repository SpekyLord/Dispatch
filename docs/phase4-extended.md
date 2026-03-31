# Phase 4 Extended - Survivor Detection, SAR Navigation, and Mesh-Integrated Communications

> **Scope note:** This document is a supplemental phase task for Phase 4 only.
> It does not replace `docs/phasetask.md`. It extends Phase 4 with additional
> sub-tasks that align the mesh system to search-and-rescue (SAR) operations,
> passive survivor detection, compass-guided mobile navigation, and mesh-routed
> communications. All items here are additive and must not break the behavior
> defined in the canonical `docs/phasetask.md` Phase 4 checklist.
>
> An AI coding agent working from this file must also read `docs/PRD.md` and
> `docs/phasetask.md` in full before touching any code. Do not invent features
> outside the scope described below.

---

## 4-EXT.1 - Passive Survivor Detection (SAR Mode)

**Objective**

Equip mesh nodes with passive sensing so rescue teams can detect nearby
survivors without requiring the survivor to actively interact with the app.
Detection events are wrapped in the canonical mesh packet envelope and relayed
to the gateway as `SURVIVOR_SIGNAL` payloads.

**New canonical `payloadType` value**

Add `SURVIVOR_SIGNAL` to the existing `payloadType` enum. A `SURVIVOR_SIGNAL`
packet is treated as equal-priority to `DISTRESS`. It uses `maxHops = 15`.

**`SURVIVOR_SIGNAL` payload contract**

```json
{
  "detectionMethod": "WIFI_PROBE | BLE_PASSIVE | ACOUSTIC | SOS_BEACON",
  "signalStrengthDbm": -72,
  "estimatedDistanceMeters": 4.5,
  "detectedDeviceIdentifier": "partial-mac-or-ble-address-anonymized",
  "lastSeenTimestamp": "ISO-8601",
  "nodeLocation": {
    "lat": 10.7202,
    "lng": 122.5621,
    "accuracyMeters": 8
  },
  "confidence": 0.84,
  "acousticPatternMatched": "tapping | voice | anomalous_sound | none"
}
```

### Build Checklist - 4-EXT.1

#### Database / Supabase

- [x] Add a `survivor_signals` table with columns: `id`, `message_id` (FK to
  `mesh_messages`), `detection_method`, `signal_strength_dbm`,
  `estimated_distance_meters`, `detected_device_identifier`,
  `last_seen_timestamp`, `node_location` (PostGIS point or JSON lat/lng),
  `confidence`, `acoustic_pattern_matched`, `created_at`, `resolved_at`,
  `resolved_by`.
- [x] Add a `resolved` boolean and `resolved_by` FK so rescue teams can mark a
  signal as located or false-positive without deleting the audit record.
- [x] Ensure delayed upload path (offline -> gateway -> server) is supported for
  `SURVIVOR_SIGNAL` packets via the existing mesh ingest flow.

#### Flask API

- [x] Extend `POST /api/mesh/ingest` to handle `SURVIVOR_SIGNAL` payloadType
  with the same idempotency contract already defined for `DISTRESS`.
- [x] Add `GET /api/mesh/survivor-signals` (municipality and department roles
  only) with filters: `status` (`active`, `resolved`), `detection_method`,
  bounding box, time range.
- [x] Add `PUT /api/mesh/survivor-signals/:id/resolve` so verified responders
  can mark a signal resolved with a free-text note.
- [x] Fast-path ingest for `SURVIVOR_SIGNAL` matching the existing `DISTRESS`
  fast-path so gateway delay is minimal.

#### Mobile App

- [x] Add a SAR Mode toggle in the mesh status panel. SAR Mode enables the
  passive sensing subsystems below. Default: off. Requires department or
  designated rescuer role to enable.
- [ ] **Wi-Fi probe sniffing:** Use platform Wi-Fi scan APIs to passively
  collect probe-request signal strengths. Do not connect to any network. Record
  `detectedDeviceIdentifier` as an anonymized partial MAC (last two octets
  zeroed). Wrap as `SURVIVOR_SIGNAL` with `detectionMethod = WIFI_PROBE`.
- [ ] **BLE passive scanning:** Use `flutter_blue_plus` or equivalent to
  continuously scan for any advertising BLE device (phones, wearables, earbuds)
  without initiating a connection. Record RSSI and anonymized partial address.
  Wrap as `SURVIVOR_SIGNAL` with `detectionMethod = BLE_PASSIVE`.
- [ ] **SOS beacon reception:** If a device is running the app and broadcasting
  its own SOS beacon (see 4-EXT.1 beacon broadcast below), detect it via BLE
  advertisement. Treat as highest-confidence signal. Wrap as `SURVIVOR_SIGNAL`
  with `detectionMethod = SOS_BEACON` and confidence = 1.0.
- [ ] **Acoustic detection:** Use the device microphone in 5-second sample
  windows to run a lightweight on-device classifier. Classify samples as
  `tapping`, `voice`, `anomalous_sound`, or `none`. Trigger a
  `SURVIVOR_SIGNAL` packet only on positive classification. Classification must
  run entirely on-device - do not send raw audio over the mesh or to the
  backend.
- [ ] **SOS beacon broadcast:** Any logged-in or anonymous user who triggers
  the no-login SOS action (already in core Phase 4) also begins broadcasting a
  detectable BLE advertisement with a standardized service UUID so nearby SAR
  nodes can pick it up passively.
- [x] Deduplicate survivor signals from the same estimated source within a
  60-second window per sensing method before generating a new packet.
- [x] Show a SAR detection feed in the department mobile view listing active
  `SURVIVOR_SIGNAL` events received locally, sorted by estimated proximity and
  confidence.

#### Realtime / Offline Transport

- [x] Give `SURVIVOR_SIGNAL` the same relay priority as `DISTRESS` in the mesh
  queue.
- [x] Apply the existing seen-message deduplication log to `SURVIVOR_SIGNAL`
  packets to prevent re-relay storms.

#### Tests

- [ ] Unit tests for Wi-Fi probe parser, BLE scan RSSI extractor, and acoustic
  sample classifier mock.
- [x] Unit tests for `SURVIVOR_SIGNAL` serialization, deduplication window, and
  packet priority ordering.
- [x] API tests for `SURVIVOR_SIGNAL` ingest idempotency and resolve endpoint.
- [ ] Manual SAR field-test step: enable SAR Mode on two devices, place one in
  airplane mode with BLE on, confirm the SAR device appears in the detection
  feed on the other.

#### Docs

- [x] Document SAR Mode permissions, battery impact, privacy implications of
  passive scanning, and how anonymized device identifiers are generated and
  stored.
- [x] Document on-device acoustic model constraints (size limit, update path).
- [x] Document `SURVIVOR_SIGNAL` packet lifecycle from detection to server
  persistence to manual resolve.

### Status Note - 4-EXT.1

- Date: `2026-03-31`
- Completed: server persistence for `SURVIVOR_SIGNAL`, responder review/resolve API routes, mesh-priority relay + dedup, SAR Mode toggle, and the department-side mobile SAR feed are implemented and covered by API/mobile tests.
- Remaining: live Wi-Fi probe sniffing, live BLE passive scan intake, microphone-backed acoustic sampling, and actual BLE SOS beacon broadcast/reception are still helper- or stub-level hooks rather than platform-integrated passive sensing subsystems.


---

## 4-EXT.2 - Compass Navigation for Survivor Locating (Mobile)

**Objective**

Give rescue personnel an AirTag-style compass view on mobile that points toward
the nearest high-confidence survivor signal using the device's location and
bearing sensors. No new backend API is required for core compass function - the
signal data flows from the existing mesh and survivor-signal feed.

### Build Checklist - 4-EXT.2

#### Mobile App

- [x] Add a **Survivor Compass** screen accessible from the SAR detection feed
  (department role, SAR Mode enabled).
- [x] Fuse device GPS coordinates with the `nodeLocation` field of the nearest
  active `SURVIVOR_SIGNAL` to compute bearing and approximate distance.
- [x] Use the device magnetometer and accelerometer to render a real-time
  directional arrow that rotates as the rescuer turns, pointing toward the
  target signal. The arrow should show the cardinal direction label and distance
  estimate.
- [x] If the target signal comes from a mesh relay rather than a direct
  detection, display a confidence band and the number of hops the signal
  traveled.
- [x] Allow the rescuer to pin a target signal (from the feed list) as the
  active compass target. Only one target may be active at a time.
- [x] Show a minimap inset that displays the rescuer's current position, the
  estimated target position, and any nearby mesh peer nodes.
- [x] When the estimated distance to target drops below 3 meters, switch the
  compass view to a proximity pulse animation and play a haptic pattern.
- [ ] Mark a survivor signal as located directly from the compass screen,
  triggering `PUT /api/mesh/survivor-signals/:id/resolve` when connectivity is
  available or queuing the resolve action for mesh relay when offline.

#### Tests

- [x] Widget test for bearing calculation given mock GPS + target coordinates.
- [x] Widget test for compass rotation using a mock magnetometer stream.
- [x] Widget test for proximity pulse threshold trigger at < 3 m.

#### Docs

- [x] Document compass accuracy limitations, sensor fusion approach, and the
  expected error envelope when signal originates from a multi-hop relay vs.
  direct detection.

### Status Note - 4-EXT.2

- Date: `2026-03-31`
- Completed: the mobile SAR feed now opens a Survivor Compass screen with live heading input, GPS-to-signal bearing math, hop/confidence guidance, target pinning, a minimap inset, and a proximity pulse/haptic state under 3 meters.
- Remaining: offline resolve actions currently queue a local retry for the HTTP resolve call. They are not yet serialized into a dedicated mesh-relayed resolve packet, so the final checklist item for offline mesh resolve remains open.
- Constraint: nearby mesh peer markers on the minimap are rendered as a relative proximity ring until peer GPS coordinates are added to mesh sync payloads.

---

## 4-EXT.3 - Interactive Mesh Map (Web Dashboard)

**Objective**

Expose mesh topology and survivor signal activity on the web dashboard's
interactive Leaflet map so municipality operators and incident commanders can
see the disaster zone in real time.

### Build Checklist - 4-EXT.3

#### Flask API

- [ ] Add `GET /api/mesh/topology` (municipality and department roles) returning
  active peer nodes with their last-known GPS coordinates, role (origin, relay,
  gateway), peer count, and last-seen timestamp. Data sourced from gateway sync
  uploads.
- [ ] Extend `GET /api/mesh/survivor-signals` response to include GeoJSON-ready
  coordinates so the web map can render signal markers directly.

#### Web App

- [ ] Add a **Mesh & SAR** layer toggle on the municipality map view.
- [ ] When enabled, render:
  - **Mesh node markers** (triangles) color-coded by role: gateway (green),
    relay (yellow), origin/offline (grey). Node popup shows role, peer count,
    queue depth, and last sync.
  - **Survivor signal markers** (pulsing red circles) for active
    `SURVIVOR_SIGNAL` events. Popup shows detection method, confidence,
    estimated distance, and a resolve button for authorized users.
  - **Disaster report markers** (existing) remain visible in the same view.
  - **Responder markers** showing the last-known location of department devices
    active on the mesh (sourced from gateway sync peer data, municipality role
    only).
- [ ] Survivor signal markers animate a distance-accuracy radius ring based on
  `estimatedDistanceMeters`.
- [ ] Resolved signals fade to grey and remain on the map for 30 minutes for
  audit purposes, then are hidden by default (toggle to show).
- [ ] Add a live node count and active survivor signal count badge to the map
  toolbar.
- [ ] Realtime updates via Supabase Realtime subscription on `survivor_signals`
  and a periodic poll on `GET /api/mesh/topology` (30-second interval).

#### Tests

- [ ] Unit tests for mesh topology API response shape.
- [ ] Web component tests for mesh layer toggle, node marker rendering, and
  survivor signal popup content.

#### Docs

- [ ] Document mesh topology data freshness (topology reflects gateway-uploaded
  state, not live BLE discovery), and how operators should interpret stale node
  data.

---

## 4-EXT.4 - Mesh-Routed Communications

**Objective**

Extend the existing mesh packet system so in-app messages, critical alerts, and
emergency social-media-style posts can be authored, relayed, and delivered via
mesh when internet is unavailable. This preserves the core comms layer for
citizens and responders in a full connectivity blackout.

**New canonical `payloadType` values**

- `MESH_MESSAGE` - a direct or group text message between app users, relayed
  over mesh.
- `MESH_POST` - a department-authored announcement post that propagates over
  mesh rather than waiting for online sync (treated as `ANNOUNCEMENT` type at
  the gateway but carries richer threading metadata offline).

### `MESH_MESSAGE` payload contract

```json
{
  "threadId": "uuid-v4",
  "recipientScope": "broadcast | department | direct",
  "recipientIdentifier": "device-fingerprint-or-department-id-or-null",
  "body": "text content, max 500 chars",
  "authorDisplayName": "Rescuer A",
  "authorRole": "citizen | department | anonymous",
  "authorOfflineToken": "hmac-signed-role-token-or-null"
}
```

### `MESH_POST` payload contract

```json
{
  "postId": "uuid-v4",
  "category": "alert | warning | safety_tip | update | situational_report",
  "title": "string max 100 chars",
  "body": "string max 1000 chars",
  "authorDepartmentId": "uuid-v4",
  "authorOfflineToken": "hmac-signed-department-token",
  "attachmentRefs": []
}
```

### Build Checklist - 4-EXT.4

#### Database / Supabase

- [ ] Add a `mesh_messages` log table for server-persisted `MESH_MESSAGE`
  packets: `id`, `thread_id`, `message_id` (FK mesh dedup), `recipient_scope`,
  `recipient_identifier`, `body`, `author_display_name`, `author_role`,
  `created_at`.
- [ ] Reuse the existing `posts` table for server-side `MESH_POST` ingestion -
  the gateway ingest should create a normal `post` record with a
  `mesh_originated = true` flag.
- [ ] Add a `mesh_originated` boolean column to the `posts` table defaulting to
  `false`. Do not change any existing post flow.

#### Flask API

- [ ] Extend `POST /api/mesh/ingest` to handle `MESH_MESSAGE` and `MESH_POST`
  payloadTypes with idempotency on `messageId`.
- [ ] For `MESH_POST` ingestion, validate the bundled `authorOfflineToken`
  against department authority rules before creating the `posts` record. Reject
  with `403` if invalid or expired.
- [ ] For `MESH_MESSAGE` ingestion, persist to `mesh_messages` for audit.
  Direct messages that have a known `recipientIdentifier` that is online should
  trigger a realtime notification event.
- [ ] Add `GET /api/mesh/messages?threadId=` (authenticated) so online clients
  can fetch thread history once connectivity is restored.

#### Mobile App

- [ ] Add an **Offline Comms** tab or panel accessible when SAR Mode is active
  or when the device is in mesh-only state (no internet).
- [ ] Allow any authenticated user (citizen or department) to compose and send a
  `broadcast` mesh message visible to all nodes in range. Max 500 characters.
  Wrap as `MESH_MESSAGE` with `recipientScope = broadcast`.
- [ ] Allow department users to send `department`-scoped mesh messages visible
  only to devices whose cached role token identifies them as department members.
- [ ] Allow department users to publish a `MESH_POST` announcement over mesh
  using their cached offline verification token. Block if token is missing or
  expired (consistent with existing announcement relay rule).
- [ ] Render received `MESH_MESSAGE` and `MESH_POST` packets in the Offline
  Comms panel in chronological order. Show author display name, role badge, and
  hop count.
- [ ] Persist received messages in local SQLite `mesh_inbox` table so they
  survive app restart.
- [ ] When internet is restored, sync the `mesh_inbox` to the backend via the
  gateway ingest endpoint.
- [ ] Unread mesh message badge on the Offline Comms tab icon.

#### Realtime / Offline Transport

- [ ] `MESH_MESSAGE` relay priority: same as `STATUS_UPDATE` (below `DISTRESS`
  and `SURVIVOR_SIGNAL`, above `INCIDENT_REPORT`).
- [ ] `MESH_POST` relay priority: same as `ANNOUNCEMENT`.
- [ ] Apply seen-message deduplication to both new payload types.
- [ ] Do not relay `direct`-scoped `MESH_MESSAGE` packets to nodes that are not
  the intended recipient (match on `recipientIdentifier` against local device
  fingerprint before forwarding).

#### Tests

- [ ] Unit tests for `MESH_MESSAGE` and `MESH_POST` serialization and priority
  ordering.
- [ ] API tests for `MESH_MESSAGE` ingest, thread fetch, and `MESH_POST`
  offline-token validation.
- [ ] Mobile widget tests for Offline Comms panel rendering, unread badge, and
  broadcast compose flow.
- [ ] Manual test: two offline devices exchange a broadcast mesh message; on
  internet restore the gateway ingests both; thread appears in web dashboard.

#### Docs

- [ ] Document `MESH_MESSAGE` privacy model (broadcast messages are relayed to
  all nodes in range), retention policy, and how to delete sensitive mesh
  messages post-incident.
- [ ] Document `MESH_POST` offline verification token requirement and what
  happens to queued posts when the token expires mid-incident.

---

## 4-EXT.5 - Survivor Trail (Last-Known-Location History)

**Objective**

Record a timestamped location trail for any device that has been seen on the
mesh. This gives rescue teams a breadcrumb trail showing where a survivor or
responder was last active, even if they have moved out of current detection
range.

### `LOCATION_BEACON` payload contract (new `payloadType`)

```json
{
  "deviceFingerprint": "anonymized-device-id",
  "displayName": "Survivor A (auto-generated) | null",
  "lat": 10.7202,
  "lng": 122.5621,
  "accuracyMeters": 12,
  "batteryPct": 34,
  "appState": "foreground | background | sos_active"
}
```

### Build Checklist - 4-EXT.5

#### Database / Supabase

- [ ] Add a `device_location_trail` table: `id`, `message_id` (FK mesh dedup),
  `device_fingerprint`, `display_name`, `location` (PostGIS point or JSON),
  `accuracy_meters`, `battery_pct`, `app_state`, `recorded_at`.
- [ ] Add a composite index on `(device_fingerprint, recorded_at DESC)` for
  efficient last-known-location queries.
- [ ] Add a TTL policy or scheduled delete job that removes trail points older
  than 72 hours post-incident (configurable, default 72 h).

#### Flask API

- [ ] Extend `POST /api/mesh/ingest` to handle `LOCATION_BEACON` payloadType.
- [ ] Add `GET /api/mesh/trail/:deviceFingerprint` returning the trail for a
  specific device over a time range (municipality and department roles).
- [ ] Add `GET /api/mesh/last-seen` returning the most recent `LOCATION_BEACON`
  per unique device fingerprint currently active on the mesh (municipality and
  department roles).

#### Mobile App

- [ ] Broadcast a `LOCATION_BEACON` packet every 30 seconds when SAR Mode is
  active or when the device is in mesh-only state. Use `maxHops = 7`.
- [ ] When the no-login SOS action is triggered, increase beacon frequency to
  every 10 seconds and set `appState = sos_active`.
- [ ] Show the survivor trail as a polyline overlay on the Survivor Compass
  minimap. Points older than 10 minutes render as faded.
- [ ] Display a **Last Seen** timestamp and location on the SAR detection feed
  entry for any device whose most recent detection was a `LOCATION_BEACON`.

#### Web App

- [ ] On the Mesh & SAR map layer (4-EXT.3), render `LOCATION_BEACON` trails as
  semi-transparent polylines per device fingerprint. Endpoints show a pin with
  last-seen timestamp.
- [ ] Allow operators to click a trail pin to open a sidebar showing the device
  display name, battery level, app state, and the last 10 trail points.

#### Tests

- [ ] API tests for `LOCATION_BEACON` ingest, trail fetch, and last-seen
  endpoint.
- [ ] Mobile unit test for beacon interval scheduler switching between normal
  (30 s) and SOS (10 s) modes.

#### Docs

- [ ] Document the privacy model for location trail data, who can access it,
  the 72-hour TTL, and how to request early deletion.

---

## Cross-Cutting Rules For This Extension

- All new `payloadType` values (`SURVIVOR_SIGNAL`, `MESH_MESSAGE`, `MESH_POST`,
  `LOCATION_BEACON`) must be added to the canonical packet envelope enum in
  both mobile and backend code.
- All new server tables must be linked to `mesh_messages.message_id` for
  deduplication audit traceability.
- All new API endpoints follow the Phase 4 role-guard rules: municipality and
  department roles for read/resolve, gateway device credential for ingest.
- No feature in this extension invents new user roles, new report status values,
  or new department types. Canonical enums in `docs/phasetask.md` remain
  authoritative.
- SAR Mode and Offline Comms are mobile-only features. Web surfaces are
  read-only and operator-focused.
- All passive sensing (Wi-Fi probe, BLE scan, acoustic) must display a visible
  user-facing disclosure in the app UI whenever the subsystem is active.

---

## Verification Checklist For Phase 4 Extension

- [ ] SAR Mode can be enabled and disabled from the mesh status panel without
  crashing or disrupting the existing mesh relay logic.
- [ ] A passive BLE scan detects a nearby device running the app in SOS mode
  and generates a `SURVIVOR_SIGNAL` packet that reaches the gateway.
- [ ] The acoustic classifier does not transmit raw audio and runs entirely
  on-device.
- [ ] The Survivor Compass points toward a pinned `SURVIVOR_SIGNAL` with correct
  bearing and switches to proximity pulse below 3 m.
- [ ] The Mesh & SAR map layer renders node markers, survivor signal markers,
  and trail polylines without regressing existing report map functionality.
- [ ] A broadcast `MESH_MESSAGE` authored offline on one device appears in the
  Offline Comms panel of a second device within mesh range.
- [ ] A `MESH_POST` authored offline with an expired offline token is rejected
  at both origination (mobile) and gateway ingest (API).
- [ ] A `LOCATION_BEACON` trail persists on the web map for a device that has
  gone offline, showing last-seen timestamp and location.
- [ ] All new ingest paths are idempotent - re-uploading the same `messageId`
  does not create duplicate server records.
- [ ] Existing Phase 4 core verification checklist items (from
  `docs/phasetask.md`) still pass after extension work is merged.

---

## Exit Criteria For Phase 4 Extension

- Rescue teams can passively detect nearby survivors without the survivor
  actively interacting with the app.
- Responders can navigate toward a detected survivor using the compass view on
  mobile.
- Municipality operators can see mesh topology, survivor signals, and device
  trails on the web map in near-real time.
- Critical communications (messages, announcements) survive a full connectivity
  blackout via mesh relay and sync to the backend on gateway restore.
- All extension work is additive and the canonical Phase 4 exit criteria remain
  satisfied.
