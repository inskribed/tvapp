# Remo — project guide for Claude

Remo is a personal IPTV player for Android TV / Google TV, built for the owner's
**Nvidia Shield (2015, Android TV 11)** and **onn 4K Plus (Google TV, 2GB RAM)**.
The owner is not a developer: explain things plainly, keep changes working, and
ship them as installable builds.

## How builds and installs work

- No local Android SDK is needed. Every push to `main` triggers GitHub Actions
  (`.github/workflows/build.yml`), which builds a signed release APK and publishes
  it as the latest GitHub release (`tvapp.apk`). Docs-only (`*.md`) changes don't build.
- Install/update on a TV box: Downloader app → code **1320771**
  (= https://github.com/inskribed/tvapp/releases/latest/download/tvapp.apk).
- Signing: `signing/release.p12` (PKCS12, alias `tvapp`), password in the repo secret
  `KEYSTORE_PASSWORD`. Never change the key or `applicationId` (`com.inskribed.tvapp`),
  or updates stop installing over the existing app.
- After pushing, check the run at https://github.com/inskribed/tvapp/actions and fix
  any compile errors before telling the owner a build is ready.
- If the owner enables wireless debugging on a box, `adb connect <ip>:5555`, then
  `adb install -r tvapp.apk` and `adb logcat` are the fastest test loop.

## Stack

Kotlin 2.0.21, AGP 8.7.3, Gradle 8.10.2 (CI installs it; no wrapper jar in repo),
Jetpack Compose + `androidx.tv:tv-material` 1.0.0, Media3/ExoPlayer 1.5.1 (+HLS, OkHttp
data source), OkHttp 4.12, Coil 2.7, org.json for parsing. minSdk 26, target 34.
No DI, no Room yet. State lives in `AppViewModel` as Compose `mutableStateOf`.

## Code map (`app/src/main/java/com/inskribed/tvapp/`)

- `AppViewModel.kt` — all app state: playlists, channels, favorites, search, settings,
  sports, playback queue.
- `data/XtreamClient.kt` — Xtream Codes API (`player_api.php`), stream URLs
  (`/live/{user}/{pass}/{id}.ts|m3u8`). Fields may be strings or numbers; use `str()`.
- `data/Repository.kt` — caches category/stream JSON on disk, refreshes after 12h.
- `data/Prefs.kt` — SharedPreferences (playlists, favorites, favorite teams, settings).
- `data/Sports.kt` — ESPN public scoreboard/teams (`site.api.espn.com`) and
  `ChannelMatcher` (matches games to channels by network aliases and team names).
- `ui/` — `AppRoot` (screen switching + sidebar), `LiveTvScreen`, `SportsScreen`
  (game rows, game detail, team picker), `OtherScreens` (Favorites, Search, Settings,
  Add playlist), `Components` (TvRow, TvButton, TvTextField, ChannelList),
  `player/PlayerScreen` (ExoPlayer, reconnect, channel up/down, pause).

## Product decisions already made

- App opens to the main screen; no forced login. No teams are pre-selected.
- Clean dark UI inspired by Nuvio; Sports section inspired by Lume's Sports Hub.
- Player: OK = pause/play, up/down = change channel (invertible in Settings), Back = exit.
- Hold OK on a channel = toggle favorite.
- Settings: multiple playlists, TS/HLS format, compact list, show/hide scores, my teams.

## Roadmap

1. TV guide grid (EPG via `get_short_epg` / `xmltv.php`), program search, guide-based sports matching
2. Tune sports channel matching from the owner's real channel names
3. Multi-view (Shield ~4 tiles, onn ~2; limited by provider connections)
4. Recording to USB drive (Shield has USB-A; onn needs a USB-C hub)
5. Proper Remo icon/banner, in-app update prompt

## Owner's Mac test setup (adb shortcuts)

The owner has Homebrew + `android-platform-tools` (adb 37) on their MacBook and
these shortcuts in `~/.zshrc` (between `# --- Remo shortcuts ---` markers):

- `remo-update` — downloads the latest release APK to `~/Downloads/tvapp.apk`,
  installs it with `adb install -r` on every box in `REMO_BOXES`, then launches it.
- `remo-log` — live `logcat` filtered to the app's process (`pidof com.inskribed.tvapp`).
- `REMO_BOXES=(192.168.0.216:5555)` — Shield (Network debugging, authorized).
  onn is `192.168.0.215` (DHCP reservation) but not reachable from the Mac yet
  (ARP "incomplete"; wireless pairing fails) — unresolved.

**When the app is renamed** (currently "Remo"), give the owner an updated
shortcuts block to replace the old one in `~/.zshrc`: rename `remo-update`,
`remo-log`, `REMO_BOXES` and the marker comments to match. If the repo name or
release asset name (`tvapp.apk`) changes, update the download URL there too, and
the Downloader code note above. Do NOT change `applicationId`
(`com.inskribed.tvapp`) as part of a rename — the display name lives in
`app/src/main/res/values/strings.xml` (`app_name`) and can change freely.
