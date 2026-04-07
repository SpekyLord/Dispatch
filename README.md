<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/Pictures/dispatch-logo-white.svg" />
    <source media="(prefers-color-scheme: light)" srcset="docs/Pictures/Dispatch Logo Transparent.png" />
    <img src="docs/Pictures/dispatch-logo-white.svg" alt="Dispatch Logo" width="200" />
  </picture>
</p>

<h1 align="center">DISPATCH</h1>

<p align="center">
  <strong>Unified Disaster Risk Reduction & Emergency Response Platform</strong>
</p>

<p align="center">
  <em>Prototype / Hackathon Pitch</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-prototype-yellow" alt="Status" />
  <img src="https://img.shields.io/badge/platform-web%20%7C%20android-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/backend-Flask-black" alt="Backend" />
  <img src="https://img.shields.io/badge/frontend-React%2019-61DAFB" alt="Frontend" />
  <img src="https://img.shields.io/badge/mobile-Flutter-02569B" alt="Mobile" />
  <img src="https://img.shields.io/badge/database-Supabase-3ECF8E" alt="Database" />
  <img src="https://img.shields.io/badge/mesh-BLE%20%2B%20WiFi%20Direct-orange" alt="Mesh" />
</p>

---

## Overview

**Dispatch** is a DRRM (Disaster Risk Reduction and Management) emergency response platform that connects citizens, verified emergency response departments, and municipalities into a unified system.

It solves the coordination gap during disasters by streamlining incident reporting, emergency response routing, inter-department visibility, and post-disaster recovery — even in areas with zero internet connectivity through offline mesh networking.

Built for local government units, emergency responders, and citizens in disaster-prone regions.

> **Note:** This is a development prototype built for a hackathon pitch. It is not deployed to production.

---

## Key Features

### Incident Reporting
- Citizens submit geo-tagged incident reports with photos, location, and severity
- Reports auto-route to relevant departments by category (fire, flood, earthquake, medical, etc.)
- Real-time status tracking with full timeline (pending → accepted → responding → resolved)

### Department Response
- Category-filtered incident boards per department type
- Accept/decline workflow with inter-department visibility
- Public announcements, warnings, and post-disaster assessments
- Department verification queue managed by municipality

### Municipality Administration
- System-wide report overview and escalation monitoring
- Department verification and approval pipeline
- Analytics dashboard: report volume, response times, department activity
- Damage assessment aggregation

### Offline Mesh Networking
- BLE + Wi-Fi Direct mesh for zero-internet environments
- Citizen-to-citizen BLE chat sessions for direct emergency communication
- Survivor signal detection and distress broadcasting
- Mesh topology tracking with device trail history
- Priority-based packet routing (DISTRESS > SURVIVOR_SIGNAL > STATUS_UPDATE)
- Automatic data reconciliation when connectivity is restored

### Real-Time Dashboard
- Leaflet-based incident mapping
- Supabase Realtime subscriptions for live updates
- Role-based views for citizens, departments, and municipality admins

---

## System Architecture

```
[ Citizen Mobile ]  <--BLE/WiFi-->  [ Citizen Mobile ]
        |                                   |
   Local Mesh Node                 Local Mesh Node
        |______________ ___________________|
                       |
                [ Mesh Gateway ]
                       |
              [ Flask API Backend ]
                       |
             [ Supabase (PostgreSQL) ]
                       |
              [ React Dashboard ]
```

### Component Breakdown

| Component | Role |
|-----------|------|
| **Mobile App** | Field device for citizens and responders — report incidents, receive alerts, participate in mesh |
| **Flask API** | REST backend handling auth, report lifecycle, mesh ingestion, and notifications |
| **Supabase** | Hosted PostgreSQL with RLS, auth, realtime, and storage buckets |
| **React Dashboard** | Web interface for all roles — incident monitoring, department management, analytics |
| **Mesh Layer** | BLE + Wi-Fi Direct peer-to-peer network for offline data relay |

### Data Flow

```
Device → Mesh Relay → Gateway → /api/mesh/ingest → Supabase → Dashboard (Realtime)
Device → Internet  → /api/reports → Supabase → Dashboard (Realtime)
```

### Offline-First Design

When internet is unavailable, devices form a local mesh network. Reports and distress signals hop across nodes until they reach a gateway with connectivity. Data syncs and reconciles automatically once a connection is restored. Offline JWT tokens enable emergency authentication without server access.

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Mobile | Flutter (Riverpod, GoRouter, Dio) | Field app, mesh node, offline-capable client (Android) |
| Mesh Layer | BLE + Wi-Fi Direct | Offline peer-to-peer communication |
| Backend | Flask (Python 3.12) | REST API, mesh ingestion, auth middleware |
| Database | Supabase (PostgreSQL + RLS) | Cloud storage, auth, realtime, file storage |
| Local Storage | SQLite (sqflite) | On-device offline data persistence |
| Dashboard | React 19 + Vite + Tailwind | Incident monitoring, analytics, admin UI |
| Mapping | Leaflet / flutter_map | Geo-tagged incident visualization |
| CI/CD | GitHub Actions | Lint, test, and build across all components |

