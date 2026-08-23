#!/bin/zsh
set -euo pipefail
umask 022

ROOT="${0:A:h:h}"
BUILT_APP="$ROOT/dist/SayAll.app"
BUILT_DRIVER="$ROOT/dist/MiRemoteV2ch.driver"
APP_DESTINATION="/Applications/SayAll.app"
DRIVER_DESTINATION="/Library/Audio/Plug-Ins/HAL/MiRemoteV2ch.driver"
APP_BUNDLE_ID="com.hd838a.RemoteMic"
DRIVER_BUNDLE_ID="com.hd838a.MiRemoteV2ch"
APP_STAGE_ROOT=""
DRIVER_STAGE_ROOT=""
DRIVER_BACKUP=""

bundle_identifier() {
  local bundle="$1"
  local plist="$bundle/Contents/Info.plist"
  [[ -f "$plist" ]] || return 1
  plutil -extract CFBundleIdentifier raw -o - "$plist" 2>/dev/null
}

validate_destinations() {
  if [[ -L "$APP_DESTINATION" || -L "$DRIVER_DESTINATION" ]]; then
    print -u2 "refusing to replace a symbolic-link destination"
    return 1
  fi
  if [[ -e "$APP_DESTINATION" && \
        "$(bundle_identifier "$APP_DESTINATION" || true)" != "$APP_BUNDLE_ID" ]]; then
    print -u2 "refusing to overwrite $APP_DESTINATION because its Bundle ID does not match"
    return 1
  fi
  if [[ -e "$DRIVER_DESTINATION" && \
        "$(bundle_identifier "$DRIVER_DESTINATION" || true)" != "$DRIVER_BUNDLE_ID" ]]; then
    print -u2 "refusing to overwrite $DRIVER_DESTINATION because its Bundle ID does not match"
    return 1
  fi
}

cleanup_privileged_stages() {
  if [[ -n "$APP_STAGE_ROOT" && "$APP_STAGE_ROOT" == /Applications/.sayall-install.* ]]; then
    rm -rf -- "$APP_STAGE_ROOT"
  fi
  if [[ -n "$DRIVER_STAGE_ROOT" && \
        "$DRIVER_STAGE_ROOT" == /Library/Audio/Plug-Ins/HAL/.miremote-install.* ]]; then
    rm -rf -- "$DRIVER_STAGE_ROOT"
  fi
}

