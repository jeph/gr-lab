#!/usr/bin/env bash
# Takes the raw screens of the App Store screenshots on an iOS simulator,
# in the dark theme, against a simulated camera whose card and looks look
# used (app/integration_test/store_screens_test.dart). compose.py turns
# them into the captioned screenshots.
#
#   tool/store_screenshots/run.sh <name> <simulator udid>
#
# <name> names the output folder, build/store-screenshots/raw/<name>
# (`iphone` and `ipad` are what compose.py reads). List simulators with
# `xcrun simctl list devices available`; the App Store takes 1320 x 2868
# (iPhone 17 Pro Max) and 2064 x 2752 (iPad Pro 13-inch).
#
# The photos on the card are listed in photos.json: Unsplash photos under
# the Unsplash License, fetched on the first run and kept out of the
# repository.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <name> <simulator udid>" >&2
  exit 64
fi
name="$1"
udid="$2"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$root/build/store-screenshots"
media="$work/media"
shots="$work/raw/$name"
bundle=io.jeph.grphoto.dev

# Each scene in the three sizes a camera serves, and as a live view frame:
# the app drops frames over 1 MiB, which the views are. An upright photo is
# stored on its side, as a GR stores it; the card says how it was held.
fetch_media() {
  mkdir -p "$media"
  local scene portrait url base size width height
  while IFS=$'\t' read -r scene portrait url; do
    base="$media/s$(printf '%02d' "$scene")"
    for size in thumb:480 view:2400 full:3000 live:1280; do
      [[ -s "${base}_${size%%:*}.jpg" ]] && continue
      width="${size##*:}"
      height=$((width * 2 / 3))
      if [[ "$portrait" == true ]]; then
        curl -fsSL --max-time 120 -o "${base}_${size%%:*}.jpg" \
          "$url?w=$height&h=$width&fit=crop&q=88&fm=jpg"
        sips -r 270 "${base}_${size%%:*}.jpg" >/dev/null
      else
        curl -fsSL --max-time 120 -o "${base}_${size%%:*}.jpg" \
          "$url?w=$width&h=$height&fit=crop&q=88&fm=jpg"
      fi
    done
  done < <(jq -r '.[] | [.scene, .portrait, .url] | @tsv' "$here/photos.json")
  jq '[.[] | {scene, portrait}]' "$here/photos.json" >"$media/scenes.json"
}

# Takes a screenshot for each <name>.request the test writes. cmd-lock
# locks the simulator, takes the Lock Screen and ends the run. The first
# Live Activity of an app comes with iOS asking whether to allow them, which
# a tap on Allow answers; where that is depends on the device.
watch_requests() {
  local request
  while true; do
    for request in "$shots"/*.request; do
      [[ -e "$request" ]] || continue
      case "$(basename "$request" .request)" in
      cmd-lock)
        xcrun simctl spawn "$udid" "$work/sim_hid" lock
        sleep 4
        xcrun simctl spawn "$udid" "$work/sim_hid" lock
        sleep 4
        # shellcheck disable=SC2086 # Two arguments: x and y.
        xcrun simctl spawn "$udid" "$work/sim_hid" tap $allow
        sleep 3
        xcrun simctl io "$udid" screenshot "$shots/lock-screen.png" >/dev/null 2>&1
        touch "$shots/done"
        return
        ;;
      *)
        xcrun simctl io "$udid" screenshot "${request%.request}.png" >/dev/null 2>&1
        ;;
      esac
      rm -f "$request"
    done
    sleep 0.3
  done
}

fetch_media
mkdir -p "$shots"
rm -f "$shots"/*
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator \
  "$here/sim_hid.c" -o "$work/sim_hid" -framework CoreFoundation
if xcrun simctl list devices | grep -F "$udid" | grep -q iPad; then
  allow="0.62 0.90"
else
  allow="0.72 0.82"
fi

# A simulator left running may still show what an earlier run left on it,
# such as a permission prompt nothing answered.
xcrun simctl shutdown "$udid" 2>/dev/null || true
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" >/dev/null
# The date as well as the time: a time alone puts the Lock Screen on
# 1 January. simctl takes an ISO date only with milliseconds and a colon in
# the time zone.
zone="$(date +%z)"
xcrun simctl status_bar "$udid" override \
  --time "$(date +%Y-%m-%d)T09:41:00.000${zone:0:3}:${zone:3}" \
  --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 \
  --dataNetwork wifi --operatorName ""
xcrun simctl ui "$udid" appearance dark
# Praça do Comércio, Lisbon: where the newest photos of the card are from.
xcrun simctl location "$udid" set 38.7075,-9.1364
# A fresh install, so iOS asks whether to allow Live Activities on every
# run and the tap on Allow always has its button. iOS would also ask for the
# location over the screens, where no test can answer, and only an installed
# app can be allowed it: the test's own install comes too late.
xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
(cd "$root/app" && flutter build ios --simulator --debug --flavor dev)
xcrun simctl install "$udid" "$root/app/build/ios/iphonesimulator/Runner.app"
xcrun simctl privacy "$udid" grant location-always "$bundle"

watch_requests &
watcher=$!
cd "$root/app"
flutter test integration_test/store_screens_test.dart --flavor dev \
  --dart-define=SHOT_DIR="$shots" --dart-define=SHOT_MEDIA="$media" \
  -d "$udid" >"$shots/flutter.log" 2>&1 &
flutter=$!
finish() {
  kill "$watcher" "$flutter" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
  xcrun simctl shutdown "$udid"
  rm -f "$shots"/*.request "$shots/done"
}
trap finish EXIT

# The locked app no longer runs the test, so the run ends here rather than
# with the test.
until [[ -e "$shots/done" ]]; do
  if ! kill -0 "$flutter" 2>/dev/null; then
    echo "the run ended before its last screen; see $shots/flutter.log" >&2
    tail -30 "$shots/flutter.log" >&2
    exit 1
  fi
  sleep 1
done
ls "$shots"
