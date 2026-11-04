-- Lumen: study planner data, in its own `lumen` schema so it sits beside Matinee's tables without touching them.
-- Run once in Supabase → SQL editor (or `supabase db push`). Safe to run again.
--
-- After running it: Project Settings → Data API → Exposed schemas → add `lumen` (the app and both
-- Edge Functions reach these tables through the Data API).
--
-- How sync works
--   * Every synced row has `updated_at` (when it last changed, by the writer's clock) and `rev` (a global,
--     ever-increasing number the server stamps on every write). Apps pull rows with `rev` greater than the last
--     one they saw, so nothing is missed whatever the phone's clock says.
--   * Last write wins: an update carrying an older `updated_at` than the stored row is silently skipped.
--   * Writes by Instinct (`updated_by = 'instinct'`) always win and are stamped with the server's time.
--   * Writes by the server itself (`updated_by = 'system'`, e.g. marking a block missed) keep the old
--     `updated_at`, so anything you did on your phone in the meantime still wins when it syncs.
--   * Deletes are soft (`deleted = true`) so every device hears about them.

create schema if not exists lumen;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_net;

create sequence if not exists lumen.rev_seq;

-- ───────────────────────────── helpers ─────────────────────────────

create or replace function lumen.stamp() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.updated_by = 'instinct' then
      new.updated_at := greatest(now(), old.updated_at + interval '1 millisecond');
    elsif new.updated_by = 'system' then
      new.updated_at := old.updated_at;
    elsif new.updated_at < old.updated_at then
      return null; -- an older write never overwrites a newer one
    end if;
    new.user_id := old.user_id;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
  elsif new.updated_by = 'instinct' or new.created_by = 'instinct' then
    new.updated_at := greatest(now(), new.updated_at);
  end if;
  new.rev := nextval('lumen.rev_seq');
  return new;
end $$;

-- Adds the columns every synced table shares, its trigger, index and row-level security.
create or replace function lumen.setup_synced(t text) returns void
language plpgsql set search_path = '' as $$
begin
  execute format($f$
    alter table lumen.%1$I
      add column if not exists user_id uuid not null default auth.uid() references auth.users on delete cascade,
      add column if not exists created_at timestamptz not null default now(),
      add column if not exists updated_at timestamptz not null default now(),
      add column if not exists deleted boolean not null default false,
      add column if not exists created_by text not null default 'me',
      add column if not exists updated_by text not null default 'me',
      add column if not exists reason text,
      add column if not exists rev bigint not null default 0
  $f$, t);
  execute format('drop trigger if exists stamp on lumen.%I', t);
  execute format('create trigger stamp before insert or update on lumen.%I for each row execute function lumen.stamp()', t);
  execute format('create index if not exists %I on lumen.%I (user_id, rev)', t || '_user_rev', t);
  execute format('alter table lumen.%I enable row level security', t);
  execute format('drop policy if exists "own rows" on lumen.%I', t);
  execute format('create policy "own rows" on lumen.%I for all to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))', t);
end $$;

-- ───────────────────────────── syllabus ─────────────────────────────

create table if not exists lumen.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  color text not null default '#7C8CFF',
  icon text not null default 'book.closed',
  exam_at timestamptz,
  sort int not null default 0
);

create table if not exists lumen.chapters (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null,
  number int,
  title text not null default '',
  sort int not null default 0
);

create table if not exists lumen.topics (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid,
  chapter_id uuid not null,
  title text not null,
  status text not null default 'not_started' check (status in ('not_started', 'learning', 'revised', 'mastered')),
  notes text,
  sort int not null default 0
);

-- ───────────────────────────── assignments ─────────────────────────────

create table if not exists lumen.assignments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null default 'homework' check (kind in ('homework', 'project', 'test', 'exam', 'revision')),
  subject_id uuid,
  chapter_ids uuid[] not null default '{}',
  due_at timestamptz,
  estimated_hours numeric(6, 2) not null default 1,
  priority text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'done')),
  notes text,
  completed_at timestamptz
);

create table if not exists lumen.attachments (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid,
  name text not null,
  path text not null,            -- object path in the lumen-files storage bucket
  mime text,
  size bigint
);

