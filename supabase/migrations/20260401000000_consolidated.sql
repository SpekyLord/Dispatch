-- =============================================================================
-- Dispatch – Consolidated Idempotent Migration
-- Safe to run on a fresh database OR one that already has some/all objects.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Extensions
-- ---------------------------------------------------------------------------
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 2. Enum types
-- ---------------------------------------------------------------------------
do $$
begin
  -- core enums
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('citizen', 'department', 'municipality');
  end if;
  if not exists (select 1 from pg_type where typname = 'department_type') then
    create type public.department_type as enum ('fire', 'police', 'medical', 'disaster', 'rescue', 'other');
  end if;
  if not exists (select 1 from pg_type where typname = 'verification_status') then
    create type public.verification_status as enum ('pending', 'approved', 'rejected');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_category') then
    create type public.report_category as enum ('fire', 'flood', 'earthquake', 'road_accident', 'medical', 'structural', 'other');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_severity') then
    create type public.report_severity as enum ('low', 'medium', 'high', 'critical');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_status') then
    create type public.report_status as enum ('pending', 'accepted', 'responding', 'resolved', 'rejected');
  end if;
  if not exists (select 1 from pg_type where typname = 'department_response_action') then
    create type public.department_response_action as enum ('accepted', 'declined');
  end if;
  if not exists (select 1 from pg_type where typname = 'post_category') then
    create type public.post_category as enum ('alert', 'warning', 'safety_tip', 'update', 'situational_report');
  end if;
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum ('report_update', 'new_report', 'verification_decision', 'announcement');
  end if;
  if not exists (select 1 from pg_type where typname = 'damage_level') then
    create type public.damage_level as enum ('minor', 'moderate', 'severe', 'critical');
  end if;
  -- mesh enums
  if not exists (select 1 from pg_type where typname = 'mesh_processing_state') then
    create type public.mesh_processing_state as enum ('pending', 'processed', 'failed', 'duplicate');
  end if;
  if not exists (select 1 from pg_type where typname = 'mesh_payload_type') then
    create type public.mesh_payload_type as enum (
      'INCIDENT_REPORT', 'ANNOUNCEMENT', 'DISTRESS', 'STATUS_UPDATE', 'SYNC_ACK'
    );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Enum value additions (must be outside transaction on some PG versions)
-- ---------------------------------------------------------------------------
do $$
begin
  begin
    alter type public.mesh_payload_type add value 'SURVIVOR_SIGNAL';
  exception when duplicate_object then null;
  end;
end $$;

do $$
begin
  begin
    alter type public.mesh_payload_type add value if not exists 'MESH_MESSAGE';
  exception when duplicate_object then null;
  end;
  begin
    alter type public.mesh_payload_type add value if not exists 'MESH_POST';
  exception when duplicate_object then null;
  end;
end $$;

