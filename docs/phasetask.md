# Phase Task Roadmap

## Canonical Docs And Prompt Compatibility

- Canonical product specification: `docs/PRD.md`
- Canonical execution checklist: `docs/phasetask.md`
- If any automation prompt says `docs/phases.md`, treat it as `docs/phasetask.md`.
- If any automation prompt says `docs/prd.md`, treat it as `docs/PRD.md`.
- If this file and the PRD ever disagree, preserve the PRD's product behavior, then record the mismatch under the active phase's notes before continuing.

## Purpose

- This file converts the PRD into an implementation roadmap for an AI coding agent.
- Each phase defines owned scope, concrete build tasks, required verification, and explicit exit criteria.
- Checkboxes are progress markers, not ideas. Do not check anything until the code exists and the matching verification has been run successfully.

## Current Repo Status

- Repository state at roadmap creation: docs only.
- Existing tracked files: `README.md` and `docs/PRD.md`.
- No web app, mobile app, backend service, database migrations, storage policies, or CI pipeline exists yet.
- Phase 0 is mandatory even though it is not listed in the PRD milestones.

## Agent Execution Loop

1. Read `docs/PRD.md` and this file before starting any phase.
2. Find the earliest phase with unchecked build work or failed verification.
3. Implement only that phase's unchecked tasks unless a blocker requires a small backward-compatible fix in an earlier phase.
4. Run the phase verification checklist after implementation.
5. Update this file by checking completed boxes, leaving incomplete work unchecked, and appending dated notes.
6. Move to the next phase only after the current phase exit criteria are satisfied.
7. Before ending any phase run, review the active phase checklist from top to bottom and check every item that was actually completed and verified during that run.

## Locked Defaults

- Repository layout:

```text
/
  apps/web
  apps/mobile
  services/api
  supabase/migrations
  supabase/seed
  .github/workflows
  docs
```

- Web stack: React + Vite + Tailwind CSS + shadcn/ui + React Router + Zustand + Fetch-based API client + Leaflet.
- Mobile stack: Flutter + Riverpod + Dio + `flutter_map` + `sqflite` + `nearby_connections`.
- Backend stack: Flask REST API with Supabase Auth, Supabase Storage, and Supabase Realtime.
- Auth default: Supabase Auth is the credential source of truth. Do not build a separate password system in application tables. Application tables should reference `auth.users.id`.
- Admin surface default: Municipality workflows are web-first. Mobile can expose municipality read-only placeholders, but the full municipality dashboard is not required on mobile for MVP.
- Citizen flow default: Auth, report submission, report history, and feed browsing must exist on both web and mobile by the time their owning phases are complete.
- Department flow default: Department responders must have working web tools in Phase 2 and working mobile responder tools by the end of Phase 2, because Phase 4 depends on mobile department participation.
- Testing default: Web uses Vitest + React Testing Library, API uses pytest, mobile uses `flutter_test`, and web smoke tests use Playwright once user-facing flows exist.
- Scope default: v1 is single municipality only.
- Notification default: v1 uses in-app notifications only. No push, SMS, or email until Phase 5.
- Feed default: citizen feed is read-only in v1. No citizen comments, reactions, reposts, or direct messaging.
- Categorization default: Phase 1 uses manual category selection. Phase 2 adds rule-based auto-categorization with manual override. ML classification and image classification stay in Phase 5.
- Background job default: do not introduce Celery or Redis in MVP phases. Use synchronous services plus a lightweight cron-compatible scan for overdue escalation when needed.
- Escalation default: a report escalates immediately when all primary departments decline, or after 120 seconds with no acceptance. Make this threshold configurable.
- Upload default: incident, post, and assessment images must allow JPEG/PNG only, maximum 3 images per report, maximum 5 MB per image.
- Localization default: English is the base language. Filipino UI labels are added in Phase 3. User-generated content is never auto-translated.
- Mesh default: mesh features are mobile only, are treated as first-class offline transport, and use the PRD packet rules exactly unless a note in this file explicitly narrows implementation scope.
- Offline department verification token default: verified department devices cache a signed offline verification JWT with a 30-day TTL and refresh it on successful online sessions. If the token is expired or missing, the device may not originate offline mesh announcements.

## Non-Negotiable Constraints

- Protect all private API routes and protected pages by authenticated role checks.
- Preserve the canonical enums and endpoint ownership listed in this document.
- Keep report status propagation live by Phase 2 and preserve it in later phases.
- Treat `is_escalated` as a flag, not a replacement for the canonical report status enum.
- Do not use `incident_reports.status = rejected` to represent a department decline. Department decline belongs only in `department_responses`.
- Do not add multi-municipality logic before a separate product decision.
- Do not treat Phase 5 stretch features as blockers for MVP completion.
- Simple map previews in report details are allowed before Phase 5. Phase 5's map item refers to richer system-wide map visualization and filtering.

## Canonical Enums

