#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build_and_run.sh [MODE] [--release] [-- SWIFT_BUILD_ARGUMENTS...]

Modes (default: run):
  run                 Build the app bundle and launch it
  --build             Build the app bundle without stopping or launching the app
  --install           Build a release app, install/upgrade it in Applications, and launch it
  --debug             Launch the rebuilt app under LLDB (System Sleep control unavailable)
  --logs              Launch and stream process logs
  --telemetry         Launch and stream LockHold's own logs
  --verify            Launch and check that the process remains running
  --help              Show this help without building

Pass --release for an optimised build; debug is the default.
Set LOCKHOLD_DIST_DIR to an absolute path to build outside the checkout.
Set LOCKHOLD_INSTALL_DIR to an absolute path to install somewhere other than /Applications.
Set LOCKHOLD_SIGN_IDENTITY to a signing identity, or - for an ad-hoc build without sleep control.
Otherwise a single available signing identity is selected automatically.
USAGE
}

MODE="run"
CONFIGURATION="debug"
while [[ $# -gt 0 ]]; do
  case "$1" in
    run) MODE="run" ;;
    --build|build) MODE="build" ;;
    --install|install) MODE="install" ;;
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
if [[ "$MODE" == "install" ]]; then
  CONFIGURATION="release"
  DIST_DIR="${LOCKHOLD_INSTALL_DIR:-/Applications}"
