#!/usr/bin/env bash
# Renders the app icon's PNGs for iOS and Android from app/icon/icon.svg.
# Run it after editing the SVG and commit the PNGs it writes.
#
# Needs resvg (https://github.com/linebender/resvg) and ImageMagick's
# `magick` on PATH.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
svg="$root/app/icon/icon.svg"
ios="$root/app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
android="$root/app/android/app/src/main/res"

# render <variant id> <width in px> <output>
# Draws the whole page with only that variant group showing. (resvg's
# --export-id would be the direct way, but 0.49 misplaces a group on a page
# whose viewBox starts below zero.)
render() {
  # The engraving on the lens is set in the app's own JetBrains Mono.
  resvg --skip-system-fonts --use-fonts-dir "$root/app/assets/fonts" \
    --stylesheet <(printf '.variant { display: none } #%s { display: inline }' "$1") \
    --width "$2" "$svg" "$3"
}

# iOS: one 1024 px image per appearance, the square in the middle of the
# page at one pixel per unit. App Store Connect rejects an icon that has an
# alpha channel, so drop the one resvg always writes.
for appearance in default:AppIcon dark:AppIcon-Dark tinted:AppIcon-Tinted; do
  output="$ios/${appearance#*:}.png"
  render "ios-${appearance%%:*}" 1536 "$output"
  magick "$output" -gravity center -crop 1024x1024+0+0 +repage \
    -alpha off "PNG24:$output"
done

# Android: the adaptive icon's layers, the whole page, which is 108 dp at
# each density.
for density in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  for layer in foreground monochrome; do
    render "android-$layer" "${density#*:}" \
      "$android/mipmap-${density%%:*}/ic_launcher_$layer.png"
  done
done
