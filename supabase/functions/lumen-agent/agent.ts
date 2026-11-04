// The Lumen agent API: what Instinct (or any assistant with an access key) uses to read your study data,
// add work, plan blocks and react to what happened. See docs/INSTINCT.md and docs/openapi.yaml.
import { Db, DbError, Query, Row, sha256Hex } from '../_shared/db.ts';
import * as T from '../_shared/time.ts';
import type { Notice } from '../_shared/apns.ts';

export interface Ctx {
  db: Db;
  now?: () => Date;
  /** Tells the student's iPhones about a change (push). Left out in tests. */
  notify?: (userId: string, notice: Notice) => void;
}

interface Caller { keyId: string; userId: string; name: string; scopes: Set<string> }

class HttpError extends Error {
  constructor(public status: number, message: string, public details?: unknown) { super(message); }
}

const VERSION = '1.0';
const SCOPES = ['read', 'write:assignments', 'write:plan', 'write:cards', 'write:syllabus'];

// ───────────────────────────── resources ─────────────────────────────

type FieldType = 'string' | 'text' | 'uuid' | 'uuid[]' | 'date' | 'number' | 'int' | 'bool' | 'enum' | 'hhmm';
interface Field { type: FieldType; values?: string[]; required?: boolean; max?: number; min?: number }
interface Resource {
  table: string;
  scope: string;
  fields: Record<string, Field>;
  order: string;
  filters: Record<string, (v: string) => [string, string]>;
  title: (r: Row, tz: string) => string;
}

const eq = (col: string) => (v: string): [string, string] => [col, `eq.${v}`];
const RESOURCES: Record<string, Resource> = {
  assignments: {
    table: 'assignments', scope: 'write:assignments', order: 'due_at.asc.nullslast',
    fields: {
      title: { type: 'string', required: true, max: 300 },
      kind: { type: 'enum', values: ['homework', 'project', 'test', 'exam', 'revision'] },
      subject_id: { type: 'uuid' },
      chapter_ids: { type: 'uuid[]' },
      due_at: { type: 'date' },
      estimated_hours: { type: 'number', min: 0.05, max: 500 },
      priority: { type: 'enum', values: ['low', 'medium', 'high', 'urgent'] },
      status: { type: 'enum', values: ['todo', 'in_progress', 'done'] },
      notes: { type: 'text', max: 20000 },
    },
    filters: {
      status: eq('status'), subject_id: eq('subject_id'), kind: eq('kind'),
      due_before: (v) => ['due_at', `lt.${v}`], due_after: (v) => ['due_at', `gte.${v}`],
    },
    title: (r, tz) => `"${r.title}"${r.due_at ? ` (due ${T.label(new Date(r.due_at), tz)})` : ''}`,
  },
  blocks: {
    table: 'blocks', scope: 'write:plan', order: 'start_at.asc',
    fields: {
      start_at: { type: 'date', required: true },
      end_at: { type: 'date', required: true },
      kind: { type: 'enum', values: ['study', 'revision', 'review', 'practice'] },
      subject_id: { type: 'uuid' },
      assignment_id: { type: 'uuid' },
      chapter_ids: { type: 'uuid[]' },
      topic_ids: { type: 'uuid[]' },
      deck_id: { type: 'uuid' },
      goal: { type: 'text', max: 2000 },
      status: { type: 'enum', values: ['planned', 'done', 'partial', 'missed', 'skipped'] },
      outcome_note: { type: 'text', max: 4000 },
    },
    filters: { status: eq('status'), assignment_id: eq('assignment_id'), subject_id: eq('subject_id'), kind: eq('kind'), deck_id: eq('deck_id') },
    title: (r, tz) => `${r.kind ?? 'study'} block ${T.label(new Date(r.start_at), tz)}${r.goal ? ` · ${r.goal}` : ''}`,
  },
  decks: {
    table: 'decks', scope: 'write:cards', order: 'name.asc',
    fields: { name: { type: 'string', required: true, max: 200 }, subject_id: { type: 'uuid' }, chapter_id: { type: 'uuid' }, notes: { type: 'text', max: 4000 } },
    filters: { subject_id: eq('subject_id'), chapter_id: eq('chapter_id') },
    title: (r) => `deck "${r.name}"`,
  },
  cards: {
    table: 'cards', scope: 'write:cards', order: 'created_at.asc',
    fields: { deck_id: { type: 'uuid', required: true }, front: { type: 'text', required: true, max: 4000 }, back: { type: 'text', max: 8000 } },
    filters: { deck_id: eq('deck_id'), state: eq('state') },
    title: (r) => `card "${String(r.front ?? '').slice(0, 50)}"`,
  },
  subjects: {
    table: 'subjects', scope: 'write:syllabus', order: 'sort.asc',
    fields: {
      name: { type: 'string', required: true, max: 120 }, color: { type: 'string', max: 9 }, icon: { type: 'string', max: 60 },
      exam_at: { type: 'date' }, sort: { type: 'int' },
    },
    filters: {},
    title: (r) => `subject "${r.name}"`,
  },
  chapters: {
    table: 'chapters', scope: 'write:syllabus', order: 'sort.asc',
    fields: { subject_id: { type: 'uuid', required: true }, number: { type: 'int' }, title: { type: 'string', max: 300 }, sort: { type: 'int' } },
    filters: { subject_id: eq('subject_id') },
    title: (r) => `chapter ${r.number ?? ''} ${r.title ?? ''}`.replace(/\s+/g, ' ').trim(),
  },
  topics: {
    table: 'topics', scope: 'write:syllabus', order: 'sort.asc',
    fields: {
      chapter_id: { type: 'uuid', required: true }, subject_id: { type: 'uuid' }, title: { type: 'string', required: true, max: 300 },
      status: { type: 'enum', values: ['not_started', 'learning', 'revised', 'mastered'] }, notes: { type: 'text', max: 4000 }, sort: { type: 'int' },
    },
    filters: { chapter_id: eq('chapter_id'), subject_id: eq('subject_id'), status: eq('status') },
    title: (r) => `topic "${r.title}"`,
  },
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isUuid = (v: unknown): v is string => typeof v === 'string' && UUID_RE.test(v);

function parseDate(v: unknown, tz = 'UTC', endOfDay = false): Date | null {
  if (typeof v !== 'string' || !v) return null;
  const day = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v);
  if (day) {
    const start = T.zoned(+day[1], +day[2], +day[3], 0, 0, tz);
    return endOfDay ? new Date(start.getTime() + 86400e3) : start;
  }
  // A local time without an offset is read in the user's zone.
  const local = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$/.exec(v);
  if (local) return T.zoned(+local[1], +local[2], +local[3], +local[4], +local[5], tz);
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d;
}

/** Checks a body against a resource's fields. Only known fields pass through. */
function validate(fields: Record<string, Field>, body: Row, partial: boolean, tz: string): { values: Row; errors: string[] } {
  const values: Row = {};
  const errors: string[] = [];
  for (const [name, f] of Object.entries(fields)) {
    if (!(name in body)) {
      if (f.required && !partial) errors.push(`${name} is required`);
      continue;
    }
    const v = body[name];
    if (v === null) {
      if (f.required) errors.push(`${name} can't be null`); else values[name] = null;
      continue;
    }
    switch (f.type) {
      case 'string': case 'text':
        if (typeof v !== 'string') { errors.push(`${name} must be a string`); break; }
        if (f.required && !v.trim()) { errors.push(`${name} can't be empty`); break; }
        values[name] = f.max ? v.slice(0, f.max) : v;
        break;
      case 'uuid':
        if (!isUuid(v)) errors.push(`${name} must be a uuid`); else values[name] = v.toLowerCase();
        break;
      case 'uuid[]':
        if (!Array.isArray(v) || !v.every(isUuid)) errors.push(`${name} must be an array of uuids`);
        else values[name] = v.map((x: string) => x.toLowerCase());
        break;
      case 'date': {
        const d = parseDate(v, tz);
        if (!d) errors.push(`${name} must be an ISO 8601 date-time`); else values[name] = d.toISOString();
        break;
      }
      case 'number': case 'int': {
        const n = typeof v === 'number' ? v : Number(v);
        if (!Number.isFinite(n)) { errors.push(`${name} must be a number`); break; }
        if (f.min !== undefined && n < f.min) { errors.push(`${name} must be at least ${f.min}`); break; }
        if (f.max !== undefined && n > f.max) { errors.push(`${name} must be at most ${f.max}`); break; }
        values[name] = f.type === 'int' ? Math.round(n) : n;
        break;
      }
      case 'bool':
        if (typeof v !== 'boolean') errors.push(`${name} must be true or false`); else values[name] = v;
        break;
      case 'enum':
        if (!f.values!.includes(v)) errors.push(`${name} must be one of ${f.values!.join(', ')}`); else values[name] = v;
        break;
      case 'hhmm':
        if (typeof v !== 'string' || !/^\d{2}:\d{2}$/.test(v)) errors.push(`${name} must be HH:MM`); else values[name] = v;
        break;
    }
  }
  return { values, errors };
}

