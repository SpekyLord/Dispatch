# Dispatch

Dispatch is a DRRM emergency response platform that connects citizens, verified departments, and municipality responders in one system. Phase 0 establishes the project foundation across web, mobile, backend, Supabase schema, storage, realtime hooks, and CI.

## Repo Layout

```text
.
|-- apps/
|   |-- web/          React + Vite + Tailwind + shadcn-compatible UI shell
|   `-- mobile/       Flutter + Riverpod mobile shell
|-- services/
|   `-- api/          Flask API foundation
|-- supabase/
|   |-- migrations/   Hosted-project SQL migrations
|   `-- seed/         Hosted-project bootstrap seed script
`-- docs/
    |-- PRD.md
    `-- phasetask.md
```

## Prerequisites

- Node 22 LTS or newer in the supported range `>=22 <25`
- `corepack` enabled so `pnpm` is available
- Python 3.12
- `uv`
- Flutter stable
- A hosted Supabase project with:
  - project URL
  - anon key
  - service role key

## Environment Variables

Copy the root sample first:

```powershell
Copy-Item .env.example .env
Copy-Item services/api/.env.example services/api/.env
Copy-Item apps/web/.env.example apps/web/.env
Copy-Item apps/mobile/.env.example apps/mobile/.env
```

Required values:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VITE_API_BASE_URL`
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- `MOBILE_API_BASE_URL`
- `MOBILE_SUPABASE_URL`
- `MOBILE_SUPABASE_ANON_KEY`
- `SEED_DEFAULT_PASSWORD`

## Install And Run

### Web

```powershell
corepack enable
corepack pnpm install
corepack pnpm --filter @dispatch/web dev
```

### API

```powershell
cd services/api
uv sync --group dev
uv run dispatch-api
```

### Mobile

```powershell
cd apps/mobile
flutter pub get
flutter run
```

## Quality Checks

### Web

```powershell
corepack pnpm --filter @dispatch/web lint
corepack pnpm --filter @dispatch/web test
corepack pnpm --filter @dispatch/web build
```

### API

```powershell
cd services/api
uv run ruff check .
uv run ruff format --check .
uv run pytest
```

### Mobile

```powershell
cd apps/mobile
flutter analyze
flutter test
```

## Supabase Workflow

This repo is hosted-Supabase-first for Phase 0. It does not assume `supabase start` or a local Docker stack.

### Apply migrations

Use the SQL in `supabase/migrations/20260328011000_phase0_foundation.sql` against your hosted development project.

Recommended options:

1. Supabase Studio SQL Editor for initial bootstrap.
2. `npx supabase db push` after linking the repo to the hosted project.

### Seed baseline accounts

```powershell
py -3.12 supabase/seed/bootstrap_seed.py
```

This script creates:

- 1 municipality admin
- 4 approved department accounts: fire, police, medical, disaster

Default emails:

- `municipality.admin@dispatch.local`
- `fire.station@dispatch.local`
- `police.station@dispatch.local`
- `medical.response@dispatch.local`
- `mdrrmo.ops@dispatch.local`

All seeded accounts use `SEED_DEFAULT_PASSWORD`.

## Seeded Ownership Model

- Municipality admin is the only seeded `municipality` user.
- Department seeds are created as approved responders.
- Citizens are not pre-seeded in Phase 0.
- Public schema user records mirror `auth.users.id`.

## App Ownership

- `apps/web`
  - role shells
  - protected routes
  - typed API client
  - Supabase realtime helper
- `services/api`
  - Flask app factory
  - health and readiness endpoints
  - Supabase auth middleware and role guards
  - storage validation helpers
- `apps/mobile`
  - role-aware navigation
  - mobile service wrappers
  - file-backed session cache and offline queue scaffolding
- `supabase`
  - schema contracts
  - RLS policies
  - storage buckets
  - realtime publication

## Notes

- Municipality admin workflows are web-first in Phase 0.
- Playwright is intentionally deferred until Phase 1.
- Android SDK is only required for device builds; `flutter analyze` and `flutter test` work without it.
- The current mobile shell uses file-backed session caching plus placeholder offline and location services. Plugin-backed packages such as `sqflite`, `nearby_connections`, and the planned `flutter_map` integration still require a host with Flutter plugin symlink support.
