#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
OUTPUT_APP="$ROOT/outputs/Session Todo.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/session-todo-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

APP="$STAGING_DIR/Session Todo.app"
CONTENTS="$APP/Contents"

# Assemble away from synced folders, which can attach Finder/File Provider
# metadata while the bundle is still being signed.
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$ROOT/.cache/clang"
CLANG_MODULE_CACHE_PATH="$ROOT/.cache/clang" \
swiftc -O \
  -framework AppKit \
  -framework Carbon \
  -framework UserNotifications \
  -framework ServiceManagement \
  "$ROOT/Sources/SessionTodo/main.swift" \
  -o "$CONTENTS/MacOS/SessionTodo"
cp "$ROOT/Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>SessionTodo</string>
  <key>CFBundleIdentifier</key><string>local.sessiontodo</string>
  <key>CFBundleName</key><string>Session Todo</string>
  <key>CFBundleDisplayName</key><string>Session Todo</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

rm -rf "$OUTPUT_APP"
mkdir -p "$ROOT/outputs"
ditto --noextattr "$APP" "$OUTPUT_APP"
xattr -cr "$OUTPUT_APP"
for attribute in com.apple.FinderInfo com.apple.ResourceFork com.apple.fileprovider.fpfs#P; do
  xattr -d "$attribute" "$OUTPUT_APP" 2>/dev/null || true
done
codesign --verify --deep --strict "$OUTPUT_APP"
echo "$OUTPUT_APP"
