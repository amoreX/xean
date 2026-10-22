<h1 align="center">xean</h1>
<p align="center">A small macOS menu bar cleaner for developer caches, build files, and old worktrees.</p>
<p align="center">Native SwiftUI + AppKit · Liquid Glass on macOS 26+ · Free and open source</p>
<p align="center">A fork of <a href="https://github.com/blitzreels/blitzclean">BlitzClean by BlitzReels</a>, focused on developer cleanup.</p>
<p align="center">
  <a href="https://x3an.vercel.app">Website</a> ·
  <a href="#get-started">Get started</a> ·
  <a href="docs/CLEANER.md">User guide</a> ·
  <a href="docs/ARCHITECTURE.md">Components</a> ·
  <a href="CONTRIBUTING.md">Contribute</a> ·
  <a href="LICENSE">MIT license</a>
</p>

xean lives behind an eraser in your menu bar. Choose what to clean, inspect individual folders if you want,
and press **Clean**. Entries collapse as they are removed, followed by a result showing what was cleaned
and what was kept. Close the panel to return to a fresh view next time.

Optional CPU, memory, and disk stats sit to the **left** of the eraser, keeping the cleaner anchored as
stats appear and disappear. Everything runs locally, with no account, subscription, or telemetry.

xean is a fork of [BlitzClean](https://github.com/blitzreels/blitzclean), focused on a single cleanup panel.
The upstream dashboard is not part of xean's interface.

## Get started

**Run:** macOS 14 or later. **Build:** full Xcode 26 or newer, with its command-line tools selected.
Native Liquid Glass buttons require macOS 26 or newer; earlier systems use standard bordered controls.
The repository is distributed as source; there is no xean binary release yet.

```sh
git clone https://github.com/amoreX/xean.git
cd xean
./start.sh
```

The launcher builds `dist/BlitzClean.app` on first run and opens the cleaner. Later runs reuse the built app.
It uses local ad-hoc signing by default, so you do not need an Apple Developer account. It leaves the app
inside the checkout and does not install over an existing copy in Applications.

After changing the source, **quit xean**, then rebuild:

```sh
./start.sh --build
```

Run `./start.sh --help` for launcher usage. It works from any directory and refuses to rebuild over a
running app. The first build downloads SwiftPM dependencies; subsequent launches use the local bundle.

The executable, app filename, preference domain, and source target retain **BlitzClean** compatibility
names. The macOS display name and permission copy use **xean**. See
[compatibility names](docs/ARCHITECTURE.md#compatibility-names) for the exact paths.

## What it cleans

| Category | Supported data |
| --- | --- |
| Claude Code | CLI and Claude desktop caches |
| Codex | Desktop and renderer caches; sessions stay |
| Superconductor | Desktop and web caches |
| Coding editors | Cursor, VS Code, Windsurf, Zed, and fed10 caches |
| Package caches | npm/npx, Yarn, pip, uv, Bun, Homebrew, and verified temporary Python environments |
| Browser caches | Supported Safari, Chrome, Firefox, and Zen caches |
| Build files | Xcode DerivedData, temporary Xcode builds/tests, and supported Swift, Rust, and web build output |
| Project dependencies | Inactive `node_modules` with a reinstall lockfile |
| Docker build cache | Unused local builder cache; images, containers, and volumes stay |
| Unused Docker images | Separate opt-in for unreferenced images older than 24h, including tagged local builds; containers and volumes stay |
| Old worktrees | Eligible clean, merged, inactive Git-linked checkouts; branches stay |

Claude Code, Codex, Superconductor, coding editors, package caches, and build files are selected by default.
Browsers, dependencies, Docker, and worktrees are opt-in. Existing preferences are preserved.

**Clean and individual Delete actions permanently remove eligible data immediately, without a second
confirmation.** Manual cleanup skips ordinary cache/build age cutoffs; temporary environments/builds/tests and unused Docker images always require 24 hours. Active tools, open files, protected locations, and items
that changed after scanning remain protected. See [cleanup rules](docs/CLEANER.md#cleanup-rules).

## One panel, a few controls

- **Inspect a category.** Click its title or chevron to open the list. Items show a name, path, size, and
  Delete action, or a reason they are protected. Worktrees also show their branch.
- **Reuse recent scans.** Completed category scans are cached for 30 seconds. Expired or invalidated results
  disappear before a fresh scan starts. No refresh button, and no entry-count limit on cleaner traversal.
- **Keep lists useful.** Category dropdowns show measured entries of at least 50 MB. This is a display
  filter: smaller eligible items have a count and total. Scan skips and unknown-size protected locations remain visible.
- **Auto-clean when space is low.** Set its GB threshold and opt in once. Checks run every 25 minutes while
  xean is running, using age rules for automatic deletion.
- **Show a low-space warning.** “Notify when low” has its own threshold and adds a red exclamation badge.
  It does not send macOS notifications or ask for notification permission.
- **Choose your stats.** Enable CPU, memory, disk, or just one. Memory can show available GB, used GB,
  or used percentage. Turning stats off stops their two-second sampler.
- **Start at login.** Enable the native login switch if you want xean available after signing in.

Auto-clean and low-space warnings start off. Their independent thresholds default to 20 GB and remain
editable beside their switches. [The user guide](docs/CLEANER.md) covers timing, defaults, and protected items.

## Native macOS UI

AppKit owns the popover's translucent background, border, pointer, and shadow. SwiftUI supplies native
switches, checkboxes, numeric fields, and segmented controls. On macOS 26+, actions use native Liquid Glass
button styles. The panel defaults to light, with a persistent light/dark theme button beside free space.

The header and Clean button stay fixed while content scrolls through a soft edge blur. Custom transitions
take 180 ms: disclosures and removed entries animate their height without moving or revealing individual
letters. Reduce Motion disables custom motion; accessibility settings also adjust the scroll effects.
Local [Cuelume](https://cuelume.dev) sounds accompany interactions and results. Opening, closing, and
background cleanup are silent.

Click outside, press Escape or ⌘W, or click the eraser again to close the panel. Closing during cleanup
keeps the operation running. The power icon or ⌘Q opens a compact inline Quit confirmation.

## Components

The active app is organized around a small set of components in [Sources/BlitzClean](Sources/BlitzClean):

| Component | Responsibility |
| --- | --- |
| [`BlitzCleanApp`](Sources/BlitzClean/BlitzCleanApp.swift) | Menu bar item, app lifetime, popover anchoring, and keyboard actions |
| [`CleanerPopover`](Sources/BlitzClean/CleanerPopover.swift) | Native popover presentation, resizing, and dismissal |
| [`CleanerView`](Sources/BlitzClean/CleanerView.swift) | Main panel, thresholds, category selection, settings, and inline confirmations |
| [`CleanerCategoryRow`](Sources/BlitzClean/CleanerCategoryRow.swift) | Expandable inventory, individual deletion, and height-only transitions |
| [`CleanerCleanupView`](Sources/BlitzClean/CleanerCleanupView.swift) | Scan progress, removal queue, success, empty, and partial results |
| [`CleanerModel`](Sources/BlitzClean/CleanerModel.swift) | State, scan caching, background checks, cleanup sequencing, and result lifetime |
| [`CleanerPolicy`](Sources/BlitzClean/CleanerPolicy.swift) | Categories, cache allowlist, preferences, defaults, and thresholds |
| [`CleanerScan`](Sources/BlitzClean/CleanerScan.swift) | Scan/driver types, project discovery, candidate consolidation, and deletion routing |
| [`CleanerMenuBarStats`](Sources/BlitzClean/CleanerMenuBarStats.swift) | Optional CPU, memory, and disk sampling and display preferences |
| [`CleanerControls`](Sources/BlitzClean/CleanerControls.swift) | Native glass button styles and aligned switch rows |

[Architecture](docs/ARCHITECTURE.md) maps the shared safety services, scroll effects, renderer, sound assets,
persistence, dependencies, and test suites. Older dashboard code remains in the repository but is not
instantiated by xean.

## Development

```sh
# Focused cleaner tests, including fixtures and popover behavior
swift test --no-parallel -j 2 --filter Cleaner

# Full repository checks, including retained upstream suites
./scripts/check.sh
```

Full media integration tests require FFmpeg/FFprobe (`brew install ffmpeg`); the cleaner itself does not.
Test deletion only against disposable fixtures. See [Contributing](CONTRIBUTING.md) for UI verification,
formatting, and changes to cleanup policy. [Releasing](docs/RELEASING.md) covers local packaging and the
remaining work for independent xean releases.

## Website

The one-page website is in [`website/dist`](website/dist), alongside the app source. To run it locally:

```sh
./start-site.sh
```

Open **http://127.0.0.1:4173**. The launcher requires Python 3 and serves only on localhost. Keep it running
while previewing; press Ctrl+C to stop. No package install or build step is needed. See the
[website guide](website/README.md) for another port or static hosting.

## Documentation

| Guide | Contents |
| --- | --- |
| [User guide](docs/CLEANER.md) | Everyday use, cleanup rules, defaults, and troubleshooting |
| [Features](docs/FEATURES.md) | Current functionality and its limits |
| [Architecture](docs/ARCHITECTURE.md) | Components, data flow, and repository map |
| [Design](docs/DESIGN.md) | Native controls, layout, motion, and interaction rules |
| [Privacy](docs/PRIVACY.md) | Local data, permissions, and network behavior |
| [Performance](docs/PERFORMANCE.md) | Scan caching, traversal, sampling, and validation |
| [Changelog](CHANGELOG.md) | xean changes and the upstream release history |
| [Roadmap](docs/ROADMAP.md) | Follow-up work, separate from implemented features |
| [Website](website/README.md) | One-page landing site, local preview, and static hosting |

## Credits and license

xean is an [MIT-licensed](LICENSE) fork of [BlitzClean](https://github.com/blitzreels/blitzclean) by BlitzReels.
Original copyright and third-party notices are preserved. [Open-source credits](OPEN_SOURCE_BASES.md)
explain the inherited code, bundled dependencies, and Cuelume sound assets.
