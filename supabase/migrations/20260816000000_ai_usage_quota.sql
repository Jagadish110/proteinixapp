-- Per-user, per-day, per-kind AI usage counters, used to rate-limit calls to
-- the Gemini proxy edge function without relying on the client to behave.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_date date not null default (timezone('utc', now()))::date,
  kind text not null check (kind in ('text', 'vision')),
  request_count integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, usage_date, kind)
);

alter table public.ai_usage enable row level security;

create policy "ai_usage_select_own" on public.ai_usage
  for select using (auth.uid() = user_id);

-- No insert/update/delete policy for regular users: rows are only ever
-- written by check_and_increment_ai_usage (security definer below), so a
-- patched client can't grant itself extra quota by writing this table
-- directly.

create index if not exists ai_usage_date_idx on public.ai_usage (usage_date);

-- Atomically checks today's usage against p_daily_limit and increments it if
-- under the limit, all in one round trip so concurrent requests from the same
-- user can't race past the cap. Runs as the calling user (auth.uid()), not
-- as an admin, so it can only ever touch that user's own counter.
create or replace function public.check_and_increment_ai_usage(p_kind text, p_daily_limit integer)
returns table(allowed boolean, used integer, remaining integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (timezone('utc', now()))::date;
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_kind not in ('text', 'vision') then
    raise exception 'invalid kind: %', p_kind;
  end if;

  insert into public.ai_usage (user_id, usage_date, kind, request_count)
  values (v_uid, v_today, p_kind, 0)
  on conflict (user_id, usage_date, kind) do nothing;

  select request_count into v_count
  from public.ai_usage
  where user_id = v_uid and usage_date = v_today and kind = p_kind
  for update;

  if v_count >= p_daily_limit then
    return query select false, v_count, 0;
    return;
  end if;

  update public.ai_usage
  set request_count = request_count + 1, updated_at = now()
  where user_id = v_uid and usage_date = v_today and kind = p_kind;

  return query select true, v_count + 1, greatest(p_daily_limit - v_count - 1, 0);
end;
$$;

grant execute on function public.check_and_increment_ai_usage(text, integer) to authenticated;
