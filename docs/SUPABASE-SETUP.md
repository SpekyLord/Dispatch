# Supabase Setup Guide

This guide walks you through setting up Supabase for the Dispatch platform.

---

## 1. Create a Supabase Project

1. Go to [supabase.com](https://supabase.com/) and sign in
2. Click **New Project**
3. Choose your organization, set a project name (e.g., `dispatch-dev`), and pick a database password
4. Select a region close to your users
5. Click **Create new project** and wait for provisioning to complete

---

## 2. Get Your Keys

Once the project is ready, go to **Settings > API** in the Supabase dashboard. You need three values:

| Key | Where to Find | Used By |
|-----|---------------|---------|
| **Project URL** | Settings > API > Project URL | All apps |
| **Anon/Public Key** | Settings > API > `anon` `public` | Web, Mobile |
| **Service Role Key** | Settings > API > `service_role` `secret` | API server, seed script |

> **Warning:** The service role key bypasses Row Level Security. Never expose it in client-side code.

---

## 3. Apply the Database Migration

The migration file at `supabase/migrations/20260328011000_phase0_foundation.sql` creates all enums, tables, functions, RLS policies, storage buckets, and realtime configuration.

The Phase 2 follow-up migration at `supabase/migrations/20260329020000_phase2_realtime_access.sql` adds realtime-friendly access policies and supporting indexes for department routing, feed reads, and notifications.

The consolidated baseline at `supabase/migrations/20260401000000_consolidated.sql` is the current one-file setup most local environments should apply first.

The assessment-post follow-up migration at `supabase/migrations/20260404000000_feed_assessment_posts.sql` adds the `post_kind` and `assessment_details` columns required for assessment-style feed posts.

### Option A: Supabase SQL Editor (Recommended)

1. Open your project in the Supabase dashboard
2. Go to **SQL Editor**
3. Click **New query**
4. Copy and paste the contents of `supabase/migrations/20260401000000_consolidated.sql`
5. Click **Run**
6. Create another query
7. Copy and paste the contents of `supabase/migrations/20260404000000_feed_assessment_posts.sql`
8. Click **Run**

### Option B: Supabase CLI

```bash
npx supabase link --project-ref <your-project-ref>
npx supabase db push
```

---

## 4. What the Migration Creates

### Enums

| Enum | Values |
|------|--------|
| `user_role` | `citizen`, `department`, `municipality` |
| `department_type` | `fire`, `police`, `medical`, `disaster`, `rescue`, `other` |
| `verification_status` | `pending`, `approved`, `rejected` |
| `report_category` | `fire`, `flood`, `earthquake`, `road_accident`, `medical`, `structural`, `other` |
| `report_severity` | `low`, `medium`, `high`, `critical` |
| `report_status` | `pending`, `accepted`, `responding`, `resolved`, `rejected` |
| `department_response_action` | `accepted`, `declined` |
| `post_category` | `alert`, `warning`, `safety_tip`, `update`, `situational_report` |
| `notification_type` | `report_update`, `new_report`, `verification_decision`, `announcement` |
| `damage_level` | `minor`, `moderate`, `severe`, `critical` |

### Core Tables

| Table | Purpose |
|-------|---------|
| `public.users` | Mirrors `auth.users.id` — stores role, name, verification status |
| `public.departments` | Department profiles with type, verification status, and contact info |
| `public.incident_reports` | Citizen-submitted reports with category, severity, location, and status |
| `public.department_responses` | Accept/decline records per department per report |
| `public.posts` | Official department announcements and updates |
| `public.notifications` | Per-user in-app notifications |

### Security

- **Row Level Security (RLS)** is enabled on all tables with role-based policies
- Helper functions: `current_app_role()`, `is_municipality()` for policy checks
- Auto-updating `updated_at` triggers on all tables

### Storage Buckets

Storage buckets are created for file uploads (images). Upload validation (JPEG/PNG only, max 5 MB) is enforced by the API server.

### Realtime

Realtime publication is configured for tables that need live updates (reports, notifications).

---

## 5. Run the Seed Script

The seed script creates default accounts for development and testing.

### Prerequisites

- Python 3.12+
- `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` set in your environment

### Run

```bash
# Load env vars from root .env (or export them manually)
# On Linux/macOS:
export $(grep -v '^#' .env | xargs)

# On Windows PowerShell:
Get-Content .env | ForEach-Object { if ($_ -match '^\s*([^#][^=]+)=(.*)$') { [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim()) } }

# Run the seed
py -3.12 supabase/seed/bootstrap_seed.py
```

### What It Creates

| Email | Role | Department |
|-------|------|------------|
| `municipality.admin@dispatch.local` | Municipality | — |
| `citizen.demo@dispatch.local` | Citizen | — |
| `fire.station@dispatch.local` | Department | BFP Central Station (fire) |
| `police.station@dispatch.local` | Department | PNP Central Precinct (police) |
| `medical.response@dispatch.local` | Department | City Medical Rescue Unit (medical) |
| `mdrrmo.ops@dispatch.local` | Department | Municipal DRRMO (disaster) |

All accounts use the password from `SEED_DEFAULT_PASSWORD` (default: `Dispatch123!`).

All department accounts are pre-verified (status: `approved`).

The seeded citizen account can sign in immediately and use the normal report submission flow.

---

## 6. Environment Variable Mapping

After setup, update your `.env` files with your Supabase credentials:

### Root `.env`

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-key>
MOBILE_SUPABASE_URL=https://<your-project-ref>.supabase.co
MOBILE_SUPABASE_ANON_KEY=<your-anon-key>
```

### `services/api/.env`

```
SUPABASE_URL=https://<your-project-ref>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
```

### `apps/web/.env`

```
VITE_SUPABASE_URL=https://<your-project-ref>.supabase.co
VITE_SUPABASE_ANON_KEY=<your-anon-key>
```

### `apps/mobile/.env`

```
MOBILE_SUPABASE_URL=https://<your-project-ref>.supabase.co
MOBILE_SUPABASE_ANON_KEY=<your-anon-key>
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Seed script fails with "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required" | Export these env vars before running the script |
| Seed script fails with HTTP 422 | User with that email already exists — the seed was already run |
| RLS blocks queries | Ensure the user's `role` in `public.users` matches expected role for the RLS policy |
| Migration fails on re-run | The migration uses `IF NOT EXISTS` — safe to re-run, but check for errors on altered types |