do $$
begin
  begin
    alter type public.mesh_payload_type add value if not exists 'LOCATION_BEACON';
  exception when duplicate_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Helper functions (table-independent)
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Core tables
-- ---------------------------------------------------------------------------
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role public.user_role not null,
  full_name text not null,
  phone text,
  avatar_url text,
  is_verified boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.users(id) on delete cascade,
  name text not null,
  type public.department_type not null,
  description text not null default '',
  contact_number text not null default '',
  address text not null default '',
  area_of_responsibility text not null default '',
  verification_status public.verification_status not null default 'pending',
  verified_by uuid references public.users(id) on delete set null,
  verified_at timestamptz,
  rejection_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.incident_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  description text not null,
  category public.report_category not null,
  severity public.report_severity not null default 'medium',
  status public.report_status not null default 'pending',
  latitude double precision,
  longitude double precision,
  address text,
  image_urls text[] not null default '{}'::text[],
  is_escalated boolean not null default false,
  resolved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.department_responses (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.incident_reports(id) on delete cascade,
  department_id uuid not null references public.departments(id) on delete cascade,
  action public.department_response_action not null,
  decline_reason text,
  responded_at timestamptz not null default timezone('utc', now()),
  notes text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.report_status_history (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.incident_reports(id) on delete cascade,
  old_status public.report_status,
  new_status public.report_status not null,
  changed_by uuid references public.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  content text not null,
  category public.post_category not null,
  image_urls text[] not null default '{}'::text[],
  is_pinned boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  type public.notification_type not null,
  title text not null,
  message text not null,
  reference_id uuid,
  reference_type text,
  is_read boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  read_at timestamptz
);

create table if not exists public.damage_assessments (
  id uuid primary key default gen_random_uuid(),
  department_id uuid not null references public.departments(id) on delete cascade,
  author_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  description text not null,
  affected_area text not null,
  damage_level public.damage_level not null,
  casualties integer not null default 0,
  displaced_persons integer not null default 0,
  image_urls text[] not null default '{}'::text[],
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

-- ---------------------------------------------------------------------------
-- 5b. Helper functions (require users table)
-- ---------------------------------------------------------------------------
create or replace function public.current_app_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.users
  where id = auth.uid()
  limit 1;
$$;

create or replace function public.is_municipality()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_app_role() = 'municipality'::public.user_role, false);
$$;

-- ---------------------------------------------------------------------------
-- 6. Department helper functions
-- ---------------------------------------------------------------------------
create or replace function public.current_department_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.departments
  where user_id = auth.uid()
    and verification_status = 'approved'::public.verification_status
  limit 1;
$$;

create or replace function public.current_department_type()
returns public.department_type
language sql
stable
security definer
set search_path = public
as $$
  select type
  from public.departments
  where user_id = auth.uid()
    and verification_status = 'approved'::public.verification_status
  limit 1;
$$;

create or replace function public.is_approved_department()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_department_id() is not null;
$$;

create or replace function public.current_department_can_view_report(
  report_category public.report_category,
  report_is_escalated boolean
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      with current_department as (
        select public.current_department_type() as department_type
      )
      select case
        when current_department.department_type is null then false
        when report_category = 'fire'::public.report_category then
          current_department.department_type = 'fire'::public.department_type
          or (
            report_is_escalated
            and current_department.department_type = 'disaster'::public.department_type
          )
        when report_category = 'flood'::public.report_category then
          current_department.department_type = 'disaster'::public.department_type
        when report_category = 'earthquake'::public.report_category then
          current_department.department_type = 'disaster'::public.department_type
        when report_category = 'road_accident'::public.report_category then
          current_department.department_type = 'police'::public.department_type
          or (
            report_is_escalated
            and current_department.department_type = 'disaster'::public.department_type
          )
        when report_category = 'medical'::public.report_category then
          current_department.department_type in (
            'medical'::public.department_type,
            'rescue'::public.department_type
          )
          or (
            report_is_escalated
            and current_department.department_type = 'disaster'::public.department_type
          )
        when report_category = 'structural'::public.report_category then
          current_department.department_type = 'disaster'::public.department_type
        when report_category = 'other'::public.report_category then
          current_department.department_type = 'disaster'::public.department_type
        else false
      end
      from current_department
    ),
    false
  );
$$;

-- ---------------------------------------------------------------------------
-- 7. Department feed tables
-- ---------------------------------------------------------------------------
create table if not exists public.department_feed_posts (
  id bigint generated by default as identity primary key,
  uploader uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  title text not null,
  content text not null,
  category text not null,
  location text not null
);

create table if not exists public.department_feed_storage (
  id bigint not null references public.department_feed_posts(id) on delete cascade,
  photos text,
  attachments text
);

create table if not exists public.department_feed_comment (
  comment_id bigint generated by default as identity primary key,
  post_id bigint not null references public.department_feed_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  user_name text not null,
  created_at timestamptz not null default timezone('utc', now()),
  comment text not null
);

create table if not exists public.department_feed_reactions (
  reaction_id bigint generated by default as identity primary key,
  post_id bigint not null references public.department_feed_posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  unique (post_id, user_id)
);

-- ---------------------------------------------------------------------------
-- 8. ALTER TABLE – add columns to existing tables
-- ---------------------------------------------------------------------------
-- department_feed_posts: reaction counter
alter table public.department_feed_posts
add column if not exists reaction integer not null default 0;

-- incident_reports: mesh origin tracking
alter table public.incident_reports
  add column if not exists mesh_message_id text,
  add column if not exists is_mesh_origin boolean not null default false;

-- posts: mesh origin tracking
alter table public.posts
  add column if not exists mesh_message_id text,
  add column if not exists is_mesh_origin boolean not null default false,
  add column if not exists mesh_originated boolean not null default false;

-- ---------------------------------------------------------------------------
-- 9. Mesh tables
-- ---------------------------------------------------------------------------
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

