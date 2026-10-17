# Menu bar cleaner

This fork replaces the monitoring dashboard with one eraser icon in the menu bar. Clicking it opens a fixed cleanup popover directly below the icon. A curved glass pointer connects the top of the popover to the icon. The panel is centered below it when space allows; near screen edges the pointer follows the icon while the panel stays onscreen. It cannot be dragged, resized or detached. Click the icon again, click outside, press Escape or press ⌘W to dismiss it. It stays out of the Dock; dismissing the popover keeps scheduled checks running. Quit exits normally. Legacy process monitoring, process controls, dashboard windows and upstream automatic updates are not started. Optional menu bar metrics use the lightweight system sampler only.

## Use

Show menu bar stats toggles the original BlitzClean CPU, memory and disk icons and values beside the
eraser. Expand Stats shown to select individual metrics, including just one, and choose available memory,
used memory or its percentage. It starts enabled, remembers its selections and stops live metrics
sampling when off. The cleaner still opens from the icon, and its pointer stays aligned with the eraser.

1. Check the categories to clean. Common project folders are discovered automatically.
2. Choose Clean to scan and permanently delete eligible items in the checked categories in one operation. There is no second confirmation. Manual cleanup includes caches and build output of any age.
3. Stop interrupts the run after the current operation; untouched items stay.

Click any category's title or chevron to expand its items. The dropdown only shows entries measured at 50 MB or larger, including protected entries; smaller and unmeasured entries are hidden. This display filter does not change bulk cleanup eligibility. Each eligible item shows its path and measured size with a direct Delete action. Individual deletion works independently of the bulk-selection checkboxes. Deleted items disappear immediately; failed removals remain with an inline reason. Worktrees include their branch; protected checkouts show why they are kept. Completed category scans are reused for 30 seconds. Opening a missing, expired or invalidated list scans it again and shows Checking… with the previous items cleared immediately. The 30 seconds starts when scanning finishes. There is no Refresh button. The list's height uses a non-bouncing 400 ms spring for opening, closing and refreshed results; Reduce Motion disables this animation.

Both background switches start off. Low-space warning shows a red exclamation badge on the menu bar eraser and beside the free-space subtitle below the chosen GB threshold. It clears when free space recovers and works independently of Auto-clean. No macOS notifications or notification permissions are used. A previously saved Notify me choice becomes the visual warning. The Auto-clean switch at the top asks for opt-in, then scans and deletes eligible items in the checked categories below the configured GB threshold. Checks use a fixed 25-minute interval, including for previously saved preferences. The app must be running; Start at login is optional. Checks do not wake a sleeping Mac. Failed disk measurements prevent automatic cleanup. Recovered free space after a scan cancels automatic deletion. Cleanup results remain in the dialog.

Selections, thresholds, folders and the last result persist across relaunch. The next-check schedule uses a persisted last-check time. Clean reuses manual category results up to 30 seconds old and scans only missing or expired categories, then revalidates each item before removal. Combining cached categories still excludes overlapping removals. Changing categories invalidates the bulk selection; changing roots or worktree age also clears the dropdown caches. Automatic cleanup clears affected dropdown results and uses a fresh scan with its age policy.

