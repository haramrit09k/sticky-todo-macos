#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"

"$ROOT/build.sh"
ditto "$ROOT/outputs/Session Todo.app" "/Applications/Session Todo.app"
open "/Applications/Session Todo.app"

echo "Installed Session Todo in /Applications."
