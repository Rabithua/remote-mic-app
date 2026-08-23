#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
if [[ "$#" -ne 0 ]]; then
  print -u2 "usage: $0"
  exit 64
fi
"$ROOT/scripts/build-app.sh"
open -n "$ROOT/dist/SayAll.app"
