// A pool of Gemini API keys. On a rate limit or quota error the next key is used, and the exhausted one
// cools down. GEMINI_API_KEY from Vercel is always in the pool; more keys can be added (admin) through
// /api/gemini-keys. Added keys are encrypted (AES-256-GCM, secret GEMINI_KEYS_SECRET) before they reach
// Redis. Key values are never returned, logged or put in an error message; only a label is kept in the clear.
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';

const env = process.env;
const KEYS = 'lifeos:gemini:keys', COOL = 'lifeos:gemini:cool';
const sha = t => createHash('sha256').update(String(t)).digest('hex');
const parse = s => { try { return JSON.parse(s) } catch { return null } };
const pairs = r => { if (!r) return []; if (!Array.isArray(r)) return Object.entries(r); const o = []; for (let i = 0; i < r.length; i += 2) o.push([r[i], r[i + 1]]); return o };

export const canStore = () => String(env.GEMINI_KEYS_SECRET || '').length >= 16;
const secret = () => createHash('sha256').update('lifeos-gemini-keys:' + env.GEMINI_KEYS_SECRET).digest();
function seal(value) {
  const iv = randomBytes(12), c = createCipheriv('aes-256-gcm', secret(), iv);
  const data = Buffer.concat([c.update(value, 'utf8'), c.final()]);
  return Buffer.concat([iv, c.getAuthTag(), data]).toString('base64');
}
function open(sealed) {
  try {
    const b = Buffer.from(sealed, 'base64'), d = createDecipheriv('aes-256-gcm', secret(), b.subarray(0, 12));
    d.setAuthTag(b.subarray(12, 28));
    return Buffer.concat([d.update(b.subarray(28)), d.final()]).toString('utf8');
  } catch { return null }
}

// Only a rough check (any 20–200 ordinary characters); whether Google accepts the key is checked with Google.
const KEY_SHAPE = /^[\x21-\x7e]{20,200}$/;
/** Takes out what copying a key from a web page brings along: spaces, line breaks, zero-width and non-breaking spaces, quotes. */
export const cleanKey = raw => String(raw ?? '').replace(/[\s\u00a0\u200b-\u200d\u2060\ufeff"'`<>\u2018\u2019\u201c\u201d]/g, '');
const ENV = () => env.GEMINI_API_KEY ? [{ id: 'env', label: 'GEMINI_API_KEY (Vercel)', value: env.GEMINI_API_KEY, builtin: true }] : [];

async function records(store) {
  if (!store) return [];
  const rows = pairs(await store(['HGETALL', KEYS]).catch(() => null)).map(([, v]) => parse(v)).filter(Boolean);
  return rows.sort((a, b) => (a.addedAt || 0) - (b.addedAt || 0));
}
async function cooldowns(store) {
  if (!store) return {};
  return Object.fromEntries(pairs(await store(['HGETALL', COOL]).catch(() => null)).map(([k, v]) => [k, parse(v)]).filter(([, v]) => v));
}

/** Every usable key, Vercel's first, with values decrypted (in memory only). */
export async function pool(store) {
  const added = canStore() ? (await records(store)).map(r => ({ id: r.id, label: r.label, value: open(r.sealed) })).filter(k => k.value) : [];
  const seen = new Set(), out = [];
  for (const k of [...ENV(), ...added]) { const h = sha(k.value); if (!seen.has(h)) { seen.add(h); out.push(k) } }
  return out;
}

/** A cooldown is per key and model (Google's free quotas are per model), except a rejected key, which is out for every model. */
const coolFor = (cool, id, model, now = Date.now()) => {
  const all = cool[id + '|*'], one = cool[id + '|' + model];
  return [all, one].filter(c => c && c.until > now).sort((a, b) => b.until - a.until)[0] || null;
};

/** The keys to try for this model, in order, skipping ones that are cooling down. */
export async function usable(store, model) {
  const [keys, cool] = await Promise.all([pool(store), cooldowns(store)]);
  return { keys: keys.filter(k => !coolFor(cool, k.id, model)), total: keys.length, cool };
}

/** Next midnight in Google's quota time zone (America/Los_Angeles), when daily free quotas reset. */
export function nextQuotaReset(now = new Date()) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: 'America/Los_Angeles', hourCycle: 'h23', hour: 'numeric', minute: 'numeric', second: 'numeric' }).formatToParts(now).map(p => [p.type, p.value]));
  const passed = (Number(parts.hour) * 3600 + Number(parts.minute) * 60 + Number(parts.second)) * 1000;
  return now.getTime() - passed + 864e5 + 60e3; // a minute of slack
}

/** What a Gemini error means for the key that made the call: 'quota' (cool down), 'rejected' (bad key) or null. */
export function classify(status, j) {
  const msg = String(j?.error?.message || ''), st = String(j?.error?.status || ''), details = JSON.stringify(j?.error?.details || []);
  if (status === 429 || st === 'RESOURCE_EXHAUSTED' || /quota|rate limit|resource has been exhausted/i.test(msg)) {
    const daily = /per ?day|PerDay|daily/i.test(msg + details);
    const delay = /"retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s"/.exec(details);
    return { kind: 'quota', daily, ms: delay ? Math.ceil(Number(delay[1]) * 1000) : 60e3 };
  }
  // Only errors about the key itself: a 403 about a model you can't use is not the key's fault.
  if ((status === 400 || status === 401 || status === 403) && (/API_KEY_INVALID|API key (not valid|expired|was reported as leaked)|Requests from this API key are blocked/i.test(msg + details) || st === 'UNAUTHENTICATED'))
    return { kind: 'rejected' };
  return null;
}

