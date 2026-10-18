// Access keys (admin only). One key per caller; each change is recorded under the key's name.
//   GET    /api/keys                 list keys (never the keys themselves)
//   GET    /api/keys?view=audit&limit=100   who changed what, newest first
//   POST   /api/keys {"name": "FRIDAY", "scope": "write"}   -> {key, record}  (the key is shown once)
//   PATCH  /api/keys {"id": "key-…", "scope": "admin"}   change what a key may do
//   DELETE /api/keys {"id": "key-…"}  revoke (also works for "legacy-agent", the LIFEOS_AGENT_TOKEN key)
import { kv, cors, ready, body } from './lifeos.mjs';
import { gate, audit, readAudit, listKeys, createKey, revokeKey, updateKey } from './_auth.mjs';

export function createHandler({ store = kv } = {}) {
  return async function handler(req, res) {
    if (cors(req, res, 'GET, POST, PATCH, DELETE') || !ready(res)) return;
    try {
      const caller = await gate(req, res, store, 'admin'); if (!caller) return;
      const q = req.query || Object.fromEntries(new URL(req.url, 'http://x').searchParams);
      if (req.method === 'GET') {
        if (q.view === 'audit') return res.status(200).json({ audit: await readAudit(store, Number(q.limit) || 100) });
        return res.status(200).json({ keys: await listKeys(store) });
      }
      const b = await body(req);
      if (req.method === 'POST') {
        const r = await createKey(store, { name: b.name, scope: b.scope || 'write' }, caller.name);
        await audit(store, caller, [{ op: 'key.create', target: r.record.id, summary: `${r.record.name} (${r.record.scope})`, ok: true }], req);
        return res.status(201).json(r);
      }
      if (req.method === 'PATCH') {
        if (!b.id || !b.scope) return res.status(400).json({ error: 'Send {"id": "<key id>", "scope": "read"|"write"|"admin"}' });
        const r = await updateKey(store, String(b.id), String(b.scope), caller.name);
        await audit(store, caller, [{ op: 'key.scope', target: r.id, summary: `${r.name} → ${b.scope}`, ok: true }], req);
        return res.status(200).json({ key: r });
      }
      if (req.method === 'DELETE') {
        const id = b.id || q.id;
        if (!id) return res.status(400).json({ error: 'Send {"id": "<key id>"}' });
        const r = await revokeKey(store, String(id), caller.name);
        await audit(store, caller, [{ op: 'key.revoke', target: r.id, summary: r.name, ok: true }], req);
        return res.status(200).json({ revoked: r });
      }
      return res.status(405).json({ error: 'Use GET, POST, PATCH or DELETE' });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message }) }
  };
}
export default createHandler();
