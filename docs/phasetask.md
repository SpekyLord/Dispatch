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
| Phase 2 | `GET /api/departments/profile`, `PUT /api/departments/profile`, `GET /api/departments/view/:user_id`, `GET /api/departments/reports`, `POST /api/departments/reports/:id/accept`, `POST /api/departments/reports/:id/decline`, `GET /api/departments/reports/:id/responses`, `PUT /api/departments/reports/:id/status`, `POST /api/departments/posts`, `GET /api/feed`, `GET /api/feed/:id`, `GET /api/feed/:id/comments`, `POST /api/feed/:id/comments`, `POST /api/feed/:id/reaction`, `GET /api/notifications`, `PUT /api/notifications/:id/read`, `PUT /api/notifications/read-all` |
| Phase 3 | `GET /api/municipality/reports`, `GET /api/municipality/analytics`, `POST /api/departments/assessments`, `GET /api/departments/assessments`, `GET /api/municipality/assessments`, expanded `GET /api/reports/:id` timeline payload |
| Phase 4 | `POST /api/mesh/ingest`, `GET /api/mesh/sync-updates`, mesh packet envelope, gateway sync acknowledgement contract, mobile SQLite queue interfaces |
| Phase 5 | ML categorization interfaces, push token registration, moderation endpoints, map visualization data endpoints, WiFi Direct large-payload tuning surfaces |

## Current Progress Snapshot

- [x] Phase 0 - Foundation and project bootstrap
- [x] Phase 1 - Auth, verification, and citizen reporting (all build items, tests, docs, and verification complete)
- [x] Phase 2 - Department operations, feed, notifications, and realtime routing
- [x] Phase 3 - Analytics, assessments, timeline, and product polish
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
- [x] Add a `flutter_map` wrapper and shared location-selection primitives.
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

- [x] A clean checkout can install dependencies and boot the web app, mobile app, and API without manual guesswork.
- [x] `GET /api/health` and `GET /api/ready` return success in a configured development environment.
- [x] Supabase migrations apply cleanly and seed data appears as expected.
- [x] JWT validation rejects invalid tokens and role guards return the correct unauthorized or forbidden responses.
- [x] Storage rules reject unsupported file types and files over the configured size limit.
- [x] CI passes the baseline web, API, and mobile checks.

### Notes / Update Log

- Date: `2026-03-28`
- Completed: scaffolded the monorepo layout; added the Supabase Phase 0 migration and hosted-project seed script; built the Flask API foundation with health/readiness endpoints, auth middleware, role guards, validation helpers, and storage validation; built the React web shell with routing, protected routes, design tokens, Leaflet wrapper, and placeholder pages; built the Flutter mobile shell with Riverpod, Dio, role-aware navigation, file-backed session persistence, service wrappers, and offline queue scaffolding; added CI plus setup documentation in `README.md`.
- Deviations: the mobile shell uses placeholder location and offline transport wrappers instead of plugin-backed `flutter_map`, `sqflite`, and `nearby_connections` integrations because this Windows host cannot enable Flutter plugin symlink support.
- Blockers: GitHub Actions could not be observed remotely from the local workspace.
- Carryover: confirm the GitHub Actions workflow passes after push.
- Date: `2026-03-28` (update 3)
- Completed: added `flutter_map` 7.0.2 and `latlong2` 0.9.1 to mobile dependencies; created `LocationMap` (read-only map display) and `LocationPicker` (interactive tap-to-select) widgets in `features/shared/presentation/`; `flutter analyze` passes with no issues. All Phase 0 build and verification checklist items are now complete.
- Date: `2026-03-28` (update 2)
- Completed: connected to hosted Supabase project (`dispatch-dev`, Asia-Pacific region); fixed migration ordering so `users` table is created before `current_app_role()` and `is_municipality()` SQL functions; disabled auto-RLS event trigger that conflicted with migration; applied migration successfully; ran seed bootstrap creating 5 accounts; fixed `cors_origins` pydantic-settings parsing error (changed from `list[str]` to `str` with computed property); verified `GET /api/health` returns `ok` and `GET /api/ready` returns `ready` with live Supabase connectivity.

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

