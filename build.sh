#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP="$ROOT/outputs/Session Todo.app"
CONTENTS="$APP/Contents"

# Always assemble a fresh bundle. Reusing an app that Finder has touched can
# leave metadata behind that ad-hoc signing correctly refuses to accept.
rm -rf "$APP"
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
echo "$APP"
