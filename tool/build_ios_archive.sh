#!/usr/bin/env bash
# Builds the prod iOS app as an Xcode archive that no signing identity has
# signed, for a later step to sign for the App Store: tool/testflight.sh on
# a Mac, tool/sign_ios_archive.sh in a release.
#
#   tool/build_ios_archive.sh [flutter build options]
#
# The options go to `flutter build ipa`, for example `--build-number 7`.
# The archive is app/build/ios/archive/Runner.xcarchive.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/app"

# Regenerates AppLocalizations from the ARB files. The build's own pub get
# does not, and its static checks then fail on messages a pull brought in.
flutter pub get

# Flutter leaves the archive unsigned: signing it would take a development
# provisioning profile, which Apple only issues to a team with a registered
# device. The export that follows signs it for the App Store, which needs
# none.
flutter build ipa --flavor prod --release --no-codesign "$@"

# The export copies the app's entitlements from the archive's signature, so
# an unsigned archive would lose the Wi-Fi entitlements and the app could
# not join the camera's network. An ad hoc signature carries them. The
# LiveActivity extension inside the app has no entitlements; it is signed
# first, as nested code is, so that the app's signature seals signed code.
app=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
codesign --force --sign - "$app/PlugIns/LiveActivity.appex"
codesign --force --sign - --entitlements ios/Runner/Runner.entitlements "$app"
