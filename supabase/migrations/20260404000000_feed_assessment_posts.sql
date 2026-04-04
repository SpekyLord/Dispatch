alter table public.department_feed_posts
  add column if not exists post_kind text not null default 'standard',
  add column if not exists assessment_details jsonb;

update public.department_feed_posts
set post_kind = 'standard'
where post_kind is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'department_feed_posts_post_kind_check'
  ) then
    alter table public.department_feed_posts
      add constraint department_feed_posts_post_kind_check
      check (post_kind in ('standard', 'assessment'));
  end if;
end
$$;
