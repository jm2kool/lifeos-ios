// LifeOS sync + agent endpoint (Vercel Node function).
// The phone and your assistants all talk to this. Storage: Upstash Redis (Vercel Marketplace).
// Env: LIFEOS_TOKEN (owner key, used by the phone), LIFEOS_AGENT_TOKEN (legacy assistant key, optional),
//      KV_REST_API_URL + KV_REST_API_TOKEN (or UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN, or REDIS_URL).
// Keys go in the Authorization header only; see _auth.mjs for permissions.
//   GET  /api/lifeos                       whole doc (read)      ?view=summary|ops|duplicates|me, ?since=<rev>
//   POST /api/lifeos {"ops":[...]}         apply ops (write)     -> {doc, results, batch}
//   POST /api/lifeos {"undo": "<log id or batch id>" | [...]}   undo logged changes (write: own changes; admin: any)
//   PUT  /api/lifeos {"doc":{...}}         replace everything (admin)
import Core from './_core.mjs';
import { readFileSync } from 'node:fs';
import { gate, audit, reservedNames, attribution } from './_auth.mjs';

const KEY = 'lifeos:doc';
const env = process.env;
const kvUrl = () => env.KV_REST_API_URL || env.UPSTASH_REDIS_REST_URL;
const kvTok = () => env.KV_REST_API_TOKEN || env.UPSTASH_REDIS_REST_TOKEN;

// Works with either Upstash (REST) or a plain Redis URL (Vercel's Redis store).
let conn = null;
function redis() { if (!conn) conn = import('redis').then(async ({ createClient }) => { const c = createClient({ url: env.REDIS_URL, socket: { connectTimeout: 8000 } }); c.on('error', () => { }); await c.connect(); return c }).catch(e => { conn = null; throw e }); return conn }
export const hasStore = () => !!(env.REDIS_URL || (kvUrl() && kvTok()));
export async function kv(cmd, fetcher = fetch) {
  if (!kvUrl() && env.REDIS_URL) { const c = await redis(); return c.sendCommand(cmd.map(String)) }
  if (!hasStore()) throw Object.assign(Error('Storage is not connected yet: add a Redis store to this Vercel project'), { status: 503 });
  const r = await fetcher(kvUrl(), { method: 'POST', headers: { Authorization: 'Bearer ' + kvTok(), 'Content-Type': 'application/json' }, body: JSON.stringify(cmd.map(String)) });
  const j = await r.json().catch(() => ({})); if (!r.ok || j.error) throw Error(j.error || 'Storage error ' + r.status); return j.result;
}
function seedDoc() { try { return JSON.parse(readFileSync(new URL('./_seed.json', import.meta.url), 'utf8')) } catch { return Core.normalize({}) } } // optional private seed; not committed
export async function body(req) { if (req.body && typeof req.body === 'object') return req.body; try { if (typeof req.body === 'string') return JSON.parse(req.body || '{}'); let s = ''; for await (const c of req) s += c; return s ? JSON.parse(s) : {} } catch { throw Object.assign(Error('Body must be JSON'), { status: 400 }) } }

async function raw(store) {
  const r = await store(['GET', KEY]);
  if (r) return { doc: Core.normalize(JSON.parse(r)), rev: JSON.parse(r).rev };
  const d = Core.normalize(seedDoc()); d.rev = Math.max(1, d.rev || 1); d.updatedAt = new Date().toISOString(); d.updatedBy = 'seed';
  await store(['SET', KEY, JSON.stringify(d)]); return { doc: d, rev: d.rev };
}
export async function load(store = kv) { return (await raw(store)).doc }
export const save = (store, d) => store(['SET', KEY, JSON.stringify(d)]);

