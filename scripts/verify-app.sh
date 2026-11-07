#!/bin/bash
set -euo pipefail
[[ $# == 2 ]] || { echo "Expected app path and Team ID." >&2; exit 2; }
APP="$1"
TEAM="$2"
[[ "$TEAM" =~ ^[A-Z0-9]{10}$ && -d "$APP" ]] || { echo "Invalid app or Team ID." >&2; exit 2; }
[[ ! -L "$APP" ]] || { echo "App must not be a symlink." >&2; exit 1; }
PLIST="$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$PLIST"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" == com.frank.snapassist ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")" == SnapAssist ]]
[[ -x "$APP/Contents/MacOS/SnapAssist" ]]
[[ -z "$(/usr/bin/find "$APP" -type l -print -quit)" ]] || { echo "Unexpected bundle symlink." >&2; exit 1; }
[[ "$(/usr/bin/lipo -archs "$APP/Contents/MacOS/SnapAssist")" == arm64 ]]
while IFS= read -r -d '' candidate; do
    if [[ "$(/usr/bin/file -b "$candidate")" == *Mach-O* ]]; then
        [[ "$(/usr/bin/lipo -archs "$candidate")" == arm64 ]] || { echo "Non-arm64 bundle executable." >&2; exit 1; }
    fi
done < <(/usr/bin/find "$APP" -type f -print0)
REQUIREMENT="anchor apple generic and identifier \"com.frank.snapassist\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"$TEAM\""
/usr/bin/codesign --verify --strict --verbose=2 -R "=$REQUIREMENT" "$APP"
DETAILS="$(/usr/bin/codesign --display --verbose=4 "$APP" 2>&1)"
[[ "$DETAILS" == *"TeamIdentifier=$TEAM"* && "$DETAILS" == *"(runtime)"* && "$DETAILS" == *"Timestamp="* ]] || {
    echo "Missing expected team, hardened runtime, or secure timestamp." >&2; exit 1;
}
echo "Signature, Developer ID requirement, runtime, timestamp, bundle ID, and arm64 verified."