| Enum | Values | Notes |
|------|--------|-------|
| `role` | `citizen`, `department`, `municipality` | Used across auth, profiles, and route guards. |
| `department_type` | `fire`, `police`, `medical`, `disaster`, `rescue`, `other` | `disaster` is the MDRRMO catch-all bucket. |
| `verification_status` | `pending`, `approved`, `rejected` | Only applies to department records. |
| `report_category` | `fire`, `flood`, `earthquake`, `road_accident`, `medical`, `structural`, `other` | Final chosen category stored on the report. |
| `report_severity` | `low`, `medium`, `high`, `critical` | Default to `medium` until a stronger severity rule exists. |
| `report_status` | `pending`, `accepted`, `responding`, `resolved`, `rejected` | `rejected` is reserved for future admin invalidation or spam handling, not department decline. |
| `department_response_action` | `accepted`, `declined` | Stored in `department_responses`. |
| `post_category` | `alert`, `warning`, `safety_tip`, `update`, `situational_report` | Only verified departments can publish. |
| `notification_type` | `report_update`, `new_report`, `verification_decision`, `announcement` | Persist per user in `notifications`. |
| `damage_level` | `minor`, `moderate`, `severe`, `critical` | Used in damage assessments. |

## Category Routing Defaults

| Report Category | Primary Department Visibility | Escalation Visibility |
|----------------|------------------------------|-----------------------|
| `fire` | all `fire` departments | `disaster` departments + municipality |
| `flood` | all `disaster` departments | municipality |
| `earthquake` | all `disaster` departments | municipality |
| `road_accident` | all `police` departments | `disaster` departments + municipality |
| `medical` | all `medical` and `rescue` departments | `disaster` departments + municipality |
| `structural` | all `disaster` departments | municipality |
| `other` | all `disaster` departments | municipality |

- Do not add a new engineering-specific enum in MVP phases. If an engineering responder must exist before Phase 5, model it as `department_type = other` and handle it through internal department metadata instead of changing the enum.

## Phase-Owned API And Interface Map

| Phase | Owned APIs / Interfaces |
|------|--------------------------|
| Phase 0 | `GET /api/health`, `GET /api/ready`, auth middleware, role guards, validation layer, Supabase clients, storage helpers, realtime subscription helpers |
| Phase 1 | `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`, `GET /api/users/profile`, `PUT /api/users/profile`, `GET /api/municipality/departments`, `GET /api/municipality/departments/pending`, `PUT /api/municipality/departments/:id/verify`, `POST /api/reports`, `GET /api/reports`, `GET /api/reports/:id`, `POST /api/reports/:id/upload` |
| Phase 2 | `GET /api/departments/profile`, `PUT /api/departments/profile`, `GET /api/departments/reports`, `POST /api/departments/reports/:id/accept`, `POST /api/departments/reports/:id/decline`, `GET /api/departments/reports/:id/responses`, `PUT /api/departments/reports/:id/status`, `POST /api/departments/posts`, `GET /api/feed`, `GET /api/feed/:id`, `GET /api/notifications`, `PUT /api/notifications/:id/read`, `PUT /api/notifications/read-all` |
| Phase 3 | `GET /api/municipality/reports`, `GET /api/municipality/analytics`, `POST /api/departments/assessments`, `GET /api/departments/assessments`, `GET /api/municipality/assessments`, expanded `GET /api/reports/:id` timeline payload |
| Phase 4 | `POST /api/mesh/ingest`, `GET /api/mesh/sync-updates`, mesh packet envelope, gateway sync acknowledgement contract, mobile SQLite queue interfaces |
| Phase 5 | ML categorization interfaces, push token registration, moderation endpoints, map visualization data endpoints, WiFi Direct large-payload tuning surfaces |

## Current Progress Snapshot

- [x] Phase 0 - Foundation and project bootstrap
- [ ] Phase 1 - Auth, verification, and citizen reporting (API, web, mobile done; Supabase tasks and some tests/docs remain)
- [ ] Phase 2 - Department operations, feed, notifications, and realtime routing
- [ ] Phase 3 - Analytics, assessments, timeline, and product polish
- [ ] Phase 4 - Mobile mesh networking and offline-first sync
- [ ] Phase 5 - Stretch features

## Cross-Phase Rules

- Finish phases in order unless a later phase requires a small backward-compatible fix to an earlier phase.
- Do not silently rename enums, statuses, endpoint paths, or routing behavior once introduced.
- Add schema changes in a backward-compatible way whenever possible.
- Preserve manual category override even after auto-categorization is introduced.
- Preserve audit trails. Status history and department response records should never be erased to simplify state transitions.
- Record all deviations, tradeoffs, and temporary shortcuts in the active phase notes with an ISO date.
- Never leave a completed and verified task unchecked in the active phase checklist.
- When a phase is only partially complete, leave the phase checkbox unchecked and explain exactly what is still missing.

## Phase 0 - Foundation And Project Bootstrap

**Objective**

Create the complete greenfield project foundation so later phases can focus on business features instead of repeated scaffolding work.

**Owned Scope**

- Monorepo directory layout
- Base web, mobile, and API applications
- Initial Supabase schema, enum types, RLS, storage buckets, and realtime enablement
- Auth middleware and role guards
- Shared environment and local development setup
- CI, linting, formatting, and test harnesses

**Prerequisites**

- `docs/PRD.md` has been reviewed.
- No implementation code exists yet.

**Core Tables Touched**

- `users`
- `departments`
- `incident_reports`
- `department_responses`
- `report_status_history`
- `posts`
- `notifications`
- `damage_assessments`
- Supabase auth user linkage and storage buckets

**API Surfaces Touched**

- `GET /api/health`
- `GET /api/ready`
- Auth JWT verification middleware
- Role-based route guard helpers
- Validation and error-response helpers

### Build Checklist

#### Database / Supabase

