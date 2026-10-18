# LifeOS server (optional)

Lets your iMessage assistant add and remove things in LifeOS by sending a plain sentence to one
web address, keeps your iPhone in sync, and lets Gemini refresh your Today screen every hour or two
even when the app is closed. Deploy it once; after that nobody touches code or Vercel.

## Deploy (once)
1. Import this repo into Vercel with **Root Directory = `server`** (no framework, no build command).
2. Storage: Vercel → Storage → add **Upstash Redis** (free). It sets `KV_REST_API_URL` and `KV_REST_API_TOKEN`.
3. Environment variables:
   - `LIFEOS_TOKEN` – a long random string; paste it into the app (Settings › Sync key).
   - `LIFEOS_AGENT_TOKEN` – another long random string, for your iMessage assistant.
   - `GEMINI_API_KEY` – your Gemini key (used by `/api/say`, `/api/pulse`, `/api/ai`).
4. In the app: Settings › Sync › server = your Vercel URL, sync key = `LIFEOS_TOKEN`.
5. Optional: on cron-job.org, call `https://YOUR-APP.vercel.app/api/pulse?key=LIFEOS_AGENT_TOKEN` every 2 hours.

## What to tell your iMessage assistant
> To change my LifeOS dashboard, send a POST to https://YOUR-APP.vercel.app/api/say with header
> `Authorization: Bearer <agent token>` and JSON `{"text": "<what to do, in plain English>", "by": "Instinct"}`.
> Examples: "add revise Sound for tomorrow", "remove the graph paper card", "mark the MUN email done",
> "add Physics tuition Thursday 7pm to my timetable", "what's on my board?". The reply says what changed.
> If you can only open links: GET https://YOUR-APP.vercel.app/api/say?key=<agent token>&text=<url-encoded sentence>

Advanced: `GET/POST /api/lifeos` reads the whole dashboard or applies exact ops (see the op list in `api/_ai.mjs`).
Every change is logged with who made it, and the app can undo it.
