// Supabase Edge Function: lumen-agent — the API Instinct uses. Deploy with JWT checking off, because it is
// authenticated with Lumen access keys instead (see supabase/config.toml and README):
//   supabase functions deploy lumen-agent --no-verify-jwt
import { handle } from './agent.ts';
import { restDb } from '../_shared/db.ts';
import { apnsFromEnv, type Notice, notifyUser } from '../_shared/apns.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('LUMEN_SERVICE_KEY') ?? '';
const db = restDb(url, key);

const apns = apnsFromEnv();

/** Pushes after the response has gone, so Instinct never waits on Apple. */
function notify(userId: string, notice: Notice) {
  if (!apns) return;
  const work = notifyUser(db, apns, userId, notice).catch((e) => console.error('push', e));
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) runtime.waitUntil(work);
}

Deno.serve((req) => handle(req, { db, notify }));