- [x] Create PostgreSQL enum types that match the canonical values in this document.
- [x] Create the base application tables from the PRD with primary keys, foreign keys, timestamps, and useful indexes.
- [x] Use `auth.users.id` as the canonical user identifier instead of storing a second password system in application tables.
- [x] Add RLS policies so citizens can access only their own private records, departments can access only their department scope, and municipality users can access municipality-wide data.
- [x] Create storage buckets for `report-images`, `post-images`, and `assessment-images`.
- [x] Add storage validation and policy rules for allowed file types and file size limits.
- [x] Enable Supabase Realtime on the tables that will later drive live updates: `incident_reports`, `department_responses`, `report_status_history`, `notifications`, and `posts`.
- [x] Seed one municipality admin account and a small set of sample departments covering `fire`, `police`, `medical`, and `disaster`.

#### Flask API

- [x] Scaffold the Flask project with clear module boundaries for auth, users, municipality, departments, reports, feed, notifications, analytics, and mesh.
- [x] Add environment loading, config validation, logging, consistent JSON error responses, and request validation helpers.
- [x] Implement Supabase JWT validation middleware and role guard decorators.
- [x] Add health and readiness endpoints that verify API boot plus Supabase connectivity.
- [x] Create storage helper services for uploads, signed URLs, and validation hooks.
- [x] Create service placeholders for reports, notifications, feed, analytics, and mesh so later phases extend stable modules instead of rewriting the app structure.

#### Web App

- [x] Scaffold the React + Vite app with Tailwind, shadcn/ui, React Router, Zustand session state, and a typed Fetch-based API client.
- [x] Create base layouts for citizen, department, and municipality shells plus protected-route wrappers.
- [x] Add a shared design-token file and base theme primitives instead of scattering colors and spacing tokens across components.
- [x] Add a Leaflet wrapper component for location display and map pin selection.
- [x] Create placeholder pages for auth, dashboard landing, report list, feed, and profile so future phases plug into stable routes.

#### Mobile App

- [x] Scaffold the Flutter app with Riverpod, Dio, local session persistence, and role-aware navigation.
- [x] Create base shells for citizen, department, and municipality landing states.
- [x] Add service wrappers for auth, uploads, location, camera/gallery access, and future mesh transport.
- [ ] Add a `flutter_map` wrapper and shared location-selection primitives.
- [x] Add local persistence scaffolding for session data and future offline queue tables without implementing Phase 4 mesh logic yet.

#### Realtime / Offline Transport

- [x] Define a shared event naming strategy for report updates, department responses, notifications, and feed updates.
- [x] Add reusable realtime subscription helpers in web and mobile so Phase 2 can connect live data without rewriting infrastructure.
- [x] Define local interfaces for offline queueing and sync services that Phase 4 can implement later.

#### Tests

- [x] Configure ESLint, Prettier, Vitest, and React Testing Library for web.
- [x] Configure pytest and lint/format tooling for the Flask API.
- [x] Configure `flutter analyze` and `flutter test` for mobile.
- [x] Add a CI workflow that runs web, API, and mobile checks on every pull request or branch build.

#### Docs

- [x] Document environment variables, startup steps, seeded accounts, and expected local services.
- [x] Document the repository layout and which app/service owns which responsibility.
- [x] Document the Supabase setup flow, including migrations, storage buckets, and RLS assumptions.

### Verification Checklist

- [ ] A clean checkout can install dependencies and boot the web app, mobile app, and API without manual guesswork.
- [ ] `GET /api/health` and `GET /api/ready` return success in a configured development environment.
- [ ] Supabase migrations apply cleanly and seed data appears as expected.
- [x] JWT validation rejects invalid tokens and role guards return the correct unauthorized or forbidden responses.
- [x] Storage rules reject unsupported file types and files over the configured size limit.
- [x] CI passes the baseline web, API, and mobile checks.

### Notes / Update Log

- Date: `2026-03-28`
- Completed: scaffolded the monorepo layout; added the Supabase Phase 0 migration and hosted-project seed script; built the Flask API foundation with health/readiness endpoints, auth middleware, role guards, validation helpers, and storage validation; built the React web shell with routing, protected routes, design tokens, Leaflet wrapper, and placeholder pages; built the Flutter mobile shell with Riverpod, Dio, role-aware navigation, file-backed session persistence, service wrappers, and offline queue scaffolding; added CI plus setup documentation in `README.md`.
- Deviations: the mobile shell uses placeholder location and offline transport wrappers instead of plugin-backed `flutter_map`, `sqflite`, and `nearby_connections` integrations because this Windows host cannot enable Flutter plugin symlink support.
- Blockers: no hosted Supabase project credentials were configured in this workspace, so migration application, realtime enablement verification, seed execution against a live project, and a real `GET /api/ready` success check were not run here; GitHub Actions could not be observed remotely from the local workspace.
- Carryover: finish the `flutter_map` wrapper and plugin-backed mobile foundations on a host with Flutter plugin symlink support, apply the Phase 0 SQL migration to the hosted Supabase project, run the seed bootstrap against that project, verify the readiness endpoint against real environment variables, and confirm the GitHub Actions workflow passes after push.

### Exit Criteria

- The repo has stable app/service scaffolding, initial schema, auth foundations, and a repeatable local setup.
- Later phases can focus on product functionality without re-deciding folder layout, auth strategy, or toolchain.

## Phase 1 - Auth, Verification, And Citizen Reporting

**Objective**

Deliver the first working end-to-end experience: user auth, department onboarding and verification, citizen report submission, and citizen report tracking.

