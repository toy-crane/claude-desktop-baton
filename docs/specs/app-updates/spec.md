# App updates

Claude Desktop Baton tells the user when a newer version is out and installs it
in a few clicks, so people stop running old builds that may no longer match how
Claude Desktop stores its data.

- Product contract this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md).
  It deferred "auto-update"; this spec settles it. Its scope line "One menu bar
  panel; no other window" gains one exception, confirmed on 2026-11-07 when the
  user chose the panel notice whose Install button opens Sparkle's update
  window. The rest of that contract still applies.
- Decision contract: [app-updates](../../decisions/app-updates.md) governs the
  updater (Sparkle 2), where the feed lives, update signing, keeping the same
  signing identity, and never relaunching during a switch.
- Decision contract: [agent-cli](../../decisions/agent-cli.md) — the running menu
  bar app finishes every switch, which is why an install waits for it.

## User-visible outcomes

- When a newer version has been published, the baton icon in the menu bar gets
  a small dot and the panel shows an **update notice** row, "Update available ·
  0.3.0", with an **Install…** button. Nothing pops up on its own.
- Install… opens the update window: new and current version, the release notes,
  and Skip This Version, Remind Me Later, and Install Update. Install Update
  downloads, verifies, replaces the app in place, and reopens it.
- After the update the app works as before: same saved accounts, usage shows
  without a new Keychain prompt, launch at login stays as it was, and the
  `claude-desktop-baton` command keeps working without reinstalling it.
- The `⋯` menu gets **Check for Updates…** for checking right away.
- People on 0.2.0 or earlier install the first version that has this feature by
  hand, once; from then on it updates itself.

## Scope

In:

- Daily background check, the update notice (icon dot and panel row), Check for
  Updates…, the update window, download, verification, install, and relaunch.
- Releases that publish what the check reads: the feed, the signed archive, and
  release notes.
- Telling existing users, in the README and the release notes of the first such
  version, that they need to install it by hand once.

Out:

- Updating Claude.app (it updates itself; off-limits in the base contract).
- Beta or pre-release channels, delta updates.
- Homebrew cask distribution.

## Behavior

### Finding an update

- About once a day, and shortly after the app launches, the app checks the feed
  for a version newer than its own that runs on this Mac's macOS.
- When one is found, the icon dot and the panel row appear. No window, sound,
  or system notification appears for a background check.
- A failed background check (offline, feed missing) shows nothing and is tried
  again at the next check.
- Check for Updates… always answers in the update window: the update, "You're
  up to date", or the error.

### The update notice

- The row sits at the bottom of the panel, above "+ Add account", and shows the
  new version number and Install….
- The row stays until the update is installed or that version is skipped. A
  newer release replaces the version shown.
- The icon dot stays until the user has opened the panel while the row is shown
  (interim per Assumptions; see there).
- Skip This Version removes the dot and the row until a newer version is
  published. Remind Me Later closes the window and keeps the row.

### Installing

- Install Update downloads the archive and verifies it before anything is
  replaced. An archive that fails verification is discarded, the window says the
  update could not be verified, and the app stays on its current version.
- The app replaces itself at the same location and reopens. It does not quit or
  relaunch while a switch is running or a switch alert (confirm, failed, Put
  Back) is open; it installs once that is over.
- Quitting the app with an update downloaded but not installed installs it on
  the way out.

### Releases

- Each published release carries the feed, the archive the app downloads, and
  release notes identical to the GitHub release's notes.
- A release's version must be higher than every earlier one; the feed lists the
  minimum macOS the build needs.

## Acceptance criteria

- With 0.3.0 installed and a 0.3.1 release published, within a day (or after
  relaunching the app) the baton icon shows a dot and the panel shows "Update
  available · 0.3.1" with Install…; no window or notification appeared on its
  own.
- Clicking Install… opens the update window naming 0.3.1 and 0.3.0 with the
  same release notes as the GitHub release.
