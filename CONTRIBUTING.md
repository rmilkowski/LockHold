# Contributing to LockHold

Small, focused improvements are welcome. For a substantial feature or new
dependency, explain the problem in an issue first so its scope can be discussed.

## Development

Use macOS with Xcode 16 or later and Swift 6. Install ShellCheck with
`brew install shellcheck`. The GitHub workflow selects Xcode 16.4; use the same
toolchain if a different Swift formatter version produces conflicting output.

```sh
./script/check.sh
./script/build_and_run.sh --verify
```

`--verify` checks process survival, not menu interactions or actual idle behaviour.
Run the manual checks below for user-visible changes. Tests substitute the IOKit
and pmset boundaries, so running the automated checks does not keep your Mac awake.

SwiftPM options can be forwarded when needed:

```sh
./script/check.sh --scratch-path /tmp/lockhold-build
./script/build_and_run.sh --build -- --scratch-path /tmp/lockhold-build
```

In an already sandboxed development environment, SwiftPM's own nested sandbox may
fail with `sandbox-exec: sandbox_apply: Operation not permitted`. For that
environment only, append `--disable-sandbox` to the forwarded SwiftPM options.
It is not required for ordinary local development or GitHub Actions.

For a checkout in a synced folder, set `LOCKHOLD_DIST_DIR` to an absolute, unsynced
output directory. File providers may attach Finder metadata to `.app` directories
after signing, which causes `codesign --verify --strict` to reject the bundle.

## Code structure

The package has app and sleep-helper executables, a small shared core, and one
test target. The original Auto-Lock assertion remains independent of the optional
privileged helper.

| Location | Responsibility |
| --- | --- |
| `Sources/LockHold/main.swift` | Create the application and retain its delegate. |
| `Sources/LockHold/App/AppDelegate.swift` | Own the menu controller and handle shutdown. |
| `Sources/LockHold/App/MenuBarController.swift` | AppKit menu actions, accessible status, and errors. |
| `Sources/LockHold/Services/AutoLockAssertionController.swift` | Own one assertion and preserve state across failures. |
| `Sources/LockHold/Services/PowerAssertionClient.swift` | Translate IOKit calls and error codes. |
| `Sources/LockHold/Services/SystemSleepController.swift` | Verified sleep state, pending approval, and removal. |
| `Sources/LockHold/Services/SleepHelperClient.swift` | Authenticated, bounded XPC requests. |
| `Sources/LockHold/Services/SleepHelperManager.swift` | SMAppService registration and approval. |
| `Sources/LockHoldCore/` | Fixed pmset operations, protocol, and signing requirements. |
| `Sources/LockHoldSleepHelper/` | Root daemon, console-user checks, and serialized operations. |
| `Sources/LockHold/Support/StatusIcon.swift` | Create native menu bar symbols and a drawing fallback. |
| `Tests/LockHoldTests/` | Assertion lifecycle, icons, sleep state, and helper approval tests. |
| `Assets/Info.plist` | App identity, version, and minimum macOS version. |
| `script/` | Build, package, lint, and test entrypoints. |

Keep AppKit work on the main actor. The assertion controller is owned by the menu
controller and must not be shared across actors. New asynchronous behaviour should
make its ownership and cancellation explicit.

Only clear an assertion ID after a successful release. Repeated enable and disable
requests must be harmless. Keep the Auto-Lock assertion separate from the persistent
System Sleep option. Exercise error paths with a fake client rather than
changing the developer's real sleep settings.

The minimum macOS version in `Package.swift` and `Assets/Info.plist` must agree.
No package dependency is currently required; prefer system frameworks when they
meet the need. See [Assets/README.md](Assets/README.md) for icon sources.

## Style and validation

Follow `.editorconfig` and `.swift-format`. Run `./script/lint.sh --fix` to format
Swift, then `./script/check.sh`. Keep changes focused and add behavioural tests
for new failure modes. Do not include generated bundles, caches, personal IDE
configuration, credentials, or signing material in commits.

Before submitting a UI or assertion change, check:

1. Launching creates one menu bar item with adjacent lock and laptop indicators and starts with the Auto-Lock override off.
2. **Disable Auto-Lock** changes the icon to red and the action to **Enable Auto-Lock**.
3. **Enable Auto-Lock** restores the normal icon and macOS-controlled idle behaviour.
4. The icon stays legible in light and dark appearance, and VoiceOver announces the app and state.
5. Exiting while active removes the app's assertion, with no leftover process.
6. The laptop indicator is red exactly when system sleep is disabled; the lock indicator shows Auto-Lock independently.
7. Clicking either indicator opens the same menu, and all four state combinations stay legible in light and dark appearance.

For actual idle behaviour, use your own Mac with appropriate sleep settings.
`pmset -g assertions` can show the assertion named
`LockHold is preventing idle display sleep` while the override is active.
Check manual lock and lid-close behaviour separately if your change affects them.

For the sleep helper, build with an Apple Development or Developer ID signing identity,
install in Applications, and approve the helper through the menu. Do not weaken the
XPC signature requirements to make ad-hoc builds work. Both peers require the same
Apple-issued signing team, their expected identifier, and no get-task-allow entitlement.
The helper also requires an active console user and only executes the fixed pmset
operations. No arbitrary command, argument, or executable path may cross XPC.

`--debug` adds get-task-allow to the app only, allowing LLDB to attach. This variant
is deliberately rejected by the helper. Do not add that entitlement to the helper
or to ordinary builds and installations; use `--install` for helper integration tests.

After setup, this read-only probe verifies the signed root connection:

```sh
/Applications/LockHold.app/Contents/MacOS/LockHold --probe-sleep-helper
```

Manually verify approval, cancellation, a second toggle without authentication,
external Terminal changes, quit/relaunch persistence, helper removal, and upgrade
without losing approval. Verify actual lid behaviour on supported Macs separately.
The helper exits when idle so subsequent requests load the current bundled executable.

## Pull requests and contribution terms

Describe the problem, resulting behaviour, and checks you ran. Include screenshots
for visual changes and note any manual checks you could not perform. Be considerate
and discuss technical decisions respectfully.

Only contribute work you have the right to share. By submitting changes, you
provide them under this repository's [BSD 2-Clause licence](LICENSE).
Confirm this in the pull request checklist.
