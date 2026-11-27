#!/usr/bin/env bash
# Runs on the macOS runner (see .github/workflows/screenshots.yml). Starts an iPhone simulator,
# installs the debug build, and photographs each screen using the demo-mode launch arguments.
set -eu
OUT=screenshots/ios
mkdir -p "$OUT"
BUNDLE=com.inskribed.orka
APP=ios/build/Build/Products/Debug-iphonesimulator/Orka.app

UDID=$(xcrun simctl list devices available | grep -E "iPhone 17 Pro \(" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}' || true)
if [ -z "$UDID" ]; then
  UDID=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | grep -oE '[0-9A-F]{8}-[0-9A-F-]{27}')
fi
echo "Simulator: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"

launch() {
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE" "$@"
}
wait_ready() {
  local data; data=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
  for i in $(seq 1 "${1:-60}"); do
    [ -f "$data/tmp/orka_demo_ready" ] && return 0
    sleep 2
  done
  echo "not ready after wait"
}
shot() { sleep "${2:-2}"; xcrun simctl io "$UDID" screenshot "$OUT/ios-$1.png"; echo "shot $1"; }

launch
wait_ready 15
shot 01-welcome 2

launch -orkaDemoM3U "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8" \
  -orkaKeepGroups "USA,UK,Canada,Australia,Ireland" -orkaFavorites 6 -orkaRecents 4 \
  -orkaTeams "NFL:Dallas Cowboys|NBA:Los Angeles Lakers" -orkaTab home
wait_ready 150
shot 02-home 3

launch -orkaTab guide;                          wait_ready 30; shot 03-guide 3
launch -orkaTab guide -orkaGuideGroup USA;      wait_ready 30; shot 04-guide-usa 3
launch -orkaTab sports;                         wait_ready 30; shot 05-sports 4
launch -orkaTab favorites;                      wait_ready 30; shot 06-favorites 3
launch -orkaTab search -orkaSearch news;        wait_ready 30; shot 07-search 3
launch -orkaTab home -orkaSettings 1;           wait_ready 30; shot 08-settings 3