// ───────────────────────────── entry ─────────────────────────────

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-lumen-key, content-type, apikey, x-client-info',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS } });
}

export async function handle(req: Request, ctx: Ctx): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  try {
    const url = new URL(req.url);
    const parts = url.pathname.split('/').filter(Boolean);
    const at = parts.indexOf('lumen-agent');
    const path = at >= 0 ? parts.slice(at + 1) : parts;
    const caller = await authenticate(req, ctx);
    const body = ['POST', 'PATCH', 'PUT'].includes(req.method) ? await readBody(req) : {};
    const api = new Api(ctx, caller, url.searchParams);
    const result = await api.route(req.method, path, body);
    if (api.notice && ctx.notify) ctx.notify(caller.userId, api.notice);
    return json(200, result);
  } catch (e) {
    if (e instanceof HttpError) return json(e.status, { error: e.message, ...(e.details ? { details: e.details } : {}) });
    if (e instanceof DbError) {
      const setup = e.code === 'PGRST106' || e.code === 'PGRST205' || e.code === '42P01';
      return json(setup ? 503 : 502, { error: setup ? 'Lumen tables are not set up: run the SQL migration and expose the lumen schema.' : e.message, code: e.code });
    }
    console.error(e);
    return json(500, { error: 'Something went wrong in Lumen.' });
  }
}

async function readBody(req: Request): Promise<Row> {
  const text = await req.text();
  if (!text.trim()) return {};
  try { return JSON.parse(text); } catch { throw new HttpError(400, 'The body must be JSON.'); }
}

async function authenticate(req: Request, ctx: Ctx): Promise<Caller> {
  const header = req.headers.get('authorization') ?? '';
  const token = (header.match(/^Bearer\s+(.+)$/i)?.[1] ?? req.headers.get('x-lumen-key') ?? '').trim();
  if (!token) throw new HttpError(401, 'Send your Lumen access key as "Authorization: Bearer <key>".');
  const hash = await sha256Hex(token);
  const rows = await ctx.db.select('agent_keys', { key_hash: `eq.${hash}`, select: 'id,user_id,name,scopes,revoked_at,last_used_at' });
  const k = rows[0];
  if (!k) throw new HttpError(401, 'That access key is not valid.');
  if (k.revoked_at) throw new HttpError(401, 'That access key has been revoked.');
  const now = (ctx.now ?? (() => new Date()))();
  if (!k.last_used_at || now.getTime() - new Date(k.last_used_at).getTime() > 60e3) {
    ctx.db.update('agent_keys', { id: `eq.${k.id}` }, { last_used_at: now.toISOString() }).catch(() => {});
  }
  return { keyId: k.id, userId: k.user_id, name: k.name, scopes: new Set(['read', ...(k.scopes ?? [])]) };
}

// ───────────────────────────── the API ─────────────────────────────

class Api {
  private db: Db;
  private now: Date;
  private prefsCache?: Row;
  /** What to push to the student after this request: a visible notice, or a silent one that just makes the app sync. */
  notice?: Notice;

  constructor(ctx: Ctx, private caller: Caller, private q: URLSearchParams) {
    this.db = ctx.db;
    this.now = (ctx.now ?? (() => new Date()))();
  }

  private need(scope: string) {
    if (!this.caller.scopes.has(scope)) throw new HttpError(403, `This key can't do that: it needs the "${scope}" scope.`);
  }

  private mine(extra: Query = {}): Query { return { user_id: `eq.${this.caller.userId}`, ...extra }; }

  async route(method: string, path: string[], body: Row): Promise<unknown> {
    const [head, a, b] = path;
    if (!head) return this.about();
    switch (head) {
      case 'context': return this.only(method, 'GET', () => this.context());
      case 'plan': return this.only(method, 'POST', () => this.plan(body));
      case 'events': return this.only(method, 'GET', () => this.events());
      case 'activity': return this.only(method, 'GET', () => this.activity());
      case 'undo': return this.only(method, 'POST', () => this.undo(body));
      case 'proposals': return this.only(method, 'GET', () => this.proposals());
      case 'preferences': return this.only(method, 'GET', async () => ({ preferences: this.cleanPrefs(await this.prefs()) }));
      case 'availability': return this.only(method, 'GET', () => this.availability());
      case 'syllabus':
        if (!a) {
          if (method === 'GET') return this.syllabus();
          if (method === 'POST') return this.importSyllabus(body);
          throw new HttpError(405, 'Use GET or POST on /syllabus.');
        }
        if (!['subjects', 'chapters', 'topics'].includes(a)) throw new HttpError(404, 'Use /syllabus/subjects, /syllabus/chapters or /syllabus/topics.');
        return this.crud(method, RESOURCES[a], b, body);
      default: {
        const res = RESOURCES[head];
        if (!res) throw new HttpError(404, `No such endpoint: /${head}`);
        return this.crud(method, res, a, body);
      }
    }
  }

  private only<R>(method: string, allowed: string, fn: () => Promise<R>): Promise<R> {
    if (method !== allowed) throw new HttpError(405, `Use ${allowed} here.`);
    return fn();
  }

  private about() {
    return {
      name: 'Lumen agent API', version: VERSION, key: this.caller.name, scopes: [...this.caller.scopes],
      now: this.now.toISOString(),
      endpoints: ['GET /context', 'POST /plan', 'GET /events', 'GET /activity', 'POST /undo', 'GET /proposals', 'GET /preferences',
        'GET /availability', 'GET|POST|PATCH|DELETE /assignments', 'GET|POST|PATCH|DELETE /blocks', 'GET|POST|PATCH|DELETE /decks',
        'GET|POST|PATCH|DELETE /cards', 'GET|POST /syllabus', 'GET|POST|PATCH|DELETE /syllabus/{subjects|chapters|topics}'],
      docs: 'docs/INSTINCT.md and docs/openapi.yaml in the Lumen repository',
    };
  }

  // ── shared reads ──

  private async prefs(): Promise<Row> {
    if (this.prefsCache) return this.prefsCache;
    const rows = await this.db.select('preferences', this.mine({ deleted: 'is.false', select: '*', limit: '1' }));
    this.prefsCache = rows[0] ?? {
      timezone: 'UTC', max_hours_per_day: 4, block_minutes: 50, break_minutes: 10, no_study_days: [], earliest_time: '08:00',
      latest_time: '22:00', plan_mode: 'ask', new_cards_per_day: 20, daily_goal_minutes: 120, desired_retention: 0.9,
    };
    return this.prefsCache!;
  }

  private async tz(): Promise<string> { return T.validZone((await this.prefs()).timezone ?? 'UTC'); }

  private cleanPrefs(p: Row): Row {
    const { webhook_secret: _s, webhook_url: _u, user_id: _id, rev: _r, ...rest } = p;
    return rest;
  }

