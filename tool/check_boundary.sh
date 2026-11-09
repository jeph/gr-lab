#!/usr/bin/env bash
# The app talks to cameras only through package:gr_camera (AGENTS.md,
# "Camera layer"). Fails when app code imports the protocol, the BLE plugin
# or gr_camera internals. The demo composition root may build the simulated
# camera from gr_fake_camera; nothing else in app/lib may.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root/app"

status=0
report() {
  echo "camera layer boundary: $1" >&2
  echo "$2" >&2
  status=1
}

if hits=$(grep -rnE "package:(gr_protocol|universal_ble)/|package:gr_camera/src/" lib); then
  report "app/lib must use package:gr_camera/gr_camera.dart only" "$hits"
fi

if hits=$(grep -rnE "package:gr_fake_camera/" lib --exclude-dir=demo); then
  report "only app/lib/src/demo may use the simulated camera" "$hits"
fi

exit "$status"