create table if not exists public.survivor_signals (
  id uuid primary key default gen_random_uuid(),
  message_id text not null unique references public.mesh_messages(message_id) on delete cascade,
  origin_device_id text not null default '',
  detection_method text not null,
  signal_strength_dbm integer not null default -90,
  estimated_distance_meters double precision not null default 0,
  detected_device_identifier text not null,
  last_seen_timestamp timestamptz not null,
  node_location jsonb not null default '{}'::jsonb,
  confidence double precision not null default 0,
  acoustic_pattern_matched text not null default 'none',
  hop_count integer not null default 0,
  resolved boolean not null default false,
  resolved_by uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  resolution_note text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.mesh_topology_nodes (
  id uuid primary key default gen_random_uuid(),
  node_device_id text not null unique,
  gateway_device_id text not null default '',
  node_role text not null default 'origin',
  node_location jsonb not null default '{}'::jsonb,
  peer_count integer not null default 0,
  queue_depth integer not null default 0,
  last_seen_at timestamptz not null default timezone('utc', now()),
  last_sync_at timestamptz not null default timezone('utc', now()),
  display_name text not null default '',
  operator_role public.user_role,
  department_id uuid references public.departments(id) on delete set null,
  department_name text not null default '',
  is_responder boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mesh_topology_nodes_role_check
    check (node_role in ('origin', 'relay', 'gateway'))
);

create table if not exists public.mesh_comms_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null,
  message_id text not null unique references public.mesh_messages(message_id) on delete cascade,
  recipient_scope text not null check (recipient_scope in ('broadcast', 'department', 'direct')),
  recipient_identifier text,
  body text not null check (char_length(body) <= 500),
  author_display_name text not null,
  author_role text not null check (author_role in ('citizen', 'department', 'anonymous')),
  author_identifier text,
  author_department_id uuid references public.departments(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.device_location_trail (
  id uuid primary key default gen_random_uuid(),
  message_id text not null unique references public.mesh_messages(message_id) on delete cascade,
  device_fingerprint text not null,
  display_name text,
  location jsonb not null default '{}'::jsonb,
  accuracy_meters real,
  battery_pct integer,
  app_state text not null default 'foreground',
  recorded_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint device_location_trail_app_state_check
    check (app_state in ('foreground', 'background', 'sos_active'))
);

-- ---------------------------------------------------------------------------
-- 10. Indexes
-- ---------------------------------------------------------------------------
-- users
create index if not exists users_role_idx on public.users (role);

-- departments
create index if not exists departments_type_verification_idx on public.departments (type, verification_status);

-- incident_reports
create index if not exists incident_reports_reporter_idx on public.incident_reports (reporter_id);
create index if not exists incident_reports_category_status_created_idx on public.incident_reports (category, status, created_at desc);
create index if not exists incident_reports_escalated_status_created_idx on public.incident_reports (is_escalated, status, created_at desc);

-- department_responses
create index if not exists department_responses_report_department_idx on public.department_responses (report_id, department_id, responded_at desc);

-- notifications
create index if not exists notifications_user_read_created_idx on public.notifications (user_id, is_read, created_at desc);

-- posts
create index if not exists posts_department_category_created_idx on public.posts (department_id, category, created_at desc);
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists posts_category_created_idx on public.posts (category, created_at desc);
create index if not exists posts_mesh_originated_idx on public.posts (mesh_originated, created_at desc);

-- damage_assessments
create index if not exists damage_assessments_department_created_idx on public.damage_assessments (department_id, created_at desc);

-- department_feed_posts
create index if not exists department_feed_posts_created_idx on public.department_feed_posts (created_at desc);
create index if not exists department_feed_posts_category_created_idx on public.department_feed_posts (category, created_at desc);

-- department_feed_storage
create index if not exists department_feed_storage_post_idx on public.department_feed_storage (id);

-- department_feed_comment
create index if not exists department_feed_comment_post_idx on public.department_feed_comment (post_id, created_at desc);
create index if not exists department_feed_comment_user_idx on public.department_feed_comment (user_id);

-- department_feed_reactions
create index if not exists department_feed_reactions_post_idx on public.department_feed_reactions (post_id);
create index if not exists department_feed_reactions_user_idx on public.department_feed_reactions (user_id);

-- mesh_messages
create index if not exists mesh_messages_message_id_idx on public.mesh_messages (message_id);
create index if not exists mesh_messages_pending_idx on public.mesh_messages (processing_state) where processing_state = 'pending';
create index if not exists mesh_messages_origin_device_idx on public.mesh_messages (origin_device_id, created_at desc);
create index if not exists mesh_messages_payload_type_idx on public.mesh_messages (payload_type);

-- distress_signals
create index if not exists distress_signals_unresolved_idx on public.distress_signals (is_resolved, created_at desc) where is_resolved = false;
create index if not exists distress_signals_device_idx on public.distress_signals (origin_device_id);

-- survivor_signals
create index if not exists survivor_signals_active_idx on public.survivor_signals (resolved, created_at desc);
create index if not exists survivor_signals_detection_method_idx on public.survivor_signals (detection_method, created_at desc);
create index if not exists survivor_signals_last_seen_idx on public.survivor_signals (last_seen_timestamp desc);

-- mesh_topology_nodes
create index if not exists mesh_topology_nodes_last_seen_idx on public.mesh_topology_nodes (last_seen_at desc);
create index if not exists mesh_topology_nodes_role_idx on public.mesh_topology_nodes (node_role, last_seen_at desc);
create index if not exists mesh_topology_nodes_department_idx on public.mesh_topology_nodes (department_id, last_seen_at desc);
create index if not exists mesh_topology_nodes_responder_idx on public.mesh_topology_nodes (is_responder, last_seen_at desc);

-- mesh_comms_messages
create index if not exists mesh_comms_messages_thread_idx on public.mesh_comms_messages (thread_id, created_at desc);
create index if not exists mesh_comms_messages_scope_idx on public.mesh_comms_messages (recipient_scope, created_at desc);

-- device_location_trail
create index if not exists device_location_trail_device_recorded_idx on public.device_location_trail (device_fingerprint, recorded_at desc);
create index if not exists device_location_trail_recorded_idx on public.device_location_trail (recorded_at desc);

-- ---------------------------------------------------------------------------
-- 11. Triggers
-- ---------------------------------------------------------------------------
drop trigger if exists set_users_updated_at on public.users;
create trigger set_users_updated_at before update on public.users for each row execute procedure public.set_updated_at();

drop trigger if exists set_departments_updated_at on public.departments;
create trigger set_departments_updated_at before update on public.departments for each row execute procedure public.set_updated_at();

drop trigger if exists set_incident_reports_updated_at on public.incident_reports;
create trigger set_incident_reports_updated_at before update on public.incident_reports for each row execute procedure public.set_updated_at();

drop trigger if exists set_posts_updated_at on public.posts;
create trigger set_posts_updated_at before update on public.posts for each row execute procedure public.set_updated_at();

drop trigger if exists set_damage_assessments_updated_at on public.damage_assessments;
create trigger set_damage_assessments_updated_at before update on public.damage_assessments for each row execute procedure public.set_updated_at();

drop trigger if exists set_mesh_topology_nodes_updated_at on public.mesh_topology_nodes;
create trigger set_mesh_topology_nodes_updated_at before update on public.mesh_topology_nodes for each row execute procedure public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 12. Enable RLS
-- ---------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.departments enable row level security;
alter table public.incident_reports enable row level security;
alter table public.department_responses enable row level security;
alter table public.report_status_history enable row level security;
alter table public.posts enable row level security;
alter table public.notifications enable row level security;
alter table public.damage_assessments enable row level security;
alter table public.department_feed_posts enable row level security;
alter table public.department_feed_storage enable row level security;
alter table public.department_feed_comment enable row level security;
alter table public.department_feed_reactions enable row level security;
alter table public.mesh_messages enable row level security;
alter table public.distress_signals enable row level security;
alter table public.survivor_signals enable row level security;
alter table public.mesh_topology_nodes enable row level security;
alter table public.mesh_comms_messages enable row level security;
alter table public.device_location_trail enable row level security;

-- ---------------------------------------------------------------------------
-- 13. RLS policies (final versions only)
-- ---------------------------------------------------------------------------

-- users
drop policy if exists "users_select_self_or_municipality" on public.users;
create policy "users_select_self_or_municipality"
on public.users for select
using (id = auth.uid() or public.is_municipality());

drop policy if exists "users_insert_self_or_municipality" on public.users;
create policy "users_insert_self_or_municipality"
on public.users for insert
with check (id = auth.uid() or public.is_municipality());

drop policy if exists "users_update_self_or_municipality" on public.users;
create policy "users_update_self_or_municipality"
on public.users for update
using (id = auth.uid() or public.is_municipality())
with check (id = auth.uid() or public.is_municipality());

-- departments
drop policy if exists "departments_select_owner_or_municipality" on public.departments;
create policy "departments_select_owner_or_municipality"
on public.departments for select
using (user_id = auth.uid() or public.is_municipality());

drop policy if exists "departments_insert_owner_or_municipality" on public.departments;
create policy "departments_insert_owner_or_municipality"
on public.departments for insert
with check (user_id = auth.uid() or public.is_municipality());

drop policy if exists "departments_update_owner_or_municipality" on public.departments;
create policy "departments_update_owner_or_municipality"
on public.departments for update
using (user_id = auth.uid() or public.is_municipality())
with check (user_id = auth.uid() or public.is_municipality());

-- incident_reports (final: includes department access)
drop policy if exists "incident_reports_select_reporter_or_municipality" on public.incident_reports;
drop policy if exists "incident_reports_select_reporter_department_or_municipality" on public.incident_reports;
create policy "incident_reports_select_reporter_department_or_municipality"
on public.incident_reports for select
using (
  reporter_id = auth.uid()
  or public.is_municipality()
  or public.current_department_can_view_report(category, is_escalated)
);

drop policy if exists "incident_reports_insert_reporter" on public.incident_reports;
create policy "incident_reports_insert_reporter"
on public.incident_reports for insert
with check (reporter_id = auth.uid());

drop policy if exists "incident_reports_update_reporter_or_municipality" on public.incident_reports;
create policy "incident_reports_update_reporter_or_municipality"
on public.incident_reports for update
using (reporter_id = auth.uid() or public.is_municipality())
with check (reporter_id = auth.uid() or public.is_municipality());

-- department_responses (final: includes visible-report access)
drop policy if exists "department_responses_select_owner_or_municipality" on public.department_responses;
drop policy if exists "department_responses_select_visible_report_or_municipality" on public.department_responses;
create policy "department_responses_select_visible_report_or_municipality"
on public.department_responses for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.incident_reports
    where public.incident_reports.id = department_responses.report_id
      and public.current_department_can_view_report(
        public.incident_reports.category,
        public.incident_reports.is_escalated
      )
  )
);

