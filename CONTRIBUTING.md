# Contributing to xean

xean is a focused macOS menu bar cleaner. Useful contributions include reproducible bug reports, compact
UI fixes, documentation, and supported cleanup locations backed by deletion-boundary tests.

Use [pull requests](https://github.com/amoreX/xean/pulls) for contributions. For a larger change, start with
a draft PR describing the problem and proposed scope before implementing it. Repository issue forms are
included for when Issues is enabled. Do not send xean-specific support requests to the upstream project.

## Setup

Use full Xcode 26 or newer and a Mac capable of running it. The app's runtime minimum is macOS 14; native
Liquid Glass controls are conditional on macOS 26+. Select Xcode's command-line tools, then run:

```sh
./start.sh
```

The launcher builds and opens the checkout's `dist/BlitzClean.app` with ad-hoc signing by default. Quit
xean and use `./start.sh --build` after source edits. Set `BLITZCLEAN_SIGNING_IDENTITY` to use your own
certificate. The target and bundle still use the inherited name; see [Architecture](docs/ARCHITECTURE.md).

## Checks

```sh
swift test --no-parallel -j 2 --filter Cleaner
./scripts/check.sh
```

The full check script builds, runs tests sequentially, lints Swift, validates plists, and checks shell
syntax. Retained media integration tests need FFmpeg/FFprobe (`brew install ffmpeg`). The cleaner itself
has no FFmpeg requirement. Keep build concurrency modest and avoid competing full-directory scans.

Format changed Swift files with `xcrun swift-format format --in-place <files>`. For packaging changes,
run `BLITZCLEAN_SIGNING_IDENTITY=- ./scripts/build-app.sh` and verify the resulting bundle.

## UI changes

Read [Design](docs/DESIGN.md) before changing visible UI or product copy. Use native controls and the
existing cleaner components. Inspect changed screens in the running packaged app, including light/dark
appearance, compact screens, loading, empty, partial failure, and completion where relevant.

Fixture renders are a useful additional check:

```sh
BLITZCLEAN_DESIGN_DIR=artifacts/cleaner swift test --no-parallel -j 2 --filter CleanerRenderTests
```

Native popover borders and composited glass also need a running-app check. Capture before/after examples
with synthetic names and paths; do not publish personal desktop screenshots or real project inventories.
Use fixture drivers for cleaning/progress demos and never enable real auto-clean for visual QA.

## Cleanup changes

- Test removals against disposable fixtures, never a contributor's real caches or projects.
- Preserve fresh identity, allowlist, activity, open-file, and applicable age checks before deletion.
- Keep root links protected; do not traverse nested symlink destinations.
- Preserve lockfile requirements and Git protections for primary, active, dirty, locked, detached,
  unmerged, or explicitly kept worktrees. Keep Docker images, containers, and volumes outside this cleaner.
- Manual Clean and Delete are intentionally immediate. Automatic cleanup must remain an explicit opt-in,
  use the chosen threshold/categories, and retain automatic age rules.
- Unreadable or unverifiable data must remain protected. Do not treat partial measurements as verification.
- Preserve 30-second category caching with immediate stale-result clearing, and revalidate cached targets.
- Keep removal history bounded and omit credentials, command lines, and conversation contents.
- Preserve existing preference/history compatibility or provide a tested migration.

## Pull requests

Explain the problem, resulting behavior, and relevant verification. Keep scope focused and disclose any
checks you could not run. Include targeted tests for changed deletion boundaries, caching, persistence,
or operation lifetime; documentation-only edits do not require rebuilding the app.

Do not commit private paths, secrets, local history, generated builds, or unredacted machine screenshots.
Read [Security](SECURITY.md) before sharing a potential unsafe-deletion report. Preserve upstream and
third-party notices in [Open-source credits](OPEN_SOURCE_BASES.md).

Contributions are licensed under this repository's [MIT License](LICENSE).
