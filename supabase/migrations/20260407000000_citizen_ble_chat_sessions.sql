alter table public.citizen_nearby_presence
add column if not exists mesh_device_id text,
add column if not exists mesh_identity_hash text;

create index if not exists citizen_nearby_presence_mesh_device_id_idx
on public.citizen_nearby_presence (mesh_device_id);

create index if not exists citizen_nearby_presence_mesh_identity_hash_idx
on public.citizen_nearby_presence (mesh_identity_hash);

create table if not exists public.citizen_ble_chat_sessions (
  id uuid primary key,
  requester_user_id uuid not null references public.users(id) on delete cascade,
  recipient_user_id uuid not null references public.users(id) on delete cascade,
  requester_mesh_device_id text not null,
  recipient_mesh_device_id text not null,
  requester_display_name text not null default '',
  recipient_display_name text not null default '',
  status text not null default 'pending',
  created_at timestamptz not null default timezone('utc', now()),
  accepted_at timestamptz,
  expires_at timestamptz not null,
  closed_at timestamptz
);

create index if not exists citizen_ble_chat_sessions_requester_idx
on public.citizen_ble_chat_sessions (requester_user_id, created_at desc);

create index if not exists citizen_ble_chat_sessions_recipient_idx
on public.citizen_ble_chat_sessions (recipient_user_id, created_at desc);

create index if not exists citizen_ble_chat_sessions_status_idx
on public.citizen_ble_chat_sessions (status, expires_at);

alter table public.citizen_ble_chat_sessions enable row level security;

drop policy if exists "citizen_ble_chat_sessions_select_participants" on public.citizen_ble_chat_sessions;
create policy "citizen_ble_chat_sessions_select_participants"
on public.citizen_ble_chat_sessions for select
using (auth.uid() = requester_user_id or auth.uid() = recipient_user_id);

drop policy if exists "citizen_ble_chat_sessions_insert_requester" on public.citizen_ble_chat_sessions;
create policy "citizen_ble_chat_sessions_insert_requester"
on public.citizen_ble_chat_sessions for insert
with check (auth.uid() = requester_user_id);

drop policy if exists "citizen_ble_chat_sessions_update_participants" on public.citizen_ble_chat_sessions;
create policy "citizen_ble_chat_sessions_update_participants"
on public.citizen_ble_chat_sessions for update
using (auth.uid() = requester_user_id or auth.uid() = recipient_user_id)
with check (auth.uid() = requester_user_id or auth.uid() = recipient_user_id);

do $$
begin
  begin
    alter publication supabase_realtime add table public.citizen_ble_chat_sessions;
  exception when duplicate_object then
    null;
  end;
end $$;
