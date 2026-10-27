# Matinee — notes for working on this repo

Matinee is a SwiftUI film and TV diary for iOS 26 (see README.md). There is no Mac in the cloud sessions:
CI (`.github/workflows/build.yml`) compiles every push to `matinee`/`main` and publishes the `.ipa`, so
check the "Build IPA" run after pushing and fix any compile errors it reports.

## Every change updates the changelog and the tour

This is a standing rule from the owner. Whenever you add or change something users can see:

1. Add an entry to `Matinee/App/Changelog.swift` → `Changelog.releases`. Put the newest release **first**.
   Either add items to the current release (if it hasn't shipped yet) or start a new one with the next version.
2. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` to match the new release.
3. Give each item a tour page: an SF Symbol, a short title, a one- or two-sentence `detail` in plain words, and an
   `action` (`TourAction`) when there's a screen to try it on. People who update see these pages as the
   What's New tour; Settings → What's new lists every release.
4. If the change affects the welcome tour for new people (`Tour.welcomePages`), update that too.
5. Mention new features in README.md's table.

## Conventions

- Swift 5 language mode; UI and stores are `@MainActor`. Match the surrounding comment style: short `///` doc
  comments that say what something is for, in plain British English.
- On-device Apple Intelligence goes through `Matinee/Services/Intelligence.swift` (and `Finder.swift`), always behind
  `#if canImport(FoundationModels)` and `Intelligence.isAvailable`, with a non-AI fallback.
- Optional server features (follows, activity, parties) degrade gracefully when their tables are missing.
