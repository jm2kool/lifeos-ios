// Supabase Edge Function: lumen-push — called every minute by pg_cron (see supabase/push_cron.sql) to start the
// study block Live Activity by push before each block and end it after. Deploy with JWT checking off; it checks the
// x-lumen-cron header against the LUMEN_CRON_SECRET secret instead:
//   supabase functions deploy lumen-push --no-verify-jwt
import { restDb } from '../_shared/db.ts';
import { apnsFromEnv } from '../_shared/apns.ts';
import { tick } from './tick.ts';

const db = restDb(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '');
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  const secret = Deno.env.get('LUMEN_CRON_SECRET') ?? '';
  if (!secret || req.headers.get('x-lumen-cron') !== secret) return json(401, { error: 'Not allowed.' });
  const cfg = apnsFromEnv();
  if (!cfg) return json(200, { skipped: 'APNs is not set up (APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID).' });
  try {
    return json(200, await tick(db, cfg));
  } catch (e) {
    console.error('lumen-push', e);
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