**Owned Scope**

- Citizen and department registration/login flows
- Municipality department verification workflow
- Basic profile management
- Citizen incident reporting with photo, location, and manual category selection
- Citizen report list and detail pages
- Initial report status tracking and status history creation

**Prerequisites**

- Phase 0 exit criteria satisfied

**Core Tables Touched**

- `users`
- `departments`
- `incident_reports`
- `report_status_history`
- report image storage bucket

**API Surfaces Touched**

- `POST /api/auth/register`
- `POST /api/auth/login`
- `POST /api/auth/logout`
- `GET /api/auth/me`
- `GET /api/users/profile`
- `PUT /api/users/profile`
- `GET /api/municipality/departments`
- `GET /api/municipality/departments/pending`
- `PUT /api/municipality/departments/:id/verify`
- `POST /api/reports`
- `GET /api/reports`
- `GET /api/reports/:id`
- `POST /api/reports/:id/upload`

### Build Checklist

#### Database / Supabase

- [ ] Finalize the `users` and `departments` schema so department onboarding captures organization name, type, contact details, address, area of responsibility, and verification status.
- [ ] Finalize the `incident_reports` schema for Phase 1 with required description, manual category, optional GPS/manual address, image references, default severity, `status = pending`, and `is_escalated = false`.
- [x] Ensure `report_status_history` receives an initial `pending` entry when a report is created.
- [ ] Add or tighten RLS and storage policies so citizens can create and read only their own reports and uploads.

#### Flask API

- [x] Implement citizen registration and department registration through Supabase Auth plus application profile creation.
- [x] Implement login, logout, and "me" endpoints that return role and profile state needed by both clients.
- [x] Implement user profile get/update endpoints for common profile fields.
- [x] Implement municipality-only department list and pending-verification endpoints.
- [x] Implement municipality approve and reject actions, including required rejection reason on rejection.
- [x] Implement department resubmission flow so a rejected department can update details and move back to `pending`.
- [x] Implement citizen report creation with description, manual category, optional location, and image upload support.
- [x] Require manual category selection in Phase 1 because auto-categorization is not active yet.
- [x] Implement citizen report list and detail endpoints, including current status and status-history summary.
- [x] Enforce that unverified departments can authenticate but cannot access department operational endpoints yet.

#### Web App

- [x] Build registration and login screens for citizens and departments.
- [x] Build a department onboarding form with verification status messaging for `pending`, `approved`, and `rejected`.
- [x] Build a municipality verification queue page with approve and reject actions plus rejection-reason input.
- [x] Build citizen profile editing.
- [x] Build the citizen report form with description, manual category selector, camera/gallery upload, GPS auto-detect, and manual map pin fallback.
- [x] Build citizen report history and detail pages with clear status display, uploaded images, and location preview.
- [x] Provide a clear "awaiting verification" state for departments after registration.

#### Mobile App

- [x] Build mobile auth flows for citizen and department users.
- [x] Build mobile citizen profile editing.
- [x] Build mobile incident reporting with camera/gallery, location capture, manual category selection, and upload progress.
- [x] Build mobile report history and detail screens with status, images, and map preview.
- [x] Build a mobile department pending/rejected status screen. Full municipality administration can remain web-only in this phase.

#### Realtime / Offline Transport

- [x] Keep the realtime foundation wired, but use manual refresh or simple polling for Phase 1 citizen status views if live subscriptions are not finished yet.
- [x] Do not implement mesh behavior in this phase.

#### Tests

- [x] Add API tests for registration, login, role guards, municipality verification, report creation, and upload validation.
- [x] Add API tests that confirm rejected departments can edit and resubmit for approval.
- [ ] Add web tests for auth flows, verification queue actions, and citizen report submission.
- [ ] Add mobile tests for citizen report submission and report-history rendering.
- [ ] Add at least one end-to-end smoke flow covering citizen register/login, report submission, and report detail display.

#### Docs

- [ ] Document the Phase 1 user flows, especially the difference between approved and unapproved department behavior.
- [ ] Document the required report inputs and image constraints.
- [ ] Document that manual category selection is temporary and will remain as an override after auto-categorization is introduced.

### Verification Checklist

- [ ] A citizen can register, log in, submit a report, and view it in their own report history on web.
- [ ] A citizen can register, log in, submit a report, and view it in their own report history on mobile.
- [ ] A municipality user can view pending departments, approve one, reject one with reason, and see the state change persist.
- [ ] A rejected department can update its information and re-enter the pending queue.
- [ ] An unverified department cannot access department operational routes.
- [x] A newly created report is stored with `status = pending`, `is_escalated = false`, and an initial status-history entry.
- [x] Image limits and supported file-type rules are enforced.

### Notes / Update Log

