-- Phase 4: mesh networking tables for offline-first sync

-- mesh processing state and payload type enums
do $$
begin
  if not exists (select 1 from pg_type where typname = 'mesh_processing_state') then
    create type public.mesh_processing_state as enum ('pending', 'processed', 'failed', 'duplicate');
  end if;
  if not exists (select 1 from pg_type where typname = 'mesh_payload_type') then
    create type public.mesh_payload_type as enum (
      'INCIDENT_REPORT', 'ANNOUNCEMENT', 'DISTRESS', 'STATUS_UPDATE', 'SYNC_ACK'
    );
  end if;
end $$;

-- dedup log: every mesh packet reaching the server is recorded here
create table if not exists public.mesh_messages (
  id uuid primary key default gen_random_uuid(),
  message_id text not null unique,
  payload_type public.mesh_payload_type not null,
  origin_device_id text not null,
  hop_count integer not null default 0,
  processing_state public.mesh_processing_state not null default 'pending',
  linked_record_id uuid,
  linked_record_type text,
  raw_payload jsonb not null default '{}'::jsonb,
  signature text,
  error_message text,
  created_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz
);

-- SOS distress signals uploaded through mesh sync
create table if not exists public.distress_signals (
  id uuid primary key default gen_random_uuid(),
  message_id text not null unique,
  origin_device_id text not null,
  latitude double precision,
  longitude double precision,
  description text not null default '',
  reporter_name text not null default '',
  contact_info text not null default '',
  hop_count integer not null default 0,
  is_resolved boolean not null default false,
  resolved_by uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

-- mesh-origin tracking on existing tables
alter table public.incident_reports
  add column if not exists mesh_message_id text,
  add column if not exists is_mesh_origin boolean not null default false;

alter table public.posts
  add column if not exists mesh_message_id text,
  add column if not exists is_mesh_origin boolean not null default false;

-- indexes
create index if not exists mesh_messages_message_id_idx
  on public.mesh_messages (message_id);
create index if not exists mesh_messages_pending_idx
  on public.mesh_messages (processing_state)
  where processing_state = 'pending';
create index if not exists mesh_messages_origin_device_idx
  on public.mesh_messages (origin_device_id, created_at desc);
create index if not exists mesh_messages_payload_type_idx
  on public.mesh_messages (payload_type);
create index if not exists distress_signals_unresolved_idx
  on public.distress_signals (is_resolved, created_at desc)
  where is_resolved = false;
create index if not exists distress_signals_device_idx
  on public.distress_signals (origin_device_id);

-- RLS
alter table public.mesh_messages enable row level security;
alter table public.distress_signals enable row level security;

drop policy if exists "mesh_messages_select_municipality" on public.mesh_messages;
create policy "mesh_messages_select_municipality"
on public.mesh_messages for select
using (public.is_municipality());

drop policy if exists "mesh_messages_insert_service" on public.mesh_messages;
create policy "mesh_messages_insert_service"
on public.mesh_messages for insert
with check (true);

drop policy if exists "distress_signals_select_municipality" on public.distress_signals;
create policy "distress_signals_select_municipality"
on public.distress_signals for select
using (public.is_municipality());

drop policy if exists "distress_signals_insert_any" on public.distress_signals;
create policy "distress_signals_insert_any"
on public.distress_signals for insert
with check (true);

drop policy if exists "distress_signals_update_municipality" on public.distress_signals;
create policy "distress_signals_update_municipality"
on public.distress_signals for update
using (public.is_municipality())
with check (public.is_municipality());

-- enable realtime
do $$
begin
  begin
    alter publication supabase_realtime add table public.distress_signals;
  exception when duplicate_object or undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.mesh_messages;
  exception when duplicate_object or undefined_object then null;
  end;
end $$;
