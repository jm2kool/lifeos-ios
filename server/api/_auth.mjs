// Who is calling, and what they may do. One key per caller, each with a permission:
//   read  – see the dashboard, ask questions
//   write – also change things (ops, /api/say changes, /api/import, undo its own changes)
//   admin – also replace the whole doc, manage keys, read the audit log, undo anyone's changes
// Keys are only accepted in the Authorization header, never in a URL. Only a hash of each key is stored.
// LIFEOS_TOKEN (the owner, admin) and LIFEOS_AGENT_TOKEN (legacy assistant, write) keep working from env;
// the legacy key can be revoked like any other.
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

const env = process.env;
const KEYS = 'lifeos:keys', AUDIT = 'lifeos:audit', REVOKED = 'lifeos:keys:revoked';
export const SCOPES = ['read', 'write', 'admin'];
const RANK = { read: 1, write: 2, admin: 3 };
const AUDIT_MAX = 2000;

const sha = t => createHash('sha256').update(String(t)).digest('hex');
const same = (a, b) => { const x = Buffer.from(String(a || '')), y = Buffer.from(String(b || '')); return x.length === y.length && x.length > 0 && timingSafeEqual(x, y) };
const pairs = r => { if (!r) return []; if (!Array.isArray(r)) return Object.entries(r); const o = []; for (let i = 0; i < r.length; i += 2) o.push([r[i], r[i + 1]]); return o };
const parse = s => { try { return JSON.parse(s) } catch { return null } };
const query = req => req.query || Object.fromEntries(new URL(req.url || '/', 'http://x').searchParams);

export const can = (caller, scope) => !!caller && RANK[caller.scope] >= RANK[scope];
// LIFEOS_ADMIN_KEYS: comma-separated key names or ids that get admin access (set in Vercel; no key values involved).
const promoted = rec => String(env.LIFEOS_ADMIN_KEYS || '').split(',').map(x => x.trim().toLowerCase()).filter(Boolean).some(x => x === String(rec.id).toLowerCase() || x === String(rec.name).toLowerCase());
const effective = rec => promoted(rec) ? 'admin' : rec.scope;
const owner = () => ({ id: 'owner', name: String(env.LIFEOS_OWNER_NAME || 'You').slice(0, 40), scope: 'admin', builtin: true });
const legacy = () => ({ id: 'legacy-agent', name: String(env.LIFEOS_AGENT_NAME || 'Assistant').slice(0, 40), scope: 'write', builtin: true, legacy: true });

const URL_KEYS = ['key', 'token', 'access_token', 'auth'];
/** Returns {caller} or {status, error, fix}. Keys in a URL are always refused, even with a valid header. */
export async function authenticate(req, store, { cron = false } = {}) {
  const q = query(req);
  if (URL_KEYS.some(k => q[k] != null)) return { status: 400, error: 'Keys in URLs are refused: they end up in logs and browser history.', fix: 'Send the header Authorization: Bearer <your key> instead, and revoke any key you have put in a URL.' };
  const token = /^Bearer\s+(\S+)$/.exec(req.headers?.authorization || '')?.[1];
  if (!token) return { status: 401, error: 'Missing key', fix: 'Send the header Authorization: Bearer <your key>' };
  if (same(token, env.LIFEOS_TOKEN)) return { caller: owner() };
  if (same(token, env.LIFEOS_AGENT_TOKEN)) {
    if (await store(['SISMEMBER', REVOKED, 'legacy-agent']).catch(() => 0)) return { status: 401, error: 'This key was revoked' };
    return { caller: legacy() };
  }
  if (cron && same(token, env.CRON_SECRET)) return { caller: { id: 'cron', name: 'Gemini', scope: 'write', builtin: true } };
  const h = sha(token);
  const rec = parse(await store(['HGET', KEYS, h]));
  if (!rec) return { status: 401, error: 'Wrong key' };
  if (rec.revokedAt) return { status: 401, error: 'This key was revoked' };
  if (!rec.lastUsedAt || Date.now() - rec.lastUsedAt > 10 * 60e3) { rec.lastUsedAt = Date.now(); await store(['HSET', KEYS, h, JSON.stringify(rec)]).catch(() => {}) }
  return { caller: { id: rec.id, name: rec.name, scope: effective(rec) } };
}

/** Sends the auth failure, or returns the caller if it has `scope`. */
export async function gate(req, res, store, scope, opts) {
  const a = await authenticate(req, store, opts);
  if (!a.caller) { res.status(a.status).json({ error: a.error, fix: a.fix }); return null }
  if (!can(a.caller, scope)) {
    await audit(store, a.caller, [{ op: 'denied', summary: (req.method || '') + ' ' + String(req.url || '').split('?')[0] + ' needs ' + scope, ok: false }], req);
    res.status(403).json({ error: `This key (${a.caller.name}) is ${a.caller.scope}-only; this needs ${scope} access.` }); return null;
  }
  return a.caller;
}