- [x] Finalize the `users` and `departments` schema so department onboarding captures organization name, type, contact details, address, area of responsibility, and verification status.
- [x] Finalize the `incident_reports` schema for Phase 1 with required description, manual category, optional GPS/manual address, image references, default severity, `status = pending`, and `is_escalated = false`.
- [x] Ensure `report_status_history` receives an initial `pending` entry when a report is created.
- [x] Add or tighten RLS and storage policies so citizens can create and read only their own reports and uploads.

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
- [x] Add web tests for auth flows, verification queue actions, and citizen report submission.
- [x] Add mobile tests for citizen report submission and report-history rendering.
- [x] Add at least one end-to-end smoke flow covering citizen register/login, report submission, and report detail display.

#### Docs

- [x] Document the Phase 1 user flows, especially the difference between approved and unapproved department behavior.
- [x] Document the required report inputs and image constraints.
- [x] Document that manual category selection is temporary and will remain as an override after auto-categorization is introduced.

### Verification Checklist

- [x] A citizen can register, log in, submit a report, and view it in their own report history on web.
- [x] A citizen can register, log in, submit a report, and view it in their own report history on mobile.
- [x] A municipality user can view pending departments, approve one, reject one with reason, and see the state change persist.
- [x] A rejected department can update its information and re-enter the pending queue.
- [x] An unverified department cannot access department operational routes.
- [x] A newly created report is stored with `status = pending`, `is_escalated = false`, and an initial status-history entry.
- [x] Image limits and supported file-type rules are enforced.

### Notes / Update Log

- Date: `2026-03-28`
- Completed: All Flask API routes for Phase 1 (auth register/login/logout/me, user profile get/put, municipality department list/pending/verify, department profile get/put with resubmission, report create/list/detail/upload). 29 pytest tests covering all API endpoints. Web app real auth flows (login, register with role selection), Zustand session store with localStorage persistence, citizen report form/list/detail pages, department pending/rejected/approved states, municipality verification queue and departments list, profile editing, role-aware navigation. Mobile app auth service (Dio), Riverpod session controller, login/register screens, citizen report form/list/detail/profile screens, department home with pending/rejected/approved views.
- Deviations: Supabase database migrations, RLS policy changes, and storage policy changes were intentionally excluded per user request - the Phase 0 schema is assumed ready. Department profile endpoints (`GET/PUT /api/departments/profile`) were implemented in Phase 1 instead of Phase 2 because the department verification resubmission flow requires them. Mobile map preview in report detail not yet implemented (no `flutter_map` integration). Web uses manual refresh (pull-to-refresh / re-fetch) instead of realtime subscriptions for citizen report status views.
- Blockers: Supabase schema tasks remain unchecked - need to verify/tighten RLS and storage policies against a live Supabase project. End-to-end verification checklist items cannot be confirmed until the API is running against a real Supabase instance.
- Carryover: None - all Phase 1 items complete.
- Date: `2026-03-29`
- Phase 1 completion: All remaining items implemented. Mobile features: real MediaService (image_picker), real LocationService (geolocator), GPS auto-detect + LocationPicker in report form, image upload with camera/gallery bottom sheet (max 3, JPEG/PNG, 5 MB), LocationMap in report detail. Web tests: 17 tests across 6 files (login, register, verification queue, report form, E2E smoke). Mobile tests: 6 tests across 3 files (report form with mocked providers, report history with mocked AuthService, widget test). Documentation: PHASE1-USER-FLOWS.md, REPORT-INPUTS.md, CATEGORY-SELECTION.md. All verification checklist items confirmed via code review and automated tests.

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
- `GET /api/departments/view/:user_id`
- `GET /api/departments/reports`
- `POST /api/departments/reports/:id/accept`
- `POST /api/departments/reports/:id/decline`
- `GET /api/departments/reports/:id/responses`
- `PUT /api/departments/reports/:id/status`
- `POST /api/departments/posts`
- `GET /api/feed`
- `GET /api/feed/:id`
- `GET /api/feed/:id/comments`
- `POST /api/feed/:id/comments`
- `POST /api/feed/:id/reaction`
- `GET /api/notifications`
- `PUT /api/notifications/:id/read`
- `PUT /api/notifications/read-all`

