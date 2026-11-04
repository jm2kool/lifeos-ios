# Lumen

A study planner for iPhone, run by your AI assistant **Instinct**. You add assignments and exams (so can Instinct);
Instinct plans study blocks around your timetable, sees what you actually got done and replans. Lumen is where you see
the plan, focus, review flashcards and track your syllabus.

SwiftUI for iOS 26 with Liquid Glass, true black, local-first SwiftData synced to Supabase, Google sign-in, and an API
with per-assistant access keys. Built as an unsigned `.ipa` by GitHub Actions for Sideloadly or AltStore.

| | |
|---|---|
| **Today** | The next block with Start focus, Instinct's proposed plan (Accept / Edit / Reject), outcomes to fill in, today's timeline, what's due, cards due, minutes and streak, and a quick-add bar that understands "physics worksheet ch 3 due fri 2h". |
| **Planner** | A week strip and day timeline with blocks laid over busy times, every assignment by due date, and the activity feed of everything Instinct added, moved or deleted, each batch with Undo. The wand runs the built-in auto-planner (deadline + priority + effort) when Instinct is offline. |
| **Focus** | Pomodoro with your lengths, pre-filled from a block. At the end: done / partly / not done and a note, which goes to Instinct. Live Activity and Dynamic Island, stats (minutes per day, subject and week, streak, plan kept). |
| **Study lock** | LifeOS's way of blocking apps: a Shortcuts automation runs *Study lock check* when you open a distracting app, and during a study block or focus round you're sent straight back to a full-screen lock (with a five-minute break button). Works with a free Apple ID. A Screen Time shield is there too for builds that have Apple's entitlement. |
| **Dynamic Island** | Two Live Activities: the focus timer (pause / end), and your **study block** — from 10 minutes before (countdown), during (goal and time left), the break after, and done — with Start focus, Done and Skip buttons. The app starts it when it runs; with push, the server starts it before each block even if Lumen hasn't been opened; a *Show next study block* Shortcut does it without push. |
| **Cards** | Decks per subject and chapter, text, images and formulas (`$E = mc^2$`), FSRS spaced repetition with Again / Hard / Good / Easy, and AI cards from pasted notes, a PDF, a photo or a page scan — written by **Claude** (the `lumen-ai-cards` function), falling back to Apple Intelligence on the iPhone. |
| **Syllabus** | Subjects → chapters → topics with not started / learning / revised / mastered and progress rings, linked to assignments, decks and focus time. |
| **Settings** | Account and sync, subjects, planning preferences (max hours a day, block and break length, no-study days, earliest/latest), free and busy times, iPhone calendar (busy times only unless you allow titles), Instinct's plan mode (auto-apply or ask first), access keys, webhook, Pomodoro, flashcards and notifications. |
| **Widgets** | Up next, Today (minutes, streak, cards due) and Next deadline, on the Home and Lock Screens. |
| **Notifications** | Block starts (with a Start focus button), a 10-minute warning, deadlines a day and 2 hours before, and a daily review reminder — rescheduled whenever the plan changes. **Push** (APNs): when Instinct has a new plan or adds work you get a notification straight away, and silent pushes keep reminders in step. |
| **Instinct API** | `lumen-agent`: one-call context, plans with validation, CRUD for assignments, blocks, decks, cards and syllabus, an events feed and an outgoing webhook. See [docs/INSTINCT.md](docs/INSTINCT.md) and [docs/openapi.yaml](docs/openapi.yaml). |

## How it fits together

```
iPhone (SwiftData, works offline)  ⇄  Supabase  ⇄  Instinct
   │  push changes, pull by rev          │  lumen schema (RLS: your rows only)
   │  Realtime while open                │  lumen-agent  ← Authorization: Bearer lmn_…
   │  Background App Refresh             │  lumen-ai-cards ← signed-in app
   └─ widgets via App Group (or server)  └─ events → webhook (pg_net)
```

- **Sync.** Every row carries `updated_at` and a server-stamped `rev`. The app sends what changed, then pulls every row
  with a higher `rev` than it last saw. The newer `updated_at` wins; Instinct's writes always win and use the server's
  clock. Deletes are soft so every device hears about them.
- **Events.** Database triggers write `lumen.events` when you finish, miss or skip a block, log focus time, add or finish
  work, change a topic, or accept or reject a plan. Instinct reads them from `/events`, and they can be POSTed to a
  webhook.

## Set up

You're reusing the Supabase project from Matinee, so Google sign-in is already switched on there.

### 1. Supabase

1. **SQL.** Open *SQL Editor*, paste [`supabase/migrations/20261104000000_lumen.sql`](supabase/migrations/20261104000000_lumen.sql)
   and run it. It only creates things in a new `lumen` schema (plus a private `lumen-files` storage bucket), and it's
   safe to run again.