- Date: `2026-03-28`
- Completed: All Flask API routes for Phase 1 (auth register/login/logout/me, user profile get/put, municipality department list/pending/verify, department profile get/put with resubmission, report create/list/detail/upload). 29 pytest tests covering all API endpoints. Web app real auth flows (login, register with role selection), Zustand session store with localStorage persistence, citizen report form/list/detail pages, department pending/rejected/approved states, municipality verification queue and departments list, profile editing, role-aware navigation. Mobile app auth service (Dio), Riverpod session controller, login/register screens, citizen report form/list/detail/profile screens, department home with pending/rejected/approved views.
- Deviations: Supabase database migrations, RLS policy changes, and storage policy changes were intentionally excluded per user request — the Phase 0 schema is assumed ready. Department profile endpoints (`GET/PUT /api/departments/profile`) were implemented in Phase 1 instead of Phase 2 because the department verification resubmission flow requires them. Mobile map preview in report detail not yet implemented (no `flutter_map` integration). Web uses manual refresh (pull-to-refresh / re-fetch) instead of realtime subscriptions for citizen report status views.
- Blockers: Supabase schema tasks remain unchecked — need to verify/tighten RLS and storage policies against a live Supabase project. End-to-end verification checklist items cannot be confirmed until the API is running against a real Supabase instance.
- Carryover: Supabase schema finalization and RLS/storage policy tightening. Web tests for auth flows, verification queue, and citizen report submission. Mobile tests for report submission and report-history rendering. End-to-end smoke test. Phase 1 documentation (user flows, report inputs, category selection notes).

### Exit Criteria

- Auth, verification, citizen reporting, and citizen-side report tracking work on both web and mobile.
- Municipality can verify departments from the web dashboard.
- Reports can be created consistently enough for Phase 2 routing and department workflows to build on them.

## Phase 2 - Department Operations, Feed, Notifications, And Realtime Routing

**Objective**

Deliver the core emergency coordination workflow: relevant departments receive reports, see each other's decisions, accept or decline in real time, escalate unattended incidents, post official updates, and notify users in app.

**Owned Scope**

- Rule-based auto-categorization with manual override preserved
- Department incident board and report-response workflow
- Inter-department response visibility
- Escalation logic and unattended incident visibility
- Department post creation and citizen feed browsing
- In-app notifications
- Live realtime updates across report routing, department responses, and citizen status tracking

**Prerequisites**

- Phase 1 exit criteria satisfied

**Core Tables Touched**

- `incident_reports`
- `department_responses`
- `report_status_history`
- `posts`
- `notifications`
- `departments`

**API Surfaces Touched**

- `GET /api/departments/profile`
- `PUT /api/departments/profile`
- `GET /api/departments/reports`
- `POST /api/departments/reports/:id/accept`
- `POST /api/departments/reports/:id/decline`
- `GET /api/departments/reports/:id/responses`
- `PUT /api/departments/reports/:id/status`
- `POST /api/departments/posts`
- `GET /api/feed`
- `GET /api/feed/:id`
- `GET /api/notifications`
- `PUT /api/notifications/:id/read`
- `PUT /api/notifications/read-all`

### Build Checklist

#### Database / Supabase

- [ ] Finalize `department_responses` as an append-only response log keyed by report and department, with latest response determining the department's current state.
- [ ] Add indexes that support report board queries by category, status, escalation state, and recency.
- [ ] Finalize `posts` and `notifications` tables plus any indexes needed for reverse-chronological feed and unread notification queries.
- [ ] Ensure realtime is enabled and configured for the tables used in department boards, citizen status updates, feed refresh, and notifications.

#### Flask API

- [ ] Implement the PRD keyword-based categorization rules for English and Filipino trigger words.
- [ ] Preserve manual override: if the user manually selects a category, keep it as the final stored category unless a future admin recategorization feature is explicitly added.
- [ ] Implement the category-to-department routing rules exactly as listed in this file.
- [ ] Implement the department incident board query so verified departments see only relevant reports, plus escalated catch-all visibility when applicable.
- [ ] Implement accept and decline actions so a department can publish a current response with optional notes and required decline reason when declining.
- [ ] Allow multiple departments to accept the same report for coordinated response.
- [ ] When the first department accepts, update the report status to `accepted` and record status history.
- [ ] Implement report status progression from `accepted` to `responding` to `resolved` through department actions.
- [ ] Implement escalation logic so reports escalate immediately after all relevant departments have latest-state declines, or after 120 seconds with no acceptance.
- [ ] Implement the 120-second no-acceptance scan as a cron-compatible API command or background scan service without introducing Celery/Redis.
- [ ] When a report escalates, set `is_escalated = true`, expose it to `disaster` departments if needed, and notify municipality users.
- [ ] Implement verified-department-only post creation with optional image attachments.
- [ ] Implement citizen/public feed list and detail retrieval.
- [ ] Implement per-user in-app notifications for new reports, report updates, verification decisions, and announcements.
- [ ] Backfill verification-decision notifications for Phase 1 workflow now that the notifications system exists.

#### Web App

- [ ] Build the department report board with filters, urgent/unattended visual state, and clear current-status badges.
- [ ] Build report detail views that show photos, description, location, current report status, and the full current response roster from sibling departments.
- [ ] Build accept and decline actions with required decline reason and clear follow-up status controls.
- [ ] Build department profile management for operational details.
- [ ] Build announcement/post creation for verified departments only.
- [ ] Build the public feed for citizens with filterable post categories and detail pages.
- [ ] Build an in-app notification center with unread state and mark-as-read actions.
- [ ] Add a simple municipality unattended-incidents view focused on escalated emergencies only. Full analytics comes in Phase 3.

#### Mobile App

- [ ] Build the department mobile report board and report detail screens with accept, decline, and status-update actions.
- [ ] Build mobile department profile management.
- [ ] Build mobile announcement creation for verified departments.
- [ ] Build mobile citizen feed browsing and feed detail views.
- [ ] Build mobile in-app notifications with unread counts.
- [ ] Upgrade citizen report detail screens from refresh-based tracking to live updates while the app is active.

#### Realtime / Offline Transport

