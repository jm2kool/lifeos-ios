// deno test supabase/tests — exercises lumen-agent against an in-memory database.
import { handle } from '../functions/lumen-agent/agent.ts';
import { sha256Hex } from '../functions/lumen-agent/db.ts';
import * as T from '../functions/lumen-agent/time.ts';
import { FakeDb } from './fake_db.ts';

function assert(cond: unknown, msg = 'assertion failed'): asserts cond { if (!cond) throw new Error(msg); }
function equal<T>(a: T, b: T, msg = '') { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); }

const USER = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const KEY = 'lmn_testkey_full_access_0123456789abcdefghij';
const READ_KEY = 'lmn_testkey_read_only_0123456789abcdefghijkl';
// Wednesday 4 November 2026, 15:20 in London (GMT, so UTC too)
const NOW = new Date('2026-11-04T15:20:00Z');

async function setup() {
  const db = new FakeDb(() => NOW);
  db.seed('agent_keys', { user_id: USER, name: 'Instinct', key_hash: await sha256Hex(KEY), scopes: ['read', 'write:assignments', 'write:plan', 'write:cards', 'write:syllabus'], revoked_at: null, last_used_at: null });
  db.seed('agent_keys', { user_id: USER, name: 'Reader', key_hash: await sha256Hex(READ_KEY), scopes: ['read'], revoked_at: null, last_used_at: null });
  db.seed('agent_keys', { user_id: USER, name: 'Old', key_hash: await sha256Hex('lmn_revoked'), scopes: ['read'], revoked_at: '2026-10-01T00:00:00Z' });
  db.seed('preferences', { id: USER, user_id: USER, timezone: 'Europe/London', max_hours_per_day: 3, block_minutes: 50, break_minutes: 10, no_study_days: [6], earliest_time: '08:00', latest_time: '22:00', plan_mode: 'ask', new_cards_per_day: 10, daily_goal_minutes: 120, webhook_secret: 'shh' });
  // Weekdays 16:00–21:00 free; Wednesday club 18:00–19:00
  for (const d of [1, 2, 3, 4, 5]) db.seed('availability', { user_id: USER, weekday: d, start_time: '16:00', end_time: '21:00', kind: 'free' });
  db.seed('availability', { user_id: USER, weekday: 0, start_time: '10:00', end_time: '17:00', kind: 'free' });
  db.seed('availability', { user_id: USER, weekday: 3, start_time: '18:00', end_time: '19:00', kind: 'busy', label: 'Chess club' });
  db.seed('busy_slots', { user_id: USER, start_at: '2026-11-05T17:00:00Z', end_at: '2026-11-05T18:00:00Z', source: 'calendar', title: null });
  const physics = db.seed('subjects', { user_id: USER, name: 'Physics' });
  const ch3 = db.seed('chapters', { user_id: USER, subject_id: physics.id, number: 3, title: 'Forces' });
  db.seed('topics', { user_id: USER, subject_id: physics.id, chapter_id: ch3.id, title: "Newton's laws", status: 'mastered' });
  db.seed('topics', { user_id: USER, subject_id: physics.id, chapter_id: ch3.id, title: 'Friction', status: 'learning' });
  const hw = db.seed('assignments', { user_id: USER, title: 'Physics worksheet', subject_id: physics.id, chapter_ids: [ch3.id], due_at: '2026-11-06T08:00:00Z', estimated_hours: 2 });
  db.seed('focus_sessions', { user_id: USER, started_at: '2026-11-04T09:00:00Z', ended_at: '2026-11-04T09:30:00Z', minutes: 30, subject_id: physics.id, assignment_id: hw.id });
  db.seed('focus_sessions', { user_id: USER, started_at: '2026-11-03T09:00:00Z', ended_at: '2026-11-03T09:45:00Z', minutes: 45, subject_id: physics.id });
  db.seed('blocks', { user_id: USER, start_at: '2026-11-04T16:00:00Z', end_at: '2026-11-04T16:50:00Z', subject_id: physics.id, assignment_id: hw.id, created_by: 'instinct' });
  db.seed('blocks', { user_id: USER, start_at: '2026-11-04T19:00:00Z', end_at: '2026-11-04T19:45:00Z', created_by: 'me', goal: 'My own block' });
  const deck = db.seed('decks', { user_id: USER, name: 'Forces', subject_id: physics.id, chapter_id: ch3.id });
  db.seed('cards', { user_id: USER, deck_id: deck.id, front: 'F = ?', back: 'ma', state: 'review', due_at: '2026-11-04T10:00:00Z' });
  db.seed('cards', { user_id: USER, deck_id: deck.id, front: 'Unit of force', back: 'newton', state: 'new' });
  db.seed('assignments', { user_id: OTHER, title: 'Not mine' });
  return { db, physics, ch3, hw, deck };
}

