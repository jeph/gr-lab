#!/usr/bin/env bash
# Code-quality checks for the whole workspace. Every check must pass; see
# AGENTS.md. `--static` skips the test suites (used by the Android and iOS
# builds, which refuse to build when a static check fails).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

# Xcode and Gradle run this with a minimal PATH; Flutter's SDK has dart.
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  PATH="$FLUTTER_ROOT/bin:$PATH"
fi

static_only=false
for arg in "$@"; do
  case "$arg" in
  --static) static_only=true ;;
  *)
    echo "usage: tool/check.sh [--static]" >&2
    exit 2
    ;;
  esac
done

failed=()
step() {
  local name="$1"
  shift
  echo "== $name"
  if ! "$@"; then
    failed+=("$name")
  fi
}

dart_packages=(packages/gr_protocol packages/gr_fake_camera)
flutter_packages=(packages/gr_camera app)

step "format" dart format --output=none --set-exit-if-changed \
  "${dart_packages[@]}" "${flutter_packages[@]}" tool

for p in "${dart_packages[@]}" "${flutter_packages[@]}"; do
  step "analyze $p" bash -c "cd '$p' && dart analyze --fatal-infos"
done
step "analyze tool" dart analyze --fatal-infos tool

step "camera layer boundary" "$root/tool/check_boundary.sh"
step "translated text" dart run tool/check_strings.dart app/lib
step "translations" dart run tool/check_translations.dart app/lib/l10n

if [[ "$static_only" == false ]]; then
  for p in "${dart_packages[@]}"; do
    step "test $p" bash -c "cd '$p' && dart test"
  done
  for p in "${flutter_packages[@]}"; do
    if [[ -d "$p/test" ]]; then
      step "test $p" bash -c "cd '$p' && flutter test --no-pub"
    fi
  done
  step "test tool/app_store" python3 -m unittest discover -s tool/app_store -p '*_test.py'
fi

if ((${#failed[@]})); then
  printf 'FAILED: %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "All checks passed."
