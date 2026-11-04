// deno test supabase/tests — push: the APNs token, notifications after Instinct's changes, Live Activities by push.
import { endActivityPayload, notifyUser, providerToken } from '../functions/_shared/apns.ts';
import { sha256Hex } from '../functions/_shared/db.ts';
import { handle } from '../functions/lumen-agent/agent.ts';
import { tick } from '../functions/lumen-push/tick.ts';
import { FakeDb } from './fake_db.ts';

function assert(cond: unknown, msg = 'assertion failed'): asserts cond { if (!cond) throw new Error(msg); }
function equal<T>(a: T, b: T, msg = '') { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg} expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`); }

const USER = '11111111-1111-4111-8111-111111111111';
const NOW = new Date('2026-11-04T15:52:00Z');

async function testKey() {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let bin = '';
  for (const b of der) bin += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).match(/.{1,64}/g)!.join('\n')}\n-----END PRIVATE KEY-----`;
  return { cfg: { key: pem, keyId: 'ABC123DEFG', teamId: 'TEAM123456' }, publicKey: pair.publicKey };
}

interface Call { url: string; headers: Record<string, string>; body: Record<string, unknown> }

function fakeApns(status = 200, reason?: string) {
  const calls: Call[] = [];
  const fetcher = (async (url: string | URL | Request, init?: RequestInit) => {
    calls.push({ url: String(url), headers: init?.headers as Record<string, string>, body: JSON.parse(String(init?.body)) });
    return new Response(reason ? JSON.stringify({ reason }) : null, { status });
  }) as typeof fetch;
  return { calls, fetcher };
}

const unb64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), (c) => c.charCodeAt(0));

Deno.test('APNs provider token is a valid ES256 JWT', async () => {
  const { cfg, publicKey } = await testKey();
  const jwt = await providerToken(cfg, 1_800_000_000);
  const [h, c, sig] = jwt.split('.');
  equal(JSON.parse(new TextDecoder().decode(unb64(h))), { alg: 'ES256', kid: 'ABC123DEFG' });
  equal(JSON.parse(new TextDecoder().decode(unb64(c))), { iss: 'TEAM123456', iat: 1_800_000_000 });
  const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, publicKey, unb64(sig), new TextEncoder().encode(`${h}.${c}`));
  assert(ok, 'signature verifies with the public key');
});

Deno.test('notifications: visible and silent pushes, dead tokens switched off', async () => {
  const { cfg } = await testKey();
  const db = new FakeDb(() => NOW);
  db.seed('push_tokens', { user_id: USER, token: 'aa11', kind: 'device', environment: 'sandbox', bundle_id: 'com.jm2kool.lumen', disabled_at: null });
  db.seed('push_tokens', { user_id: USER, token: 'bb22', kind: 'device', environment: 'production', bundle_id: 'com.example.lumen', disabled_at: null });
  db.seed('push_tokens', { user_id: USER, token: 'cc33', kind: 'live_activity_start', environment: 'sandbox', bundle_id: 'com.jm2kool.lumen', disabled_at: null });
  const visible = fakeApns();
  equal(await notifyUser(db, cfg, USER, { title: 'Instinct has a new plan', body: '4 blocks', open: 'lumen://today' }, visible.fetcher), 2);
  equal(visible.calls[0].url, 'https://api.sandbox.push.apple.com/3/device/aa11');
  equal(visible.calls[1].url, 'https://api.push.apple.com/3/device/bb22');
  equal(visible.calls[1].headers['apns-topic'], 'com.example.lumen', 'topic is the bundle id the device reported');
  equal(visible.calls[0].headers['apns-push-type'], 'alert');
  equal((visible.calls[0].body.aps as Record<string, unknown>)['content-available'], 1);
  equal(visible.calls[0].body.open, 'lumen://today');
  assert(visible.calls[0].headers.authorization.startsWith('bearer '), 'token auth');

  const silent = fakeApns();
  await notifyUser(db, cfg, USER, {}, silent.fetcher);
  equal(silent.calls[0].headers['apns-push-type'], 'background');
  equal(silent.calls[0].headers['apns-priority'], '5');
  equal(silent.calls[0].body, { aps: { 'content-available': 1 } });

  const gone = fakeApns(410, 'Unregistered');
  equal(await notifyUser(db, cfg, USER, { title: 'x' }, gone.fetcher), 0);
  assert(db.t('push_tokens').filter((t) => t.kind === 'device').every((t) => t.disabled_at), 'dead tokens are switched off');
});

