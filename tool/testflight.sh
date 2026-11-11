#!/usr/bin/env bash
# Builds the prod iOS app and uploads it to TestFlight.
#
#   tool/testflight.sh [build number]
#
# Xcode signs and uploads the build with the Apple account added in its
# settings (Settings > Accounts), which must belong to the project's
# development team; nothing else has to be set up on a Mac.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# App Store Connect takes each build number once and wants every upload of
# a version to be higher than the last; the time of the build is both.
build_number="${1:-$(date -u +%y%m%d%H%M)}"

cd "$root/app"

# Flutter leaves the archive unsigned: signing it would take a development
# provisioning profile, which Apple only issues to a team with a registered
# device. The export below signs it for the App Store, which needs none.
flutter build ipa --flavor prod --no-codesign --build-number "$build_number"

# The export copies the app's entitlements from the archive's signature, so
# an unsigned archive would lose the Wi-Fi entitlements and the app could
# not join the camera's network. An ad hoc signature carries them.
archive=build/ios/archive/Runner.xcarchive
codesign --force --sign - --entitlements ios/Runner/Runner.entitlements \
  "$archive/Products/Applications/Runner.app"

xcodebuild -exportArchive -allowProvisioningUpdates \
  -archivePath "$archive" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath build/ios/ipa
