# Mesh Field-Test Procedure

Manual device-to-device verification steps for Phase 4 mesh networking.
These tests require **2+ physical Android/iOS devices** with BLE and optional WiFi Direct support.

---

## Prerequisites

- At least 2 Android devices (API 28+) or iOS devices (iOS 14+) with BLE
- The Dispatch mobile app installed on all devices
- One device designated as **Gateway** (has internet connectivity)
- Other devices in **airplane mode** (WiFi/cellular off, Bluetooth on)
- A running backend at a reachable URL for the gateway device
- At least one verified department account and one citizen account seeded in the database

---

## Test 1: Offline Incident Report Relay

**Goal:** A citizen report created offline reaches the server via a relay chain.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Log in as citizen, submit an incident report with description and category | Report queued locally; mesh status panel shows queue size = 1 |
| 2 | Device A | Open mesh status panel | Role shows "Origin", queue size >= 1, peer count updates when B is nearby |
| 3 | Device B (relay, offline) | Open app, ensure mesh is active | Device B discovers Device A via BLE; peer count increments |
| 4 | — | Wait ~10 seconds for BLE relay | Device B receives the packet; its seen-messages log includes the messageId |
| 5 | Device C (gateway, online) | Open app with internet on | Device C discovers Device B, receives relayed packet, uploads to `POST /api/mesh/ingest` |
| 6 | Device C | Check mesh status panel | Queue drains to 0; last sync time updates |
| 7 | Server | Query `GET /api/reports` or check DB | New report exists with `is_mesh_origin = true` and a linked `mesh_messages` dedup entry |
| 8 | Device C | Observe SYNC_ACK rebroadcast | SYNC_ACK packet propagates back toward Device A |
| 9 | Device A | Check mesh status panel | Queue entry marked as synced after receiving the SYNC_ACK |

**Pass criteria:** Report visible on server, no duplicate records, SYNC_ACK reaches origin.

---

## Test 2: Offline Department Announcement Relay

**Goal:** A verified department can broadcast an announcement offline; unverified devices cannot.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Log in as verified department while still online to cache the offline verification token | Token cached with 30-day TTL |
| 2 | Device A | Switch to airplane mode (Bluetooth on) | Device goes offline; mesh role becomes "Origin" |
| 3 | Device A | Create an announcement post from the department home screen | `ANNOUNCEMENT` packet queued locally with the embedded verification token |
| 4 | Device B (gateway, online) | Discover Device A and receive the relayed packet | Gateway uploads packet to `POST /api/mesh/ingest` |
| 5 | Server | Check `posts` table | New post exists with `mesh_originated = true`; token validated successfully |
| 6 | Device A | Check mesh status panel | SYNC_ACK received; queue entry marked synced |

**Negative case — expired/missing token:**

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 7 | Device X (offline) | Log in as department but with expired or missing offline token | App blocks announcement creation with a clear error message |
| 8 | — | If a forged announcement packet somehow reaches the gateway | Server rejects the packet; `mesh_messages` entry has `processing_state = error` |

**Pass criteria:** Valid announcement reaches server and appears in feed; expired-token announcement is blocked on device and rejected by server.

---

## Test 3: SOS Distress Signal Propagation

**Goal:** A distress signal created without login propagates with highest priority and wider hop range.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline, not logged in) | Tap the SOS button on the home screen | `DISTRESS` packet created with `maxHops = 15` and queued |
| 2 | Device A | Observe mesh status panel (if accessible) or check queue | Distress packet is at front of queue (priority 0) |
| 3 | Device B (relay, offline) | Nearby, mesh active | Receives distress packet; relays it; hopCount increments by 1 |
| 4 | Device C (gateway, online) | Receives relayed distress packet | Uploads immediately; distress packets sorted to front of ingest batch |
| 5 | Server | Check `distress_signals` table | New distress record with correct `origin_device_id`, coordinates, hop count |
| 6 | Server | Check notifications | Municipality users notified of the distress signal |
| 7 | — | Verify immutability | Attempting to re-ingest the same `messageId` returns `duplicate`, no new record created |

