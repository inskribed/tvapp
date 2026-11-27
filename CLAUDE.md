# Orka — project guide for Claude

Orka (renamed from Remo; the repo is still `tvapp`) is a personal IPTV player for Android TV / Google TV, built for the owner's
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
- **Push straight to `main`** (owner's choice, "Option A"): even when a session is
  assigned a `claude/...` branch, put finished work on `main` so it builds, then
  confirm the Actions run succeeded. No pull requests needed. If the app is ever
  opened to other users, switch to PRs plus separate test vs stable releases.
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
- `data/Updater.kt` — in-app updater: GitHub `releases/latest`, compares the tag's
  build number (`v0.1.N`) with `versionCode` (both = CI run number), downloads
  `tvapp.apk` to cache, installs via FileProvider (`${applicationId}.files`).
- `data/Sports.kt` — ESPN public scoreboard/teams (`site.api.espn.com`) and
  `ChannelMatcher` (matches games to channels by network aliases and team names).
- `ui/` — `AppRoot` (screen switching + sidebar), `GuideScreen` (EPG grid:
  2-hour window, ◀▶ at the edge shifts time, per-channel `get_short_epg` fetched lazily for
  visible rows, max 4 at once, cached 30 min in `AppViewModel.epg`; or List view —
  `GuideListRow`, big channel rows with now-playing + progress, `vm.guideList`), `SportsScreen`
  (game rows, game detail, team picker), `OtherScreens` (Favorites, Search, Settings,
  Add playlist), `Components` (TvRow, TvButton, TvTextField, ChannelList),
  `player/PlayerScreen` (ExoPlayer, reconnect, channel up/down, pause).

## iPhone app (`ios/`)

Native SwiftUI, iOS 26+ (real Liquid Glass: `glassEffect`, `.glass` button styles), iPhone only,
bundle id `com.inskribed.orka`. Not run locally (no Swift/Xcode in the cloud sandbox): GitHub's
macOS runner is the compiler/test loop — `.github/workflows/ios.yml` (runs on `ios/**` pushes):
`swift test` for the logic package, then XcodeGen + `xcodebuild` for the simulator. Read failures
with `get_job_logs` (the "Show compile errors" step greps `error:`). The Android release workflow
ignores `ios/**` and `design/**`.

- `ios/OrkaCore/` — Swift package, Foundation only, unit-tested (15 tests): `XtreamClient`
  (login, live categories/streams, short EPG, HLS stream URLs; Codable with `FlexString`/`Lossy`
  for sloppy provider JSON), `Sports` (ESPN), `ChannelMatcher` (port of the Kotlin one),
  `LiveCacheStore` (parsed channel list on disk), `ContentKind` (live/movies/series).
  Android's Kotlin logic is NOT shared; if matcher aliases or parsing change, change both.
- `ios/Orka/` — app. `project.yml` is the XcodeGen spec (the `.xcodeproj` is generated, not
  committed). `AppModel` = all state (@Observable), `PlayerModel` = AVPlayer (HLS only — AVPlayer
  can't play raw .ts; retry/backoff like Android; PiP via AVPlayerLayer; audio continues in the
  mini player bar), `Store` (UserDefaults; playlist logins in Keychain). Views in `Views/`.
- Rules from the first review: the audio session is activated only when playback starts and
  released on stop (never at launch — it would stop the owner's music). Scores refresh from ONE
  app-level loop in `AppModel` (30s live / 120s otherwise, paused in background via scenePhase);
  don't add per-screen refresh loops. Logos go through `ImageLoader`/`RemoteImage` (memory cache,
  off-main decode), not AsyncImage. The mini player shows live video via `PlayerSurface`; PiP
  attaches to whichever surface enters a window (`didMoveToWindow`). The player has a 15s stall
  watchdog and counts a failure once (`retryPending`). Lock screen/headphone controls are wired.
- Search is whole-word (`OrkaCore/ChannelSearch`: each query word must start a word in the name;
  squashed-substring fallback only when nothing matches) — the old squashed search made "|us|"
  match "Museum". Hidden channel groups (Settings > Library > Channel groups, per playlist in
  UserDefaults `hidden_groups_<playlistId>`, quick "by country" tags from `groupPrefix`) are
  removed from `visibleChannels`, which Guide, Search and the game matcher use; favorites/recents
  keep them. Android matches: `data/ChannelSearch.kt` (same rules) and `ui/ChannelGroupsScreen.kt`
  (Settings > Channel groups; `vm.channels` = visible, `vm.allChannels` = everything).
- Language mode is Swift 5 on purpose (fewer strict-concurrency errors without a local compiler).
- Avoid type names that clash with system types (`Category` did; it's `ChannelCategory`).

**Launch/sync policy (owner's priority: get to sports games fast):** at launch only the saved
channel list loads from disk (refreshed in the background only if >12h old) and ESPN scores load
immediately. Guide data is fetched lazily per visible channel (max 4 at once, 30 min cache).
Movies and Series must NEVER sync at launch: add them as separate `ContentKind` syncs triggered
manually from Settings > Library (placeholders exist, "Coming soon"), on both Android and iOS.

**iOS UX decisions:** opens to Home (live/upcoming games summary, recently watched, favorites);
tabs Home (plain "Home" large title — no logo in the UI, per Apple's guidance), Guide (no time grid
on phone: group tiles at the top select a group, same as the Groups sheet; "All channels" is one list
with a pinned glass header per shown group), Sports, Favorites, Search; Settings is a sheet from Home.
Touch and hold = favorite. Player: bottom row is CH− · back 15s · play/pause · ahead 15s · CH+ (seek
stays within the stream's buffer); swipe up = stream info panel (now/next, picture size, bitrate);
swipe down = same as the ⌄ button (close to the mini bar). PiP is the top-right button (full screen
closes when PiP starts; PiP "back to app" reopens it; closing the PiP window stops the stream).
The brand (logo, name, version) lives in Settings > About, not on Home.
Back out of the player = mini player bar above the tab bar. Long lists use light `listPanel`
instead of glass for smoothness; glass is for cards, controls and the mini player.

**Not done yet / next:** TestFlight automation (needs the owner's Apple Developer account; add
signing + `fastlane`/`xcodebuild archive` workflow), Inter font (iOS uses the system font),
Movies/Series, program search, widgets.

## Playlist types: Xtream and M3U (both apps)

- Xtream (`kind = "xtream"`, server/username/password) and **M3U links** for legal sources
  (`kind = "m3u"` on Android with the link in `server`; `m3uURL` set on iOS). Owner's test sources:
  Free-TV (`raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8`) and iptv-org
  (`iptv-org.github.io/iptv/...` — that host is blocked from the cloud sandbox; its raw files on
  raw.githubusercontent.com/iptv-org/iptv/master/streams/*.m3u are reachable for testing).
- Parser: `ios/OrkaCore/.../M3UParser.swift` (unit-tested) and `data/M3uParser.kt` (same rules —
  change both). group-title (first of "A;B") → #EXTGRP → tvg-country → country from tvg-id → "Other";
  #EXTVLCOPT http-user-agent / http-referrer kept per channel and sent when playing; YouTube/Twitch
  pages and non-URLs skipped; channel id = "m" + 12 hex of SHA-1(url) so favorites survive refreshes.
- M3U guide = XMLTV (`ios/OrkaCore/.../XMLTV.swift`, unit-tested; `data/Xmltv.kt`, same rules):
  sources = a link the user typed (`epgUrl`, comma-separated ok) or else the playlist header's list
  (`LiveData.guideUrls`), cut by `chooseSources` to the shown channels' countries (from tvg-id
  suffix), max 8 files, plainest file per country, never "all_sources"/"dummy". Matching: tvg-id →
  id without punctuation → display name minus brackets/quality words. Window: −2h…+24h, summaries
  ≤400 chars. Saved per playlist (iOS `guide_<id>.json`, Android `guide_<id>.tsv`), refreshed in the
  background after 12h; applied to every channel's epg state at once (no per-channel requests).
  Android streams + gunzips while downloading (XmlPullParser); iOS downloads, gunzips via
  NSData(.zlib) after the gzip header, XMLParser. The header link is no longer saved into `epgUrl`
  (that field is the user's override only). Android caches the raw text
  (`cache_<id>_m3u.json`); iOS caches the parsed list like Xtream. Android plays HLS/TS/DASH (dash
  module added); iPhone plays HLS only.
- Add playlist has one-tap Free-TV / iptv-org buttons (`FREE_SOURCES` / `freeSources`).

## Screenshots (both apps)

`.github/workflows/screenshots.yml` (manual: Actions → Screenshots → Run workflow, input `which` =
both/android/ios) runs an Android TV emulator (API 30, tv_1080p, KVM) and an iPhone 17 Pro simulator,
loads the free Free-TV playlist (keeping only USA/UK/Canada/Australia/Ireland groups, 6 favorites,
Cowboys + Lakers as "my teams"), walks through the screens and photographs them. Pictures are
attached to the run and published as the **`screenshots` pre-release** (never "latest", so it can't
become an app update): `https://github.com/inskribed/tvapp/releases/tag/screenshots`; files are
`android-NN-*.png` / `ios-NN-*.png` and can be curl'd from the sandbox.
- Debug-only demo hooks (absent from release builds): Android `src/debug/.../DemoHook.kt`
  (intent extras `demo_*`; release has a no-op stub) and iOS `ios/Orka/DemoMode.swift` (`#if DEBUG`,
  launch args `-orka*`). Android is started through the exported `.OrkaLauncher` alias (MainActivity
  isn't exported, so `am start` of it is refused); the script then drives the remote with
  `adb shell input keyevent`. iOS relaunches per screen and waits for `tmp/orka_demo_ready`.
- Debug builds skip the automatic update check (their version number is a throwaway).
- Search on the TV: don't press RIGHT into the search box in the script (opens the keyboard).
- Both apps show the real guide (XMLTV) and live ESPN data from the runners' internet access.

## Product decisions already made

- App opens to the TV Guide (the old Live TV list section was removed; the guide's List view
  replaces it). No forced login. No teams are pre-selected.
- Clean dark UI inspired by Nuvio; Sports section inspired by Lume's Sports Hub.
- Player: OK = pause/play, up/down = change channel (invertible in Settings), Back = shrink to a
  small window (top-right, `AppViewModel.playerMini`) while browsing; Back again stops it;
  picking a channel (or the same one) goes full screen.
  While mini, a "Now playing" item at the bottom of the sidebar returns to full screen.
- `Theme.kt` provides `LocalContentColor = AppColors.Text`; tv-material's default is black, so
  any Text outside a Surface without its own color would otherwise render black.
- Sidebar: line icons (`ui/Icons.kt`, hand-drawn ImageVectors — no icon library) overlaying the
  content; collapses to icons when focus leaves it, expands when focus enters.
- TV Guide depth, TiviMate-style: the group list is a permanent column (`GroupsColumn`) left of
  the guide. In the group list the menu shows as icons; inside the channels (`vm.guideImmersive`,
  set from the guide area's focus) the menu and group column slide off left and the guide uses
  the full width. ◀ on a channel (or Back) slides the groups back with the current group focused;
  moving onto a group shows it; OK/▶ returns to the last channel. All sliding is `graphicsLayer`
  translation read in the draw phase (no re-layout per frame — keep it that way for the 2015
  Shield). Guide speed rules: guide data is per-channel state (`vm.epgFor(key)`), and the focused
  item goes into a `State` read only by `GuideHeader` — never read per-move state in GuideScreen's
  body, or every row redraws on each D-pad press.
- Accent color is user-chosen (Settings → Appearance, presets in `Theme.kt` `AccentPresets`,
  saved in Prefs). `AppColors.Accent` is state-backed, so reading it recomposes on change. Used
  tastefully: sidebar highlight (glass pill: 2dp accent border, ~16% accent fill, light top
  sheen), current-section icon, settings headers, text-field focus, guide accents, mini-player
  border. All focusable items share the glass highlight via `glassColors` / `glassBorder` /
  `glassSheen` in `Components.kt` (TvRow, TvButton, game cards, guide cells); no more solid white.
- Brand: teal (`AccentPresets[0]`, #1FE3CC) with a lime highlight (`AppColors.Highlight`,
  #C9FF3F: guide progress bar, "Now" label, Now playing icon). Logo = play button with an orca
  fin, wave lines and eye patch. Assets are PNGs generated by `design/logo/` (mark.py +
  build_assets.py → `drawable-nodpi/orka_mark.png`, `ic_orka_foreground.png`,
  `drawable-xhdpi|xxhdpi/banner_orka.png`; launcher icon `@mipmap/ic_orka`). Resources were renamed
  from ic_launcher/banner so TV launchers that cache icons pick up the new ones. The accent pref key is versioned (`accent_color_v2`).
- Font: Inter (static TTFs in `res/font`, applied via `LocalTextStyle` in `Theme.kt`).
- Back on the TV: each screen's own steps first (player → mini, guide channels → groups, detail
  screens close); with nothing left, Back opens the side menu (`MainScreen` BackHandler, off while
  the menu has focus); Back from the menu stops a mini player if one is running, then leaves Orka.
- The home-screen entry is the `<activity-alias android:name=".OrkaLauncher">` (MainActivity is not
  exported). It was added so Google TV on the onn reloads the Orka icon; don't rename it.
- Playlists can be edited (Settings → Edit; same screen as Add, prefilled; type is fixed). Saving
  re-checks the login or re-downloads the M3U, keeps the playlist id (favorites/hidden groups stay),
  and reloads it if it's the one in use. Same on iPhone (Settings → swipe or ⓘ → Edit).
- Hold OK on a channel = toggle favorite.
- Settings: multiple playlists, TS/HLS format, compact list, show/hide scores, my teams.

## Roadmap

1. ~~TV guide grid~~ (done). Still to do: program search and guide-based sports matching
   (need bulk EPG, e.g. `xmltv.php` — watch memory on the 2GB onn)
2. Tune sports channel matching from the owner's real channel names
3. Multi-view (Shield ~4 tiles, onn ~2; limited by provider connections)
4. Recording to USB drive (Shield has USB-A; onn needs a USB-C hub)
5. ~~Icon/banner, in-app update prompt~~ (done)

## Owner's Mac test setup (adb shortcuts)

The owner has Homebrew + `android-platform-tools` (adb 37) on their MacBook and
these shortcuts in `~/.zshrc` (between `# --- Orka shortcuts ---` markers):

- `orka-update` — downloads the latest release APK to `~/Downloads/tvapp.apk`,
  installs it with `adb install -r` on every box in `REMO_BOXES`, then launches it.
- `orka-log` — live `logcat` filtered to the app's process (`pidof com.inskribed.tvapp`).
- `ORKA_BOXES=(192.168.0.216:5555)` — Shield (Network debugging, authorized).
  onn is `192.168.0.215` (DHCP reservation) but not reachable from the Mac yet
  (ARP "incomplete"; wireless pairing fails) — unresolved.

**When the app is renamed** (currently "Orka"), give the owner an updated
shortcuts block to replace the old one in `~/.zshrc` (delete between the markers, paste the
new block): rename `orka-update`, `orka-log`, `ORKA_BOXES` and the marker comments to match. If the repo name or
release asset name (`tvapp.apk`) changes, update the download URL there too, and
the Downloader code note above. Do NOT change `applicationId`
(`com.inskribed.tvapp`) as part of a rename — the display name lives in
`app/src/main/res/values/strings.xml` (`app_name`) and can change freely.
