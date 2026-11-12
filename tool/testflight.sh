#!/usr/bin/env bash
# Builds the prod iOS app on this Mac and uploads it to TestFlight, to try a
# build that is not a release. Releases are built and uploaded by
# .github/workflows/release.yml.
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

"$root/tool/build_ios_archive.sh" --build-number "$build_number"

cd "$root/app"

# The key, not an Apple account added in Xcode's settings: the sign-in
# Xcode saved for one stopped working within the hour, twice (Xcode 27.1,
# 2026-11-10).
xcodebuild -exportArchive -allowProvisioningUpdates \
  -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ios/ExportOptions.plist \
  -exportPath build/ios/ipa
