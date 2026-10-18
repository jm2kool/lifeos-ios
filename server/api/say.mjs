// The one address your assistant needs. Send a plain sentence; Gemini turns it into changes.
//   POST /api/say   {"text": "add revise Sound for tomorrow"}      Authorization: Bearer <your key>
//   ("question" or "message" work in place of "text".) Changes are recorded under the key's name.
// Reply: {"reply": "...", "changes": [{op, title, ok, error}], "model": "...", "batch": "..."}
// To add many items at once, use POST /api/import instead: it is exact, doesn't go through Gemini, and reports each item.
import { load, commit, kv, cors, ready, body } from './lifeos.mjs';
import { gate, can } from './_auth.mjs';
import { snapshot, gemini, expand, SYSTEM, MODEL, fallbackNote } from './_ai.mjs';

export const EXPECTED = {
  method: 'POST',
  url: '/api/say',
  headers: { Authorization: 'Bearer <your key>', 'Content-Type': 'application/json' },
  body: { text: 'string, required: what to do or ask, in plain English (max 4000 characters). "question" or "message" are accepted too.' },
  example: { text: 'add revise Sound for tomorrow' },
  bulk: 'To add many tasks, events or inbox items at once, POST them to /api/import.',
};
const MAX_OPS = 30;

export function createHandler({ store = kv, fetcher } = {}) {
  return async function handler(req, res) {
    if (cors(req, res, 'GET, POST') || !ready(res)) return;
    try {
      const caller = await gate(req, res, store, 'read'); if (!caller) return;
      const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
      let b = {};
      if (req.method === 'POST') { try { b = await body(req) } catch { return res.status(400).json({ error: 'Body must be JSON', expected: EXPECTED }) } }
      if (typeof b === 'string') b = { text: b };
      const field = ['text', 'question', 'message'].find(k => typeof b?.[k] === 'string' && b[k].trim());
      const raw = field ? b[field] : (q.text || q.question || '');
      if (!String(raw).trim()) return res.status(400).json({ error: 'Missing "text". Got ' + (b && typeof b === 'object' && Object.keys(b).length ? 'fields: ' + Object.keys(b).join(', ') : 'an empty body') + '.', expected: EXPECTED });
      if (String(raw).length > 4000) return res.status(413).json({ error: 'Text is longer than 4000 characters. Split it, or use /api/import for bulk adds.', expected: EXPECTED });
      const text = String(raw).trim();
      const doc = await load(store);
      let g;
      try {
        g = await gemini(SYSTEM(doc.profile?.name), `Snapshot (JSON):\n${snapshot(doc)}\n\nMessage from ${caller.name}: ${text}\n\nReply with only JSON: {"reply": string, "ops": [op, …]}. Use an empty ops list for questions. At most ${MAX_OPS} ops.`, { fetcher });
      } catch (e) {
        return res.status(e.status || 502).json({ error: 'Gemini could not answer, so nothing was changed. ' + e.message, attempts: e.attempts, retry: true });
      }
      const j = g.value;
      const asked = Array.isArray(j.ops) ? j.ops : [];
      const ops = expand(doc, asked.slice(0, MAX_OPS));
      const warnings = [];
      const fb = fallbackNote(g, MODEL()); if (fb) warnings.push(fb);
      if (asked.length > MAX_OPS) warnings.push(`Gemini proposed ${asked.length} changes; only the first ${MAX_OPS} were applied. Use /api/import for bulk adds.`);
      if (!j.reply && !ops.length) return res.status(502).json({ error: `Gemini (${g.model}) answered with no reply and no changes, so nothing was changed. Try again or rephrase.`, model: g.model, warnings, retry: true });
      if (ops.length && !can(caller, 'write')) {
        return res.status(200).json({ reply: (j.reply || '') + `\n\n(Nothing was changed: the key "${caller.name}" is read-only.)`, changes: [], readOnly: true, model: g.model, warnings });
      }
      let results = [], batch;
      if (ops.length) ({ results, batch } = await commit(store, ops, caller, req));
      const changes = ops.map((o, i) => ({ op: o.op, title: o.title || o.subject || o.text || o.value?.title || o.id || '', ok: results[i]?.ok ?? false, error: results[i]?.error }));
      const failed = changes.filter(c => !c.ok).length;
      if (failed) warnings.push(`${failed} of ${changes.length} changes failed; see changes[].error.`);
      return res.status(failed ? 207 : 200).json({ reply: j.reply || 'Done.', changes, model: g.model, batch, warnings: warnings.length ? warnings : undefined });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
