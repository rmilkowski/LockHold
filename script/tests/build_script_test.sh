#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lockhold-build-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
FIXTURE="$TEST_DIR/project with spaces"
mkdir -p "$FIXTURE/script" "$FIXTURE/Assets" "$TEST_DIR/tools" "$TEST_DIR/output with spaces"
cp "$ROOT_DIR/script/build_and_run.sh" "$FIXTURE/script/"
cp "$ROOT_DIR/Assets/Info.plist" "$ROOT_DIR/Assets/LockHold.icns" "$FIXTURE/Assets/"
cp "$ROOT_DIR/LICENSE" "$FIXTURE/"

export LOCKHOLD_TEST_PACKAGE="$FIXTURE"
export LOCKHOLD_DIST_DIR="$FIXTURE/dist"
export LOCKHOLD_TEST_BINARY_DIR="$TEST_DIR/output with spaces"
export LOCKHOLD_TEST_CALLS="$TEST_DIR/calls"
export LOCKHOLD_TEST_FAIL="none"
export PATH="$TEST_DIR/tools:$PATH"
touch "$LOCKHOLD_TEST_CALLS"
printf 'fixture executable\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"

# Run the real packaging script with build/sign/process stubs and controlled
# move failures. No real app is launched, stopped, or signed here.
cat > "$TEST_DIR/tools/swift" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift\n' >> "$LOCKHOLD_TEST_CALLS"
[[ "$1" == "build" && "$2" == "--package-path" && "$3" == "$LOCKHOLD_TEST_PACKAGE" ]]
if [[ "$LOCKHOLD_TEST_FAIL" == "build" ]]; then exit 42; fi
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$LOCKHOLD_TEST_BINARY_DIR"
fi
STUB
cat > "$TEST_DIR/tools/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign\n' >> "$LOCKHOLD_TEST_CALLS"
if [[ "$LOCKHOLD_TEST_FAIL" == "sign" ]]; then exit 43; fi
if [[ "$LOCKHOLD_TEST_FAIL" == "final" || "$LOCKHOLD_TEST_FAIL" == "restore" ]]; then
  if [[ "$*" == "--verify --strict $LOCKHOLD_DIST_DIR/LockHold.app" ]]; then exit 44; fi
fi
STUB
cat > "$TEST_DIR/tools/mv" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$2" == "$LOCKHOLD_DIST_DIR/LockHold.app" ]]; then
  if [[ "$LOCKHOLD_TEST_FAIL" == "promote" && "$1" == */.lockhold-build.*/LockHold.app ]]; then
    exit 45
  fi
  if [[ "$LOCKHOLD_TEST_FAIL" == "restore" && "$1" == */Previous.app ]]; then
    exit 46
  fi
fi
exec /bin/mv "$@"
STUB
cat > "$TEST_DIR/tools/pgrep" <<'STUB'
#!/usr/bin/env bash
printf 'pgrep\n' >> "$LOCKHOLD_TEST_CALLS"
echo 'Unexpected process lookup in build-only mode' >&2
exit 99
STUB
cat > "$TEST_DIR/tools/pkill" <<'STUB'
#!/usr/bin/env bash
printf 'pkill\n' >> "$LOCKHOLD_TEST_CALLS"
echo 'Unexpected process termination in build-only mode' >&2
exit 99
STUB
chmod +x "$TEST_DIR/tools/"* "$FIXTURE/script/build_and_run.sh"

# Reproduce invocation by absolute path from outside the package directory.
cd "$TEST_DIR"
"$FIXTURE/script/build_and_run.sh" --help > /dev/null
if "$FIXTURE/script/build_and_run.sh" --invalid > /dev/null 2>&1; then
  echo 'Invalid mode unexpectedly succeeded' >&2
  exit 1
else
  [[ $? -eq 2 ]]
fi
[[ ! -s "$LOCKHOLD_TEST_CALLS" ]]
[[ ! -d "$FIXTURE/dist" ]]

BUNDLE="$FIXTURE/dist/LockHold.app"

assert_no_staging() {
  if compgen -G "$FIXTURE/dist/.lockhold-build.*" > /dev/null; then
    echo 'Unexpected staging directory remains' >&2
    exit 1
  fi
}

# A failed first build must not leave an unverified app at the destination.
export LOCKHOLD_TEST_FAIL=final
if "$FIXTURE/script/build_and_run.sh" --build > /dev/null 2>&1; then
  echo 'Final verification failure unexpectedly succeeded' >&2
  exit 1
else
  [[ $? -eq 44 ]]
fi
[[ ! -e "$BUNDLE" ]]
assert_no_staging

export LOCKHOLD_TEST_FAIL=none
: > "$LOCKHOLD_TEST_CALLS"
"$FIXTURE/script/build_and_run.sh" --build
cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHold" "$BUNDLE/Contents/MacOS/LockHold"
cmp "$FIXTURE/Assets/Info.plist" "$BUNDLE/Contents/Info.plist"
cmp "$FIXTURE/LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
[[ -x "$BUNDLE/Contents/MacOS/LockHold" ]]
[[ $(wc -l < "$LOCKHOLD_TEST_CALLS") -eq 5 ]]

printf 'keep the existing bundle\n' > "$BUNDLE/keep"
cp "$BUNDLE/Contents/MacOS/LockHold" "$TEST_DIR/previous-binary"
printf 'replacement executable\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"
for failure in build sign promote final; do
  export LOCKHOLD_TEST_FAIL="$failure"
  if "$FIXTURE/script/build_and_run.sh" --build > /dev/null 2>&1; then
    echo "Simulated $failure failure unexpectedly succeeded" >&2
    exit 1
  fi
  [[ -f "$BUNDLE/keep" ]]
  cmp "$TEST_DIR/previous-binary" "$BUNDLE/Contents/MacOS/LockHold"
  assert_no_staging
done

# If restoring fails too, the backup must survive the EXIT cleanup.
export LOCKHOLD_TEST_FAIL=restore
if "$FIXTURE/script/build_and_run.sh" --build > "$TEST_DIR/restore.log" 2>&1; then
  echo 'Restore failure unexpectedly succeeded' >&2
  exit 1
fi
BACKUP_DIR="$(compgen -G "$FIXTURE/dist/.lockhold-build.*")"
[[ -f "$BACKUP_DIR/Previous.app/keep" ]]
cmp "$TEST_DIR/previous-binary" "$BACKUP_DIR/Previous.app/Contents/MacOS/LockHold"
[[ "$(cat "$TEST_DIR/restore.log")" == *"Backup retained at $BACKUP_DIR/Previous.app"* ]]
/bin/mv "$BACKUP_DIR/Previous.app" "$BUNDLE"
rmdir "$BACKUP_DIR"

# A successful retry replaces the old bundle and removes the backup.
export LOCKHOLD_TEST_FAIL=none
"$FIXTURE/script/build_and_run.sh" --build
[[ ! -e "$BUNDLE/keep" ]]
cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHold" "$BUNDLE/Contents/MacOS/LockHold"
assert_no_staging

echo 'Build-script regression checks passed.'
