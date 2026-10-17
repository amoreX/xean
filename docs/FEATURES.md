# xean features

This page describes the current cleaner. The inherited dashboard, recovery tools, media tools, and process
controls remain in source but are not exposed by xean.

## Cleanup and inspection

| Feature | Behavior |
| --- | --- |
| Ten cleanup categories | Claude Code, Codex, Superconductor, coding editors, packages, browsers, builds, dependencies, Docker builder cache, and worktrees |
| Manual Clean | Scan selected categories and immediately remove eligible items, with no second confirmation or age cutoff |
| Category disclosure | Click the title or chevron to inspect paths, sizes, worktree branches, and protected-item reasons |
| Individual Delete | Remove one eligible item independently of the bulk-selection checkbox |
| Inventory visibility | Dropdowns show measured items of at least 50 MB; smaller items can still participate in bulk cleanup |
| Scan reuse | Reuse completed category results for 30 seconds; clear stale results before scanning again |
| Complete tree traversal | No arbitrary entry, depth, project-count, or elapsed-time cutoff in cleaner traversal; unreadable or interrupted scans are not treated as verified |
| Deletion progress | Collapse each queue entry only after successful removal; keep failures visible |
| Result screen | Distinct success, empty, and partial results with counts and measured bytes; reset on panel close |

The exact cache allowlist and project rules are in [the user guide](CLEANER.md#cleanup-rules) and
[`CleanerPolicy.swift`](../Sources/BlitzClean/CleanerPolicy.swift).

## Background controls

Auto-clean and low-space warnings are independent and initially off. Each has a 1–1,000 GB threshold,
defaulting to 20 GB. Auto-clean requires a short inline opt-in. Background checks run every 25 minutes
while the app is running, without waking the Mac. A fresh disk check after the automatic scan can cancel
deletion if enough space has already been freed.

Automatic caches/builds and Docker builder cache retain a 24-hour minimum; dependencies retain seven days.
Worktrees use a configurable 1–365 day minimum, defaulting to 30 days. Manual deletion skips age rules but
keeps the same identity, activity, and location checks.

“Notify when low” means a red badge on the eraser and free-space value. It does not request permission or
send system notifications. Start at login uses macOS's native login-item service.

## Menu bar and interface

- Optional CPU, memory, and disk metrics to the left of the eraser; at least one metric when enabled.
- Available memory, used memory, or used percentage, with two-second sampling that stops when disabled.
- Native popover material and borders, system appearance, and native switches, checkboxes, inputs, and pickers.
- Native Liquid Glass buttons on macOS 26+, with standard bordered fallbacks on macOS 14–15.
- Fixed header and footer, soft scroll-edge blur, and 180 ms height transitions without text animations.
- Reduce Motion and Increase Contrast adjustments.
- Local interaction sounds; silent opening, closing, and background operations.
- Compact inline confirmations for enabling auto-clean and quitting; no separate confirmation modal.

## Current limits

Project discovery starts from known development/tool locations and preserved custom roots; it is not a
whole-disk browser. A folder can be large and still ineligible because it is active or fails verification.
The 50 MB visibility filter also hides unmeasured protected entries. The app does not delete arbitrary
personal files, whole app profiles, conversation history, Docker volumes, or the primary Git checkout.

There is no xean binary release or active automatic updater yet. Bundle naming and stored data retain
BlitzClean compatibility identifiers. See [Roadmap](ROADMAP.md) for follow-up work.
