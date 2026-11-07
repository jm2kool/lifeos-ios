# LINER.

A personal, artwork-first Apple Music companion for iPhone (iOS 26), built from `SPEC.md`. Free-signed and sideloaded:
CI (`.github/workflows/liner.yml`) builds every push and publishes `LINER.ipa` as the **liner-latest** release.
Install it with Sideloadly using your Apple ID.

| Area | What's there |
|---|---|
| Library | Artists · Albums · Songs · Playlists · Mixtapes with search and sort; black-and-white artist photos from Deezer |
| Artist titles | iOS 27-style stylised names: the artist's logo (TheAudioDB) in white, or genre-matched lettering; pick a style per artist; pages tinted from the artwork |
| Playback | Library songs via `applicationQueuePlayer`, imported files via AVPlayer, mixed in one queue; shuffle, repeat, Up Next |
| Player | Always full-screen artwork aimed at the subject, motion covers or Living Covers behind it, glass controls tinted by the art |
| Lock screen | Animated 3:4 / 1:1 artwork (motion cover or Living Cover); guaranteed for mixtapes, best effort for Apple Music songs |
| Stats | My LINER.: totals, ranked artists/albums/songs; artist and album pages with your history and ranks |
| Passports | Song Passport (hearts, moods, notes, connection, Song DNA, favourite moments, saved lyrics); Album Passport (hearts, personal ranking, history, cover) |
| Editions & pins | Your own versions of albums (library + mixtape tracks, custom covers); pinned carousel on Home |
| Mixtapes | Import mp3/m4a/wav/aiff/mp4/mov from Files or "Open in LINER."; covers, motion covers, LRC lyrics |
| Lyrics | LRCLIB synced lyrics, sing-along view, tap to seek, save lines and moments |
| Recaps | Week / month / year from the day you install, story mode, Monday notification |
| Share | 9:16 still and animated cards to Instagram Stories, Photos or anywhere |
| Mood playlists | On-device Apple Intelligence recipe + local scoring; Mood Mix without AI; save to Apple Music |
| Vinyl Mode | Record crate, turntable, needle drop, 33⅓ rpm spin, scratch-scrub, Side B |
| Settings | Covers, Low Power, lyrics, sounds, notifications, rebuild stats, JSON backup, test data, spike lab |

Limits of free signing: no MusicKit (MediaPlayer only), no widgets or extensions, re-sign every 7 days.
See `PHASE0.md` for the device checks and `CLAUDE.md` for working on the code.