---

## Offline & Mesh Behavior

### Offline Mode
The mobile app functions with zero internet. Reports are queued locally in SQLite, mesh packets are relayed via BLE, and offline JWTs signed with `crypto` allow emergency authentication without server round-trips.

### Mesh Topology
Devices discover each other via BLE advertising. Each device maintains a fingerprint and broadcasts presence. The `/api/mesh/citizen-presence/nearby` endpoint helps locate nearby citizens within a configurable radius.

### Message Routing
Data hops across mesh nodes using priority-based sorting:
1. **DISTRESS** — highest priority
2. **SURVIVOR_SIGNAL** — detection alerts
3. **INCIDENT_REPORT / MESH_MESSAGE / MESH_POST** — standard
4. **LOCATION_BEACON / SYNC_ACK** — background

### Conflict Resolution
When two devices sync conflicting data, the backend processes packets in batch via `/api/mesh/ingest` with topology snapshots. Timestamps and device fingerprints are used to determine ordering.

### Sync Behavior
On reconnection, devices call `/api/mesh/sync-updates?since=<timestamp>` to pull missed updates. SYNC_ACK payloads confirm successful delivery.

### Known Limitations
- BLE range: ~10-30 meters depending on device
- Max mesh hops determined by device density
- Battery impact increases with active BLE scanning
- Topology snapshots are point-in-time, not continuously streamed

---

## Getting Started

### Prerequisites

- **Node.js** 22 LTS (`>=22 <25`) with `corepack` enabled
- **pnpm** (via corepack)
- **Python** 3.12
- **uv** (Python package manager)
- **Flutter** stable channel
- **Android SDK** (for device builds; not required for `flutter analyze` / `flutter test`)
- A **Supabase** hosted project with project URL, anon key, and service role key

### Installation

```bash
# Clone the repo
git clone https://github.com/SpekyLord/Dispatch.git
cd Dispatch
```

### Environment Variables

```bash
# Copy all env templates
cp .env.example .env
cp services/api/.env.example services/api/.env
cp apps/web/.env.example apps/web/.env
cp apps/mobile/.env.example apps/mobile/.env
```

Fill in your Supabase credentials in each `.env` file:

| Variable | Where | Description |
|----------|-------|-------------|
| `SUPABASE_URL` | root, api | Supabase project URL |
| `SUPABASE_ANON_KEY` | root, api | Supabase anonymous key |
| `SUPABASE_SERVICE_ROLE_KEY` | root, api | Supabase service role key |
| `VITE_API_BASE_URL` | web | Backend URL (default: `http://127.0.0.1:5000`) |
| `VITE_SUPABASE_URL` | web | Supabase URL for frontend |
| `VITE_SUPABASE_ANON_KEY` | web | Supabase anon key for frontend |
| `MOBILE_API_BASE_URL` | mobile | API URL for Android emulator (`http://10.0.2.2:5000`) |
| `MOBILE_WEB_API_BASE_URL` | mobile | API URL for Flutter web (`http://127.0.0.1:5000`) |
| `MOBILE_SUPABASE_URL` | mobile | Supabase URL for mobile |
| `MOBILE_SUPABASE_ANON_KEY` | mobile | Supabase anon key for mobile |
| `SEED_DEFAULT_PASSWORD` | root | Password for seeded accounts (default: `Dispatch123!`) |

### Database Setup

Apply the migration SQL against your hosted Supabase project:

```bash
# Option 1: Paste into Supabase Studio SQL Editor
# File: supabase/migrations/20260406200000_seed.sql

# Option 2: Use Supabase CLI
npx supabase db push
```

Seed baseline accounts:

```bash
python supabase/seed/bootstrap_seed.py
```

