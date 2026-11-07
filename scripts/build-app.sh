#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-release}"
ACTION="${2:-}"
if [[ "$CONFIG" == install ]]; then CONFIG=release; ACTION=install; fi
[[ "$CONFIG" == debug || "$CONFIG" == release ]] || { echo "Expected debug or release." >&2; exit 2; }
[[ -z "$ACTION" || "$ACTION" == install ]] || { echo "Expected optional install action." >&2; exit 2; }
[[ $# -le 2 ]] || { echo "Too many arguments." >&2; exit 2; }
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity or its fingerprint.}"
: "${EXPECTED_TEAM_ID:?Set EXPECTED_TEAM_ID to your Developer ID Team ID.}"
[[ "$SIGN_IDENTITY" != - && "$EXPECTED_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Invalid signing inputs." >&2; exit 2; }
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

/usr/bin/xcrun swift build --configuration "$CONFIG" --arch arm64
BIN_DIR="$(/usr/bin/xcrun swift build --configuration "$CONFIG" --arch arm64 --show-bin-path)"
/bin/mkdir -p "$ROOT/dist/$CONFIG"
STAGING="$(/usr/bin/mktemp -d "$ROOT/dist/$CONFIG/.staging.XXXXXX")"
trap '/bin/rm -rf "$STAGING"' EXIT
APP="$STAGING/SnapAssist.app"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$BIN_DIR/SnapAssist" "$APP/Contents/MacOS/SnapAssist"
/bin/cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
for localization in "$ROOT"/Resources/*.lproj; do
    [[ ! -d "$localization" ]] || /bin/cp -R "$localization" "$APP/Contents/Resources/"
done
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
    --identifier com.frank.snapassist "$APP"
/bin/bash "$ROOT/scripts/verify-app.sh" "$APP" "$EXPECTED_TEAM_ID"
DEST="$ROOT/dist/$CONFIG/SnapAssist.app"
PREVIOUS="$STAGING/previous.app"
if [[ -e "$DEST" ]]; then /bin/mv "$DEST" "$PREVIOUS"; fi
if ! /bin/mv "$APP" "$DEST"; then
    [[ ! -e "$PREVIOUS" ]] || /bin/mv "$PREVIOUS" "$DEST"
    exit 1
fi
echo "Verified $CONFIG arm64 Developer ID build: $DEST"
if [[ "$ACTION" == install ]]; then
    /bin/bash "$ROOT/scripts/install-app.sh" "$DEST" "$EXPECTED_TEAM_ID"
fi
