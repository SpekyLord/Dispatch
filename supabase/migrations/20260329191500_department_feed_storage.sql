create table if not exists public.department_feed_storage (
  id bigint not null references public.department_feed_posts(id) on delete cascade,
  photos text,
  attachments text
);

create index if not exists department_feed_storage_post_idx
  on public.department_feed_storage (id);

alter table public.department_feed_storage enable row level security;

drop policy if exists "department_feed_storage_select_public" on public.department_feed_storage;
create policy "department_feed_storage_select_public"
on public.department_feed_storage for select
using (true);

insert into storage.buckets (id, name, public)
values
  ('department-feed-images', 'department-feed-images', true),
  ('department-feed-attachments', 'department-feed-attachments', true)
on conflict (id) do update set public = excluded.public;