**Pass criteria:** Distress reaches server with priority handling, municipality notified, no duplicates on re-ingest.

---

## Test 4: Server Update Injection into Mesh

**Goal:** A gateway pulls server-side status changes and rebroadcasts them so offline devices see updated report statuses.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Server/Web | A department accepts an incident report via the web dashboard, changing status to `accepted` | `report_status_history` entry created |
| 2 | Device C (gateway) | Calls `GET /api/mesh/sync-updates?since=<last_sync>` | Response includes the status change in `report_updates` and `status_history` |
| 3 | Device C | Rebroadcasts `STATUS_UPDATE` packets into mesh | Nearby offline devices receive the update |
| 4 | Device A (offline, citizen) | Check report detail screen | Report status updated to `accepted` from the mesh-relayed STATUS_UPDATE |

**Pass criteria:** Offline device reflects the server-side status change without needing its own internet connection.

---

## Test 5: Mesh Deduplication Under Multi-Path Relay

**Goal:** The same packet arriving from multiple relay paths does not create duplicate records.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Submit an incident report | Packet queued |
| 2 | Devices B & D (relays) | Both receive and relay the same packet to Device C (gateway) | Gateway receives 2 copies with same `messageId` |
| 3 | Device C (gateway) | Uploads both to `POST /api/mesh/ingest` | First processed normally; second returns `duplicate` status |
| 4 | Server | Check `incident_reports` and `mesh_messages` | Exactly 1 report, exactly 1 dedup entry |

**Pass criteria:** Single server record regardless of relay path count.

---

## Test 6: Hop Limit Enforcement

**Goal:** Packets exceeding `maxHops` are dropped and not relayed further.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A | Create a packet with `maxHops = 2` (test override or use a normal report with default 7 and chain enough devices) | Packet queued with `hopCount = 0` |
| 2 | Device B (relay) | Receives and relays | `hopCount` incremented to 1 |
| 3 | Device C (relay) | Receives and relays | `hopCount` incremented to 2 |
| 4 | Device D (relay) | Receives packet with `hopCount = 2`, `maxHops = 2` | Packet dropped; not relayed further |

**Pass criteria:** Device D does not relay the packet; `hopCount >= maxHops` triggers drop.

---

## Test 7: WiFi Direct Handoff for Large Payloads

**Goal:** Payloads above 10 KB automatically negotiate WiFi Direct instead of BLE.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Submit a report with 3 attached images (total payload > 10 KB) | Transport selection picks WiFi Direct |
| 2 | Device B (nearby) | Accept WiFi Direct connection | Large payload transferred over WiFi Direct |
| 3 | — | If WiFi Direct negotiation fails | Falls back to BLE fragmentation; packet still delivered (slower) |

**Pass criteria:** Large payloads use WiFi Direct when available; BLE fragmentation is the fallback.

---

## Test 8: Mesh Communications (MESH_MESSAGE / MESH_POST)

**Goal:** Offline direct messages and mesh posts relay correctly and recover thread history on sync.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline, department) | Open Offline Comms, send a message in a thread | `MESH_MESSAGE` packet queued; appears in local inbox |
| 2 | Device B (relay/gateway) | Receives and relays or uploads | Message reaches server; stored in `mesh_comms_messages` |
| 3 | Device A | Reconnects to internet, opens Offline Comms | Thread history recovered from server via `GET /api/mesh/messages?threadId=...` |

**Pass criteria:** Messages persist locally offline, sync to server, and thread history is recoverable.

---

## Environment Reset Between Tests

1. Clear the `mesh_queue`, `seen_messages`, and `mesh_peers` SQLite tables on each device (reinstall or use a debug reset)
2. Clear `mesh_messages` and `distress_signals` on the server if testing dedup behavior
3. Ensure all devices have fresh BLE discovery state

---

## Reporting Template

For each test, record:

| Field | Value |
|-------|-------|
| Test # | |
| Date | |
| Devices used | (model, OS version) |
| Backend URL | |
| Result | Pass / Fail / Partial |
| Notes | (latency observed, unexpected behavior, error messages) |
| Screenshots | (mesh status panel, server DB queries) |
