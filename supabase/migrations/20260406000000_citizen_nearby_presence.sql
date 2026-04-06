-- =============================================================================
-- Citizen nearby presence pins
-- =============================================================================

create table if not exists public.citizen_nearby_presence (
  user_id uuid primary key references public.users(id) on delete cascade,
  display_name text not null default '',
  lat double precision not null,
  lng double precision not null,
  location jsonb not null default '{}'::jsonb,
  accuracy_meters real,
  last_seen_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists citizen_nearby_presence_last_seen_idx
on public.citizen_nearby_presence (last_seen_at desc);

create index if not exists citizen_nearby_presence_lat_lng_idx
on public.citizen_nearby_presence (lat, lng);

drop trigger if exists set_citizen_nearby_presence_updated_at on public.citizen_nearby_presence;
create trigger set_citizen_nearby_presence_updated_at
before update on public.citizen_nearby_presence
for each row execute procedure public.set_updated_at();

alter table public.citizen_nearby_presence enable row level security;

drop policy if exists "citizen_nearby_presence_select_authenticated" on public.citizen_nearby_presence;
create policy "citizen_nearby_presence_select_authenticated"
on public.citizen_nearby_presence for select
using (auth.role() = 'authenticated');

drop policy if exists "citizen_nearby_presence_insert_self" on public.citizen_nearby_presence;
create policy "citizen_nearby_presence_insert_self"
on public.citizen_nearby_presence for insert
with check (auth.uid() = user_id);

drop policy if exists "citizen_nearby_presence_update_self" on public.citizen_nearby_presence;
create policy "citizen_nearby_presence_update_self"
on public.citizen_nearby_presence for update
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

do $$
begin
  begin
    alter publication supabase_realtime add table public.citizen_nearby_presence;
  exception when duplicate_object then
    null;
  end;
end $$;
