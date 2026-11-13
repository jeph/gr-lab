#!/usr/bin/env bash
# Takes the raw screens of the App Store screenshots on iOS simulators, in
# the dark theme and in each language asked for, against a simulated camera
# whose card and looks look used
# (app/integration_test/store_screens_test.dart). compose.py turns them
# into the captioned screenshots.
#
#   tool/store_screenshots/run.sh <device>=<udid> ... [locale ...]
#
# A device is `iphone`, `ipad` or `duo`, with the simulator that stands for
# it: the App Store takes 1320 x 2868 (iPhone 17 Pro Max), 2064 x 2752
# (iPad Pro 13-inch) and 2853 x 2007 (iPhone Duo, open). List simulators
# with `xcrun simctl list devices available`. A locale is one of the app's
# (app/l10n.yaml); without any, the screens are taken in English. They go to
# build/store-screenshots/raw/<device>/<locale>.
#
# The app is built once, with the walk as its entry point, and each
# simulator is restarted in each language and runs it: GR Photo follows the
# phone's language, and so do the status bar and the Lock Screen.
#
# An iPhone Duo starts closed, and Xcode 27.1 has no command that opens it:
# each time the script says so, press Open on the simulator in Device Hub.
# The walk starts when the inner display comes on. Needs ImageMagick 7
# (`magick`) to see that it has.
#
# The photos on the card are listed in photos.json: Unsplash photos under
# the Unsplash License, fetched on the first run and kept out of the
# repository.
set -euo pipefail

devices=()
locales=()
for argument in "$@"; do
  case "$argument" in
  iphone=* | ipad=* | duo=*) devices+=("$argument") ;;
  *) locales+=("$argument") ;;
  esac
done
if [[ ${#devices[@]} -eq 0 ]]; then
  echo "usage: $0 <iphone|ipad|duo>=<udid> ... [locale ...]" >&2
  exit 64
fi
[[ ${#locales[@]} -gt 0 ]] || locales=(en)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
work="$root/build/store-screenshots"
media="$work/media"
bundle=io.jeph.grphoto.dev
# How long a walk may take before the run gives up on it.
walk_seconds=420

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

# The language and region iOS is set to for a locale of the app.
ios_language() {
  case "$1" in
  en) echo "en-US en_US" ;;
  pt) echo "pt-PT pt_PT" ;;
  da) echo "da-DK da_DK" ;;
  sv) echo "sv-SE sv_SE" ;;
  cs) echo "cs-CZ cs_CZ" ;;
  el) echo "el-GR el_GR" ;;
  ko) echo "ko-KR ko_KR" ;;
  ja) echo "ja-JP ja_JP" ;;
  zh) echo "zh-Hans-CN zh_CN" ;;
  zh_Hant) echo "zh-Hant-TW zh_TW" ;;
  fr | de | es | it | nl | fi | pl | hu | tr | ru | th)
    echo "$1-$(tr '[:lower:]' '[:upper:]' <<<"$1") $1_$(tr '[:lower:]' '[:upper:]' <<<"$1")"
    ;;
  *)
    echo "$1 is not a locale of the app" >&2
    return 1
    ;;
  esac
}

# Sets the language of a simulator that is shut down.
set_language() {
  local udid="$1" language region
  read -r language region <<<"$(ios_language "$2")"
  local preferences="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/.GlobalPreferences.plist"
  plutil -replace AppleLanguages -json "[\"$language\"]" "$preferences"
  plutil -replace AppleLocale -string "$region" "$preferences"
  # The Lock Screen shows the status bar's time only with a 24-hour clock or
  # in English: with the 12-hour clock of Greek, Korean and Taiwan it shows
  # the real time (iOS 26.5).
  if [[ "$2" == en ]]; then
    plutil -remove AppleICUForce24HourTime "$preferences" 2>/dev/null || true
  else
    plutil -replace AppleICUForce24HourTime -bool true "$preferences"
  fi
}

# Records that the user allowed the app's Live Activities both times iOS
# asks, under the first one (Allow) and under a later one (Always Allow):
# simctl has no grant for them. The daemon that keeps the record reads it
# when it starts.
allow_live_activities() {
  local udid="$1" daemon=com.apple.liveactivitiesd key
  xcrun simctl spawn "$udid" defaults write "$daemon" \
    AppAuthorizationRecords -dict "$bundle" -bool true
  for key in FirstResponseRecords SecondResponseRecords; do
    xcrun simctl spawn "$udid" defaults write "$daemon" "$key" -array "$bundle"
  done
  xcrun simctl spawn "$udid" launchctl stop "$daemon"
}

# Takes a simulator's screenshot. An iPhone Duo has two displays, and which
# of them simctl takes by itself changes with the pose: 3 is the inner one.
screenshot() {
  local device="$1" udid="$2" file="$3"
  if [[ "$device" == duo ]]; then
    xcrun simctl io "$udid" screenshot --display=3 "$file" >/dev/null 2>&1
  else
    xcrun simctl io "$udid" screenshot "$file" >/dev/null 2>&1
  fi
}

