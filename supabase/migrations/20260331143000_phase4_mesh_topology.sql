-- Phase 4 extension: gateway-uploaded mesh topology snapshots for the web map.

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

create index if not exists mesh_topology_nodes_last_seen_idx
  on public.mesh_topology_nodes (last_seen_at desc);
create index if not exists mesh_topology_nodes_role_idx
  on public.mesh_topology_nodes (node_role, last_seen_at desc);
create index if not exists mesh_topology_nodes_department_idx
  on public.mesh_topology_nodes (department_id, last_seen_at desc);
create index if not exists mesh_topology_nodes_responder_idx
  on public.mesh_topology_nodes (is_responder, last_seen_at desc);

alter table public.mesh_topology_nodes enable row level security;

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

drop trigger if exists set_mesh_topology_nodes_updated_at on public.mesh_topology_nodes;
create trigger set_mesh_topology_nodes_updated_at
before update on public.mesh_topology_nodes
for each row execute procedure public.set_updated_at();

do $$
begin
  begin
    alter publication supabase_realtime add table public.mesh_topology_nodes;
  exception when duplicate_object or undefined_object then null;
  end;
end $$;