The popover uses one continuous light Liquid Glass background with charcoal controls, supplied by
[metneo/LiquidGlass](https://github.com/metneo/LiquidGlass). macOS 26 uses system glass; macOS 14–15 use
the package's material fallback. The popover blurs the desktop behind it. Reduce Transparency and Increase
Contrast use an opaque background and controls; the custom interactions respect Reduce Motion.
The compact 420 × 592-point panel has unboxed sections and a fixed footer. Tight spacing groups the
content without horizontal dividers,
and quiet actions appear as text. There are no mode tabs. Low-space warning and Auto-clean have separate switches; their settings expand and fade smoothly. The anchored panel uses a non-bouncing fade and slight scale over 460 ms when opening and 360 ms when closing. The pointer stays fixed, and rapid reopen clicks reverse the current motion. The window hides after the animation finishes; Reduce Motion makes visibility immediate. Discrete mouse-wheel steps ease over 180 ms, while trackpad scrolling keeps native momentum. There is no scrollbar; rows subtly shrink, blur and fade as they cross the top and
bottom edges. Reduce Motion disables the scaling and blur, while Increase Contrast removes the fade too.

Interface sounds come from [Cuelume](https://cuelume.dev), rendered from its default recipes and played locally. Interface sounds are always enabled at 70%, with no sound controls. Opening and closing the dialog is silent. Sounds play only while the app is active, use one voice, and suppress rapid repeated clicks. Background checks are silent. Old sound preferences are ignored.

## Scope

- Claude Code: CLI cache, `.claude/cache`, supported Claude desktop caches.
- Codex: macOS cache directories and named renderer/GPU caches inside the desktop profile.
- Superconductor: macOS cache directories and named renderer/GPU caches.
- Editors: supported Cursor, VS Code, Windsurf and Zed caches.
- Packages: npm, Yarn, pip, uv, Bun and Homebrew download caches.
- Browsers: supported Safari, Chrome and Firefox caches.
- Builds: Xcode DerivedData and supported web, Swift and Rust output in discovered projects, including nested packages. Project output needs a matching manifest, a Git ignore rule and no tracked files. Activity checks for project output use that project's working directories and open files; unrelated Node or compiler processes do not block its removal. Shared caches retain their tool activity checks.
- Dependencies: inactive project `node_modules` with an exact reinstall lockfile. Manual cleanup has no age cutoff; automatic cleanup requires seven days. Normal package links are supported without following their destinations.
- Docker: only unused builder cache through a verified local Unix socket. Automatic cleanup requires 24 hours of age; manual cleanup has no age filter. Images, containers and volumes stay. Automatic estimates can include newer cache that the age filter will keep.
- Worktrees: Git-linked checkouts from common tool locations and added folders. Automatic cleanup uses a configurable 1–365 day age based on the newest file change, folder creation or worktree Git metadata change. Manual removal has no age cutoff. Primary, locked, detached, unmerged, dirty and active worktrees stay. Ignored files and open files also block removal. Removal uses `git worktree remove` without force and leaves branches intact. Cloud sandboxes are outside this app's scope.

Automatic cache and build cleanup keeps items newer than 24 hours. Clicking Clean bypasses this age cutoff for both scanning and removal, even when Auto-clean is enabled. Manual worktree and dependency removal also bypass their age cutoffs. Automatic dependencies retain their seven-day limit. Active tools, open files and changes since the scan still block removal. The dialog omits the age-policy helper line. Conversation history, credentials, installed plugins, whole app profiles and unknown cache directories are outside the allowlist. Cleanup roots that are symbolic links remain protected. Nested links are fingerprinted and removed as links without traversing or counting their destinations. Special files, unreadable data, changed identities and failed activity checks preserve the item. Worktree age alone never proves redundancy. Git ancestry is verified against the locally available default branch; the cleaner does not fetch.

Cleaner discovery and file-tree verification have no entry-count, depth, project-count or elapsed-time cutoff. Trees are traversed in deterministic depth-first order, releasing completed paths rather than retaining the whole scan. Scans run off the main thread and honor cancellation. Discovery still skips generated directories and links; unreadable data remains protected. Individual external Git and activity commands retain their hang protection. The dialog omits detailed skipped-path notes; eligibility checks still preserve skipped files. Previously saved custom project folders remain part of discovery, but the dialog no longer has a folder editor. Protected inventory entries use the same complete traversal for measurement.

Deletion rechecks identity, file metadata, age and activity. A small filesystem race remains between validation and removal, as in the upstream cleaner. Successful removals use the existing bounded local history. No telemetry or external service is added.

## Development

Auto-clean sits directly below the header, above What to clean. Its inline confirmation is one compact
row showing an editable free-space threshold with Cancel and OK. It replaces the toggle row with a
320 ms crossfade, preserving the same 34-point height so the content stays stationary.
“Notify when low” sits immediately below Auto-clean and groups its own free-space threshold with an indent.
The two limits are independent and persist separately; existing shared limits migrate to both. The
Auto-clean limit stays editable in its normal row as well as its confirmation. Glass buttons are clipped
to their rounded outlines to remove the dark spill beneath them. The Stats shown disclosure and
metric choices have the same indent below Show menu bar stats. Stats sit to the left of the eraser;
changing their visibility eases the label width leftward and fades the metrics over 280 ms, keeping
the eraser and popover stationary. Settings use native macOS switches and consistent 34-point rows.
Reduce Motion applies changes immediately. Cleanup keeps Clean disabled with progress beside it, without a Stop
button. Only the transient footer result is shown; the persistent cleanup-history paragraphs are hidden.

The header places “xean”, free disk space and a power icon on one line. Power or ⌘Q transforms
the same anchored popover into a padded, rounded 72-point-high row containing Quit xean?, Cancel and Quit,
with no sheet, modal window or subtitle.
Cancel or Escape expands it back to the cleaner; confirming Quit stops the app. The resize and
content fade take 300 ms and 240 ms respectively, or happen immediately with Reduce Motion enabled.

Run `swift test --no-parallel -j 2`. Render the dialog with `BLITZCLEAN_DESIGN_DIR=artifacts/cleaner swift test --filter CleanerRenderTests`, then inspect a packaged app. `BLITZCLEAN_SIGNING_IDENTITY=- ./scripts/build-app.sh` builds an ad-hoc local app in `dist`. Open it normally for icon-only launch, or pass `--cleaner` to open the dialog. Test removal only with disposable fixtures.

### Reproduce sound assets

Clone <https://github.com/danielwh2/cuelume> into a scratch directory, check out
`2a1ba4fc1b67e8371c9f37e37a51e61353166335`, then run `npm ci --ignore-scripts` and `npm run build`
there. From this repository, run `node scripts/render-cleaner-sounds.mjs /path/to/cuelume`.
The generator uses Cuelume's own `scripts/sound.mjs` offline engine, default theme, seeded noise,
subtle emphasis for clicks/opening and normal emphasis for results. Eight 48 kHz stereo WAVs are committed
under `Sources/BlitzClean/Resources/Cuelume`. SwiftPM bundles them; app packaging copies the resource bundle
and MIT notice. No Node.js runtime or network connection is needed in the app.

LiquidGlass is pinned to revision `36f81c85922aa3475b7e5bb210e69ffe20a2b377` in SwiftPM. Packaging includes
its resource bundle (needed by the older-system renderer) and original MIT license. Its package skill is
the reference for `.liquidGlass` and `.glassStyleButton`; checkbox labels and keyboard behavior continue
to use the app's accessible controls.
