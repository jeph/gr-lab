#!/usr/bin/env bash
# Signs an archive from tool/build_ios_archive.sh for the App Store with
# GR Photo's distribution certificate and provisioning profiles, and checks
# the app that comes out. .github/workflows/release.yml runs this in a job
# that holds the certificate and nothing else.
#
# Usage: tool/sign_ios_archive.sh <Runner.xcarchive> <entitlements.plist> <output folder>
#
# The entitlements file is the app's own (app/ios/Runner/Runner.entitlements);
# the signed app has to carry every entitlement in it. The output folder
# receives the .ipa.
#
# Environment:
#   IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64  the Apple Distribution certificate
#                                            and its private key as PKCS12,
#                                            base64-encoded
#   IOS_DISTRIBUTION_CERTIFICATE_PASSWORD    the PKCS12 file's password
#   IOS_PROVISIONING_PROFILE_BASE64          the App Store provisioning profile
#                                            for the app, base64-encoded
#   IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64
#                                            the App Store provisioning profile
#                                            for the app's LiveActivity
#                                            extension, which has an App ID of
#                                            its own (the app's with
#                                            .LiveActivity added),
#                                            base64-encoded
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <Runner.xcarchive> <entitlements.plist> <output folder>" >&2
  exit 2
fi
archive=$1
entitlements=$2
output=$3

: "${IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64:?is not set}"
: "${IOS_DISTRIBUTION_CERTIFICATE_PASSWORD:?is not set}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?is not set}"
: "${IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64:?is not set}"

plist() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

work=$(mktemp -d)
keychain="$work/signing.keychain-db"
installed_profiles=()
# The keychains searched before this script. security prints each one
# indented and in double quotes.
searched=()
while IFS= read -r line; do
  line=${line#"${line%%[![:space:]]*}"}
  line=${line#\"}
  searched+=("${line%\"}")
done < <(security list-keychains -d user)
cleanup() {
  security list-keychains -d user -s ${searched[@]+"${searched[@]}"} >/dev/null 2>&1 || true
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -f ${installed_profiles[@]+"${installed_profiles[@]}"}
  rm -rf "$work"
}
trap cleanup EXIT

(
  umask 077
  printf '%s' "$IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64" | base64 --decode >"$work/certificate.p12"
  printf '%s' "$IOS_PROVISIONING_PROFILE_BASE64" | base64 --decode >"$work/app.mobileprovision"
  printf '%s' "$IOS_LIVE_ACTIVITY_PROVISIONING_PROFILE_BASE64" | base64 --decode >"$work/extension.mobileprovision"
)

# The app and its LiveActivity extension, which draws the app's Live
# Activities, are signed with a profile each. A profile says which team and
# bundle it signs for; the archive has to hold those bundles, and both
# profiles have to be the same team's.
bundles=(app extension)
bundle_ids=(
  "$(plist ApplicationProperties:CFBundleIdentifier "$archive/Info.plist")"
  "$(plist CFBundleIdentifier "$archive/Products/Applications/Runner.app/PlugIns/LiveActivity.appex/Info.plist")"
)
profile_uuids=()
team=
for i in "${!bundles[@]}"; do
  profile="$work/${bundles[$i]}"
  security cms -D -i "$profile.mobileprovision" >"$profile.plist"
  profile_uuids+=("$(plist UUID "$profile.plist")")
  team=${team:-$(plist TeamIdentifier:0 "$profile.plist")}
  profile_bundle=$(plist Entitlements:application-identifier "$profile.plist")
  if [[ "$profile_bundle" != "$team.${bundle_ids[$i]}" ]]; then
    echo "the ${bundles[$i]}'s provisioning profile is for $profile_bundle, not $team.${bundle_ids[$i]}" >&2
    exit 1
  fi
done

# A keychain of its own, with a password nobody else has, holds the
# certificate while xcodebuild signs and is deleted afterwards.
keychain_password=$(openssl rand -hex 32)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 3600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -P "$IOS_DISTRIBUTION_CERTIFICATE_PASSWORD" \
  -f pkcs12 -k "$keychain" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" >/dev/null
# xcodebuild looks for the certificate in the keychains the user searches.
security list-keychains -d user -s "$keychain" ${searched[@]+"${searched[@]}"} >/dev/null

profiles="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$profiles"
for i in "${!bundles[@]}"; do
  installed_profiles+=("$profiles/${profile_uuids[$i]}.mobileprovision")
  cp "$work/${bundles[$i]}.mobileprovision" "${installed_profiles[$i]}"
done

options="$work/ExportOptions.plist"
/usr/libexec/PlistBuddy \
  -c 'Add :method string app-store-connect' \
  -c 'Add :destination string export' \
  -c 'Add :signingStyle string manual' \
  -c "Add :teamID string $team" \
  -c 'Add :signingCertificate string Apple Distribution' \
  -c 'Add :provisioningProfiles dict' \
  -c "Add :provisioningProfiles:${bundle_ids[0]} string ${profile_uuids[0]}" \
  -c "Add :provisioningProfiles:${bundle_ids[1]} string ${profile_uuids[1]}" \
  -c 'Add :manageAppVersionAndBuildNumber bool false' \
  "$options" >/dev/null

xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$options" \
  -exportPath "$output"

ipas=("$output"/*.ipa)
if [[ ${#ipas[@]} -ne 1 || ! -f "${ipas[0]}" ]]; then
  echo "the export did not leave exactly one .ipa in $output" >&2
  exit 1
fi

# Checks that the bundle $1 is signed by the profiles' team for distribution
# and writes the entitlements it is signed with to $2.
check_signature() {
  local bundle=$1 entitlements=$2 signature
  codesign --verify --strict "$bundle"
  signature=$(codesign --display --verbose=2 "$bundle" 2>&1)
  if ! grep -q "^Authority=Apple Distribution: .*($team)$" <<<"$signature" ||
    ! grep -q "^TeamIdentifier=$team$" <<<"$signature"; then
    echo "${bundle##*/} is not signed with team $team's Apple Distribution certificate" >&2
    exit 1
  fi
  codesign --display --entitlements - --xml "$bundle" >"$entitlements" 2>/dev/null
  if [[ "$(plist get-task-allow "$entitlements")" != false ]]; then
    echo "${bundle##*/} lets a debugger attach (get-task-allow)" >&2
    exit 1
  fi
}

# The app in the .ipa and its extension have to be signed by the profiles'
# team for distribution, and the app has to still carry the entitlements it
# declares: an export that drops the Wi-Fi ones makes an app that cannot join
# the camera.
unzip -q "${ipas[0]}" -d "$work/ipa"
apps=("$work"/ipa/Payload/*.app)
app=${apps[0]}
check_signature "$app/PlugIns/LiveActivity.appex" "$work/extension-entitlements.plist"
check_signature "$app" "$work/signed-entitlements.plist"
while IFS= read -r key; do
  declared=$(plist "$key" "$entitlements")
  signed=$(plist "$key" "$work/signed-entitlements.plist" 2>/dev/null || true)
  if [[ "$signed" != "$declared" ]]; then
    echo "the signed app lacks the entitlement $key = $declared" >&2
    exit 1
  fi
done < <(plutil -convert xml1 -o - "$entitlements" | sed -n 's:.*<key>\(.*\)</key>.*:\1:p')