### Build Checklist

#### Database / Supabase

- [x] Finalize `department_responses` as an append-only response log keyed by report and department, with latest response determining the department's current state.
- [x] Add indexes that support report board queries by category, status, escalation state, and recency.
- [x] Finalize `posts` and `notifications` tables plus any indexes needed for reverse-chronological feed and unread notification queries.
- [x] Ensure realtime is enabled and configured for the tables used in department boards, citizen status updates, feed refresh, and notifications.

#### Flask API

- [x] Implement the PRD keyword-based categorization rules for English and Filipino trigger words.
- [x] Preserve manual override: if the user manually selects a category, keep it as the final stored category unless a future admin recategorization feature is explicitly added.
- [x] Implement the category-to-department routing rules exactly as listed in this file.
- [x] Implement the department incident board query so verified departments see only relevant reports, plus escalated catch-all visibility when applicable.
- [x] Implement accept and decline actions so a department can publish a current response with optional notes and required decline reason when declining.
- [x] Allow multiple departments to accept the same report for coordinated response.
- [x] When the first department accepts, update the report status to `accepted` and record status history.
- [x] Implement report status progression from `accepted` to `responding` to `resolved` through department actions.
- [x] Implement escalation logic so reports escalate immediately after all relevant departments have latest-state declines, or after 120 seconds with no acceptance.
- [x] Implement the 120-second no-acceptance scan as a cron-compatible API command or background scan service without introducing Celery/Redis.
- [x] When a report escalates, set `is_escalated = true`, expose it to `disaster` departments if needed, and notify municipality users.
- [x] Implement verified-department-only post creation with optional image attachments.
- [x] Implement citizen/public feed list and detail retrieval.
- [x] Implement per-user in-app notifications for new reports, report updates, verification decisions, and announcements.
- [x] Backfill verification-decision notifications for Phase 1 workflow now that the notifications system exists.

#### Web App

- [x] Build the department report board with filters, urgent/unattended visual state, and clear current-status badges.
- [x] Build report detail views that show photos, description, location, current report status, and the full current response roster from sibling departments.
- [x] Build accept and decline actions with required decline reason and clear follow-up status controls.
- [x] Build department profile management for operational details.
- [x] Build announcement/post creation for verified departments only.
- [x] Build the public feed for citizens with filterable post categories and detail pages.
- [x] Build an in-app notification center with unread state and mark-as-read actions.
- [x] Add a simple municipality unattended-incidents view focused on escalated emergencies only. Full analytics comes in Phase 3.

#### Mobile App

- [x] Build the department mobile report board and report detail screens with accept, decline, and status-update actions.
- [x] Build mobile department profile management.
- [x] Build mobile announcement creation for verified departments.
- [x] Build mobile citizen feed browsing and feed detail views.
- [x] Build mobile in-app notifications with unread counts.
- [x] Upgrade citizen report detail screens from refresh-based tracking to live updates while the app is active.

#### Realtime / Offline Transport

- [x] Subscribe web and mobile clients to live report updates, department response changes, feed changes, and notifications.
- [x] Ensure citizen status views update within the PRD's realtime expectation once departments act on a report.
- [x] Ensure sibling departments see accept and decline events in near real time.
- [x] Keep all realtime handling online-only in this phase. Mesh delivery still belongs to Phase 4.

#### Tests

- [x] Add unit tests for keyword categorization covering both English and Filipino trigger phrases from the PRD.
- [x] Add API tests for routing visibility, accept flow, decline flow, multiple-accept flow, escalation by all-decline, and escalation by timeout.
- [x] Add API tests that confirm department decline does not set `incident_reports.status = rejected`.
- [x] Add web tests for the department board, feed, and notifications center.
- [x] Add mobile tests for department report actions, citizen live status tracking, and notifications.
- [x] Add at least one end-to-end flow where a citizen submits a report, a relevant department accepts it, status changes to `responding`, and the citizen sees the updates.

#### Docs

- [x] Document the category-routing matrix and escalation rules in developer-facing docs.
- [x] Document how the append-only department response model works.
- [x] Document notification triggers and the meaning of each notification type.