2. **Expose the schema.** *Project Settings → Data API → Exposed schemas* → add **`lumen`** → Save.
3. **Redirect URL.** *Authentication → URL Configuration → Redirect URLs* → add **`lumen://auth-callback`**.
4. **Edge Functions.** With the [Supabase CLI](https://supabase.com/docs/guides/cli):
   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase functions deploy lumen-agent --no-verify-jwt   # Instinct uses Lumen keys, not Supabase JWTs
   supabase functions deploy lumen-ai-cards
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-…          # optional LUMEN_AI_MODEL=…
   ```
   (Or in the dashboard: *Edge Functions → Deploy a new function*, paste the files, and turn **Verify JWT off** for
   `lumen-agent`.) `lumen-ai-cards` is Lumen's main AI: Claude (`claude-opus-5-5`), with Anthropic's server-side refusal
   fallback switched on. If it can't be reached (offline, signed out, no key), the app uses Apple Intelligence on the
   iPhone, and with neither, simple "term: meaning" rules.
5. **Realtime** is turned on for the Lumen tables by the SQL. If you ever see "realtime for …" notices, check
   *Database → Publications → supabase_realtime* includes the `lumen` tables.

### 1b. Push notifications (optional — needs a paid Apple Developer account)

APNs only delivers to an app whose provisioning profile includes push, and only with a key from a paid Apple Developer
account. A free Apple ID can't do either, so Lumen falls back to Realtime and Background App Refresh.

1. In SQL Editor run [`supabase/migrations/20261104120000_lumen_push.sql`](supabase/migrations/20261104120000_lumen_push.sql).
2. developer.apple.com → *Certificates, IDs & Profiles → Keys → +* → tick **Apple Push Notifications service (APNs)** →
   download the `.p8`. Note the **Key ID** and your **Team ID** (top right).
3. ```bash
   supabase secrets set APNS_KEY_ID=XXXXXXXXXX APNS_TEAM_ID=YYYYYYYYYY APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
   supabase secrets set LUMEN_CRON_SECRET=$(openssl rand -hex 24)
   supabase functions deploy lumen-agent --no-verify-jwt
   supabase functions deploy lumen-push --no-verify-jwt
   ```
4. For the study-block Live Activity before each block, open [`supabase/push_cron.sql`](supabase/push_cron.sql), put your
   `LUMEN_CRON_SECRET` in place of the placeholder and run it (it calls `lumen-push` every minute with pg_cron).
5. Install **`Lumen.ipa`** (it asks for push) with the paid Apple ID. Settings → Notifications → *Push from the server*
   shows whether it's on. Each iPhone reports its own bundle id and APNs environment, so re-signed bundle ids work.

### 2. Google Cloud

**Nothing new.** Lumen signs in through Supabase's Google provider in a secure browser sheet (OAuth with PKCE), the same
way Matinee does, so Google only ever redirects to your Supabase callback (`https://<ref>.supabase.co/auth/v1/callback`),
which your existing **Web** OAuth client already allows. No iOS client ID or URL scheme is needed in Google Cloud. (You
would only need an iOS client ID with Google's native sign-in SDK, which Lumen doesn't use.)

If you later move Lumen to a different Supabase project, enable Google there with the same Web client ID and secret, and
add that project's callback URL to the Web client's *Authorised redirect URIs*.

### 3. GitHub

The workflow reads the Supabase address and anon key from repository secrets and writes them into
`Config/Secrets.xcconfig`, which is baked into the app's Info.plist:

- It uses **`SUPABASE_URL`** and **`SUPABASE_ANON_KEY`** (already set for Matinee — same project), or
  **`LUMEN_SUPABASE_URL`** and **`LUMEN_SUPABASE_ANON_KEY`** if you add those to override them.
- Without secrets the app still builds and asks for the address and key on the sign-in screen (*Server settings*).

Every push to the `lumen` branch builds the app (≈3 minutes on `macos-26` with Xcode 26), then takes simulator
screenshots of every screen with sample data (artifact **lumen-screens**). A second, cheap Ubuntu workflow tests the SQL
migration on Postgres, the Edge Functions with Deno, and the planner, quick-add parser and FSRS in Swift.

### 4. Install the app

1. GitHub → **Releases** → **Lumen (latest build)** → download **`Lumen.ipa`** if your Apple ID has push (a paid developer
   account), or **`Lumen-no-push.ipa`** for a free Apple ID.
   This repository is public, so the release is a **draft** that only you can see (the `.ipa` contains your Supabase
   address and anon key). It's also on the run's page under *Artifacts → Lumen-ipa*.
2. Install with [Sideloadly](https://sideloadly.io) (or AltStore) and your Apple ID.
   In Sideloadly's advanced options leave **"Remove app extensions"** off so the widgets and Live Activity stay.
3. On the iPhone: *Settings → General → VPN & Device Management* → trust your Apple ID, and turn on
   *Settings → Privacy & Security → Developer Mode* if asked.
4. Open Lumen → **Continue with Google**. Allow notifications. Add your subjects (Syllabus → +) and your free times
   (Settings → When you're free), and switch on the iPhone calendar if you want class and plans kept clear.

### 5. Study lock (blocking apps)

Settings → Focus → **Study lock** walks you through it: Shortcuts → Automation → **App** → pick the distracting apps →
*Is Opened* → *Run Immediately* → add Lumen's **Study lock check**. During a study block or focus round, opening one of
those apps brings you straight back to Lumen's lock screen; outside study time nothing happens. For the Dynamic Island
without push, add a *Time of Day* automation that runs **Show next study block** shortly before your usual blocks.

### 6. Connect Instinct

1. Lumen → Settings → **Instinct → Assistants & access keys → New access key**. Name it "Instinct", choose what it may
   do, and **copy the key** — it's shown once (Lumen stores only its SHA-256 hash). *Copy setup* gives you a short note
   with the address and key.
2. Paste the message from **Copy setup** (or [docs/INSTINCT-PROMPT.md](docs/INSTINCT-PROMPT.md) with your key filled in)
   into Instinct. The address is `https://pryljjakjcswekcwxcog.supabase.co/functions/v1/lumen-agent`; the full guide is
   [docs/INSTINCT.md](docs/INSTINCT.md) and [docs/openapi.yaml](docs/openapi.yaml).
3. Choose **Auto-apply** or **Ask me first** under Settings → Instinct.
4. Optional: Settings → Instinct → **Webhook** — an address that receives each event as it happens, signed with
   `X-Lumen-Signature: sha256=<HMAC-SHA256 of the body with your secret>`.

Revoke a key by swiping it in the same list; it stops working immediately.

## Free Apple ID notes

- **7 days:** a free Apple ID's apps expire after a week — re-install from Sideloadly (your data is safe in Supabase
  and in the app). At most 3 sideloaded apps at once, and each app plus its widget extension uses 2 of your 10 App IDs a week.
- **App Group** (`group.com.jm2kool.lumen`) is how the widgets read your plan. Sideloadly usually keeps it; if a
  re-signer drops it, the widgets fall back to fetching the same snapshot from Supabase (Settings → About shows which).
- **Live Activities, local notifications, Background App Refresh, calendar access and the study lock** all work with a
  free Apple ID. **Push** needs a paid one (see 1b); without it the plan refreshes via Realtime while the app is open
  and Background App Refresh otherwise — make sure it's on for Lumen — and use `Lumen-no-push.ipa`.
- **Focus shield (Screen Time)** needs Apple's Family Controls entitlement, which free accounts can't get. Lumen reads
  its own provisioning profile at launch and hides the option when the entitlement isn't there, so nothing breaks. The
  study lock does the same job without it.
- **Apple Intelligence** is the fallback for AI cards when Claude can't be reached; it needs an iPhone 15 Pro or newer.

## Project layout

```
project.yml                     XcodeGen spec (app + one widget extension)
Config/                         Info.plist, entitlements, Lumen.xcconfig (+ Secrets.xcconfig from CI)
Lumen/App/                      App entry, lifecycle, router, demo data for screenshots
Lumen/Model/                    SwiftData models (one per lumen table) and enums
Lumen/Sync/                     Supabase auth (Google, PKCE), REST client, sync engine, Realtime, store
Lumen/Services/                 Focus timer, notifications, calendar, Screen Time, widgets, files, AI cards
Lumen/Services/Core/            Plain-Swift logic: FSRS, quick-add parser, auto-planner (tested on Linux)
Lumen/Views/                    Today, Planner, Focus, Cards, Syllabus, Settings, sheets, theme
LumenWidgets/                   Widgets and the focus Live Activity
Shared/                         Code shared by the app and widgets
supabase/migrations/            The SQL migration
supabase/functions/             lumen-agent (Instinct API), lumen-ai-cards (Claude), lumen-push (Live Activities by push), _shared
supabase/tests/                 Agent API tests (Deno) and SQL checks
tests/core/                     Swift tests for the plain logic
docs/                           INSTINCT.md, INSTINCT-PROMPT.md (the message to paste) and openapi.yaml
```

## Developing

- `supabase/tests/sql/run.sh` with `PGHOST`/`PGUSER` set runs the migration twice on a plain Postgres and checks
  row-level security, last-write-wins, Instinct and system writes, events, webhooks and plans.
- `deno test supabase/tests/` tests the agent API against an in-memory database.
- `swiftc tests/core/main.swift Lumen/Services/Core/*.swift -o coretest && ./coretest` tests the planner, parser and FSRS.
- Launch the app with `LUMEN_DEMO=1` for sample data without an account (`LUMEN_TAB`, `LUMEN_SHEET` pick a screen).