# Waits for an iPhone Duo to be opened: its inner display is black while it
# is closed.
wait_open() {
  local udid="$1" shots="$2" told=false
  until screenshot duo "$udid" "$shots/open.png" &&
    [[ "$(magick "$shots/open.png" -alpha off -format '%[fx:mean>0.01]' info:)" == 1 ]]; do
    $told || echo "duo: press Open on the simulator in Device Hub" >&2
    told=true
    sleep 2
  done
  rm -f "$shots/open.png"
}

# Takes a screenshot for each <name>.request the walk writes into a folder.
# `failure` is the walk giving up, and cmd-lock its end: it locks the
# simulator and takes the Lock Screen.
watch_requests() {
  local device="$1" udid="$2" shots="$3" request
  while true; do
    for request in "$shots"/*.request; do
      [[ -e "$request" ]] || continue
      case "$(basename "$request" .request)" in
      cmd-lock)
        xcrun simctl spawn "$udid" "$work/lock_button"
        sleep 4
        xcrun simctl spawn "$udid" "$work/lock_button"
        sleep 4
        screenshot "$device" "$udid" "$shots/lock-screen.png"
        touch "$shots/done"
        return
        ;;
      failure)
        screenshot "$device" "$udid" "$shots/failure.png"
        touch "$shots/failed"
        return
        ;;
      *)
        screenshot "$device" "$udid" "${request%.request}.png"
        ;;
      esac
      rm -f "$request"
    done
    sleep 0.3
  done
}

# Walks the app on one simulator in one language.
take() {
  local device="$1" udid="$2" locale="$3"
  local shots="$work/raw/$device/$locale" waited=0 watcher app data
  mkdir -p "$shots"
  rm -f "$shots"/*

  # Restarted, for the language and because a simulator left running may
  # still show what an earlier walk left on it, such as a permission prompt
  # nothing answered.
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  set_language "$udid" "$locale"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" >/dev/null
  [[ "$device" != duo ]] || wait_open "$udid" "$shots"
  # The date as well as the time: a time alone puts the Lock Screen on
  # 1 January. simctl takes an ISO date only with milliseconds and a colon
  # in the time zone, and the simulator (iOS 26.5) keeps its day and month
  # only in English: in the other languages the Lock Screen shows 1 January
  # whatever the date.
  local zone
  zone="$(date +%z)"
  xcrun simctl status_bar "$udid" override \
    --time "$(date +%Y-%m-%d)T09:41:00.000${zone:0:3}:${zone:3}" \
    --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 \
    --dataNetwork wifi --operatorName ""
  xcrun simctl ui "$udid" appearance dark
  # Praça do Comércio, Lisbon: where the newest photos of the card are from.
  xcrun simctl location "$udid" set 38.7075,-9.1364
  # A fresh install, so every walk starts from the same state. iOS would
  # ask for the location over the screens and whether to allow Live
  # Activities under the first one, where nothing can answer.
  xcrun simctl uninstall "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl install "$udid" "$root/app/build/ios/iphonesimulator/Runner.app"
  xcrun simctl privacy "$udid" grant location-always "$bundle"
  allow_live_activities "$udid"
  # Where the walk finds its folders: an app started on a simulator gets
  # nothing from the host's environment.
  data="$(xcrun simctl get_app_container "$udid" "$bundle" data)/Library/Application Support"
  mkdir -p "$data"
  jq -n --arg shots "$shots" --arg media "$media" '{$shots, $media}' \
    >"$data/store-screenshots.json"

  watch_requests "$device" "$udid" "$shots" &
  watcher=$!
  xcrun simctl launch --console "$udid" "$bundle" >"$shots/app.log" 2>&1 &
  app=$!
  # The locked app no longer runs the walk, so it ends with the Lock Screen
  # rather than with the app.
  until [[ -e "$shots/done" || -e "$shots/failed" || $waited -ge $walk_seconds ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  kill "$watcher" "$app" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
  xcrun simctl shutdown "$udid"
  rm -f "$shots"/*.request
  if [[ ! -e "$shots/done" ]]; then
    echo "$device $locale: the walk ended before its last screen; see $shots/failure.txt" >&2
    return 1
  fi
  rm -f "$shots/done"
  echo "$device $locale"
}

# Every language on one simulator, which is left in English.
take_all() {
  local device="$1" udid="$2" locale failed=0
  for locale in "${locales[@]}"; do
    take "$device" "$udid" "$locale" || failed=1
  done
  set_language "$udid" en
  return $failed
}

for locale in "${locales[@]}"; do
  ios_language "$locale" >/dev/null
done
fetch_media
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator \
  "$here/lock_button.c" -o "$work/lock_button" -framework CoreFoundation
(cd "$root/app" && flutter build ios --simulator --debug --flavor dev \
  --target integration_test/store_screens_test.dart)

running=()
for device in "${devices[@]}"; do
  take_all "${device%%=*}" "${device#*=}" &
  running+=($!)
done
trap 'kill "${running[@]}" 2>/dev/null || true' INT TERM
status=0
for job in "${running[@]}"; do
  wait "$job" || status=1
done
exit $status