  private async range(defaultDays = 14): Promise<{ from: Date; to: Date }> {
    const tz = await this.tz();
    const from = parseDate(this.q.get('from'), tz) ?? T.startOfDay(this.now, tz);
    let to = parseDate(this.q.get('to'), tz, true) ?? new Date(from.getTime() + defaultDays * 86400e3);
    if (to.getTime() - from.getTime() > 62 * 86400e3) to = new Date(from.getTime() + 62 * 86400e3);
    if (to <= from) throw new HttpError(400, '"to" must be after "from".');
    return { from, to };
  }

  // ── /context ──

  private async context() {
    this.need('read');
    const tz = await this.tz();
    const prefs = await this.prefs();
    const { from, to } = await this.range();
    await this.db.rpc('sweep_missed', { p_user: this.caller.userId }).catch(() => {});
    const yearAgo = new Date(this.now.getTime() - 365 * 86400e3).toISOString();
    const twoWeeksAgo = new Date(this.now.getTime() - 14 * 86400e3);
    const [windows, busySlots, assignments, blocks, sessions, subjects, chapters, topics, decks, cards, reviewsToday, proposals] = await Promise.all([
      this.db.select('availability', this.mine({ deleted: 'is.false', select: '*', order: 'weekday.asc,start_time.asc' })),
      this.db.select('busy_slots', this.mine({ deleted: 'is.false', select: 'id,start_at,end_at,source,title,all_day', and: `(end_at.gt."${from.toISOString()}",start_at.lt."${to.toISOString()}")`, order: 'start_at.asc' })),
      this.db.select('assignments', this.mine({ deleted: 'is.false', select: '*', order: 'due_at.asc.nullslast' })),
      this.db.select('blocks', this.mine({ deleted: 'is.false', select: '*', and: `(end_at.gt."${new Date(Math.min(from.getTime(), twoWeeksAgo.getTime())).toISOString()}",start_at.lt."${to.toISOString()}")`, order: 'start_at.asc' })),
      this.db.select('focus_sessions', this.mine({ deleted: 'is.false', select: 'started_at,minutes,subject_id,assignment_id,block_id,outcome,note', started_at: `gte.${yearAgo}` })),
      this.db.select('subjects', this.mine({ deleted: 'is.false', select: 'id,name,color,exam_at,sort,created_by', order: 'sort.asc' })),
      this.db.select('chapters', this.mine({ deleted: 'is.false', select: 'id,subject_id,number,title,sort', order: 'sort.asc' })),
      this.db.select('topics', this.mine({ deleted: 'is.false', select: 'id,subject_id,chapter_id,title,status,sort', order: 'sort.asc' })),
      this.db.select('decks', this.mine({ deleted: 'is.false', select: 'id,name,subject_id,chapter_id' })),
      this.db.select('cards', this.mine({ deleted: 'is.false', select: 'deck_id,state,due_at' })),
      this.db.select('review_logs', this.mine({ deleted: 'is.false', select: 'state,reviewed_at', reviewed_at: `gte.${T.startOfDay(this.now, tz).toISOString()}` })),
      this.db.select('proposals', this.mine({ deleted: 'is.false', status: 'eq.pending', select: 'id,created_at,reasoning,blocks,range_start,range_end', order: 'created_at.desc', limit: '1' })),
    ]);

    const subjectName = new Map(subjects.map((s) => [s.id, s.name]));
    const chapterTitle = new Map(chapters.map((c) => [c.id, c.number != null ? `Ch ${c.number}${c.title ? ` ${c.title}` : ''}` : c.title]));
    const loggedBy = new Map<string, number>();
    const loggedByBlock = new Map<string, number>();
    for (const s of sessions) {
      if (s.assignment_id) loggedBy.set(s.assignment_id, (loggedBy.get(s.assignment_id) ?? 0) + (s.minutes ?? 0));
      if (s.block_id) loggedByBlock.set(s.block_id, (loggedByBlock.get(s.block_id) ?? 0) + (s.minutes ?? 0));
    }
    const plannedBy = new Map<string, number>();
    for (const b of blocks) {
      if (b.assignment_id && b.status === 'planned' && new Date(b.end_at) > this.now) {
        plannedBy.set(b.assignment_id, (plannedBy.get(b.assignment_id) ?? 0) + minutesBetween(b.start_at, b.end_at));
      }
    }
    const weekAgo = this.now.getTime() - 7 * 86400e3;
    const assignmentOut = assignments
      .filter((a) => a.status !== 'done' || new Date(a.completed_at ?? a.updated_at).getTime() > weekAgo)
      .map((a) => {
        const est = Math.round(Number(a.estimated_hours ?? 1) * 60);
        const logged = loggedBy.get(a.id) ?? 0;
        return {
          id: a.id, title: a.title, kind: a.kind, subject_id: a.subject_id, subject: subjectName.get(a.subject_id) ?? null,
          chapter_ids: a.chapter_ids ?? [], chapters: (a.chapter_ids ?? []).map((id: string) => chapterTitle.get(id)).filter(Boolean),
          due_at: a.due_at, due_local: a.due_at ? T.isoLocal(new Date(a.due_at), tz) : null,
          overdue: a.status !== 'done' && !!a.due_at && new Date(a.due_at) < this.now,
          estimated_hours: Number(a.estimated_hours), estimated_minutes: est, logged_minutes: logged,
          planned_minutes: plannedBy.get(a.id) ?? 0, remaining_minutes: a.status === 'done' ? 0 : Math.max(0, est - logged),
          progress: a.status === 'done' ? 1 : est > 0 ? Math.min(1, +(logged / est).toFixed(2)) : 0,
          priority: a.priority, status: a.status, notes: a.notes || null, created_by: a.created_by, reason: a.reason,
        };
      });

    const blockOut = (b: Row) => ({
      id: b.id, start_at: b.start_at, end_at: b.end_at, start_local: T.isoLocal(new Date(b.start_at), tz), end_local: T.isoLocal(new Date(b.end_at), tz),
      minutes: minutesBetween(b.start_at, b.end_at), kind: b.kind, status: b.status, subject_id: b.subject_id,
      subject: subjectName.get(b.subject_id) ?? null, assignment_id: b.assignment_id, deck_id: b.deck_id, chapter_ids: b.chapter_ids ?? [],
      goal: b.goal || null, outcome_note: b.outcome_note || null, logged_minutes: loggedByBlock.get(b.id) ?? 0,
      created_by: b.created_by, reason: b.reason,
    });
    const upcoming = blocks.filter((b) => new Date(b.end_at) > from).map(blockOut);
    const outcomes = blocks.filter((b) => new Date(b.end_at) <= this.now && new Date(b.start_at) >= twoWeeksAgo && b.status !== 'planned').map(blockOut).reverse();

    const free = this.freeSlots(prefs, windows, busySlots, blocks, from, to, tz);

    // Syllabus
    const syllabus = subjects.map((s) => {
      const st = topics.filter((t) => t.subject_id === s.id);
      return {
        id: s.id, name: s.name, exam_at: s.exam_at, progress: progressOf(st), topics: countBy(st),
        chapters: chapters.filter((c) => c.subject_id === s.id).map((c) => {
          const ct = topics.filter((t) => t.chapter_id === c.id);
          return { id: c.id, number: c.number, title: c.title, progress: progressOf(ct), topics: ct.map((t) => ({ id: t.id, title: t.title, status: t.status })) };
        }),
      };
    });

    // Cards
    const endOfToday = new Date(T.startOfDay(this.now, tz).getTime() + 86400e3);
    const introduced = reviewsToday.filter((r) => r.state === 'new').length;
    const newAllowance = Math.max(0, Number(prefs.new_cards_per_day ?? 20) - introduced);
    const byDeck = decks.map((d) => {
      const dc = cards.filter((c) => c.deck_id === d.id);
      return {
        deck_id: d.id, name: d.name, subject_id: d.subject_id, chapter_id: d.chapter_id, total: dc.length,
        due_now: dc.filter((c) => c.state !== 'new' && new Date(c.due_at) <= this.now).length,
        due_today: dc.filter((c) => c.state !== 'new' && new Date(c.due_at) <= endOfToday).length,
        new: dc.filter((c) => c.state === 'new').length,
      };
    });
    const totalNew = byDeck.reduce((n, d) => n + d.new, 0);

    // Focus stats
    const today = T.dayKey(this.now, tz);
    const perDay = new Map<string, number>();
    const bySubject7 = new Map<string, number>();
    let total7 = 0, total30 = 0;
    for (const s of sessions) {
      const t = new Date(s.started_at);
      const key = T.dayKey(t, tz);
      perDay.set(key, (perDay.get(key) ?? 0) + (s.minutes ?? 0));
      const age = this.now.getTime() - t.getTime();
      if (age <= 7 * 86400e3) {
        total7 += s.minutes ?? 0;
        const name = subjectName.get(s.subject_id) ?? 'Other';
        bySubject7.set(name, (bySubject7.get(name) ?? 0) + (s.minutes ?? 0));
      }
      if (age <= 30 * 86400e3) total30 += s.minutes ?? 0;
    }
    const last7: Record<string, number> = {};
    for (let i = 6; i >= 0; i--) {
      const k = T.dayKey(new Date(this.now.getTime() - i * 86400e3), tz);
      last7[k] = perDay.get(k) ?? 0;
    }
    let streak = 0;
    let probe = this.now.getTime();
    if (!perDay.get(today)) probe -= 86400e3;
    while (perDay.get(T.dayKey(new Date(probe), tz))) { streak++; probe -= 86400e3; }
    const pastPlanned = blocks.filter((b) => new Date(b.end_at) < this.now && new Date(b.start_at) >= twoWeeksAgo);
    const adherence = pastPlanned.length
      ? +(pastPlanned.reduce((n, b) => n + (b.status === 'done' ? 1 : b.status === 'partial' ? 0.5 : 0), 0) / pastPlanned.length).toFixed(2)
      : null;

    const pending = proposals[0];
    return {
      now: this.now.toISOString(), now_local: T.isoLocal(this.now, tz), timezone: tz,
      range: { from: from.toISOString(), to: to.toISOString(), from_local: T.isoLocal(from, tz), to_local: T.isoLocal(to, tz) },
      preferences: this.cleanPrefs(prefs),
      availability: {
        weekly: windows.map((w) => ({ id: w.id, weekday: w.weekday, start_time: w.start_time, end_time: w.end_time, kind: w.kind, label: w.label })),
        busy_slots: [...busySlots.map((b) => ({ start_at: b.start_at, end_at: b.end_at, start_local: T.isoLocal(new Date(b.start_at), tz), end_local: T.isoLocal(new Date(b.end_at), tz), source: b.source, title: b.title, all_day: b.all_day })),
          ...free.weeklyBusy],
        free_slots: free.slots,
        free_minutes_by_day: free.byDay,
      },
      subjects: subjects.map((s) => ({ id: s.id, name: s.name, exam_at: s.exam_at })),
      assignments: assignmentOut,
      blocks: { upcoming, recent_outcomes: outcomes },
      syllabus,
      cards: { due_now: byDeck.reduce((n, d) => n + d.due_now, 0), due_today: byDeck.reduce((n, d) => n + d.due_today, 0), new_available: Math.min(totalNew, newAllowance), by_deck: byDeck },
      focus: {
        minutes_today: perDay.get(today) ?? 0, daily_goal_minutes: prefs.daily_goal_minutes ?? 120, last_7_days: last7,
        minutes_7d: total7, minutes_30d: total30, by_subject_7d: Object.fromEntries(bySubject7), streak_days: streak, plan_adherence_14d: adherence,
      },
      pending_proposal: pending ? { id: pending.id, created_at: pending.created_at, blocks: (pending.blocks ?? []).length, reasoning: pending.reasoning } : null,
    };
  }

