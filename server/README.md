# LifeOS server (optional)

Lets your assistants add and remove things in LifeOS by sending a plain sentence to one web address,
keeps your iPhone in sync, and lets Gemini refresh your Today screen every hour or two even when the app
is closed. Deploy it once; after that nobody touches code or Vercel.

## Deploy (once)
1. Import this repo into Vercel with **Root Directory = `server`** (no framework, no build command).
2. Storage: Vercel → Storage → add **Upstash Redis** (free). It sets `KV_REST_API_URL` and `KV_REST_API_TOKEN`.
3. Environment variables:
   - `LIFEOS_TOKEN` – a long random string. This is the **owner key**: paste it into the app (Settings › Sync key).
   - `GEMINI_API_KEY` – your Gemini key (used by `/api/say`, `/api/pulse`, `/api/ai`).
   - Optional: `GEMINI_MODEL` (default `gemini-3.5-flash`), `LIFEOS_OWNER_NAME` (default `You`).
   - Optional: `GEMINI_KEYS_SECRET` – any long random string (16+ characters). Lets you add more Gemini keys
     from the app; they're encrypted with it before they're stored (see "Several Gemini keys").
   - Optional, older setups: `LIFEOS_AGENT_TOKEN` + `LIFEOS_AGENT_NAME` (see "The old shared key" below).
4. In the app: Settings › Sync › server = your Vercel URL, sync key = `LIFEOS_TOKEN`.
5. In the app: Settings › Access keys › create one key per assistant (e.g. "FRIDAY", *Read and change*).

