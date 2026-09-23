# Security

LockHold intentionally keeps the display awake while its override is active. Use
it only when that is appropriate for your environment. It does not authenticate
users, enforce lock policies, store credentials, or communicate over the network.

Optional System Sleep control installs a root helper through macOS's SMAppService
approval flow. Its XPC interface only reads the sleep flag or sets a Boolean value;
it never accepts command strings or executable paths. Both peers validate an
Apple-issued signing team, an exact identifier, and the absence of the
get-task-allow entitlement. Each helper request must come from the active console
user. The helper invokes the fixed system pmset executable and verifies writes.

The system sleep setting persists independently of LockHold and its helper.
Removing the helper through LockHold restores normal sleep before unregistering it.
Disabling its background item or deleting the app does not restore that setting.

## Reporting a vulnerability

Use GitHub's **Security → Report a vulnerability** if private reporting is enabled
for this repository. Include the affected version or commit, macOS version,
reproduction steps, and observed impact. Remove personal information from logs.

If private reporting is unavailable, open an issue asking the maintainer for a
private reporting channel without posting vulnerability details publicly.

## Support

Security fixes are developed against the current default branch. Older versions
do not have a separate long-term support commitment.