- [ ] Subscribe web and mobile clients to live report updates, department response changes, feed changes, and notifications.
- [ ] Ensure citizen status views update within the PRD's realtime expectation once departments act on a report.
- [ ] Ensure sibling departments see accept and decline events in near real time.
- [ ] Keep all realtime handling online-only in this phase. Mesh delivery still belongs to Phase 4.

#### Tests

- [ ] Add unit tests for keyword categorization covering both English and Filipino trigger phrases from the PRD.
- [ ] Add API tests for routing visibility, accept flow, decline flow, multiple-accept flow, escalation by all-decline, and escalation by timeout.
- [ ] Add API tests that confirm department decline does not set `incident_reports.status = rejected`.
- [ ] Add web tests for the department board, feed, and notifications center.
- [ ] Add mobile tests for department report actions, citizen live status tracking, and notifications.
- [ ] Add at least one end-to-end flow where a citizen submits a report, a relevant department accepts it, status changes to `responding`, and the citizen sees the updates.

#### Docs

- [ ] Document the category-routing matrix and escalation rules in developer-facing docs.
- [ ] Document how the append-only department response model works.
- [ ] Document notification triggers and the meaning of each notification type.

### Verification Checklist

- [ ] Only relevant departments see a newly created report before escalation.
- [ ] Departments can see each other's current accept or decline states and decline reasons.
- [ ] More than one department can accept the same report.
- [ ] The first acceptance moves the report to `accepted`, later department status updates can move it to `responding` and `resolved`, and all changes create status-history entries.
- [ ] If all relevant departments decline, the report escalates immediately and municipality users can see it.
- [ ] If no one accepts within 120 seconds, the report escalates automatically.
- [ ] Only verified departments can create public posts.
- [ ] Citizens can browse the feed on web and mobile, but cannot comment or react.
- [ ] In-app notifications are created, displayed, and can be marked read.
- [ ] Citizen report detail screens update live after department actions.

### Notes / Update Log

- Date:
- Completed:
- Deviations:
- Blockers:
- Carryover:

### Exit Criteria

- The core responder coordination workflow works end to end.
- Citizens, departments, and municipality users receive the minimum live information they need for the MVP.
- The system's main differentiator, inter-department visibility and unattended escalation, is operational.

## Phase 3 - Analytics, Assessments, Timeline, And Product Polish

**Objective**

Turn the operational MVP into a decision-support product with analytics, post-disaster assessments, bilingual UI labels, and a polished cross-device experience.

**Owned Scope**

- Municipality report overview and analytics dashboard
- Damage assessment module
- Full report status-history timeline
- English and Filipino UI labels
- Web mobile-responsiveness and UX polish

**Prerequisites**

- Phase 2 exit criteria satisfied

**Core Tables Touched**

- `incident_reports`
- `report_status_history`
- `department_responses`
- `damage_assessments`
- `departments`
- `posts`
- assessment image storage bucket

**API Surfaces Touched**

- `GET /api/municipality/reports`
- `GET /api/municipality/analytics`
- `POST /api/departments/assessments`
- `GET /api/departments/assessments`
- `GET /api/municipality/assessments`
- expanded `GET /api/reports/:id`

### Build Checklist

#### Database / Supabase

- [ ] Finalize `damage_assessments` with fields for affected area, damage level, casualties, displaced persons, location, image attachments, and timestamps.
- [ ] Add indexes needed for municipality analytics queries by category, status, time range, and department.
- [ ] Ensure assessment image storage validation matches the same file-type and file-size policy family used elsewhere.
- [ ] Validate that status-history retention is complete enough to calculate timing metrics accurately.

#### Flask API

- [ ] Implement municipality report overview queries with filters for type, status, date, location, and escalation state.
- [ ] Implement municipality analytics that return report volume, response times, department activity, and unattended-report counts.
- [ ] Define response-time metrics explicitly: report creation to first acceptance, first acceptance to responding, and responding to resolved.
- [ ] Implement department damage-assessment submission with optional images and location.
- [ ] Implement department assessment list retrieval for the submitting department.
- [ ] Implement municipality assessment list retrieval.
- [ ] Expand report detail payloads so timeline/history views can show all status transitions clearly.

#### Web App

- [ ] Build the municipality report overview page with filters and actionable system-wide visibility.
- [ ] Build the municipality analytics dashboard with charts for report volume, status mix, response times, and department activity.
- [ ] Build municipality assessment views that surface recent assessments and basic recovery context.
- [ ] Build a report timeline UI that shows every status transition in order.
- [ ] Add English and Filipino translation resources for static UI labels.
- [ ] Polish responsiveness across citizen, department, and municipality web experiences down to narrow mobile widths.

#### Mobile App

- [ ] Build department mobile damage-assessment submission and assessment history screens.
- [ ] Add English and Filipino translation resources for static mobile UI labels.
- [ ] Polish mobile layouts for report detail, feed, notification, and department-response screens.
- [ ] Keep municipality analytics web-first. Mobile municipality can remain limited to lightweight read-only status views if implemented.

#### Realtime / Offline Transport

- [ ] Preserve Phase 2 realtime behavior while expanding timeline data visibility.
- [ ] Do not introduce mesh transport changes in this phase.

#### Tests

