#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lockhold-build-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
FIXTURE="$TEST_DIR/project with spaces"
mkdir -p "$FIXTURE/script" "$FIXTURE/Assets" "$TEST_DIR/tools" "$TEST_DIR/output with spaces"
cp "$ROOT_DIR/script/build_and_run.sh" "$FIXTURE/script/"
cp "$ROOT_DIR/Assets/Info.plist" "$ROOT_DIR/Assets/LockHold.icns" "$FIXTURE/Assets/"
cp "$ROOT_DIR/Assets/dev.codex.LockHold.SleepHelper.plist" "$FIXTURE/Assets/"
cp "$ROOT_DIR/Assets/Debug.entitlements" "$FIXTURE/Assets/"
cp "$ROOT_DIR/LICENSE" "$FIXTURE/"

export LOCKHOLD_TEST_PACKAGE="$FIXTURE"
export LOCKHOLD_DIST_DIR="$FIXTURE/dist"
export LOCKHOLD_TEST_BINARY_DIR="$TEST_DIR/output with spaces"
export LOCKHOLD_TEST_CALLS="$TEST_DIR/calls"
export LOCKHOLD_TEST_FAIL="none"
export LOCKHOLD_TEST_ALLOW_PROCESS=0
export LOCKHOLD_TEST_PROCESS_STATE="$TEST_DIR/running"
export LOCKHOLD_TEST_LAUNCHED="$TEST_DIR/launched"
unset LOCKHOLD_INSTALL_DIR
export LOCKHOLD_SIGN_IDENTITY=-
export PATH="$TEST_DIR/tools:$PATH"
touch "$LOCKHOLD_TEST_CALLS"
printf 'fixture executable\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"
printf 'fixture helper\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHoldSleepHelper"

# Run the real packaging script with build/sign/process stubs and controlled
# move failures. No real app is launched, stopped, or signed here.
cat > "$TEST_DIR/tools/swift" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'swift\n' >> "$LOCKHOLD_TEST_CALLS"
[[ "$1" == "build" && "$2" == "--package-path" && "$3" == "$LOCKHOLD_TEST_PACKAGE" ]]
if [[ "$LOCKHOLD_TEST_ALLOW_PROCESS" == 1 ]]; then
  [[ "$4" == "--configuration" && "$5" == "${LOCKHOLD_TEST_CONFIGURATION:-release}" ]]
fi
if [[ "$LOCKHOLD_TEST_FAIL" == "build" ]]; then exit 42; fi
if [[ " $* " == *" --show-bin-path "* ]]; then
  printf '%s\n' "$LOCKHOLD_TEST_BINARY_DIR"
fi
STUB
cat > "$TEST_DIR/tools/codesign" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'codesign\n' >> "$LOCKHOLD_TEST_CALLS"
if [[ "$1" == "--force" ]]; then
  [[ " $* " == *' --options runtime '* ]]
  if [[ "${!#}" == */Contents/MacOS/LockHoldSleepHelper ]]; then
    [[ " $* " != *' --entitlements '* ]]
  elif [[ "${!#}" == */LockHold.app ]]; then
    if [[ "${LOCKHOLD_TEST_DEBUG_SIGNING:-0}" == 1 ]]; then
      [[ " $* " == *" --entitlements $LOCKHOLD_TEST_PACKAGE/Assets/Debug.entitlements "* ]]
      [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$LOCKHOLD_TEST_PACKAGE/Assets/Debug.entitlements")" == true ]]
    else
      [[ " $* " != *' --entitlements '* ]]
    fi
  else
    echo 'Unexpected signing target' >&2
    exit 99
  fi
fi
if [[ -n "${LOCKHOLD_TEST_GATE:-}" && "$*" == "--verify --strict ${LOCKHOLD_INSTALL_DIR:-$LOCKHOLD_DIST_DIR}/LockHold.app" ]]; then
  touch "$LOCKHOLD_TEST_GATE.ready"
  for ((attempt = 0; attempt < 500; attempt++)); do
    if [[ -f "$LOCKHOLD_TEST_GATE.release" ]]; then break; fi
    sleep 0.02
  done
  [[ -f "$LOCKHOLD_TEST_GATE.release" ]] || exit 98