privileged_install() {
  local driver_needs_install="$1"
  if [[ "$EUID" -ne 0 ]]; then
    print -u2 "privileged install phase must run as root"
    exit 1
  fi
  trap cleanup_privileged_stages EXIT INT TERM
  validate_destinations
  "$ROOT/scripts/verify-app.sh" "$BUILT_APP"

  if [[ "$driver_needs_install" == "1" ]]; then
    "$ROOT/scripts/verify-driver.sh" "$BUILT_DRIVER"
    DRIVER_STAGE_ROOT="$(mktemp -d \
      /Library/Audio/Plug-Ins/HAL/.miremote-install.XXXXXX)"
    ditto --norsrc --noextattr --noqtn --noacl \
      "$BUILT_DRIVER" "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver"
    chown -R root:wheel "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver"
    find "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver" -type d -exec chmod 755 {} +
    find "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver" -type f -exec chmod 644 {} +
    chmod 755 "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver/Contents/MacOS/MiRemoteV2ch"
    "$ROOT/scripts/verify-driver.sh" "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver"

    if [[ -e "$DRIVER_DESTINATION" ]]; then
      local timestamp="$(date +%Y%m%d-%H%M%S)"
      DRIVER_BACKUP="${DRIVER_DESTINATION}.backup-$timestamp"
      if [[ -e "$DRIVER_BACKUP" || -L "$DRIVER_BACKUP" ]]; then
        print -u2 "refusing to replace existing backup: $DRIVER_BACKUP"
        exit 1
      fi
      mv "$DRIVER_DESTINATION" "$DRIVER_BACKUP"
      print "Backed up driver: $DRIVER_BACKUP"
    fi
    if ! mv "$DRIVER_STAGE_ROOT/MiRemoteV2ch.driver" "$DRIVER_DESTINATION" || \
       ! "$ROOT/scripts/verify-driver.sh" "$DRIVER_DESTINATION"; then
      rm -rf -- "$DRIVER_DESTINATION"
      if [[ -n "$DRIVER_BACKUP" && -e "$DRIVER_BACKUP" ]]; then
        mv "$DRIVER_BACKUP" "$DRIVER_DESTINATION"
      fi
      print -u2 "driver replacement failed; previous installation was restored"
      exit 1
    fi
    killall coreaudiod 2>/dev/null || true
  else
    "$ROOT/scripts/verify-driver.sh" "$DRIVER_DESTINATION"
    print "Keeping healthy driver: $DRIVER_DESTINATION"
  fi

  APP_STAGE_ROOT="$(mktemp -d /Applications/.sayall-install.XXXXXX)"
  ditto --norsrc --noextattr --noqtn --noacl \
    "$BUILT_APP" "$APP_STAGE_ROOT/SayAll.app"
  chown -R root:wheel "$APP_STAGE_ROOT/SayAll.app"
  "$ROOT/scripts/verify-app.sh" "$APP_STAGE_ROOT/SayAll.app"

  pkill -x RemoteMic 2>/dev/null || true
  if [[ -e "$APP_DESTINATION" ]]; then
    mv "$APP_DESTINATION" "$APP_STAGE_ROOT/Previous.app"
  fi
  if ! mv "$APP_STAGE_ROOT/SayAll.app" "$APP_DESTINATION" || \
     ! "$ROOT/scripts/verify-app.sh" "$APP_DESTINATION"; then
    rm -rf -- "$APP_DESTINATION"
    if [[ -e "$APP_STAGE_ROOT/Previous.app" ]]; then
      mv "$APP_STAGE_ROOT/Previous.app" "$APP_DESTINATION"
    fi
    print -u2 "app replacement failed; previous installation was restored"
    exit 1
  fi
  if [[ -e "$APP_STAGE_ROOT/Previous.app" ]]; then
    rm -rf -- "$APP_STAGE_ROOT/Previous.app"
  fi
}

if [[ "${1:-}" == "--privileged-install" ]]; then
  if [[ "$#" -ne 2 || ("${2:-}" != "0" && "${2:-}" != "1") ]]; then
    print -u2 "invalid privileged install invocation"
    exit 64
  fi
  privileged_install "$2"
  exit 0
fi

if [[ "$#" -ne 0 ]]; then
  print -u2 "usage: $0"
  exit 64
fi
if [[ "$(uname -m)" != "arm64" ]]; then
  print -u2 "SayAll requires Apple Silicon"
  exit 1
fi

validate_destinations
"$ROOT/scripts/build-app.sh"
"$ROOT/scripts/verify-app.sh" "$BUILT_APP"

driver_needs_install=0
if [[ ! -d "$DRIVER_DESTINATION" ]]; then
  driver_needs_install=1
elif ! "$ROOT/scripts/verify-driver.sh" "$DRIVER_DESTINATION"; then
  driver_needs_install=1
fi
if [[ "$driver_needs_install" == "1" ]]; then
  "$ROOT/scripts/build-driver.sh"
  "$ROOT/scripts/verify-driver.sh" "$BUILT_DRIVER"
fi

osascript - "$ROOT" "$driver_needs_install" <<'APPLESCRIPT'
on run arguments
  set repositoryRoot to item 1 of arguments
  set driverFlag to item 2 of arguments
  set installerPath to repositoryRoot & "/scripts/install-local.sh"
  set installCommand to quoted form of installerPath & " --privileged-install " & quoted form of driverFlag
  do shell script installCommand with administrator privileges
end run
APPLESCRIPT

open "$APP_DESTINATION"
print "Installed and launched: $APP_DESTINATION"
