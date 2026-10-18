import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { memoryStore, call, setEnv, fakeGemini } from './helpers.mjs';
setEnv();
const { createHandler: lifeos, mutate } = await import('../api/lifeos.mjs');
const { createHandler: say } = await import('../api/say.mjs');
const { createHandler: imp } = await import('../api/import.mjs');
const { createHandler: keys } = await import('../api/keys.mjs');
const { createHandler: pulse } = await import('../api/pulse.mjs');
const { _forgetGoneModels } = await import('../api/_ai.mjs');

let store;
beforeEach(() => { store = memoryStore(); _forgetGoneModels() });
const OWNER = 'owner-secret';
async function newKey(name, scope) { const r = await call(keys({ store }), { method: 'POST', key: OWNER, body: { name, scope } }); assert.equal(r.statusCode, 201, JSON.stringify(r.body)); return r.body }

test('keys in a URL are refused everywhere, even next to a valid header', async () => {
  for (const [h, url] of [[lifeos, '/api/lifeos?key=owner-secret'], [say, '/api/say?key=owner-secret&text=hi'], [pulse, '/api/pulse?key=owner-secret'], [imp, '/api/import?token=x']]) {
    const r = await call(h({ store }), { method: 'GET', url, key: OWNER });
    assert.equal(r.statusCode, h === imp ? 405 : 400, url);
    if (h !== imp) assert.match(r.body.error, /URLs are refused/);
  }
});

test('per-caller keys: permissions, attribution, revoke, audit', async () => {
  const friday = await newKey('FRIDAY', 'write');
  const reader = await newKey('Viewer', 'read');
  assert.match(friday.key, /^lfo_/);
  const h = lifeos({ store });
  // read-only key cannot write
  let r = await call(h, { method: 'POST', key: reader.key, body: { ops: [{ op: 'task.add', title: 'x' }] } });
  assert.equal(r.statusCode, 403);
  // FRIDAY writes; a forged "by" is ignored
  r = await call(h, { method: 'POST', key: friday.key, body: { by: 'You', ops: [{ op: 'task.add', title: 'Revise', by: 'You' }] } });
  assert.equal(r.statusCode, 200);
  assert.equal(r.body.doc.state.log[0].by, 'FRIDAY'); assert.equal(r.body.doc.state.tasks[0].changedBy, 'FRIDAY');
  // the legacy key can't pretend to be FRIDAY either
  r = await call(h, { method: 'POST', key: 'agent-secret', body: { by: 'FRIDAY', ops: [{ op: 'task.add', title: 'y' }] } });
  assert.equal(r.body.doc.state.log[0].by, 'Assistant');
  // the owner may label its own changes (the app marks Gemini's), but not with another key's name
  r = await call(h, { method: 'POST', key: OWNER, body: { ops: [{ op: 'task.add', title: 'z', by: 'Gemini' }, { op: 'task.add', title: 'w', by: 'friday' }] } });
  assert.deepEqual(r.body.doc.state.log.slice(0, 2).map(e => e.by), ['You', 'Gemini']);
  // non-admins can't manage keys
  assert.equal((await call(keys({ store }), { key: friday.key })).statusCode, 403);
  // list never shows keys; revoke works
  const list = (await call(keys({ store }), { key: OWNER })).body.keys;
  assert.ok(list.some(k => k.name === 'FRIDAY')); assert.ok(!JSON.stringify(list).includes(friday.key));
  await call(keys({ store }), { method: 'DELETE', key: OWNER, body: { id: friday.record.id } });
  assert.equal((await call(h, { key: friday.key })).statusCode, 401);
  await call(keys({ store }), { method: 'DELETE', key: OWNER, body: { id: 'legacy-agent' } });
  assert.equal((await call(h, { key: 'agent-secret' })).statusCode, 401);
  // audit has who did what, including the denied attempt
  const audit = (await call(keys({ store }), { url: '/api/keys?view=audit', key: OWNER })).body.audit;
  assert.ok(audit.some(a => a.name === 'FRIDAY' && a.op === 'task.add' && a.ok));
  assert.ok(audit.some(a => a.name === 'Viewer' && a.op === 'denied'));
  assert.ok(audit.some(a => a.op === 'key.revoke'));
  // duplicate names refused
  assert.equal((await call(keys({ store }), { method: 'POST', key: OWNER, body: { name: 'assistant', scope: 'read' } })).statusCode, 409);
});