fi
if [[ "$LOCKHOLD_TEST_FAIL" == "sign" ]]; then exit 43; fi
if [[ "$LOCKHOLD_TEST_FAIL" == "final" || "$LOCKHOLD_TEST_FAIL" == "restore" ]]; then
  if [[ "$*" == "--verify --strict ${LOCKHOLD_INSTALL_DIR:-$LOCKHOLD_DIST_DIR}/LockHold.app" ]]; then exit 44; fi
fi
STUB
cat > "$TEST_DIR/tools/mv" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$2" == "${LOCKHOLD_INSTALL_DIR:-$LOCKHOLD_DIST_DIR}/LockHold.app" ]]; then
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
set -euo pipefail
printf 'pgrep\n' >> "$LOCKHOLD_TEST_CALLS"
if [[ "$LOCKHOLD_TEST_ALLOW_PROCESS" != 1 ]]; then
  echo 'Unexpected process lookup in build-only mode' >&2
  exit 99
fi
[[ -f "$LOCKHOLD_TEST_PROCESS_STATE" ]]
STUB
cat > "$TEST_DIR/tools/pkill" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'pkill\n' >> "$LOCKHOLD_TEST_CALLS"
if [[ "$LOCKHOLD_TEST_ALLOW_PROCESS" != 1 ]]; then
  echo 'Unexpected process termination in build-only mode' >&2
  exit 99
fi
rm -f "$LOCKHOLD_TEST_PROCESS_STATE"
STUB
cat > "$TEST_DIR/tools/open" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'open\n' >> "$LOCKHOLD_TEST_CALLS"
[[ "$LOCKHOLD_TEST_ALLOW_PROCESS" == 1 ]]
[[ "$*" == "-n $LOCKHOLD_INSTALL_DIR/LockHold.app" ]]
if [[ "$LOCKHOLD_TEST_FAIL" == "open" ]]; then exit 47; fi
printf '%s\n' "$2" > "$LOCKHOLD_TEST_LAUNCHED"
touch "$LOCKHOLD_TEST_PROCESS_STATE"
STUB
cat > "$TEST_DIR/tools/lldb" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf 'lldb\n' >> "$LOCKHOLD_TEST_CALLS"
[[ "${LOCKHOLD_TEST_DEBUG_SIGNING:-0}" == 1 ]]
[[ "$*" == "-- $LOCKHOLD_DIST_DIR/LockHold.app/Contents/MacOS/LockHold" ]]
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
  if compgen -G "${LOCKHOLD_INSTALL_DIR:-$LOCKHOLD_DIST_DIR}/.lockhold-build.*" > /dev/null; then
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
cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHoldSleepHelper" "$BUNDLE/Contents/MacOS/LockHoldSleepHelper"
cmp "$FIXTURE/Assets/dev.codex.LockHold.SleepHelper.plist" "$BUNDLE/Contents/Library/LaunchDaemons/dev.codex.LockHold.SleepHelper.plist"
[[ -x "$BUNDLE/Contents/MacOS/LockHold" ]]
[[ -x "$BUNDLE/Contents/MacOS/LockHoldSleepHelper" ]]
[[ $(wc -l < "$LOCKHOLD_TEST_CALLS") -eq 7 ]]

