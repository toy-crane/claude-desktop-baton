# Claude Desktop Baton

Claude Desktop Baton is a macOS menu bar app for using several Claude accounts in
Claude Desktop. It switches Claude Desktop to another saved account in one
click, shows each account's usage, and hands Code session lists over between
accounts only at the moment of a switch, like passing a baton.

Concept borrowed from https://github.com/5eanxlee/claude-desktop-accounts (its
account-switching mechanism and session-record layout, as observed in Claude
Desktop 2.16). Nothing of its code, packaging, or UI carries over.

- Decision contract: [docs/decisions/session-sync.md](../../decisions/session-sync.md)
  governs when sessions sync, which sessions sync, how deletions follow, and
  why there is no background sync. This spec does not restate its rules.
- Visual reference for the panel: option 1 ("two bars") of
  https://claude.ai/artifact/HKrGSYErpDfxVP7GeEyrMm. It is a comparison, not an
  approved full prototype; the panel description below is the contract.

## User-visible outcomes

- From the menu bar, the user sees every saved account with how much of its
  current-session and weekly limits is used, and which account Claude is
  signed in to.
- Clicking another account switches Claude Desktop to it in one step. Claude
  restarts signed in to that account, and its Code tab lists the sessions the
  other accounts have, within the synced scope.
- Nothing touches Claude's session folders while the user is not switching.
- A misclick cannot silently stop work in progress: when a Code session was
  active in the last 2 minutes, the switch asks once.

## Scope

In:

- Saved accounts: automatic save of the signed-in account, add, remove.
- Account switch, including session sync as one of its steps.
- Usage for every saved account.
- One menu bar panel; no other window.

Out (removed from the reference project on purpose):

- Background or periodic session sync, a manual "sync now" action, a sync
  command line, and any Node.js dependency (see the decision contract).
- A separate accounts window, a "Save current account" action, command-line
  modes, and an npx/curl installer.

## Behavior

### Launch

- The app runs on macOS 26 or later.
- It launches at login by default. A "Launch at login" toggle in the "⋯" menu
  turns that off and on.

### Saved accounts

- On first launch, accounts already saved by the reference app in
  `~/Library/Application Support/Claude Accounts/accounts/` are imported
  read-only, so the user does not sign in to them again. The reference app's
  files are not changed. Without that folder the app starts with no accounts.
- When Claude is signed in to an account that is not saved, the app saves it
  automatically. There is no manual save action.
- Add account: Claude quits, the app runs the session sync, then Claude
  reopens signed out on this Mac only (the outgoing account's server-side
  session is not ended). An alert then asks the user to sign in to another
  account in Claude. The first account that loads afterwards is saved
  automatically. The outgoing account stays switchable.
- Remove account: from the "⋯" menu, after a confirmation alert.
  It deletes only the app's saved sign-in for that account; Claude and the
  session folders are not changed.
- Saved sign-ins stay encrypted exactly as Claude stored them. Decrypted
  values are never written to disk or logged.

### Switching

1. The user clicks an account other than the current one.
2. If any non-archived session in the signed-in account's folder was active
   in the last 2 minutes (its record's `lastActivityAt`, or the last write to
   its Claude Code conversation file), an alert asks first, for example
   "2 sessions are working in Claude", with Switch and Cancel. Otherwise the
   switch starts on the first click. Either way the panel closes.
3. Claude quits normally. If it is still open after 45 seconds, the switch
   stops and nothing is changed.
4. The outgoing account's sign-in is saved again, keeping any token Claude
   refreshed.
5. Session sync runs (rules in the decision contract).
6. The target account's sign-in is put in place, keeping a copy of what was
   there before.
7. Claude reopens, and the app waits up to 45 seconds for Claude to confirm the
   target account.
8. On failure, an alert offers to put the previous account back.

A sync failure does not stop the switch: the switch completes and an alert
warns; the missing records are brought in line at the next switch.

### Usage

- For each saved account: percent used of the current session (5-hour) limit
  and of the weekly limit, using the same terms as Claude's own usage screen
  ("Session", "Week").
- Refreshed every 2 minutes and when the panel opens if older than 1 minute.
  The time of the last refresh appears in the "⋯" menu.
