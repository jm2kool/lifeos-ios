// Bulk import: add many tasks, events, inbox items, board cards or saved links in one exact call (no Gemini).
//   POST /api/import   Authorization: Bearer <write key>
//   {"inbox": [{subject, from, account?, body?, gist?, priority?, id?}, …], "events": [{title, start, end?, note?, id?}, …],
//    "tasks": [{title, due?, note?, id?}, …], "board": [{title, column?}], "saved": [{title, url?}], "dryRun": false}
//   or {"doc": <a whole LifeOS export>} to merge a backup into what is on the server.
// Same id = update. A likely duplicate (same day + similar title for events, same sender + subject for inbox,
// same title + due for tasks) is skipped, never deleted. Items without an id get one derived from their content,
// so sending the same batch twice is safe. The whole import is one change in the log and can be undone in one step.
// Reply (200, or 207 if any item failed): {summary, counts:{inbox:{added,updated,unchanged,duplicate,failed},…}, items:[{kind,index,id,status,error?,duplicateOf?}], batch, rev}
import Core from './_core.mjs';
import { kv, cors, ready, body, mutate, load } from './lifeos.mjs';
import { gate, audit, reservedNames, attribution } from './_auth.mjs';

const MAX_ITEMS = 2000;
const KINDS = ['tasks', 'events', 'inbox', 'board', 'saved'];
export const EXPECTED = { inbox: [{ subject: 'string', from: 'sender@example.com', body: 'optional', id: 'optional' }], events: [{ title: 'string', start: 'YYYY-MM-DD or ISO date-time', end: 'optional' }], tasks: [{ title: 'string', due: 'YYYY-MM-DD (optional)' }], dryRun: false };

export function createHandler({ store = kv } = {}) {
  return async function handler(req, res) {
    if (cors(req, res, 'POST') || !ready(res)) return;
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only', expected: EXPECTED });
    try {
      const caller = await gate(req, res, store, 'write'); if (!caller) return;
      const b = await body(req);
      const isDoc = b && b.doc && typeof b.doc === 'object';
      if (!isDoc && !KINDS.some(k => Array.isArray(b?.[k]))) return res.status(400).json({ error: 'Send lists named ' + KINDS.join(', ') + ', or {"doc": <export>}.', expected: EXPECTED });
      const n = isDoc ? 0 : KINDS.reduce((s, k) => s + (Array.isArray(b[k]) ? b[k].length : 0), 0);
      if (n > MAX_ITEMS) return res.status(413).json({ error: `At most ${MAX_ITEMS} items per import; split it.` });
      const input = isDoc ? { doc: b.doc } : Object.fromEntries(KINDS.filter(k => b[k] != null).map(k => [k, b[k]]));
      const by = attribution(caller, b.by, await reservedNames(store));
      const batch = Core.uid('batch');
      const dryRun = b.dryRun === true;
      let r;
      if (dryRun) r = Core.runImport(await load(store), input, { by, keyId: caller.id, batch, dryRun: true });
      else {
        r = await mutate(store, by, doc => Core.runImport(doc, input, { by, keyId: caller.id, batch }));
        if (r.changed) await audit(store, caller, [{ op: 'import', by, summary: r.summary, ok: true, batch }], req);
      }
      const failed = Object.values(r.counts).reduce((s, c) => s + c.failed, 0);
      return res.status(failed ? 207 : 200).json({
        ok: !failed, dryRun, summary: r.summary, counts: r.counts, items: r.items, kept: r.kept.length ? r.kept : undefined,
        batch: r.changed && !dryRun ? batch : undefined, rev: r.doc.rev, doc: b.returnDoc && !dryRun ? r.doc : undefined,
      });
    } catch (e) { return res.status(e.status || 500).json({ error: e.message, expected: e.status === 400 ? EXPECTED : undefined }) }
  };
}
export default createHandler();
