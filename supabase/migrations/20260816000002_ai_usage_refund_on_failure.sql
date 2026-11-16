-- Companion to check_and_increment_ai_usage: called by the edge function when
-- the upstream Gemini call fails after the quota slot was already consumed,
-- so a transient Gemini-side error (rate limit, 503) doesn't cost the user
-- part of their daily allowance for something that wasn't their fault.
create or replace function public.refund_ai_usage(p_kind text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today date := (timezone('utc', now()))::date;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  if p_kind not in ('text', 'vision') then
    raise exception 'invalid kind: %', p_kind;
  end if;

  update public.ai_usage
  set request_count = greatest(request_count - 1, 0), updated_at = now()
  where user_id = v_uid and usage_date = v_today and kind = p_kind;
end;
$$;

revoke execute on function public.refund_ai_usage(text) from public;
revoke execute on function public.refund_ai_usage(text) from anon;
grant execute on function public.refund_ai_usage(text) to authenticated;
