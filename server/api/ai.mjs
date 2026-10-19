// Gemini proxy so your API keys stay on the server. Env: GEMINI_API_KEY (plus any keys added under /api/gemini-keys), LIFEOS_TOKEN.
// On a rate limit or quota error the next key in the pool is used; the response says how many keys are active.
import { kv } from './lifeos.mjs';
import { gate } from './_auth.mjs';
import { withKeys, usable } from './_keys.mjs';

export function createHandler({ store = kv, fetcher = fetch } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET') { // health check: GET /api/ai with Authorization: Bearer <key> -> is a Gemini key working, which models exist
      const q = req.query || {};
      if (!await gate(req, res, store, 'read')) return;
      const m = String(q.model || process.env.GEMINI_MODEL || 'gemini-3.5-flash'), out = {};
      const { keys, total } = await usable(store, m).catch(() => ({ keys: [], total: 0 }));
      out.keys = { active: keys.length, total };
      const key = keys[0]?.value || '';
      try { const t = Date.now(); const r = await fetcher('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': key }, signal: AbortSignal.timeout(15000) }); const j = await r.json().catch(() => ({})); out.list = { status: r.status, ms: Date.now() - t, error: j.error?.message, flash: (j.models || []).map(x => x.name.replace('models/', '')).filter(n => /flash/.test(n)) } } catch (e) { out.list = { error: String(e.message) } }
      try {
        const t = Date.now();
        const r = await withKeys(store, m, async value => { const x = await fetcher('https://generativelanguage.googleapis.com/v1beta/models/' + m + ':generateContent', { method: 'POST', headers: { 'x-goog-api-key': value, 'Content-Type': 'application/json' }, body: JSON.stringify({ contents: [{ role: 'user', parts: [{ text: 'Reply with the word ok' }] }], ...(/^gemini-3/.test(m) && q.think !== 'default' ? { generationConfig: { thinkingConfig: { thinkingLevel: 'low' } } } : {}) }), signal: AbortSignal.timeout(40000) }); return { status: x.status, json: await x.json().catch(() => ({})) } });
        out.generate = { model: m, status: r.status, ms: Date.now() - t, key: r.key, error: r.json?.error?.message, text: (r.json?.candidates?.[0]?.content?.parts || []).map(p => p.text || '').join('').slice(0, 80) };
      } catch (e) { out.generate = { model: m, error: String(e.message) } }
      return res.status(200).json(out);
    }
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!await gate(req, res, store, 'write')) return;
    const b = typeof req.body === 'object' ? req.body : JSON.parse(req.body || '{}');
    const model = String(b.model || 'gemini-3.5-flash');
    if (!/^[a-z0-9.\-]{3,60}$/.test(model)) return res.status(400).json({ error: 'Bad model name' });
    if (!b.body || JSON.stringify(b.body).length > 200000) return res.status(400).json({ error: 'Bad request' });
    try {
      const r = await withKeys(store, model, async value => {
        const x = await fetcher(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': value }, body: JSON.stringify(b.body), signal: AbortSignal.timeout(45000) });
        return { status: x.status, json: await x.json().catch(() => ({})) };
      });
      const { keys, total } = await usable(store, model).catch(() => ({ keys: [], total: 0 }));
      res.setHeader('X-LifeOS-Keys', `${keys.length}/${total}`);
      return res.status(r.status).json(r.json);
    } catch (e) { return res.status(e.status === 503 ? 503 : 504).json({ error: e.status === 503 ? e.message : 'Gemini did not respond' }) }
  };
}
export default createHandler();
