#!/bin/bash
# Compila Snap Assist e crea un bundle .app autonomo.
#
#   ./scripts/build-app.sh              # build release in dist/
#   ./scripts/build-app.sh debug        # build debug
#   ./scripts/build-app.sh release install   # copia anche in ~/Applications
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-release}"
INSTALL="${2:-}"

if [ "$CONFIG" = "install" ]; then
    CONFIG="release"
    INSTALL="install"
fi

echo "▸ Build ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/SnapAssist"
APP="$ROOT/dist/SnapAssist.app"

echo "▸ Creo il bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SnapAssist"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Localizzazioni (italiano/inglese, la lingua la sceglie macOS).
for lproj in "$ROOT"/Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$APP/Contents/Resources/"
    fi
done

# Firma: se esiste l'identità locale creata da scripts/setup-signing.sh la
# usiamo (stabile tra le build, i permessi TCC restano validi); altrimenti
# firma ad-hoc, che cambia a ogni compilazione.
SIGN_IDENTITY="Snap Assist Local Signing"
SIGN_KEYCHAIN="$HOME/Library/Application Support/SnapAssist/Signing/SnapAssist.keychain-db"

signed=0
if [ -f "$SIGN_KEYCHAIN" ]; then
    security unlock-keychain -p snapassist "$SIGN_KEYCHAIN" >/dev/null 2>&1 || true
    if codesign --force --sign "$SIGN_IDENTITY" --keychain "$SIGN_KEYCHAIN" \
        --identifier com.frank.snapassist "$APP" >/dev/null 2>&1; then
        signed=1
        echo "  Firma: identità locale stabile"
    fi
fi

if [ "$signed" = "0" ]; then
    codesign --force --sign - --identifier com.frank.snapassist "$APP" >/dev/null 2>&1 || true
    echo "  Firma: ad-hoc (esegui scripts/setup-signing.sh per una firma stabile)"
fi
touch "$APP"

echo "✓ Creato: $APP"

if [ "$INSTALL" = "install" ]; then
    DEST="$HOME/Applications/SnapAssist.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "✓ Installato: $DEST"
    echo "  Apri con: open \"$DEST\""
else
    echo "  Apri con: open \"$APP\""
fi
