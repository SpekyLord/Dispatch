-- Phase 4 extension: mesh location beacons and short-lived last-known trails.

do $$
begin
  begin
    alter type public.mesh_payload_type add value if not exists 'LOCATION_BEACON';
  exception when duplicate_object then null;
  end;
end $$;

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

create index if not exists device_location_trail_device_recorded_idx
  on public.device_location_trail (device_fingerprint, recorded_at desc);
create index if not exists device_location_trail_recorded_idx
  on public.device_location_trail (recorded_at desc);

alter table public.device_location_trail enable row level security;

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

do $$
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
end $$;
