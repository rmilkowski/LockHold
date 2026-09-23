# Changelog

## Unreleased

## 0.2.1 - 2026-09-23

- Stop repeated sleep-helper status queries during menu and appearance updates.
- Cache helper status between lifecycle refreshes while checking current status for sleep changes, approval, and removal.
- Avoid redundant status-bar icon updates and refresh helper status after failed operations.

## 0.2.0 - 2026-09-23

- Add independent System Sleep control through an optional SMAppService root helper.
- Preserve Auto-Lock labels and behaviour; show persistent system sleep state separately.
- Show adjacent lock and laptop indicators, independently red when each override is active, with one shared menu.
- Resume the requested sleep change after initial approval, verify pmset results, and support helper removal.
- Validate both XPC peers by signing team and identifier, and restrict helper requests to the active console user.
- Package and sign the helper with the app, with ad-hoc builds retaining Auto-Lock only.
- Preserve the selected sleep action when another app changes the setting before it runs.
- Keep LLDB debugging available through a separate app signing variant that cannot access the root helper.
- Stop idle helpers after rejected connections so app upgrades can start the current helper.

- Add shared Codex Run, Build, and Install/Upgrade actions, with release installation and rollback.
- Isolate Codex build caches by checkout and prevent concurrent replacement of the same app bundle.
- Restore the previous app bundle when replacement or final signature verification fails.

## 0.1.1 - 2026-09-05

- Native menu bar toggle for a temporary idle display-sleep assertion.
- Red active icon, accessible state labels, and user-facing IOKit errors.
- Assertion ownership retained after release failures so the operation can be retried.
- Build, debug, log, verification, and build-only modes, with optional release builds.
- Validated app bundles with version metadata and local ad-hoc signing.
- Swift and shell linting, assertion lifecycle tests, and packaging regression checks.
- GitHub Actions for Apple Silicon and Intel, contributor documentation, and the BSD 2-Clause licence.
