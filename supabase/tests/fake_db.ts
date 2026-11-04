// An in-memory stand-in for the PostgREST calls lumen-agent makes, for tests.
import type { Db, Query, Row } from '../functions/_shared/db.ts';

const DEFAULTS: Record<string, Row> = {
  assignments: { kind: 'homework', chapter_ids: [], estimated_hours: 1, priority: 'medium', status: 'todo', notes: null, completed_at: null },
  blocks: { kind: 'study', chapter_ids: [], topic_ids: [], status: 'planned', goal: null, outcome_note: null },
  cards: { state: 'new', back: '', stability: 0, difficulty: 0, reps: 0, lapses: 0 },
  topics: { status: 'not_started', sort: 0 },
  chapters: { sort: 0, title: '' },
  subjects: { sort: 0, color: '#7C8CFF', icon: 'book.closed' },
  proposals: { status: 'pending', edited: false },
};

function compare(a: unknown, b: string): number {
  if (typeof a === 'number') return a - Number(b);
  if (typeof a === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(a) && /^\d{4}-\d{2}-\d{2}T/.test(b)) return Date.parse(a) - Date.parse(b);
  return String(a).localeCompare(b);
}

function test(row: Row, col: string, expr: string): boolean {
  const dot = expr.indexOf('.');
  const op = expr.slice(0, dot);
  let val = expr.slice(dot + 1);
  if (val.startsWith('"') && val.endsWith('"')) val = val.slice(1, -1);
  const v = row[col];
  switch (op) {
    case 'eq': return String(v) === val;
    case 'neq': return String(v) !== val;
    case 'is': return val === 'null' ? v == null : val === 'true' ? v === true : val === 'false' ? v === false : false;
    case 'in': return val.slice(1, -1).split(',').includes(String(v));
    case 'gt': return v != null && compare(v, val) > 0;
    case 'gte': return v != null && compare(v, val) >= 0;
    case 'lt': return v != null && compare(v, val) < 0;
    case 'lte': return v != null && compare(v, val) <= 0;
    default: throw new Error(`fake db: unsupported op ${op}`);
  }
}

function matches(row: Row, q: Query): boolean {
  for (const [k, expr] of Object.entries(q)) {
    if (['select', 'order', 'limit'].includes(k)) continue;
    if (k === 'and') {
      const inner = expr.slice(1, -1);
      const parts = inner.match(/[a-z_]+\.[a-z]+\.("[^"]*"|[^,]*)/g) ?? [];
      for (const p of parts) {
        const i = p.indexOf('.');
        if (!test(row, p.slice(0, i), p.slice(i + 1))) return false;
      }
      continue;
    }
    if (!test(row, k, expr)) return false;
  }
  return true;
}

export class FakeDb implements Db {
  tables: Record<string, Row[]> = {};
  rpcs: { name: string; args: Row }[] = [];
  private seq = 1;
  constructor(public now: () => Date) {}

  t(name: string): Row[] { return (this.tables[name] ??= []); }

  seed(table: string, row: Row): Row {
    const full = this.fill(table, row);
    this.t(table).push(full);
    return full;
  }

  private fill(table: string, row: Row): Row {
    const now = this.now().toISOString();
    const base: Row = { id: crypto.randomUUID(), created_at: now, updated_at: now, deleted: false, created_by: 'me', updated_by: 'me', reason: null };
    if (table === 'events') { base.id = this.seq++; base.at = now; delete base.deleted; }
    if (table === 'cards') base.due_at = now;
    return { ...base, ...(DEFAULTS[table] ?? {}), ...row };
  }

  select(table: string, q: Query): Promise<Row[]> {
    let rows = this.t(table).filter((r) => matches(r, q));
    if (q.order) {
      const keys = q.order.split(',').map((s) => s.split('.'));
      rows = [...rows].sort((a, b) => {
        for (const [col, dir = 'asc'] of keys) {
          const av = a[col], bv = b[col];
          if (av === bv) continue;
          if (av == null) return 1;
          if (bv == null) return -1;
          const c = compare(av, String(bv));
          if (c !== 0) return dir === 'desc' ? -c : c;
        }
        return 0;
      });
    }
    if (q.limit) rows = rows.slice(0, Number(q.limit));
    return Promise.resolve(structuredClone(rows));
  }

  insert(table: string, rows: Row | Row[]): Promise<Row[]> {
    const list = (Array.isArray(rows) ? rows : [rows]).map((r) => this.fill(table, r));
    this.t(table).push(...list);
    return Promise.resolve(structuredClone(list));
  }

  update(table: string, q: Query, values: Row): Promise<Row[]> {
    const hit = this.t(table).filter((r) => matches(r, q));
    for (const r of hit) Object.assign(r, values);
    return Promise.resolve(structuredClone(hit));
  }

  rpc(name: string, args: Row): Promise<unknown> {
    this.rpcs.push({ name, args });
    if (name === 'apply_plan') {
      const removed: string[] = [];
      const created: string[] = [];
      const from = Math.max(Date.parse(args.p_from), this.now().getTime());
      for (const b of this.t('blocks')) {
        if (!b.deleted && b.user_id === args.p_user && b.status === 'planned' && Date.parse(b.start_at) >= from && Date.parse(b.start_at) < Date.parse(args.p_to)
          && (args.p_replace === 'all' || ['instinct', 'auto'].includes(b.created_by)) && args.p_replace !== 'none') {
          b.deleted = true; removed.push(b.id);
        }
      }
      for (const nb of args.p_blocks as Row[]) {
        const row = this.seed('blocks', { ...nb, user_id: args.p_user, created_by: 'instinct', updated_by: 'instinct' });
        created.push(row.id);
      }
      return Promise.resolve({ batch_id: args.p_batch, created, removed });
    }
    return Promise.resolve(null);
  }
}
