// Gemini refreshes the Today screen on its own. Call every 1-2 hours with the header
// Authorization: Bearer <a write key> (cron-job.org: add it under Advanced > Headers), or use Vercel Cron, which sends CRON_SECRET.
// Keys in the URL are refused.
import { load, commit, kv, ready } from './lifeos.mjs';
import { gate } from './_auth.mjs';
import { snapshot, gemini, expand, SYSTEM, PULSE_PROMPT, MODEL, fallbackNote } from './_ai.mjs';

const ALLOWED = new Set(['task.add', 'task.update', 'board.add', 'board.move', 'board.update', 'inbox.priority', 'draft.email']);

export function createHandler({ store = kv, fetcher } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    if (!ready(res)) return;
    try {
      const caller = await gate(req, res, store, 'write', { cron: true }); if (!caller) return;
      const doc = await load(store);
      let g;
      try { g = await gemini(SYSTEM(doc.profile?.name), PULSE_PROMPT(snapshot(doc)), { fetcher }) }
      catch (e) { return res.status(e.status || 502).json({ error: 'Gemini could not refresh Today; nothing was changed. ' + e.message, attempts: e.attempts }) }
      const j = g.value;
      const ops = expand(doc, (Array.isArray(j.ops) ? j.ops : []).filter(o => o && ALLOWED.has(o.op)).slice(0, 6));
      const pulse = { at: Date.now(), by: 'Gemini', model: g.model, warning: fallbackNote(g, MODEL()), brief: j.brief || '', focus: j.focus || '', focusTarget: j.focusTarget && typeof j.focusTarget === 'object' ? { page: String(j.focusTarget.page || ''), id: j.focusTarget.id == null ? null : String(j.focusTarget.id) } : undefined, highlights: (Array.isArray(j.highlights) ? j.highlights : []).slice(0, 3), changes: ops.map(o => o.op === 'draft.email' ? 'Drafted “' + (o.subject || 'a reply') + '”' : (o.title ? o.op + ': ' + o.title : o.op)) };
      const r = await commit(store, [{ op: 'content.set', path: 'pulse', value: pulse }, ...ops].map(o => Object.assign({ by: 'Gemini' }, o)), caller, req);
      return res.status(200).json({ ok: true, pulse, results: r.results, batch: r.batch });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
