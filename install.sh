#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/outputs/Session Todo.app"
DESTINATION="/Applications/Session Todo.app"

"$ROOT/build.sh"

# Replacing files inside an existing bundle can preserve Finder metadata and
# invalidate its signature. Stop the old copy and install a completely fresh one.
killall SessionTodo 2>/dev/null || true
rm -rf "$DESTINATION"
ditto --noextattr "$APP" "$DESTINATION"
xattr -cr "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
open "$DESTINATION"

echo "Installed Session Todo in /Applications."