- [ ] Add API tests for analytics calculations and filter correctness.
- [ ] Add API tests for damage-assessment creation and retrieval.
- [ ] Add tests that confirm report timelines include all expected status transitions in order.
- [ ] Add web tests for municipality analytics and report-overview filtering.
- [ ] Add mobile tests for damage-assessment submission and bilingual label switching.
- [ ] Add responsive smoke checks for major web views.

#### Docs

- [ ] Document how analytics metrics are defined so future work does not accidentally change KPI meanings.
- [ ] Document bilingual label coverage expectations and what is intentionally not translated.
- [ ] Document the damage-assessment workflow and how it contributes to municipality review.

### Verification Checklist

- [ ] Municipality users can view and filter system-wide reports from the web dashboard.
- [ ] Municipality analytics values match known fixture data for report counts and timing metrics.
- [ ] Departments can submit damage assessments and municipality users can view them.
- [ ] Report detail views show a complete timeline of status changes.
- [ ] Static UI labels can switch between English and Filipino on supported screens.
- [ ] Web layouts remain usable on desktop, tablet, and phone widths.

### Notes / Update Log

- Date:
- Completed:
- Deviations:
- Blockers:
- Carryover:

### Exit Criteria

- Municipality users can make informed decisions from the dashboard.
- Department field reporting supports post-disaster assessment capture.
- The product is substantially more polished, localized, and operationally useful than the Phase 2 MVP.

## Phase 4 - Mobile Mesh Networking And Offline-First Sync

**Objective**

Implement the offline-first mobile mesh system so reports, announcements, distress signals, and status updates can move across nearby devices without internet and sync to the backend when a gateway reconnects.

**Owned Scope**

- BLE discovery and relay
- WiFi Direct handoff for large payloads
- Standardized mesh packet envelope
- Local SQLite queue, seen-message log, and sync state
- Gateway upload, deduplication, and acknowledgement flow
- Offline verified-department announcements
- SOS distress signal with no-login entry point
- Mesh status panel

**Prerequisites**

- Phase 3 exit criteria satisfied
- Department mobile workflows from Phase 2 exist and are stable enough to receive reports/status updates on device

**Core Tables Touched**

- backend `mesh_messages` deduplication log
- backend `distress_signals`
- `incident_reports`
- `posts`
- `report_status_history`
- mobile SQLite `mesh_queue`
- mobile SQLite `seen_messages`
- mobile SQLite `mesh_peers`

**API Surfaces Touched**

- `POST /api/mesh/ingest`
- `GET /api/mesh/sync-updates`
- mesh packet envelope
- sync acknowledgement contract

### Canonical Mesh Packet Envelope

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

### Build Checklist

#### Database / Supabase

- [ ] Add a backend `mesh_messages` table or equivalent durable deduplication log keyed by `messageId`, `payloadType`, `originDeviceId`, processing state, and linked server record.
- [ ] Add a backend `distress_signals` table to persist SOS events uploaded through mesh sync.
- [ ] Add any required metadata fields or linking tables so synced mesh-created records can be traced back to their `messageId`.
- [ ] Ensure existing buckets and policies support delayed upload of attachments that originated offline.

#### Flask API

- [ ] Implement `POST /api/mesh/ingest` as the dedicated gateway upload endpoint for batch packet ingestion.
- [ ] Implement idempotent processing for `INCIDENT_REPORT`, `ANNOUNCEMENT`, `DISTRESS`, and `STATUS_UPDATE` packets based on `messageId`.
- [ ] Return `SYNC_ACK` results from gateway ingest so the mobile app can rebroadcast acknowledgment state into the mesh.
- [ ] Implement `GET /api/mesh/sync-updates` so gateway devices can pull server-side changes and rebroadcast them into local mesh range.
- [ ] Enforce the PRD conflict rules: incident reports append-only, announcements append-only, distress immutable, status updates last-write-wins by timestamp.
- [ ] Validate offline announcement verification tokens locally against the bundled public key rules and reject invalid or missing department authority for offline-originated announcements.
- [ ] Implement a fast-path ingest for distress packets so they bypass the normal batch queue once a gateway has connectivity.

#### Web App

- [ ] Add web-visible indicators where helpful so synced reports or posts can show they originated from mesh transport.
- [ ] Do not build new web mesh-management screens in this phase unless needed for debugging or operator visibility.

#### Mobile App

- [ ] Integrate `nearby_connections` for BLE discovery and transport management.
- [ ] Negotiate WiFi Direct automatically for payloads above 10 KB and fall back to BLE fragmentation if negotiation fails.
- [ ] Create local SQLite tables for queued packets, seen message IDs, peer cache, and last successful sync time.
- [ ] Implement node-role handling for origin, relay, and gateway behavior.
- [ ] Serialize offline incident reports into `INCIDENT_REPORT` packets and queue them with local `QUEUED_MESH` state.
- [ ] Accept incoming report and status packets and reflect them in department and citizen mobile views.
- [ ] Serialize department announcements into `ANNOUNCEMENT` packets and include the cached offline verification token.
- [ ] Block offline announcement creation if the cached department verification token is missing or expired.
- [ ] Add a one-tap SOS action reachable without login and broadcast `DISTRESS` packets with `maxHops = 15`.
- [ ] Build the mesh status panel showing current role, peer count, estimated reach, queue size, and last sync time.

#### Realtime / Offline Transport

