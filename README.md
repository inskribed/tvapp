# Orka

A personal IPTV player for Android TV / Google TV (Nvidia Shield, onn 4K Plus).

## Install or update on a TV box

1. Install **Downloader** (by AFTVnews) from the Play Store.
2. Allow it to install apps: Settings → Apps → Security & restrictions → Unknown sources → Downloader → On.
3. In Downloader, enter the code **1320771**
   (or the full link: `https://github.com/inskribed/tvapp/releases/latest/download/tvapp.apk`).

4. Install. To update later, repeat step 3. Your playlists and favorites stay.

## Using it

- **First launch:** enter your Xtream Codes server URL, username and password.
- **TV Guide:** the main screen. Press left on a channel for groups; **Hold OK** on a channel to add or remove a favorite. Switch between Grid and List view at the top.
- **In the player:** up/down changes channel, OK shows channel info, Back shrinks it to a small window; Back again stops it.
- **Settings:** add more playlists, switch between them, change stream format (TS/HLS) if a channel won't play.

## How builds work

Every push to `main` builds a signed APK with GitHub Actions and publishes it as the latest release.
The signing key in `signing/` is password-protected; the password lives only in the
`KEYSTORE_PASSWORD` repository secret.

## Roadmap

- [x] Xtream login, multiple playlists, Live TV, favorites, search, channel up/down
- [x] TV guide grid (EPG), in-app updates
- [x] Sports: favorite teams, live games, matched channels, hide/show scores
- [ ] Program search
- [ ] Multi-view
- [ ] Recording to USB drive
