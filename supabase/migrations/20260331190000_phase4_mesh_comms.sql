-- Phase 4 extension: mesh-routed communications

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

alter table public.posts
  add column if not exists mesh_originated boolean not null default false;

update public.posts
set mesh_originated = true
where is_mesh_origin = true;

create index if not exists mesh_comms_messages_thread_idx
  on public.mesh_comms_messages (thread_id, created_at desc);
create index if not exists mesh_comms_messages_scope_idx
  on public.mesh_comms_messages (recipient_scope, created_at desc);
create index if not exists posts_mesh_originated_idx
  on public.posts (mesh_originated, created_at desc);

alter table public.mesh_comms_messages enable row level security;

drop policy if exists "mesh_comms_messages_select_service" on public.mesh_comms_messages;
create policy "mesh_comms_messages_select_service"
on public.mesh_comms_messages for select
using (true);

drop policy if exists "mesh_comms_messages_insert_service" on public.mesh_comms_messages;
create policy "mesh_comms_messages_insert_service"
on public.mesh_comms_messages for insert
with check (true);

begin;
  do $$
  begin
    begin
      alter publication supabase_realtime add table public.mesh_comms_messages;
    exception when duplicate_object or undefined_object then null;
    end;
  end $$;
commit;

