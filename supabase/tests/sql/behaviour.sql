-- Behaviour checks for the Lumen migration: row-level security, last-write-wins, Instinct and system writes, events, webhooks, plans.
\set ON_ERROR_STOP 1
insert into auth.users values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');
-- act as user 1
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
insert into lumen.preferences (id, user_id, timezone, webhook_url, webhook_secret) values ('11111111-1111-1111-1111-111111111111', '11111111-1111-1111-1111-111111111111', 'Europe/London', 'https://example.com/hook', 's3cret');
insert into lumen.assignments (id, title, due_at, updated_at) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Physics worksheet', now() + interval '3 days', '2026-11-04 10:00:00+00');
-- an older write is skipped
update lumen.assignments set title = 'OLD', updated_at = '2026-11-04 09:00:00+00' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select 'lww-skip', title from lumen.assignments;
-- a newer one wins and bumps rev
update lumen.assignments set title = 'Newer', status = 'in_progress', updated_at = '2026-11-04 11:00:00+00' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select 'lww-win', title, rev from lumen.assignments;
-- upsert path (what the app's push does)
insert into lumen.assignments (id, user_id, title, updated_at) values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Upsert older', '2026-11-04 10:30:00+00')
  on conflict (id) do update set title = excluded.title, updated_at = excluded.updated_at;
select 'upsert-older-skipped', title from lumen.assignments;
-- user 2 can't see user 1's rows
select set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', false);
select 'rls-other-user', count(*) from lumen.assignments;
reset role;
-- Instinct (service role) writes always win, even with an old timestamp
set role service_role; select set_config('request.jwt.claim.sub', '', false);
update lumen.assignments set title = 'From Instinct', updated_by = 'instinct', updated_at = '2000-01-01' where id = 'aaaaaaaa-0000-0000-0000-000000000001';
select 'instinct-wins', title, updated_at > '2026-11-04 11:00:00+00' as newer from lumen.assignments;
-- a block in the past gets swept to missed, keeping updated_at
insert into lumen.blocks (id, user_id, start_at, end_at, updated_at) values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', now() - interval '3 hours', now() - interval '2 hours', '2026-11-01');
select 'swept', lumen.sweep_missed('11111111-1111-1111-1111-111111111111');
select 'missed', status, updated_at = '2026-11-01'::timestamptz as kept_time from lumen.blocks where id = 'bbbbbbbb-0000-0000-0000-000000000001';
-- the phone's later "done" still wins
update lumen.blocks set status = 'done', updated_by = 'me', updated_at = '2026-11-02' where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select 'phone-done-wins', status from lumen.blocks where id = 'bbbbbbbb-0000-0000-0000-000000000001';
-- plans
insert into lumen.blocks (id, user_id, start_at, end_at, created_by, updated_by) values ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', now() + interval '1 day', now() + interval '1 day 50 minutes', 'instinct', 'instinct');
insert into lumen.blocks (id, user_id, start_at, end_at) values ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', now() + interval '1 day 2 hours', now() + interval '1 day 3 hours');
select 'apply', lumen.apply_plan('11111111-1111-1111-1111-111111111111', now(), now() + interval '7 days', 'instinct',
  jsonb_build_array(jsonb_build_object('start_at', now() + interval '2 days', 'end_at', now() + interval '2 days 45 minutes', 'goal', 'Ch 3 questions', 'chapter_ids', jsonb_build_array('cccccccc-0000-0000-0000-000000000001'))),
  'instinct', 'Spread before Friday');
select 'blocks-after-plan', id, deleted, created_by, goal, chapter_ids from lumen.blocks order by start_at;
select 'activity', actor, action, summary from lumen.activity order by at;
reset role;
select 'events', type, actor, data->>'from' from lumen.events order by id;
select 'webhooks', url, headers->>'X-Lumen-Event', left(headers->>'X-Lumen-Signature', 15) from net.calls;
-- widget fallback
set role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', false);
select lumen.widget_put('0123456789abcdef0123456789abcdef', '{"todayMinutes": 42}');
set role anon;
select 'widget', lumen.widget_get('0123456789abcdef0123456789abcdef');
