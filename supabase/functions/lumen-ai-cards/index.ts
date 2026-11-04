// Supabase Edge Function: lumen-ai-cards — turns study notes into flashcards for the app.
// Claude is Lumen's main AI; Apple Intelligence on the iPhone is the fallback. Signed-in users only.
//
// Secrets (Supabase → Edge Functions → Secrets):
//   ANTHROPIC_API_KEY   required: Claude writes the cards (default model claude-opus-5-5)
//   LUMEN_AI_MODEL      optional: a different Claude model id
// If this can't be reached, the app falls back to Apple Intelligence on the iPhone.
import Anthropic from 'npm:@anthropic-ai/sdk@1.4.0';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...CORS } });

interface Card { front: string; back: string }

const SCHEMA = {
  type: 'object',
  properties: {
    cards: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          front: { type: 'string', description: 'A short, specific question or prompt' },
          back: { type: 'string', description: 'The answer in one or two sentences, or a formula' },
        },
        required: ['front', 'back'],
        additionalProperties: false,
      },
    },
  },
  required: ['cards'],
  additionalProperties: false,
};

const SYSTEM = `You write excellent study flashcards from a student's notes.
- Each card tests exactly one fact, definition, formula, cause, or step.
- Fronts are clear questions a student could answer from memory; avoid yes/no questions.
- Backs are short and correct, taken only from the notes. Never invent facts that aren't there.
- Write formulas in LaTeX between dollar signs, e.g. $v = u + at$, $H_2O$, $\\frac{1}{2}mv^2$.
- Cover the most important ideas first. Skip trivia, headings and page furniture.
- Match the language of the notes.`;

async function userFrom(req: Request): Promise<string | null> {
  const auth = req.headers.get('authorization');
  const url = Deno.env.get('SUPABASE_URL');
  const anon = Deno.env.get('SUPABASE_ANON_KEY');
  if (!auth || !url || !anon) return null;
  const res = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: auth, apikey: anon } });
  if (!res.ok) return null;
  const user = await res.json();
  return typeof user?.id === 'string' ? user.id : null;
}

function clean(cards: unknown): Card[] {
  if (!Array.isArray(cards)) return [];
  const seen = new Set<string>();
  const out: Card[] = [];
  for (const c of cards) {
    const front = typeof c?.front === 'string' ? c.front.trim() : '';
    const back = typeof c?.back === 'string' ? c.back.trim() : '';
    if (!front || !back || seen.has(front.toLowerCase())) continue;
    seen.add(front.toLowerCase());
    out.push({ front: front.slice(0, 1000), back: back.slice(0, 2000) });
  }
  return out;
}

async function withClaude(key: string, notes: string, count: number, subject: string): Promise<{ cards: Card[]; model: string }> {
  const client = new Anthropic({ apiKey: key });
  const model = Deno.env.get('LUMEN_AI_MODEL') || 'claude-opus-5-5';
  const response = await client.beta.messages.create({
    model,
    max_tokens: 16000,
    // If a safety classifier declines, the API re-runs the request on Anthropic's recommended fallback model.
    betas: ['server-side-fallback-2026-07-01'],
    fallbacks: 'default',
    output_config: { effort: 'medium', format: { type: 'json_schema', schema: SCHEMA } },
    system: SYSTEM,
    messages: [{
      role: 'user',
      content: `${subject ? `Subject: ${subject}\n` : ''}Write up to ${count} flashcards from these notes:\n\n<notes>\n${notes}\n</notes>`,
    }],
  });
  if (response.stop_reason === 'refusal') throw new Error('The AI declined to make cards from these notes.');
  if (response.stop_reason === 'max_tokens') console.warn('lumen-ai-cards: hit max_tokens; using what came back');
  let text = '';
  for (const block of response.content) if (block.type === 'text') text += block.text;
  const parsed = JSON.parse(text);
  return { cards: clean(parsed.cards).slice(0, count), model: response.model ?? model };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'Use POST.' });
  const user = await userFrom(req);
  if (!user) return json(401, { error: 'Sign in to Lumen to make cards with AI.' });

  let body: { text?: unknown; count?: unknown; subject?: unknown };
  try { body = await req.json(); } catch { return json(400, { error: 'Send JSON: {"text": "...", "count": 15}.' }); }
  const notes = typeof body.text === 'string' ? body.text.trim() : '';
  if (notes.length < 20) return json(400, { error: 'Add a bit more text to make cards from.' });
  if (notes.length > 60000) return json(413, { error: 'That is a lot of text — split it into parts of under 60,000 characters.' });
  const count = Math.min(60, Math.max(1, Math.round(Number(body.count) || 15)));
  const subject = typeof body.subject === 'string' ? body.subject.slice(0, 80) : '';

  const anthropic = Deno.env.get('ANTHROPIC_API_KEY');
  if (!anthropic) return json(503, { error: 'Claude is not set up: add ANTHROPIC_API_KEY in Supabase → Edge Functions → Secrets.' });
  try {
    const result = await withClaude(anthropic, notes, count, subject);
    return json(200, { cards: result.cards, model: result.model, provider: 'anthropic' });
  } catch (e) {
    console.error('lumen-ai-cards', e instanceof Error ? e.message : e);
    const message = e instanceof Anthropic.RateLimitError ? 'The AI is busy — try again in a minute.'
      : e instanceof Anthropic.AuthenticationError ? 'The AI key in Supabase secrets was not accepted.'
      : e instanceof Error ? e.message : 'The AI could not make cards right now.';
    return json(502, { error: message });
  }
});
