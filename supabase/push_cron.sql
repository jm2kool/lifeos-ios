-- Optional, for push: runs lumen-push every minute so the study block Live Activity appears on your iPhone about
-- ten minutes before each block, even when Lumen hasn't been opened. Needs the lumen-push function deployed and the
-- LUMEN_CRON_SECRET secret set (any long random string).
--
-- Replace REPLACE_WITH_LUMEN_CRON_SECRET with that same string, then run this once in Supabase → SQL Editor.
-- To stop it: select cron.unschedule('lumen-push');

create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.unschedule('lumen-push') where exists (select 1 from cron.job where jobname = 'lumen-push');

select cron.schedule('lumen-push', '* * * * *', $$
  select net.http_post(
    url := 'https://pryljjakjcswekcwxcog.supabase.co/functions/v1/lumen-push',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-lumen-cron', 'REPLACE_WITH_LUMEN_CRON_SECRET'),
    body := '{"tick": true}'::jsonb,
    timeout_milliseconds := 15000
  );
$$);
