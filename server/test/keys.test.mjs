import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { memoryStore, call, setEnv } from './helpers.mjs';
setEnv();
process.env.GEMINI_KEYS_SECRET = 'test-secret-for-gemini-keys';
const { createHandler: gkeys } = await import('../api/gemini-keys.mjs');
const { createHandler: say } = await import('../api/say.mjs');
const { createHandler: ai } = await import('../api/ai.mjs');
const { createHandler: keys } = await import('../api/keys.mjs');
const { _forgetGoneModels } = await import('../api/_ai.mjs');
const { classify, nextQuotaReset, scrub, cleanKey } = await import('../api/_keys.mjs');

const OWNER = 'owner-secret';
const K1 = 'AIzaSyTESTKEY1aaaaaaaaaaaaaaaaaaaaaaaaa', K2 = 'AIzaSyTESTKEY2bbbbbbbbbbbbbbbbbbbbbbbbb';
let store;
beforeEach(() => { store = memoryStore(); _forgetGoneModels(); process.env.GEMINI_API_KEY = 'g'; process.env.GEMINI_KEYS_SECRET = 'test-secret-for-gemini-keys' });

/** Fake Google: `byKey` maps a key value to a response for generateContent; the models list always works. */
function google(byKey) {
  const calls = [];
  const f = async (url, init = {}) => {
    const key = init.headers?.['x-goog-api-key'];
    if (url.includes('/models?')) return { ok: true, status: 200, json: async () => ({ models: [] }) };
    calls.push(key);
    const p = byKey[key] ?? byKey['*'] ?? { status: 200, text: '{"reply":"ok","ops":[]}' };
    const status = p.status ?? 200;
    return { ok: status < 300, status, json: async () => p.json ?? { candidates: [{ content: { parts: [{ text: p.text }] } }] } };
  };
  f.calls = calls;
  return f;
}
const quota = (msg = 'You exceeded your current quota', details = []) => ({ status: 429, json: { error: { code: 429, status: 'RESOURCE_EXHAUSTED', message: msg, details } } });
const add = (key, label, fetcher = google({})) => call(gkeys({ store, fetcher }), { method: 'POST', key: OWNER, body: { key, label } });

test('adding keys: admin only, stored encrypted, listed without values', async () => {
  let r = await add(K1, 'Spare 1');
  assert.equal(r.statusCode, 201, JSON.stringify(r.body));
  assert.equal(r.body.total, 2); assert.equal(r.body.active, 2);
  assert.deepEqual(r.body.keys.map(k => k.label), ['GEMINI_API_KEY (Vercel)', 'Spare 1']);
  const everything = JSON.stringify([...store.kv]) + JSON.stringify(r.body) + JSON.stringify((await call(gkeys({ store }), { key: OWNER })).body);
  assert.ok(!everything.includes(K1), 'the key value never appears in storage or responses');
  assert.equal((await add(K1, 'again')).statusCode, 409, 'duplicates refused');
  assert.equal((await add('not a key', 'x')).statusCode, 400);
  const w = await call(keys({ store }), { method: 'POST', key: OWNER, body: { name: 'FRIDAY', scope: 'write' } });
  assert.equal((await call(gkeys({ store }), { key: w.body.key })).statusCode, 403, 'write keys cannot see the pool');
  // Google says no -> not added, and the message has no key in it
  const bad = async (url, init) => ({ ok: false, status: 400, json: async () => ({ error: { message: 'API key not valid: ' + init.headers['x-goog-api-key'] } }) });
  r = await add(K2, 'Bad', bad);
  assert.equal(r.statusCode, 400); assert.ok(!r.body.error.includes(K2)); assert.match(r.body.error, /\[key\]/);
});

test('without GEMINI_KEYS_SECRET extra keys cannot be stored', async () => {
  delete process.env.GEMINI_KEYS_SECRET;
  const r = await add(K1, 'Spare');
  assert.equal(r.statusCode, 503); assert.match(r.body.error, /GEMINI_KEYS_SECRET/);
});