// Saves only if nobody else saved since we read (compares rev inside Redis), so simultaneous writers never overwrite each other.
const CAS = `local raw=redis.call('GET',KEYS[1]) local r='none' if raw then local ok,d=pcall(cjson.decode,raw) if ok and d.rev~=nil then r=tostring(d.rev) end end if r==ARGV[1] then redis.call('SET',KEYS[1],ARGV[2]) return 1 end return 0`;
const revText = r => r == null ? 'none' : String(r);
/** Runs fn(doc) -> {doc, changed, ...} and saves the result, retrying if someone else saved first. */
export async function mutate(store, by, fn) {
  for (let i = 0; i < 6; i++) {
    const { doc, rev } = await raw(store);
    const out = fn(doc);
    if (!out.changed) return Object.assign({ saved: false }, out);
    out.doc.rev = (doc.rev || 0) + 1; out.doc.updatedAt = new Date().toISOString(); out.doc.updatedBy = by;
    if (Number(await store(['EVAL', CAS, 1, KEY, revText(rev), JSON.stringify(out.doc)])) === 1) return Object.assign({ saved: true }, out);
    await new Promise(r => setTimeout(r, 20 + Math.random() * 80 * (i + 1)));
  }
  throw Object.assign(Error('LifeOS is busy with other changes; try again'), { status: 503 });
}

const auditRows = (ops, results, batch) => ops.map((o, i) => ({ op: o.op, by: o.by, target: results[i]?.id ?? o.id ?? o.value?.id ?? o.path, summary: String(o.title || o.subject || o.text || o.value?.title || o.path || '').slice(0, 120), ok: !!results[i]?.ok, error: results[i]?.error, batch }));

/** Applies ops as `caller`; an op's own `by` (already checked by the endpoint) wins over the caller's name. */
export async function commit(store, ops, caller, req) {
  const batch = Core.uid('batch');
  const list = ops.map(o => Object.assign({}, o, { by: o.by || caller.name, opId: o.opId || Core.uid('srv') }));
  const r = await mutate(store, list[0]?.by || caller.name, doc => { const x = Core.applyAll(doc, list, { batch, keyId: caller.id }); return { doc: x.doc, results: x.results, changed: x.results.some(y => y.ok && !y.skipped) } });
  await audit(store, caller, auditRows(list, r.results, batch).filter((x, i) => !r.results[i]?.skipped), req);
  return { doc: r.doc, results: r.results, batch };
}
export async function undoChanges(store, ids, caller, req) {
  const batch = Core.uid('batch');
  const r = await mutate(store, caller.name, doc => Object.assign(Core.undo(doc, ids, { by: caller.name, keyId: caller.id, batch, allow: e => caller.scope === 'admin' || e.key === caller.id }), { changed: true }));
  await audit(store, caller, [{ op: 'undo', target: r.undone.join(','), summary: 'Undid ' + r.undone.length + ' change(s)', ok: r.results.every(x => x.ok), batch }], req);
  return r;
}

export function summary(d) {
  const s = d.state, c = d.content, tz = d.profile.timezone || 'UTC';
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(new Date());
  const done = new Set((s.done || []).map(String)), idone = new Set((s.inboxDone || []).map(String));
  const ev = (c.events || []).filter(e => e.status !== 'superseded' && !/^(Paused|Superseded|Removed)/i.test(e.note || '')).filter(e => String(e.end || e.start) >= day).slice(0, 15);
  const L = [`LifeOS for ${d.profile.name || 'owner'} · ${day} (${tz}) · rev ${d.rev}`, '',
    'Open tasks:', ...(s.tasks || []).filter(t => !done.has(String(t.id))).map(t => `- [${t.id}] ${t.title}${t.due ? ' (due ' + t.due + ')' : ''}`), '',
    'Board:', ...(s.board || []).map(b => `- [${b.id}] ${['To do', 'Doing', 'Done'][b.c]}: ${b.t}${b.due ? ' (due ' + b.due + ')' : ''}`), '',
    'Upcoming events:', ...ev.map(e => `- ${e.start}: ${e.title}`), '',
    'Inbox to review:', ...(c.inbox || []).filter(m => !idone.has(String(m.id))).map(m => `- [${m.id}] ${m.t} (${m.f})`), '',
    'Draft reviews:', ...Object.values(s.draftReviews || {}).map(r => `- ${r.draftId} v${r.version} ${r.week}: ${r.action}${r.changes ? ' — ' + r.changes : ''}`), '',
    'Recent changes:', ...(s.log || []).slice(0, 10).map(l => `- ${new Date(l.at).toISOString()} ${l.by}: ${l.op} ${l.summary || ''}${l.undone ? ' (undone)' : ''}`)];
  return L.join('\n');
}

