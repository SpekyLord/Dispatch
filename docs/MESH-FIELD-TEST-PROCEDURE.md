# Mesh Field-Test Procedure (Phase 4)

Manual hardware verification for Phase 4 mesh networking.

Status on **April 4, 2026**:
- Automated verification is complete in-repo.
- Physical multi-device execution is **prepared** and still **pending by design**.

---

## Scope

This procedure validates:
- offline report relay
- offline department announcement relay
- SOS distress propagation
- deduplication and hop-limit behavior
- mesh comms relay + history recovery
- topology snapshot visibility on gateway sync

This procedure does **not** require:
- passive Wi-Fi probe sniffing (not available in standard mobile app sandbox)

---

## Prerequisites

- 2 to 4 physical Android devices (BLE-capable); 3+ devices recommended for relay/hop tests
- Dispatch mobile app installed on all devices
- One device designated as **Gateway** (internet on)
- At least one **department or municipality** account for gateway topology checks
- At least one citizen account
- Backend URL reachable from the gateway device
- Seeded accounts and data from the normal setup docs

---

## Preflight Checklist (Run Before Test 1)

1. On each device, open the app and approve required permissions:
- Location
- Bluetooth / Nearby devices
- Nearby Wi-Fi devices (Android 13+ where shown)
- Microphone (for SAR/acoustic flows)
2. Confirm mesh status panel opens without permission errors.
3. Confirm gateway device is logged in and online.
4. Confirm non-gateway test devices can run offline (airplane mode + Bluetooth on).
5. Confirm at least one gateway-role test account is `department` or `municipality` for topology/survivor endpoints.

---

## Test 1: Offline Incident Report Relay

**Goal:** A citizen report created offline reaches the server through relays and returns ACK state.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Log in as citizen, submit an incident report | Report queued locally; mesh queue size = 1 |
| 2 | Device A | Open mesh status panel | Role shows origin/relay, queue >= 1 |
| 3 | Device B (relay, offline) | Keep app active and nearby | Peer discovery occurs; packet relays |
| 4 | Device C (gateway, online) | Keep app active and sync | Gateway ingests packet via `POST /api/mesh/ingest` |
| 5 | Device C | Check mesh status panel | Queue drains; last sync updates |
| 6 | Server | Check reports data | New report exists with mesh-origin marker |
| 7 | Server | Check topology data | Gateway node appears/updates with fresh sync time |
| 8 | Web dashboard | Open Mesh/SAR map | Topology updates appear within polling interval |
| 9 | Device A | Wait for ACK propagation | Queue item becomes synced |

**Pass criteria:** One server record only, topology updated, ACK reaches origin.

---

## Test 2: Offline Department Announcement Relay

**Goal:** Verified department can post offline with valid token; invalid token path fails safely.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A | Log in as verified department while online | Offline verification token cached |
| 2 | Device A | Go offline (airplane mode + Bluetooth on) | App remains usable in mesh mode |
| 3 | Device A | Create announcement | `ANNOUNCEMENT` packet queued |
| 4 | Device B (gateway, online) | Receive/relay/sync | Packet ingested by gateway |
| 5 | Server | Check `posts` | Mesh-originated post created |
| 6 | Device A | Wait for ACK | Queue entry marked synced |

**Negative case (expired/missing token):**

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 7 | Device X (offline) | Attempt department announcement with expired/missing token | App blocks creation with clear message |
| 8 | Server | If forged packet reaches ingest | Server rejects; mesh message marked error |

**Pass criteria:** Valid token succeeds, invalid token is blocked/rejected.

---

## Test 3: SOS Distress Signal Propagation

**Goal:** Distress works without login and is prioritized.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline, no login) | Trigger SOS | `DISTRESS` packet queued with high priority |
| 2 | Device B/C | Relay toward gateway | Distress relayed with hop increments |
| 3 | Gateway | Sync queue | Distress ingested ahead of normal traffic |
| 4 | Server | Check distress storage | Distress row exists with correct origin/hop metadata |
| 5 | Re-ingest check | Resend same message ID | Duplicate handling prevents duplicate distress row |

**Pass criteria:** Distress ingested once, prioritized, deduplicated correctly.

---

## Test 4: Server Update Injection Back Into Mesh

