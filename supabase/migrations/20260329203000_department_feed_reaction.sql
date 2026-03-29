alter table public.department_feed_posts
add column if not exists reaction integer not null default 0;
