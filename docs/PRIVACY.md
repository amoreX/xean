# xean privacy and permissions

The cleaner runs locally. It has no account system, telemetry, analytics SDK, cloud scan, or remote AI
inference. Paths, measurements, settings, and cleanup history stay on the Mac unless you choose to share them.

## What the active cleaner reads

- File identity, type, size, modification times, and directory structure in supported cleanup locations.
- Project manifests, lockfile presence, Git metadata, checkout status, and local branch ancestry to check
  whether dependencies, build output, and worktrees are eligible. It does not fetch remote Git branches.
- Local process and open-file information to avoid removing data in use. Activity checks may read command
  lines locally; these are not copied into the cleanup ledger.
- Local Docker builder-cache information through a verified Unix socket when Docker cleanup is selected.
- Available disk space. Optional menu bar metrics also read host CPU and memory statistics.

The active cleaner does not invoke the inherited AI session-title readers, window-response probes, local
HTTP project probes, process-signaling controls, media tools, or dashboard history monitors. Conversation
contents, credentials, installed plugins, and whole app profiles are outside its cleanup allowlist.

## Stored data

xean currently retains the inherited `com.blitzreels.BlitzClean` bundle/preference domain and
`~/Library/Application Support/BlitzClean` data folder. An installed BlitzClean copy can therefore share
this data. Renaming the interface has not isolated the two apps' preferences.

| Store | Contents and lifetime |
| --- | --- |
| Cleaner preferences | Selected categories, warning/automatic modes, thresholds, worktree age, and preserved custom project roots |
| Menu bar preferences | Enabled state, selected metrics, and memory display format |
| `cleaner.lastCheck` | Latest background-check timestamp, retained across launches |
| `cleaner.lastOutcome` | Most recent result: date, counts, measured removed bytes, and observed free-space gain |
| `cleanup-history.json` | Up to 1,000 removal records, with paths, dates, measured sizes, and before/after volume readings |
| Category scan cache | In-memory inventory, reused for 30 seconds after completion; no persistent scan database |
| Cleanup screen | Transient queue/result, cleared when the panel closes |

The cleanup ledger uses atomic writes, a local file lock, and owner-only file permissions. Settings live
in UserDefaults. Older chart, media, or incident files can remain from upstream installations; the active
cleaner does not start those subsystems or continually write their histories. Legacy preference migration
is retained.

File paths and project names can be sensitive. Replace them with placeholders before sharing logs or
screenshots. Never commit local history, reports, build artifacts, or machine screenshots.

## Network behavior

The running cleaner does not start an updater or send scan results anywhere. Sparkle remains a build
dependency, but its update controller is not instantiated. The app uses already-rendered local sound assets.
Docker operations are restricted to a local endpoint, not a remote Docker host.

Cloning and the first build use GitHub and SwiftPM to obtain source and dependencies. Visiting documentation
or repository links in a browser is a separate network action. Building a signed distribution can also
contact Apple's signing/notarization services; this is not cleaner telemetry.

## Permissions

“Notify when low” shows an in-app/menu bar badge, so it does not request notification permission.
The cleaner does not need Accessibility permission for its normal interface or window-response checks.
macOS can still restrict access to protected folders. A denied or unverifiable path stays protected;
the app does not elevate privileges or bypass macOS filesystem protections.

Start at login uses `SMAppService.mainApp` and is optional. Signing identity and bundle location affect
how macOS recognizes the app; local ad-hoc rebuilds can affect stored permissions or login registration.

## Deletion and lifetime

Manual Clean and Delete permanently remove eligible data without another confirmation. Auto-clean requires
explicit opt-in and uses the selected categories, threshold, age policies, and fresh safety checks.
Neither operation is a general-purpose Trash action; xean has no restore feature.

Closing the panel keeps active cleanup and scheduled checks running. Quitting exits the app; xean is not
a separate background daemon and cannot run while the Mac is asleep or the app is stopped. See
[the user guide](CLEANER.md) for cleanup rules and [Security](../SECURITY.md) for reporting a problem.
