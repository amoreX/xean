# xean design

xean is a single-panel menu bar cleaner. These rules describe the active product; inherited dashboard
components are retained for compatibility, not a reference for new cleaner UI.

Use AppKit's native `NSPopover`, light by default with a persistent light/dark choice. On macOS 26+, set its native glass
backdrop to the regular frosted style with a 12% white or black tint matching the theme for a neutral, translucent surface that
diffuses background details. Keep content at
full opacity and leave the glass inside hosted controls untouched. AppKit owns the material, border,
pointer, shadow and screen-edge placement; do not layer a custom material, outline or shape over it.
The choice is independent of macOS appearance. Reduce Transparency and increased contrast restore
the standard native material, including when those settings change while open. Earlier macOS versions
retain their standard native popover. Content is 420 × 580 points, shortened
on smaller screens. Use native SwiftUI switches, checkboxes, text fields and segmented
pickers. Primary and secondary actions use native glass button styles on macOS 26 or newer, with
standard bordered styles on earlier systems. Do not add custom tints, button outlines or shadow clips.
Keep sections unboxed, with compact spacing and no horizontal dividers.

The header is one line: lowercase “xean”, available space, a refresh button, a sun/moon theme button, and an accessible power icon.
The theme button crossfades the rendered popover over 180 ms without moving or rebuilding it, and
remembers the choice across launches. The temporary image is local to the view, ignores input and
accessibility, and is removed when the fade finishes or the panel closes/resizes. Rapid switches start
from the current blend; Reduce Motion switches immediately. Its help and accessible label describe the destination theme.
This control belongs only to the native app; do not add it to the website preview.
Power and ⌘Q replace the contents with a compact “Quit xean?”, Cancel and Quit row. This is the same
popover, resized to 64 points of content, not a modal. Cancel or Escape restores the cleaner. Dismissing
and reopening starts in the normal cleaner. Clicking the icon again, clicking outside, Escape and ⌘W
close the panel while disk checks and active cleanup continue; Quit exits.

Keep ordinary control and disclosure animations at 180 ms with no bounce, text reveals or content
scaling. Popover visibility uses a short whole-window fade. Disclosures animate their clipped height,
leaving text layout unchanged. Confirmed removals use a red center-out background sweep (320 ms),
a 120 ms hold, a short 18-point slide and fade (240 ms), then height collapse (280 ms). Present bulk
removals one at a time without delaying filesystem operations; show the result after the last animation.
Use the same removal treatment for an individual Delete and the website preview. The website runs this
faster: 80 ms sweep, 16 ms hold, 56 ms departure and 64 ms collapse, with a 48 ms per-item lead-in.
The website popover has one continuous curved outline and glass surface, including the rounded notch
beneath the menu bar icon; keep its notch and body joined while the panel resizes.
Unmount closed controls after the collapse so they
cannot retain keyboard focus or accessibility entries. Reduce Motion makes these changes immediate.
Mouse-wheel steps ease over 180 ms; trackpads retain native momentum. Preserve the short scroll-edge
blur and fade while keeping the header and footer fixed. Hide the additional macOS 26 scroll-edge
effect; blur only the rows, not a second backdrop rectangle over the glass. Do not scale rows as they scroll. Increased
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
show branches. Protected items show their reason instead. Show eligible entries measured at 50 MB or
larger, with a count and total for smaller eligible items. Show protected entries whose size is unknown, and display scan notes and running-tool skips. The display filter does not change bulk cleanup eligibility. Reuse completed category scans
for 30 seconds, including when Clean follows a dropdown scan. Clear expired results before showing
Checking… and scan only missing or expired categories. The header Refresh button bypasses this cache and rescans selected and previously opened categories without deleting anything. Disable it during scanning or cleanup and while showing cleanup results. Individual
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
Capture the eraser's screen position when opening and keep the panel stationary until it closes.
Use a transparent, noninteractive native anchor host at that fixed position so the popover never follows
intermediate menu bar layout changes. Reopening captures the current eraser position. The host adds no
visible surface or border; AppKit still draws the entire popover. Quit may change its height downward.
Show menu bar stats is enabled by default and stops two-second sampling when disabled. Clicking its
label or switch toggles the feature and reveals or collapses the metric controls directly beneath it,
indented one level. Do not add a separate Stats shown row or disclosure. The controls select CPU, memory
and disk, including a single metric, and the original available/used/percentage memory formats. Keep at least
one metric while enabled. Login remains a native switch. Do not start the historical process monitors.

Automatic cache/build cleanup uses a 24-hour minimum, dependencies seven days, and worktrees their
configured age. Manual Clean skips age cutoffs while retaining activity and identity checks, except temporary Python environments, Xcode build output, and Tickle test folders, which always require at least 24 hours. Nested
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
