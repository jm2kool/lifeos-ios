-- Minimal stand-ins for the parts of Supabase the migration touches (auth, storage, pg_net, realtime), so it can be tested on plain Postgres.
-- Minimal stand-ins for what Supabase provides.
do $$ begin create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; exception when others then null; end $$;
create schema auth; create schema extensions; create schema storage; create schema net;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role', true) $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text, public bool);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text);
create function storage.foldername(name text) returns text[] language sql as $$ select string_to_array(name, '/') $$;
create table net.calls (url text, body jsonb, headers jsonb);
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint
  language sql security definer as $$ insert into net.calls values (url, body, headers); select 1::bigint $$;
grant usage on schema net to public; grant execute on all functions in schema net to public;
create publication supabase_realtime;