drop policy if exists "department_responses_insert_owner_or_municipality" on public.department_responses;
create policy "department_responses_insert_owner_or_municipality"
on public.department_responses for insert
with check (
  exists (
    select 1
    from public.departments
    where public.departments.id = department_responses.department_id
      and public.departments.user_id = auth.uid()
  ) or public.is_municipality()
);

-- report_status_history (final: includes department access)
drop policy if exists "report_status_history_select_owner_or_municipality" on public.report_status_history;
drop policy if exists "report_status_history_select_reporter_department_or_municipality" on public.report_status_history;
create policy "report_status_history_select_reporter_department_or_municipality"
on public.report_status_history for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.incident_reports
    where public.incident_reports.id = report_status_history.report_id
      and public.incident_reports.reporter_id = auth.uid()
  )
  or exists (
    select 1
    from public.incident_reports
    where public.incident_reports.id = report_status_history.report_id
      and public.current_department_can_view_report(
        public.incident_reports.category,
        public.incident_reports.is_escalated
      )
  )
);

-- posts (final: public select)
drop policy if exists "posts_select_owner_or_municipality" on public.posts;
drop policy if exists "posts_select_public" on public.posts;
create policy "posts_select_public"
on public.posts for select
using (true);

drop policy if exists "posts_insert_owner_or_municipality" on public.posts;
create policy "posts_insert_owner_or_municipality"
on public.posts for insert
with check (author_id = auth.uid() or public.is_municipality());

