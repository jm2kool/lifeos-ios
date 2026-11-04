-- Lumen push: the APNs tokens each iPhone registers (for notifications, and for starting and ending the study
-- block Live Activity), and a note of which Live Activity pushes were already sent. Run after the first migration.
-- Safe to run again.

create table if not exists lumen.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  token text not null unique,
  kind text not null check (kind in ('device', 'live_activity_start', 'live_activity')),
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  bundle_id text not null,
  activity_key text,               -- for live_activity tokens: the block id the activity shows
  device_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz,         -- set when Apple says the token is no longer valid
  last_error text
);
create index if not exists push_tokens_user on lumen.push_tokens (user_id) where disabled_at is null;

alter table lumen.push_tokens enable row level security;
drop policy if exists "own tokens" on lumen.push_tokens;
create policy "own tokens" on lumen.push_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Only the server reads and writes this.
create table if not exists lumen.push_sent (
  user_id uuid not null references auth.users on delete cascade,
  key text not null,
  sent_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table lumen.push_sent enable row level security;

grant select, insert, update, delete on lumen.push_tokens to authenticated, service_role;
grant select, insert, update, delete on lumen.push_sent to service_role;

notify pgrst, 'reload schema';