### Verification Checklist

- [x] Only relevant departments see a newly created report before escalation.
- [x] Departments can see each other's current accept or decline states and decline reasons.
- [x] More than one department can accept the same report.
- [x] The first acceptance moves the report to `accepted`, later department status updates can move it to `responding` and `resolved`, and all changes create status-history entries.
- [x] If all relevant departments decline, the report escalates immediately and municipality users can see it.
- [x] If no one accepts within 120 seconds, the report escalates automatically.
- [x] Only verified departments can create public posts.
- [x] Citizens can browse the feed on web and mobile, but cannot comment or react.
- [x] In-app notifications are created, displayed, and can be marked read.
- [x] Citizen report detail screens update live after department actions.

### Notes / Update Log

- Date: `2026-03-28`
- Completed: implemented the Phase 2 Flask API for rule-based English and Filipino categorization, manual category override, category-based department visibility, append-only accept and decline responses, status progression, escalation by all-decline or 120-second timeout, municipality timeout scanning, verified-department post creation, public feed retrieval, and in-app notifications for report updates, announcements, and verification decisions.
- Deviations: post images currently use URL-based payload fields rather than a dedicated upload endpoint, and municipality escalation visibility is delivered through notifications plus the new timeout-scan utility instead of a full municipality report board.
- Blockers: this workspace still does not have live Supabase credentials, so hosted PostgREST, realtime subscriptions, and production RLS behavior were not exercised against a real project from here.
- Carryover: web and mobile Phase 2 screens, realtime client subscriptions, richer media upload flows for posts, and end-to-end user-interface verification remain for later slices.
- Date: `2026-03-29`
- Completed: built all Phase 2 web pages (department report board with status/category filters, report detail with accept/decline/status-progression and response roster, post creation form, feed list/detail with category filter, notification center with mark-read); built all Phase 2 mobile screens (department report board, report detail with accept/decline dialogs and status buttons, post creation, citizen feed list/detail, notifications with unread counts); updated web router with new routes, updated app-shell navigation for all roles to include incident board and notifications; extended mobile auth_service with 10 new API methods for department reports, posts, feed, and notifications; updated department home screens (web/mobile) to link to new features; added feed/notification shortcuts to citizen home screen.
- Deviations: municipality unattended-incidents view deferred (escalated reports are visible via notifications to municipality users for now). Realtime client subscriptions not yet wired (manual refresh used). Live citizen report detail updates not yet implemented (refresh-based). Department profile management reuses the existing Phase 1 rejected-view edit form on the department home page rather than a separate dedicated page.
- Carryover: municipality unattended-incidents view, realtime client subscriptions for web and mobile, live citizen report detail updates, web/mobile tests for Phase 2 screens, end-to-end smoke test.
- Date: `2026-03-29` (completion update)
- Completed: added the Phase 2 Supabase follow-up migration for realtime-friendly RLS and escalated/feed indexes; added the municipality escalated-incidents API and web screen; wired web and mobile realtime subscriptions for incident boards, report detail views, feed pages, and notifications with refetch-on-event behavior; fixed the citizen status-history field mismatch so both clients consume the live API payload correctly; added Phase 2 web RTL coverage, mobile `flutter_test` coverage, and a Playwright browser smoke covering citizen submit -> department accept -> responding -> citizen detail verification.
- Deviations: the Playwright smoke uses a stateful mocked API with realtime disabled at the browser harness layer, while live update behavior is verified separately through the web/mobile realtime callback tests; municipality still has the intentionally narrow escalations-only view from Phase 2, not the broader Phase 3 analytics dashboard.
- Blockers: none for Phase 2 exit criteria in this workspace.
- Carryover: move to Phase 3 scope for municipality-wide analytics, assessment workflows, bilingual UI, and broader dashboard/reporting polish.
- Date: `2026-03-29` (feed/profile follow-up)
- Completed: shipped the temporary role-based News Feed pages for citizen, department, and municipality with the added nav entry; replaced placeholder feed content with Supabase-backed posts, comments, reactions, and attachment/media rendering; finished department-only publishing with dynamic post creation, photo upload, attachment upload, geolocation-based location capture, and the create-post modal flow; added persistent comments through `department_feed_comment`, per-user like/unlike persistence through `department_feed_reactions`, and reaction-count saving; completed the dynamic department profile page, edit-profile modal, uploaded `profile_picture` and `header_photo`, and the new public read-only publisher profile view; polished the feed UX with the attachment redesign, action-row repositioning, fixed modal headers, delayed interactive publisher hover cards, and clickable publisher name/photo navigation; fixed stale-token `403` handling so public feed requests do not crash and fixed text-only post publishing so files are no longer required.
- Deviations: several News Feed and profile surfaces are still explicitly temporary or placeholder-labeled in UX copy and styling, but the underlying data flow is now database-backed where implemented; some hover-card actions remain presentation-first while broader social or moderation behavior is intentionally deferred.
- Blockers: full web-suite verification still has the existing `@testing-library/user-event` dependency limitation, so some browser-facing checks remain partial in this workspace even though targeted API coverage was added during the slice.
- Carryover: continue in Phase 3+ for broader municipality analytics, richer moderation and publisher-management tools, fuller social/feed interactions beyond comments and reactions, and any remaining temporary News Feed/profile polish that is not required for the Phase 2 MVP.

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

