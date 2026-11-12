#!/usr/bin/env bash
# Signs a release APK with GR Photo's release key and checks that the result
# carries the release certificate and nothing else. A signature the APK
# already has, such as the debug key's that the build leaves on it, is
# replaced. .github/workflows/release.yml runs this in a job that holds the
# signing secrets and nothing else.
#
# Adapted from scripts/sign-release-apk.sh of Pipkin (github.com/jeph/pipkin,
# v0.0.22, MIT License).
#
# Usage: tool/sign_release_apk.sh <built.apk> <signed.apk>
#
# Environment:
#   ANDROID_RELEASE_KEYSTORE_BASE64    the PKCS12 keystore, base64-encoded
#   ANDROID_RELEASE_KEYSTORE_PASSWORD  the keystore's password, which PKCS12
#                                      also uses for the key
#   ANDROID_RELEASE_KEY_ALIAS          the key's alias in the keystore
#   ANDROID_RELEASE_CERT_SHA256        the SHA-256 digest of the release
#                                      certificate, in hex; colons are optional
#   BUILD_TOOLS                        the Android build-tools folder holding
#                                      zipalign and apksigner
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <built.apk> <signed.apk>" >&2
  exit 2
fi
built=$1
signed=$2

: "${ANDROID_RELEASE_KEYSTORE_BASE64:?is not set}"
: "${ANDROID_RELEASE_KEYSTORE_PASSWORD:?is not set}"
: "${ANDROID_RELEASE_KEY_ALIAS:?is not set}"
: "${ANDROID_RELEASE_CERT_SHA256:?is not set}"
: "${BUILD_TOOLS:?is not set}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
keystore="$work/release.p12"
(
  umask 077
  printf '%s' "$ANDROID_RELEASE_KEYSTORE_BASE64" | base64 --decode >"$keystore"
)

# 16 KB page alignment keeps the APK installable on devices with 16 KB
# memory pages.
"$BUILD_TOOLS/zipalign" -P 16 -f 4 "$built" "$work/aligned.apk"
# The password reaches apksigner through the environment, never the command
# line.
"$BUILD_TOOLS/apksigner" sign \
  --ks "$keystore" \
  --ks-type PKCS12 \
  --ks-pass env:ANDROID_RELEASE_KEYSTORE_PASSWORD \
  --ks-key-alias "$ANDROID_RELEASE_KEY_ALIAS" \
  --v4-signing-enabled false \
  --out "$signed" \
  "$work/aligned.apk"

certificates=$("$BUILD_TOOLS/apksigner" verify --print-certs "$signed")
# apksigner prints one digest per signer and signature scheme; they must all
# name the one release certificate.
actual=$(sed -n 's/^.*certificate SHA-256 digest: //p' <<<"$certificates" | sort -u)
expected=$(printf '%s' "$ANDROID_RELEASE_CERT_SHA256" | tr -d ':' | tr 'A-F' 'a-f')
if [[ "$actual" != "$expected" ]]; then
  echo "$signed is signed by $actual, not the release certificate $expected" >&2
  exit 1
fi