# LLDB gets its entitlement only on the app, including when debugging optimised code.
# Ordinary builds above and installs below must never receive that entitlement.
for configuration in debug release; do
  DEBUG_ARGUMENTS=(--debug)
  if [[ "$configuration" == release ]]; then DEBUG_ARGUMENTS+=(--release); fi
  touch "$LOCKHOLD_TEST_PROCESS_STATE"
  : > "$LOCKHOLD_TEST_CALLS"
  LOCKHOLD_TEST_ALLOW_PROCESS=1 LOCKHOLD_TEST_CONFIGURATION="$configuration" LOCKHOLD_TEST_DEBUG_SIGNING=1 \
    "$FIXTURE/script/build_and_run.sh" "${DEBUG_ARGUMENTS[@]}"
  [[ "$(cat "$LOCKHOLD_TEST_CALLS")" == $'pgrep\npkill\npgrep\nswift\nswift\ncodesign\ncodesign\ncodesign\ncodesign\ncodesign\nlldb' ]]
  assert_no_staging
done

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

# Install uses its own destination, a release build, and the verified bundle path.
export LOCKHOLD_INSTALL_DIR="$TEST_DIR/Applications with spaces"
export LOCKHOLD_TEST_ALLOW_PROCESS=1
INSTALLED_APP="$LOCKHOLD_INSTALL_DIR/LockHold.app"
touch "$BUNDLE/untouched-by-install"
"$FIXTURE/script/build_and_run.sh" --install
cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHold" "$INSTALLED_APP/Contents/MacOS/LockHold"
[[ "$(cat "$LOCKHOLD_TEST_LAUNCHED")" == "$INSTALLED_APP" ]]
[[ -f "$BUNDLE/untouched-by-install" ]]
assert_no_staging

# Failed upgrades preserve the old installation and never launch the failed app.
cp "$INSTALLED_APP/Contents/MacOS/LockHold" "$TEST_DIR/installed-binary"
touch "$INSTALLED_APP/keep"
printf 'upgraded executable\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"
for failure in build sign promote final open; do
  export LOCKHOLD_TEST_FAIL="$failure"
  touch "$LOCKHOLD_TEST_PROCESS_STATE"
  rm -f "$LOCKHOLD_TEST_LAUNCHED"
  : > "$LOCKHOLD_TEST_CALLS"
  if "$FIXTURE/script/build_and_run.sh" --install > /dev/null 2>&1; then
    echo "Simulated install $failure failure unexpectedly succeeded" >&2
    exit 1
  fi
  [[ -f "$INSTALLED_APP/keep" && ! -e "$LOCKHOLD_TEST_LAUNCHED" ]]
  cmp "$TEST_DIR/installed-binary" "$INSTALLED_APP/Contents/MacOS/LockHold"
  if [[ "$failure" == "build" || "$failure" == "sign" ]]; then
    [[ -f "$LOCKHOLD_TEST_PROCESS_STATE" ]]
  fi
  assert_no_staging
done

# A valid upgrade stops the old process only after staged verification succeeds.
export LOCKHOLD_TEST_FAIL=none
touch "$LOCKHOLD_TEST_PROCESS_STATE"
: > "$LOCKHOLD_TEST_CALLS"
"$FIXTURE/script/build_and_run.sh" --install
[[ ! -e "$INSTALLED_APP/keep" ]]
cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHold" "$INSTALLED_APP/Contents/MacOS/LockHold"
[[ "$(cat "$LOCKHOLD_TEST_CALLS")" == $'swift\nswift\ncodesign\ncodesign\ncodesign\ncodesign\npgrep\npkill\npgrep\ncodesign\nopen' ]]
assert_no_staging

