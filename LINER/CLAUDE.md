# LINER. — notes for working on this folder

LINER. is a separate app from Matinee (the rest of this repo). `SPEC.md` is the source of truth; build one phase at a time.

- Free signing only: MediaPlayer framework, never MusicKit or the Apple Music API. One app extension:
  `LINERWidgets` (the live lyrics Live Activity), sharing `Shared/LyricsActivity.swift` with the app.
- Swift 6 language mode. UI and stores are `@MainActor`. Callbacks that the system calls on its own queues
  (MediaPlayer artwork handlers, notifications, remote commands) are `@Sendable` closures that hop back to the
  main actor. MediaPlayer is imported with `@preconcurrency`.
- No Mac in cloud sessions: `.github/workflows/liner.yml` builds every push touching `LINER/` and publishes
  the `.ipa` as the `liner-latest` release. Check the run and fix any errors or warnings.
- Keep files under 300 lines, one feature per folder, and a preview with `PreviewData` for every view.
- The Phase 0 spike lab lives in `Spikes/` and is reachable from Settings → Spike lab.

## Before you start, and before you finish

Several chats work on LINER. at once, each on its own `claude/...` branch, and every one of them publishes the same
`liner-latest` build. A fix that only lives on one chat's branch disappears the next time another chat pushes.

- `LINER` is the trunk. Before changing anything, `git fetch origin` and merge `origin/LINER` and every
  `origin/claude/*` branch that has LINER/ commits yours doesn't
  (`git rev-list --count HEAD..origin/<branch> -- LINER`). Never start from a base that lacks them.
- When the work is done, ask the owner to merge your branch into `LINER` (or do it if they've said you may).
- The build number in `project.yml` only goes up: take the highest one on any branch and add one.

These have been fixed and lost more than once. Check they're still true after any merge:

- `GlassCircleButton` has `.contentShape(.circle)`, so the whole circle takes the tap.
- The Listening Room's X calls `onClose()` (the crate's own `room = false`) as well as `dismiss()`.
- `GatefoldView.close()` works at any point: nothing but `closing` guards it, and `open()` stops when `closing` is set.
- Listening Room moves go through `RoomStep.run` (timer-backed), never a bare `withAnimation … completion:`.
- No `Dictionary(uniqueKeysWithValues:)` anywhere: two songs can share an ID, and that traps just after the intro.
