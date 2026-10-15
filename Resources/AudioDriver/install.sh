#!/bin/zsh -f
# Runtime installer: only macOS system tools, no Xcode, network, or repository required.
set -euo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH
umask 022

RESOURCE_DIR="${0:A:h}"
SOURCE="$RESOURCE_DIR/MiRemoteV2ch.driver"
DESTINATION="/Library/Audio/Plug-Ins/HAL/MiRemoteV2ch.driver"
IDENTIFIER="com.hd838a.MiRemoteV2ch"
STAGE=""
BACKUP=""
PLACED=0
COMMITTED=0
LOCKED=0
LOCK="/Library/Audio/Plug-Ins/HAL/.miremote-driver-install.lock"

bundle_identifier() {
  plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null
}

verify_bundle() {
  local bundle="$1"
  local binary="$bundle/Contents/MacOS/MiRemoteV2ch"
  [[ -d "$bundle" && ! -L "$bundle" && -x "$binary" ]] || return 1
  [[ -z "$(find "$bundle" -type l -print -quit)" ]] || return 1
  [[ "$(bundle_identifier "$bundle")" == "$IDENTIFIER" ]] || return 1
  [[ "$(plutil -extract CFBundleName raw -o - "$bundle/Contents/Info.plist")" == MiRemoteV2ch ]] || return 1
  [[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$bundle/Contents/Info.plist")" == 14.0 ]] || return 1
  file -b "$binary" | grep -Eq '^Mach-O 64-bit bundle arm64$' || return 1
  codesign --verify --deep --strict -R '=identifier "com.hd838a.MiRemoteV2ch"' "$bundle" >/dev/null 2>&1
}

check_destination() {
  local directory
  for directory in /Library /Library/Audio /Library/Audio/Plug-Ins /Library/Audio/Plug-Ins/HAL; do
    [[ ! -L "$directory" ]] || return 12
  done
  [[ ! -L "$DESTINATION" ]] || return 12
  [[ -e "$DESTINATION" ]] || return 10
  [[ "$(bundle_identifier "$DESTINATION" || true)" == "$IDENTIFIER" ]] || return 12
  verify_bundle "$DESTINATION" || return 11
}

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  if [[ "$COMMITTED" == 0 ]]; then
    if [[ "$PLACED" == 1 ]]; then
      rm -rf -- "$DESTINATION"
    fi
    if [[ -n "$BACKUP" && -d "$BACKUP" && ! -e "$DESTINATION" ]]; then
      mv -- "$BACKUP" "$DESTINATION"
    fi
  fi
  if [[ -n "$STAGE" && "$STAGE" == /Library/Audio/Plug-Ins/HAL/.miremote-app-install.* ]]; then
    rm -rf -- "$STAGE"
  fi
  if [[ "$LOCKED" == 1 ]]; then rmdir -- "$LOCK"; fi
  exit "$result"
}

case "${1:-}" in
  --check)
    [[ "$#" == 1 ]] || exit 64
    check_destination
    exit $?
    ;;
  --verify-bundle)
    [[ "$#" == 2 ]] || exit 64
    verify_bundle "$2"
    exit $?
    ;;
  --install)
    [[ "$#" == 1 && "$EUID" == 0 ]] || exit 64
    ;;
  *) exit 64 ;;
esac

check_result=0
check_destination || check_result=$?
if [[ "$check_result" == 0 ]]; then
  print 'DRIVER_KEPT'
  exit 0
fi
if [[ "$check_result" == 12 ]]; then
  print -u2 'Refusing a symbolic-link destination or mismatched Bundle ID.'
  exit 12
fi
verify_bundle "$SOURCE"
mkdir -p /Library/Audio/Plug-Ins/HAL
# Serialize app instances and recheck after acquiring the lock.
mkdir -- "$LOCK"
LOCKED=1
trap cleanup EXIT
trap 'exit 130' INT TERM
check_result=0
check_destination || check_result=$?
[[ "$check_result" != 12 ]] || exit 12
if [[ "$check_result" == 0 ]]; then
  COMMITTED=1
  print 'DRIVER_KEPT'
  exit 0
fi

STAGE="$(mktemp -d /Library/Audio/Plug-Ins/HAL/.miremote-app-install.XXXXXX)"
ditto --norsrc --noextattr --noqtn --noacl "$SOURCE" "$STAGE/MiRemoteV2ch.driver"
verify_bundle "$STAGE/MiRemoteV2ch.driver"
chown -R root:wheel "$STAGE"
find "$STAGE" -type d -exec chmod 755 {} +
find "$STAGE" -type f -exec chmod 644 {} +
chmod 755 "$STAGE/MiRemoteV2ch.driver/Contents/MacOS/MiRemoteV2ch"
# Verify the root-owned copy, not just the mutable source in the user's app.
verify_bundle "$STAGE/MiRemoteV2ch.driver"
if [[ -e "$DESTINATION" ]]; then
  BACKUP="${DESTINATION}.backup-$(date +%Y%m%d-%H%M%S)-$$"
  [[ ! -e "$BACKUP" && ! -L "$BACKUP" ]] || exit 1
  mv -- "$DESTINATION" "$BACKUP"
fi
mv -- "$STAGE/MiRemoteV2ch.driver" "$DESTINATION"
PLACED=1
verify_bundle "$DESTINATION"
COMMITTED=1
# Core Audio discovers new HAL drivers when its daemon restarts.
killall coreaudiod 2>/dev/null || true
print 'DRIVER_INSTALLED'
