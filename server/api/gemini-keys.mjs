// Extra Gemini API keys, used in turn when one hits a rate limit or runs out of quota (admin only).
// Key values go in once and never come back out: listing shows labels and status only.
//   GET    /api/gemini-keys                      {keys: [{id, label, status: active|cooling|rejected, reason, until}], active, total}
//   POST   /api/gemini-keys {"key": "AIza…", "label": "Spare 1"}   adds a key (checked with Google first)
//   PATCH  /api/gemini-keys {"id": "gk-…", "reset": true}         clears its cooldown
//   DELETE /api/gemini-keys {"id": "gk-…"}                        removes it
// Needs GEMINI_KEYS_SECRET in Vercel to store keys (encrypted). GEMINI_API_KEY is always in the pool too.
import { kv, cors, ready, body } from './lifeos.mjs';
import { gate, audit } from './_auth.mjs';
import { MODEL } from './_ai.mjs';
import { describe, addKey, removeKey, resetKey } from './_keys.mjs';

/** Asks Google whether a key works, without spending generate quota. Returns an error message or null. */
export const checkWith = fetcher => async value => {
  try {
    const r = await fetcher('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1', { headers: { 'x-goog-api-key': value }, signal: AbortSignal.timeout(10000) });
    if (r.ok) return null;
    const j = await r.json().catch(() => ({}));
    return r.status === 429 ? null : 'Google rejected this key: ' + (j.error?.message || 'error ' + r.status);
  } catch { return null } // can't reach Google right now; keep the key, it is checked on first use
};

export function createHandler({ store = kv, fetcher = fetch } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    if (cors(req, res, 'GET, POST, PATCH, DELETE') || !ready(res)) return;
    try {
      const caller = await gate(req, res, store, 'admin'); if (!caller) return;
      const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
      const model = /^[a-z0-9.\-]{3,60}$/.test(q.model || '') ? q.model : MODEL();
      if (req.method === 'GET') return res.status(200).json(await describe(store, model));
      const b = await body(req);
      if (req.method === 'POST') {
        const r = await addKey(store, { key: b.key, label: b.label }, caller.name, checkWith(fetcher));
        await audit(store, caller, [{ op: 'gemini-key.add', target: r.id, summary: r.label, ok: true }], req);
        return res.status(201).json({ added: r, ...(await describe(store, model)) });
      }
      if (!b.id) return res.status(400).json({ error: 'Send {"id": "<key id>"}' });
      if (req.method === 'PATCH') {
        await resetKey(store, String(b.id));
        return res.status(200).json(await describe(store, model));
      }
      if (req.method === 'DELETE') {
        const r = await removeKey(store, String(b.id));
        await audit(store, caller, [{ op: 'gemini-key.remove', target: r.id, summary: r.label, ok: true }], req);
        return res.status(200).json({ removed: r, ...(await describe(store, model)) });
      }
      return res.status(405).json({ error: 'Use GET, POST, PATCH or DELETE' });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
