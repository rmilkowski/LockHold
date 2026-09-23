#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--fix" ) ]]; then
  echo "Usage: lint.sh [--fix]" >&2
  exit 2
fi
if ! command -v shellcheck >/dev/null; then
  echo "ShellCheck is required. Install it with: brew install shellcheck" >&2
  exit 1
fi

SWIFT_FILES=("$ROOT_DIR/Package.swift" "$ROOT_DIR/Sources" "$ROOT_DIR/Tests")
if [[ "${1:-}" == "--fix" ]]; then
  swift format format --in-place --recursive --configuration "$ROOT_DIR/.swift-format" "${SWIFT_FILES[@]}"
fi
swift format lint --strict --recursive --configuration "$ROOT_DIR/.swift-format" "${SWIFT_FILES[@]}"

SHELL_FILES=("$ROOT_DIR"/script/*.sh "$ROOT_DIR"/script/tests/*.sh)
for script_file in "${SHELL_FILES[@]}"; do
  bash -n "$script_file"
done
shellcheck --severity=style "${SHELL_FILES[@]}"
plutil -lint "$ROOT_DIR/Assets/Info.plist"
plutil -lint "$ROOT_DIR/Assets/Debug.entitlements"
plutil -lint "$ROOT_DIR/Assets/dev.codex.LockHold.SleepHelper.plist"
echo "Lint passed."
