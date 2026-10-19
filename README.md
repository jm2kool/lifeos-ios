# LifeOS for iPhone

Native SwiftUI app for iOS 26 with Liquid Glass: Today (Gemini brief, day timeline, countdown, focus,
streak), Inbox with Gemini reply drafts, Study (focus timer, coverage), Library (Board, Drafts, Calendar,
Timetable, Feed, Saved, Finances, Workflows), search, and a Gemini assistant that can change anything
(with undo).

## Install with Sideloadly
1. Download **LifeOS.ipa** from the [latest release](../../releases/latest).
2. Open Sideloadly, plug in your iPhone, drag the .ipa in, enter your Apple ID, Start.
3. On the iPhone: Settings › General › VPN & Device Management › trust your Apple ID.
   (iOS 16+: also turn on Settings › Privacy & Security › Developer Mode.)
4. Open LifeOS, import your data file, and paste your Gemini key in Settings.

Free Apple IDs re-sign every 7 days (Sideloadly can auto-refresh). Requires iOS 26.

## Voice capture
Tap the mic at the top of any tab and speak. Gemini decides what it is and files it: a to-do, an email draft
(it waits in Drafts for you; nothing is ever sent), a calendar event, a timetable block, a note, a link or a board card.
A short confirmation says what it did, with Undo. For calendar events you also get a ready-made message asking your
iMessage assistant (FRIDAY) to add it to Google Calendar. If Gemini isn't sure, or doesn't answer, it's still filed
and the review dot lights up.

**Without opening the app**
- Siri: "Capture in LifeOS". Siri asks what to capture and listens; you stay where you are.
- Action Button (and a Lock Screen or Control Centre button): in Shortcuts make a new shortcut with
  1. **Dictate Text** (stop listening: After Pause)
  2. **Capture with LifeOS**, with Text = *Dictated Text*
  3. **If** *Capture with LifeOS* **has any value** → **Send Message** (*Capture with LifeOS*) to FRIDAY → **End If**

  Then Settings › Action Button › Shortcut › pick it. You get the small dictation bubble, stay in your current app,
  and LifeOS files it in the background and shows what it did.

## Build
Every push to `main` builds an unsigned .ipa on GitHub Actions (`.github/workflows/build.yml`)
and attaches it to the `latest` release. No local Xcode needed.

## Server (optional)
See `server/README.md` for sync and for letting your iMessage assistant update LifeOS.
