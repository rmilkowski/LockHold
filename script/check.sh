#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/lint.sh"
swift test --package-path "$ROOT_DIR" -Xswiftc -warnings-as-errors "$@"
"$ROOT_DIR/script/tests/build_script_test.sh"