  /** Free study time: weekly free windows (or earliest–latest every day) minus weekly busy windows, busy slots and existing blocks. */
  private freeSlots(prefs: Row, windows: Row[], busy: Row[], blocks: Row[], from: Date, to: Date, tz: string) {
    const earliest = T.minutes(prefs.earliest_time, 8 * 60);
    const latest = T.minutes(prefs.latest_time, 22 * 60);
    const noStudy = new Set<number>((prefs.no_study_days ?? []).map(Number));
    const freeWindows = windows.filter((w) => w.kind === 'free');
    const slots: Row[] = [];
    const weeklyBusy: Row[] = [];
    const byDay: Record<string, number> = {};
    const taken: T.Span[] = [
      ...busy.map((b) => ({ start: +new Date(b.start_at), end: +new Date(b.end_at) })),
      ...blocks.filter((b) => b.status !== 'skipped' && b.status !== 'missed').map((b) => ({ start: +new Date(b.start_at), end: +new Date(b.end_at) })),
      { start: 0, end: Math.max(this.now.getTime(), from.getTime()) },
    ];
    for (const day of T.days(from, to, tz)) {
      const at = (m: number) => +T.zoned(day.y, day.m, day.d, Math.floor(m / 60), m % 60, tz);
      const dayBusy = windows.filter((w) => w.kind === 'busy' && w.weekday === day.weekday)
        .map((w) => ({ start: at(T.minutes(w.start_time)), end: at(T.minutes(w.end_time)), label: w.label }));
      for (const b of dayBusy) {
        if (b.end > from.getTime() && b.start < to.getTime()) {
          weeklyBusy.push({ start_at: new Date(b.start).toISOString(), end_at: new Date(b.end).toISOString(), start_local: T.isoLocal(new Date(b.start), tz), end_local: T.isoLocal(new Date(b.end), tz), source: 'weekly', title: b.label ?? null, all_day: false });
        }
      }
      byDay[day.key] = 0;
      if (noStudy.has(day.weekday)) continue;
      let base: T.Span[] = freeWindows.length
        ? freeWindows.filter((w) => w.weekday === day.weekday).map((w) => ({ start: at(Math.max(T.minutes(w.start_time), earliest)), end: at(Math.min(T.minutes(w.end_time), latest)) }))
        : [{ start: at(earliest), end: at(latest) }];
      base = T.subtract(base, [...dayBusy, ...taken, { start: 0, end: from.getTime() }, { start: to.getTime(), end: Number.MAX_SAFE_INTEGER }]);
      for (const s of base) {
        const mins = Math.round((s.end - s.start) / 60000);
        if (mins < 15) continue;
        byDay[day.key] += mins;
        slots.push({ start_at: new Date(s.start).toISOString(), end_at: new Date(s.end).toISOString(), start_local: T.isoLocal(new Date(s.start), tz), end_local: T.isoLocal(new Date(s.end), tz), minutes: mins });
      }
    }
    return { slots, weeklyBusy, byDay };
  }

  // ── /plan ──