drop policy if exists "posts_update_owner_or_municipality" on public.posts;
create policy "posts_update_owner_or_municipality"
on public.posts for update
using (author_id = auth.uid() or public.is_municipality())
with check (author_id = auth.uid() or public.is_municipality());

-- notifications
drop policy if exists "notifications_select_owner_or_municipality" on public.notifications;
create policy "notifications_select_owner_or_municipality"
on public.notifications for select
using (user_id = auth.uid() or public.is_municipality());

drop policy if exists "notifications_insert_owner_or_municipality" on public.notifications;
create policy "notifications_insert_owner_or_municipality"
on public.notifications for insert
with check (user_id = auth.uid() or public.is_municipality());

drop policy if exists "notifications_update_owner_or_municipality" on public.notifications;
create policy "notifications_update_owner_or_municipality"
on public.notifications for update
using (user_id = auth.uid() or public.is_municipality())
with check (user_id = auth.uid() or public.is_municipality());

-- damage_assessments
drop policy if exists "damage_assessments_select_owner_or_municipality" on public.damage_assessments;
create policy "damage_assessments_select_owner_or_municipality"
on public.damage_assessments for select
using (
  author_id = auth.uid()
  or exists (
    select 1
    from public.departments
    where public.departments.id = damage_assessments.department_id
      and public.departments.user_id = auth.uid()
  )
  or public.is_municipality()
);

