# xean and retained bundle artwork

The current product name is lowercase **xean**. Its active menu bar icon is the system `eraser.fill` symbol;
optional metrics sit to its left. AppKit supplies the popover's appearance, pointer, border, and shadow.
Do not add a custom glass background or outline to the cleaner.

The app bundle still contains inherited BlitzClean artwork and uses the `BlitzClean.app` filename. These
assets are retained, not a new xean logo. A separate bundle/artwork migration is listed in
[the roadmap](../../docs/ROADMAP.md).

| Asset | Contents |
| --- | --- |
| `BlitzClean.icon/Assets/Mark.svg` | Transparent 1024 × 1024 mint C/lightning foreground |
| `BlitzClean.icon/Assets/Background.svg` | Opaque graphite background layer |
| `BlitzClean.icon/icon.json` | Layered Icon Composer source |
| `app-icon.png` | 1024 px fallback artwork used to generate the bundled ICNS |
| `family/` | Retained BlitzReels/BlitzRecorder artwork for upstream views; not promoted in xean's panel |

The layered Icon Composer document is not currently used by the packaging script. Regenerate the fallback
artwork and ICNS from the repository root with:

```sh
swift scripts/render-icon.swift assets/brand/app-icon.png
./scripts/build-icon.sh
```

Preserve source attribution and license notices. Follow [Design](../../docs/DESIGN.md) for active cleaner
UI changes rather than the visual conventions of the retained dashboard artwork.