  private async plan(body: Row) {
    this.need('write:plan');
    const tz = await this.tz();
    const prefs = await this.prefs();
    if (!Array.isArray(body.blocks)) throw new HttpError(400, 'Send {"blocks": [...]} — each with start_at, end_at and what it is for.');
    if (body.blocks.length > 300) throw new HttpError(400, 'At most 300 blocks per plan.');
    const replace = body.replace ?? 'instinct';
    if (!['instinct', 'all', 'none'].includes(replace)) throw new HttpError(400, 'replace must be instinct, all or none.');
    const mode = body.mode ?? prefs.plan_mode ?? 'ask';
    if (!['auto', 'ask'].includes(mode)) throw new HttpError(400, 'mode must be auto or ask.');
    const reasoning = typeof body.reasoning === 'string' ? body.reasoning.slice(0, 8000) : null;

    // Each block, checked like POST /blocks.
    const errors: Row[] = [];
    const drafts: Row[] = [];
    body.blocks.forEach((raw: Row, i: number) => {
      if (typeof raw !== 'object' || raw === null) { errors.push({ index: i, error: 'not an object' }); return; }
      const { values, errors: e } = validate(RESOURCES.blocks.fields, raw, false, tz);
      if (e.length) { errors.push({ index: i, error: e.join('; ') }); return; }
      if (new Date(values.end_at) <= new Date(values.start_at)) { errors.push({ index: i, error: 'end_at must be after start_at' }); return; }
      if (new Date(values.end_at).getTime() - new Date(values.start_at).getTime() > 6 * 3600e3) { errors.push({ index: i, error: 'a block can be at most 6 hours' }); return; }
      if (new Date(values.start_at).getTime() < this.now.getTime() - 5 * 60e3) { errors.push({ index: i, error: 'starts in the past' }); return; }
      drafts.push({ index: i, id: isUuid(raw.id) ? raw.id.toLowerCase() : crypto.randomUUID(), ...values, reason: typeof raw.reason === 'string' ? raw.reason.slice(0, 2000) : null });
    });
    if (errors.length) throw new HttpError(400, 'Some blocks are not valid.', { errors });

    const starts = drafts.map((d) => +new Date(d.start_at));
    const ends = drafts.map((d) => +new Date(d.end_at));
    const from = parseDate(body.from, tz) ?? (drafts.length ? T.startOfDay(new Date(Math.min(...starts)), tz) : T.startOfDay(this.now, tz));
    const to = parseDate(body.to, tz, true) ?? (drafts.length ? new Date(T.startOfDay(new Date(Math.max(...ends)), tz).getTime() + 86400e3) : new Date(from.getTime() + 86400e3));
    if (to <= from) throw new HttpError(400, '"to" must be after "from".');

    const [windows, busy, existing, assignments, decks] = await Promise.all([
      this.db.select('availability', this.mine({ deleted: 'is.false', select: '*' })),
      this.db.select('busy_slots', this.mine({ deleted: 'is.false', select: '*', and: `(end_at.gt."${new Date(from.getTime() - 86400e3).toISOString()}",start_at.lt."${new Date(to.getTime() + 86400e3).toISOString()}")` })),
      this.db.select('blocks', this.mine({ deleted: 'is.false', select: '*', and: `(end_at.gt."${new Date(from.getTime() - 86400e3).toISOString()}",start_at.lt."${new Date(to.getTime() + 86400e3).toISOString()}")` })),
      this.db.select('assignments', this.mine({ deleted: 'is.false', select: 'id,title,subject_id,chapter_ids,due_at,status' })),
      this.db.select('decks', this.mine({ deleted: 'is.false', select: 'id,subject_id' })),
    ]);
    const assignmentBy = new Map(assignments.map((a) => [a.id, a]));
    const deckBy = new Map(decks.map((d) => [d.id, d]));
    const replaceFrom = Math.max(from.getTime(), this.now.getTime());
    const replaced = (b: Row) => replace !== 'none' && b.status === 'planned' && +new Date(b.start_at) >= replaceFrom && +new Date(b.start_at) < to.getTime()
      && (replace === 'all' || b.created_by === 'instinct' || b.created_by === 'auto');
    const kept = existing.filter((b) => !replaced(b) && b.status !== 'skipped' && b.status !== 'missed');

    const earliest = T.minutes(prefs.earliest_time, 8 * 60);
    const latest = T.minutes(prefs.latest_time, 22 * 60);
    const noStudy = new Set<number>((prefs.no_study_days ?? []).map(Number));
    const freeWindows = windows.filter((w) => w.kind === 'free');
    const conflicts: Row[] = [];
    const warnings: string[] = [];
    const perDay = new Map<string, number>();
    for (const b of kept) {
      if (+new Date(b.start_at) >= from.getTime() && +new Date(b.start_at) < to.getTime()) {
        const k = T.dayKey(new Date(b.start_at), tz);
        perDay.set(k, (perDay.get(k) ?? 0) + minutesBetween(b.start_at, b.end_at));
      }
    }

    for (const d of drafts) {
      const span = { start: +new Date(d.start_at), end: +new Date(d.end_at) };
      const where = T.label(new Date(d.start_at), tz);
      if (d.assignment_id) {
        const a = assignmentBy.get(d.assignment_id);
        if (!a) { conflicts.push({ index: d.index, reason: 'unknown_assignment', message: `Block ${d.index} (${where}): no assignment ${d.assignment_id}` }); continue; }
        d.subject_id ??= a.subject_id ?? null;
        if (!d.chapter_ids?.length && a.chapter_ids?.length) d.chapter_ids = a.chapter_ids;
        if (a.due_at && span.start >= +new Date(a.due_at)) warnings.push(`Block ${d.index} (${where}) is after "${a.title}" is due.`);
        if (a.status === 'done') warnings.push(`Block ${d.index} (${where}) is for "${a.title}", which is already done.`);
      }
      if (d.deck_id) {
        const deck = deckBy.get(d.deck_id);
        if (!deck) { conflicts.push({ index: d.index, reason: 'unknown_deck', message: `Block ${d.index} (${where}): no deck ${d.deck_id}` }); continue; }
        d.subject_id ??= deck.subject_id ?? null;
      }
      const p = T.partsIn(new Date(d.start_at), tz);
      const dayBusy = windows.filter((w) => w.kind === 'busy' && w.weekday === p.weekday)
        .map((w) => ({ start: +T.zoned(p.y, p.m, p.d, Math.floor(T.minutes(w.start_time) / 60), T.minutes(w.start_time) % 60, tz), end: +T.zoned(p.y, p.m, p.d, Math.floor(T.minutes(w.end_time) / 60), T.minutes(w.end_time) % 60, tz), title: w.label ?? 'Weekly busy time' }));
      const hitBusy = busy.find((b) => T.overlaps(span, { start: +new Date(b.start_at), end: +new Date(b.end_at) }));
      const hitWeekly = dayBusy.find((b) => T.overlaps(span, b));
      const hitKept = kept.find((b) => T.overlaps(span, { start: +new Date(b.start_at), end: +new Date(b.end_at) }));
      const hitOther = drafts.find((o) => o !== d && T.overlaps(span, { start: +new Date(o.start_at), end: +new Date(o.end_at) }));
      if (hitBusy) conflicts.push({ index: d.index, reason: 'busy', message: `Block ${d.index} (${where}) overlaps a busy time ${T.label(new Date(hitBusy.start_at), tz)}–${T.label(new Date(hitBusy.end_at), tz).slice(-5)}${hitBusy.title ? ` (${hitBusy.title})` : ''}.` });
      else if (hitWeekly) conflicts.push({ index: d.index, reason: 'weekly_busy', message: `Block ${d.index} (${where}) overlaps "${hitWeekly.title}".` });
      else if (hitKept) conflicts.push({ index: d.index, reason: 'existing_block', message: `Block ${d.index} (${where}) overlaps an existing block (${hitKept.id}) that this plan keeps.` });
      else if (hitOther) conflicts.push({ index: d.index, reason: 'plan_overlap', message: `Block ${d.index} (${where}) overlaps block ${hitOther.index} in this plan.` });

      const startMin = p.h * 60 + p.mi;
      const endMin = startMin + Math.round((span.end - span.start) / 60000);
      if (noStudy.has(p.weekday)) warnings.push(`Block ${d.index} (${where}) is on a no-study day.`);
      if (startMin < earliest || endMin > latest) warnings.push(`Block ${d.index} (${where}) is outside ${prefs.earliest_time}–${prefs.latest_time}.`);
      if (freeWindows.length && !freeWindows.some((w) => w.weekday === p.weekday && T.minutes(w.start_time) <= startMin && T.minutes(w.end_time) >= endMin)) {
        warnings.push(`Block ${d.index} (${where}) is outside the free study windows.`);
      }
      const key = T.dayKey(new Date(d.start_at), tz);
      perDay.set(key, (perDay.get(key) ?? 0) + Math.round((span.end - span.start) / 60000));
    }
    const max = Math.round(Number(prefs.max_hours_per_day ?? 4) * 60);
    for (const [day, m] of perDay) if (m > max) warnings.push(`${day} has ${m} min of study planned, over the ${max} min daily maximum.`);

    let dropped: number[] = [];
    if (conflicts.length) {
      if (body.drop_conflicts === true) {
        dropped = [...new Set(conflicts.map((c) => c.index as number))];
        warnings.push(...conflicts.map((c) => `Dropped: ${c.message}`));
      } else {
        throw new HttpError(422, 'The plan clashes with busy times or other blocks. Fix those blocks, or send "drop_conflicts": true to leave them out.', { conflicts, warnings });
      }
    }
    const final = drafts.filter((d) => !dropped.includes(d.index)).map((d) => ({
      id: d.id, start_at: d.start_at, end_at: d.end_at, kind: d.kind ?? 'study', subject_id: d.subject_id ?? null, assignment_id: d.assignment_id ?? null,
      deck_id: d.deck_id ?? null, chapter_ids: d.chapter_ids ?? [], topic_ids: d.topic_ids ?? [], goal: d.goal ?? '', reason: d.reason,
    }));
    const removing = existing.filter(replaced).map((b) => b.id);
    const summary = { blocks: final.length, minutes: final.reduce((n, b) => n + minutesBetween(b.start_at, b.end_at), 0), replaces: removing.length, from: from.toISOString(), to: to.toISOString() };

    if (body.dry_run === true) return { status: 'valid', mode, ...summary, warnings, dropped };

    if (mode === 'auto') {
      const batch = crypto.randomUUID();
      const r = await this.db.rpc('apply_plan', {
        p_user: this.caller.userId, p_from: from.toISOString(), p_to: to.toISOString(), p_replace: replace, p_blocks: final,
        p_actor: 'instinct', p_reason: reasoning, p_batch: batch, p_proposal: null,
      });
      this.notice = { title: 'Instinct updated your plan', body: `${summary.blocks} block${summary.blocks === 1 ? '' : 's'} · ${Math.round(summary.minutes / 6) / 10} h${removing.length ? `, ${removing.length} moved or removed` : ''}${reasoning ? `. ${reasoning.slice(0, 120)}` : ''}`, open: 'lumen://planner', thread: 'plan' };
      return { status: 'applied', mode, batch_id: batch, created: r?.created ?? [], removed: r?.removed ?? [], ...summary, warnings, dropped };
    }

    // Ask first: one waiting proposal at a time; a newer one replaces it.
    await this.db.update('proposals', this.mine({ status: 'eq.pending', deleted: 'is.false' }), { status: 'superseded', updated_by: 'instinct', updated_at: this.now.toISOString() });
    const [proposal] = await this.db.insert('proposals', {
      user_id: this.caller.userId, range_start: from.toISOString(), range_end: to.toISOString(), replace, blocks: final, reasoning,
      warnings, status: 'pending', created_by: 'instinct', updated_by: 'instinct', reason: reasoning, updated_at: this.now.toISOString(),
    });
    await this.log(crypto.randomUUID(), [{ action: 'plan_proposed', entity: 'proposals', id: proposal.id, before: null, after: null,
      summary: `Suggested a plan: ${final.length} blocks, ${Math.round(summary.minutes / 6) / 10} h` }], reasoning);
    const days = new Set(final.map((b) => T.dayKey(new Date(b.start_at), tz))).size;
    this.notice = { title: 'Instinct has a new plan', body: `${final.length} block${final.length === 1 ? '' : 's'} · ${Math.round(summary.minutes / 6) / 10} h over ${days} day${days === 1 ? '' : 's'}. Tap to review.`, open: 'lumen://today', thread: 'plan' };
    return { status: 'proposed', mode, proposal_id: proposal.id, ...summary, warnings, dropped };
  }