drop policy if exists "damage_assessments_insert_owner_or_municipality" on public.damage_assessments;
create policy "damage_assessments_insert_owner_or_municipality"
on public.damage_assessments for insert
with check (
  author_id = auth.uid()
  or exists (
    select 1
    from public.departments
    where public.departments.id = damage_assessments.department_id
      and public.departments.user_id = auth.uid()
  )
  or public.is_municipality()
);

-- department_feed_posts
drop policy if exists "department_feed_posts_select_public" on public.department_feed_posts;
create policy "department_feed_posts_select_public"
on public.department_feed_posts for select
using (true);

-- department_feed_storage
drop policy if exists "department_feed_storage_select_public" on public.department_feed_storage;
create policy "department_feed_storage_select_public"
on public.department_feed_storage for select
using (true);

-- department_feed_comment
drop policy if exists "department_feed_comment_select_public" on public.department_feed_comment;
create policy "department_feed_comment_select_public"
on public.department_feed_comment for select
using (true);

-- department_feed_reactions
drop policy if exists "department_feed_reactions_select_public" on public.department_feed_reactions;
create policy "department_feed_reactions_select_public"
on public.department_feed_reactions for select
using (true);

-- mesh_messages
drop policy if exists "mesh_messages_select_municipality" on public.mesh_messages;
create policy "mesh_messages_select_municipality"
on public.mesh_messages for select
using (public.is_municipality());

drop policy if exists "mesh_messages_insert_service" on public.mesh_messages;
create policy "mesh_messages_insert_service"
on public.mesh_messages for insert
with check (true);

-- distress_signals
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

-- survivor_signals
drop policy if exists "survivor_signals_select_responder" on public.survivor_signals;
create policy "survivor_signals_select_responder"
on public.survivor_signals for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.departments
    where public.departments.user_id = auth.uid()
      and public.departments.verification_status = 'approved'::public.verification_status
  )
);

drop policy if exists "survivor_signals_insert_any" on public.survivor_signals;
create policy "survivor_signals_insert_any"
on public.survivor_signals for insert
with check (true);

drop policy if exists "survivor_signals_update_responder" on public.survivor_signals;
create policy "survivor_signals_update_responder"
on public.survivor_signals for update
using (
  public.is_municipality()
  or exists (
    select 1
    from public.departments
    where public.departments.user_id = auth.uid()
      and public.departments.verification_status = 'approved'::public.verification_status
  )
)
with check (
  public.is_municipality()
  or exists (
    select 1
    from public.departments
    where public.departments.user_id = auth.uid()
      and public.departments.verification_status = 'approved'::public.verification_status
  )
);

-- mesh_topology_nodes
drop policy if exists "mesh_topology_nodes_select_responder" on public.mesh_topology_nodes;
create policy "mesh_topology_nodes_select_responder"
on public.mesh_topology_nodes for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.departments
    where public.departments.user_id = auth.uid()
      and public.departments.verification_status = 'approved'::public.verification_status
  )
);

drop policy if exists "mesh_topology_nodes_insert_any" on public.mesh_topology_nodes;
create policy "mesh_topology_nodes_insert_any"
on public.mesh_topology_nodes for insert
with check (true);

drop policy if exists "mesh_topology_nodes_update_any" on public.mesh_topology_nodes;
create policy "mesh_topology_nodes_update_any"
on public.mesh_topology_nodes for update
using (true)
with check (true);

-- mesh_comms_messages
drop policy if exists "mesh_comms_messages_select_service" on public.mesh_comms_messages;
create policy "mesh_comms_messages_select_service"
on public.mesh_comms_messages for select
using (true);

