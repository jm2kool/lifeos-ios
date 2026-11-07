# LINER. — Phase 0 spike lab

Phase 0 is a throwaway test app (bundle `com.jm2kool.liner`, shown as **LINER.**). It checks the five risky things in SPEC §10 before any real feature gets built. Every result goes into one report you can copy.

## Install
1. GitHub → Releases → **LINER. (latest build)** (tag `liner-latest`) → download `LINER.ipa`.
   (The "Build LINER IPA" run also uploads it as the `LINER-ipa` artifact.)
2. Install it with Sideloadly using your Apple ID, the same way as Matinee.
   On free signing you can have **3 sideloaded apps at once**, so you may need to remove one first.
3. Before testing:
   - Low Power Mode **off**
   - Settings → Accessibility → Motion: Reduce Motion **off**, Auto-Play Animated Images **on**
   - Instagram installed and signed in
   - Apple Intelligence **on**, if your iPhone supports it

## Run the steps in order (the home screen lists them)
| Step | Spike | What you do | What to look at |
|---|---|---|---|
| 1 | **D · Library playback** | Tap *Allow Apple Music access*. Tap a song you've played a lot. | Music starts. The badge turns WORKS on its own after 4 s. Check 2–3 play counts against the Music app. |
| 2 | **A · Lock screen art** | Tap *Make Living Covers*. **Test 1:** Start → lock the phone → look → try pause/play on the lock screen → unlock → tap what you saw. **Test 2:** same again with the test tone. Optional: *Import audio file* with a SoundCloud mp3. | Does the lock screen show the art **full-screen and moving**? Is it full-screen but still? Or the normal small square? |
| 3 | **B · Apple Intelligence** | Opens and checks itself. Tap *Run the model* with the sample vibe. | Availability, and how long the recipe and the 40-song ordering take (target: under 5 s total). |
| 4 | **C · Deezer** | Tap *Look them up* (your 10 most-played artists). | How many come back with a real photo. Whether the B&W portrait looks good. |
| 5 | **E · Instagram** | Tap each of the 3 *Open in Instagram* buttons. Close the story without posting, come back, and tap what you saw. | Whether the **video** background moves in Instagram. |

The spike lab is in Settings (gear on Home) → Spike lab. When done, tap **Copy report** and paste it to Claude.

## What the code checks for you
- **A:** logs `MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys`. It also logs whether the 3:4 key is still in `nowPlayingInfo` 2.5 s after it's written, and every time iOS asks for the preview or video ("System asked for … VIDEO"). If iOS never asks for the video during Test 1, the queue player owns Now Playing and our keys are ignored.
- **B:** logs the availability reason, both timings, and any mood the model made up that isn't in the app's list.
- **C:** logs the name match and photo/no-photo for each artist (Deezer's placeholder URLs contain `/artist//`).
- **D:** logs library size, scan time, how many songs have store IDs / are cloud-only / protected, and any `prepareToPlay` error code.
- **E:** logs whether `instagram-stories://` can be opened, the video file size, and what `open()` returned.

## Notes
- Matinee's share code (`Matinee/Views/StoryShare.swift`) only uses `backgroundImage` + `stickerImage`. **It never used `backgroundVideo`**, so spike E is the first real test of that key. The Facebook app ID is Matinee's (`1097387086261982`), stored once in `LINER/Config/Info.plist` as `LINERFacebookAppID`.
- The Living Cover maker here is a simple version of SPEC §6.9 mode A (zoom + drift, seamless loop). The real `LivingCoverRenderer` comes in Phase 8.
