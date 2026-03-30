-- Phase 4 extension: survivor signal persistence and responder access.

do $$
begin
  begin
    alter type public.mesh_payload_type add value 'SURVIVOR_SIGNAL';
  exception
    when duplicate_object then null;
  end;
end $$;

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

create index if not exists survivor_signals_active_idx
  on public.survivor_signals (resolved, created_at desc);
create index if not exists survivor_signals_detection_method_idx
  on public.survivor_signals (detection_method, created_at desc);
create index if not exists survivor_signals_last_seen_idx
  on public.survivor_signals (last_seen_timestamp desc);

alter table public.survivor_signals enable row level security;

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

do $$
begin
  begin
    alter publication supabase_realtime add table public.survivor_signals;
  exception when duplicate_object or undefined_object then null;
  end;
end $$;