- When a limit reaches 100%, that bar and number turn red and the time until it
  resets appears beside the account name.
- When usage cannot be fetched, the numbers show "—", the bars are empty, and
  a small indicator beside the name explains why on hover.

### Panel (option 1, "two bars")

- Opened from a menu bar icon. While switching, the icon shows a spinner.
- One block per saved account: the account name; below it a "Session" bar and a
  "Week" bar, each with its percent.
- The panel has two sections. "Signed in" holds the signed-in account alone,
  with a larger name and its email. "Switch to" lists every other saved
  account in the order they were saved. When the signed-in account is not
  saved yet, "Signed in" is left out and every saved account is under
  "Switch to".
- Email (except the signed-in account's), plan, and reset times appear only on
  hover.
- Monochrome: ink bars on a light track (dark mode mirrored). Red only for a
  reached limit.
- Footer: "+ Add account" and a "⋯" menu holding the last refresh time,
  "Launch at login" (a toggle), "Remove account ›", and "Quit ⌘Q".
- The panel holds no switching controls or messages. Confirmations, failures
  ("Couldn't switch to …" with "Put Back <previous>"), sync warnings, the
  add-account sign-in prompt, and remove confirmations appear as alerts.
- While switching, the panel, if reopened, shows the target row with a spinner
  and every row and action disabled.
- UI text is English.

## Acceptance criteria

1. While Claude runs and no switch or add is in progress, the app changes no
   file under Claude's session folders (no file in them gains a newer
   modification time from the app).
2. After switching from account A to B, B's Code tab lists every non-archived
   session from A's folder, and every archived one whose last activity is
   within 30 days; an archived session older than that, present only in A, is
   not listed under B.
3. When the same session differs between folders, the copy with the latest
   `lastActivityAt` is the one every folder holds after the switch.
4. A session deleted in Claude under A (its folder holds `deleted_<id>`) is
   absent from every other folder after the next switch, and its removed copies
   are in the app's own trash.
5. A record missing from a folder without a `deleted_` marker is present again
   after the next switch.
6. With a session active in the last 2 minutes, clicking another account shows
   a confirmation alert, and Cancel leaves Claude untouched. With none, one
   click starts the switch.
7. A switch whose target fails to load offers "Put back <previous>", and
   choosing it returns Claude to the previous account.
8. Each saved account shows Session and Week percent used within 2 minutes of
   the panel opening; a limit at 100% shows red with its reset time; a failed
   fetch shows "—" and the hover reason.
9. Signing in to an unsaved account in Claude makes it appear in the panel
   without any action in the app.
10. Add account reopens Claude signed out; after signing in to another account,
    both accounts are listed and switching between them works.
11. Remove account removes only that account from the panel; Claude stays
    signed in as before and no session folder changes.
12. A sync failure during a switch still ends with Claude signed in to the
    target account, and an alert warns that sessions were not synced.
13. Claude.app's bundle is never modified.
14. On first launch with the reference app's accounts folder present, its
    saved accounts appear in the panel without signing in, and switching to
    each works; the reference app's folder is unchanged.
15. After a fresh install the app starts again after logging out and back in to
    macOS; with "Launch at login" turned off, it does not.
16. The app launches and works on macOS 26.

## Settled constraints and rationale

- Sync only during a switch or an add, with Claude closed; scope and deletion
  rules per [session-sync](../../decisions/session-sync.md).
- Usage stays, with its costs: a one-time Keychain approval for "Claude Safe
  Storage", in-memory cookie decryption, and an undocumented claude.ai usage
  endpoint. The user picks the target account by remaining room, so the panel
  is mainly a usage view.
- Panel option 1 was chosen over a single "room left" bar and ring tiles: it
  matches Claude's own usage screen, so it reads without a legend.
- Switching messages are alerts, not panel content (the user's change after
  seeing the panel during implementation): the panel stays a usage view.
- The signed-in account sits apart at the top, chosen over a highlighted card
  and a check with a side rule: a small dot was too easy to miss, and a
  separate section answers "who am I now" before "where can I go".
