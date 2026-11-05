#!/bin/bash
# Builds a Developer ID–signed, notarized and stapled app, as a zip and a DMG for a GitHub Release.
#   scripts/release.sh
# Needs a "Developer ID Application" identity and a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials claude-desktop-baton --team-id <TEAM_ID>
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Claude Desktop Baton"
PROFILE="${NOTARY_PROFILE:-claude-desktop-baton}"
VERSION="$(awk -F'"' '/^VERSION=/ {print $2}' scripts/build-app.sh)"
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application identity found." >&2; exit 1; }

SIGN_IDENTITY="$IDENTITY" scripts/build-app.sh
APP="build/$NAME.app"
ZIP="build/ClaudeDesktopBaton-$VERSION.zip"

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# DMG: the stapled app beside an Applications shortcut, itself signed, notarized and stapled.
DMG="build/ClaudeDesktopBaton-$VERSION.dmg"
STAGE="build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
rm -rf "$STAGE"

shasum -a 256 "$ZIP" "$DMG"
echo "Release archives: $ZIP $DMG"
