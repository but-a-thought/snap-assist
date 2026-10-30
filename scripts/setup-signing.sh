#!/bin/bash
# Crea (una sola volta) un'identità di firma locale per Snap Assist.
#
# Serve a evitare che ogni ricompilazione faccia perdere i permessi di
# Accessibilità e Registrazione schermo: la firma ad-hoc cambia a ogni build,
# un certificato locale no.
set -euo pipefail

DEST="$HOME/Library/Application Support/SnapAssist/Signing"
KEYCHAIN="$DEST/SnapAssist.keychain-db"
IDENTITY="Snap Assist Local Signing"
PASSWORD="snapassist"

if [ -f "$KEYCHAIN" ] && security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ Identità già presente: $KEYCHAIN"
    exit 0
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
    -subj "/CN=$IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null

openssl pkcs12 -export \
    -out "$TMP/identity.p12" \
    -inkey "$TMP/key.pem" \
    -in "$TMP/cert.pem" \
    -passout "pass:$PASSWORD" 2>/dev/null

rm -f "$KEYCHAIN"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null 2>&1

cp "$TMP/cert.pem" "$DEST/SnapAssist.crt"
cp "$TMP/identity.p12" "$DEST/SnapAssist.p12"
chmod 600 "$DEST"/*

echo "✓ Identità creata: $IDENTITY"
echo "  Keychain: $KEYCHAIN"
