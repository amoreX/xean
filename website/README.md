# xean website

A single-page static site inspired by the spare layout of [knowyourshit](https://github.com/amoreX/knowyourshit), with an ivory, sage, and deep teal palette. The implementation is plain HTML, CSS, and JavaScript; there is no build step or dependency installation.

## Preview

From the repository root:

```sh
./start-site.sh
```

Open `http://127.0.0.1:4173`. Python 3 is the only requirement; no account, Node.js, or package installation is needed. Keep the terminal running and press Ctrl+C to stop it. Use `./start-site.sh 4174` to choose another port. The launcher works from any working directory.

## Contents

- `dist/index.html`: minimal hero, interactive product preview, GitHub links, and a large footer wordmark.
- `dist/styles.css`: responsive layout, local fonts, 180 ms control and row-height transitions, reduced-motion support.
- `dist/app.js`: synthetic cleanup demonstration, stats toggle, and reset.
- `dist/assets/fonts`: self-hosted Manrope and Instrument Serif with their SIL Open Font License notices.
- `dist/assets/github.svg`: GitHub mark from [Octicons](https://github.com/primer/octicons), with its MIT license in `octicons-LICENSE.txt`.

The preview contains synthetic sizes and never reads, scans, or deletes visitor files. Get xean links directly to the repository’s installation instructions. No analytics, remote fonts, or browser storage are used.

The website source lives in the [xean fork](https://github.com/amoreX/xean) alongside the native app. Deploy `website/dist/` to any static host with no build command. Optional local hosting metadata is ignored by Git; the site has no dependency on ChatGPT Sites.
