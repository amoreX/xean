# xean roadmap

The current source build already has the single-panel cleaner, category inventories, immediate manual
cleanup, opt-in automatic cleanup, visual low-space warnings, configurable menu bar stats, and native glass
controls. See [Features](FEATURES.md) for shipped behavior.

The following are follow-up areas, not implemented features or release commitments:

- **Independent app identity.** Rename the executable, bundle, artwork, preference domain, and data directory
  with an explicit migration plan. xean currently shares BlitzClean's compatibility identifiers.
- **Binary distribution.** Prepare xean-specific versioning, signed/notarized downloads, checksums, and
  release validation for both supported Mac architectures.
- **Update infrastructure.** Replace inherited feed/key defaults before considering an xean updater.
  The current app does not start Sparkle.
- **Broader UI validation.** Exercise light/dark appearance, Reduce Motion, Increase Contrast, keyboard
  access, VoiceOver, older macOS fallbacks, and smaller screens on more hardware.
- **Cleanup coverage.** Add supported cache/build locations only with fixture tests for their deletion
  boundaries, active-tool checks, and failure states.
- **Large-tree profiling.** Continue measuring traversal and cancellation with representative disposable
  dependency/build trees without reintroducing arbitrary scan caps.

Contributions should keep the menu bar utility compact and preserve explicit auto-clean opt-in and fresh
removal validation. See [Contributing](../CONTRIBUTING.md) before proposing a larger change.
