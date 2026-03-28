create index if not exists incident_reports_escalated_status_created_idx
  on public.incident_reports (is_escalated, status, created_at desc);

create index if not exists posts_created_idx
  on public.posts (created_at desc);

create index if not exists posts_category_created_idx
  on public.posts (category, created_at desc);

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

drop policy if exists "incident_reports_select_reporter_department_or_municipality" on public.incident_reports;
drop policy if exists "incident_reports_select_reporter_or_municipality" on public.incident_reports;
create policy "incident_reports_select_reporter_department_or_municipality"
on public.incident_reports for select
using (
  reporter_id = auth.uid()
  or public.is_municipality()
  or public.current_department_can_view_report(category, is_escalated)
);

drop policy if exists "department_responses_select_visible_report_or_municipality" on public.department_responses;
drop policy if exists "department_responses_select_owner_or_municipality" on public.department_responses;
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

drop policy if exists "report_status_history_select_reporter_department_or_municipality" on public.report_status_history;
drop policy if exists "report_status_history_select_owner_or_municipality" on public.report_status_history;
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

drop policy if exists "posts_select_public" on public.posts;
drop policy if exists "posts_select_owner_or_municipality" on public.posts;
create policy "posts_select_public"
on public.posts for select
using (true);
