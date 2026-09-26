# LockHold

![LockHold icon](Assets/LockHold.iconset/icon_128x128.png)

Keep your Mac's display awake with one menu bar toggle.

LockHold is a small native macOS utility that temporarily prevents idle display
sleep and the automatic lock that normally follows it. It has no accounts,
network connections, analytics, or third-party runtime dependencies.

## Usage

Click either of the adjacent lock and laptop icons in the menu bar to open the shared menu:

| Action | Behaviour |
| --- | --- |
| **Disable Auto-Lock** | Keep the display awake. The lock icon becomes a red crossed-out lock. |
| **Enable Auto-Lock** | Release LockHold's override and return control to macOS. |
| **Disable System Sleep** | Prevent system sleep, including closing the lid, using an optional approved helper. The laptop icon becomes red. |
| **Enable System Sleep** | Restore normal system sleep behaviour. |
| **Exit** | Quit the app and release the Auto-Lock override; preserve the system sleep setting. |

The Auto-Lock override starts off and is temporary. It does not change your stored
power or password settings. LockHold does not start automatically at login.

### Optional system sleep control

Install a signed build in Applications, then choose **Disable System Sleep**.
On first use, LockHold registers its bundled sleep helper and opens System Settings
so an administrator can approve it under Login Items & Extensions. Once approved,
the requested change resumes automatically. Subsequent toggles use that approval
without requesting an administrator password each time. You can cancel the pending
change from LockHold's menu while approval is outstanding.

This is independent of Auto-Lock. The helper runs Apple's `/usr/bin/pmset -a disablesleep 1`
or `0`, then reads the setting back to verify it. The setting is system-wide and
**persists after quitting LockHold and restarting your Mac**, until you turn it off.
The menu reads macOS's actual value, including changes made in Terminal; launching
LockHold never resets an existing setting. The lock and laptop indicators turn red
independently when their respective overrides are active. Both are red when both
overrides are active; inactive indicators follow the menu bar's normal appearance.
The pair stays together as one menu bar item and opens the same menu from either icon.

Keeping a closed MacBook running consumes power and can generate heat; leave it
ventilated. This feature does not change password or screen-lock preferences.
`disablesleep` is an undocumented pmset option, so lid behaviour needs checking on
the MacBook model and macOS version in use. It is not a guarantee against battery,
thermal, or other system-enforced shutdowns.

**Sleep Helper Settings…** opens macOS's approval controls. **Remove Sleep Helper…**
first restores normal system sleep and then unregisters the helper. If restoration
fails, LockHold keeps the helper registered so you can retry. Remove it before
deleting the app. Simply quitting or disabling the background item in System Settings
does not undo the persistent sleep setting.

The helper accepts only the fixed read/toggle operations, validates the client's
Apple signing team and exact app identifier, and checks that the requesting user
is the active console user. The app also verifies the helper's signature and root
identity. The helper exits when idle; macOS starts it on demand. No PAM or sudoers
changes are needed.

### What the Auto-Lock option prevents

LockHold holds an IOKit
[`PreventUserIdleDisplaySleep` assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridledisplaysleep).
This asks macOS to prevent idle display sleep. It is not a general switch for every
way a Mac can lock: manual locking, closing a laptop lid, forced sleep, and
organisation-managed policies remain outside its control. macOS may also override
power assertions under battery or thermal constraints.

**Enable Auto-Lock** only releases LockHold's own assertion. It does not enable a
disabled system lock setting or cancel assertions held by other apps.

## Build and run

Requirements:

- macOS 14 Sonoma or later, on Apple Silicon or Intel.
- Xcode 27 or later, with its command-line tools selected (`xcode-select -p`).
- Swift 6.4 or later. CI uses Xcode 27.0 on GitHub's `xcode-27` Apple Silicon
  runner (public preview); Intel is not currently tested in CI.

Download or clone this repository, then run from its root:

```sh
./script/build_and_run.sh
```

The script builds `dist/LockHold.app` and launches it. The app appears in the menu
bar, with no Dock icon or main window. The script can also be invoked by absolute
path from another directory, including paths containing spaces.

To build an optimised app without launching it or stopping a running instance:

```sh
./script/build_and_run.sh --build --release
```

You can copy the resulting app into Applications. The script uses the single valid
code-signing identity available on the Mac, or falls back to ad-hoc signing if none
is available. Set `LOCKHOLD_SIGN_IDENTITY` to choose an identity when there are several,
or to `-` to explicitly build ad-hoc. Ad-hoc builds support Auto-Lock but cannot enable
the privileged sleep helper. Apple Development signing supports local helper testing;
Developer ID signing and notarisation are needed for public distribution.