/** Names that callers other than the owner may not use. */
export async function reservedNames(store) {
  const names = new Set([owner().name.toLowerCase(), legacy().name.toLowerCase()]);
  for (const [, v] of pairs(await store(['HGETALL', KEYS]))) { const r = parse(v); if (r && !r.revokedAt) names.add(String(r.name).toLowerCase()) }
  return names;
}
/** The name a change is recorded under. Only the owner may label changes (e.g. "you", "Gemini"), and never with another caller's name. */
export function attribution(caller, requested, reserved) {
  if (caller.scope !== 'admin' || !requested) return caller.name;
  const r = String(requested).slice(0, 40);
  return reserved && reserved.has(r.toLowerCase()) && r.toLowerCase() !== caller.name.toLowerCase() ? caller.name : r;
}

export async function audit(store, caller, entries, req) {
  if (!entries.length) return;
  const ip = String(req?.headers?.['x-forwarded-for'] || '').split(',')[0].trim() || undefined;
  const at = Date.now();
  const rows = entries.map(e => JSON.stringify({ at, key: caller?.id, name: caller?.name, ip, ...e }));
  try { await store(['LPUSH', AUDIT, ...rows]); await store(['LTRIM', AUDIT, 0, AUDIT_MAX - 1]) } catch { }
}
export async function readAudit(store, limit = 100) {
  return ((await store(['LRANGE', AUDIT, 0, Math.min(AUDIT_MAX, Math.max(1, limit)) - 1])) || []).map(parse).filter(Boolean);
}

export async function listKeys(store) {
  const out = [owner(), legacy()].filter(k => k.id === 'owner' ? env.LIFEOS_TOKEN : env.LIFEOS_AGENT_TOKEN);
  const revokedLegacy = await store(['SISMEMBER', REVOKED, 'legacy-agent']).catch(() => 0);
  for (const k of out) if (k.legacy && revokedLegacy) k.revokedAt = true;
  for (const [, v] of pairs(await store(['HGETALL', KEYS]))) { const r = parse(v); if (r) { if (!r.revokedAt && promoted(r)) { r.grantedScope = r.scope; r.scope = 'admin'; r.viaSetting = 'LIFEOS_ADMIN_KEYS' } out.push(r) } }
  return out.sort((a, b) => (a.builtin ? 0 : 1) - (b.builtin ? 0 : 1) || (a.createdAt || 0) - (b.createdAt || 0));
}
/** Returns the new key once; only its hash is kept. */
export async function createKey(store, { name, scope }, by) {
  name = String(name || '').trim().slice(0, 40);
  if (!name) throw Object.assign(Error('Give the key a name, e.g. "FRIDAY"'), { status: 400 });
  if (!SCOPES.includes(scope)) throw Object.assign(Error('scope must be read, write or admin'), { status: 400 });
  if ((await reservedNames(store)).has(name.toLowerCase())) throw Object.assign(Error(`A key named "${name}" already exists; revoke it first or pick another name`), { status: 409 });
  const key = 'lfo_' + randomBytes(24).toString('base64url');
  const rec = { id: 'key-' + randomBytes(6).toString('hex'), name, scope, createdAt: Date.now(), createdBy: by, hint: key.slice(0, 8) + '…' };
  await store(['HSET', KEYS, sha(key), JSON.stringify(rec)]);
  return { key, record: rec };
}
/** Changes what a key may do. The key itself stays the same. */
export async function updateKey(store, id, scope, by) {
  if (!SCOPES.includes(scope)) throw Object.assign(Error('scope must be read, write or admin'), { status: 400 });
  if (id === 'owner' || id === 'legacy-agent') throw Object.assign(Error('This key comes from a Vercel setting; its access can\'t be changed here'), { status: 400 });
  for (const [h, v] of pairs(await store(['HGETALL', KEYS]))) {
    const r = parse(v);
    if (r && r.id === id) {
      if (r.revokedAt) throw Object.assign(Error('This key was revoked'), { status: 409 });
      r.scope = scope; r.changedAt = Date.now(); r.changedBy = by;
      await store(['HSET', KEYS, h, JSON.stringify(r)]);
      return Object.assign({}, r, promoted(r) ? { scope: 'admin', grantedScope: scope, viaSetting: 'LIFEOS_ADMIN_KEYS' } : {});
    }
  }
  throw Object.assign(Error('No such key'), { status: 404 });
}
export async function revokeKey(store, id, by) {
  if (id === 'owner') throw Object.assign(Error('The owner key comes from LIFEOS_TOKEN in Vercel; change it there to rotate it'), { status: 400 });
  if (id === 'legacy-agent') { await store(['SADD', REVOKED, 'legacy-agent']); return { id, name: legacy().name, revokedAt: Date.now(), revokedBy: by } }
  for (const [h, v] of pairs(await store(['HGETALL', KEYS]))) {
    const r = parse(v);
    if (r && r.id === id) { if (!r.revokedAt) { r.revokedAt = Date.now(); r.revokedBy = by; await store(['HSET', KEYS, h, JSON.stringify(r)]) } return r }
  }
  throw Object.assign(Error('No such key'), { status: 404 });
}
