# Building and releasing xean

The public fork currently distributes source. It has no xean binary release or active automatic updater.
Inherited packaging scripts still produce `BlitzClean.app` and use BlitzClean version/bundle identifiers.
Do not describe local ad-hoc builds or inherited upstream releases as notarized xean downloads.

## Local development bundle

```sh
./start.sh
# After source changes, quit xean first:
./start.sh --build
```

The launcher defaults to ad-hoc signing and opens the app in `dist/`. To build without launching:

```sh
BLITZCLEAN_SIGNING_IDENTITY=- ./scripts/build-app.sh
```

The build script bundles SwiftPM resources, Cuelume sounds, the retained LiquidGlass resources, Sparkle,
icons, and license notices, then verifies the signature. It explicitly stamps the installed SDK version
into the executable so AppKit selects the correct native appearance, while retaining the macOS 14 runtime
minimum. Build jobs default to two; `BLITZCLEAN_BUILD_JOBS` overrides this.

## Before an independent release

1. Run the relevant checks and `./scripts/check.sh`; inspect changed UI in the packaged app.
2. Choose xean version/build numbers in `support/Info.plist` and document the exact commit and changes.
3. Review bundle identity and stored-data migration. The current domain/data folder can be shared with
   an upstream BlitzClean installation; an independent identity is still follow-up work.
4. Use your own Developer ID identity and notarization credentials. Keep all secrets outside Git.
5. Keep updates disabled. The current app does not instantiate Sparkle, and inherited release scripts
   contain upstream feed, signing-account, and appcast URL defaults.
6. Exclude local reports, generated binaries, secrets, and personal screenshots from the source commit.

## Signed universal archive

The inherited packaging helper accepts a Developer ID identity and builds both `arm64` and `x86_64`.
For this fork, explicitly skip inherited update signing:

```sh
BLITZCLEAN_SKIP_UPDATES=1 \
BLITZCLEAN_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-notarization-profile' \
  ./scripts/package-release.sh
```

Use a notarization keychain profile configured outside the repository. The script waits for acceptance,
staples and validates the ticket, checks Gatekeeper, recreates the archive, and computes its SHA-256.
Without a notarization profile, it creates a signed preview only; signing alone is not notarization.

Current output names are `dist/BlitzClean-<version>-macOS.zip` and `.zip.sha256`. Retaining these names does
not imply that upstream publishes or supports the fork. Never reuse upstream signing keys or publish an
appcast pointing to upstream releases as an xean update channel.

## Publishing checklist

Publish only after verifying the exact commit and artifacts. Create the release under
[amoreX/xean](https://github.com/amoreX/xean/releases), attach the archive and checksum, and state the
supported OS versions, architectures, signing/notarization status, and known limitations.

Download the published archive and verify its checksum, bundle version, architectures, signature, and
stapled ticket. Test opening it on a separate Mac where possible. Use a prerelease for incomplete release
validation. CI artifacts and local ad-hoc bundles are development builds, not verified public releases.

An eventual updater needs xean-owned keys, feed URLs, release URLs, and explicit runtime integration.
Document and test that separately before enabling it.
