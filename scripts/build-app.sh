#!/bin/bash
# Builds "Claude Desktop Baton.app" into build/, signed with the first Apple Development
# identity so the Keychain approval for "Claude Safe Storage" survives rebuilds.
#   scripts/build-app.sh            build only
#   scripts/build-app.sh install    also copy to /Applications and open it
# FEED_URL overrides the update feed, e.g. a local one for testing an update between two builds.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Claude Desktop Baton"
BUNDLE_ID="com.toycrane.claude-desktop-baton"
VERSION="0.6.0"
APP="build/$NAME.app"
# Sparkle update feed and the public half of the update signing key (docs/decisions/app-updates.md).
FEED_URL="${FEED_URL:-https://github.com/toy-crane/claude-desktop-baton/releases/latest/download/appcast.xml}"
SPARKLE_PUBLIC_KEY="9hYgmXx207oDz4nG8vYoai94ITdBOv48xMYruWjz+RQ="

swift build -c release --product ClaudeDesktopBaton
BIN="$(swift build -c release --show-bin-path)/ClaudeDesktopBaton"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/ClaudeDesktopBaton"
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
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
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# SIGN_IDENTITY overrides the identity, e.g. a "Developer ID Application" one for release builds.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
sign() {
  if [[ "$IDENTITY" == Developer\ ID* ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
  elif [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$@"
  else
    codesign --force --sign - "$@"
  fi
}
[ -n "$IDENTITY" ] || echo "No Apple Development identity found; signing ad hoc (macOS will ask for Keychain access after each rebuild)." >&2
# Sparkle's helpers first, inside out, as Sparkle documents for apps that sign outside Xcode.
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$FW/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/XPCServices/Downloader.xpc"
sign "$FW/Autoupdate"
sign "$FW/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
  pkill -x ClaudeDesktopBaton 2>/dev/null || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed /Applications/$NAME.app"
fi
