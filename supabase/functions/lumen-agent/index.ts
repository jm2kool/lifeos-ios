// Supabase Edge Function: lumen-agent — the API Instinct uses. Deploy with JWT checking off, because it is
// authenticated with Lumen access keys instead (see supabase/config.toml and README):
//   supabase functions deploy lumen-agent --no-verify-jwt
import { handle } from './agent.ts';
import { restDb } from './db.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? Deno.env.get('LUMEN_SERVICE_KEY') ?? '';
const db = restDb(url, key);

Deno.serve((req) => handle(req, { db }));