-- ───────────────────────────── planning ─────────────────────────────

create table if not exists lumen.blocks (
  id uuid primary key default gen_random_uuid(),
  start_at timestamptz not null,
  end_at timestamptz not null,
  kind text not null default 'study' check (kind in ('study', 'revision', 'review', 'practice')),
  subject_id uuid,
  assignment_id uuid,
  chapter_ids uuid[] not null default '{}',
  topic_ids uuid[] not null default '{}',
  deck_id uuid,
  goal text,
  status text not null default 'planned' check (status in ('planned', 'done', 'partial', 'missed', 'skipped')),
  outcome_note text,
  proposal_id uuid,
  check (end_at > start_at)
);

create table if not exists lumen.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  minutes int not null default 0,
  subject_id uuid,
  assignment_id uuid,
  block_id uuid,
  deck_id uuid,
  goal text,
  outcome text check (outcome in ('done', 'partial', 'not_done')),
  note text
);

-- Weekly pattern: when you're free to study, and regular busy times (school, practice, work).
create table if not exists lumen.availability (
  id uuid primary key default gen_random_uuid(),
  weekday smallint not null check (weekday between 0 and 6),   -- 0 = Sunday … 6 = Saturday
  start_time text not null check (start_time ~ '^\d{2}:\d{2}$'),
  end_time text not null check (end_time ~ '^\d{2}:\d{2}$'),
  kind text not null default 'free' check (kind in ('free', 'busy')),
  label text
);

-- One-off busy times: synced from the iPhone calendar (start/end only unless you allow titles), or added by hand.
create table if not exists lumen.busy_slots (
  id uuid primary key default gen_random_uuid(),
  start_at timestamptz not null,
  end_at timestamptz not null,
  source text not null default 'manual' check (source in ('calendar', 'manual')),
  title text,
  all_day boolean not null default false
);

create table if not exists lumen.preferences (
  id uuid primary key default gen_random_uuid(),
  timezone text not null default 'UTC',
  max_hours_per_day numeric(4, 2) not null default 4,
  block_minutes int not null default 50,
  break_minutes int not null default 10,
  no_study_days smallint[] not null default '{}',
  earliest_time text not null default '08:00',
  latest_time text not null default '22:00',
  plan_mode text not null default 'ask' check (plan_mode in ('auto', 'ask')),
  pomodoro_focus int not null default 25,
  pomodoro_short int not null default 5,
  pomodoro_long int not null default 15,
  pomodoro_rounds int not null default 4,
  review_time text not null default '19:00',
  new_cards_per_day int not null default 20,
  desired_retention numeric(3, 2) not null default 0.90,
  daily_goal_minutes int not null default 120,
  share_calendar_titles boolean not null default false,
  webhook_url text,
  webhook_secret text
);

-- A plan Instinct (or the built-in planner) suggested and is waiting for you on Today.
create table if not exists lumen.proposals (
  id uuid primary key default gen_random_uuid(),
  range_start timestamptz not null,
  range_end timestamptz not null,
  replace text not null default 'instinct' check (replace in ('instinct', 'all', 'none')),
  blocks jsonb not null default '[]',
  reasoning text,
  warnings jsonb not null default '[]',
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'superseded')),
  edited boolean not null default false,
  feedback text,
  decided_at timestamptz
);

-- What Instinct (and the planners) added, moved or deleted. `before` restores the row on Undo.
create table if not exists lumen.activity (
  id uuid primary key default gen_random_uuid(),
  at timestamptz not null default now(),
  batch_id uuid,
  actor text not null default 'instinct',
  action text not null,           -- created | updated | deleted | plan_applied | plan_proposed | undone
  entity text,                    -- table name
  entity_id uuid,
  summary text not null default '',
  before jsonb,
  after jsonb,
  undone_at timestamptz
);

-- ───────────────────────────── flashcards ─────────────────────────────

create table if not exists lumen.decks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject_id uuid,
  chapter_id uuid,
  notes text,
  sort int not null default 0
);