test('a rate-limited key cools down and the next key answers; the cooldown is shown and skipped next time', async () => {
  await add(K1, 'Spare 1');
  const g = google({ g: quota('Quota exceeded for metric: generate_content_free_tier_requests, limit: 10 per minute', [{ '@type': 'type.googleapis.com/google.rpc.RetryInfo', retryDelay: '37s' }]) });
  let r = await call(say({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { text: 'hi' } });
  assert.equal(r.statusCode, 200, JSON.stringify(r.body)); assert.equal(r.body.reply, 'ok');
  assert.deepEqual(g.calls, ['g', K1]);
  const list = (await call(gkeys({ store }), { key: OWNER })).body;
  assert.equal(list.active, 1); assert.equal(list.keys[0].status, 'cooling'); assert.equal(list.keys[0].reason, 'rate limit');
  assert.ok(list.keys[0].until > Date.now() + 30e3 && list.keys[0].until < Date.now() + 40e3, 'uses Google\'s retryDelay');
  r = await call(say({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { text: 'again' } });
  assert.deepEqual(g.calls, ['g', K1, K1], 'the cooling key is skipped');
  // reset clears it
  await call(gkeys({ store }), { method: 'PATCH', key: OWNER, body: { id: 'env', reset: true } });
  assert.equal((await call(gkeys({ store }), { key: OWNER })).body.active, 2);
});

test('when every key is out of quota for a model, the next model is tried; a daily quota cools until the reset', async () => {
  await add(K1, 'Spare 1');
  const daily = quota('Quota exceeded for metric: generate_content_free_tier_requests, limit: 250 per day');
  const g = google({ g: daily, [K1]: daily });
  // only the fallback model answers: make the fake answer per model
  const f = async (url, init) => url.includes('gemini-2.5-flash') ? { ok: true, status: 200, json: async () => ({ candidates: [{ content: { parts: [{ text: '{"reply":"from 2.5","ops":[]}' }] } }] }) } : g(url, init);
  const r = await call(say({ store, fetcher: f }), { method: 'POST', key: OWNER, body: { text: 'hi' } });
  assert.equal(r.statusCode, 200, JSON.stringify(r.body)); assert.equal(r.body.model, 'gemini-2.5-flash');
  const list = (await call(gkeys({ store }), { key: OWNER })).body;
  assert.equal(list.active, 0); assert.ok(list.keys.every(k => k.reason === 'daily quota'));
  assert.ok(list.keys[0].until >= nextQuotaReset() - 1000);
  const other = (await call(gkeys({ store }), { url: '/api/gemini-keys?model=gemini-2.5-flash', key: OWNER })).body;
  assert.equal(other.active, 2, 'cooldowns are per model');
});

test('a rejected key is skipped; all keys rejected is a clear error without key values', async () => {
  await add(K1, 'Spare 1');
  const rej = { status: 400, json: { error: { status: 'INVALID_ARGUMENT', message: 'API key not valid. Please pass a valid API key.', details: [{ reason: 'API_KEY_INVALID' }] } } };
  let g = google({ g: rej });
  let r = await call(say({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { text: 'hi' } });
  assert.equal(r.statusCode, 200); assert.deepEqual(g.calls, ['g', K1]);
  assert.equal((await call(gkeys({ store }), { key: OWNER })).body.keys[0].status, 'rejected');
  store = memoryStore(); await add(K1, 'Spare 1');
  g = google({ '*': rej });
  r = await call(say({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { text: 'hi' } });
  assert.equal(r.statusCode, 502); assert.match(r.body.error, /rejected the API keys/); assert.ok(!JSON.stringify(r.body).includes(K1));
});

test('removing a key; the Vercel key cannot be removed here', async () => {
  const a = (await add(K1, 'Spare 1')).body.added;
  assert.equal((await call(gkeys({ store }), { method: 'DELETE', key: OWNER, body: { id: 'env' } })).statusCode, 400);
  const r = await call(gkeys({ store }), { method: 'DELETE', key: OWNER, body: { id: a.id } });
  assert.equal(r.statusCode, 200); assert.equal(r.body.total, 1);
});

test('the /api/ai proxy rotates keys too and reports the pool size', async () => {
  await add(K1, 'Spare 1');
  const g = google({ g: quota() });
  const r = await call(ai({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { model: 'gemini-3.5-flash', body: { contents: [] } } });
  assert.equal(r.statusCode, 200); assert.deepEqual(g.calls, ['g', K1]); assert.equal(r.headers['X-LifeOS-Keys'], '1/2');
  delete process.env.GEMINI_API_KEY; store = memoryStore();
  const none = await call(ai({ store, fetcher: g }), { method: 'POST', key: OWNER, body: { model: 'gemini-3.5-flash', body: { contents: [] } } });
  assert.equal(none.statusCode, 503);
});

test('classify, scrub and the quota reset', () => {
  assert.equal(classify(429, {}).kind, 'quota');
  assert.equal(classify(400, { error: { message: 'API key expired. Please renew the API key.' } }).kind, 'rejected');
  assert.equal(classify(500, { error: { message: 'internal' } }), null);
  assert.equal(classify(404, { error: { message: 'model not found' } }), null);
  assert.equal(scrub('bad AIzaSyABCDEFGHIJKLMNOPQRSTUVWX123 here', []), 'bad [key] here');
  const t = nextQuotaReset(new Date('2026-10-19T12:00:00Z'));
  assert.equal(new Date(t).toISOString(), '2026-10-20T07:01:00.000Z'); // midnight PDT + 1 min
});

test('pasted keys: invisible characters, spaces and quotes are taken out; other key formats are accepted', async () => {
  assert.equal(cleanKey('\u200b ' + K1 + '\u00a0\n'), K1);
  assert.equal(cleanKey('“' + K1 + '”'), K1);
  let r = await add('\ufeff' + K1 + ' \u200b', 'Pasted');
  assert.equal(r.statusCode, 201, JSON.stringify(r.body));
  const other = 'AQ.Ab8RN6Kx_new-style.key0123456789abcdef';
  r = await add(other, 'New format');
  assert.equal(r.statusCode, 201, JSON.stringify(r.body));
  assert.equal((await add('short', 'x')).statusCode, 400);
});