export function cors(req, res, methods) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Access-Control-Allow-Origin', '*'); res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type'); res.setHeader('Access-Control-Allow-Methods', methods + ', OPTIONS');
  if (req.method === 'OPTIONS') { res.status(204).end(); return true }
  return false;
}
export function ready(res) {
  if (!env.LIFEOS_TOKEN) { res.status(503).json({ error: 'Sync is not set up: add LIFEOS_TOKEN in Vercel' }); return false }
  if (!hasStore()) { res.status(503).json({ error: 'Sync is not set up: connect a Redis store in Vercel' }); return false }
  return true;
}

export function createHandler({ store = kv } = {}) {
  return async function handler(req, res) {
    if (cors(req, res, 'GET, POST, PUT') || !ready(res)) return;
    try {
      const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
      if (req.method === 'GET') {
        const caller = await gate(req, res, store, 'read'); if (!caller) return;
        if (q.view === 'me') return res.status(200).json({ id: caller.id, name: caller.name, scope: caller.scope });
        if (q.view === 'ops') return res.status(200).json({ ops: Core.OPS });
        const d = await load(store);
        if (q.view === 'summary') { res.setHeader('Content-Type', 'text/plain; charset=utf-8'); return res.status(200).send(summary(d)) }
        if (q.view === 'duplicates') return res.status(200).json({ duplicates: Core.duplicates(d) });
        if (q.since != null && Number(q.since) === d.rev) return res.status(200).json({ unchanged: true, rev: d.rev });
        return res.status(200).json({ doc: d });
      }
      if (req.method === 'POST') {
        const caller = await gate(req, res, store, 'write'); if (!caller) return;
        const b = await body(req);
        if (b.undo != null) { const r = await undoChanges(store, b.undo, caller, req); return res.status(r.results.every(x => x.ok) ? 200 : 207).json({ doc: r.doc, undone: r.undone, results: r.results }) }
        if (!Array.isArray(b.ops) || !b.ops.length || b.ops.length > 200) return res.status(400).json({ error: 'Send {"ops":[...]} with 1-200 ops, or {"undo":"<log id>"}. For bulk adds use POST /api/import.', expected: { ops: [{ op: 'task.add', title: 'Revise Sound', due: 'YYYY-MM-DD' }] } });
        if (JSON.stringify(b).length > 900000) return res.status(413).json({ error: 'Too large' });
        const reserved = await reservedNames(store);
        // each op may carry its own label (the app marks Gemini's changes), subject to the same rule as `by`
        const ops = b.ops.map(o => Object.assign({}, o, { by: attribution(caller, (o && o.by) || b.by, reserved) }));
        const r = await commit(store, ops, caller, req);
        return res.status(r.results.every(x => x.ok) ? 200 : 207).json({ doc: r.doc, results: r.results, batch: r.batch });
      }
      if (req.method === 'PUT') {
        const caller = await gate(req, res, store, 'admin'); if (!caller) return;
        const b = await body(req);
        if (!b.doc || typeof b.doc !== 'object' || !b.doc.content || !b.doc.state) return res.status(400).json({ error: 'Send {"doc":{...}} with content and state. To add to what is there instead, use POST /api/import.' });
        const by = attribution(caller, b.by, await reservedNames(store));
        const r = await mutate(store, by, () => { const d = Core.normalize(b.doc); d.state.log.unshift({ id: Core.uid('log'), op: 'doc.replace', by, key: caller.id, at: Date.now(), summary: 'Replaced everything' }); return { doc: d, changed: true } });
        await audit(store, caller, [{ op: 'doc.replace', by, ok: true }], req);
        return res.status(200).json({ doc: r.doc });
      }
      return res.status(405).json({ error: 'Use GET, POST or PUT' });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message || 'Server error' }) }
  };
}
export default createHandler();
