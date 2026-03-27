create extension if not exists pgcrypto;

do $$
begin
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
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

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

create index if not exists users_role_idx on public.users (role);
create index if not exists departments_type_verification_idx on public.departments (type, verification_status);
create index if not exists incident_reports_reporter_idx on public.incident_reports (reporter_id);
create index if not exists incident_reports_category_status_created_idx on public.incident_reports (category, status, created_at desc);
create index if not exists department_responses_report_department_idx on public.department_responses (report_id, department_id, responded_at desc);
create index if not exists notifications_user_read_created_idx on public.notifications (user_id, is_read, created_at desc);
create index if not exists posts_department_category_created_idx on public.posts (department_id, category, created_at desc);
create index if not exists damage_assessments_department_created_idx on public.damage_assessments (department_id, created_at desc);

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

alter table public.users enable row level security;
alter table public.departments enable row level security;
alter table public.incident_reports enable row level security;
alter table public.department_responses enable row level security;
alter table public.report_status_history enable row level security;
alter table public.posts enable row level security;
alter table public.notifications enable row level security;
alter table public.damage_assessments enable row level security;

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

drop policy if exists "incident_reports_select_reporter_or_municipality" on public.incident_reports;
create policy "incident_reports_select_reporter_or_municipality"
on public.incident_reports for select
using (reporter_id = auth.uid() or public.is_municipality());

drop policy if exists "incident_reports_insert_reporter" on public.incident_reports;
create policy "incident_reports_insert_reporter"
on public.incident_reports for insert
with check (reporter_id = auth.uid());

drop policy if exists "incident_reports_update_reporter_or_municipality" on public.incident_reports;
create policy "incident_reports_update_reporter_or_municipality"
on public.incident_reports for update
using (reporter_id = auth.uid() or public.is_municipality())
with check (reporter_id = auth.uid() or public.is_municipality());

drop policy if exists "department_responses_select_owner_or_municipality" on public.department_responses;
create policy "department_responses_select_owner_or_municipality"
on public.department_responses for select
using (
  exists (
    select 1
    from public.departments
    where public.departments.id = department_responses.department_id
      and public.departments.user_id = auth.uid()
  ) or public.is_municipality()
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

drop policy if exists "report_status_history_select_owner_or_municipality" on public.report_status_history;
create policy "report_status_history_select_owner_or_municipality"
on public.report_status_history for select
using (
  exists (
    select 1
    from public.incident_reports
    where public.incident_reports.id = report_status_history.report_id
      and public.incident_reports.reporter_id = auth.uid()
  ) or public.is_municipality()
);

drop policy if exists "posts_select_owner_or_municipality" on public.posts;
create policy "posts_select_owner_or_municipality"
on public.posts for select
using (author_id = auth.uid() or public.is_municipality());

drop policy if exists "posts_insert_owner_or_municipality" on public.posts;
create policy "posts_insert_owner_or_municipality"
on public.posts for insert
with check (author_id = auth.uid() or public.is_municipality());

drop policy if exists "posts_update_owner_or_municipality" on public.posts;
create policy "posts_update_owner_or_municipality"
on public.posts for update
using (author_id = auth.uid() or public.is_municipality())
with check (author_id = auth.uid() or public.is_municipality());

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

insert into storage.buckets (id, name, public)
values
  ('report-images', 'report-images', false),
  ('post-images', 'post-images', false),
  ('assessment-images', 'assessment-images', false)
on conflict (id) do nothing;

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

do $$
begin
  begin
    alter publication supabase_realtime add table public.incident_reports;
  exception when duplicate_object or undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.department_responses;
  exception when duplicate_object or undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.report_status_history;
  exception when duplicate_object or undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.notifications;
  exception when duplicate_object or undefined_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.posts;
  exception when duplicate_object or undefined_object then null;
  end;
end $$;
