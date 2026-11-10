# LINER.

A personal, artwork-first Apple Music companion for iPhone (iOS 26), built from `SPEC.md`. Free-signed and sideloaded:
CI (`.github/workflows/liner.yml`) builds every push and publishes `LINER.ipa` as the **liner-latest** release.
Install it with Sideloadly using your Apple ID.

| Area | What's there |
|---|---|
| Library | Artists · Albums · Songs · Playlists with search and sort; one-song "albums" are treated as songs; editions of an album ("WILD", "WILD (Deluxe)") are grouped into one album led by the biggest edition (Mixtapes have their own tab); albums as a moving crate with haptic ticks; black-and-white artist photos from Deezer |
| Search | The whole Apple Music catalogue — artists, albums and singles, songs; play, queue or add them to your library — or switch to Your Library |
| Artist pages | A Page like Apple Music's (latest release, Top Songs, Albums, Singles & EPs from the Apple Music catalogue via the iTunes Search API, streamed by Apple Music ID — through the Music app's player if LINER.'s own one refuses; singles Apple lists without songs are found by name) and LINER. stats (your history with them) |
| Artist titles | iOS 27-style stylised names: the artist's logo (TheAudioDB) in white — collaborations like "Drake & PARTYNEXTDOOR" get both logos joined with an "&" when the duo has none of its own — or genre-matched lettering; pick a style per artist in Settings → Artist titles; pages tinted from the artwork |
| Playback | Library songs via `applicationQueuePlayer` (iCloud and catalogue songs stream by Apple Music ID, with one automatic retry), imported files via AVPlayer, mixed in one queue; shuffle, repeat, Up Next |
| Player | Always full-screen artwork aimed at the subject, motion covers or Living Covers behind it, glass controls tinted by the art; swipe the mini player left or right for the next or previous song; opens by itself when you start a song (Settings → Listening); the screen stays on while it's open |
| Lock screen | Animated 3:4 / 1:1 artwork (motion cover or Living Cover); guaranteed for mixtapes, best effort for Apple Music songs |
| Stats | My LINER.: totals, ranked artists/albums/songs; artist and album pages with your history and ranks |
| Passports | Song Passport (hearts, moods, notes, connection, Song DNA, favourite moments, saved lyrics); Album Passport (hearts, personal ranking, history, cover) |
| Album titles | The album's own title lettering, lifted from its cover with on-device text recognition when it's clean enough (Settings → Covers → Album title logos); plain text otherwise |
| Editions & pins | Full Album (every song from Apple Music, the ones you don't have streamed) or Saved Album (only your library's songs) per album; your own versions of albums (library + mixtape tracks, custom covers); pins on Home in a grid that fits how many there are; playing an edition shows its cover in the player, the mini player and on the Lock Screen |
| Mixtapes | Import mp3/m4a/wav/aiff/mp4/mov from Files or "Open in LINER."; covers, motion covers, LRC lyrics |
| Lyrics | LRCLIB synced lyrics, sing-along view that opens on the line being sung, the current and next line on the player, tap to seek, save lines and moments; live lyrics on the Lock Screen (Live Activity that follows you from song to song, lines slide up as they change, its own clock and a keep-alive adapted from Lyricar (silence at full mixer volume, a 10 s watchdog, a background-task hold while it restarts) so it doesn't freeze in the background, moving on with the music when one song runs into the next, dimming if a line is ever overdue, a Live lyrics log in Settings to see why if it does, and a Dynamic Island with a little record, a progress ring that moves by itself, and the lyric with time left when expanded) |
| Recaps | In My LINER.: week / month / year from the day you install, story mode, Monday notification |
| Share | 9:16 still and animated cards to Instagram Stories, Photos or anywhere; share lyrics like Apple Music (tap Share in the lyrics, pick up to six lines in a row, and they go on the story card over the cover) |
| Mood playlists | On-device Apple Intelligence recipe + local scoring; Mood Mix without AI; save to Apple Music |
| Vinyl Mode | Double-tap Home to switch; Home becomes the record crate (with a rise-and-focus transition); the lyric being sung is printed round the record and travels round with it, each line drifting into the next; albums open as a gatefold sleeve (lifts out of the crate and opens from the spine: the cover full screen with title, numbers and songwriters, the tracklist a swipe away; side by side as squares in landscape); "Put it on" slides the record out and drops it onto a plain record on the turntable; double-tap the record button in the crate for the Listening Room (a black turntable and a shelf of your most played records, spines out: take one off, open the sleeve, drag the record onto the deck; the screen stays on); needle drop, 33⅓ rpm spin, scratch-scrub, Side B; Cover/Record switch in the player opens a turntable deck whose tonearm follows the song — move it to seek, set it down off the record to pause |
| Demo mode | For CI only: `LINER_DEMO=1` swaps in a made-up library, covers and play history, and `LINER_SCENE` picks what happens (splash, crate, player, lyrics, share, stats, recap, library, island). Recordings go to the **liner-preview** release |
| Settings | Covers, Low Power, lyrics, sounds, notifications, artist titles, recalibrate Apple Music, rebuild stats, JSON backup, test data, spike lab |

Limits of free signing: no MusicKit (MediaPlayer only), re-sign every 7 days. The live lyrics widget extension uses one extra App ID.
See `PHASE0.md` for the device checks and `CLAUDE.md` for working on the code.

Parts of the live lyrics keep-alive are adapted from [Lyricar](https://github.com/noluyorAbi/lyricar) (Apache 2.0); see `NOTICE`.
