#!/bin/zsh
set -euo pipefail
umask 022

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
TRIPLE="arm64-apple-macosx14.0"
OUTPUT_DIR="${REMOTE_MIC_OUTPUT_DIR:-$ROOT/dist}"
APP="$OUTPUT_DIR/SayAll.app"
SCRATCH="${REMOTE_MIC_BUILD_SCRATCH_PATH:-$ROOT/.build/app}"

if [[ "$#" -ne 0 ]]; then
  print -u2 "usage: $0"
  exit 64
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  print -u2 "SayAll local builds require Apple Silicon"
  exit 1
fi
case "$OUTPUT_DIR" in
  "$ROOT/dist"|/private/tmp/remote-mic-app-output-*) ;;
  *) print -u2 "refusing unexpected app output directory: $OUTPUT_DIR"; exit 1 ;;
esac

cd "$ROOT"
xcrun swift build \
  --scratch-path "$SCRATCH" \
  -c "$CONFIGURATION" \
  --triple "$TRIPLE"
BIN_DIR="$(xcrun swift build \
  --scratch-path "$SCRATCH" \
  -c "$CONFIGURATION" \
  --triple "$TRIPLE" \
  --show-bin-path)"
BIN="$BIN_DIR/RemoteMic"
test -x "$BIN"

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ditto --norsrc --noextattr --noqtn --noacl "$BIN" "$APP/Contents/MacOS/RemoteMic"
strip -S -x "$APP/Contents/MacOS/RemoteMic"
ditto --norsrc --noextattr --noqtn --noacl \
  "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

for resource in \
  StatusIconTemplate.png \
  StatusIconTemplate@2x.png \
  StatusIconActiveTemplate.png \
  StatusIconActiveTemplate@2x.png; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/Resources/$resource" "$APP/Contents/Resources/$resource"
done
for localization in en.lproj zh-Hans.lproj; do
  mkdir -p "$APP/Contents/Resources/$localization"
  for resource in InfoPlist.strings Localizable.strings; do
    ditto --norsrc --noextattr --noqtn --noacl \
      "$ROOT/Resources/$localization/$resource" \
      "$APP/Contents/Resources/$localization/$resource"
  done
done
for document in LICENSE.md COPYRIGHT.md THIRD_PARTY_NOTICES.md README.md README.en.md DEVELOPMENT.md TESTING.md; do
  ditto --norsrc --noextattr --noqtn --noacl \
    "$ROOT/$document" "$APP/Contents/Resources/$document"
done

codesign \
  --force \
  --deep \
  --sign - \
  --timestamp=none \
  --identifier com.hd838a.RemoteMic \
  --requirements '=designated => identifier "com.hd838a.RemoteMic"' \
  "$APP"
"$ROOT/scripts/verify-app.sh" "$APP"
print "Built: $APP"
