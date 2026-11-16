-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, so the earlier
-- `grant ... to authenticated` in 20260816000000 didn't actually stop the
-- anon role from calling this RPC — it would just fail inside the function
-- since auth.uid() is null for anon. Close that off explicitly instead of
-- relying on the runtime check.
revoke execute on function public.check_and_increment_ai_usage(text, integer) from public;
revoke execute on function public.check_and_increment_ai_usage(text, integer) from anon;
grant execute on function public.check_and_increment_ai_usage(text, integer) to authenticated;
