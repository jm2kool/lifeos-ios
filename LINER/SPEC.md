# LINER. — Build Spec

> Working name: **LINER.** (as in liner notes, your notes on the music). It's a personal, artwork‑first Apple Music companion for iPhone, inspired by @sakisgraphics' "MONO." concept.
> Owner: Jash. Distribution: **sideloaded .ipa built by GitHub Actions** (same pipeline as Matinee and the study app). Not for the App Store.
> Rename anytime: the name lives in one constant, `AppBrand.name`, plus the display name in `project.yml`.

This file is the single source of truth for the coding agent. Read all of it before writing code. Build **one phase at a time** (§10), make sure it compiles, then stop and report.

---

## 0. What the app is

The app reads the user's Apple Music library and rebuilds it around their personal history with each artist, album and song. That history comes from play counts, ratings, moods, notes, rankings, custom editions and recaps.

On top of that it adds:
- full‑screen artwork everywhere, including the lock screen
- sing‑along lyrics
- on‑device AI mood playlists
- Instagram share cards
- imported "mixtapes" (your own audio files)
- a Vinyl Mode inspired by MD Vinyl

Visual language: OLED black, an editorial serif for titles, tiny letter‑spaced caps for labels, monochrome UI where colour comes only from artwork, and **iOS 26 Liquid Glass** for every control surface.

Minimum target: **iOS 26.0**, iPhone only, portrait only (Vinyl Mode may allow landscape later).

---

## 1. Feasibility: read this first

