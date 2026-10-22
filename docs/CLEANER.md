# Using xean

xean opens from the eraser in the menu bar. It stays out of the Dock and keeps its header and Clean button
fixed while you scroll through settings and categories. To build and launch it, follow
[Get started](../README.md#get-started).

## Manual cleanup

1. Check the categories you want to clean. Project locations are discovered automatically.
2. Optionally click a category title or chevron to inspect its items. Use Delete to remove one eligible
   item, regardless of whether its category is checked for bulk cleaning.
3. Press Clean to scan and permanently delete eligible data in the checked categories. There is no second
   confirmation and no manual age cutoff.
4. Successful entries collapse out of the queue. The result shows measured removed bytes, counts, and any
   protected or failed items. Done closes the panel; reopening returns to the normal cleaner.

There is no Stop button. Closing the panel during cleanup lets it finish without reopening the result.
Individual Delete keeps short feedback beside Clean for five seconds. Failed removals stay with their
reason. Removal is permanent; xean does not provide an undo or move these items to Trash.

## Category lists and scanning

Dropdowns show eligible and protected entries measured at **50 MB or larger**, with names, paths, sizes,
and worktree branches where available. Protected entries with unknown sizes remain visible. Smaller eligible items have a count and total, and scan skips show their reasons. Bulk cleanup includes those smaller eligible items.

Completed manual category scans are reusable for **30 seconds after completion**. Expired, missing, or
invalidated lists clear their old contents before showing Checking… and scanning again. Clean shares those
cached results and scans only missing/expired selected categories. Each removal still validates its target
again. Changing roots or worktree age invalidates category caches; successful removal clears the matching
path and descendants from other cached categories. The header refresh button bypasses the cache and rescans selected and previously opened categories without changing selections or deleting files. Running-app protections still apply. Refresh publishes cache results before checking project folders and worktrees. Protected folders remain visible with their reasons; xean does not recursively measure them solely for display.

Cleaner traversal has no arbitrary entry-count, depth, project-count, or elapsed-time cap. Large dependency
trees can take longer to inspect. Project discovery starts at known development/tool locations and saved
custom roots; it skips generated trees and symbolic links. This is not a complete scan of all disks.
Unreadable data stays protected, and external Git/activity commands retain hang timeouts.

## Automatic cleanup and warnings

| Control | Default | Behavior |
| --- | --- | --- |
| Auto-clean | Off; 20 GB | After inline opt-in, clean selected categories when free space is below its threshold |
| Notify when low | Off; 20 GB | Show a red exclamation badge on the eraser and free-space header |
| Threshold inputs | 1–1,000 GB | Separate values, always visible beside their switches; no stepper arrows |
| Background interval | 25 minutes | Fixed interval while the app runs; last-check time persists across launches |
| Automatic worktree age | 30 days | Editable from 1–365 days when Auto-clean and Old worktrees are selected |

Enabling auto-clean replaces the same row with “Enable auto-clean?”, Cancel, and OK. It does not repeat
the threshold input. Turning it off takes effect without a confirmation. Warning badges are independent
of automatic cleanup, clear when measured free space recovers, and never ask for notification permission.

Automatic runs use fresh scans and age rules. A failed disk reading prevents automatic deletion. If free
space recovers during scanning, a second disk check skips the cleanup. Background runs are silent and do
not open result screens. Both switches off means manual cleanup only. Checks do not wake a sleeping Mac.

## Cleanup rules

| Category | Scope and conditions |
| --- | --- |
| Claude Code | `.claude/cache`, supported CLI cache, Claude desktop cache and named renderer/GPU caches |
| Codex | Supported macOS caches and named renderer/GPU caches in its desktop profile; sessions stay |
| Superconductor | Supported macOS and named renderer/GPU caches |
| Coding editors | Cursor, VS Code, Windsurf, Zed, and fed10 cache locations |
| Package caches | npm (including npx), Yarn, pip, uv, Bun, and Homebrew download caches; verified temporary Python environments in macOS temporary directories |
| Browser caches | Supported Safari, Chrome, Firefox, and Zen cache locations |
| Build files | Xcode DerivedData and supported web/Swift/Rust output in discovered projects, including nested packages; project output requires a matching manifest, Git ignore rule, and no tracked files; also verified temporary Xcode build output and stale `tickle-desktop-test-XXXXXX` directories in the current user’s macOS temporary directory |
| Project dependencies | Inactive `node_modules` with an exact reinstall lockfile; package links are supported without following destinations |
| Docker build cache | Unused builder cache through a verified local Unix socket; images, containers, and volumes remain |
| Unused Docker images | Separate opt-in: images older than 24 hours that no container references, including tagged local images; local images may need rebuilding. Containers and volumes stay |
| Old worktrees | Clean, merged, inactive Git-linked checkouts; removal uses `git worktree remove` without force and leaves branches intact |

Claude Code, Codex, Superconductor, editors, packages, and builds start selected. Browsers, dependencies,
Docker, unused Docker images, and worktrees start unselected. Previous selections are retained.

| Age policy | Manual Clean / Delete | Automatic cleanup |
| --- | --- | --- |
| Caches and build output | No age cutoff | At least 24 hours |
| Temporary environments, Xcode builds, and Tickle test folders | At least 24 hours | At least 24 hours |
| Project dependencies | No age cutoff | At least seven days |
| Docker builder cache | No age filter | At least 24 hours; the displayed estimate can include newer cache that stays |
| Unused Docker images | At least 24 hours | At least 24 hours |
| Worktrees | No age cutoff | Configured minimum; age includes file changes, creation, and Git metadata activity |

Every deletion rechecks identity, metadata, location, and activity. Automatic operations also recheck age.
Active tools, open files, unreadable trees, special files, identity changes, and failed verification keep
the item. Shared caches retain named app/package-manager checks. Generic Node, Python, and Ruby processes do not block unrelated caches: affected cache rules check open files and working directories across the cache root at scan time and again before removal. Failed activity checks keep the cache. Temporary test cleanup accepts only owned directories with the exact six-character alphanumeric test suffix, keeps linked roots, and requires every entry to be at least 24 hours old even for manual cleanup. Each test folder is checked for open files and working directories before deletion. Project build output uses the project's working
directories and open files rather than blocking on every unrelated compiler or Node process.

Primary, locked, detached, unmerged, dirty, active, or explicitly kept worktrees remain protected. Ignored
files and open files can also block their removal. Merge checks use locally available default-branch
ancestry without fetching. Age alone never proves that a worktree can be discarded.

Conversation history, credentials, installed plugins, whole app profiles, and unknown cache directories
are outside the allowlist. Root symlinks stay protected; nested links are fingerprinted and deleted as
links, never by traversing their destinations. A small race remains between final validation and removal.

## Menu bar stats and appearance

Show menu bar stats starts enabled, with CPU, memory, and disk controls directly beneath it. Click its
label or switch to toggle stats and show or hide those controls. Memory supports available GB, used GB,
and used percentage. At least one metric remains selected
while enabled. Metrics sample every two seconds; switching them off stops this sampler.

Stats sit to the left of the eraser, which remains the popover anchor. AppKit supplies the translucent
background, border, pointer, and shadow. The sun/moon button beside the free-space readout switches the
panel and its native controls between light and dark. Light is the default; your choice is remembered
across launches independently of macOS appearance. Both themes respect increased contrast. Native Liquid Glass buttons are used on
macOS 26+, with standard bordered fallbacks on earlier supported systems.

Custom motion takes 180 ms. Disclosures and removed rows animate clipped height without text fades or
scaling. The scroll-edge blur and fade remain; Reduce Motion disables custom motion/blur, and Increase
Contrast removes the edge fade and blur. Trackpads retain native momentum.

Interaction sounds use bundled Cuelume WAVs at 70% volume, with one playback voice and suppression of rapid
repeat clicks. Opening and closing are silent, as are background operations. There is no sound setting.

## Closing, quitting, and login

Click the eraser again, click outside, press Escape, or press ⌘W to dismiss the panel. Active cleanup and
background checks continue. The power icon or ⌘Q switches the same popover to a compact Quit confirmation;
Cancel or Escape restores the cleaner. Quit exits the app. Start at login is optional and uses macOS's
native login-item service.

## Common questions

**Why does an item stay after Clean?** It may be in use, changed since scanning, outside the allowlist,
unreadable, or protected by project/Git rules. Check the inline reason. Close the owning tool before
trying again; size alone does not establish eligibility.

**Why does a category contain files but no cleanup entries?** It may contain protected data, running-tool caches, or files outside the supported rules. The dropdown shows scan notes and protected locations; smaller eligible entries are summarized rather than listed individually.

**Why does a new scan take time?** Large trees are traversed completely. A scan within the 30-second cache
window is reused, but fresh deletion validation is still required. Auto-clean always starts a fresh scan.

**Why do removed bytes differ from the free-space increase?** Removed bytes are measured file data.
Other disk activity and filesystem accounting affect available space; these are separate measurements.

**Why does Finder or macOS still say BlitzClean?** The source target, bundle, and data identifiers are
inherited. See [compatibility names](ARCHITECTURE.md#compatibility-names).

For local data and permissions, read [Privacy](PRIVACY.md). For fixture-based development and sound asset
reproduction, read [Contributing](../CONTRIBUTING.md) and [Open-source credits](../OPEN_SOURCE_BASES.md).

### What is kept and why

Expanded categories show scan failures and running-tool skips, protected data with unknown sizes, and the total of smaller items included in Clean. Cleanup results retain scan notes rather than implying all disk data was removed. Simulator/device-support data, Codex history/runtimes, and Claude scratchpads are explicitly protected. Downloads are personal data outside cleanup scope.

Temporary discovery includes the current user’s macOS temporary directory and `/private/tmp`. Python environments require `pyvenv.cfg` and only known environment entries; Xcode build directories require validated `info.plist` workspace metadata and only generated output entries. Extra files, linked markers, repositories, foreign-owned directories, active files/working directories, and unverified checks are kept. Every entry must be at least 24 hours old even for manual removal. These checks are repeated before deletion. Claude scratchpads are shown for manual review, never automatically deleted.

### Parallel cleanup

Native cleanup runs up to three independent filesystem removals at once. Each target still receives
its normal identity, activity, ownership and age checks immediately before removal. Overlapping paths
and shared project scopes cannot run together; Git worktree and Docker operations run exclusively.
Stopping prevents queued work from starting while already-started removals finish and are recorded.
Successful rows disappear immediately, without a queued deletion animation; failures remain visible.

### Expanded cleanup coverage

Project discovery includes Downloads, local tool projects in `~/.local/share`, Codex experiment folders,
and Superconductor projects. Existing dependency/worktree safety checks still apply; arbitrary downloaded
files are never cleanup targets. Temporary Xcode build folders may include generated `TestResults`.

“Other app caches” covers Slack and Linear cache folders plus WhatsApp's staged updater installations.
Zen's Mozilla updater cache is included under Browser caches. Playwright browser downloads are included
under Package caches; browsers may need reinstalling with `playwright install`. Updater and browser-download
cleanup requires a 24-hour minimum and checks for running tools and open files. Profiles, messages,
Playwright registrations, simulator devices and iPhone support data stay protected.

“Python environments” is a separate opt-in category for `.venv`/`venv` directories in discovered project
locations. It requires verified generated-environment metadata, a regular owned dependency manifest,
at least seven days of age even for manual cleanup, no active interpreter or project, and the normal
identity/ownership/internal-volume checks again before deletion. In Git projects, environments must be
ignored and contain no tracked files. Unverified environments appear as
protected items with reasons; installed standalone runtimes are not included.
