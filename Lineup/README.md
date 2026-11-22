# Lineup

Your school timetable on your Apple Watch. Open the app on your wrist and you see the lesson on now, then the
rest of the day a page at a time.

Everything is stored on your iPhone and watch. There is no account, and nothing needs the internet: the phone
hands the watch a copy over Bluetooth, and the watch keeps it, so it still works with your phone left at home.

## On the watch

| Page | What it shows |
|---|---|
| **Lessons** | One page per lesson today, opening on the one on now (or next). Subject, room, teacher, time left, and what to bring. Earlier lessons sit above, dimmed. |
| **Next** | Swipe up, turn the Digital Crown, or **double-tap your finger and thumb** (Series 9, Ultra 2 and later) to go to the next lesson. On the last page it jumps back to now. |
| **Homework** | Everything still to do, soonest first. Tap to tick it off; your phone catches up next time it's in range. |
| **Pack for tomorrow** | Each subject on the next school day with the things to bring, to tick off as you pack, and any homework to hand in. Before school starts it shows today's instead. |

## On the iPhone

| Tab | What it does |
|---|---|
| **Today** | The same view as the watch, bigger. |
| **Week** | Add lessons day by day. New lessons start when the last one ends, you can reuse bell times from other lessons, and copy a whole day to another. |
| **Homework** | Grouped into overdue, today, tomorrow, this week and later. A new piece of homework is due the next lesson of that subject unless you change it. |
| **Subjects** | Name, usual room, teacher, colour, and things to bring to every lesson. |
| **Settings** | School days, Week A / Week B timetables, an optional heads-up before each lesson (shows on the watch too), and the watch's sync status. |

## Building

`project.yml` is an XcodeGen spec with two targets: the iPhone app (`iOS/`) and the watch app (`Watch/`), which share
`Shared/Timetable.swift`. `.github/workflows/lineup.yml` builds an unsigned `.ipa` with the watch app inside and puts it
in a draft release called "Lineup (latest build)". Install it with Sideloadly; the watch app then shows up in the
Watch app on your iPhone under Available Apps.