test('undo over HTTP: write keys undo their own changes, the owner undoes anything', async () => {
  const friday = await newKey('FRIDAY', 'write'), other = await newKey('Other', 'write');
  const h = lifeos({ store });
  let r = await call(h, { method: 'POST', key: friday.key, body: { ops: [{ op: 'task.add', title: 'a' }, { op: 'task.add', title: 'b' }] } });
  const batch = r.body.batch;
  assert.equal((await call(h, { method: 'POST', key: other.key, body: { undo: batch } })).statusCode, 403);
  r = await call(h, { method: 'POST', key: OWNER, body: { undo: batch } });
  assert.equal(r.statusCode, 200); assert.equal(r.body.doc.state.tasks.length, 0); assert.equal(r.body.undone.length, 2);
  assert.equal((await call(h, { method: 'POST', key: OWNER, body: { undo: batch } })).statusCode, 409);
});

test('concurrent writers never overwrite each other', async () => {
  const h = lifeos({ store });
  await call(h, { key: OWNER }); // seed
  // someone else saves between our read and our write
  store.beforeCas = async () => { await mutate(store, 'other', d => { d.state.tasks.push({ id: 'theirs', title: 'theirs' }); return { doc: d, changed: true } }) };
  const r = await call(h, { method: 'POST', key: OWNER, body: { ops: [{ op: 'task.add', id: 'mine', title: 'mine' }] } });
  assert.deepEqual(r.body.doc.state.tasks.map(t => t.id).sort(), ['mine', 'theirs']);
});

test('/api/import: 11 inbox items in one call, partial failures reported, retry safe', async () => {
  const friday = await newKey('FRIDAY', 'write');
  const h = imp({ store });
  const inbox = Array.from({ length: 11 }, (_, i) => ({ subject: 'Mail ' + i, from: 'x@y.z', body: 'b' }));
  inbox[4] = { from: 'x@y.z' }; // no subject
  let r = await call(h, { method: 'POST', key: friday.key, body: { inbox } });
  assert.equal(r.statusCode, 207);
  assert.equal(r.body.counts.inbox.added, 10); assert.equal(r.body.counts.inbox.failed, 1);
  assert.deepEqual(r.body.items.filter(i => i.status === 'failed').map(i => i.index), [4]);
  assert.match(r.body.items[4].error, /subject/);
  r = await call(h, { method: 'POST', key: friday.key, body: { inbox: inbox.filter((_, i) => i !== 4) } });
  assert.equal(r.statusCode, 200); assert.equal(r.body.counts.inbox.unchanged, 10); assert.equal(r.body.batch, undefined);
  // dry run changes nothing
  r = await call(h, { method: 'POST', key: friday.key, body: { tasks: [{ title: 'T' }], dryRun: true } });
  assert.match(r.body.summary, /^Would import 1 task/);
  const doc = (await call(lifeos({ store }), { key: OWNER })).body.doc;
  assert.equal(doc.state.tasks.length, 0); assert.equal(doc.content.inbox.length, 10);
  assert.equal(doc.state.log[0].by, 'FRIDAY'); assert.equal(doc.state.log[0].op, 'import');
  // read keys can't import
  const v = await newKey('Viewer', 'read');
  assert.equal((await call(h, { method: 'POST', key: v.key, body: { tasks: [{ title: 'x' }] } })).statusCode, 403);
  assert.equal((await call(h, { method: 'POST', key: friday.key, body: { stuff: [] } })).statusCode, 400);
});

test('/api/say accepts text, question or message and explains the shape otherwise', async () => {
  const g = fakeGemini({ '*': { reply: { reply: 'You have 0 tasks.', ops: [] } } });
  const h = say({ store, fetcher: g });
  for (const k of ['text', 'question', 'message']) {
    const r = await call(h, { method: 'POST', key: OWNER, body: { [k]: 'what is on my board?' } });
    assert.equal(r.statusCode, 200, k); assert.equal(r.body.reply, 'You have 0 tasks.');
  }
  const r = await call(h, { method: 'POST', key: OWNER, body: { prompt: 'hi' } });
  assert.equal(r.statusCode, 400); assert.match(r.body.error, /Missing "text"\. Got fields: prompt/); assert.ok(r.body.expected.body.text);
});

