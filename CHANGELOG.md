# xean changelog

## 2026-10-17 — Current source build

This is the xean fork's development history, not a published binary release. The bundle still carries
inherited BlitzClean version and identity fields.

### Cleaner

- Replace the dashboard entry point with a single menu bar cleanup panel.
- Provide ten categories covering developer/app caches, browsers, build output, dependencies, unused Docker
  builder cache, and eligible Git worktrees.
- Run manual Clean and individual Delete immediately, without a second confirmation or age cutoff, while
  retaining fresh location, identity, activity, and project checks.
- Expand category titles to inspect items, paths, sizes, branches, and protection reasons; show measured
  entries of at least 50 MB without changing the bulk-cleanup scope.
- Reuse completed manual category scans for 30 seconds, clear invalidated results before rescanning, and
  remove arbitrary entry/depth/project/time caps from cleaner traversal.
- Support nested package links without following destinations; protect linked cleanup roots.

### Background and menu bar

- Add opt-in auto-clean and independent visual low-space warnings, each with an editable GB threshold.
- Check every 25 minutes while running, with automatic age rules and a post-scan free-space check.
- Use a red exclamation badge instead of OS notifications or notification permission requests.
- Place optional CPU, memory, and disk stats to the left of the eraser; stop their two-second sampling
  when disabled and retain individual metric/memory-format choices.

### Interface

- Use an AppKit-native popover and native SwiftUI controls, including Liquid Glass buttons on macOS 26+.
- Follow system appearance and accessibility settings; retain the scroll-edge blur and fade.
- Use 180 ms custom motion with height-only disclosures/removals and no text-reveal animations.
- Show the deletion queue during Clean, collapse successful removals, and distinguish success, empty, and
  partial results. Clear the result on panel close without canceling an active operation.
- Keep confirmations compact and inline, with no repeated auto-clean threshold input.
- Bundle local Cuelume interaction sounds; keep panel opening/closing and background work silent.

### Repository and development

- Publish the source at [amoreX/xean](https://github.com/amoreX/xean).
- Add `start.sh` for first-run building, local launch, and explicit rebuilds without interrupting a running app.
- Stamp packaged binaries with the build SDK version to preserve current native macOS appearance.
- Rewrite documentation around xean's features, component map, cleanup policy, privacy, and build process.

## Upstream history

[BlitzClean's original release notes](docs/UPSTREAM_CHANGELOG.md) are preserved separately, including the
1.4.0 baseline. They describe the upstream dashboard and release channel, not xean's current interface.
