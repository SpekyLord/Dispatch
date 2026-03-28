# How to Run Dispatch

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Node.js | 22 LTS (>=22 <25) | [nodejs.org](https://nodejs.org/) |
| Corepack | (ships with Node) | `corepack enable` |
| Python | 3.12 | [python.org](https://www.python.org/) |
| uv | latest | `pip install uv` or [docs.astral.sh/uv](https://docs.astral.sh/uv/) |
| Flutter | stable (^3.11.4) | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| Git | latest | [git-scm.com](https://git-scm.com/) |

You also need a **Supabase project** — see [SUPABASE-SETUP.md](SUPABASE-SETUP.md) for details.

---

## 1. Clone the Repository

```bash
git clone https://github.com/<your-org>/Dispatch.git
cd Dispatch
```

## 2. Environment Variables

Copy all `.env.example` files and fill in your Supabase credentials:

```bash
cp .env.example .env
cp services/api/.env.example services/api/.env
cp apps/web/.env.example apps/web/.env
cp apps/mobile/.env.example apps/mobile/.env
```

**Root `.env`** — main config shared across apps:

| Variable | Description |
|----------|-------------|
| `DISPATCH_ENV` | `development` |
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anon/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Your Supabase service role key |
| `VITE_API_BASE_URL` | `http://127.0.0.1:5000` |
| `VITE_SUPABASE_URL` | Same as `SUPABASE_URL` |
| `VITE_SUPABASE_ANON_KEY` | Same as `SUPABASE_ANON_KEY` |
| `MOBILE_SUPABASE_URL` | Same as `SUPABASE_URL` |
| `MOBILE_SUPABASE_ANON_KEY` | Same as `SUPABASE_ANON_KEY` |
| `MOBILE_API_BASE_URL` | `http://10.0.2.2:5000` (Android emulator) |
| `SEED_DEFAULT_PASSWORD` | `Dispatch123!` |

Each sub-app `.env` file mirrors the relevant subset — see the `.env.example` in each directory.

---

## 3. Running the Web App

```bash
corepack enable
corepack pnpm install
corepack pnpm --filter @dispatch/web dev
```

The web app starts at **http://localhost:5173**.

### Web Linting & Tests

```bash
corepack pnpm --filter @dispatch/web lint     # ESLint
corepack pnpm --filter @dispatch/web test     # Vitest
corepack pnpm --filter @dispatch/web build    # Production build
```

---

## 4. Running the API

```bash
cd services/api
uv sync --group dev
uv run dispatch-api
```

The API starts at **http://127.0.0.1:5000**.

### API Linting & Tests

```bash
cd services/api
uv run ruff check .           # Lint
uv run ruff format --check .  # Format check
uv run pytest                 # Unit tests
```

---

## 5. Running the Mobile App

```bash
cd apps/mobile
flutter pub get
flutter run
```

> **Note:** Android SDK is only required for device/emulator builds. `flutter analyze` and `flutter test` work without it.

### Mobile Linting & Tests

```bash
cd apps/mobile
flutter analyze    # Dart analyzer
flutter test       # Unit tests
```

---

## 6. Database Setup

Before using any app, you need to apply the Supabase migration and run the seed script. See [SUPABASE-SETUP.md](SUPABASE-SETUP.md) for the full walkthrough.

Quick version:

1. Apply `supabase/migrations/20260328011000_phase0_foundation.sql` in the Supabase SQL Editor
2. Run the seed: `py -3.12 supabase/seed/bootstrap_seed.py` (requires `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in env)

---

## 7. CI/CD

GitHub Actions CI runs automatically on pushes to `main`/`master` and all pull requests. It runs three parallel jobs:

- **Web:** install → lint → test → build
- **API:** sync deps → ruff check → ruff format → pytest
- **Mobile:** pub get → analyze → test

See `.github/workflows/ci.yml` for the full config.

---

## Project Structure

```
Dispatch/
├── apps/
│   ├── web/              # React + Vite + Tailwind + shadcn/ui
│   └── mobile/           # Flutter + Riverpod
├── services/
│   └── api/              # Flask REST API
├── supabase/
│   ├── migrations/       # PostgreSQL migrations
│   └── seed/             # Bootstrap seed script
├── docs/                 # Documentation
├── .github/workflows/    # CI/CD
└── .env.example          # Root env template
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `corepack` not found | Run `npm install -g corepack` or update Node to 22+ |
| `uv` not found | `pip install uv` or install from [docs.astral.sh/uv](https://docs.astral.sh/uv/) |
| Mobile build fails | Ensure Flutter SDK and Android SDK are installed; run `flutter doctor` |
| API can't connect to Supabase | Check `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in `services/api/.env` |
| CORS errors on web | Verify `CORS_ORIGINS` in `services/api/.env` includes your dev URL |
