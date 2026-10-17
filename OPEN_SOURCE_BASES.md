# xean open-source credits

xean is a fork of [BlitzClean](https://github.com/blitzreels/blitzclean). Its cleaner reuses the upstream
cache, filesystem, project/Git, Docker, metric-rendering, and history infrastructure, with a focused menu
bar interface and its own cleanup orchestration. Upstream dashboard and other modules remain in source.

The [MIT License](LICENSE) preserves the BlitzReels, BlitzClean, and Buildkeep copyright notices.
This fork does not replace those credits or claim the inherited code and artwork as newly authored.

## Bundled packages and assets

| Project | Role in this repository | Notice |
| --- | --- | --- |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Inherited SwiftPM updater framework, included in bundles; xean does not instantiate its updater | The packaging script copies Sparkle's own license from the resolved artifact |
| [LiquidGlass](https://github.com/metneo/LiquidGlass) | Pinned dependency used by retained shared components; the active cleaner uses AppKit/SwiftUI native controls | [MIT notice](licenses/LiquidGlass-LICENSE.txt) |
| [Cuelume](https://github.com/danielwh2/cuelume) | Eight locally rendered interaction cues played through AVAudioPlayer | [MIT notice](licenses/Cuelume-LICENSE.txt) |
| [OrphanBar](https://github.com/scr2em/orphan-bar) | Adapted leftover-process rules in retained upstream code, not an active xean feature | [MIT notice](licenses/OrphanBar-LICENSE.txt) |

SwiftPM pins LiquidGlass to `36f81c85922aa3475b7e5bb210e69ffe20a2b377`. Sparkle's declared requirement is
in [`Package.swift`](Package.swift); `Package.resolved` records the resolved dependency state.

## Reproducing Cuelume sounds

Cues use the upstream default recipes at commit `2a1ba4fc1b67e8371c9f37e37a51e61353166335` (version 0.2.8).
In a separate scratch checkout of Cuelume:

```sh
git checkout 2a1ba4fc1b67e8371c9f37e37a51e61353166335
npm ci --ignore-scripts
npm run build
```

Then, from the xean repository:

```sh
node scripts/render-cleaner-sounds.mjs /path/to/cuelume
```

The script verifies the revision and uses Cuelume's offline renderer with seeded noise and the default
theme. It writes eight 48 kHz stereo WAVs to `Sources/BlitzClean/Resources/Cuelume`. SwiftPM and app packaging
bundle those assets and their MIT notice. The running app needs neither Node.js nor a network connection.

## Inherited design references

The upstream project documented these references; listing them does not imply that all of their features
are implemented in xean or that their authors maintain this fork:

- [ClearDisk](https://github.com/bysiber/cleardisk): developer-cache catalog and storage cleanup concepts.
- [Stats](https://github.com/exelban/stats): native metric collection and menu bar presentation.
- [Purge](https://github.com/jithin-sabu/purge-app): allowlisted cleanup, project-age and lockfile checks.
- [Radix](https://github.com/colinvkim/Radix): scanning, progress, and snapshot design references.

## License policy

Preserve notices for copied or substantially adapted code and assets. Check licenses before adding new
dependencies. Do not import GPL or non-commercial source into this MIT project without first resolving
the licensing implications. The packaged app must continue to include the applicable notices.
