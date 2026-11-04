#!/usr/bin/env bash
# Runs the Lumen migration twice (it must be re-runnable) against a plain Postgres with Supabase stubs, then the behaviour checks.
# Usage: PGHOST=… PGPORT=… PGUSER=postgres supabase/tests/sql/run.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../.." && pwd)
psql -v ON_ERROR_STOP=1 -q -c "drop database if exists lumen_test" -c "create database lumen_test"
psql -d lumen_test -v ON_ERROR_STOP=1 -q -f "$here/00_supabase_stubs.sql" 2>/dev/null
# Every migration, in order, twice.
cat "$root"/supabase/migrations/*.sql | sed 's/create extension if not exists pg_net;/-- pg_net stubbed/' > /tmp/lumen_migration.sql
psql -d lumen_test -v ON_ERROR_STOP=1 -q -f /tmp/lumen_migration.sql > /dev/null 2>&1 || psql -d lumen_test -v ON_ERROR_STOP=1 -q -f /tmp/lumen_migration.sql
psql -d lumen_test -v ON_ERROR_STOP=1 -q -f /tmp/lumen_migration.sql > /dev/null 2>&1 || psql -d lumen_test -v ON_ERROR_STOP=1 -q -f /tmp/lumen_migration.sql
out=$(psql -d lumen_test -At -f "$here/behaviour.sql" 2>&1 | grep -E '^(lww|upsert|rls|instinct|swept|missed|phone|apply|events|webhooks|widget)')
echo "$out"
expect() { echo "$out" | grep -qF "$1" || { echo "FAILED: expected '$1'"; exit 1; }; }
expect 'lww-skip|Physics worksheet'
expect 'upsert-older-skipped|Newer'
expect 'rls-other-user|0'
expect 'instinct-wins|From Instinct|t'
expect 'missed|missed|t'
expect 'phone-done-wins|done'
expect 'events|block.missed|system|planned'
expect 'webhooks|https://example.com/hook|block.completed'
expect 'widget|{"todayMinutes": 42}'
if echo "$out" | grep -q 'webhooks|.*|assignment.updated'; then echo "FAILED: Instinct's own change was sent to the webhook"; exit 1; fi
echo "SQL checks passed"
