# Dispatch API

Phase 2 Flask API for the Dispatch emergency response platform.

## Commands

```powershell
uv sync --group dev
uv run dispatch-api
uv run ruff check .
uv run ruff format .
uv run pytest
```

## Phase 2 Summary

- Reports auto-categorize from English and Filipino keywords when the citizen does not choose a category.
- Manual category selection still wins when a citizen provides one.
- Verified departments only see reports routed to their department type, plus escalated catch-all visibility when the routing matrix allows it.
- Department responses are append-only. The latest response per department is the current visible state on the roster.
- The first acceptance moves a report from `pending` to `accepted`. Departments then advance reports through `responding` and `resolved`.
- Pending reports escalate immediately after all primary departments decline, or after 120 seconds with no acceptance.
- Municipality users can trigger the timeout scan with `POST /api/system/report-escalations/scan`.

## Routing Matrix

| Category | Primary departments | Escalation visibility |
|----------|---------------------|-----------------------|
| `fire` | `fire` | `disaster` + municipality notifications |
| `flood` | `disaster` | municipality notifications |
| `earthquake` | `disaster` | municipality notifications |
| `road_accident` | `police` | `disaster` + municipality notifications |
| `medical` | `medical`, `rescue` | `disaster` + municipality notifications |
| `structural` | `disaster` | municipality notifications |
| `other` | `disaster` | municipality notifications |

## Response Model

- `POST /api/departments/reports/:id/accept` appends an `accepted` response.
- `POST /api/departments/reports/:id/decline` appends a `declined` response and requires `decline_reason`.
- `GET /api/departments/reports/:id/responses` returns the latest state for every visible department, including pending departments with no response yet.
- Department declines never set `incident_reports.status = rejected`.

## Notification Triggers

| Notification type | Trigger |
|-------------------|---------|
| `new_report` | New routed incident reports and escalated incidents |
| `report_update` | Acceptance, status progression, and escalation updates for the reporting citizen |
| `verification_decision` | Municipality approval or rejection of a department |
| `announcement` | New verified-department feed posts for citizens |

## Public Feed

- `POST /api/departments/posts` is restricted to verified departments.
- `GET /api/feed` and `GET /api/feed/:id` are public read endpoints.
- Feed responses include a compact department snapshot for display.