/** Records that a key hit a limit (cooldown for this model) or was rejected (out for 6 hours, every model). */
export async function cool(store, id, model, c, now = Date.now()) {
  if (!store || !c) return;
  const field = c.kind === 'rejected' ? id + '|*' : id + '|' + model;
  const until = c.kind === 'rejected' ? now + 6 * 3600e3 : c.daily ? nextQuotaReset(new Date(now)) : now + Math.max(15e3, Math.min(c.ms, 3600e3));
  await store(['HSET', COOL, field, JSON.stringify({ until, reason: c.kind === 'rejected' ? 'rejected' : c.daily ? 'daily quota' : 'rate limit', model: c.kind === 'rejected' ? null : model })]).catch(() => { });
}

/** Removes every key value from a message, so an error from Google can never echo one. */
export function scrub(text, keys) {
  let s = String(text ?? '');
  for (const k of keys || []) if (k?.value && k.value.length >= 8) s = s.split(k.value).join('[key]');
  return s.replace(/AIza[0-9A-Za-z_\-]{20,}/g, '[key]');
}

/** One request to Gemini, trying each usable key until one isn't rate limited or rejected.
    send(key) must make the call and return {status, json}. Returns {status, json, key: label, rotated, exhausted}. */
export async function withKeys(store, model, send) {
  const { keys, total } = await usable(store, model);
  if (!total) throw Object.assign(Error('No Gemini key: add GEMINI_API_KEY in Vercel or a key in LifeOS Settings › Gemini › Server keys'), { status: 503 });
  if (!keys.length) return { status: 429, json: { error: { message: `All ${total} Gemini keys are cooling down for ${model}` } }, exhausted: true, rotated: 0 };
  let last = null, rotated = 0, rejected = 0;
  for (const k of keys) {
    const r = await send(k.value);
    const c = classify(r.status, r.json);
    if (!c) return { ...r, json: sanitize(r.json, keys), key: k.label, rotated };
    await cool(store, k.id, model, c);
    if (c.kind === 'rejected') rejected++;
    last = { ...r, json: sanitize(r.json, keys) }; rotated++;
  }
  return { ...last, exhausted: true, rotated, allRejected: rejected === keys.length };
}
const sanitize = (j, keys) => j?.error?.message ? { ...j, error: { ...j.error, message: scrub(j.error.message, keys) } } : j;

// ---- managing the pool (admin) ----

/** What the app shows: labels and status only, never a value. */
export async function describe(store, model, now = Date.now()) {
  const [keys, cool, recs] = await Promise.all([pool(store), cooldowns(store), records(store)]);
  const added = new Map(recs.map(r => [r.id, r]));
  const rows = keys.map(k => {
    const c = coolFor(cool, k.id, model, now);
    return { id: k.id, label: k.label, builtin: !!k.builtin, addedAt: added.get(k.id)?.addedAt, addedBy: added.get(k.id)?.addedBy,
      status: !c ? 'active' : c.reason === 'rejected' ? 'rejected' : 'cooling', reason: c?.reason, until: c?.until };
  });
  const unreadable = canStore() ? recs.filter(r => !keys.some(k => k.id === r.id)).length : recs.length;
  return { keys: rows, active: rows.filter(r => r.status === 'active').length, total: rows.length, model, canAdd: canStore(), unreadable: unreadable || undefined };
}

/** Adds a key. check(value) may test it with Google first and return an error message. */
export async function addKey(store, { key, label }, by, check) {
  if (!canStore()) throw Object.assign(Error('Set GEMINI_KEYS_SECRET in Vercel (any long random string) to store extra Gemini keys'), { status: 503 });
  const value = cleanKey(key);
  if (!KEY_SHAPE.test(value)) throw Object.assign(Error('That doesn\'t look like a Gemini API key'), { status: 400 });
  const existing = await pool(store);
  if (existing.some(k => k.value === value)) throw Object.assign(Error('That key is already in the pool'), { status: 409 });
  if (check) { const problem = await check(value); if (problem) throw Object.assign(Error(scrub(problem, [{ value }])), { status: 400 }) }
  const id = 'gk-' + randomUUID().slice(0, 8);
  const rec = { id, label: String(label || '').trim().slice(0, 40) || 'Key ' + (existing.length + 1), sealed: seal(value), addedAt: Date.now(), addedBy: by };
  await store(['HSET', KEYS, id, JSON.stringify(rec)]);
  return { id, label: rec.label, addedAt: rec.addedAt };
}
export async function removeKey(store, id) {
  if (id === 'env') throw Object.assign(Error('That key comes from GEMINI_API_KEY in Vercel; change it there'), { status: 400 });
  const rec = parse(await store(['HGET', KEYS, id]));
  if (!rec) throw Object.assign(Error('No such key'), { status: 404 });
  await store(['HDEL', KEYS, id]); await store(['HDEL', COOL, id + '|*']).catch(() => { });
  return { id, label: rec.label };
}
/** Clears a key's cooldowns, e.g. after you fixed its billing. */
export async function resetKey(store, id) {
  for (const k of Object.keys(await cooldowns(store))) if (k.startsWith(id + '|')) await store(['HDEL', COOL, k]);
  return { id };
}
