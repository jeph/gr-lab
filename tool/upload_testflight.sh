#!/usr/bin/env bash
# Uploads a signed .ipa to App Store Connect, where it appears under
# TestFlight once processed. .github/workflows/release.yml runs this in a
# job that holds the upload key and nothing else.
#
# Usage: tool/upload_testflight.sh <app.ipa>
#
# Environment:
#   APP_STORE_CONNECT_API_KEY_P8      the App Store Connect API key, the
#                                     contents of its AuthKey_<key id>.p8 file.
#                                     The Developer role is enough to upload.
#   APP_STORE_CONNECT_API_KEY_ID      the key's ID
#   APP_STORE_CONNECT_API_ISSUER_ID   the issuer ID of the team's keys
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <app.ipa>" >&2
  exit 2
fi
ipa=$1

: "${APP_STORE_CONNECT_API_KEY_P8:?is not set}"
: "${APP_STORE_CONNECT_API_KEY_ID:?is not set}"
: "${APP_STORE_CONNECT_API_ISSUER_ID:?is not set}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
key="$work/AuthKey_$APP_STORE_CONNECT_API_KEY_ID.p8"
(
  umask 077
  printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" >"$key"
)

xcrun altool --upload-app -f "$ipa" -t ios \
  --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
  --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
  --p8-file-path "$key"
