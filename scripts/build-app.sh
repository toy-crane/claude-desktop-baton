#!/bin/bash
# Builds "Claude Desktop Baton.app" into build/, signed with the first Apple Development
# identity so the Keychain approval for "Claude Safe Storage" survives rebuilds.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh install    also copy to /Applications and open it
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Claude Desktop Baton"
BUNDLE_ID="com.toycrane.claude-desktop-baton"
VERSION="0.2.0"
APP="build/$NAME.app"

swift build -c release --product ClaudeDesktopBaton
BIN="$(swift build -c release --show-bin-path)/ClaudeDesktopBaton"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeDesktopBaton"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN" --iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>ClaudeDesktopBaton</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Unofficial. Not affiliated with or endorsed by Anthropic.</string>
</dict>
</plist>
PLIST

# SIGN_IDENTITY overrides the identity, e.g. a "Developer ID Application" one for release builds.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
elif [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "No Apple Development identity found; signing ad hoc (macOS will ask for Keychain access after each rebuild)." >&2
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x ClaudeDesktopBaton 2>/dev/null || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed /Applications/$NAME.app"
fi