- Install Update, then the relaunch, leaves `/Applications/Claude Desktop
  Baton.app` at 0.3.1 (About shows it), with the dot and row gone.
- After that update, the panel loads every account's usage without macOS asking
  about "Claude Safe Storage", launch at login is unchanged, and
  `claude-desktop-baton status` runs from a new terminal without reinstalling
  the command.
- A feed whose archive signature does not match the project's key is refused:
  the app stays on 0.3.0 and says the update could not be verified.
- Starting a switch and then choosing Install Update: the app does not restart
  until the switch has finished and any switch alert is closed.
- Skip This Version on 0.3.1 removes the dot and row; publishing 0.3.2 brings
  them back.
- With the network off, the background check shows nothing; Check for Updates…
  shows an error in the update window.
- Check for Updates… with no newer release shows that the app is up to date.

## Settled constraints and rationale

- Updater: Sparkle 2, pinned to an exact version (user choice, 2026-11-07; see
  app-updates for rejected alternatives).
- Surface: icon dot plus panel row; Sparkle's window opens only from Install… or
  Check for Updates…. The user compared it with "Sparkle window only" (easy to
  miss for a menu bar app, whose windows open behind other apps) and "plus a
  system notification" (one more permission prompt for news that is not
  urgent), and chose this on 2026-11-07.
- No relaunch during a switch or while a switch alert is open: a restart then
  can leave Claude closed or signed in to the wrong account, and drops the Put
  Back alert.
- Same bundle identifier and Developer ID team for every update, so Keychain
  approval, the login item, and the command link carry over.

## Assumptions (overridable)

- Check interval is Sparkle's default of one day, plus a check soon after
  launch.
- Automatic checks are on from first launch with no "check automatically?"
  prompt; Check for Updates… is the only update item in the `⋯` menu (no
  separate on/off toggle).
- Interim: the icon dot clears once the panel has been opened with the row
  showing; the row itself stays. Replace if the dot proves too easy to dismiss.
- Sparkle's own "Automatically download and install updates in the future"
  checkbox stays available in the update window, unchecked by default. When a
  user checks it, updates install without asking, still never during a switch.
- Update window text is Sparkle's standard English text; the panel row copy is
  "Update available · <version>" and "Install…".
- The feed and archive come from the repository's latest-release download URL;
  the archive is the zip already produced by the release script, and the DMG
  stays for first-time installs.

## Off-limits

- Claude.app and its data: an update to this app touches only this app's bundle.
- Sending anything about the Mac or the user with the update check: no system
  profile, no analytics.
- The `~/.local/bin/claude-desktop-baton` link and the login item: an update must
  not recreate, move, or remove them.

## Deferred

- Showing update availability in the command line (`status`, `--json`) for
  agents. Until decided, the command line says nothing about updates.
- A Homebrew cask as an extra channel.
- A beta channel.

## Remaining risks

- The full download-verify-replace-relaunch path was not run during shaping;
  only building, signing, and loading Sparkle in this project's bundle were
  checked. The first real test is an update between two test builds before the
  first public release that has the updater.
- If the Sparkle private key is lost, installed copies refuse every later
  update until users reinstall by hand. If it leaks, someone who can also get
  a file onto the update path could ship a build the app accepts (the Developer
  ID signature and notarization still have to pass).
- The latest-release URL follows GitHub's "Latest" release. Publishing a release
  without the feed asset, or marking the wrong release as latest, stops update
  checks for everyone until fixed.
- Users who installed into a folder they cannot write to without admin rights
  are asked for an administrator password during the update.
- 0.2.0 and earlier never learn about updates on their own; users who do not
  read the release page stay on old builds.

## Setup before implementation

- A Sparkle EdDSA key pair for signing updates, kept in the login Keychain of the Mac that runs `scripts/release.sh` and backed up outside it, so update archives can be signed — done when Sparkle's `generate_keys -p` on that Mac prints a public key and a backup entry for the private key exists in the user's password manager.
