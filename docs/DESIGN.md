# xean design

xean is a single-panel menu bar cleaner. These rules describe the active product; inherited dashboard
components are retained for compatibility, not a reference for new cleaner UI.

Use AppKit's native `NSPopover` for its translucent gray material, border, pointer, shadow and
screen-edge placement. Do not layer a custom material, outline or shape over its background. Follow
the system appearance, including accessibility preferences. Content is 420 × 580 points, shortened
on smaller screens. Use native SwiftUI switches, checkboxes, text fields and segmented
pickers. Primary and secondary actions use native glass button styles on macOS 26 or newer, with
standard bordered styles on earlier systems. Do not add custom tints, button outlines or shadow clips.
Keep sections unboxed, with compact spacing and no horizontal dividers.

The header is one line: lowercase “xean”, available space, and an accessible power icon.
Power and ⌘Q replace the contents with a compact “Quit xean?”, Cancel and Quit row. This is the same
popover, resized to 64 points of content, not a modal. Cancel or Escape restores the cleaner. Dismissing
and reopening starts in the normal cleaner. Clicking the icon again, clicking outside, Escape and ⌘W
close the panel while disk checks and active cleanup continue; Quit exits.

Keep custom animations at 180 ms with no bounce, text fades, text reveals or content scaling.
Popover visibility uses a short whole-window fade. Disclosures and removed entries animate their
clipped height, leaving text layout unchanged. Unmount closed controls after the collapse so they
cannot retain keyboard focus or accessibility entries. Reduce Motion makes these changes immediate.
Mouse-wheel steps ease over 180 ms; trackpads retain native momentum. Preserve the short scroll-edge
blur and fade while keeping the header and footer fixed. Do not scale rows as they scroll. Increased
Contrast removes the edge fade; Reduce Motion and Increased Contrast disable scroll blur.

Auto-clean is the first row, with an editable GB threshold. “Notify when low” immediately follows
in the same one-line layout: label, numeric input, GB and switch. Keep both independent thresholds
visible even when their switches are off. Numeric inputs have no up/down stepper arrows. The auto-clean
opt-in replaces the existing row with “Enable auto-clean?”, Cancel and OK, using the same 34-point
height. Do not repeat the threshold input in this confirmation. Swap the
text directly without revealing or fading it. Both switches off means manual cleanup only. Existing
shared thresholds migrate to both preferences. Background checks run every 25 minutes with no
interval editor. Low-space warnings use a red exclamation badge on the eraser and free-space header;
there are no system notifications or permission controls.

Category title rows expand independently from native selection checkboxes. The whole title row
opens its disclosure. Lists show item names, paths, sizes and a direct Delete action; worktrees also
show branches. Protected items show their reason instead. Show only entries measured at 50 MB or
larger; this display filter does not change bulk cleanup eligibility. Reuse completed category scans
for 30 seconds, including when Clean follows a dropdown scan. Clear expired results before showing
Checking… and scan only missing or expired categories. There is no Refresh button. Individual
successful removals collapse out; failures stay with their reason.

The idle footer has one right-aligned Clean button and no hint text. Clean immediately scans and
removes eligible selected data, with no review or second confirmation. Replace the settings with a
cleanup screen: scanning status first, then the actual deletion queue. Collapse each row only after
its deletion succeeds; failures stay visible. After the final collapse show a result screen with
removed bytes and count. Distinguish successful, empty and partial/failed runs, retaining reasons for
items that could not be removed. Do not claim files were removed when none were. Done closes the
panel. Closing clears this transient result; closing during cleanup must not cancel deletion or
resurrect its result on reopen. Individual Delete retains brief footer feedback for five seconds.
Background cleanup does not open a result screen. Keep history internally without a persistent
Last cleanup paragraph. There is no Stop button. Cuelume interaction sounds are enabled at 70%,
with no sound settings; opening and closing are silent.

Menu bar metrics use the original BlitzClean icons, typography and renderer, positioned to the left
of the eraser. Width changes animate for 180 ms while the eraser and its popover stay anchored.
Attach the native popover to a fixed-size view over the eraser, pinned to the trailing edge of the
status button. Let AppKit follow that view; do not recalculate the pointer from the changing stats image.
Show menu bar stats is enabled by default and stops two-second sampling when disabled. Clicking its
label or switch toggles the feature and reveals or collapses the metric controls directly beneath it,
indented one level. Do not add a separate Stats shown row or disclosure. The controls select CPU, memory
and disk, including a single metric, and the original available/used/percentage memory formats. Keep at least
one metric while enabled. Login remains a native switch. Do not start the historical process monitors.

Automatic cache/build cleanup uses a 24-hour minimum, dependencies seven days, and worktrees their
configured age. Manual Clean skips age cutoffs while retaining activity and identity checks. Nested
package links are fingerprinted without following destinations; linked cleanup roots stay protected.
Scanning and validation have no arbitrary entry, depth or elapsed-time caps and support cancellation.
Project discovery still discovers common locations without a Project folders editor. Every deletion
revalidates its target, including removals based on cached scans. See [the user guide](CLEANER.md#cleanup-rules) for cleanup policies.

Historical dashboard components remain available to upstream tests but are not instantiated by the app.

## Verification

Inspect changed UI in the running packaged app, including system light/dark appearance, a smaller screen,
keyboard interaction, and applicable accessibility preferences. Exercise loading, empty, populated, long-path,
disabled, failed-removal, and completion states with a fixture driver. Never clean real user data for UI QA.

`BLITZCLEAN_DESIGN_DIR=artifacts/cleaner swift test --no-parallel -j 2 --filter CleanerRenderTests` provides
fixture renders. These supplement running-app checks; they do not prove native popover/glass appearance.
Popover and menu bar tests cover anchoring, fast reopen, and presentation lifetime. A successful build is
not visual acceptance. Use synthetic data for any public screenshots.
