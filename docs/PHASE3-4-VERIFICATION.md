# Phase 3-4 Verification Guide

This guide freezes the current core Phase 3 and core Phase 4 verification baseline and separates:

- automated verification already covered in-repo
- prepared manual field checks that still require physical devices
- items intentionally out of scope for this core completion pass

## Automated Baseline

Run these commands from a clean working tree before changing Phase 3 or Phase 4 behavior:

```bash
# API
cd services/api
uv run pytest tests/test_phase3.py tests/test_phase4.py

# Web
cd apps/web
corepack pnpm test
corepack pnpm build

# Mobile full environment
cd apps/mobile
flutter analyze
flutter test

# Mobile fallback for this Windows host when plugin symlinks are unavailable
cd apps/mobile
flutter test --no-pub test/mesh_transport_test.dart test/survivor_compass_screen_test.dart test/offline_comms_screen_test.dart
```

## Phase 3 Coverage

### Bilingual static labels

Supported EN/FIL switching in this core pass is limited to static UI labels on:

- web municipality reports, analytics, and assessments
- web department assessments
- web shared report timeline and status labels on citizen report detail
- web shared shell/navigation labels that route into the supported Phase 3 screens
- mobile department assessment screen
- mobile citizen report detail timeline/status labels
- mobile shared sign-out/language actions on the supported entry points

These remain intentionally untranslated:

- user-generated descriptions, notes, and free text
- backend-provided free text payloads
- historical seeded/demo content
- raw enum values that are not already mapped to user-facing labels

### Phase 3 automated checks by area

| Area | Primary automated coverage |
|------|-----------------------------|
| Municipality report filtering | `services/api/tests/test_phase3.py`, `apps/web/src/pages/municipality/municipality-reports-page.test.tsx` |
| Municipality analytics fixtures | `services/api/tests/test_phase3.py`, `apps/web/src/pages/municipality/municipality-analytics-page.test.tsx` |
| Municipality assessments list/empty state | `services/api/tests/test_phase3.py`, `apps/web/src/pages/municipality/municipality-assessments-page.test.tsx` |
| Department assessment submit/history | `services/api/tests/test_phase3.py`, `apps/web/src/pages/department/department-assessment-page.test.tsx`, `apps/mobile/test/department_assessment_screen_test.dart` |
| Expanded report timeline payload | `services/api/tests/test_phase3.py`, `apps/web/src/pages/citizen/citizen-report-detail-page.test.tsx`, `apps/mobile/test/citizen_report_detail_locale_test.dart` |
| Locale switching on supported screens | web Phase 3 page tests above plus `apps/mobile/test/department_assessment_screen_test.dart` and `apps/mobile/test/citizen_report_detail_locale_test.dart` |
| Responsive smoke | `apps/web/e2e/phase3-responsive.spec.ts` |

## Phase 4 Ready-For-Field-Execution Matrix

Core Phase 4 implementation is treated as **ready for device validation**. Physical execution is still pending by design because it requires BLE-capable hardware.

| Core checklist item | Automated coverage | Manual field step |
|---------------------|--------------------|-------------------|
| Mesh ingest, idempotency, and acknowledgements | `services/api/tests/test_phase4.py` | Test 1 and Test 5 in `docs/MESH-FIELD-TEST-PROCEDURE.md` |
| Distress priority and persistence | `services/api/tests/test_phase4.py` | Test 3 |
| Offline department announcement token enforcement | `services/api/tests/test_phase4.py`, mobile mesh tests | Test 2 |
| Status-update rebroadcast readiness | `services/api/tests/test_phase4.py`, mobile mesh tests | Test 4 |
| Local queue, dedup, hop-limit, and relay behavior | `apps/mobile/test/mesh_transport_test.dart` | Test 1, Test 5, Test 6 |
| Large-payload handoff behavior | mobile mesh transport tests | Test 7 |
| Mesh communications relay/thread recovery | offline comms Flutter tests and Phase 4 API tests | Test 8 |
| Mesh status panel and SAR-ready mobile surfaces | survivor/mesh Flutter tests | capture evidence during Tests 1-8 |

## Hardware Field-Test Preflight

Before running the manual Phase 4 procedure:

1. Confirm at least 2 physical BLE-capable devices are available. Prefer 3 when validating relay plus gateway behavior.
2. Confirm one device can reach the backend URL and the others can run in airplane mode with Bluetooth enabled.
3. Seed and verify at least one citizen account and one approved department account.
4. Confirm the mobile build points at the correct backend URL and that the gateway device can log in online.
5. Reset local mesh state using the procedure in `docs/MESH-FIELD-TEST-PROCEDURE.md`.
6. Decide who is acting as origin, relay, and gateway before starting the run.
7. Capture evidence for each run:
   - device models and OS versions
   - backend URL
   - screenshots of mesh status panels
   - server-side evidence for synced rows
   - noteworthy latency or relay anomalies

## Result Logging

Use the reporting template already included at the end of `docs/MESH-FIELD-TEST-PROCEDURE.md`. That template is the canonical result log for physical Phase 4 execution in this repo.

## Out Of Scope For This Core Pass

- any new Phase 4 packet types, endpoints, or transport contracts
- the remaining `4-EXT` carryover tracked in `docs/phase4-extended.md`
- locale persistence beyond the current in-memory session