## Keys and permissions
Every caller gets its own key. A key is **read only**, **write** (read and change) or **admin**
(also manage keys, see the audit log, replace everything, undo anyone's changes).

- Changes are recorded under the **key's name**. A request can't claim to be someone else: a `"by"` field
  from a non-admin key is ignored, and even the owner can't label a change with another key's name.
- Keys go in the header `Authorization: Bearer <key>` only. **A key in a URL (`?key=…`) is refused**
  with a 400, even if the header is also set, because URLs end up in logs and browser history.
- Only a hash of each key is stored. The key itself is shown once, when it's created.
- Revoke a key in the app (Settings › Access keys, swipe left) or with `DELETE /api/keys`.
  The owner key comes from `LIFEOS_TOKEN`; change it in Vercel to rotate it.
- Every change (and every refused attempt) goes into an audit log: who, what, when, from which IP.
  See it in the app under Access keys, or `GET /api/keys?view=audit`.

```
GET    /api/keys                                    list keys (admin)
GET    /api/keys?view=audit&limit=100               who changed what, newest first
POST   /api/keys     {"name":"FRIDAY","scope":"write"}   -> {"key":"lfo_…","record":{…}}  (key shown once)
PATCH  /api/keys     {"id":"key-…","scope":"admin"} change what a key may do (also: touch and hold a key in the app)
DELETE /api/keys     {"id":"key-…"}                 revoke ("legacy-agent" revokes LIFEOS_AGENT_TOKEN)
GET    /api/lifeos?view=me                          which key am I? {"id","name","scope"}
```

A Vercel setting can also make named keys admin: `LIFEOS_ADMIN_KEYS=Instinct` (comma-separated key names or
ids). Remove it from Vercel and redeploy to take that back. A revoked key stays revoked either way.

`PUT /api/lifeos` (replace the whole doc, admin) accepts an optional `"rev"`: if the doc changed since that rev
you get a 409 instead of overwriting. The previous version is kept for 7 days, so a replace can be undone from
Activity or with `{"undo": "<logId>"}`.

### The old shared key
`LIFEOS_AGENT_TOKEN` keeps working as a **write** key named `LIFEOS_AGENT_NAME` (default `Assistant`).
Its changes are labelled with that name no matter what `"by"` says. Once each assistant has its own key,
revoke it under Access keys ("The old shared assistant key").

## What to tell your assistant
> To change my LifeOS dashboard, send a POST to https://YOUR-APP.vercel.app/api/say with headers
> `Authorization: Bearer <your key>` and `Content-Type: application/json`, and the body
> `{"text": "<what to do, in plain English>"}`. Examples: "add revise Sound for tomorrow",
> "remove the graph paper card", "mark the MUN email done", "what's on my board?".
> Never put the key in the URL. To add several items at once, use /api/import instead (below).

### `/api/say`
Request: `POST /api/say` with JSON `{"text": "…"}` (max 4000 characters). `"question"` or `"message"`
are accepted in place of `"text"`. A missing or empty text returns **400** with the shape it expects:

```json
{"error": "Missing \"text\". Got fields: prompt.",
 "expected": {"method": "POST", "url": "/api/say",
              "headers": {"Authorization": "Bearer <your key>", "Content-Type": "application/json"},
              "body": {"text": "string, required: …"}, "example": {"text": "add revise Sound for tomorrow"}}}
```

Reply (200, or 207 if some changes failed):
```json
{"reply": "Added “Revise Sound” for tomorrow.",
 "changes": [{"op": "task.add", "title": "Revise Sound", "ok": true}],
 "model": "gemini-3.5-flash", "batch": "batch-…", "warnings": ["…only when something went wrong"]}
```
- With a read-only key, Gemini answers but nothing is changed (`"readOnly": true`).
- **Model fallback:** if `GEMINI_MODEL` is gone ("no longer available", 404), busy, slow, or answers with
  nothing usable, the server tries `gemini-3.5-flash`, `gemini-2.5-flash`, then `gemini-flash-latest`.
  When a fallback answers, `warnings` says which model failed and why; a model Google says is gone is
  skipped for the rest of that server instance's life.
- If every model fails you get a **502** (504 if they all timed out) with `"error"`, `"attempts"`
  (each model and its error) and `"retry": true`, never an empty reply. Nothing is changed in that case.
- At most 30 changes per sentence; more are cut and `warnings` says so.

## Several Gemini keys
Free Gemini keys have small per-minute and per-day limits. Add more keys in the app (Settings › Gemini › API keys ›
On your server) and the server uses them in turn: when a key is rate limited or out of quota it cools down (for
Google's suggested wait, or until the daily reset at midnight Pacific for a daily quota) and the next key answers.
A key Google rejects rests for 6 hours. Cooldowns are per model, since Google's free quotas are. `GEMINI_API_KEY` is
always first in the pool.

- Added keys are encrypted (AES-256-GCM with `GEMINI_KEYS_SECRET`) before they reach Redis. Changing or removing
  that secret makes them unreadable: add them again.
- Key values are never returned, logged or put in an error message, and a key is checked with Google before it's added.
- `/api/say`, `/api/pulse` and the app's `/api/ai` proxy all use the pool. `/api/ai` answers with the header
  `X-LifeOS-Keys: <active>/<total>`, which is how the app shows the count.
- Keys added on the iPhone itself stay in its Keychain and are never sent here.

```
GET    /api/gemini-keys                         {keys: [{id, label, status: active|cooling|rejected, reason, until}], active, total}   (admin)
POST   /api/gemini-keys {"key":"AIza…","label":"Spare 1"}
PATCH  /api/gemini-keys {"id":"gk-…","reset":true}   clear a cooldown
DELETE /api/gemini-keys {"id":"gk-…"}
```

## Bulk import: `/api/import`
Exact, doesn't go through Gemini, and reports every item. Use it for anything more than a few items.

```
POST /api/import        Authorization: Bearer <write key>
{"inbox":  [{"subject": "MUN briefing", "from": "sec@school.org", "account": "Gmail · main", "body": "…"}],
 "events": [{"title": "TALLENTEX exam", "start": "2026-10-25T08:00:00+05:30", "end": "2026-10-25T12:00:00+05:30"}],
 "tasks":  [{"title": "Revise Sound", "due": "2026-10-19"}],
 "board":  [{"title": "Graph paper", "column": "To do"}],
 "saved":  [{"title": "Notes", "url": "https://…"}],
 "dryRun": false}
```
or `{"doc": <a whole LifeOS export>}` to merge a backup into what's on the server (this is what the app's
Import does). Up to 2000 items per call.

Reply (200, or **207** if any item failed, the rest are still imported):
```json
{"ok": false, "summary": "Imported 2 tasks, 1 event, 10 inbox items; 1 likely duplicate skipped; 1 item failed.",
 "counts": {"inbox": {"added": 10, "updated": 0, "unchanged": 0, "duplicate": 0, "failed": 1}, "…": {}},
 "items": [{"kind": "inbox", "index": 4, "status": "failed", "error": "Inbox item needs a subject (t or subject)"},
           {"kind": "events", "index": 0, "id": "event-…", "status": "duplicate", "duplicateOf": "55uap…", "duplicateTitle": "TALLENTEX exam (offline)"}],
 "batch": "batch-…", "rev": 42}
```
- **Merge, never delete.** Same id = update. Items without an id get one made from their content, so
  re-sending the same batch after a timeout is safe: the second time everything is `unchanged`.
- **Duplicates are skipped and reported**, never deleted: events on the same day with nearly the same
  title (same words, ignoring case, punctuation and order) and within 90 minutes; inbox items with the same
  sender and subject; open tasks with the same title and due date. When an import itself has two copies,
  the one with a time that isn't superseded is kept.
- `"dryRun": true` reports what would happen without changing anything.
- The whole import is one entry in the change log and can be undone in one step.
- Field names: tasks `title, due, note`; events `title, start, end, note, source`; inbox `subject` (or `t`),
  `from` (or `sender`), `account` (or `f`), `body` (or `b`), `gist`, `priority`.

## Undo and "changed by"
Every change made through the server is logged in the doc (`state.log`, last 100) with who made it, which key,
and the ops that undo it. Items carry `changedBy` / `changedAt`. In the app, Today shows
"FRIDAY made 3 changes" with **Review** and **Undo all**, Activity has **Undo** on each change, and tasks and
events show a "Changed by" label.

```
POST /api/lifeos {"undo": "<log id or batch id>"}      or {"undo": ["log-…", "log-…"]}
```
Write keys can undo their own changes; admin keys can undo anyone's. Undoing is logged too and can itself be undone.

## Keeping Today fresh
Call `POST /api/pulse` every 1–2 hours with the header `Authorization: Bearer <a write key>`.
On cron-job.org: Advanced › Headers › add `Authorization` = `Bearer <key>` (the old `?key=` URL no longer works).
Or use Vercel Cron (`vercel.json` crons + a `CRON_SECRET` env var, which Vercel sends as the bearer token);
note that Vercel's free plan runs crons once a day.

## Advanced
- `GET /api/lifeos` reads the whole doc (read key). `?view=summary` plain text, `?view=ops` the op list,
  `?view=duplicates` likely duplicates already in the doc, `?since=<rev>` returns `{"unchanged":true}` if nothing changed.
- `POST /api/lifeos {"ops":[…]}` applies exact ops (see `api/_core.mjs`), 1–200 per call.
- `PUT /api/lifeos {"doc":{…}}` replaces everything (admin only). To add to what's there, use `/api/import`.
- Writes are conflict-safe: a save only lands if nobody else saved since it was read, otherwise it's
  re-applied on the fresh copy, so two assistants writing at once never overwrite each other.

## Tests
`cd server && npm test` (Node 20+, no other setup: tests use an in-memory store and a fake Gemini).
