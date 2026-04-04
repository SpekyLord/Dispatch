drop policy if exists "department_responses_select_visible_report_or_municipality" on public.department_responses;

create policy "department_responses_select_visible_report_or_municipality"
on public.department_responses for select
using (
  public.is_municipality()
  or exists (
    select 1
    from public.incident_reports
    where public.incident_reports.id = department_responses.report_id
      and public.incident_reports.reporter_id = auth.uid()
  )
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
