#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_and_run.sh [MODE] [--release] [-- SWIFT_BUILD_ARGUMENTS...]

Modes (default: run):
  run                 Build the app bundle and launch it
  --build             Build the app bundle without stopping or launching the app
  --debug             Launch the rebuilt app under LLDB
  --logs              Launch and stream process logs
  --telemetry         Launch and stream LockHold's own logs
  --verify            Launch and check that the process remains running
  --help              Show this help without building

Pass --release for an optimised build; debug is the default.
Set LOCKHOLD_DIST_DIR to an absolute path to build outside the checkout.
USAGE
}

MODE="run"
CONFIGURATION="debug"
while [[ $# -gt 0 ]]; do
  case "$1" in
    run) MODE="run" ;;
    --build|build) MODE="build" ;;
    --debug|debug) MODE="debug" ;;
    --logs|logs) MODE="logs" ;;
    --telemetry|telemetry) MODE="telemetry" ;;
    --verify|verify) MODE="verify" ;;
    --release) CONFIGURATION="release" ;;
    --help|-h) usage; exit 0 ;;
    --) shift; break ;;
    *) usage >&2; exit 2 ;;
  esac
  shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "LockHold requires macOS." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LockHold"
DIST_DIR="${LOCKHOLD_DIST_DIR:-$ROOT_DIR/dist}"
if [[ "$DIST_DIR" != /* ]]; then
  echo "LOCKHOLD_DIST_DIR must be an absolute path." >&2
  exit 2
fi
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Assets/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
SWIFT_BUILD_ARGUMENTS=(--package-path "$ROOT_DIR" --configuration "$CONFIGURATION" "$@")

# Keep generated caches local to the checkout, while honouring explicit overrides.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$ROOT_DIR/.build/cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/cache/clang}"
export SWIFTPM_MODULECACHE_PATH="${SWIFTPM_MODULECACHE_PATH:-$ROOT_DIR/.build/cache/swiftpm}"

stop_app() {
  local current_user
  current_user="$(id -u)"
  if ! pgrep -x -u "$current_user" "$APP_NAME" >/dev/null; then
    return
  fi

  pkill -x -u "$current_user" "$APP_NAME" || true
  for ((attempt = 0; attempt < 50; attempt++)); do
    if ! pgrep -x -u "$current_user" "$APP_NAME" >/dev/null; then
      return
    fi
    sleep 0.1
  done
  echo "LockHold is still running. Quit it before rebuilding." >&2
  exit 1
}

if [[ "$MODE" != "build" ]]; then
  stop_app
fi

swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --product "$APP_NAME"
BUILD_BINARY="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)/$APP_NAME"

# Assemble and validate a replacement before removing the previous bundle.
mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.lockhold-build.XXXXXX")"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
PREVIOUS_APP="$STAGING_DIR/Previous.app"
INSTALLING=false
HAD_PREVIOUS=false

cleanup() {
  local result=$?
  trap - EXIT
  if [[ "$INSTALLING" == true ]]; then
    if [[ -e "$PREVIOUS_APP" || -L "$PREVIOUS_APP" ]]; then
      if ! rm -rf "$APP_BUNDLE" || ! mv "$PREVIOUS_APP" "$APP_BUNDLE"; then
        printf 'Could not restore the previous app. Backup retained at %s\n' "$PREVIOUS_APP" >&2
        exit 1
      fi
    elif [[ "$HAD_PREVIOUS" == false ]]; then
      rm -rf "$APP_BUNDLE" || exit 1
    fi
  fi
  rm -rf "$STAGING_DIR" || exit 1
  exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp -X "$BUILD_BINARY" "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp -X "$INFO_PLIST" "$STAGED_APP/Contents/Info.plist"
cp -X "$ROOT_DIR/Assets/$APP_NAME.icns" "$STAGED_APP/Contents/Resources/"
cp -X "$ROOT_DIR/LICENSE" "$STAGED_APP/Contents/Resources/"
chmod +x "$STAGED_APP/Contents/MacOS/$APP_NAME"
plutil -lint "$STAGED_APP/Contents/Info.plist"

# Ad-hoc signing is for local builds, not Developer ID distribution or notarisation.
codesign --force --sign - "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"

if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
  HAD_PREVIOUS=true
fi
INSTALLING=true
if [[ "$HAD_PREVIOUS" == true ]]; then
  mv "$APP_BUNDLE" "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
INSTALLING=false
rm -rf "$STAGING_DIR"
trap - EXIT INT TERM
printf 'Built %s (%s)\n' "$APP_BUNDLE" "$CONFIGURATION"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build) ;;
  run) open_app ;;
  debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  verify)
    open_app
    sleep 2
    pgrep -x -u "$(id -u)" "$APP_NAME" >/dev/null
    echo "LockHold is running."
    ;;
esac