async function call(db: FakeDb, method: string, path: string, body?: unknown, key = KEY) {
  const req = new Request(`https://x.supabase.co/functions/v1/lumen-agent${path}`, {
    method, headers: key ? { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' } : {},
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const res = await handle(req, { db, now: () => NOW });
  return { status: res.status, body: await res.json() };
}

Deno.test('time zones: London winter and summer', () => {
  equal(T.zoned(2026, 11, 4, 16, 0, 'Europe/London').toISOString(), '2026-11-04T16:00:00.000Z');
  equal(T.zoned(2026, 7, 1, 16, 0, 'Europe/London').toISOString(), '2026-07-01T15:00:00.000Z');
  equal(T.zoned(2026, 3, 29, 12, 0, 'America/New_York').toISOString(), '2026-03-29T16:00:00.000Z');
  equal(T.isoLocal(new Date('2026-07-01T15:00:00Z'), 'Europe/London'), '2026-07-01T16:00:00+01:00');
  equal(T.partsIn(new Date('2026-11-04T23:30:00Z'), 'Asia/Kolkata').weekday, 4);
});

Deno.test('keys: missing, wrong, revoked and good', async () => {
  const { db } = await setup();
  equal((await call(db, 'GET', '/', undefined, '')).status, 401);
  equal((await call(db, 'GET', '/', undefined, 'lmn_nope')).status, 401);
  const revoked = await call(db, 'GET', '/', undefined, 'lmn_revoked');
  equal(revoked.status, 401);
  assert(String(revoked.body.error).includes('revoked'));
  const ok = await call(db, 'GET', '/');
  equal(ok.status, 200);
  equal(ok.body.key, 'Instinct');
  assert(db.t('agent_keys')[0].last_used_at, 'last_used_at stamped');
});

Deno.test('scopes: a read-only key cannot write', async () => {
  const { db } = await setup();
  const r = await call(db, 'POST', '/assignments', { title: 'x' }, READ_KEY);
  equal(r.status, 403);
  equal((await call(db, 'GET', '/assignments', undefined, READ_KEY)).status, 200);
});

Deno.test('context: everything in one call, free time around busy times and blocks', async () => {
  const { db, hw } = await setup();
  const r = await call(db, 'GET', '/context?from=2026-11-04&to=2026-11-08');
  equal(r.status, 200, 'status');
  const c = r.body;
  equal(c.timezone, 'Europe/London');
  assert(!('webhook_secret' in c.preferences), 'secret hidden');
  const a = c.assignments.find((x: { id: string }) => x.id === hw.id);
  equal(a.logged_minutes, 30);
  equal(a.remaining_minutes, 90);
  equal(a.planned_minutes, 50);
  assert(!c.assignments.some((x: { title: string }) => x.title === 'Not mine'), 'only my rows');
  // Wednesday: 16:00–21:00 free, minus the 16:00 and 19:00 blocks and chess club 18–19
  const wed = c.availability.free_slots.filter((s: { start_local: string }) => s.start_local.startsWith('2026-11-04'));
  equal(wed.map((s: { start_local: string; end_local: string }) => `${s.start_local.slice(11, 16)}-${s.end_local.slice(11, 16)}`), ['16:50-18:00', '19:45-21:00']);
  // Thursday: the calendar slot 17–18 is taken out
  const thu = c.availability.free_slots.filter((s: { start_local: string }) => s.start_local.startsWith('2026-11-05'));
  equal(thu.map((s: { start_local: string; end_local: string }) => `${s.start_local.slice(11, 16)}-${s.end_local.slice(11, 16)}`), ['16:00-17:00', '18:00-21:00']);
  // Saturday is a no-study day
  equal(c.availability.free_minutes_by_day['2026-11-07'], 0);
  equal(c.availability.free_minutes_by_day['2026-11-08'], 420);
  assert(c.availability.busy_slots.some((b: { title: string }) => b.title === 'Chess club'), 'weekly busy expanded');
  equal(c.cards.due_now, 1);
  equal(c.cards.new_available, 1);
  equal(c.focus.minutes_today, 30);
  equal(c.focus.streak_days, 2);
  equal(c.syllabus[0].progress, 0.67);
  equal(c.blocks.upcoming.length, 2);
});

Deno.test('assignments: create, change, delete — all logged for undo', async () => {
  const { db, physics } = await setup();
  const made = await call(db, 'POST', '/assignments', { title: 'Chem lab report', kind: 'project', subject_id: physics.id, due_at: '2026-11-13T17:00', estimated_hours: 3, reason: 'From your email' });
  equal(made.status, 200);
  const row = db.t('assignments').find((x) => x.id === made.body.id)!;
  equal(row.created_by, 'instinct');
  equal(row.due_at, '2026-11-13T17:00:00.000Z', 'local time read in London');
  equal(db.t('activity').length, 1);
  equal(db.t('activity')[0].reason, 'From your email');
  const bad = await call(db, 'POST', '/assignments', { title: '', kind: 'essay' });
  equal(bad.status, 400);
  const patched = await call(db, 'PATCH', `/assignments/${made.body.id}`, { status: 'done' });
  equal(patched.status, 200);
  assert(db.t('assignments').find((x) => x.id === made.body.id)!.completed_at, 'completed_at set');
  const gone = await call(db, 'DELETE', `/assignments/${made.body.id}`, { reason: 'Duplicate' });
  equal(gone.status, 200);
  equal(db.t('assignments').find((x) => x.id === made.body.id)!.deleted, true);
  // Undo the delete
  const undo = await call(db, 'POST', '/undo', { batch_id: gone.body.batch_id });
  equal(undo.body.undone, 1);
  equal(db.t('assignments').find((x) => x.id === made.body.id)!.deleted, false);
});

Deno.test('blocks: a block over a busy time is refused', async () => {
  const { db } = await setup();
  const clash = await call(db, 'POST', '/blocks', { start_at: '2026-11-05T17:30:00Z', end_at: '2026-11-05T18:15:00Z', goal: 'x' });
  equal(clash.status, 409);
  const club = await call(db, 'POST', '/blocks', { start_at: '2026-11-04T18:15:00Z', end_at: '2026-11-04T18:45:00Z' });
  equal(club.status, 409, 'weekly busy');
  const ok = await call(db, 'POST', '/blocks', { start_at: '2026-11-05T18:10:00Z', end_at: '2026-11-05T19:00:00Z', kind: 'revision' });
  equal(ok.status, 200);
});

Deno.test('plan: clashes are reported; ask mode saves a proposal; auto mode applies', async () => {
  const { db, hw, deck } = await setup();
  const blocks = [
    { start_at: '2026-11-05T16:00:00Z', end_at: '2026-11-05T16:50:00Z', assignment_id: hw.id, goal: 'Questions 1–6', reason: 'Due Friday' },
    { start_at: '2026-11-05T17:15:00Z', end_at: '2026-11-05T17:45:00Z', assignment_id: hw.id, goal: 'Clashes with calendar' },
    { start_at: '2026-11-05T20:30:00Z', end_at: '2026-11-05T20:45:00Z', kind: 'review', deck_id: deck.id, goal: 'Cards' },
  ];
  const clash = await call(db, 'POST', '/plan', { blocks, reasoning: 'Spread before Friday' });
  equal(clash.status, 422);
  equal(clash.body.details.conflicts[0].index, 1);

  const asked = await call(db, 'POST', '/plan', { blocks, reasoning: 'Spread before Friday', drop_conflicts: true });
  equal(asked.status, 200);
  equal(asked.body.status, 'proposed');
  const p = db.t('proposals')[0];
  equal(p.blocks.length, 2);
  equal(p.blocks[0].subject_id, hw.subject_id, 'subject filled from the assignment');
  equal(p.blocks[0].chapter_ids, hw.chapter_ids, 'chapters filled from the assignment');
  equal(p.blocks[1].subject_id, deck.subject_id, 'subject filled from the deck');

  const again = await call(db, 'POST', '/plan', { blocks: blocks.filter((_, i) => i !== 1), mode: 'auto', from: '2026-11-04', to: '2026-11-06' });
  equal(again.status, 200);
  equal(again.body.status, 'applied');
  const apply = db.rpcs.find((r) => r.name === 'apply_plan')!;
  equal(apply.args.p_actor, 'instinct');
  // Instinct's 16:00 block today hasn't started yet, so the new plan replaces it; your own 19:00 block stays.
  equal(again.body.removed.length, 1);
  const live = db.t('blocks').filter((b) => !b.deleted);
  equal(live.length, 3);
  assert(live.some((b) => b.goal === 'My own block'), 'your own block is kept');
});

Deno.test('plan: warnings for limits and outside windows', async () => {
  const { db } = await setup();
  const r = await call(db, 'POST', '/plan', {
    dry_run: true, blocks: [
      { start_at: '2026-11-07T10:00:00Z', end_at: '2026-11-07T11:00:00Z', goal: 'Saturday' },
      { start_at: '2026-11-05T07:00:00Z', end_at: '2026-11-05T07:30:00Z', goal: 'Too early' },
    ],
  });
  equal(r.status, 200);
  equal(r.body.status, 'valid');
  assert(r.body.warnings.some((w: string) => w.includes('no-study day')), 'no-study warning');
  assert(r.body.warnings.some((w: string) => w.includes('outside 08:00–22:00')), 'hours warning');
});

Deno.test('events: cursor, own changes hidden by default', async () => {
  const { db } = await setup();
  db.seed('events', { user_id: USER, type: 'block.completed', actor: 'me', data: {} });
  db.seed('events', { user_id: USER, type: 'assignment.added', actor: 'instinct', data: {} });
  db.seed('events', { user_id: USER, type: 'block.missed', actor: 'system', data: {} });
  db.seed('events', { user_id: OTHER, type: 'block.completed', actor: 'me', data: {} });
  const r = await call(db, 'GET', '/events?since=0');
  equal(r.body.events.map((e: { type: string }) => e.type), ['block.completed', 'block.missed']);
  equal(r.body.cursor, '3');
  const next = await call(db, 'GET', `/events?since=${r.body.cursor}`);
  equal(next.body.events.length, 0);
  const typed = await call(db, 'GET', '/events?since=0&types=block.*&include_own=true');
  equal(typed.body.events.length, 2);
});

Deno.test('decks with cards in one call, and a syllabus import', async () => {
  const { db, physics } = await setup();
  const r = await call(db, 'POST', '/decks', { name: 'Waves', subject_id: physics.id, cards: [{ front: 'v = ?', back: '$f\\lambda$' }, { front: 'Unit of frequency', back: 'Hz' }] });
  equal(r.status, 200);
  equal(r.body.decks[0].cards.length, 2);
  const s = await call(db, 'POST', '/syllabus', { subject: { name: 'physics' }, chapters: [{ number: 3, title: 'Forces', topics: ['Momentum'] }, { number: 4, title: 'Energy', topics: ['Work', { title: 'Power', status: 'learning' }] }] });
  equal(s.status, 200);
  equal(s.body.subject_id, physics.id, 'matched existing subject by name');
  equal(db.t('chapters').length, 2, 'chapter 3 reused, chapter 4 added');
  equal(db.t('topics').length, 5);
  const tree = await call(db, 'GET', '/syllabus');
  equal(tree.body.subjects[0].chapters.length, 2);
});
