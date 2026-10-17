# xean security

xean can permanently delete eligible caches, build output, dependencies, and worktrees. Manual Clean and
Delete execute immediately; automatic cleanup requires opt-in. Location, identity, activity, and applicable
age checks are part of the deletion boundary.

## Reporting

Do not publish exploit details, credentials, private paths, or sensitive files in a public issue or PR.
If this repository offers **Security → Report a vulnerability**, use that private form. Private reporting
is not currently enabled on the fork; otherwise contact [the fork maintainer](https://github.com/amoreX)
to arrange a private channel before sharing sensitive details. Upstream BlitzReels contact information is
not a support channel for xean.

Include the source commit (`git rev-parse --short HEAD`), macOS version, build method, and a minimal
reproduction using disposable folders. Explain expected versus actual behavior and redact all unrelated
local data. No response-time guarantee is made.

Relevant problems include:

- Removing a path outside the selected scope or supported allowlist.
- Following a symlink destination or bypassing target identity/activity validation.
- Bypassing Git worktree or Docker endpoint protections.
- Automatically deleting without opt-in or ignoring the saved automatic policy.
- Exposing credentials, conversation contents, or private local data.

## Limits

Deletion runs as the current user, without privilege escalation. It is not hardened against a hostile
process modifying the same filesystem tree between final validation and removal. No restore mechanism
is provided. See [cleanup rules](docs/CLEANER.md#cleanup-rules) and [Privacy](docs/PRIVACY.md) for the current
behavior and data handling.