| Feature | Status | How |
|---|---|---|
| Read library, play counts, metadata, artwork | ✅ Works with any signing | `MediaPlayer` (`MPMediaQuery`, `MPMediaItem.playCount`, `.composer`, `.genre`, `.albumTrackNumber`, `.releaseDate`, `.lastPlayedDate`, `.dateAdded`, `.artwork`) |
| Play library songs in‑app | ✅ (confirm in Phase 0 on free signing) | `MPMusicPlayerController.applicationQueuePlayer` (MediaPlayer). No MusicKit (no paid account) |
| Artist portraits (B&W hero) | ✅ via Deezer | Deezer public API `picture_xl` (no key), cached, then desaturated in‑app. Apple's own artist art would need a paid account |
| Weekly/monthly/yearly recaps | ⚠️ Works from install day forward | Apple gives **cumulative** play counts only. Daily snapshots plus in‑app play log give per‑period plays. No history before install |
| Synced sing‑along lyrics | ✅ via third party | Apple Music lyrics aren't exposed to 3rd‑party apps. Use **LRCLIB** (`https://lrclib.net/api/get`), which is free and needs no key, and parse `syncedLyrics` (LRC) |
| Always full‑screen artwork in app | ✅ | Our own UI, so we just do it |
| Animated covers in app, even in Low Power Mode | ✅ | Our own `AVPlayerLayer` loop. We ignore `isLowPowerModeEnabled` (user's explicit choice) |
| Apple Music's official motion artwork | ❌ Not available | Apple doesn't expose `editorialVideo` to 3rd‑party apps. Instead, the user attaches their own motion cover (mp4/mov/gif), or the app generates a "Living Cover" from the still image |
| Full‑screen lock screen artwork for every song | 🧪 Spike first | iOS 26 lets apps provide `MPMediaItemAnimatedArtwork` under `MPNowPlayingInfoProperty3x4AnimatedArtwork` (tall, full‑screen). We supply a looping video for **every** track, either the real motion cover or a generated Living Cover, which should force the full‑screen layout. **Works for mixtapes (our AVPlayer).** For Apple Music tracks it only works if the system lets us add keys while the MediaPlayer/MusicKit queue player owns Now Playing, which is unconfirmed. Phase 0 tests this |
| Lock screen animation in Low Power Mode | ❌ Impossible | Apple shows the static preview image in Low Power Mode, Low Data Mode, high thermal state and Reduce Motion. No override exists. The **in‑app** player still animates |
| AI mood playlists | ✅ on capable devices | `FoundationModels` (iOS 26, Apple Intelligence device and setting). The on‑device model has a **~4K token** context, so it never sees the whole library. See §6.12 |
| Instagram Stories share (image + video) | ✅ | `instagram-stories://share?source_application=<FB_APP_ID>` plus pasteboard. **Reuse Matinee's Facebook App ID.** Video must be ≤20s, ≤1080p, H.264 |
| Import audio (SoundCloud downloads, mp3/m4a/mp4/wav) | ✅ | `.fileImporter` + "Open in LINER" document types. Audio is extracted from video containers with `AVAssetExportSession` |
| Mixing Apple Music + imported files in one queue | ✅ but complex | Two engines behind one `PlaybackCoordinator` (§5) |

### Signing: DECIDED, free path
Jash has **no paid Apple Developer account**, so:
- **No MusicKit.** Don't import MusicKit, don't use `ApplicationMusicPlayer`, and don't call the Apple Music API. Use the MediaPlayer framework only.
- Library playback uses `MPMusicPlayerController.applicationQueuePlayer`.
- Artist images come from the Deezer public API (no key), cached and desaturated.
- The app is free‑signed, so it re‑signs every 7 days and gets **no app extensions** (no widgets, share extension or Live Activities).
- Keep catalog lookups behind a `CatalogProvider` protocol so a paid path could be added later. Build only the Deezer implementation now.

---

## 2. Tech stack and repo layout

- Swift 6, SwiftUI, iOS 26 SDK, Xcode 26.
- **XcodeGen** (`project.yml`). Never hand‑edit `.pbxproj`.
- SwiftData for all user‑generated data.
- Frameworks: MediaPlayer, AVFoundation, AVKit, FoundationModels, CoreImage, Vision (subject masks for Living Covers), PhotosUI, UniformTypeIdentifiers, BackgroundTasks.
- **No app extensions in v1.** They cost extra App IDs on free signing. Use document types instead of a share extension.
- CI: GitHub Actions on a macOS runner with Xcode 26 runs `xcodegen` → `xcodebuild archive CODE_SIGNING_ALLOWED=NO` → zip `Payload/LINER.app` into `LINER.ipa` → upload artifact. Copy the workflow from Matinee/study‑app if present.

```
LINER/
  project.yml
  .github/workflows/build.yml
  App/                LINERApp.swift, RootView.swift, AppBrand.swift
  DesignSystem/       Colors, Typography, Glass, Components (Card, StatTile, SectionLabel, HeartRating, ChipGrid)
  Library/            LibraryService (MediaPlayer), CatalogProvider (+Deezer), ArtworkCache
  Playback/           PlaybackCoordinator, MusicEngine, LocalEngine, NowPlayingManager, LivingCoverRenderer
  Stats/              StatsEngine, SnapshotService, PlayLog, RecapBuilder
  Features/
    Home/ Library/ Artist/ Album/ Player/ Lyrics/ SongPassport/ AlbumPassport/
    Editions/ Pins/ MyStats/ Recaps/ Mixtapes/ Vinyl/ MoodPlaylists/ Share/ Settings/
  Models/             SwiftData @Model types (§4)
  Resources/          Assets, sounds (needle drop, crackle), Info.plist bits
```

Info.plist needs:
- `NSAppleMusicUsageDescription`
- `UIBackgroundModes: [audio, fetch, processing]` and `BGTaskSchedulerPermittedIdentifiers`
- `LSApplicationQueriesSchemes: [instagram-stories]`
- `CFBundleDocumentTypes` (audio + mpeg4 movie) with `LSSupportsOpeningDocumentsInPlace = NO`
- `UIFileSharingEnabled`
- `NSPhotoLibraryAddUsageDescription`

---

## 3. Design system

**Feel:** OLED‑black gallery. The artwork is the colour; everything else is monochrome.

- **Background:** `#000000`. Cards are `#0E0E0E` → `#161616` with a 1px `white.opacity(0.06)` stroke and 22pt continuous corners.
- **Type:**
  - Display and titles use the system **serif** (New York): `.font(.system(size:, design: .serif))`. Artist names are 44–56pt, album and song titles 28–34pt, section titles like "My Top Songs" 26pt.
  - Labels are SF Pro 10–11pt **uppercase, tracking 2–3pt, 55% white** (e.g. `MOST PLAYED ARTIST`, `YOUR LISTENING HISTORY`).
  - Numbers in stat tiles use serif 30–34pt with grouped digits. Use the user's locale; Jash is in India, so `11,557`, not MONO's German `11.557`.
- **Artist portraits:** desaturated (CIPhotoEffectNoir or saturation 0 + contrast 1.1) with a bottom gradient to black.
- **Liquid Glass (the upgrade over MONO):**
  - Native `TabView` (auto glass tab bar) with `.tabBarMinimizeBehavior(.onScrollDown)`.
  - The mini player goes in **`.tabViewBottomAccessory`**, Apple‑Music style.
  - Floating buttons (back, •••, play/shuffle row, passport, heart) use `.glassEffect(.regular.interactive(), in: .circle)` or `.buttonStyle(.glass)`. Group adjacent ones in `GlassEffectContainer` so they morph.
  - Sheets (Passports, Editions, Ranking) use the default iOS 26 glass sheets at `.presentationDetents([.medium, .large])`.
  - The player controls cluster sits on glass tinted by the artwork's dominant colour: `.glassEffect(.regular.tint(dominant.opacity(0.25)))`.
- **Motion:** Use `matchedGeometryEffect` / `.navigationTransition(.zoom(sourceID:in:))` from artwork tiles to album and player. Use spring `(response 0.45, damping 0.85)`. Haptics go on rating taps, reorder and needle drop.
- **Rating:** 5 hearts (filled white / outlined 30%).

---

## 4. Data model (SwiftData)

Media identity can't be a single ID. `MPMediaItem.persistentID` can change after iCloud Library re‑syncs. Store a `MediaKey`:

```swift
struct MediaKey: Codable, Hashable {
  var persistentID: UInt64
  var storeID: String?   // playbackStoreID if non-empty
  var title: String; var artist: String; var album: String; var duration: Double
}
```

Resolve with `persistentID` → `storeID` → fuzzy (normalized title + artist + album, duration ±2s).

```swift
@Model SongNote        // Song Passport
  key: MediaKey; rating: Int?  // 1–5
  moods: [String]; notes: String; connection: String
  favoriteMoments: [Moment]   // Moment {seconds: Double, name: String}
  lyricLines: [String]        // saved lyric lines (from Lyrics view)
  updatedAt: Date

@Model AlbumNote       // Album Passport
  albumKey: AlbumKey   // albumPersistentID + title + albumArtist
  rating: Int?; personalRanking: [MediaKey]
  pinned: Bool; pinnedAppearance: PinAppearance // .artistPortrait | .albumArtwork
  motionCover: URL?    // user-attached video, stored in App Support
  coverOverride: Data? // still image

@Model Edition         // Personal Editions (album OR mixtape based)
  id: UUID; baseAlbumKey: AlbumKey?; title: String
  tracks: [EditionTrack]   // enum: .library(MediaKey) | .mixtape(UUID)
  coverImage: Data?; motionCover: URL?; isActive: Bool; createdAt: Date

@Model Mixtape         // standalone imported "album"
  id: UUID; title: String; artist: String; label: String?; year: Int?
  coverImage: Data?; motionCover: URL?; tracks: [MixtapeTrack]; showInHome: Bool
@Model MixtapeTrack
  id: UUID; title: String; artist: String; fileURL: URL (relative to App Support/Mixtapes)
  duration: Double; trackNumber: Int; lyricsLRC: String?

@Model PlaySnapshot    // one row per (date, song) only when count changed
  date: Date; key: MediaKey; playCount: Int
@Model PlayEvent       // in-app log
  key: MediaKey? ; mixtapeTrackID: UUID?; startedAt: Date; listenedSeconds: Double; completed: Bool

@Model PinnedPlaylist  playlistPersistentID: UInt64, appearance
@Model MoodPlaylist    id, name, prompt, recipe(JSON), tracks:[MediaKey], createdAt, autoRefresh: Bool
@Model LyricsCache     key: MediaKey, lrc: String?, plain: String?, fetchedAt
@Model ArtistImage     artistName (normalized), url, localPath, source
```

User files (mixtape audio, motion covers, generated Living Covers) live in `Application Support/LINER/…`, excluded from iCloud backup except Mixtapes.

---

## 5. Playback architecture

```
PlaybackCoordinator (@Observable, single source of truth for UI)
 ├─ queue: [QueueItem]    // .library(MPMediaItem) | .mixtape(MixtapeTrack)
 ├─ MusicEngine           // MPMusicPlayerController.applicationQueuePlayer
 ├─ LocalEngine           // AVQueuePlayer for mixtape files
 └─ NowPlayingManager     // MPNowPlayingInfoCenter + MPRemoteCommandCenter + animated artwork
```

- **Engine handoff:** When the next item's engine differs, pause the current engine, prepare the other, then play. Before each mixtape item starts, set `AVAudioSession` `.playback` active.
- **Shuffle, repeat and queue reordering** are owned by the coordinator, not the engines. Feed MusicEngine one contiguous run of library items at a time.
- **Play logging:** Log a `PlayEvent` on item end or skip. Count it as "completed" if ≥ 50% or ≥ 4 min.
- **Lock screen (NowPlayingManager):**
  - Always set title, artist, album, duration, elapsed and rate, plus static `MPMediaItemArtwork`.
  - If `MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys` contains the 3:4 key, attach `MPMediaItemAnimatedArtwork(artworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:)` built from either the **user motion cover** or the **Living Cover** (§6.9). Also provide 1:1.
  - Reuse one `artworkID` per album so the system doesn't re‑request assets for every song.
  - The preview image must match the aspect ratio exactly or the system ignores it.
  - The preview image must be ready synchronously; the video URL can be produced async (system timeout ~30s).
  - Video must be local, ≤60fps, a seamless loop under 30s.
- **Phase 0 spike (do before building anything else):** Play a library song through `applicationQueuePlayer`, then write `nowPlayingInfo` with the 3:4 animated key. Check on device whether the lock screen goes full‑screen.
  - If it doesn't stick, try re‑applying on `MPMusicPlayerControllerNowPlayingItemDidChange` and on playback‑state changes.
  - If it still loses, record that: Apple Music tracks get standard lock screen art and mixtapes get full‑screen. Tell Jash.

---

## 6. Features

### 6.1 Home (from MONO 01 + 08)
- **Pinned carousel:** paged, full‑width 4:5 cards with page dots, ↗ to open. Each pinned album shows its **artist portrait** or **album artwork** (per‑pin setting, long‑press → "Pinned Album Appearance"). A small album thumbnail sits in the corner when showing a portrait. Pinned playlists appear in the same carousel.
- **Recently Added** grid (2 columns, square art, title + artist), sorted by `dateAdded`.
- **Mixtapes shelf:** horizontal row of the user's mixtapes (if any).
- **Mood Playlists shelf** (if any).
- Pull to refresh re‑scans the library and takes a snapshot.

### 6.2 Library tab
A glass segmented control switches between **Artists · Albums · Songs · Playlists · Mixtapes**, each with search and sort (A–Z, most played, recently added, rating).

### 6.3 Artist page (MONO 02)
- Full‑bleed B&W portrait, large serif name, `ARTIST · N RELEASES`, then glass Play and Shuffle buttons.
- **My [Brand]** card: `#rank MOST PLAYED ARTIST IN YOUR LIBRARY`, most‑played song tile and most‑played album tile, each with art and play count.
- **My Top Songs:** top 10 in a two‑column numbered grid with plays.
- Total plays and estimated minutes, with the footnote "Minutes estimated from track durations × play counts".
- Albums row (See All) and Songs list (See All).

### 6.4 Album view (MONO 03)
- Full‑bleed artwork header (motion cover plays if present).
- Serif title, artist caps, then glass row: ▶ · shuffle · download (opens the song in Apple Music to download, since a 3rd‑party app can't download) · **Passport**.
- `ALBUM · 13 SONGS · 36 MIN · POP`.
- **Edition switcher:** `ORIGINAL ALBUM ⌄` lists editions plus "Manage Editions".
- Tracklist, then release date and copyright line where available.
- **My Listening History:** avg plays per song, minutes, `#rank` in top albums.
- **Your Top 3 Songs.**

### 6.5 Full player (MONO 04 + your additions)
- **ALWAYS full‑screen artwork.** Any square cover is scaled to *fill* the whole screen (`.scaledToFill`, aspect‑fill, top‑aligned on the face/subject using a Vision saliency or person mask). It never shows a letterboxed square. This applies to Apple Music, mixtapes and editions alike.
- If a motion cover exists, it loops behind everything. Otherwise a **Living Cover** plays (subtle Ken Burns/parallax, §6.9). There's a setting to turn it off. Animation is **not** paused in Low Power Mode unless the user toggles "Respect Low Power Mode" (default OFF).
- Bottom gradient sampled from the artwork, then title/artist, a Song Passport button and ♥ (in a GlassEffectContainer).
- Below that: scrubber with elapsed and remaining time; shuffle · ⏮ · ⏯ (big glass circle) · ⏭ · repeat.
- Last row: ••• · volume slider (`MPVolumeView`‑backed) · lyrics · queue.
- Crossfade or matched transition of the artwork between tracks. Swipe down to dismiss to the mini player.
- The player background "atmosphere" uses dominant and secondary colours extracted from the artwork (CIAreaAverage on regions).

### 6.6 Sing‑along lyrics (new)
- Fetch: `GET https://lrclib.net/api/get?track_name=…&artist_name=…&album_name=…&duration=…` with header `User-Agent: LINER/1.0 (personal app)`. On 404, fall back to `/api/search?track_name=…&artist_name=…` and pick the closest duration. Cache in `LyricsCache`. Mixtapes can paste or import their own `.lrc`.
- Parse LRC (`[mm:ss.xx]` lines) into `[(time, text)]`. Plain lyrics are the fallback (static scroll).
- **Sing‑along UI:** full‑screen over the blurred artwork, large serif lines. The active line is bright, past lines fade, future lines are dim. Auto‑scroll keeps the active line at about 35% height. Tap a line to seek there.
- Long‑press a line → "Save line" (goes into the Song Passport `lyricLines`) or "Save as favorite moment".
- Sync uses a `TimelineView(.animation)` reading the coordinator's current time.

### 6.7 Personal Editions (MONO 05 + mixtapes)
- Sheet header: "MY EDITIONS". The list shows editions with an active checkmark, swipe to delete, and "+ CREATE NEW EDITION".
- The editor provides: rename, set cover image (Photos) **or motion cover** (video), "+ ADD SONGS" (from library **or from mixtapes**), remove (−) and drag‑to‑reorder.
- The footnote states the Apple Music library is never modified.
- Playing an active edition plays its tracklist through the coordinator, mixing engines as needed.

### 6.8 Album Passport (MONO 06) and Song Passport (MONO 07)
- **Album Passport sheet:**
  - header with art, title, artist and song count
  - My Rating (hearts)
  - Personal Album Ranking → full‑screen drag list ("Your order, not your play counts")
  - Personal Editions → Manage
  - My Listening History: total plays, avg plays, listening time, library album rank
  - Full Album Ranking by plays
- **Song Passport sheet:**
  - header
  - My Rating
  - Mood chips (multi‑select): Euphoric, Melancholic, Nostalgic, Intimate, Dreamy, Dangerous, Healing, Late Night, Confident, Bittersweet, Energetic, Calm, plus a "+ custom" chip
  - My Notes and My Connection text fields
  - Song DNA: album, release date, duration, genre, composer, album artist, track number, plays, last played, date added
  - My Favorite Moments: a timestamp field, "Use current time", optional name, and multiple moments allowed. Tapping one seeks there.
  - Saved Lyric Lines
  - Share button (§6.13)

### 6.9 Motion covers and Living Covers (new)
- **User motion cover:** attach mp4/mov/gif to any album, edition or mixtape. Re‑encode to H.264, loop‑trimmed ≤20s, and export 1:1 and 3:4 crops plus a first‑frame preview.
- **Living Cover generator** (`LivingCoverRenderer`, AVAssetWriter, 8s seamless loop, 30fps, 1080×1440 for 3:4 and 1080×1080 for 1:1):
  - Mode A: slow zoom (1.00→1.06) + drift, ping‑ponged so the loop is seamless.
  - Mode B: subject lift via the Vision foreground mask, with gentle parallax between subject and background and an optional slow light sweep.
  - Generate lazily on first play, cache per album (`artworkID = "living-" + albumKey hash`), and evict with an LRU cap of 300 MB.
- These videos feed the in‑app player background, the lock screen (§5) and share cards.

### 6.10 Pinned albums and playlists (MONO 08)
Pin and unpin from the album/playlist ••• menu or a long‑press. Pinned appearance can be Artist Portrait or Album Artwork. The Playlists tab has "PINNED PLAYLISTS" (carousel) and "ALL PLAYLISTS".

### 6.11 My Stats tab, "My LINER." (MONO 09)
- Title "My LINER." with subtitle "Your music. Your history."
- All‑time total plays and minutes.
- Top Artists, Top Albums (numbered badges) and Top Songs, each with "See All" (full ranked lists, 100+).
- Extras: total library size, most‑loved (highest‑rated) albums, most‑used moods.

### 6.12 Recaps tab (new, Wrapped‑style)
- **Data:**
  - `SnapshotService` records each library song's `playCount`, writing rows only for songs whose count changed since the last snapshot.
  - Snapshots run on app launch/foreground, on `BGAppRefreshTask` (best effort, ~daily) and after playback ends.
  - **Plays in a period** = count delta across snapshots inside the period. Deltas spanning a period boundary are split proportionally by time. `PlayEvent`s from in‑app playback timestamp plays precisely and are de‑duplicated against deltas. Mixtape plays come only from `PlayEvent`.
  - On first launch, store a baseline snapshot. Show "Recaps start today — LINER. records your listening from now on." Don't fake past data.
- **Periods:** Week (Mon–Sun), Month, Year, plus an "All time" card. Show a horizontal picker of past periods.
- **Each recap shows:**
  - minutes listened (vs previous period, with an ↑/↓ %)
  - top 5 artists, albums and songs
  - top genre
  - top moods (from Song Passport tags of the songs played)
  - new discoveries (first played this period)
  - most‑replayed day
  - a "song of the period" hero
- **Story mode:** a tap‑through full‑screen story sequence, Wrapped‑style, about 8 cards. Each card has a full‑bleed motion or Living Cover background, serif numbers, and an animated count‑up. Every card is shareable (§6.13). Optionally send a local notification "Your week in music is ready" on Monday mornings.

### 6.13 Share cards (new, Matinee‑style)
- **Templates (9:16):** Song Passport, Album Passport, Artist "My history", Recap card, Now Playing, Saved lyric line.
- **Still:** `ImageRenderer` at 1080×1920. **Animated** (when a motion cover or Living Cover exists): composite the cover video full‑bleed plus the overlay layer with `AVVideoCompositionCoreAnimationTool`. Export H.264, ≤20s (loop it), 1080×1920.
- **Instagram Stories:** set the pasteboard with `com.instagram.sharedSticker.backgroundVideo` (or `…backgroundImage`) plus top/bottom colours from the artwork. Open `instagram-stories://share?source_application=<FB_APP_ID>`. **Use the same Facebook App ID Matinee uses** (it lives in config, never hard‑coded in multiple places).
- Also offer "Save to Photos" and the system share sheet.

### 6.14 AI Mood Playlists (new, Apple Intelligence on‑device)
- Gate on `SystemLanguageModel.default.availability`:
  - `.available` → show the feature
  - `appleIntelligenceNotEnabled` → explain how to turn it on
  - `deviceNotEligible` → hide the AI button and offer the non‑AI "Mood Mix" builder (same scoring, manual sliders)
  - `modelNotReady` → "Model downloading, try later"
- **Never pass the library to the model** (4K context). Two‑step design:
  1. **Recipe:** the user types a vibe ("rainy late‑night drive, a bit sad but hopeful") or taps mood chips, and optionally picks seed songs. A `LanguageModelSession` returns a `@Generable struct MoodRecipe { name, description, moods: [String] (from the app's mood list, via @Guide anyOf), genres: [String], energy: 0–1, eraFrom/To: Int?, seedArtists: [String], length: 15–40 }`.
  2. **Scoring in Swift:** score each library song locally. Mood‑tag match counts for the most, then genre match, seed‑artist/album affinity, the user's rating, play‑count affinity (normalized), and an energy proxy (genre map + BPM where known). Add diversity rules: max 3 per artist, no back‑to‑back same album.
  3. Optional polish: send the **top ~40 candidates** (title – artist only) back to the model for ordering and a title/description, in a fresh session.
- Save as `MoodPlaylist` (with an "auto‑refresh weekly" toggle that re‑runs scoring as tags and plays change). One tap creates a real Apple Music playlist via `MPMediaLibrary.default().getPlaylist(with:creationMetadata:)` + `addItem(withProductID:)` when the store ID exists. Otherwise it stays in‑app.
- Quick presets: "From my Late Night songs", "Most loved this month", "Forgotten favourites" (high rating, not played in 90 days).

### 6.15 Mixtapes (new)
- **Import:**
  - "+" in Mixtapes → `.fileImporter` (allowed: `.audio`, `.mp3`, `.mpeg4Audio`, `.wav`, `.aiff`, `.mpeg4Movie`, `.quickTimeMovie`, multi‑select).
  - Also "Open in LINER" from the Files app, Safari downloads or the share sheet (via `CFBundleDocumentTypes` + `onOpenURL`).
  - Video containers get the audio track extracted with `AVAssetExportSession(presetName: AppleM4A)` and are stored in `App Support/Mixtapes/<uuid>.m4a`.
  - Embedded metadata (title, artist, album, artwork) is read with `AVAsset.load(.commonMetadata)` to pre‑fill fields.
- **Organise:**
  - Create a mixtape (title, artist, label, year, cover image **or motion cover**), then add, rename and reorder tracks.
  - Tracks can also be dropped into any **Personal Edition** ("my version of the album"), and a mixtape can stay a standalone album.
  - Mixtapes appear in Library → Mixtapes, the Home shelf, search, stats and recaps (from `PlayEvent`), and get Song/Album Passports like any other music.
- Playback uses LocalEngine with full Now Playing control, so the lock screen gets a guaranteed full‑screen animated cover.

### 6.16 Vinyl Mode (new, MD Vinyl‑inspired, original design)
- **Toggle:** Settings → "Vinyl Mode", plus a quick toggle in the player's ••• menu.
- **The drawer:**
  - With Vinyl Mode on, the Home tab gains a **record drawer handle** at the bottom. Swipe up to pull out a glass drawer showing your crate.
  - The crate is a horizontal **3D flip‑through** of album sleeves (`rotation3DEffect`, slight perspective, sleeves leaning back). Drag to flip; each passing sleeve gives a soft haptic tick.
  - Filter chips: Pinned · Recent · Most played · Mixtapes · Mood Playlists.
- **Picking a record:**
  - Tap a sleeve and the record slides out of the sleeve (matched geometry).
  - It lands on a minimal turntable view: platter, the album art as the record's centre label, grooves drawn with a radial gradient plus a subtle specular sheen.
  - The tonearm swings onto the record, followed by a needle‑drop "pop" and a quiet crackle (both bundled CC0 sounds, toggleable), then playback starts.
- **Playing:**
  - The record spins at 33⅓ rpm (≈0.556 rev/s) while playing and eases to a stop on pause.
  - Drag on the record to **scratch‑scrub**: angular delta maps to seek, with a light rubber‑band.
  - Lift the tonearm (drag it off) to pause.
  - Flip the record (swipe up on it) to jump to the second half of the tracklist ("Side B").
- **Easter egg (homage to MD Vinyl):** tiny text on the centre label shows "LINER. — curated by Jash" plus the album year.
- The aesthetic stays minimal and monochrome: no wood grain. The turntable is matte black with glass controls.

### 6.17 Settings
Vinyl Mode, Living Covers on/off and style, Respect Low Power Mode (default off), lyrics source, needle sounds, recaps notifications, rebuild stats, export/import user data (JSON backup of passports, editions, mixtape metadata), name/brand, and about.

---

## 7. Stats engine (shared by Artist, Album, My Stats, Recaps)
- Snapshot the library once into memory (`[SongStat]` with key, artist, albumKey, genre, playCount, duration, dateAdded, lastPlayed).
- Minutes = Σ(playCount × duration)/60. Always label it "estimated".
- Ranks: artists by Σ plays; albums by Σ plays; songs by plays. Ties break by lastPlayed.
- Album average plays = Σ plays / track count.
- Cache results and invalidate on library change (`MPMediaLibraryDidChange`) or a new snapshot.
- Run heavy work off the main actor. A 10k‑song library must load stats in under 1s after first launch.

---

## 8. Navigation map
TabView (glass), in order:
1. **Home**
2. **Library**
3. **Recaps**
4. **My LINER.** (stats)
5. **Search** (`Tab(role: .search)`)

The mini player sits in `.tabViewBottomAccessory`. The full player is a `fullScreenCover` with zoom transition. Passports, Editions and Ranking are sheets.

---

## 9. Quality bar
- 60fps scrolling. Artwork is loaded off the main thread at the requested size and cached (NSCache + disk).
- Every list has an empty state in the house style. Handle "no Apple Music permission" and "no subscription" (canPlay) gracefully.
- Dynamic Type up to XL on labels and VoiceOver labels on all controls.
- Nothing is ever written to the user's Apple Music library except explicit "Save as Apple Music playlist".

---

## 10. Build phases (one per session; compile and run on device after each)

| # | Phase | Done when |
|---|---|---|
| 0 | **Spikes:** (a) lock screen 3:4 animated artwork with applicationQueuePlayer + with AVPlayer; (b) FoundationModels availability on Jash's phone; (c) Deezer artist image lookup; (d) applicationQueuePlayer plays library songs under free signing; (e) confirm the Instagram `backgroundVideo` pasteboard key against Matinee's code | Short written report of what works |
| 1 | Project skeleton: XcodeGen, CI workflow → .ipa, design system, glass TabView, permission flow, LibraryService | App installs, lists albums/artists/songs with art |
| 2 | PlaybackCoordinator + MusicEngine + mini player + **full‑screen player** + NowPlayingManager (static) | Play/skip/scrub/shuffle/repeat from library, lock screen controls work |
| 3 | StatsEngine + Artist page + Album view + My Stats | Numbers match the Music app's play counts |
| 4 | SwiftData models + Song Passport + Album Passport + Personal Ranking | All passport fields persist |
| 5 | Personal Editions + Pins (Home carousel, appearance) + Playlists tab | Edition plays in custom order with custom cover |
| 6 | Mixtapes (import, extract, metadata, LocalEngine, mixed queues) | SoundCloud mp3 and an mp4 import and play; mixed edition plays across engines |
| 7 | Lyrics (LRCLIB, sing‑along view, save lines/moments) | Synced lyrics on a popular song, tap‑to‑seek works |
| 8 | Motion covers + Living Cover renderer + animated lock screen artwork | Full‑screen animated lock screen for mixtapes, plus Apple Music tracks if Phase 0 succeeded |
| 9 | Snapshots + PlayLog + Recaps (weekly/monthly/yearly + story mode) | A week of test data (debug seeder) renders correctly |
| 10 | Share cards (still + video) + Instagram Stories | Story opens in Instagram with animated background |
| 11 | AI Mood Playlists (+ non‑AI fallback) | "late night, hopeful" gives a sensible 25‑song list in under 5s |
| 12 | Vinyl Mode | Drawer, crate flip, needle drop, spin, scratch‑scrub, Side B |
| 13 | Polish: transitions, haptics, empty states, settings, backup/export | Jash signs off |

Include a **DEBUG data seeder** (fake snapshots and play events) so recaps and stats can be tested without weeks of listening.

---

## 11. Rules for the coding agent
1. Read this whole file first. Only work on the phase you're asked for. Don't start the next phase.
2. Prefer native iOS 26 APIs (Liquid Glass, `tabViewBottomAccessory`, zoom transitions) over custom imitations.
3. When an API's behaviour is uncertain (anything marked 🧪), build the smallest test, report the result, and adapt. Never fake a feature or silently drop it; say what didn't work.
4. Keep files small (<300 lines), one feature per folder, and previews for every view with mock data.
5. After each phase: run `xcodegen` + `xcodebuild` (simulator) until there are zero errors and zero new warnings, push, and confirm the GitHub Action produced the .ipa.
6. End each phase with: what was built, what to test on the phone, and any known issues.