create table if not exists lumen.cards (
  id uuid primary key default gen_random_uuid(),
  deck_id uuid not null,
  front text not null default '',
  back text not null default '',
  front_image text,               -- object path in lumen-files
  back_image text,
  -- FSRS scheduling state
  state text not null default 'new' check (state in ('new', 'learning', 'review', 'relearning')),
  due_at timestamptz not null default now(),
  stability double precision not null default 0,
  difficulty double precision not null default 0,
  reps int not null default 0,
  lapses int not null default 0,
  scheduled_days double precision not null default 0,
  last_review_at timestamptz
);

create table if not exists lumen.review_logs (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null,
  deck_id uuid,
  rating smallint not null check (rating between 1 and 4),   -- 1 Again, 2 Hard, 3 Good, 4 Easy
  reviewed_at timestamptz not null default now(),
  state text,
  elapsed_days double precision,
  scheduled_days double precision,
  stability double precision,
  difficulty double precision,
  duration_ms int
);

do $$
declare t text;
begin
  foreach t in array array['subjects', 'chapters', 'topics', 'assignments', 'attachments', 'blocks', 'focus_sessions',
                           'availability', 'busy_slots', 'preferences', 'proposals', 'activity', 'decks', 'cards', 'review_logs']
  loop
    perform lumen.setup_synced(t);
  end loop;
end $$;

-- One preferences row per person.
create unique index if not exists preferences_one_per_user on lumen.preferences (user_id);
create index if not exists cards_user_due on lumen.cards (user_id, due_at) where not deleted;
create index if not exists focus_user_start on lumen.focus_sessions (user_id, started_at);
create index if not exists blocks_user_start on lumen.blocks (user_id, start_at);
create index if not exists busy_user_start on lumen.busy_slots (user_id, start_at);

-- ───────────────────────────── assistant access keys ─────────────────────────────
-- The key itself is shown once in the app and never stored: only its SHA-256 hash.

create table if not exists lumen.agent_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  key_hash text not null unique,
  prefix text not null,
  scopes text[] not null default array['read'],
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at timestamptz
);
alter table lumen.agent_keys enable row level security;
drop policy if exists "own keys" on lumen.agent_keys;
create policy "own keys" on lumen.agent_keys for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ───────────────────────────── events (what Instinct reacts to) ─────────────────────────────

create table if not exists lumen.events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  at timestamptz not null default now(),
  type text not null,
  entity text,
  entity_id uuid,
  actor text not null default 'me',
  data jsonb not null default '{}'
);
create index if not exists events_user_id on lumen.events (user_id, id);
alter table lumen.events enable row level security;
drop policy if exists "read own events" on lumen.events;
create policy "read own events" on lumen.events for select to authenticated using (user_id = (select auth.uid()));

create or replace function lumen.emit(p_user uuid, p_type text, p_entity text, p_id uuid, p_actor text, p_data jsonb)
returns void language sql security definer set search_path = '' as $$
  insert into lumen.events (user_id, type, entity, entity_id, actor, data)
  values (p_user, p_type, p_entity, p_id, coalesce(p_actor, 'me'), coalesce(p_data, '{}'::jsonb));
$$;

create or replace function lumen.on_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  actor text := new.updated_by;
  base jsonb;
