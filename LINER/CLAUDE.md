# LINER. — notes for working on this folder

LINER. is a separate app from Matinee (the rest of this repo). `SPEC.md` is the source of truth; build one phase at a time.

- Free signing only: MediaPlayer framework, never MusicKit or the Apple Music API. No app extensions.
- Swift 6 language mode. UI and stores are `@MainActor`. Callbacks that the system calls on its own queues
  (MediaPlayer artwork handlers, notifications, remote commands) are `@Sendable` closures that hop back to the
  main actor. MediaPlayer is imported with `@preconcurrency`.
- No Mac in cloud sessions: `.github/workflows/liner.yml` builds every push touching `LINER/` and publishes
  the `.ipa` as the `liner-latest` release. Check the run and fix any errors or warnings.
- Keep files under 300 lines, one feature per folder, and a preview with `PreviewData` for every view.
- The Phase 0 spike lab lives in `Spikes/` and is reachable from Settings → Spike lab.