# Hold one transaction at final verification while a contender tries the same
# destination. Check both successful publication and rollback before retrying.
for mode in --build --install; do
  if [[ "$mode" == --build ]]; then
    unset LOCKHOLD_INSTALL_DIR
    export LOCKHOLD_TEST_ALLOW_PROCESS=0
    SHARED_APP="$BUNDLE"
  else
    export LOCKHOLD_INSTALL_DIR="$TEST_DIR/Applications with spaces"
    export LOCKHOLD_TEST_ALLOW_PROCESS=1
    SHARED_APP="$INSTALLED_APP"
  fi
  for outcome in none final; do
    GATE="$TEST_DIR/concurrent-$mode-$outcome"
    cp "$SHARED_APP/Contents/MacOS/LockHold" "$TEST_DIR/before-concurrent"
    printf 'first concurrent build %s %s\n' "$mode" "$outcome" > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"
    LOCKHOLD_TEST_GATE="$GATE" LOCKHOLD_TEST_FAIL="$outcome" \
      "$FIXTURE/script/build_and_run.sh" "$mode" > "$GATE.log" 2>&1 &
    FIRST_PID=$!
    for ((attempt = 0; attempt < 500; attempt++)); do
      if [[ -f "$GATE.ready" ]]; then break; fi
      sleep 0.02
    done
    if [[ ! -f "$GATE.ready" ]]; then
      cat "$GATE.log" >&2
      echo 'Concurrent build did not reach verification' >&2
      wait "$FIRST_PID" || true
      exit 1
    fi

    cp "$SHARED_APP/Contents/MacOS/LockHold" "$TEST_DIR/during-concurrent"
    cp "$LOCKHOLD_TEST_CALLS" "$TEST_DIR/calls-before-contender"
    printf 'contending build\n' > "$LOCKHOLD_TEST_BINARY_DIR/LockHold"
    if "$FIXTURE/script/build_and_run.sh" "$mode" > "$GATE.contender.log" 2>&1; then
      echo 'Concurrent replacement unexpectedly succeeded' >&2
      touch "$GATE.release"
      wait "$FIRST_PID" || true
      exit 1
    fi
    [[ "$(cat "$GATE.contender.log")" == *'Cannot lock '* ]]
    cmp "$TEST_DIR/calls-before-contender" "$LOCKHOLD_TEST_CALLS"
    cmp "$TEST_DIR/during-concurrent" "$SHARED_APP/Contents/MacOS/LockHold"
    [[ "$(cat "${SHARED_APP%/*}/.lockhold-build.lock/pid")" == "$FIRST_PID" ]]

    touch "$GATE.release"
    if [[ "$outcome" == none ]]; then
      wait "$FIRST_PID"
      cmp "$TEST_DIR/during-concurrent" "$SHARED_APP/Contents/MacOS/LockHold"
    else
      if wait "$FIRST_PID"; then
        echo 'Concurrent verification failure unexpectedly succeeded' >&2
        exit 1
      else
        [[ $? -eq 44 ]]
      fi
      cmp "$TEST_DIR/before-concurrent" "$SHARED_APP/Contents/MacOS/LockHold"
    fi
    assert_no_staging
    "$FIXTURE/script/build_and_run.sh" "$mode" > /dev/null
    cmp "$LOCKHOLD_TEST_BINARY_DIR/LockHold" "$SHARED_APP/Contents/MacOS/LockHold"
    [[ ! -e "$SHARED_APP/LockHold.app" ]]
    assert_no_staging
  done
done

# Never overwrite an unrelated application or a symlink at the install path.
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier example.unrelated' "$INSTALLED_APP/Contents/Info.plist"
: > "$LOCKHOLD_TEST_CALLS"
if "$FIXTURE/script/build_and_run.sh" --install > /dev/null 2>&1; then
  echo 'Unrelated app was unexpectedly replaced' >&2
  exit 1
fi
[[ ! -s "$LOCKHOLD_TEST_CALLS" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALLED_APP/Contents/Info.plist")" == example.unrelated ]]
/bin/mv "$INSTALLED_APP" "$TEST_DIR/saved-app"
ln -s "$TEST_DIR/saved-app" "$INSTALLED_APP"
if "$FIXTURE/script/build_and_run.sh" --install > /dev/null 2>&1; then
  echo 'Install symlink was unexpectedly replaced' >&2
  exit 1
fi
[[ -L "$INSTALLED_APP" && ! -s "$LOCKHOLD_TEST_CALLS" ]]

echo 'Build-script regression checks passed.'
