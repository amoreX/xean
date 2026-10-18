#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
    printf 'Usage: %s [port]\n' "$0" >&2
    exit 2
fi

case "${1:-4173}" in
    --help|-h)
        printf 'Usage: %s [port]\nStart the xean website on localhost (default port: 4173).\n' "$0"
        exit 0
        ;;
    ''|*[!0-9]*)
        printf 'Port must be a number between 1 and 65535.\n' >&2
        exit 2
        ;;
esac

SITE_PORT="${1:-4173}"
if [ "$SITE_PORT" -lt 1 ] || [ "$SITE_PORT" -gt 65535 ]; then
    printf 'Port must be a number between 1 and 65535.\n' >&2
    exit 2
fi

SITE_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if ! command -v python3 >/dev/null 2>&1; then
    printf 'Python 3 is required to run the local website.\n' >&2
    exit 1
fi

exec python3 -u -m http.server "$SITE_PORT" --bind 127.0.0.1 --directory "$SITE_ROOT/website/dist"
