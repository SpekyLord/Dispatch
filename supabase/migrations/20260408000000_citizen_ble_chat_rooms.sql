alter table public.citizen_ble_chat_sessions
add column if not exists room_id uuid;

create table if not exists public.citizen_ble_chat_rooms (
  id uuid primary key,
  creator_user_id uuid not null references public.users(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz not null,
  closed_at timestamptz
);

create index if not exists citizen_ble_chat_rooms_status_idx
on public.citizen_ble_chat_rooms (status, created_at desc);

create index if not exists citizen_ble_chat_rooms_creator_idx
on public.citizen_ble_chat_rooms (creator_user_id, created_at desc);

create table if not exists public.citizen_ble_chat_room_members (
  id uuid primary key,
  room_id uuid not null references public.citizen_ble_chat_rooms(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  mesh_device_id text not null,
  display_name text not null default '',
  status text not null default 'active',
  joined_at timestamptz not null default timezone('utc', now()),
  left_at timestamptz,
  unique (room_id, user_id)
);

create index if not exists citizen_ble_chat_room_members_room_idx
on public.citizen_ble_chat_room_members (room_id, status);

create index if not exists citizen_ble_chat_room_members_user_idx
on public.citizen_ble_chat_room_members (user_id, status);

alter table public.citizen_ble_chat_rooms enable row level security;
alter table public.citizen_ble_chat_room_members enable row level security;

drop policy if exists "citizen_ble_chat_rooms_select_authenticated" on public.citizen_ble_chat_rooms;
create policy "citizen_ble_chat_rooms_select_authenticated"
on public.citizen_ble_chat_rooms for select
using (auth.role() = 'authenticated');

drop policy if exists "citizen_ble_chat_rooms_insert_authenticated" on public.citizen_ble_chat_rooms;
create policy "citizen_ble_chat_rooms_insert_authenticated"
on public.citizen_ble_chat_rooms for insert
with check (auth.role() = 'authenticated');

drop policy if exists "citizen_ble_chat_rooms_update_authenticated" on public.citizen_ble_chat_rooms;
create policy "citizen_ble_chat_rooms_update_authenticated"
on public.citizen_ble_chat_rooms for update
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

drop policy if exists "citizen_ble_chat_room_members_select_authenticated" on public.citizen_ble_chat_room_members;
create policy "citizen_ble_chat_room_members_select_authenticated"
on public.citizen_ble_chat_room_members for select
using (auth.role() = 'authenticated');

drop policy if exists "citizen_ble_chat_room_members_insert_authenticated" on public.citizen_ble_chat_room_members;
create policy "citizen_ble_chat_room_members_insert_authenticated"
on public.citizen_ble_chat_room_members for insert
with check (auth.role() = 'authenticated');

drop policy if exists "citizen_ble_chat_room_members_update_authenticated" on public.citizen_ble_chat_room_members;
create policy "citizen_ble_chat_room_members_update_authenticated"
on public.citizen_ble_chat_room_members for update
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

do $$
begin
  begin
    alter publication supabase_realtime add table public.citizen_ble_chat_rooms;
  exception when duplicate_object then
    null;
  end;

  begin
    alter publication supabase_realtime add table public.citizen_ble_chat_room_members;
  exception when duplicate_object then
    null;
  end;
end $$;