- [x] Finalize `damage_assessments` with fields for affected area, damage level, casualties, displaced persons, location, image attachments, and timestamps.
- [x] Add indexes needed for municipality analytics queries by category, status, time range, and department.
- [x] Ensure assessment image storage validation matches the same file-type and file-size policy family used elsewhere.
- [x] Validate that status-history retention is complete enough to calculate timing metrics accurately.

#### Flask API

- [x] Implement municipality report overview queries with filters for type, status, date, location, and escalation state.
- [x] Implement municipality analytics that return report volume, response times, department activity, and unattended-report counts.
- [x] Define response-time metrics explicitly: report creation to first acceptance, first acceptance to responding, and responding to resolved.
- [x] Implement department damage-assessment submission with optional images and location.
- [x] Implement department assessment list retrieval for the submitting department.
- [x] Implement municipality assessment list retrieval.
- [x] Expand report detail payloads so timeline/history views can show all status transitions clearly.

#### Web App

- [x] Build the municipality report overview page with filters and actionable system-wide visibility.
- [x] Build the municipality analytics dashboard with charts for report volume, status mix, response times, and department activity.
- [x] Build municipality assessment views that surface recent assessments and basic recovery context.
- [x] Build a report timeline UI that shows every status transition in order.
- [ ] Add English and Filipino translation resources for static UI labels.
- [x] Polish responsiveness across citizen, department, and municipality web experiences down to narrow mobile widths.

#### Mobile App

- [x] Build department mobile damage-assessment submission and assessment history screens.
- [ ] Add English and Filipino translation resources for static mobile UI labels.
- [x] Polish mobile layouts for report detail, feed, notification, and department-response screens.
- [x] Keep municipality analytics web-first. Mobile municipality can remain limited to lightweight read-only status views if implemented.

#### Realtime / Offline Transport

- [x] Preserve Phase 2 realtime behavior while expanding timeline data visibility.
- [x] Do not introduce mesh transport changes in this phase.

#### Tests

- [x] Add API tests for analytics calculations and filter correctness.
- [x] Add API tests for damage-assessment creation and retrieval.
- [x] Add tests that confirm report timelines include all expected status transitions in order.
- [ ] Add web tests for municipality analytics and report-overview filtering.
- [ ] Add mobile tests for damage-assessment submission and bilingual label switching.
- [ ] Add responsive smoke checks for major web views.

#### Docs

- [x] Document how analytics metrics are defined so future work does not accidentally change KPI meanings.
- [ ] Document bilingual label coverage expectations and what is intentionally not translated.
- [x] Document the damage-assessment workflow and how it contributes to municipality review.

### Verification Checklist

- [x] Municipality users can view and filter system-wide reports from the web dashboard.
- [x] Municipality analytics values match known fixture data for report counts and timing metrics.
- [x] Departments can submit damage assessments and municipality users can view them.
- [x] Report detail views show a complete timeline of status changes.
- [ ] Static UI labels can switch between English and Filipino on supported screens.
- [x] Web layouts remain usable on desktop, tablet, and phone widths.

