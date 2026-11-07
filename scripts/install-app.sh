#!/bin/bash
set -euo pipefail
[[ $# == 2 ]] || { echo "Expected source app and Team ID." >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$1"
TEAM="$2"
DEST=/Applications/SnapAssist.app
/bin/bash "$ROOT/scripts/verify-app.sh" "$SOURCE" "$TEAM"
[[ "$SOURCE" != "$DEST" ]] || { echo "Source must be a staged build." >&2; exit 2; }
STAGING="$(/usr/bin/mktemp -d /Applications/.SnapAssist-install.XXXXXX)"
BACKUP=""
REPLACED=0
cleanup() {
    local result=$?
    if [[ $result != 0 && "$REPLACED" == 1 ]]; then
        /bin/mv "$DEST" "$STAGING/failed.app" || true
    fi
    if [[ $result != 0 && -n "$BACKUP" && -e "$BACKUP" ]]; then
        /bin/mv "$BACKUP" "$DEST" || echo "Restore backup manually: $BACKUP" >&2
    fi
    /bin/rm -rf "$STAGING"
    exit "$result"
}
trap cleanup EXIT
/usr/bin/ditto "$SOURCE" "$STAGING/SnapAssist.app"
/bin/bash "$ROOT/scripts/verify-app.sh" "$STAGING/SnapAssist.app" "$TEAM"
"$STAGING/SnapAssist.app/Contents/MacOS/SnapAssist" --prepare-install
if [[ -e "$DEST" || -L "$DEST" ]]; then
    [[ -d "$DEST" && ! -L "$DEST" ]] || { echo "Unexpected installation target." >&2; exit 1; }
    BACKUP="${STAGING}.previous.app"
    /bin/mv "$DEST" "$BACKUP"
fi
/bin/mv "$STAGING/SnapAssist.app" "$DEST"
REPLACED=1
/bin/bash "$ROOT/scripts/verify-app.sh" "$DEST" "$TEAM"
echo "Installed verified arm64 app: $DEST"
[[ -z "$BACKUP" ]] || echo "Previous app retained: $BACKUP"