begin
  if tg_table_name = 'assignments' then
    base := jsonb_build_object('title', new.title, 'kind', new.kind, 'subject_id', new.subject_id, 'due_at', new.due_at,
                               'status', new.status, 'estimated_hours', new.estimated_hours, 'priority', new.priority);
    if tg_op = 'INSERT' then
      perform lumen.emit(new.user_id, 'assignment.added', 'assignments', new.id, new.created_by, base);
    elsif new.deleted and not old.deleted then
      perform lumen.emit(new.user_id, 'assignment.deleted', 'assignments', new.id, actor, base);
    elsif new.status is distinct from old.status then
      perform lumen.emit(new.user_id, case when new.status = 'done' then 'assignment.done' else 'assignment.status' end,
                         'assignments', new.id, actor, base || jsonb_build_object('from', old.status));
    elsif new.due_at is distinct from old.due_at or new.estimated_hours is distinct from old.estimated_hours
          or new.priority is distinct from old.priority or new.title is distinct from old.title then
      perform lumen.emit(new.user_id, 'assignment.updated', 'assignments', new.id, actor,
                         base || jsonb_build_object('previous', jsonb_build_object('due_at', old.due_at, 'estimated_hours', old.estimated_hours, 'priority', old.priority)));
    end if;

  elsif tg_table_name = 'blocks' then
    base := jsonb_build_object('start_at', new.start_at, 'end_at', new.end_at, 'kind', new.kind, 'subject_id', new.subject_id,
                               'assignment_id', new.assignment_id, 'deck_id', new.deck_id, 'goal', new.goal, 'status', new.status,
                               'note', new.outcome_note);
    if tg_op = 'INSERT' then
      if new.created_by = 'me' then perform lumen.emit(new.user_id, 'block.added', 'blocks', new.id, 'me', base); end if;
    elsif new.deleted and not old.deleted then
      perform lumen.emit(new.user_id, 'block.deleted', 'blocks', new.id, actor, base);
    elsif new.status is distinct from old.status and new.status <> 'planned' then
      perform lumen.emit(new.user_id, 'block.' || case new.status when 'done' then 'completed' else new.status end,
                         'blocks', new.id, actor, base || jsonb_build_object('from', old.status));
    elsif new.start_at is distinct from old.start_at or new.end_at is distinct from old.end_at then
      perform lumen.emit(new.user_id, 'block.moved', 'blocks', new.id, actor,
                         base || jsonb_build_object('previous', jsonb_build_object('start_at', old.start_at, 'end_at', old.end_at)));
    end if;

  elsif tg_table_name = 'focus_sessions' then
    if tg_op = 'INSERT' then
      perform lumen.emit(new.user_id, 'focus.logged', 'focus_sessions', new.id, new.created_by,
        jsonb_build_object('minutes', new.minutes, 'started_at', new.started_at, 'ended_at', new.ended_at, 'subject_id', new.subject_id,
                           'assignment_id', new.assignment_id, 'block_id', new.block_id, 'deck_id', new.deck_id,
                           'outcome', new.outcome, 'note', new.note, 'goal', new.goal));
    end if;

  elsif tg_table_name = 'topics' then
    if tg_op = 'UPDATE' and new.status is distinct from old.status then
      perform lumen.emit(new.user_id, 'topic.status', 'topics', new.id, actor,
        jsonb_build_object('title', new.title, 'chapter_id', new.chapter_id, 'subject_id', new.subject_id, 'status', new.status, 'from', old.status));
    end if;

  elsif tg_table_name = 'proposals' then
    if tg_op = 'UPDATE' and new.status is distinct from old.status and new.status in ('accepted', 'rejected') then
      perform lumen.emit(new.user_id, 'proposal.' || new.status, 'proposals', new.id, actor,
        jsonb_build_object('edited', new.edited, 'feedback', new.feedback, 'range_start', new.range_start, 'range_end', new.range_end));
    end if;

  elsif tg_table_name in ('preferences', 'availability') then
    if new.created_by <> 'instinct' and actor <> 'instinct' then
      perform lumen.emit(new.user_id, tg_table_name || '.changed', tg_table_name, new.id, actor, '{}'::jsonb);
    end if;
  end if;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['assignments', 'blocks', 'focus_sessions', 'topics', 'proposals', 'preferences', 'availability']
  loop
    execute format('drop trigger if exists on_change on lumen.%I', t);
    execute format('create trigger on_change after insert or update on lumen.%I for each row execute function lumen.on_change()', t);
  end loop;
end $$;

-- Outgoing webhook: every event you (not Instinct) cause is POSTed to preferences.webhook_url, signed with
-- X-Lumen-Signature: sha256=<hex HMAC of the body with webhook_secret>. Never blocks or fails the write.
create or replace function lumen.fire_webhook() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
  v_body jsonb;