  // ── /events ──

  private async events() {
    this.need('read');
    const tz = await this.tz();
    await this.db.rpc('sweep_missed', { p_user: this.caller.userId }).catch(() => {});
    const since = this.q.get('since') ?? this.q.get('cursor');
    const limit = clamp(Number(this.q.get('limit') ?? 100), 1, 500);
    const query: Query = this.mine({ select: 'id,at,type,entity,entity_id,actor,data', order: 'id.asc', limit: String(limit) });
    if (since && /^\d+$/.test(since)) query.id = `gt.${since}`;
    else if (since) {
      const d = parseDate(since, tz);
      if (!d) throw new HttpError(400, 'since must be an ISO date-time or an event id (cursor).');
      query.at = `gt.${d.toISOString()}`;
    } else query.at = `gt.${new Date(this.now.getTime() - 86400e3).toISOString()}`;
    const types = this.q.get('types')?.split(',').map((s) => s.trim()).filter(Boolean);
    const includeOwn = this.q.get('include_own') === 'true';
    const rows = await this.db.select('events', query);
    const events = rows
      .filter((e) => includeOwn || e.actor !== 'instinct')
      .filter((e) => !types?.length || types.some((t) => e.type === t || (t.endsWith('.*') && e.type.startsWith(t.slice(0, -1)))))
      .map((e) => ({ ...e, at_local: T.isoLocal(new Date(e.at), tz) }));
    const last = rows[rows.length - 1];
    return {
      events, cursor: last ? String(last.id) : (since && /^\d+$/.test(since) ? since : null),
      next_since: last ? last.at : null, has_more: rows.length === limit,
    };
  }

  private async activity() {
    this.need('read');
    const limit = clamp(Number(this.q.get('limit') ?? 50), 1, 500);
    const rows = await this.db.select('activity', this.mine({ deleted: 'is.false', select: 'id,at,batch_id,actor,action,entity,entity_id,summary,reason,undone_at', order: 'at.desc', limit: String(limit) }));
    return { activity: rows };
  }

  private async proposals() {
    this.need('read');
    const rows = await this.db.select('proposals', this.mine({ deleted: 'is.false', select: 'id,created_at,status,edited,feedback,decided_at,reasoning,range_start,range_end,blocks', order: 'created_at.desc', limit: '10' }));
    return { proposals: rows.map((p) => ({ ...p, blocks: (p.blocks ?? []).length })) };
  }

  private async availability() {
    this.need('read');
    const tz = await this.tz();
    const prefs = await this.prefs();
    const { from, to } = await this.range(7);
    const [windows, busy, blocks] = await Promise.all([
      this.db.select('availability', this.mine({ deleted: 'is.false', select: '*' })),
      this.db.select('busy_slots', this.mine({ deleted: 'is.false', select: '*', and: `(end_at.gt."${from.toISOString()}",start_at.lt."${to.toISOString()}")` })),
      this.db.select('blocks', this.mine({ deleted: 'is.false', select: '*', and: `(end_at.gt."${from.toISOString()}",start_at.lt."${to.toISOString()}")` })),
    ]);
    const free = this.freeSlots(prefs, windows, busy, blocks, from, to, tz);
    return { timezone: tz, weekly: windows, busy_slots: [...busy, ...free.weeklyBusy], free_slots: free.slots, free_minutes_by_day: free.byDay };
  }

  // ── /syllabus ──

  private async syllabus() {
    this.need('read');
    const [subjects, chapters, topics] = await Promise.all([
      this.db.select('subjects', this.mine({ deleted: 'is.false', select: '*', order: 'sort.asc' })),
      this.db.select('chapters', this.mine({ deleted: 'is.false', select: '*', order: 'sort.asc' })),
      this.db.select('topics', this.mine({ deleted: 'is.false', select: '*', order: 'sort.asc' })),
    ]);
    return {
      subjects: subjects.map((s) => ({
        ...strip(s), progress: progressOf(topics.filter((t) => t.subject_id === s.id)),
        chapters: chapters.filter((c) => c.subject_id === s.id).map((c) => ({
          ...strip(c), progress: progressOf(topics.filter((t) => t.chapter_id === c.id)),
          topics: topics.filter((t) => t.chapter_id === c.id).map(strip),
        })),
      })),
    };
  }

