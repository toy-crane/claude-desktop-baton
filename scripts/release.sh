#!/bin/bash
# Builds a Developer ID–signed, notarized and stapled app, as a zip and a DMG for a GitHub Release,
# plus the update feed (appcast.xml) that installed copies read from the latest release.
#   scripts/release.sh
# Needs a "Developer ID Application" identity and a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials claude-desktop-baton --team-id <TEAM_ID>
# and the Sparkle update signing key in the login Keychain (backed up in 1Password; restore it with
# Sparkle's `generate_keys -f <file>`). Release notes go in release-notes/<version>.md first: they are
# shown in the update window and used as the GitHub release's notes.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Claude Desktop Baton"
PROFILE="${NOTARY_PROFILE:-claude-desktop-baton}"
VERSION="$(awk -F'"' '/^VERSION=/ {print $2}' scripts/build-app.sh)"
NOTES="${RELEASE_NOTES:-release-notes/$VERSION.md}"
[ -s "$NOTES" ] || { echo "Write the release notes for $VERSION to $NOTES first." >&2; exit 1; }
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

# Update feed: one item for the zip, its release notes embedded, signed with the Sparkle key.
FEED_DIR="build/appcast"
rm -rf "$FEED_DIR" build/appcast.xml
mkdir -p "$FEED_DIR"
cp "$ZIP" "$FEED_DIR/"
cp "$NOTES" "$FEED_DIR/ClaudeDesktopBaton-$VERSION.md"
GENERATE_APPCAST="$(find .build/artifacts -path '*Sparkle/bin/generate_appcast' -type f | head -1)"
[ -x "$GENERATE_APPCAST" ] || { echo "Sparkle's generate_appcast was not found under .build/artifacts." >&2; exit 1; }
"$GENERATE_APPCAST" --embed-release-notes \
  --download-url-prefix "https://github.com/toy-crane/claude-desktop-baton/releases/download/v$VERSION/" \
  -o build/appcast.xml "$FEED_DIR"
grep -q "sparkle:edSignature" build/appcast.xml || { echo "appcast.xml has no EdDSA signature." >&2; exit 1; }
rm -rf "$FEED_DIR"

shasum -a 256 "$ZIP" "$DMG"
echo "Release archives: $ZIP $DMG build/appcast.xml"
echo "Publish all three in one release, so the latest release always carries the feed:"
echo "  gh release create v$VERSION \"$ZIP\" \"$DMG\" build/appcast.xml --title \"Claude Desktop Baton $VERSION\" --notes-file \"$NOTES\""