**Goal:** Online server-side status changes reach offline devices via mesh rebroadcast.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Web/API | Change report status (e.g., `accepted`) | Status history written server-side |
| 2 | Gateway | Pull `GET /api/mesh/sync-updates` | Updated status included in response |
| 3 | Gateway | Rebroadcast update packets | Nearby offline devices receive status update |
| 4 | Offline citizen device | Open report detail | New status appears without direct internet |

**Pass criteria:** Offline client reflects server status transition after mesh rebroadcast.

---

## Test 5: Multi-Path Deduplication

**Goal:** Same message relayed through multiple paths creates one server-side effect.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A | Create report/message | Packet queued |
| 2 | Devices B and D | Relay same message to gateway | Gateway sees duplicate `messageId` arrivals |
| 3 | Gateway | Ingest both copies | First processed, second marked duplicate |
| 4 | Server | Inspect records | Exactly one linked domain record |

**Pass criteria:** No duplicate domain record for same `messageId`.

---

## Test 6: Hop-Limit Enforcement

**Goal:** Packets stop relaying once `hopCount >= maxHops`.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A | Emit packet with low max hops | Starts at `hopCount = 0` |
| 2 | Relay chain B then C | Relay packet | Hop count increments each relay |
| 3 | Next relay device D | Receives with hop limit reached | Packet dropped, not relayed onward |

**Pass criteria:** No forwarding after max hops threshold.

---

## Test 7: Large Payload Transport Fallback (Wi-Fi Direct Optional)

**Goal:** Large payload transfer remains reliable, with Wi-Fi Direct when available and BLE fallback otherwise.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A | Create large payload report (e.g., multiple images) | Transfer path selection attempts large-payload strategy |
| 2 | Nearby relay/gateway | Receive payload | Delivery succeeds |
| 3 | If Wi-Fi Direct supported and negotiated | Observe transport | Wi-Fi Direct path may be used |
| 4 | If Wi-Fi Direct unavailable/fails | Observe fallback | BLE fragmentation path used, still delivered |

**Pass criteria:** Delivery succeeds; Wi-Fi Direct use is optional, BLE fallback is valid.

---

## Test 8: Mesh Comms (MESH_MESSAGE / MESH_POST)

**Goal:** Offline messages/posts relay and history is recoverable after sync.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Device A (offline) | Send Offline Comms message | `MESH_MESSAGE` queued and visible locally |
| 2 | Relay/gateway device | Relay + ingest | Message stored server-side |
| 3 | Device A (online later) | Open thread history | History recovered from API |

**Pass criteria:** Offline persistence + successful server recovery of thread history.

---

## Test 9: Topology-Only Gateway Sync

**Goal:** Gateway can publish topology snapshot even when packet queue is empty.

| Step | Device | Action | Expected Result |
|------|--------|--------|-----------------|
| 1 | Gateway (department/municipality account) | Ensure queue is empty | Mesh queue shows 0 |
| 2 | Gateway | Trigger mesh status refresh/sync | Topology snapshot upload attempted |
| 3 | Server | Inspect topology endpoint/data | Node `synced_at` refreshes |
| 4 | Web dashboard | Observe map | Fresh topology state appears after polling |

**Pass criteria:** Topology updates without requiring queued payload packets.

---

## Expected Role-Based API Behavior

These are **expected**, not failures:

- `citizen` hitting `/api/mesh/topology` can return `403`
- `citizen` hitting `/api/mesh/survivor-signals` can return `403`
- topology/survivor operator checks should use `department` or `municipality` accounts

---

## Environment Reset Between Tests

1. Clear mobile mesh local state (`mesh_queue`, seen-message cache, peer cache) or reinstall debug build.
2. Reset relevant server rows when validating dedup and fresh state behavior.
3. Clear stale peer discovery by toggling Bluetooth/app restart.
4. Reconfirm permissions after reinstall/device reboot.

---

## Reporting Template

| Field | Value |
|-------|-------|
| Test # | |
| Date | |
| Devices used (model + OS) | |
| App build/branch/commit | |
| Backend URL | |
| Account roles used | |
| Result | Pass / Fail / Partial |
| Notes (latency/errors) | |
| Evidence (screenshots/logs) | |

---

## Quick Triage Notes

- Queue not draining + `403` topology/survivor calls: verify account role (use department/municipality for operator APIs).
- Missing permission prompts: open OS app settings and grant permissions manually, then relaunch app.
- Device discovery unstable: keep screens awake, Bluetooth on, and app foregrounded during relay tests.
