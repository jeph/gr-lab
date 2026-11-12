#!/usr/bin/env bash
# Installs the Flutter SDK for .github/workflows/release.yml: downloads
# Flutter's own archive of one pinned version, refuses it unless its SHA-256
# is the pinned one, and puts flutter and dart on the PATH of later steps.
#
# Usage: tool/install_flutter.sh
#
# Environment:
#   FLUTTER_VERSION              the stable release to install, such as 3.47.9
#   FLUTTER_SHA256_LINUX_X64     the SHA-256 of that release's Linux archive
#   FLUTTER_SHA256_MACOS_ARM64   the SHA-256 of its macOS archive for Apple silicon
#   RUNNER_TEMP, GITHUB_PATH     set by GitHub Actions
#
# The digests are the `sha256` values in
# https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json
# and releases_macos.json.
set -euo pipefail

: "${FLUTTER_VERSION:?is not set}"
: "${RUNNER_TEMP:?is not set}"
: "${GITHUB_PATH:?is not set}"

case "$(uname -s)-$(uname -m)" in
Linux-x86_64)
  archive="linux/flutter_linux_$FLUTTER_VERSION-stable.tar.xz"
  sha256="${FLUTTER_SHA256_LINUX_X64:?is not set}"
  ;;
Darwin-arm64)
  archive="macos/flutter_macos_arm64_$FLUTTER_VERSION-stable.zip"
  sha256="${FLUTTER_SHA256_MACOS_ARM64:?is not set}"
  ;;
*)
  echo "no pinned Flutter archive for $(uname -s) $(uname -m)" >&2
  exit 1
  ;;
esac

download="$RUNNER_TEMP/${archive##*/}"
curl --fail --silent --show-error --location --output "$download" \
  "https://storage.googleapis.com/flutter_infra_release/releases/stable/$archive"
echo "$sha256  $download" | shasum --algorithm 256 --check

case "$download" in
*.tar.xz) tar -xJf "$download" -C "$RUNNER_TEMP" ;;
*.zip) unzip -q "$download" -d "$RUNNER_TEMP" ;;
esac
rm "$download"

echo "$RUNNER_TEMP/flutter/bin" >>"$GITHUB_PATH"
"$RUNNER_TEMP/flutter/bin/flutter" --version
