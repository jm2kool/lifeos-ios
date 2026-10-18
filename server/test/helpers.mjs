// In-memory stand-in for Redis plus Vercel-style req/res, for the tests.
export function memoryStore() {
  const kv = new Map(), hashes = new Map(), lists = new Map(), sets = new Map();
  const h = k => { if (!hashes.has(k)) hashes.set(k, new Map()); return hashes.get(k) };
  const l = k => { if (!lists.has(k)) lists.set(k, []); return lists.get(k) };
  const s = k => { if (!sets.has(k)) sets.set(k, new Set()); return sets.get(k) };
  const store = async cmd => {
    const [c, ...a] = cmd.map(String);
    switch (c.toUpperCase()) {
      case 'GET': return kv.get(a[0]) ?? null;
      case 'SET': kv.set(a[0], a[1]); return 'OK';
      case 'HGET': return h(a[0]).get(a[1]) ?? null;
      case 'HSET': h(a[0]).set(a[1], a[2]); return 1;
      case 'HGETALL': return [...h(a[0])].flat();
      case 'LPUSH': l(a[0]).unshift(...a.slice(1).reverse()); return l(a[0]).length;
      case 'LTRIM': lists.set(a[0], l(a[0]).slice(Number(a[1]), Number(a[2]) + 1)); return 'OK';
      case 'LRANGE': return l(a[0]).slice(Number(a[1]), Number(a[2]) + 1);
      case 'SADD': s(a[0]).add(a[1]); return 1;
      case 'SISMEMBER': return s(a[0]).has(a[1]) ? 1 : 0;
      case 'EVAL': { // the compare-and-set script in lifeos.mjs
        const [, , key, expect, value] = a; const raw = kv.get(key);
        let rev = 'none'; if (raw) { const r = JSON.parse(raw).rev; if (r != null) rev = String(r) }
        if (store.beforeCas) { const f = store.beforeCas; store.beforeCas = null; await f() }
        const now = kv.get(key); let cur = 'none'; if (now) { const r = JSON.parse(now).rev; if (r != null) cur = String(r) }
        if (cur === expect) { kv.set(key, value); return 1 } return 0;
      }
      default: throw Error('memoryStore: unsupported ' + c);
    }
  };
  store.kv = kv;
  return store;
}
export async function call(handler, { method = 'GET', url = '/', key, body, headers = {} } = {}) {
  const u = new URL(url, 'http://x');
  const req = { method, url, query: Object.fromEntries(u.searchParams), headers: { ...headers, ...(key ? { authorization: 'Bearer ' + key } : {}) }, body };
  const res = { statusCode: 200, headers: {}, body: undefined,
    setHeader(k, v) { this.headers[k] = v }, status(c) { this.statusCode = c; return this },
    json(v) { this.body = v; return this }, send(v) { this.body = v; return this }, end() { return this } };
  await handler(req, res);
  return res;
}
export function setEnv() {
  Object.assign(process.env, { LIFEOS_TOKEN: 'owner-secret', LIFEOS_AGENT_TOKEN: 'agent-secret', LIFEOS_AGENT_NAME: 'Assistant', KV_REST_API_URL: 'http://kv', KV_REST_API_TOKEN: 't', GEMINI_API_KEY: 'g' });
  delete process.env.GEMINI_MODEL;
}
/** Fake Gemini: `plan` maps model name -> {status, json} or a function. */
export function fakeGemini(plan) {
  const calls = [];
  const fetcher = async (url, init) => {
    const model = /models\/([^:]+):/.exec(url)[1]; calls.push(model);
    let p = plan[model] ?? plan['*'];
    if (typeof p === 'function') p = p(JSON.parse(init.body));
    if (!p) return { ok: false, status: 404, json: async () => ({ error: { message: `models/${model} is not found` } }) };
    if (p.throw) throw Object.assign(Error(p.throw), { name: p.throw === 'timed out' ? 'TimeoutError' : 'Error' });
    const status = p.status ?? 200;
    const json = p.json ?? { candidates: [{ content: { parts: [{ text: typeof p.text === 'string' ? p.text : JSON.stringify(p.reply) }] } }] };
    return { ok: status < 300, status, json: async () => json };
  };
  fetcher.calls = calls;
  return fetcher;
}