- Confirm only when a session was active in the last 2 minutes: a switch
  restarts Claude and stops running Code work, which is costly when
  orchestrator sessions run several at once; always confirming would make every
  switch two clicks. Running session processes cannot be the signal, because
  idle sessions keep processes too.
- Never use Claude's own Log Out for saved accounts: it most likely ends the
  server-side session and breaks the saved copy. Add account signs out on this
  Mac only.
- macOS 26 or later: the app works on this Mac now and keeps working after the
  planned move to macOS 27; requiring 27 would block use until that update.
- Launch at login is on by default: the app must be running to save newly
  signed-in accounts and keep usage current.
- The app's name is "Claude Desktop Baton", chosen by the user. Because it carries the
  Claude name, the app states that it is unofficial and not affiliated with
  Anthropic wherever it describes itself (for example its About information).

## Assumptions (overridable)

- Account name: the organization name; Claude's default personal organization
  shows as "Personal"; when two accounts would show the same name, the email's
  local part is appended.
- Interface faces: Geist and Geist Mono bundled with the app, falling back to
  the system font.
- The 2-minute activity window reads the signed-in account's session records
  and the modification time of each session's conversation file under
  `~/.claude/projects/` (read only). Revised during implementation: on
  2026-11-05 a session mid-turn had a `lastActivityAt` 868 seconds old while
  its conversation file had been written 0 seconds earlier, so the record alone
  misses long turns.
- Accounts are listed in the order they were saved, not sorted by usage.

## Off-limits

- Writing to any session folder while Claude runs: Claude holds the loaded
  folder in memory and overwrites outside changes.
- Modifying Claude.app or its signature: updates must install normally.
- Ending a server-side session (Claude's Log Out or an equivalent request).
- Writing decrypted cookies or tokens anywhere, including logs.
- Cowork sessions, cloud sessions, Remote Control state, artifacts, and
  scheduled tasks: they stay with the account that created them.

## Deferred

- Sign-in changes made outside the app (Claude's own sign-in screen): no sync
  happens; the panel only reflects who is signed in. Revisit if sessions are
  found missing after such changes.
- Renaming accounts or choosing labels by hand.
- Cleaning up the copies of archived sessions older than 30 days that the
  reference project already placed in every folder (about 3.4 GB across 7
  folders on this Mac). No folder records which account a session came from,
  so removal could hide sessions from their own account.
- Distribution: notarization, auto-update, and an installer beyond copying the
  app.

## Remaining risks

- Claude Desktop's session-record layout, sign-in storage, `deleted_` markers,
  and usage endpoint are undocumented and can change with an update. The app
  should check what it reads and stop instead of guessing.
- Whether Claude writes a `deleted_` marker for every deletion is not verified;
  if not, deleted sessions reappear after a switch.
- A session that is running but has written nothing to its conversation for
  over 2 minutes (for example a single long tool call) does not count as
  working, so the switch starts without asking.
- A newly added account's session folder does not exist until Claude first
  loads it, so its sidebar lists other accounts' sessions only from its next
  switch-in.
- Rebuilding with an ad-hoc signature makes macOS ask for Keychain access
  again after each rebuild.
- On 2026-11-05 no GitHub repository or npm package was named
  "claude-desktop-baton", but the shorter "Claude Baton" and "Baton" are taken
  by related tools (GitHub `bakabaka91/claude-baton`, `rlawlsgus/Baton`, npm
  `claude-baton`, Mac App Store "Baton: API Client"), so a shortened form of the
  name would collide if the app is published.

## Setup before implementation

- Stop the reference project so two tools do not switch or sync at once, keeping its saved accounts for import — done when `launchctl print gui/$(id -u)/local.claude-session-sync` reports no such service, `Claude Accounts.app` is not running or installed, and `~/Library/Application Support/Claude Accounts/accounts/` still exists.
- A stable code-signing identity for local builds, so the Keychain approval for "Claude Safe Storage" survives rebuilds — done when `security find-identity -v -p codesigning` lists an "Apple Development" identity.
- At least two Claude accounts the user can sign in to, for switching and usage checks — done when both can sign in to Claude Desktop on this Mac.
