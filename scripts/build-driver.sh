#!/bin/zsh
set -euo pipefail
umask 022

ROOT="${0:A:h:h}"
BLACKHOLE_COMMIT="e2b22aaaba4e507a097131704bf96dabc004d9cf"
WORK_ROOT="${REMOTE_MIC_DRIVER_WORK_DIR:-$ROOT/.build/driver}"
SOURCE_ROOT="$WORK_ROOT/BlackHole"
OUTPUT="${REMOTE_MIC_DRIVER_OUTPUT:-$ROOT/dist/MiRemoteV2ch.driver}"
PATCH="$ROOT/third_party/blackhole/blackhole-device-usb.patch"
DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS kDriver_Name=\"MiRemoteV\" kPlugIn_BundleID=\"com.hd838a.MiRemoteV2ch\" kNumber_Of_Channels=2'

if [[ "$#" -ne 0 ]]; then
  print -u2 "usage: $0"
  exit 64
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  print -u2 "MiRemoteV2ch builds require Apple Silicon"
  exit 1
fi
for command in git xcodebuild; do
  command -v "$command" >/dev/null || {
    print -u2 "missing required command: $command"
    exit 1
  }
done
case "$WORK_ROOT" in
  "$ROOT/.build/driver"|/private/tmp/remote-mic-driver-*) ;;
  *) print -u2 "refusing unexpected driver work path: $WORK_ROOT"; exit 1 ;;
esac
case "$OUTPUT" in
  "$ROOT/dist/MiRemoteV2ch.driver"|/private/tmp/remote-mic-driver-output-*/MiRemoteV2ch.driver) ;;
  *) print -u2 "refusing unexpected driver output: $OUTPUT"; exit 1 ;;
esac

rm -rf -- "$WORK_ROOT" "$OUTPUT"
mkdir -p "${WORK_ROOT:h}" "${OUTPUT:h}"
git clone https://github.com/ExistentialAudio/BlackHole.git "$SOURCE_ROOT"
git -C "$SOURCE_ROOT" checkout --detach "$BLACKHOLE_COMMIT"
test "$(git -C "$SOURCE_ROOT" rev-parse HEAD)" = "$BLACKHOLE_COMMIT"
git -C "$SOURCE_ROOT" apply --check "$PATCH"
git -C "$SOURCE_ROOT" apply "$PATCH"

xcodebuild \
  -project "$SOURCE_ROOT/BlackHole.xcodeproj" \
  -target BlackHole \
  -configuration Release \
  -sdk macosx \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  CODE_SIGNING_ALLOWED=NO \
  PRODUCT_NAME=MiRemoteV2ch \
  PRODUCT_BUNDLE_IDENTIFIER=com.hd838a.MiRemoteV2ch \
  GCC_PREPROCESSOR_DEFINITIONS="$DEFINITIONS" \
  build

ditto --norsrc --noextattr --noqtn --noacl \
  "$SOURCE_ROOT/build/Release/MiRemoteV2ch.driver" "$OUTPUT"
strip -S "$OUTPUT/Contents/MacOS/MiRemoteV2ch"
codesign \
  --force \
  --deep \
  --sign - \
  --timestamp=none \
  --identifier com.hd838a.MiRemoteV2ch \
  --requirements '=designated => identifier "com.hd838a.MiRemoteV2ch"' \
  "$OUTPUT"
"$ROOT/scripts/verify-driver.sh" "$OUTPUT"
print "Built: $OUTPUT"
