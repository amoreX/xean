#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
APP_BUNDLE="$ROOT_DIR/dist/BlitzClean.app"
REBUILD=false

if (( $# > 1 )); then
    print -u2 "Usage: $0 [--build|--help]"
    exit 2
fi
case "${1:-}" in
    --build) REBUILD=true ;;
    --help|-h)
        print "Usage: $0 [--build]"
        print "Open xean, building it on first run. Use --build to rebuild after source changes."
        exit 0
        ;;
    "") ;;
    *) print -u2 "Usage: $0 [--build|--help]"; exit 2 ;;
esac

if [[ "$(uname -s)" != Darwin ]]; then
    print -u2 "xean requires macOS."
    exit 1
fi

if [[ "$REBUILD" == true || ! -x "$APP_BUNDLE/Contents/MacOS/BlitzClean" ]]; then
    if pgrep -x BlitzClean >/dev/null; then
        print -u2 "Quit xean, then run $0 --build to launch the updated app."
        exit 1
    fi
    BLITZCLEAN_SIGNING_IDENTITY="${BLITZCLEAN_SIGNING_IDENTITY:--}" \
        "$ROOT_DIR/scripts/build-app.sh"
fi

open "$APP_BUNDLE" --args --cleaner
