// Apple Push Notification service, with a token-based (.p8) key. Used by lumen-agent (Instinct changed something)
// and lumen-push (start the study block Live Activity before each block).
//
// Secrets: APNS_KEY_P8 (the .p8 file's contents), APNS_KEY_ID, APNS_TEAM_ID. Without them, nothing is sent.
import type { Db, Row } from './db.ts';

export interface ApnsConfig { key: string; keyId: string; teamId: string }

export function apnsFromEnv(): ApnsConfig | null {
  const key = Deno.env.get('APNS_KEY_P8') ?? '';
  const keyId = Deno.env.get('APNS_KEY_ID') ?? '';
  const teamId = Deno.env.get('APNS_TEAM_ID') ?? '';
  return key && keyId && teamId ? { key, keyId, teamId } : null;
}

const b64url = (bytes: Uint8Array | string) => {
  const raw = typeof bytes === 'string' ? new TextEncoder().encode(bytes) : bytes;
  let s = '';
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

/** The provider token APNs wants: an ES256 JWT, valid for up to an hour. */
export async function providerToken(cfg: ApnsConfig, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const pem = cfg.key.replace(/\\n/g, '\n').replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  const head = b64url(JSON.stringify({ alg: 'ES256', kid: cfg.keyId }));
  const claims = b64url(JSON.stringify({ iss: cfg.teamId, iat: nowSeconds }));
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(`${head}.${claims}`));
  return `${head}.${claims}.${b64url(new Uint8Array(sig))}`;
}

let cached: { token: string; at: number; keyId: string } | null = null;
async function bearer(cfg: ApnsConfig): Promise<string> {
  const now = Date.now();
  if (!cached || cached.keyId !== cfg.keyId || now - cached.at > 40 * 60e3) cached = { token: await providerToken(cfg), at: now, keyId: cfg.keyId };
  return cached.token;
}

export interface Push {
  token: string;
  environment: string;           // sandbox | production
  topic: string;                 // the app's bundle id (plus .push-type.liveactivity for Live Activities)
  pushType: 'alert' | 'background' | 'liveactivity';
  priority: 5 | 10;
  payload: Row;
  collapseId?: string;
}

export interface Sent { ok: boolean; status: number; reason?: string }

export async function sendPush(cfg: ApnsConfig, p: Push, fetcher: typeof fetch = fetch): Promise<Sent> {
  const host = p.environment === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const headers: Record<string, string> = {
    authorization: `bearer ${await bearer(cfg)}`, 'apns-topic': p.topic, 'apns-push-type': p.pushType,
    'apns-priority': String(p.priority), 'content-type': 'application/json',
  };
  if (p.collapseId) headers['apns-collapse-id'] = p.collapseId;
  try {
    const res = await fetcher(`https://${host}/3/device/${p.token}`, { method: 'POST', headers, body: JSON.stringify(p.payload) });
    if (res.ok) return { ok: true, status: res.status };
    const body = await res.json().catch(() => ({}));
    return { ok: false, status: res.status, reason: body?.reason };
  } catch (e) {
    return { ok: false, status: 0, reason: e instanceof Error ? e.message : String(e) };
  }
}

const dead = (r: Sent) => r.status === 410 || ['BadDeviceToken', 'Unregistered', 'DeviceTokenNotForTopic', 'TopicDisallowed'].includes(r.reason ?? '');

async function record(db: Db, token: Row, r: Sent) {
  if (r.ok) return;
  await db.update('push_tokens', { id: `eq.${token.id}` }, { last_error: r.reason ?? `HTTP ${r.status}`, ...(dead(r) ? { disabled_at: new Date().toISOString() } : {}) }).catch(() => {});
}

/** What to tell the student. Without a title it's silent: Lumen just syncs and reschedules in the background. */
export interface Notice { title?: string; body?: string; open?: string; thread?: string }

export async function notifyUser(db: Db, cfg: ApnsConfig | null, userId: string, notice: Notice, fetcher: typeof fetch = fetch): Promise<number> {
  if (!cfg) return 0;
  const tokens = await db.select('push_tokens', { user_id: `eq.${userId}`, kind: 'eq.device', disabled_at: 'is.null', select: '*' }).catch(() => [] as Row[]);
  let sent = 0;
  for (const t of tokens) {
    const visible = !!notice.title;
    const payload: Row = visible
      ? { aps: { alert: { title: notice.title, body: notice.body ?? '' }, sound: 'default', 'thread-id': notice.thread ?? 'lumen', 'content-available': 1 }, open: notice.open ?? 'lumen://today' }
      : { aps: { 'content-available': 1 } };
    const r = await sendPush(cfg, {
      token: t.token, environment: t.environment, topic: t.bundle_id, pushType: visible ? 'alert' : 'background',
      priority: visible ? 10 : 5, payload, collapseId: visible ? undefined : 'lumen-sync',
    }, fetcher);
    await record(db, t, r);
    if (r.ok) sent++;
  }
  return sent;
}

/** The Live Activity's content state, as StudyBlockAttributes.ContentState decodes it (dates in Unix seconds). */
export interface StudyState {
  phase: 'upcoming' | 'during' | 'rest' | 'ended';
  title: string; goal: string; subject: string; colorHex: string; kind: string;
  start: number; end: number; note: string;
}

/** Starts the study block Live Activity on a device, by push (iOS 17.2+). */
export function startActivityPayload(blockID: string, state: StudyState, alert: { title: string; body: string }): Row {
  return {
    aps: {
      timestamp: Math.floor(Date.now() / 1000), event: 'start', 'content-state': state,
      'attributes-type': 'StudyBlockAttributes', attributes: { blockID }, alert: { title: alert.title, body: alert.body, sound: 'default' },
      'stale-date': state.start, 'relevance-score': 100,
    },
  };
}

export function endActivityPayload(state: StudyState): Row {
  const now = Math.floor(Date.now() / 1000);
  return { aps: { timestamp: now, event: 'end', 'content-state': { ...state, phase: 'ended' }, 'dismissal-date': now + 300 } };
}

export async function sendActivity(db: Db, cfg: ApnsConfig, token: Row, payload: Row, fetcher: typeof fetch = fetch): Promise<Sent> {
  const r = await sendPush(cfg, {
    token: token.token, environment: token.environment, topic: `${token.bundle_id}.push-type.liveactivity`,
    pushType: 'liveactivity', priority: 10, payload,
  }, fetcher);
  await record(db, token, r);
  return r;
}
