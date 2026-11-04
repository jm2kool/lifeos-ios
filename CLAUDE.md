# Lumen — notes for working on this branch

Lumen is a SwiftUI study planner for iOS 26 (see README.md), on the `lumen` branch of this repository (the other branches
hold Matinee and LifeOS). There is no Mac in the cloud sessions: `.github/workflows/build.yml` compiles every push to
`lumen`, publishes the `.ipa` as the draft release "Lumen (latest build)", and uploads simulator screenshots as the
`lumen-screens` artifact. Check the "Build Lumen IPA" run after pushing and fix any compile errors it reports;
look at the screenshots after UI changes.

## Conventions

- Swift 5 language mode; UI and stores are `@MainActor`. Short `///` doc comments that say what something is for, in
  plain British English.
- Dark only, true black (`Color.black`) under everything; Liquid Glass via `.glassEffect`, `GlassEffectContainer`,
  `.buttonStyle(.glass / .glassProminent)` and `glassEffectID`. Use the helpers in `Views/Theme.swift`
  (`glassCard`, `backdrop`, `InstinctBadge`, `Fmt`, `Haptics`).
- Every synced model has the `Synced` fields (`updatedAt`, `trashed`, `dirty`, `createdBy`, `updatedBy`, `reason`) and
  maps 1:1 to a table in `supabase/migrations`. Change a model and its table together, keep `fields()`/`apply(_:)` in
  step, and never hard-delete synced rows (set `trashed` and `touch()`).
- Writes go through `Store` (`insert`, `touch`, `save`) so sync, notifications and widgets follow.
- Anything Instinct made or changed shows `InstinctBadge` (`byInstinct`).
- Apple Intelligence goes through `CardMaker`, behind `#if canImport(FoundationModels)` and an availability check,
  with a non-AI fallback.
- Logic that doesn't need UIKit/SwiftUI lives in `Lumen/Services/Core/` and is tested on Linux (`tests/core`).
- The agent API (`supabase/functions/lumen-agent`) must keep `docs/openapi.yaml` and `docs/INSTINCT.md` in step, and
  its tests (`deno test supabase/tests/`) green.
