# App updates

## Decisions

- The app finds and installs its own updates with Sparkle 2. Sparkle is pinned
  to an exact version.
- The update feed (appcast) is published as an asset of every GitHub release and
  read from the repository's latest-release download URL, so no other server is
  needed.
- Every update archive is signed with the project's Sparkle EdDSA key, in
  addition to the Developer ID signature and notarization the release already
  has. The app rejects an archive whose EdDSA signature does not match.
- Every update keeps the bundle identifier `com.toycrane.claude-desktop-baton`
  and is signed by the same Developer ID team, so the Keychain approval for
  "Claude Safe Storage", the login item, and the `~/.local/bin` link carry over.
- An update never quits or relaunches the app while a switch is running or a
  switch alert is open; installation waits until it is over
  ([agent-cli](agent-cli.md): the running menu bar app is the one place that
  finishes switches).

## Boundaries

- The update check contacts only the feed URL and the archive it names; Sparkle's
  system-profile reporting stays off.
- This covers the menu bar app itself. Claude.app is never updated or modified
  by this app.

## Why

The app is distributed outside the Mac App Store and reads Claude's data and
Keychain item, so it cannot be sandboxed and needs a self-updater. Replacing a
running bundle, verifying what was downloaded, and relaunching are the
error-prone parts; Sparkle does them and is what most outside-the-store Mac apps
use. Hosting the feed on GitHub Releases keeps the existing release flow as the
only place a version is published. Restarting mid-switch would leave Claude
closed or signed in to the wrong account, which is why installs wait.

## Reconsider when

- The app moves to the Mac App Store or a sandbox.
- Releases stop being published on GitHub, or a release can no longer carry the
  feed asset.
- Sparkle stops shipping releases that support the app's minimum macOS.

## Still-rejected alternatives

- A self-built notifier that checks the GitHub API and opens the download page
  — installation stays manual; revisit only if Sparkle becomes unusable.
- A self-built installer that replaces the bundle itself — duplicates Sparkle's
  signature checks and relaunch handling with more ways to fail.
- Homebrew cask as the update path — works outside the app and only for people
  who installed with Homebrew; may be added later as an extra channel.
- Mac App Store — its sandbox forbids reading Claude's files and Keychain item.

## Evidence worth preserving

- 2026-11-07, Sparkle 2.10.1 in a scratch copy of this project: the SwiftPM
  binary target resolves and links; a bundle with
  `Contents/Frameworks/Sparkle.framework`, signed with an Apple Development
  identity, passes `codesign --verify --deep --strict`; running the executable
  through a `~/.local/bin`-style symlink loads Sparkle through the
  `@executable_path/../Frameworks` rpath; the package ships `generate_keys`,
  `sign_update`, and `generate_appcast`, and `generate_appcast` embeds `.md`
  release notes placed beside the archive.
- `https://github.com/toy-crane/claude-desktop-baton/releases/latest/download/<asset>`
  resolves to the latest release's asset (checked with the 0.2.0 zip).