Deno.test('Live Activities: started by push before a block, once; ended after', async () => {
  const { cfg } = await testKey();
  const db = new FakeDb(() => NOW);
  const physics = db.seed('subjects', { user_id: USER, name: 'Physics', color: '#7C8CFF' });
  const hw = db.seed('assignments', { user_id: USER, title: 'Physics worksheet' });
  const soon = db.seed('blocks', { user_id: USER, start_at: '2026-11-04T16:00:00Z', end_at: '2026-11-04T16:50:00Z', subject_id: physics.id, assignment_id: hw.id, goal: 'Questions 7–12' });
  db.seed('blocks', { user_id: USER, start_at: '2026-11-04T18:00:00Z', end_at: '2026-11-04T18:50:00Z', goal: 'Later' });
  const old = db.seed('blocks', { user_id: USER, start_at: '2026-11-04T14:00:00Z', end_at: '2026-11-04T14:50:00Z', goal: 'Earlier' });
  db.seed('push_tokens', { user_id: USER, token: 'start1', kind: 'live_activity_start', environment: 'sandbox', bundle_id: 'com.jm2kool.lumen', disabled_at: null });
  db.seed('push_tokens', { user_id: USER, token: 'act1', kind: 'live_activity', activity_key: old.id, environment: 'sandbox', bundle_id: 'com.jm2kool.lumen', disabled_at: null });

  const apns = fakeApns();
  const r = await tick(db, cfg, NOW, apns.fetcher);
  equal(r.started, 1);
  equal(r.ended, 1);
  const start = apns.calls.find((c) => c.url.endsWith('/start1'))!;
  equal(start.headers['apns-topic'], 'com.jm2kool.lumen.push-type.liveactivity');
  equal(start.headers['apns-push-type'], 'liveactivity');
  const aps = start.body.aps as Record<string, unknown>;
  equal(aps.event, 'start');
  equal(aps['attributes-type'], 'StudyBlockAttributes');
  equal(aps.attributes, { blockID: soon.id });
  const state = aps['content-state'] as Record<string, unknown>;
  equal(state.phase, 'upcoming');
  equal(state.title, 'Physics worksheet');
  equal(state.subject, 'Physics');
  equal(state.start, Date.parse('2026-11-04T16:00:00Z') / 1000, 'Unix seconds');
  equal((aps.alert as Record<string, string>).title, 'Physics in 8 min');
  const end = apns.calls.find((c) => c.url.endsWith('/act1'))!;
  equal((end.body.aps as Record<string, unknown>).event, 'end');
  assert(db.t('push_tokens').find((t) => t.token === 'act1')!.disabled_at, 'ended activity token retired');

  const again = fakeApns();
  const r2 = await tick(db, cfg, new Date(NOW.getTime() + 60e3), again.fetcher);
  equal(r2.started, 0, 'not started twice');
  equal(again.calls.length, 0);
  equal((endActivityPayload({ phase: 'during', title: 't', goal: '', subject: '', colorHex: '', kind: 'study', start: 1, end: 2, note: '' }).aps as Record<string, Record<string, string>>)['content-state'].phase, 'ended');
});

Deno.test('agent: pushes after Instinct plans or adds work, not after reads', async () => {
  const db = new FakeDb(() => NOW);
  const KEY = 'lmn_push_test_key_0123456789abcdefghijklmnop';
  db.seed('agent_keys', { user_id: USER, name: 'Instinct', key_hash: await sha256Hex(KEY), scopes: ['read', 'write:assignments', 'write:plan'], revoked_at: null });
  db.seed('preferences', { id: USER, user_id: USER, timezone: 'Europe/London', plan_mode: 'ask', earliest_time: '08:00', latest_time: '22:00', max_hours_per_day: 4, no_study_days: [] });
  const pushed: { user: string; notice: Record<string, unknown> }[] = [];
  const call = async (method: string, path: string, body?: unknown) => {
    const req = new Request(`https://x.supabase.co/functions/v1/lumen-agent${path}`, {
      method, headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body),
    });
    return await handle(req, { db, now: () => NOW, notify: (user, notice) => pushed.push({ user, notice: notice as Record<string, unknown> }) });
  };
  await call('GET', '/context');
  equal(pushed.length, 0, 'reads push nothing');
  await call('POST', '/assignments', { title: 'Chemistry lab report', kind: 'project', due_at: '2026-11-13T17:00' });
  equal(pushed[0].notice.title, 'Instinct added Chemistry lab report');
  assert(String(pushed[0].notice.open).startsWith('lumen://assignment?id='), 'opens the assignment');
  await call('POST', '/plan', { blocks: [{ start_at: '2026-11-05T16:00:00Z', end_at: '2026-11-05T16:50:00Z', goal: 'x' }] });
  equal(pushed[1].notice.title, 'Instinct has a new plan');
  equal(pushed[1].user, USER);
  await call('POST', '/plan', { mode: 'auto', blocks: [{ start_at: '2026-11-06T16:00:00Z', end_at: '2026-11-06T16:50:00Z', goal: 'y' }] });
  equal(pushed[2].notice.title, 'Instinct updated your plan');
});
