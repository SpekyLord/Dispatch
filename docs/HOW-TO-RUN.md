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
| `MOBILE_WEB_API_BASE_URL` | `http://127.0.0.1:5000` (`flutter run -d chrome`) |
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
corepack pnpm --filter @dispatch/web test:e2e # Playwright smoke/e2e
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
flutter run --dart-define-from-file=.env
```

> **Note:** Android SDK is only required for device/emulator builds. `flutter analyze` and `flutter test` work without it.
>
> **Chrome note:** `flutter run -d chrome` uses `MOBILE_WEB_API_BASE_URL` if provided. If you leave it blank, the app falls back to the current browser host on port `5000`. The API now allows localhost and `127.0.0.1` development origins on any port.
>
> **APK note:** A plain `flutter build apk` does not pick up your mobile `.env` unless you pass it during the build. Use:
>
> ```bash
> flutter build apk --dart-define-from-file=.env
> ```
>
> If that APK will run on a physical Android phone, `MOBILE_API_BASE_URL` must not be `http://10.0.2.2:5000`, because `10.0.2.2` only works inside the Android emulator.

### Running on a Physical Android Phone

Use this flow when testing on a real phone instead of emulator/Chrome.
For full mesh pass/fail execution steps, use [MESH-FIELD-TEST-PROCEDURE.md](MESH-FIELD-TEST-PROCEDURE.md).

1. Set API host so your phone can reach your backend over LAN:

```bash
# services/api/.env
API_HOST=0.0.0.0
API_PORT=5000
```

2. Set the mobile API base URL to your computer's LAN IP:

```bash
# apps/mobile/.env
MOBILE_API_BASE_URL=http://<YOUR_PC_LAN_IP>:5000
```

Example: `http://192.168.254.119:5000`

If you are building an APK for that phone instead of using `flutter run`, build it with the same `.env` file:

```bash
cd apps/mobile
flutter build apk --dart-define-from-file=.env
```

3. Start the API:

```bash
cd services/api
uv run dispatch-api
```

4. Connect your Android phone (USB debugging on) and verify Flutter sees it:

```bash
flutter devices
```

5. Run the app on that specific device:

```bash
cd apps/mobile
flutter pub get
flutter run -d <DEVICE_ID> --dart-define-from-file=.env --no-pub
```

6. Grant runtime permissions when prompted (required for mesh and SAR on phone):

- Location (GPS)
- Nearby Devices / Bluetooth (scan, connect, advertise)
- Nearby Wi-Fi Devices
- Microphone

The app now keeps prompting for missing mesh/SAR permissions on resume until all required permissions are approved. If Android marks a permission as "Don't ask again", use **Open App Settings** in the app permission gate.

### Wi-Fi Probe Notes (Mobile)

- Wi-Fi probe detection means passively sniffing nearby device Wi-Fi probe requests to estimate presence.
- In this mobile build, Wi-Fi probe is intentionally unavailable on standard Android/iOS app sandboxing.
- Mesh and SAR still work through BLE passive scan, SOS beacon advertising, microphone window summaries, GPS/location beacons, and gateway sync.

Optional (USB-only): route phone localhost to your computer localhost so you can use `http://127.0.0.1:5000` instead of LAN IP:

```bash
adb reverse tcp:5000 tcp:5000
```

If `adb` is not in PATH, use Android Studio's terminal or add Android SDK platform-tools to your PATH.

First Android build on a machine can be slow because Gradle/Flutter artifacts are downloaded. To prefetch them once:

```bash
flutter precache --android
```

### Mobile Linting & Tests

```bash
cd apps/mobile
flutter analyze    # Dart analyzer
flutter test       # Unit tests
```

If this Windows host cannot enable Flutter plugin symlink support, use the targeted fallback mesh suite instead of blocking on a full plugin bootstrap:

```bash
cd apps/mobile
flutter test --no-pub test/mesh_transport_test.dart test/survivor_compass_screen_test.dart test/offline_comms_screen_test.dart
```

---

## 6. Phase 3-4 Verification Baseline

The canonical Phase 3/4 verification package lives in [PHASE3-4-VERIFICATION.md](PHASE3-4-VERIFICATION.md).

Quick baseline commands:

```bash
# API
cd services/api
uv run pytest tests/test_phase3.py tests/test_phase4.py

# Web
cd apps/web
corepack pnpm test
corepack pnpm build

# Mobile
cd apps/mobile
flutter analyze
flutter test
```

For responsive smoke coverage, run:

```bash
cd apps/web
corepack pnpm test:e2e
```

---

## 7. Database Setup

Before using any app, you need to apply the Supabase migration and run the seed script. See [SUPABASE-SETUP.md](SUPABASE-SETUP.md) for the full walkthrough.

Quick version:

1. Apply `supabase/migrations/20260401000000_consolidated.sql` in the Supabase SQL Editor (idempotent — safe to re-run)
2. Apply `supabase/migrations/20260404000000_feed_assessment_posts.sql` so assessment-style feed posts can be saved
3. Run the seed: `py -3.12 supabase/seed/bootstrap_seed.py` (requires `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` in env)

---

## 8. Phase 4 Hardware Readiness

Physical Phase 4 mesh execution is still pending by design and requires hardware. The implementation and automation baseline are ready; the field run itself must follow [MESH-FIELD-TEST-PROCEDURE.md](MESH-FIELD-TEST-PROCEDURE.md).

Minimum preflight:

- 2+ BLE-capable phones or tablets, preferably 3 for relay-plus-gateway validation
- 1 gateway device with backend connectivity
- seeded citizen and approved department accounts
- confirmed backend URL on the gateway device
- local mesh reset before each manual run

Topology upload trigger points (gateway-ready mobile sessions):

- Offline Comms `Sync queued packets` now uploads queued packets and a `topologySnapshot` in the same ingest call.
- Mesh Network pull-to-refresh / refresh button now also performs a gateway sync, allowing topology-only uploads even when no packets are queued.
- If gateway coordinates are unavailable, packet sync still proceeds and topology upload is skipped for that attempt.

Use the reporting template inside `docs/MESH-FIELD-TEST-PROCEDURE.md` for the final pass/fail log.

---

## 9. CI/CD

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
| CORS errors on Flutter web | Restart the API after pulling the latest changes so development localhost ports are allowed, then confirm the mobile app is using `MOBILE_WEB_API_BASE_URL` or the browser-host fallback |
