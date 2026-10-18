// The one address your iMessage assistant needs. Send a plain sentence; Gemini turns it into changes.
//   POST /api/say   {"text": "add revise Sound for tomorrow", "by": "Instinct"}   Authorization: Bearer <LIFEOS_AGENT_TOKEN>
//   GET  /api/say?text=what%27s%20on%20my%20board&key=<LIFEOS_AGENT_TOKEN>
// Reply: {"reply": "...", "changes": [...]}
import { who, load, commit, kv } from './lifeos.mjs';
import { snapshot, gemini, expand, SYSTEM } from './_ai.mjs';

export function createHandler({ store = kv } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    const url = new URL(req.url, 'http://x');
    const q = req.query || Object.fromEntries(url.searchParams);
    if (q.key && !req.headers.authorization) req.headers.authorization = 'Bearer ' + q.key;
    if (!who(req)) return res.status(401).json({ error: 'Missing or wrong key' });
    let b = req.body; if (typeof b === 'string') { try { b = JSON.parse(b) } catch { b = { text: b } } }
    const text = String((b && b.text) || q.text || '').trim().slice(0, 4000);
    const by = String((b && b.by) || q.by || 'Assistant').slice(0, 40);
    if (!text) return res.status(400).json({ error: 'Send {"text": "..."}' });
    try {
      const doc = await load(store);
      const j = await gemini(SYSTEM(doc.profile?.name), `Snapshot (JSON):\n${snapshot(doc)}\n\nMessage from ${by}: ${text}\n\nReply with only JSON: {"reply": string, "ops": [op, …]}. Use an empty ops list for questions.`);
      const ops = expand(doc, Array.isArray(j.ops) ? j.ops.slice(0, 30) : []);
      let results = [];
      if (ops.length) results = (await commit(store, ops, by)).results;
      return res.status(200).json({ reply: j.reply || (ops.length ? 'Done.' : ''), changes: ops.map((o, i) => ({ op: o.op, title: o.title || o.subject || o.text || o.id || '', ok: results[i]?.ok ?? false, error: results[i]?.error })) });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