begin
  if new.actor = 'instinct' then return null; end if;
  select webhook_url, webhook_secret into v_url, v_secret
    from lumen.preferences where user_id = new.user_id and not deleted limit 1;
  if coalesce(v_url, '') !~ '^https?://' then return null; end if;
  v_body := jsonb_build_object('id', new.id, 'type', new.type, 'at', new.at, 'entity', new.entity,
                               'entity_id', new.entity_id, 'actor', new.actor, 'data', new.data);
  perform net.http_post(
    url := v_url,
    body := v_body,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'User-Agent', 'Lumen-Webhook/1',
      'X-Lumen-Event', new.type,
      'X-Lumen-Signature', 'sha256=' || encode(extensions.hmac(v_body::text, coalesce(v_secret, ''), 'sha256'), 'hex')),
    timeout_milliseconds := 5000);
  return null;
exception when others then
  raise warning 'lumen webhook skipped: %', sqlerrm;
  return null;
end $$;

drop trigger if exists webhook on lumen.events;
create trigger webhook after insert on lumen.events for each row execute function lumen.fire_webhook();

-- ───────────────────────────── server-side helpers ─────────────────────────────

-- Planned blocks that ended more than 30 minutes ago with no outcome become "missed".
create or replace function lumen.sweep_missed(p_user uuid default null) returns int
language plpgsql set search_path = '' as $$
declare n int;
begin
  if auth.uid() is not null and p_user is not null and p_user <> auth.uid() then
    raise exception 'not your data';
  end if;
  update lumen.blocks set status = 'missed', updated_by = 'system'
   where user_id = coalesce(p_user, auth.uid()) and status = 'planned' and not deleted
     and end_at < now() - interval '30 minutes';
  get diagnostics n = row_count;
  return n;
end $$;

-- Applies a plan in one transaction: removes the planned blocks it replaces, adds the new ones,
-- logs each change in the activity feed (for Undo) and marks the proposal accepted.
create or replace function lumen.apply_plan(
  p_user uuid, p_from timestamptz, p_to timestamptz, p_replace text, p_blocks jsonb,
  p_actor text default 'instinct', p_reason text default null, p_batch uuid default gen_random_uuid(),
  p_proposal uuid default null
) returns jsonb
language plpgsql set search_path = '' as $$
declare
  old_row lumen.blocks;
  new_row lumen.blocks;
  b jsonb;
  removed uuid[] := '{}';
  created uuid[] := '{}';
  tz text;
begin
  if auth.uid() is not null and p_user <> auth.uid() then
    raise exception 'not your data';
  end if;
  tz := coalesce((select timezone from lumen.preferences where user_id = p_user and not deleted limit 1), 'UTC');
  begin
    perform now() at time zone tz;
  exception when others then
    tz := 'UTC';
  end;

  if p_replace in ('instinct', 'all') then
    for old_row in
      select * from lumen.blocks
       where user_id = p_user and not deleted and status = 'planned'
         and start_at >= greatest(p_from, now()) and start_at < p_to
         and (p_replace = 'all' or created_by in ('instinct', 'auto'))
    loop
      update lumen.blocks set deleted = true, updated_by = p_actor, reason = p_reason, updated_at = now()
       where id = old_row.id returning * into new_row;
      insert into lumen.activity (user_id, batch_id, actor, action, entity, entity_id, summary, before, after, created_by, updated_by, reason)
      values (p_user, p_batch, p_actor, 'deleted', 'blocks', old_row.id,
              'Removed block ' || to_char(old_row.start_at at time zone tz, 'Dy HH24:MI'), to_jsonb(old_row), to_jsonb(new_row), p_actor, p_actor, p_reason);
      removed := removed || old_row.id;
    end loop;
  end if;

  for b in select * from jsonb_array_elements(coalesce(p_blocks, '[]'::jsonb))
  loop
    insert into lumen.blocks (id, user_id, start_at, end_at, kind, subject_id, assignment_id, chapter_ids, topic_ids, deck_id, goal,
                              status, proposal_id, created_by, updated_by, reason, updated_at)
    values (coalesce((b->>'id')::uuid, gen_random_uuid()), p_user, (b->>'start_at')::timestamptz, (b->>'end_at')::timestamptz,
            coalesce(b->>'kind', 'study'), (b->>'subject_id')::uuid, (b->>'assignment_id')::uuid,
            coalesce(array(select jsonb_array_elements_text(coalesce(b->'chapter_ids', '[]'::jsonb))::uuid), '{}'),
            coalesce(array(select jsonb_array_elements_text(coalesce(b->'topic_ids', '[]'::jsonb))::uuid), '{}'),
            (b->>'deck_id')::uuid, b->>'goal', 'planned', p_proposal, p_actor, p_actor, coalesce(b->>'reason', p_reason), now())
    returning * into new_row;
    insert into lumen.activity (user_id, batch_id, actor, action, entity, entity_id, summary, before, after, created_by, updated_by, reason)
    values (p_user, p_batch, p_actor, 'created', 'blocks', new_row.id,
            'Planned ' || new_row.kind || ' ' || to_char(new_row.start_at at time zone tz, 'Dy HH24:MI') || coalesce(' · ' || new_row.goal, ''),
            null, to_jsonb(new_row), p_actor, p_actor, coalesce(b->>'reason', p_reason));
    created := created || new_row.id;
  end loop;

  if p_proposal is not null then
    update lumen.proposals set status = 'accepted', decided_at = now(), updated_by = p_actor where id = p_proposal and user_id = p_user;
  end if;

  return jsonb_build_object('batch_id', p_batch, 'created', to_jsonb(created), 'removed', to_jsonb(removed));