fi
if [[ "$DIST_DIR" != /* ]]; then
  echo "LOCKHOLD_DIST_DIR and LOCKHOLD_INSTALL_DIR must be absolute paths." >&2
  exit 2
fi
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Assets/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"

LOCK_DIR="$DIST_DIR/.lockhold-build.lock"
LOCK_HELD=false
STAGING_DIR=""
PREVIOUS_APP=""
INSTALLING=false
HAD_PREVIOUS=false

release_lock() {
  if [[ "$LOCK_HELD" == true ]]; then
    rm -f "$LOCK_DIR/pid" && rmdir "$LOCK_DIR" || return 1
    LOCK_HELD=false
  fi
}

cleanup() {
  local result=$? retain_backup=false
  trap - EXIT
  if [[ "$INSTALLING" == true ]]; then
    if [[ -e "$PREVIOUS_APP" || -L "$PREVIOUS_APP" ]]; then
      if ! rm -rf "$APP_BUNDLE" || ! mv "$PREVIOUS_APP" "$APP_BUNDLE"; then
        printf 'Could not restore the previous app. Backup retained at %s\n' "$PREVIOUS_APP" >&2
        retain_backup=true
        result=1
      fi
    elif [[ "$HAD_PREVIOUS" == false ]]; then
      rm -rf "$APP_BUNDLE" || result=1
    fi
  fi
  if [[ "$retain_backup" == false && -n "$STAGING_DIR" ]]; then
    rm -rf "$STAGING_DIR" || result=1
  fi
  release_lock || result=1
  exit "$result"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Hold one destination lock through inspection, building, replacement, and rollback.
# A contender must never read or remove another invocation's temporary app state.
mkdir -p "$DIST_DIR"
if ! mkdir "$LOCK_DIR"; then
  printf 'Cannot lock %s. If another build or install is running, wait for it to finish and retry.\n' "$DIST_DIR" >&2
  printf 'If a previous build was forcibly killed, confirm it has ended before removing %s.\n' "$LOCK_DIR" >&2
  exit 1
fi
LOCK_HELD=true
printf '%s\n' "$$" > "$LOCK_DIR/pid"

if [[ "$MODE" == "install" && ( -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ) ]]; then
  if [[ -L "$APP_BUNDLE" ]]; then
    echo "Refusing to replace a symbolic link at $APP_BUNDLE." >&2
    exit 1
  fi
  EXISTING_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Contents/Info.plist")"
  if [[ "$EXISTING_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "Refusing to replace an app with a different bundle identifier at $APP_BUNDLE." >&2
    exit 1
  fi
fi
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

if [[ "$MODE" != "build" && "$MODE" != "install" ]]; then
  stop_app
fi

swift build "${SWIFT_BUILD_ARGUMENTS[@]}"
BUILD_BINARY_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_BINARY_DIR/$APP_NAME"

# Assemble and validate a replacement before removing the previous bundle.
STAGING_DIR="$(mktemp -d "$DIST_DIR/.lockhold-build.XXXXXX")"
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
PREVIOUS_APP="$STAGING_DIR/Previous.app"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources" "$STAGED_APP/Contents/Library/LaunchDaemons"
cp -X "$BUILD_BINARY" "$STAGED_APP/Contents/MacOS/$APP_NAME"
cp -X "$BUILD_BINARY_DIR/LockHoldSleepHelper" "$STAGED_APP/Contents/MacOS/LockHoldSleepHelper"
cp -X "$ROOT_DIR/Assets/dev.codex.LockHold.SleepHelper.plist" "$STAGED_APP/Contents/Library/LaunchDaemons/"
cp -X "$INFO_PLIST" "$STAGED_APP/Contents/Info.plist"
cp -X "$ROOT_DIR/Assets/$APP_NAME.icns" "$STAGED_APP/Contents/Resources/"
cp -X "$ROOT_DIR/LICENSE" "$STAGED_APP/Contents/Resources/"
chmod +x "$STAGED_APP/Contents/MacOS/$APP_NAME"
chmod +x "$STAGED_APP/Contents/MacOS/LockHoldSleepHelper"
plutil -lint "$STAGED_APP/Contents/Info.plist"
plutil -lint "$STAGED_APP/Contents/Library/LaunchDaemons/dev.codex.LockHold.SleepHelper.plist"

# A stable Apple-issued identity is required by the helper's mutual XPC validation.
# The ad-hoc fallback keeps the original Auto-Lock feature usable without an account.
SIGN_IDENTITY="${LOCKHOLD_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITIES="$(security find-identity -p codesigning -v 2>/dev/null | awk '$1 ~ /^[0-9]+\)$/ && length($2) == 40 { print $2 }')"
  if [[ -n "$SIGN_IDENTITIES" && "$SIGN_IDENTITIES" != *$'\n'* ]]; then
    SIGN_IDENTITY="$SIGN_IDENTITIES"
  elif [[ -n "$SIGN_IDENTITIES" ]]; then
    echo 'Multiple signing identities found. Select one with LOCKHOLD_SIGN_IDENTITY, or use - for an ad-hoc build.' >&2
    exit 1
  else
    SIGN_IDENTITY="-"
  fi
fi
codesign --force --options runtime --identifier "$BUNDLE_ID.SleepHelper" --sign "$SIGN_IDENTITY" "$STAGED_APP/Contents/MacOS/LockHoldSleepHelper"
APP_SIGN_ARGUMENTS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$MODE" == "debug" ]]; then
  # Only this debugger variant can be attached to; the root helper rejects such clients.
  APP_SIGN_ARGUMENTS+=(--entitlements "$ROOT_DIR/Assets/Debug.entitlements")
fi
codesign "${APP_SIGN_ARGUMENTS[@]}" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP/Contents/MacOS/LockHoldSleepHelper"
codesign --verify --strict "$STAGED_APP"

if [[ "$MODE" == "install" ]]; then
  # Keep the installed app running until its replacement is ready.
  stop_app
fi

if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
  HAD_PREVIOUS=true
fi
INSTALLING=true
if [[ "$HAD_PREVIOUS" == true ]]; then
  mv "$APP_BUNDLE" "$PREVIOUS_APP"
fi
mv "$STAGED_APP" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"
if [[ "$MODE" == "install" ]]; then
  open -n "$APP_BUNDLE"
fi
INSTALLING=false
rm -rf "$STAGING_DIR"
release_lock
trap - EXIT INT TERM
printf 'Built %s (%s)\n' "$APP_BUNDLE" "$CONFIGURATION"
if [[ "$MODE" == "debug" ]]; then
  echo 'Debugger build: System Sleep control is unavailable. Use --install for the approved-helper feature.'
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo 'Ad-hoc build: Auto-Lock works; the privileged sleep helper requires an Apple Development or Developer ID identity.'
fi
if [[ "$MODE" == "install" ]]; then
  printf 'Installed and launched %s\n' "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  build|install) ;;
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
