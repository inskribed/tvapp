#!/usr/bin/env bash
# Runs inside the Android TV emulator (see .github/workflows/screenshots.yml).
# Loads a free playlist through the debug-only DemoHook, then walks through the screens with the
# remote's keys and photographs each one.
set -u
PKG=com.inskribed.tvapp
OUT=screenshots/android
mkdir -p "$OUT"

adb wait-for-device
adb install -r app/build/outputs/apk/debug/app-debug.apk

shot() { sleep "${2:-1.5}"; adb exec-out screencap -p > "$OUT/android-$1.png"; echo "shot $1"; }
key()  { adb shell input keyevent "$1"; sleep "${2:-1.5}"; }

adb logcat -c
# Started through the exported home-screen entry (MainActivity itself isn't exported, so the
# command line is not allowed to start it directly). The extras are passed on to the app.
adb shell am start -W -n "$PKG/.OrkaLauncher" \
  --es demo_m3u "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8" \
  --es demo_keep "USA,UK,Canada,Australia,Ireland" \
  --es demo_favorites 6 \
  --es demo_teams "'NFL:Dallas Cowboys|NBA:Los Angeles Lakers'" \
  --es demo_section guide

# Up to 5 minutes for the playlist, groups and guide.
for i in $(seq 1 120); do
  adb logcat -d -s OrkaDemo:I | grep -q READY && break
  sleep 2
done
adb logcat -d -s OrkaDemo:I

shot 01-menu-open 3
key KEYCODE_DPAD_RIGHT;  shot 02-guide-groups 1
key KEYCODE_DPAD_RIGHT;  shot 03-guide-channels 2
key KEYCODE_DPAD_DOWN;   key KEYCODE_DPAD_DOWN;  shot 04-guide-details 1
key KEYCODE_DPAD_LEFT;   shot 05-groups-back 1
key KEYCODE_DPAD_DOWN;   key KEYCODE_DPAD_DOWN;  shot 06-other-group 2
key KEYCODE_DPAD_LEFT;   key KEYCODE_DPAD_DOWN;  shot 07-sports-menu 2
key KEYCODE_DPAD_RIGHT;  shot 08-sports 2
key KEYCODE_DPAD_LEFT;   key KEYCODE_DPAD_DOWN;  key KEYCODE_DPAD_RIGHT; shot 09-favorites 2
# Search: stay in the menu (going into the search box opens the on-screen keyboard).
key KEYCODE_DPAD_LEFT;   key KEYCODE_DPAD_DOWN;  shot 10-search-menu 2
key KEYCODE_DPAD_DOWN;   key KEYCODE_DPAD_RIGHT; shot 11-settings 2
for i in 1 2 3 4 5 6; do key KEYCODE_DPAD_DOWN 0.6; done; shot 12-settings-lower 1.5
for i in 1 2 3 4 5 6; do key KEYCODE_DPAD_DOWN 0.6; done; shot 13-settings-more 1.5
adb logcat -d -s OrkaDemo:I > "$OUT/demo-log.txt"