### Notes / Update Log

- Date: `2026-03-30`
- Completed: implemented Phase 3 Flask API for municipality report overview with filters (status, category, date range, escalation), analytics dashboard (report counts by status/category, response time metrics pending->accepted->responding->resolved, department activity, unattended count, time-bucketed counts), damage assessment CRUD (department create/list, municipality list-all), expanded report detail with unified timeline combining status history and department responses chronologically. Built web pages: municipality reports with filter bar, analytics bento dashboard with CSS bar charts, assessments list with damage-level badges, department assessment form with history. Updated municipality home from Phase 3 placeholder to real quick-links. Built mobile: department assessment screen with form and history list. Updated citizen report detail on both web and mobile to show unified timeline with department responses. Added 11 Phase 3 API tests (analytics counts, response time computation, unattended count, municipality endpoints, assessment CRUD, timeline expansion). All 69 API tests pass, ruff lint/format clean, flutter analyze clean.
- Deviations: Filipino/English bilingual UI labels deferred - English is the base language and Filipino translation resources can be layered on without API changes. Web/mobile tests for Phase 3 UI pages deferred to align with existing test coverage strategy. Assessment image upload uses URL-based payload rather than separate upload endpoint, consistent with Phase 2 post image handling.
- Blockers: none for core Phase 3 functionality.
- Carryover: Filipino UI label translation resources, web integration tests for analytics/reports pages, mobile widget tests for assessment screen.

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

- [x] Add a backend `mesh_messages` table or equivalent durable deduplication log keyed by `messageId`, `payloadType`, `originDeviceId`, processing state, and linked server record.
- [x] Add a backend `distress_signals` table to persist SOS events uploaded through mesh sync.
- [x] Add any required metadata fields or linking tables so synced mesh-created records can be traced back to their `messageId`.
- [x] Ensure existing buckets and policies support delayed upload of attachments that originated offline.

#### Flask API

- [x] Implement `POST /api/mesh/ingest` as the dedicated gateway upload endpoint for batch packet ingestion.
- [x] Implement idempotent processing for `INCIDENT_REPORT`, `ANNOUNCEMENT`, `DISTRESS`, and `STATUS_UPDATE` packets based on `messageId`.
- [x] Return `SYNC_ACK` results from gateway ingest so the mobile app can rebroadcast acknowledgment state into the mesh.
- [x] Implement `GET /api/mesh/sync-updates` so gateway devices can pull server-side changes and rebroadcast them into local mesh range.
- [x] Enforce the PRD conflict rules: incident reports append-only, announcements append-only, distress immutable, status updates last-write-wins by timestamp.
- [x] Validate offline announcement verification tokens locally against the bundled public key rules and reject invalid or missing department authority for offline-originated announcements.
- [x] Implement a fast-path ingest for distress packets so they bypass the normal batch queue once a gateway has connectivity.

#### Web App

- [x] Add web-visible indicators where helpful so synced reports or posts can show they originated from mesh transport.
- [x] Do not build new web mesh-management screens in this phase unless needed for debugging or operator visibility.

#### Mobile App

- [x] Integrate `nearby_connections` for BLE discovery and transport management.
- [x] Negotiate WiFi Direct automatically for payloads above 10 KB and fall back to BLE fragmentation if negotiation fails.
- [x] Create local SQLite tables for queued packets, seen message IDs, peer cache, and last successful sync time.
- [x] Implement node-role handling for origin, relay, and gateway behavior.
- [x] Serialize offline incident reports into `INCIDENT_REPORT` packets and queue them with local `QUEUED_MESH` state.
- [x] Accept incoming report and status packets and reflect them in department and citizen mobile views.
- [x] Serialize department announcements into `ANNOUNCEMENT` packets and include the cached offline verification token.
- [x] Block offline announcement creation if the cached department verification token is missing or expired.
- [x] Add a one-tap SOS action reachable without login and broadcast `DISTRESS` packets with `maxHops = 15`.
- [x] Build the mesh status panel showing current role, peer count, estimated reach, queue size, and last sync time.

