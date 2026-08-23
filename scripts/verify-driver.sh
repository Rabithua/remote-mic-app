#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DRIVER="${1:-$ROOT/dist/MiRemoteV2ch.driver}"
PLIST="$DRIVER/Contents/Info.plist"
BINARY="$DRIVER/Contents/MacOS/MiRemoteV2ch"

if [[ "$#" -gt 1 ]]; then
  print -u2 "usage: $0 [MiRemoteV2ch.driver]"
  exit 64
fi
test -d "$DRIVER"
test -f "$PLIST"
test -x "$BINARY"
plutil -lint "$PLIST" >/dev/null
test "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = "com.hd838a.MiRemoteV2ch"
test "$(plutil -extract CFBundleName raw -o - "$PLIST")" = "MiRemoteV2ch"
test "$(lipo -archs "$BINARY")" = "arm64"
xcrun vtool -show-build "$BINARY" | grep -Fq "minos 14.0"
codesign --verify --deep --strict "$DRIVER"
CODESIGN_DETAILS="$(codesign -d -r- "$DRIVER" 2>&1)"
print -r -- "$CODESIGN_DETAILS" | grep -Fq 'identifier "com.hd838a.MiRemoteV2ch"'
strings "$BINARY" | grep -Fxq 'MiRemoteV %ich'
strings "$BINARY" | grep -Fxq 'MiRemoteV%ich_UID'
print "DRIVER VERIFY PASS: $DRIVER"
