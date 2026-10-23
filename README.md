# Matinee

An independent film diary for iPhone, inspired by Letterboxd. It's built for iOS 26: Liquid Glass controls, a pure-black OLED theme, and sign-in with Google, Apple, GitHub, Discord, X, Facebook, Microsoft, Spotify or email.

Matinee is not affiliated with Letterboxd.

## What it does

| Letterboxd | Matinee | How Matinee changes it |
|---|---|---|
| Rate / log / review sheet | **Inline action panel** on every film | Watch, like, watchlist and the star rating sit on the film page itself. Slide across the stars to rate in half steps. |
| Long-press poster | **Long-press anywhere** | Log, watched, like, watchlist and add to list work from every poster in the app. |
| Diary | **Diary + year heatmap** | A "this year so far" card and a 6-month heatmap of film nights. Swipe right to log again, left to edit or delete, with undo. |
| Log date picker | **Today / Yesterday / Pick date** chips | One tap for the common case. |
| Film page | **Full-screen poster, page tinted by the poster's colour** | Scroll up from the poster and the page underneath is painted in the poster's main colour. |
| Profile | **Apple Card-style background** | A slowly moving colour blend drawn from your four favourite posters. |
| Watchlist | **Random pick** | Shake the phone, double-tap Library, or tap Random pick: a random watchlist film lands as a card that grows into its page. Filter by how much time you have. |
| — | **Widgets** | A home-screen and Lock Screen widget with a random watchlist film; tap to open it. |
| — | **Now watching** | Start watching puts a live timer in the Dynamic Island and on the Lock Screen. Pause with an exact time, a mood and a note. |
| Film page | **Trailer + where to watch** | Tap the poster for the trailer, full screen. See where it streams, rents or sells in India. |
| — | **Story card** | Share any film as a story-sized image with your rating. |
| Lists | **Lists with progress** | Shows "you've seen 3 of 7". Lists can be ranked and reordered by dragging. |
| Profile favourites | **Four favourites + ratings spread** | Tap any bar in your ratings chart to see those films. |
| Tags | **Tag suggestions** | Your past tags come up as chips while you log. |
| Import | **Letterboxd CSV import** | Bring your whole history across from Settings. |

## Install

Every push to `main` builds an unsigned `.ipa` on GitHub's Macs and attaches it to the **latest** release. Install it with [Sideloadly](https://sideloadly.io) using your Apple ID, the same way you install LifeOS. The **preview** release has simulator screenshots and a short screen recording.

## Film data

Films, posters, cast and recommendations come from [TMDB](https://www.themoviedb.org), the same database Letterboxd uses. You need a free **API Read Access Token**: sign up, then go to Settings → API.

- **In the app:** paste the token into the card on the Films tab, or under Settings → Film data.
- **Built in:** add it as a repository secret named `TMDB_TOKEN`. CI writes it into `Config/Info.plist` at build time, so it never sits in the source code.

## Sign-in setup (Google, Apple and the rest)

Sign-in goes through a free [Supabase](https://supabase.com) project. Supabase handles every provider in one place, so no client secrets are stored in the app.

1. Create a project at supabase.com. Copy the **Project URL** and the **anon / publishable key** from *Project Settings → API*.
2. Go to *Authentication → URL Configuration* and add the redirect URL `matinee://auth-callback`.
3. Go to *Authentication → Sign In / Providers* and turn on the ones you want:
   - **Email**: on by default. It works with no extra setup.
   - **Google**: in Google Cloud Console, create an OAuth client of type *Web application*. Set its authorised redirect URI to `https://<your-project>.supabase.co/auth/v1/callback`, then paste the client ID and secret into Supabase.
   - **GitHub, Discord, X, Facebook, Microsoft (Azure), Spotify**: same pattern. Make an OAuth app on that site with the Supabase callback URL above, then paste its ID and secret into Supabase.
   - **Apple**: needs a paid Apple Developer account, for a Services ID and key.
4. In the app, go to **Settings → Account server** (also on the sign-in screen) and paste the URL and key. To have them built in instead, fill `MatineeSupabaseURL` and `MatineeSupabaseAnonKey` in `Config/Info.plist`.

Providers you haven't switched on in Supabase show an error page in the sign-in sheet.

### Optional: sync your library to your account

Run this in Supabase's SQL editor. Once it's in place, your diary, ratings and lists follow your account to any phone.

```sql
create table if not exists public.libraries (
  user_id uuid primary key references auth.users on delete cascade,
  doc jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.libraries enable row level security;
create policy "own library" on public.libraries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

## Project layout

```
Matinee/App        App entry, tabs, routes
Matinee/Model      FilmRef, LogEntry, FilmList, and the Library store (JSON on disk + cloud sync)
Matinee/Services   Catalog (TMDB), Auth (Supabase + PKCE), Letterboxd importer
Matinee/Views      Home, Film, Log sheet, Diary, Library, Lists, Profile, Search, Sign-in, Settings
project.yml        XcodeGen spec. CI runs `xcodegen generate` and then builds.
```

### Optional: the watchlist widget on sideloaded builds

Sideloadly with a free Apple ID drops the permission that lets the app and its widget share files, so the widget sends your watchlist through your Supabase project instead. In the app, open **Settings → Widget → Copy setup SQL**, paste it into Supabase's SQL editor and run it once. Each phone reads only its own row, identified by a private device ID.