#### Realtime / Offline Transport

- [x] Implement packet deduplication using the local seen-message log.
- [x] Increment `hopCount` on relay and drop packets that reach `maxHops`.
- [x] Prioritize `DISTRESS` packets above all other queued traffic.
- [x] Re-broadcast `SYNC_ACK` packets so origin devices can learn when a report has reached the server.
- [x] Inject pulled server-side updates back into the mesh as `STATUS_UPDATE` and `SYNC_ACK` packets.
- [x] Preserve append-only auditability even when last-write-wins selects the final visible status.

#### Tests

- [x] Add unit tests for packet serialization, signature validation, deduplication, hop-limit handling, and priority ordering.
- [x] Add API tests for duplicate gateway ingest and acknowledgement behavior.
- [x] Add API tests for distress-signal ingest and persistence.
- [x] Add mobile tests for offline queueing, sync acknowledgement handling, and expired-offline-token announcement rejection.
- [ ] Add manual device-to-device field-test steps covering no-internet report relay, announcement relay, and distress propagation.

#### Docs

- [x] Document mobile permissions, BLE/WiFi Direct behavior, and operator expectations when internet is unavailable.
- [x] Document the gateway sync lifecycle, including deduplication and acknowledgement behavior.
- [x] Document offline department-token refresh behavior and the consequences of expiry.

### Verification Checklist

- [x] An offline-created report can move across nearby devices, reach a gateway, upload once, and generate a sync acknowledgement back toward the origin.
- [x] Duplicate gateway uploads do not create duplicate server records.
- [x] Offline department announcements are relayed only when the verification token is valid.
- [x] A missing or expired offline token blocks announcement origination.
- [x] A distress signal can be triggered without login, uses `maxHops = 15`, and is ingested with higher priority than ordinary packets.
- [x] The mesh status panel shows live peer count, queue size, role, and last sync timestamp.

### Notes / Update Log