test('/api/say falls back when the model is gone and says so; total failure is an error, not an empty reply', async () => {
  process.env.GEMINI_MODEL = 'gemini-2.5-flash';
  const ok = { reply: { reply: 'Added.', ops: [{ op: 'task.add', title: 'Revise Sound' }] } };
  let g = fakeGemini({ 'gemini-2.5-flash': { status: 400, json: { error: { message: 'gemini-2.5-flash is no longer available to new users' } } }, 'gemini-3.5-flash': ok });
  const friday = await newKey('FRIDAY', 'write');
  let r = await call(say({ store, fetcher: g }), { method: 'POST', key: friday.key, body: { text: 'add revise sound' } });
  assert.equal(r.statusCode, 200); assert.equal(r.body.model, 'gemini-3.5-flash');
  assert.match(r.body.warnings[0], /gemini-2.5-flash failed \(gemini-2.5-flash is no longer available.*answered with gemini-3.5-flash/);
  assert.equal(r.body.changes[0].ok, true);
  // the dead model is skipped next time
  r = await call(say({ store, fetcher: g }), { method: 'POST', key: friday.key, body: { text: 'again' } });
  assert.deepEqual(g.calls, ['gemini-2.5-flash', 'gemini-3.5-flash', 'gemini-3.5-flash']);
  // empty replies and non-JSON fall through to the next model, and if all fail it's a 502 with the reasons
  g = fakeGemini({ '*': { text: '' } });
  r = await call(say({ store, fetcher: g }), { method: 'POST', key: friday.key, body: { text: 'hi' } });
  assert.equal(r.statusCode, 502); assert.match(r.body.error, /nothing was changed/); assert.ok(r.body.attempts.length >= 2); assert.equal(r.body.retry, true);
  // a reply with neither text nor ops is also surfaced
  g = fakeGemini({ '*': { reply: { ops: [] } } });
  r = await call(say({ store, fetcher: g }), { method: 'POST', key: friday.key, body: { text: 'hi' } });
  assert.equal(r.statusCode, 502); assert.match(r.body.error, /no reply and no changes/);
  delete process.env.GEMINI_MODEL;
});

test('/api/say with a read-only key answers but changes nothing', async () => {
  const v = await newKey('Viewer', 'read');
  const g = fakeGemini({ '*': { reply: { reply: 'Added.', ops: [{ op: 'task.add', title: 'x' }] } } });
  const r = await call(say({ store, fetcher: g }), { method: 'POST', key: v.key, body: { text: 'add x' } });
  assert.equal(r.body.readOnly, true);
  assert.equal((await call(lifeos({ store }), { key: OWNER })).body.doc.state.tasks.length, 0);
});

test('undo can be undone, view=me and view=duplicates work, pulse accepts CRON_SECRET only in the header', async () => {
  const h = lifeos({ store });
  let r = await call(h, { method: 'POST', key: OWNER, body: { ops: [{ op: 'content.upsert', path: 'events', value: { id: 'a', title: 'TALLENTEX - offline exam', start: '2026-10-25' } }, { op: 'content.upsert', path: 'events', value: { id: 'b', title: 'TALLENTEX exam (offline)', start: '2026-10-25T08:00:00+05:30' } }] } });
  r = await call(h, { method: 'POST', key: OWNER, body: { undo: r.body.batch } });
  assert.equal(r.body.doc.content.events.length, 0);
  r = await call(h, { method: 'POST', key: OWNER, body: { undo: r.body.doc.state.log[0].id } });
  assert.equal(r.body.doc.content.events.length, 2, 'redo restores both');
  const dups = (await call(h, { url: '/api/lifeos?view=duplicates', key: OWNER })).body.duplicates;
  assert.equal(dups.length, 1); assert.equal(dups[0].keep, 'b');
  assert.deepEqual((await call(h, { url: '/api/lifeos?view=me', key: 'agent-secret' })).body, { id: 'legacy-agent', name: 'Assistant', scope: 'write' });
  process.env.CRON_SECRET = 'cron-secret';
  const g = fakeGemini({ '*': { reply: { brief: 'Exam Sunday.', focus: 'Revise', highlights: [], ops: [] } } });
  r = await call(pulse({ store, fetcher: g }), { method: 'GET', key: 'cron-secret' });
  assert.equal(r.statusCode, 200); assert.equal(r.body.pulse.model, 'gemini-3.5-flash');
  assert.equal((await call(h, { key: 'cron-secret' })).statusCode, 401, 'cron secret only works for pulse');
  delete process.env.CRON_SECRET;
});

test('LIFEOS_ADMIN_KEYS promotes only the named key; PATCH changes access; whole-doc replace is guarded and undoable', async () => {
  const instinct = await newKey('Instinct', 'write'), other = await newKey('Other', 'write');
  const h = lifeos({ store });
  const doc = (await call(h, { key: OWNER })).body.doc;
  // before the grant: write key can't replace the whole doc
  assert.equal((await call(h, { method: 'PUT', key: instinct.key, body: { doc } })).statusCode, 403);
  process.env.LIFEOS_ADMIN_KEYS = 'instinct';
  try {
    assert.equal((await call(h, { url: '/api/lifeos?view=me', key: instinct.key })).body.scope, 'admin');
    assert.equal((await call(h, { url: '/api/lifeos?view=me', key: other.key })).body.scope, 'write', 'only Instinct is promoted');
    const listed = (await call(keys({ store }), { key: OWNER })).body.keys.find(k => k.name === 'Instinct');
    assert.equal(listed.scope, 'admin'); assert.equal(listed.viaSetting, 'LIFEOS_ADMIN_KEYS');
    // read, then a harmless replace with the current rev
    const cur = (await call(h, { key: instinct.key })).body.doc;
    const edited = JSON.parse(JSON.stringify(cur)); edited.state.board.push({ id: 'c1', t: 'Test card', c: 0 });
    let r = await call(h, { method: 'PUT', key: instinct.key, body: { doc: edited, rev: cur.rev } });
    assert.equal(r.statusCode, 200); assert.equal(r.body.doc.state.board[0].t, 'Test card');
    assert.equal(r.body.doc.state.log[0].op, 'doc.replace'); assert.equal(r.body.doc.state.log[0].by, 'Instinct');
    // a stale rev is refused instead of overwriting
    r = await call(h, { method: 'PUT', key: instinct.key, body: { doc: edited, rev: cur.rev } });
    assert.equal(r.statusCode, 409); assert.match(r.body.error, /Conflict/);
    // without a rev it still works (old clients)
    const logId = (await call(h, { method: 'PUT', key: instinct.key, body: { doc: cur } })).body.logId;
    // undo restores the version before that replace (the one with the test card)
    r = await call(h, { method: 'POST', key: OWNER, body: { undo: logId } });
    assert.equal(r.statusCode, 200); assert.equal(r.body.doc.state.board[0]?.t, 'Test card');
    assert.ok(r.body.doc.state.log.find(e => e.id === logId).undone);
    // ops still work for the admin key
    r = await call(h, { method: 'POST', key: instinct.key, body: { ops: [{ op: 'state.setKey', path: 'draftReviews', key: 'p|1|w1|approve', value: { action: 'approve' } }] } });
    assert.equal(r.statusCode, 200); assert.ok(r.body.doc.state.draftReviews['p|1|w1|approve']);
  } finally { delete process.env.LIFEOS_ADMIN_KEYS }
  // PATCH: owner changes Other to admin and back
  let r = await call(keys({ store }), { method: 'PATCH', key: OWNER, body: { id: other.record.id, scope: 'admin' } });
  assert.equal(r.statusCode, 200);
  assert.equal((await call(h, { url: '/api/lifeos?view=me', key: other.key })).body.scope, 'admin');
  assert.equal((await call(keys({ store }), { method: 'PATCH', key: instinct.key, body: { id: other.record.id, scope: 'read' } })).statusCode, 403, 'non-admin cannot change access');
  await call(keys({ store }), { method: 'PATCH', key: OWNER, body: { id: other.record.id, scope: 'read' } });
  assert.equal((await call(h, { url: '/api/lifeos?view=me', key: other.key })).body.scope, 'read');
});
