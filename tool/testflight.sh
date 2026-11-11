#!/usr/bin/env bash
# Builds the prod iOS app and uploads it to TestFlight.
#
#   tool/testflight.sh [build number]
#
# Xcode signs and uploads the build with an App Store Connect API key of
# the Admin role (a lesser role may not use the team's distribution
# certificate): its AuthKey_<key id>.p8 file in
# ~/.appstoreconnect/private_keys, and ASC_KEY_ID and ASC_ISSUER_ID set in
# ~/.appstoreconnect/gr-lab.env.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$HOME/.appstoreconnect/gr-lab.env"

if [[ ! -f "$config" ]]; then
  echo "missing $config (ASC_KEY_ID and ASC_ISSUER_ID)" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$config"

# App Store Connect takes each build number once and wants every upload of
# a version to be higher than the last; the time of the build is both.
build_number="${1:-$(date -u +%y%m%d%H%M)}"

cd "$root/app"

# Regenerates AppLocalizations from the ARB files. The build's own pub get
# does not, and its static checks then fail on messages a pull brought in.
flutter pub get

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

# The key, not an Apple account added in Xcode's settings: the sign-in
# Xcode saved for one stopped working within the hour, twice (Xcode 27.1,
# 2026-11-10).
xcodebuild -exportArchive -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -archivePath "$archive" \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath build/ios/ipa