end $$;

-- ───────────────────────────── widget fallback ─────────────────────────────
-- If the re-signing tool drops the App Group, the widget reads a small snapshot from here instead,
-- keyed by the private per-device id that the app and its widget share.

create table if not exists lumen.widget_snapshots (
  device text primary key,
  user_id uuid not null references auth.users on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);
alter table lumen.widget_snapshots enable row level security;

create or replace function lumen.widget_put(p_device text, p_data jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into lumen.widget_snapshots (device, user_id, data, updated_at)
  select p_device, auth.uid(), p_data, now() where auth.uid() is not null and length(p_device) >= 32
  on conflict (device) do update set data = excluded.data, user_id = excluded.user_id, updated_at = now();
$$;

create or replace function lumen.widget_get(p_device text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce((select data from lumen.widget_snapshots where device = p_device and length(p_device) >= 32), '{}'::jsonb);
$$;

-- ───────────────────────────── files ─────────────────────────────

insert into storage.buckets (id, name, public) values ('lumen-files', 'lumen-files', false)
on conflict (id) do nothing;

drop policy if exists "lumen files: own folder" on storage.objects;
create policy "lumen files: own folder" on storage.objects for all to authenticated
  using (bucket_id = 'lumen-files' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'lumen-files' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ───────────────────────────── access ─────────────────────────────

grant usage on schema lumen to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema lumen to authenticated, service_role;
grant usage, select on all sequences in schema lumen to authenticated, service_role;
alter default privileges in schema lumen grant select, insert, update, delete on tables to authenticated, service_role;

revoke execute on all functions in schema lumen from public, anon;
grant execute on function lumen.sweep_missed(uuid) to authenticated, service_role;
grant execute on function lumen.apply_plan(uuid, timestamptz, timestamptz, text, jsonb, text, text, uuid, uuid) to authenticated, service_role;
grant execute on function lumen.widget_put(text, jsonb) to authenticated;
grant execute on function lumen.widget_get(text) to anon, authenticated;
grant execute on function lumen.stamp(), lumen.on_change(), lumen.fire_webhook() to authenticated, service_role;

-- ───────────────────────────── realtime ─────────────────────────────
-- The app listens while it's open, so changes from Instinct show up straight away.

do $$
declare t text;
begin
  foreach t in array array['subjects', 'chapters', 'topics', 'assignments', 'attachments', 'blocks', 'focus_sessions',
                           'availability', 'busy_slots', 'preferences', 'proposals', 'activity', 'decks', 'cards']
  loop
    begin
      execute format('alter publication supabase_realtime add table lumen.%I', t);
    exception when others then
      raise notice 'realtime for %: %', t, sqlerrm;
    end;
  end loop;
end $$;

notify pgrst, 'reload schema';