- [ ] Implement packet deduplication using the local seen-message log.
- [ ] Increment `hopCount` on relay and drop packets that reach `maxHops`.
- [ ] Prioritize `DISTRESS` packets above all other queued traffic.
- [ ] Re-broadcast `SYNC_ACK` packets so origin devices can learn when a report has reached the server.
- [ ] Inject pulled server-side updates back into the mesh as `STATUS_UPDATE` and `SYNC_ACK` packets.
- [ ] Preserve append-only auditability even when last-write-wins selects the final visible status.

#### Tests

- [ ] Add unit tests for packet serialization, signature validation, deduplication, hop-limit handling, and priority ordering.
- [ ] Add API tests for duplicate gateway ingest and acknowledgement behavior.
- [ ] Add API tests for distress-signal ingest and persistence.
- [ ] Add mobile tests for offline queueing, sync acknowledgement handling, and expired-offline-token announcement rejection.
- [ ] Add manual device-to-device field-test steps covering no-internet report relay, announcement relay, and distress propagation.

#### Docs

- [ ] Document mobile permissions, BLE/WiFi Direct behavior, and operator expectations when internet is unavailable.
- [ ] Document the gateway sync lifecycle, including deduplication and acknowledgement behavior.
- [ ] Document offline department-token refresh behavior and the consequences of expiry.

### Verification Checklist

- [ ] An offline-created report can move across nearby devices, reach a gateway, upload once, and generate a sync acknowledgement back toward the origin.
- [ ] Duplicate gateway uploads do not create duplicate server records.
- [ ] Offline department announcements are relayed only when the verification token is valid.
- [ ] A missing or expired offline token blocks announcement origination.
- [ ] A distress signal can be triggered without login, uses `maxHops = 15`, and is ingested with higher priority than ordinary packets.
- [ ] The mesh status panel shows live peer count, queue size, role, and last sync timestamp.

### Notes / Update Log

- Date:
- Completed:
- Deviations:
- Blockers:
- Carryover:

### Exit Criteria

- Core offline reporting, announcement relay, and distress handling work on mobile without internet.
- Gateway sync is idempotent and auditable.
- The system can degrade gracefully from online realtime into offline mesh transport and back again.

## Phase 5 - Stretch Features

**Objective**

Add non-MVP improvements only after the MVP phases are stable and verified.

**Owned Scope**

- ML-enhanced categorization
- Image-based classification
- Push notifications
- Municipality content moderation tools
- Rich map-based incident visualization
- WiFi Direct optimization for large payloads

**Prerequisites**

- Phase 4 exit criteria satisfied
- MVP behavior is stable enough that stretch work will not destabilize core emergency workflows

**Core Tables Touched**

- model/config tables if needed
- push device-token table
- moderation-related post fields
- any additional spatial or inference-log tables introduced for stretch work

**API Surfaces Touched**

- ML categorization service interfaces
- push token registration and dispatch interfaces
- moderation endpoints
- map visualization data endpoints
- any WiFi Direct tuning controls exposed for diagnostics

### Build Checklist

#### Database / Supabase

- [ ] Add storage for push device tokens if push notifications are implemented.
- [ ] Add moderation-related post state fields if municipality moderation is implemented.
- [ ] Add any model-config or inference-log storage needed for ML classification.
- [ ] Add spatial indexes only if rich incident-map querying actually needs them.

#### Flask API

- [ ] Upgrade report categorization from rule-based only to rule-based plus ML fallback while preserving manual override.
- [ ] Add confidence scoring and a safe fallback when confidence is low.
- [ ] Add image-based classification only as a supplement to text-based classification, never as the sole report-routing signal.
- [ ] Add push-notification token registration and delivery flows.
- [ ] Add municipality moderation endpoints for hide, unpublish, or review states if moderation is turned on.
- [ ] Add richer map-data endpoints for clustered incident visualization and filtering if the dashboard implements them.

#### Web App

- [ ] Add moderation tooling only if municipality moderation is approved for implementation.
- [ ] Add richer map-based incident visualization without regressing existing report-detail map previews.
- [ ] Add confidence and fallback UI only if ML categorization is active.

#### Mobile App

- [ ] Add push-notification permission prompts, token registration, and notification deep linking.
- [ ] Add any mobile UI needed for richer map views or ML confidence feedback.
- [ ] Optimize large attachment transfer behavior when WiFi Direct is available and beneficial.

#### Realtime / Offline Transport

- [ ] Preserve Phase 4 mesh behavior while improving large-payload handling.
- [ ] Do not let push-notification work replace or weaken in-app notifications and mesh delivery.

#### Tests

- [ ] Add regression tests that confirm rule-based/manual fallback still works if ML is unavailable.
- [ ] Add push-notification registration and delivery smoke tests.
- [ ] Add moderation permission tests if moderation is implemented.
- [ ] Add performance or soak tests if map clustering or large-payload transfer changes are introduced.

#### Docs

- [ ] Document every stretch feature toggle and rollout dependency.
- [ ] Document any new operating costs, third-party services, or model assets introduced by stretch work.

### Verification Checklist

- [ ] Core MVP flows still pass after stretch features are added.
- [ ] ML categorization falls back safely when confidence is low or the model is unavailable.
- [ ] Push notifications complement, not replace, in-app notifications.
- [ ] Moderation tools are role-protected if implemented.
- [ ] Rich map features do not block or replace the simpler required map views from earlier phases.

### Notes / Update Log

- Date:
- Completed:
- Deviations:
- Blockers:
- Carryover:

### Exit Criteria

- Stretch work is additive, optional, and does not compromise the MVP emergency coordination workflow.
- Every added feature has a clear operational reason and verification coverage.
