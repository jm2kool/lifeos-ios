// Gemini refreshes the Today screen on its own. Call every 1-2 hours from a free cron service
// (for example cron-job.org) with Authorization: Bearer <LIFEOS_AGENT_TOKEN>, or ?key=..., or Vercel Cron (CRON_SECRET).
import { who, load, commit, kv } from './lifeos.mjs';
import { snapshot, gemini, expand, SYSTEM, PULSE_PROMPT } from './_ai.mjs';

const ALLOWED = new Set(['task.add', 'task.update', 'board.add', 'board.move', 'board.update', 'inbox.priority', 'draft.email']);

export function createHandler({ store = kv } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
    if (q.key && !req.headers.authorization) req.headers.authorization = 'Bearer ' + q.key;
    const cron = process.env.CRON_SECRET && req.headers.authorization === 'Bearer ' + process.env.CRON_SECRET;
    if (!cron && !who(req)) return res.status(401).json({ error: 'Missing or wrong key' });
    try {
      const doc = await load(store);
      const j = await gemini(SYSTEM(doc.profile?.name), PULSE_PROMPT(snapshot(doc)));
      const ops = expand(doc, (Array.isArray(j.ops) ? j.ops : []).filter(o => o && ALLOWED.has(o.op)).slice(0, 6));
      const pulse = { at: Date.now(), by: 'Gemini', brief: j.brief || '', focus: j.focus || '', highlights: (j.highlights || []).slice(0, 3), changes: ops.map(o => o.op === 'draft.email' ? 'Drafted “' + (o.subject || 'a reply') + '”' : (o.title ? o.op + ': ' + o.title : o.op)) };
      const r = await commit(store, [{ op: 'content.set', path: 'pulse', value: pulse }, ...ops], 'Gemini');
      return res.status(200).json({ ok: true, pulse, results: r.results });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