This creates 1 municipality admin + 4 approved departments (fire, police, medical, disaster). See [Seeded Accounts](#seeded-accounts) for details.

### Running Each Component

**Backend**
```bash
cd services/api
uv sync --group dev
uv run dispatch-api
# Runs on http://127.0.0.1:5000
```

**Web Dashboard**
```bash
corepack enable
corepack pnpm install
corepack pnpm --filter @dispatch/web dev
# Runs on http://localhost:5173
```

**Mobile (Android)**
```bash
cd apps/mobile
flutter pub get
flutter run --dart-define-from-file=.env
```

> **Note:** Use `MOBILE_API_BASE_URL=http://10.0.2.2:5000` for Android emulator. For physical devices or APKs, point to your actual backend host. For Flutter web, use `MOBILE_WEB_API_BASE_URL`.

---

## Project Structure

```
Dispatch/
├── apps/
│   ├── web/                    # React + Vite + Tailwind dashboard
│   │   ├── src/
│   │   │   ├── app/            # Router & design tokens
│   │   │   ├── components/     # UI components (branding, feed, maps, layout)
│   │   │   ├── lib/            # API client, auth, realtime helpers
│   │   │   └── pages/          # Route pages by role (citizen, department, municipality)
│   │   └── e2e/                # Playwright tests (planned)
│   └── mobile/                 # Flutter + Riverpod mobile app (Android)
│       └── lib/
│           ├── core/           # Config, services, state, theme, routing
│           └── features/       # Auth, citizen, department, municipality, mesh
├── services/
│   └── api/                    # Flask REST backend
│       └── src/dispatch_api/
│           ├── modules/        # Route blueprints (auth, reports, departments, mesh, etc.)
│           └── services/       # Business logic layer
├── supabase/
│   ├── migrations/             # SQL schema & RLS policies
│   └── seed/                   # Bootstrap seed script
├── docs/                       # PRD, phase plans, setup guides, specs
├── .github/workflows/          # CI pipeline (lint, test, build)
└── .env.example                # Root environment template
```

---

## API Documentation

**Base URL:** `http://127.0.0.1:5000/api` (local development)

**Authentication:** Bearer token via `Authorization: Bearer <jwt>` header. Supabase JWT for online auth, custom offline JWT for emergency mesh scenarios.

### Key Endpoints

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| `POST` | `/register` | Public | Sign up (citizen or department) |
| `POST` | `/login` | Public | Sign in |
| `GET` | `/me` | Yes | Current user profile |
| `POST` | `/reports` | Citizen | Create incident report |
| `GET` | `/reports` | Citizen | List own reports |
| `GET` | `/reports/<id>` | Yes | Report detail with timeline |
| `POST` | `/reports/<id>/upload` | Citizen | Upload report image |
| `GET` | `/departments/reports` | Department | Category-filtered incident board |
| `POST` | `/departments/reports/<id>/accept` | Department | Accept a report |
| `POST` | `/departments/reports/<id>/decline` | Department | Decline a report |
| `PUT` | `/departments/reports/<id>/status` | Department | Update report status |
| `POST` | `/departments/posts` | Department | Create announcement |
| `POST` | `/departments/assessments` | Department | Create damage assessment |
| `GET` | `/feed` | Public | Public announcements feed |
| `POST` | `/mesh/ingest` | Yes | Ingest offline mesh packets |
| `GET` | `/mesh/sync-updates` | Yes | Pull updates since timestamp |
| `GET` | `/mesh/topology` | Dept/Muni | Mesh node topology |
| `GET` | `/mesh/survivor-signals` | Dept/Muni | Distress signals list |
| `PUT` | `/mesh/citizen-presence` | Citizen | Update location & mesh info |
| `GET` | `/mesh/citizen-presence/nearby` | Citizen | Find nearby citizens |
| `GET` | `/health` | Public | Health check |
| `GET` | `/ready` | Public | Readiness probe with diagnostics |

**Error Format:**
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Description of the error",
    "details": {}
  }
}
```

---

## Seeded Accounts

The bootstrap seed script creates test accounts for local development:

| Role | Email | Password |
|------|-------|----------|
| Municipality | `municipality.admin@dispatch.local` | `Dispatch123!` |
| Fire Dept | `fire.station@dispatch.local` | `Dispatch123!` |
| Police Dept | `police.station@dispatch.local` | `Dispatch123!` |
| Medical Dept | `medical.response@dispatch.local` | `Dispatch123!` |
| Disaster (MDRRMO) | `mdrrmo.ops@dispatch.local` | `Dispatch123!` |
| Citizen (Demo) | `citizen.demo@dispatch.local` | `Dispatch123!` |

---

## Quality Checks

**Web**
```bash
corepack pnpm --filter @dispatch/web lint    # ESLint (zero warnings)
corepack pnpm --filter @dispatch/web test    # Vitest
corepack pnpm --filter @dispatch/web build   # Vite build
```

**API**
```bash
cd services/api
uv run ruff check .          # Lint
uv run ruff format --check . # Format check
uv run pytest                # Tests
```

**Mobile**
```bash
cd apps/mobile
flutter analyze   # Static analysis
flutter test      # Unit tests
```

---

## Contributing

1. **Fork** the repository
2. **Create a branch** from `main`: `git checkout -b feat/your-feature`
3. **Make your changes** and ensure all quality checks pass
4. **Commit** using conventional format:
   - `feat:` new feature
   - `fix:` bug fix
   - `docs:` documentation
   - `refactor:` code restructuring
   - `test:` adding or updating tests
   - `chore:` maintenance
5. **Push** and open a **Pull Request** against `main`

### Code Style
- **Web:** ESLint + Prettier (enforced in CI, zero warnings)
- **API:** Ruff (linter + formatter)
- **Mobile:** `flutter analyze` with `flutter_lints`

---

## Tools Used

### AI Tools
| Tool | Purpose |
|------|---------|
| [OpenAI Codex](https://openai.com/codex) | AI-assisted code generation and completion |
| [Claude Code](https://claude.ai/code) | AI coding assistant for development and refactoring |

### Development Environment
| Category | Tool |
|----------|------|
| IDE / Code Editor | Visual Studio Code |
| Version Control | Git / GitHub |

---

## License

This project was developed as part of a DRRM Hackathon initiative. It is a prototype and not intended for production use.