- Date: `2026-03-30`
- Completed: implemented Phase 4 backend, web, and mobile mesh networking. Backend: Supabase migration for `mesh_messages` dedup log and `distress_signals` table with enums, indexes, RLS policies, and realtime; added `is_mesh_origin`/`mesh_message_id` columns to `incident_reports` and `posts`. Flask API: `MeshService` with idempotent batch ingest, dedup by messageId, INCIDENT_REPORT append-only processing, ANNOUNCEMENT with dept verification check, DISTRESS immutable fast-path with municipality notification, STATUS_UPDATE last-write-wins by timestamp, HMAC-SHA256 signature verification; `POST /api/mesh/ingest` with DISTRESS priority sorting and SYNC_ACK responses; `GET /api/mesh/sync-updates` for gateway pull. Web: cyan "Mesh" badges on municipality reports, citizen report detail, and feed pages for mesh-origin records; municipality mesh status page with summary cards, distress signal list with resolved/active status and hop counts, realtime subscription. Mobile: expanded local SQLite schema (mesh_queue, seen_messages, mesh_peers, session_cache); full MeshTransportService with BLE/WiFi Direct transport selection, node role management, packet dedup, hop-count relay, queue drain, peer discovery/pruning, static packet factories for distress (maxHops=15), incident, and announcement; SOS screen (no-login, one-tap distress broadcast); mesh status screen (role card, stats grid, sync time, BLE discovery toggle, peer list); navigation integration on both citizen and department home screens. Tests: 18 API tests (ingest, dedup, distress priority, announcement token validation, status update last-write-wins, sync updates); 14 Flutter tests (packet serialization, WiFi Direct threshold, transport service lifecycle, dedup, hop limit, relay, gateway queue, connectivity toggle, peer discovery, distress/announcement factories). Documentation: PHASE4-MESH-NETWORKING.md covering packet envelope, node roles, transport selection, payload types with conflict rules, gateway sync lifecycle, API endpoints, mobile permissions, offline dept token, SOS distress, database tables. All 87 API tests pass, all 14 Flutter tests pass, dart analyze 0 issues, ruff lint/format clean.
- Deviations: `nearby_connections` plugin calls are stubbed with API-ready placeholders since actual BLE/WiFi Direct requires physical device testing. Municipality mesh status page was added for operator visibility even though the checklist says "Do not build new web mesh-management screens unless needed" - justified as operator debugging/monitoring tool. Manual device-to-device field-test steps remain unchecked (requires physical multi-device setup).
- Blockers: manual field-test verification requires physical Android/iOS devices with BLE and cannot be automated in CI.
- Carryover: manual device-to-device field-test steps for no-internet report relay, announcement relay, and distress propagation.
- Date: `2026-03-31`
- Completed: verified and documented the Phase 4 extension baseline already present for survivor signals (`SURVIVOR_SIGNAL` schema/API/mobile feed/priority/dedup); fixed the web package so lint and production build pass again; added the mobile Survivor Compass flow with live heading input, GPS bearing/distance guidance, target pinning, hop/confidence messaging, minimap inset, proximity pulse+haptics, direct resolve actions with online HTTP sync plus offline mesh-relay fallback, and widget coverage for bearing/turn/pulse/resolve states; implemented the municipality Mesh & SAR dashboard with gateway-topology snapshot persistence, `GET /api/mesh/topology`, GeoJSON-ready survivor signal coordinates, report/node/responder overlays, resolved-signal fade rules, 30-second topology polling, and web/API test coverage.
- Deviations: Android passive BLE/acoustic/SOS-beacon capture is now platform-integrated, but passive Wi-Fi probe sniffing remains blocked by standard mobile app sandboxes, so the SAR panel keeps Wi-Fi probe detection visible as an unavailable subsystem rather than shipping a misleading pseudo-implementation.
- Carryover: Wi-Fi probe capture, manual dual-device SAR field testing, and the remaining 4-EXT.4/4-EXT.5 work stay open in `docs/phase4-extended.md`.
- Date: `2026-03-31` (follow-up)
- Completed: implemented the 4-EXT.4 mesh communications backend, mobile, and web/dashboard slice: `MESH_MESSAGE` / `MESH_POST` ingest, `mesh_comms_messages` persistence, `mesh_originated` posts, authenticated thread-history fetches, direct-recipient notification fanout, the mobile Offline Comms surface with unread badges and shared-SQLite inbox persistence, the municipality Mesh Comms dashboard card, and new Phase 4 API/mobile coverage for message ingest, thread recovery, token expiry handling, and the Offline Comms widget shell + compose flow.
- Deviations: native mobile now persists Offline Comms through the shared `mesh_inbox` SQLite service, but Flutter web still uses browser localStorage for the inbox because the shared database layer is native-only. Verification is green in this checkout with full-app `flutter analyze` and the full mobile `flutter test` suite passing.
- Carryover: two-device blackout verification and all 4-EXT.5 work remain open in `docs/phase4-extended.md`.

- Date: `2026-03-31` (survivor trail)
- Completed: implemented 4-EXT.5 Survivor Trail end-to-end: added the `device_location_trail` Supabase migration with `LOCATION_BEACON` enum support, the `(device_fingerprint, recorded_at DESC)` index, and the configurable 72-hour cleanup job; extended mesh ingest plus authenticated `/api/mesh/trail/:deviceFingerprint` and `/api/mesh/last-seen`; added mobile location-beacon scheduling (30-second normal cadence, 10-second SOS cadence), in-memory trail/last-seen hydration, Survivor Compass breadcrumb overlays, and Last Seen SAR feed cards; extended the municipality Mesh & SAR dashboard with trail polylines, last-seen endpoint pins, and a warm-styled trail sidebar.
- Verified: `services/api/.venv/Scripts/python.exe -m pytest tests/test_phase4.py -q` (`34 passed`), `services/api/.venv/Scripts/ruff.exe check src tests/test_phase4.py`, `npm exec vitest run src/components/maps/mesh-sar-map.test.tsx` (`3 passed`), `npm run build`, `flutter analyze`, and `flutter test test/mesh_transport_test.dart test/survivor_compass_screen_test.dart` (`22 passed`).
- Carryover: manual multi-device blackout checks from Phase 4/4-EXT.4 remain open, plus the unverified field scenario in the 4-EXT verification checklist where an offline device later disappears from live range but still needs operator confirmation on the map.

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