These are builds for the build machine's architecture, not notarised public downloads.
See [release preparation](docs/RELEASING.md) before distributing binaries.

If your checkout is inside iCloud Drive or another synced folder, its file provider
may add Finder metadata that invalidates macOS bundle verification. Build into an
unsynced directory instead:

```sh
LOCKHOLD_DIST_DIR="$HOME/Library/Caches/LockHold/dist" ./script/build_and_run.sh --build --release
```

`LOCKHOLD_DIST_DIR` must be an absolute path and is also honoured by the launch modes.

### Codex actions

The shared Codex environment provides three actions:

| Action | Behaviour |
| --- | --- |
| **Run** | Build a debug app in `~/Library/Caches/LockHold/<checkout-id>/dist` and launch it. |
| **Build** | Build a release app in that checkout's cache without stopping or launching LockHold. |
| **Install/Upgrade** | Build a release app, replace `/Applications/LockHold.app`, and launch it. |

Run and Build use an unsynced cache identified by the checkout's physical path,
so separate worktrees do not overwrite each other's builds. The
environment is saved in `.codex/environments/environment.toml` so these actions
are available in other checkouts too.

To install or upgrade from a terminal:

```sh
./script/build_and_run.sh --install
```

The installed app keeps running until the new bundle has been built and verified.
The installer then stops your running LockHold instances and replaces the app,
restoring the previous bundle if replacement, verification, or launch fails. If
restoration also fails, it prints the retained backup location. A successful
launch starts with the Auto-Lock override off and reads the existing system sleep setting.
Version numbers come from `Assets/Info.plist`;
installing does not automatically increment them.

The destination must be writable by your account. Set `LOCKHOLD_INSTALL_DIR` to
an absolute alternative such as `"$HOME/Applications"` if needed; install mode
uses this setting instead of `LOCKHOLD_DIST_DIR`.

Builds and installs lock their destination until replacement or rollback finishes.
If another action is using the same destination, the new action exits with a retry
message. A forcibly killed build may leave `.lockhold-build.lock` in that directory;
confirm that its process (recorded in the lock's `pid` file) has ended before
removing the stale lock directory and retrying.

### Development commands

| Command | Purpose |
| --- | --- |
| `./script/build_and_run.sh --build` | Build a debug app bundle without launching it. |
| `./script/build_and_run.sh --install` | Build, install or upgrade, and launch a release app in Applications. |
| `./script/build_and_run.sh --verify` | Rebuild, launch, and check that the process stays running. |
| `./script/build_and_run.sh --debug` | Rebuild and launch under LLDB. |
| `./script/build_and_run.sh --logs` | Rebuild, launch, and stream process logs. |
| `./script/build_and_run.sh --telemetry` | Rebuild, launch, and stream LockHold's local diagnostic logs. |
| `./script/build_and_run.sh --help` | Show all options. |

`--debug` gives the app the debugging entitlement required by LLDB. The privileged
helper rejects debugger-enabled clients, so System Sleep control is unavailable in
that variant, even if the helper is already approved. Normal builds and installations
do not receive this entitlement; use `--install` to return to the full app.

Launch modes stop the current user's running LockHold processes before rebuilding;
`--install` waits until the replacement is ready, and `--build` leaves them running.
Stopping LockHold releases its Auto-Lock override; the new instance starts with it off.
The separate system sleep setting is preserved.
Build or signing failures leave the previous app bundle intact.

## Lint and tests

Install [ShellCheck](https://www.shellcheck.net/) once, then run the checks:

```sh
brew install shellcheck
./script/check.sh
```

This runs Swift's bundled `swift-format` linter in strict mode, ShellCheck,
shell syntax and bundle-metadata checks, Swift tests with compiler warnings treated
as errors, and build-script regression checks. Tests use fake IOKit and pmset clients
and do not change the Mac's sleep state.

```sh
./script/lint.sh        # Check Swift and shell code
./script/lint.sh --fix  # Format Swift, then rerun all lint checks
swift test             # Run just the Swift tests
```

GitHub Actions is configured to run the same checks and build release bundles on
Apple Silicon and Intel. No signing secrets are needed for these local-build checks.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the code structure, development workflow,
and manual UI checks. For security concerns, see [SECURITY.md](SECURITY.md).
Notable changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Licence

LockHold uses the [BSD 2-Clause licence](LICENSE). You may use, modify, and
redistribute it, including commercially, provided you retain the copyright notice,
licence conditions, and disclaimer. The software is provided without warranty.