  /** {"subject": {...} or "subject_id", "chapters": [{"number", "title", "topics": ["…" or {title, status}]}]} */
  private async importSyllabus(body: Row) {
    this.need('write:syllabus');
    const tz = await this.tz();
    const batch = crypto.randomUUID();
    const entries: LogEntry[] = [];
    let subjectId: string | undefined = isUuid(body.subject_id) ? body.subject_id : undefined;
    if (!subjectId) {
      const { values, errors } = validate(RESOURCES.subjects.fields, body.subject ?? {}, false, tz);
      if (errors.length) throw new HttpError(400, `subject: ${errors.join('; ')}`);
      const existing = (await this.db.select('subjects', this.mine({ deleted: 'is.false', select: 'id,name' })))
        .find((x) => String(x.name).toLowerCase() === String(values.name).toLowerCase());
      if (existing) subjectId = existing.id;
      else {
        const [s] = await this.db.insert('subjects', this.stamp(values, body.reason));
        subjectId = s.id;
        entries.push({ action: 'created', entity: 'subjects', id: s.id, before: null, after: s, summary: `Added ${RESOURCES.subjects.title(s, tz)}` });
      }
    }
    if (!Array.isArray(body.chapters)) throw new HttpError(400, 'Send "chapters": [...].');
    const existingChapters = await this.db.select('chapters', this.mine({ deleted: 'is.false', subject_id: `eq.${subjectId}`, select: '*' }));
    let sort = existingChapters.length;
    for (const ch of body.chapters as Row[]) {
      let chapter = existingChapters.find((c) => (ch.number != null && c.number === ch.number) || (ch.title && c.title?.toLowerCase() === String(ch.title).toLowerCase()));
      if (!chapter) {
        const { values, errors } = validate(RESOURCES.chapters.fields, { ...ch, subject_id: subjectId, sort: ch.sort ?? (ch.number ?? sort) }, false, tz);
        if (errors.length) throw new HttpError(400, `chapter: ${errors.join('; ')}`);
        [chapter] = await this.db.insert('chapters', this.stamp(values, body.reason));
        entries.push({ action: 'created', entity: 'chapters', id: chapter.id, before: null, after: chapter, summary: `Added ${RESOURCES.chapters.title(chapter, tz)}` });
        sort++;
      }
      const topics = (Array.isArray(ch.topics) ? ch.topics : []).map((t: unknown, i: number) => typeof t === 'string' ? { title: t, sort: i } : { sort: i, ...(t as Row) });
      if (topics.length) {
        const rows = topics.map((t: Row) => {
          const { values, errors } = validate(RESOURCES.topics.fields, { ...t, chapter_id: chapter!.id, subject_id: subjectId }, false, tz);
          if (errors.length) throw new HttpError(400, `topic: ${errors.join('; ')}`);
          return this.stamp(values, body.reason);
        });
        const made = await this.db.insert('topics', rows);
        for (const t of made) entries.push({ action: 'created', entity: 'topics', id: t.id, before: null, after: t, summary: `Added ${RESOURCES.topics.title(t, tz)}` });
      }
    }
    await this.log(batch, entries, body.reason);
    this.notice = {};
    return { subject_id: subjectId, batch_id: batch, created: entries.length };
  }

  // ── generic CRUD ──

  private stamp(values: Row, reason: unknown): Row {
    return {
      ...values, user_id: this.caller.userId, created_by: 'instinct', updated_by: 'instinct',
      reason: typeof reason === 'string' ? reason.slice(0, 2000) : null, updated_at: this.now.toISOString(),
    };
  }

  private async crud(method: string, res: Resource, id: string | undefined, body: Row): Promise<unknown> {
    const tz = await this.tz();
    if (id && !isUuid(id)) throw new HttpError(400, 'The id in the path must be a uuid.');
    if (method === 'GET') {
      this.need('read');
      if (id) {
        const [row] = await this.db.select(res.table, this.mine({ id: `eq.${id}`, select: '*' }));
        if (!row) throw new HttpError(404, 'Not found.');
        return { [res.table.replace(/s$/, '')]: strip(row) };
      }
      const query: Query = this.mine({ select: '*', order: res.order, limit: String(clamp(Number(this.q.get('limit') ?? 500), 1, 2000)) });
      if (this.q.get('include_deleted') !== 'true') query.deleted = 'is.false';
      for (const [k, f] of Object.entries(res.filters)) {
        const v = this.q.get(k);
        if (v) { const [col, expr] = f(v); query[col] = expr; }
      }
      if (res.table === 'blocks') {
        const from = parseDate(this.q.get('from'), tz), to = parseDate(this.q.get('to'), tz, true);
        if (from && to) query.and = `(end_at.gt."${from.toISOString()}",start_at.lt."${to.toISOString()}")`;
        else if (from) query.end_at = `gt.${from.toISOString()}`;
        else if (to) query.start_at = `lt.${to.toISOString()}`;
      }
      if (res.table === 'cards' && this.q.get('due') === 'true') query.due_at = `lte.${this.now.toISOString()}`;
      const rows = await this.db.select(res.table, query);
      return { [res.table]: rows.map(strip) };
    }

    this.need(res.scope);
    const batch = crypto.randomUUID();
    const reason = body.reason;

    if (method === 'POST') {
      if (id) throw new HttpError(400, `POST to /${res.table} without an id; use PATCH /${res.table}/{id} to change one.`);
      const items: Row[] = Array.isArray(body) ? body : Array.isArray(body.items) ? body.items : [body];
      if (items.length > 500) throw new HttpError(400, 'At most 500 at a time.');
      const rows: Row[] = [];
      const errors: Row[] = [];
      items.forEach((item, i) => {
        const { values, errors: e } = validate(res.fields, item, false, tz);
        if (e.length) { errors.push({ index: i, error: e.join('; ') }); return; }
        if (isUuid(item.id)) values.id = item.id.toLowerCase();
        rows.push(this.stamp(values, item.reason ?? reason));
      });
      if (errors.length) throw new HttpError(400, 'Some items are not valid.', { errors });
      await this.check(res, rows, tz, null);
      const made = await this.db.insert(res.table, rows);
      // Cards can come with their deck: POST /decks {"name": …, "cards": [{front, back}]}
      const entries: LogEntry[] = made.map((r) => ({ action: 'created', entity: res.table, id: r.id, before: null, after: r, summary: `Added ${res.title(r, tz)}` }));
      if (res.table === 'decks' && !Array.isArray(body) && Array.isArray(body.cards) && made.length === 1) {
        const cardRows = (body.cards as Row[]).map((c) => {
          const { values, errors: e } = validate(RESOURCES.cards.fields, { ...c, deck_id: made[0].id }, false, tz);
          if (e.length) throw new HttpError(400, `card: ${e.join('; ')}`);
          return this.stamp(values, reason);
        });
        if (cardRows.length) {
          const cards = await this.db.insert('cards', cardRows);
          entries.push(...cards.map((r) => ({ action: 'created', entity: 'cards', id: r.id, before: null, after: r, summary: `Added ${RESOURCES.cards.title(r, tz)}` })));
          made[0].cards = cards.map(strip);
        }
      }
      await this.log(batch, entries, reason);
      const out = made.map(strip);
      if (res.table === 'assignments') {
        const first = out[0];
        this.notice = out.length === 1
          ? { title: `Instinct added ${first.title}`, body: `${String(first.kind ?? 'homework').replace(/^./, (c: string) => c.toUpperCase())}${first.due_at ? ` · due ${T.label(new Date(first.due_at), tz)}` : ''}${typeof reason === 'string' ? ` · ${reason.slice(0, 80)}` : ''}`, open: `lumen://assignment?id=${first.id}`, thread: 'work' }
          : { title: `Instinct added ${out.length} assignments`, body: out.slice(0, 3).map((a) => a.title).join(', '), open: 'lumen://planner', thread: 'work' };
      } else if (res.table === 'decks' || res.table === 'cards') {
        const cards = res.table === 'cards' ? out.length : (out[0]?.cards?.length ?? 0);
        this.notice = cards ? { title: 'Instinct made flashcards', body: `${cards} new card${cards === 1 ? '' : 's'}${res.table === 'decks' ? ` in ${out[0].name}` : ''}.`, open: 'lumen://review', thread: 'cards' } : {};
      } else {
        this.notice = {};
      }
      return { batch_id: batch, [res.table]: out, ...(out.length === 1 ? { id: out[0].id } : {}) };
    }

    if (!id) throw new HttpError(400, `Put the id in the path: ${method} /${res.table}/{id}`);
    const [before] = await this.db.select(res.table, this.mine({ id: `eq.${id}`, deleted: 'is.false', select: '*' }));
    if (!before) throw new HttpError(404, 'Not found (or already deleted).');

    if (method === 'PATCH') {
      const { values, errors } = validate(res.fields, body, true, tz);
      if (errors.length) throw new HttpError(400, errors.join('; '));
      if (!Object.keys(values).length) throw new HttpError(400, `Nothing to change. Fields: ${Object.keys(res.fields).join(', ')}`);
      if (res.table === 'assignments' && values.status) values.completed_at = values.status === 'done' ? (before.completed_at ?? this.now.toISOString()) : null;
      await this.check(res, [{ ...before, ...values }], tz, before);
      const [after] = await this.db.update(res.table, this.mine({ id: `eq.${id}` }), { ...values, updated_by: 'instinct', reason: typeof reason === 'string' ? reason.slice(0, 2000) : before.reason, updated_at: this.now.toISOString() });
      await this.log(batch, [{ action: 'updated', entity: res.table, id, before, after, summary: `Changed ${res.title(after ?? before, tz)}` }], reason);
      this.notice = {};
      return { batch_id: batch, [res.table.replace(/s$/, '')]: strip(after ?? before) };
    }

    if (method === 'DELETE') {
      const entries: LogEntry[] = [];
      const gone = async (table: string, row: Row) => {
        const [after] = await this.db.update(table, this.mine({ id: `eq.${row.id}` }), { deleted: true, updated_by: 'instinct', reason: typeof reason === 'string' ? reason : row.reason, updated_at: this.now.toISOString() });
        entries.push({ action: 'deleted', entity: table, id: row.id, before: row, after, summary: `Removed ${(RESOURCES[table]?.title ?? (() => table))(row, tz)}` });
      };
      await gone(res.table, before);
      // A deck takes its cards with it, a chapter its topics.
      const children = res.table === 'decks' ? ['cards', 'deck_id'] : res.table === 'chapters' ? ['topics', 'chapter_id'] : null;
      if (children) {
        const kids = await this.db.select(children[0], this.mine({ [children[1]]: `eq.${id}`, deleted: 'is.false', select: '*' }));
        for (const k of kids) await gone(children[0], k);
      }
      await this.log(batch, entries, reason);
      this.notice = {};
      return { batch_id: batch, deleted: entries.map((e) => ({ entity: e.entity, id: e.id })) };
    }
    throw new HttpError(405, 'Use GET, POST, PATCH or DELETE.');
  }