drop policy if exists "mesh_comms_messages_insert_service" on public.mesh_comms_messages;
create policy "mesh_comms_messages_insert_service"
on public.mesh_comms_messages for insert
with check (true);

-- device_location_trail
drop policy if exists "device_location_trail_select_responder" on public.device_location_trail;
create policy "device_location_trail_select_responder"
on public.device_location_trail for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.departments
    where public.departments.user_id = auth.uid()
      and public.departments.verification_status = 'approved'::public.verification_status
  )
);

drop policy if exists "device_location_trail_insert_any" on public.device_location_trail;
create policy "device_location_trail_insert_any"
on public.device_location_trail for insert
with check (true);

-- ---------------------------------------------------------------------------
-- 14. Storage buckets
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values
  ('report-images', 'report-images', false),
  ('post-images', 'post-images', false),
  ('assessment-images', 'assessment-images', false)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values
  ('department-feed-images', 'department-feed-images', true),
  ('department-feed-attachments', 'department-feed-attachments', true)
on conflict (id) do update set public = excluded.public;

-- ---------------------------------------------------------------------------
-- 15. Storage object policies
-- ---------------------------------------------------------------------------
drop policy if exists "storage_select_owner_or_municipality" on storage.objects;
create policy "storage_select_owner_or_municipality"
on storage.objects for select
using (
  bucket_id in ('report-images', 'post-images', 'assessment-images')
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or public.is_municipality()
  )
);

drop policy if exists "storage_insert_owner_or_municipality" on storage.objects;
create policy "storage_insert_owner_or_municipality"
on storage.objects for insert
with check (
  bucket_id in ('report-images', 'post-images', 'assessment-images')
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or public.is_municipality()
  )
);

drop policy if exists "storage_update_owner_or_municipality" on storage.objects;
create policy "storage_update_owner_or_municipality"
on storage.objects for update
using (
  bucket_id in ('report-images', 'post-images', 'assessment-images')
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or public.is_municipality()
  )
)
with check (
  bucket_id in ('report-images', 'post-images', 'assessment-images')
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or public.is_municipality()
  )
);

drop policy if exists "storage_delete_owner_or_municipality" on storage.objects;
create policy "storage_delete_owner_or_municipality"
on storage.objects for delete
using (
  bucket_id in ('report-images', 'post-images', 'assessment-images')
  and (
    split_part(name, '/', 1) = auth.uid()::text
    or public.is_municipality()
  )
);

-- ---------------------------------------------------------------------------
-- 16. Realtime publications (consolidated)
-- ---------------------------------------------------------------------------
do $$
begin
  begin alter publication supabase_realtime add table public.incident_reports;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.department_responses;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.report_status_history;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.notifications;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.posts;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.department_feed_posts;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.department_feed_comment;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.distress_signals;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.mesh_messages;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.survivor_signals;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.mesh_topology_nodes;
  exception when duplicate_object or undefined_object then null; end;

  begin alter publication supabase_realtime add table public.mesh_comms_messages;
  exception when duplicate_object or undefined_object then null; end;
end $$;

-- ---------------------------------------------------------------------------
-- 17. Cleanup functions + pg_cron (location trail)
-- ---------------------------------------------------------------------------
create or replace function public.device_location_trail_ttl_hours()
returns integer
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('dispatch.device_location_trail_ttl_hours', true), '')::integer,
    72
  );
$$;

create or replace function public.cleanup_device_location_trail()
returns integer
language plpgsql
security definer
as $$
declare
  removed_count integer := 0;
begin
  delete from public.device_location_trail
  where recorded_at < timezone('utc', now()) - make_interval(hours => public.device_location_trail_ttl_hours());

  get diagnostics removed_count = row_count;
  return removed_count;
end;
$$;

do $cron_block$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('dispatch_device_location_trail_cleanup');
    exception when invalid_parameter_value then null;
    end;

    perform cron.schedule(
      'dispatch_device_location_trail_cleanup',
      '0 * * * *',
      $$select public.cleanup_device_location_trail();$$
    );
  end if;
exception when undefined_function then null;
end $cron_block$;

-- ---------------------------------------------------------------------------
-- 18. Data backfill (safe to re-run – idempotent update)
-- ---------------------------------------------------------------------------
update public.posts
set mesh_originated = true
where is_mesh_origin = true
  and mesh_originated = false;
