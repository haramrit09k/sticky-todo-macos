#!/bin/zsh
set -euo pipefail

# Wrap the built app in a drag-to-install disk image:
#   ./make-dmg.sh Session-Todo-macOS.dmg
ROOT="${0:A:h}"
APP="$ROOT/outputs/Session Todo.app"
DMG="${1:?usage: make-dmg.sh <output.dmg>}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/session-todo-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto --noextattr "$APP" "$STAGING_DIR/Session Todo.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "Session Todo" -srcfolder "$STAGING_DIR" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