  /** Checks that go beyond field types: times, busy clashes, parents that must exist. */
  private async check(res: Resource, rows: Row[], tz: string, before: Row | null) {
    if (res.table === 'blocks') {
      const allow = this.q.get('allow_overlap') === 'true';
      for (const r of rows) {
        if (new Date(r.end_at) <= new Date(r.start_at)) throw new HttpError(400, 'end_at must be after start_at.');
        const timeChanged = !before || before.start_at !== r.start_at || before.end_at !== r.end_at;
        if (allow || !timeChanged) continue;
        const span = { start: +new Date(r.start_at), end: +new Date(r.end_at) };
        const busy = await this.db.select('busy_slots', this.mine({ deleted: 'is.false', select: 'start_at,end_at,title', and: `(end_at.gt."${r.start_at}",start_at.lt."${r.end_at}")` }));
        const p = T.partsIn(new Date(r.start_at), tz);
        const weekly = (await this.db.select('availability', this.mine({ deleted: 'is.false', kind: 'eq.busy', weekday: `eq.${p.weekday}`, select: '*' })))
          .find((w) => T.overlaps(span, { start: +T.zoned(p.y, p.m, p.d, Math.floor(T.minutes(w.start_time) / 60), T.minutes(w.start_time) % 60, tz), end: +T.zoned(p.y, p.m, p.d, Math.floor(T.minutes(w.end_time) / 60), T.minutes(w.end_time) % 60, tz) }));
        if (busy.length || weekly) {
          const what = busy[0] ? `${T.label(new Date(busy[0].start_at), tz)}${busy[0].title ? ` (${busy[0].title})` : ''}` : weekly!.label ?? 'a weekly busy time';
          throw new HttpError(409, `That block overlaps a busy time: ${what}. Pick another time, or add ?allow_overlap=true.`);
        }
      }
    }
    if (res.table === 'cards') {
      const deckIds = [...new Set(rows.map((r) => r.deck_id))];
      const found = await this.db.select('decks', this.mine({ deleted: 'is.false', id: `in.(${deckIds.join(',')})`, select: 'id' }));
      if (found.length !== deckIds.length) throw new HttpError(400, 'deck_id must be one of your decks.');
    }
    if (res.table === 'topics') {
      for (const r of rows) {
        if (r.subject_id) continue;
        const [c] = await this.db.select('chapters', this.mine({ id: `eq.${r.chapter_id}`, select: 'subject_id' }));
        if (!c) throw new HttpError(400, 'chapter_id must be one of your chapters.');
        r.subject_id = c.subject_id;
      }
    }
  }

  // ── /undo ──

  private async undo(body: Row) {
    if (!isUuid(body.batch_id)) throw new HttpError(400, 'Send {"batch_id": "<uuid>"} from an earlier response or GET /activity.');
    const items = await this.db.select('activity', this.mine({ batch_id: `eq.${body.batch_id}`, undone_at: 'is.null', deleted: 'is.false', select: '*' }));
    if (!items.length) throw new HttpError(404, 'Nothing to undo in that batch.');
    for (const it of items) {
      const res = Object.values(RESOURCES).find((r) => r.table === it.entity);
      if (res) this.need(res.scope); else this.need('write:plan');
    }
    let restored = 0;
    for (const it of items) {
      if (!it.entity || !it.entity_id || it.entity === 'proposals') continue;
      const values: Row = it.before ? { ...strip(it.before), deleted: !!it.before.deleted } : { deleted: true };
      delete values.id;
      await this.db.update(it.entity, this.mine({ id: `eq.${it.entity_id}` }), { ...values, updated_by: 'instinct', reason: 'Undone by Instinct', updated_at: this.now.toISOString() });
      await this.db.update('activity', this.mine({ id: `eq.${it.id}` }), { undone_at: this.now.toISOString(), updated_by: 'instinct', updated_at: this.now.toISOString() });
      restored++;
    }
    this.notice = {};
    return { undone: restored };
  }

  // ── activity log ──

  private async log(batch: string, entries: LogEntry[], reason: unknown) {
    if (!entries.length) return;
    const r = typeof reason === 'string' ? reason.slice(0, 2000) : null;
    await this.db.insert('activity', entries.map((e) => ({
      user_id: this.caller.userId, at: this.now.toISOString(), batch_id: batch, actor: 'instinct', action: e.action, entity: e.entity,
      entity_id: e.id, summary: e.summary, before: e.before, after: e.after, created_by: 'instinct', updated_by: 'instinct', reason: r,
      updated_at: this.now.toISOString(),
    })));
  }
}

interface LogEntry { action: string; entity: string; id: string; before: Row | null; after: Row | null; summary: string }

// ───────────────────────────── helpers ─────────────────────────────

function minutesBetween(a: string, b: string): number { return Math.round((+new Date(b) - +new Date(a)) / 60000); }
function clamp(n: number, lo: number, hi: number): number { return Number.isFinite(n) ? Math.min(hi, Math.max(lo, Math.round(n))) : lo; }

/** Drops columns an assistant has no use for. */
function strip(r: Row): Row {
  const { user_id: _u, rev: _r, ...rest } = r;
  return rest;
}

const WEIGHT: Record<string, number> = { not_started: 0, learning: 1 / 3, revised: 2 / 3, mastered: 1 };
function progressOf(topics: Row[]): number {
  if (!topics.length) return 0;
  return +(topics.reduce((n, t) => n + (WEIGHT[t.status] ?? 0), 0) / topics.length).toFixed(2);
}
function countBy(topics: Row[]): Record<string, number> {
  const out: Record<string, number> = { not_started: 0, learning: 0, revised: 0, mastered: 0 };
  for (const t of topics) out[t.status] = (out[t.status] ?? 0) + 1;
  return out;
}

export { SCOPES };
