# xean website

A single-page static site inspired by the spare layout of [knowyourshit](https://github.com/amoreX/knowyourshit), with an ivory, sage, and deep teal palette. The implementation is plain HTML, CSS, and JavaScript; there is no build step or dependency installation.

## Preview

From the repository root:

```sh
./start-site.sh
```

Open `http://127.0.0.1:4173`. Python 3 is the only requirement; no account, Node.js, or package installation is needed. Keep the terminal running and press Ctrl+C to stop it. Use `./start-site.sh 4174` to choose another port. The launcher works from any working directory.

## Contents

- `dist/index.html`: minimal hero, install chooser, interactive product preview, and a footer wordmark with Nihal’s X link.
- `dist/styles.css`: responsive layout, local fonts, responsive controls, 320 ms disclosures and staged removal animations, and reduced-motion support.
- `dist/app.js`: agent installation prompt, clipboard feedback/fallback, install chooser, and sound control.
- `dist/demo.js`: synthetic app state, live metrics, category inventories, cleanup queue, and automatic walkthrough.
- `dist/sounds.js`: gesture-triggered Web Audio playback of the native app’s Cuelume cues, at the same 70% volume.
- `dist/assets/fonts`: self-hosted Manrope and Instrument Serif with their SIL Open Font License notices.
- `dist/assets/github.svg`: GitHub mark from [Octicons](https://github.com/primer/octicons), with its MIT license in `octicons-LICENSE.txt`.
- `dist/assets/sounds`: seven cues from the app’s `Sources/BlitzClean/Resources/Cuelume` directory; their MIT license is included as `LICENSE.txt`.

Get xean expands into two choices. **Let your agent do it** copies a setup prompt and shows “Prompt copied”; if clipboard access fails, a selectable text field provides the prompt. **Do it yourself** opens the repository’s installation instructions.

The browser preview uses a shorter 420 × 500 panel with the native cleaner’s categories, settings, scroll-edge blur, compact quit confirmation, and cleanup/result screens. It uses example paths and sizes and never reads, scans, or deletes visitor files. The silent walkthrough scrolls to worktrees over 950 ms, visibly highlights and presses the checkbox and disclosure, and pauses for reading. It also highlights and presses Clean before switching screens. The checking screen keeps the selected queue visible; each removed entry gets the same red center-out sweep, short slide/fade, and height collapse as the native app, one row at a time, and numbers ease to their new values over 480 ms. The success screen stays visible for six seconds before the next cycle. Interacting interrupts the automatic scrolling; replay starts the walkthrough again. Reduced Motion disables automatic playback and movement. Sound cues play only for user actions, with a mute control beside the preview.

No analytics, remote fonts, or browser storage are used. The preview is implemented in HTML/CSS; the installed app uses native SwiftUI and AppKit components.

The website source lives in the [xean fork](https://github.com/amoreX/xean) alongside the native app. Deploy `website/dist/` to any static host with no build command. Optional local hosting metadata is ignored by Git; the site has no dependency on ChatGPT Sites.
