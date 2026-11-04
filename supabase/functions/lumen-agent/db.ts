// A small client for the Data API (PostgREST) on the `lumen` schema, using the service role.
// The agent always filters by the key owner's user_id itself, since the service role skips row-level security.

// deno-lint-ignore no-explicit-any
export type Row = Record<string, any>;
export type Query = Record<string, string>;

export interface Db {
  select(table: string, q: Query): Promise<Row[]>;
  insert(table: string, rows: Row | Row[]): Promise<Row[]>;
  update(table: string, q: Query, values: Row): Promise<Row[]>;
  // deno-lint-ignore no-explicit-any
  rpc(name: string, args: Row): Promise<any>;
}

export class DbError extends Error {
  constructor(public status: number, message: string, public code?: string) { super(message); }
}

export function restDb(baseUrl: string, key: string, schema = 'lumen'): Db {
  const base = baseUrl.replace(/\/$/, '') + '/rest/v1/';
  const headers = (extra: Record<string, string> = {}) => {
    const h: Record<string, string> = {
      apikey: key, 'Accept-Profile': schema, 'Content-Profile': schema, 'Content-Type': 'application/json', ...extra,
    };
    // New-style secret keys (sb_secret_…) go only in apikey; legacy service-role JWTs also as a bearer token.
    if (!key.startsWith('sb_')) h.Authorization = `Bearer ${key}`;
    return h;
  };
  async function call(method: string, path: string, q: Query, body?: unknown, prefer?: string) {
    const url = base + path + (Object.keys(q).length ? '?' + new URLSearchParams(q).toString() : '');
    const res = await fetch(url, { method, headers: headers(prefer ? { Prefer: prefer } : {}), body: body === undefined ? undefined : JSON.stringify(body) });
    const text = await res.text();
    // deno-lint-ignore no-explicit-any
    let json: any = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = text; }
    if (!res.ok) throw new DbError(res.status, json?.message ?? `Database error ${res.status}`, json?.code);
    return json;
  }
  return {
    select: (table, q) => call('GET', table, q),
    insert: (table, rows) => call('POST', table, { select: '*' }, rows, 'return=representation'),
    update: (table, q, values) => call('PATCH', table, { ...q, select: '*' }, values, 'return=representation'),
    rpc: (name, args) => call('POST', 'rpc/' + name, {}, args),
  };
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
