# Release preparation

Publishing this source repository and distributing a trusted macOS app are separate
steps. The build script creates a local ad-hoc signature; it does not use a Developer
ID identity, enable a distribution workflow, or submit anything to Apple.

## Publishing the source repository

1. Run `./script/check.sh` and review the exact files that will be committed.
2. Keep `.build/`, `dist/`, personal Codex settings, credentials, and signing files
   out of Git. Only `.codex/environments/environment.toml` is shared from `.codex/`.
3. After creating the GitHub repository, enable private vulnerability reporting.
4. Let both CI jobs pass and consider requiring them in the default branch's ruleset.

The repository includes the BSD 2-Clause licence, contributor guidance, issue and pull request
templates, and monthly Dependabot checks for its pinned GitHub Actions dependency.

## Distributing a binary

1. Choose a permanent bundle identifier under the publisher's control before the
   first public binary release. `dev.codex.LockHold` is the current development identifier.
2. Set the release version and build number in `Assets/Info.plist`, update
   `CHANGELOG.md`, and keep the minimum OS version consistent with `Package.swift`.
3. Run the checks and `./script/build_and_run.sh --build --release`. Builds are for
   the selected toolchain's target architecture. Validate Apple Silicon and Intel
   artifacts separately, or establish and verify a universal-binary build.
4. Test the menu, idle behaviour, manual locking, and exit cleanup on supported Macs.
5. For downloads intended for other users, set up Developer ID signing, hardened
   runtime, and Apple's notarisation process. Verify the final distributed artifact,
   including its signature and stapled notarisation ticket, on a clean Mac.

Follow [Apple's distribution guidance](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
when setting up that pipeline. Keep signing credentials outside the repository.
There is no automated publishing or notarisation step in this project yet.
