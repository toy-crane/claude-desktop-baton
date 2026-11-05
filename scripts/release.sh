#!/bin/bash
# Builds a Developer ID–signed, notarized and stapled app, zipped for a GitHub Release.
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
shasum -a 256 "$ZIP"
echo "Release archive: $ZIP"
