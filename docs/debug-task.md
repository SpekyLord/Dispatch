# Debug Task Log

Full feature audit conducted on `2026-04-05` across web, mobile, and API.

## Legend

- `[x]` Fixed
- `[ ]` Not yet fixed
- `[-]` Deferred / Won't fix

---

## Previous Bug Fix Passes (Already Committed)

### Commit `bb8ddf2` — 2026-04-04 (Municipality pages + API fixes)
- [x] Municipality reports page: all cards linked to `/municipality/reports/escalated` instead of individual reports
- [x] Municipality profile page: entirely placeholder — replaced with functional page
- [x] Municipality report detail page: created new page + route
- [x] Analytics date range filter: simplified overly complex logic
- [x] Mesh origin checks: standardized to `is_mesh_origin` only
- [x] Municipality profile route: wired `/municipality/profile`

### Commit `ada1af2` — 2026-04-04 (Error handling + security)
- [x] **Security**: Mesh `/ingest` and `/sync-updates` missing `@require_auth()`
- [x] **Security**: Public department profile exposed unverified departments
- [x] Assessment creation: non-integer input caused 500 crash — added validation
- [x] Auth routes: 8x silent `except Exception: pass` — replaced with `log.warning()`
- [x] Auth logout: `sign_out()` return value not checked
- [x] Feed delete/update: non-standard error JSON — replaced with `raise ApiError()`
- [x] Verification page: no error states for failed fetch/actions
- [x] Notifications page: optimistic updates didn't rollback on failure
- [x] Citizen home page: no error state on failed report fetch
- [x] Department home page: no error state on failed fetch
- [x] Department report detail: 321 lines of dead legacy code causing 5 TS errors

---

## Current Bug Fix Pass — 2026-04-05

### CRITICAL — Broken Features

- [x] **B1**: Municipality Analytics Dashboard — API/frontend field mismatches
  - Web expects `avg_response_time_hours` but API returns `response_times` (dict with 3 metrics)
  - Web expects `unattended_count` but API returns `unattended_reports`
  - Web expects `{name, accepts, declines}` but API returns `{department_id, accepted, declined}`
  - Files: `municipality-analytics-page.tsx`, `analytics_service.py`

- [x] **B2**: Department News Feed (Mobile) — completely broken
  - Was hardcoded `itemCount: 5`, fake titles "Our Post Title $index", no API calls
  - Rewrote with real `getFeedPosts()` API call, realtime subscriptions, loading/empty/error states
  - File: `apps/mobile/lib/features/department/presentation/department_news_feed_screen.dart`

- [x] **B3**: Department Reports Screen (Mobile) — placeholder only
  - Was hardcoded `itemCount: 10`, fake data, empty navigation — dead code never imported
  - Replaced with thin wrapper delegating to `DepartmentReportBoardScreen` (the real implementation)
  - File: `apps/mobile/lib/features/department/presentation/department_reports_screen.dart`

### HIGH — Security / Data Integrity

- [x] **S1**: PostgREST filter injection — user input directly interpolated into filter strings
  - Added `sanitize_postgrest_value()` to `validation.py`
  - Applied to `reports/routes.py`, `municipality/routes.py`, `analytics_service.py`

- [x] **S2**: Mesh trail endpoint unvalidated `int()` cast on `limit` param — crashes on bad input
  - Added `_int_arg()` helper to `mesh/routes.py`

### MEDIUM — TypeScript / Build Errors

- [x] **T1**: `role-news-feed-page.tsx:481` — `post.location` possibly null before `.trim()`
- [x] **T2**: `role-news-feed-page.tsx:1384` — `post.photos` possibly undefined before `.length`
- [x] **T3**: `role-news-feed-page.tsx:1845` — `activeCommentPost.photos` possibly undefined before `.length`
- [x] **T4**: `department-home-page.tsx:481` — unused `ProfileField` declaration
- [x] **T5**: `department-home-page.tsx:552` — unused `formatRegistryId` declaration

### MEDIUM — UX / Error Handling

- [x] **U1**: `municipality-analytics-page.tsx:67` — `Math.max()` returns `-Infinity` on empty category object
- [x] **U2**: `department-view-page.tsx:100` — empty `.catch()` leaves user stuck in loading forever

### LOW — Incomplete Features (Web)

- [x] **I1**: Department Home Page (Web) — all placeholder/mock content
  - Replaced hardcoded activity feed, weather widget, map, readiness, insights, and news desk with real data
  - Dashboard now fetches live reports from `/api/departments/reports` and shows real counts/recent incidents
  - Removed ~200 lines of dead placeholder components
  - File: `apps/web/src/pages/department/department-home-page.tsx`

### LOW — Incomplete Features (Mobile)

- [-] **I2**: Citizen Profile (Mobile) — hardcoded stats and recent reports
  - File: `apps/mobile/lib/features/citizen/presentation/citizen_profile_screen.dart`

- [-] **I3**: Mobile Create Post — missing photo/attachment upload and GPS features
  - File: `apps/mobile/lib/features/department/presentation/department_create_post_screen.dart`

- [-] **I4**: Citizen Feed BLoC — dead code, unused TODO placeholder
  - File: `apps/mobile/lib/features/citizen/bloc/citizen_feed_bloc.dart`

- [-] **I5**: Report Filtering UI — API supports filters, no UI controls on citizen home
  - Would need filter bar/dropdown on citizen home page

---

## Backend-Only Bug Fix Pass — 2026-04-05 (continued)

### HIGH — Security

- [x] **S3**: PostgREST injection in mesh `get_sync_updates` — `since` query param interpolated directly into 4 PostgREST filter strings without sanitization
  - Applied `sanitize_postgrest_value()` to `since` in `mesh_service.py`

- [x] **S4**: PostgREST injection in mesh `list_messages` — `threadId` query param interpolated into PostgREST filter without sanitization
  - Applied `sanitize_postgrest_value()` to `thread_id` in `mesh_service.py`

### MEDIUM — Performance / Data Leak

- [x] **P1**: `notification_service.list_for_user()` fetches ALL notifications (no user_id DB filter)
  - Every call loaded every user's notifications into API memory, filtered in Python
  - Added `"user_id": f"eq.{user_id}"` to PostgREST query params

- [x] **P2**: `notification_service.list_users_by_role()` fetches ALL users (no role DB filter)
  - Called on every feed post creation to notify citizens — loaded entire users table
  - Added `"role": f"eq.{role}"` to PostgREST query params

---

## TS Build Status

- **Before fixes**: 5 errors (3 null-safety + 2 unused vars)
- **After fixes**: 0 errors (clean build)
