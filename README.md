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

## Build
Every push to `main` builds an unsigned .ipa on GitHub Actions (`.github/workflows/build.yml`)
and attaches it to the `latest` release. No local Xcode needed.

## Server (optional)
See `server/README.md` for sync and for letting your iMessage assistant update LifeOS.
