#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if [[ "$#" -ne 0 ]]; then
  print -u2 "usage: $0"
  exit 64
fi

plutil -lint Resources/Info.plist Resources/*.lproj/*.strings >/dev/null
for script in scripts/*.sh(N); do
  zsh -n "$script"
done
xcrun swift format lint --strict --recursive --parallel Sources Tests Package.swift
xcrun swift test
"$ROOT/scripts/build-app.sh"
print "TEST PASS"
