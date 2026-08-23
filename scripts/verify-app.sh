#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="${1:-$ROOT/dist/SayAll.app}"
PLIST="$APP/Contents/Info.plist"
BINARY="$APP/Contents/MacOS/RemoteMic"

if [[ "$#" -gt 1 ]]; then
  print -u2 "usage: $0 [SayAll.app]"
  exit 64
fi
test -d "$APP"
test -f "$PLIST"
test -x "$BINARY"
plutil -lint "$PLIST" >/dev/null
test "$(plutil -extract CFBundleIdentifier raw -o - "$PLIST")" = "com.hd838a.RemoteMic"
test "$(plutil -extract CFBundleExecutable raw -o - "$PLIST")" = "RemoteMic"
test "$(plutil -extract CFBundleDisplayName raw -o - "$PLIST")" = "SayAll"
test "$(plutil -extract LSMinimumSystemVersion raw -o - "$PLIST")" = "14.0"
test "$(plutil -extract LSUIElement raw -o - "$PLIST")" = "true"
if plutil -p "$PLIST" | rg -q '"SU|NSBonjourServices|NSLocalNetworkUsageDescription'; then
  print -u2 "removed update or mobile networking metadata is still present"
  exit 1
fi
test "$(lipo -archs "$BINARY")" = "arm64"
xcrun vtool -show-build "$BINARY" | rg -Fq "minos 14.0"
codesign --verify --deep --strict "$APP"
CODESIGN_DETAILS="$(codesign -d -r- "$APP" 2>&1)"
print -r -- "$CODESIGN_DETAILS" | rg -Fq 'identifier "com.hd838a.RemoteMic"'
if otool -L "$BINARY" | rg -qi 'Sparkle|SayAllMacRemote'; then
  print -u2 "removed framework linkage is still present"
  exit 1
fi
test ! -e "$APP/Contents/Helpers"
test ! -e "$APP/Contents/Frameworks"
for localization in en.lproj zh-Hans.lproj; do
  plutil -lint "$APP/Contents/Resources/$localization/InfoPlist.strings" >/dev/null
  plutil -lint "$APP/Contents/Resources/$localization/Localizable.strings" >/dev/null
done
print "APP VERIFY PASS: $APP"
