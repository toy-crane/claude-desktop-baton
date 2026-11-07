# CLI follows the switch

One click in the panel moves the Claude Code CLI (`claude` in the terminal) to
the same account as Claude Desktop, so terminal work and Desktop work use the
same account's limits.

- Product contract this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  (switching steps, alerts, panel layout, off-limits). This spec states only
  what changes.
- Decision contract: [cli-sign-in](../../decisions/cli-sign-in.md) governs how
  the CLI is moved (in place, not per-folder), where a CLI sign-in comes from,
  re-saving the outgoing one, and leaving the CLI alone when none is saved.
- Decision contract: [session-sync](../../decisions/session-sync.md) is
  unchanged; the CLI step does not sync anything.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Desktop sign-in, CLI sign-in,
  CLI account).

## User-visible outcomes

- After switching to an account whose CLI sign-in is saved, `claude` in any
  terminal uses that account: new `claude` processes at once, already-running
  ones within about 30 seconds, without restarting them.
- The user can see in the panel which account the CLI is on, including when it
  differs from Claude Desktop's.
- Each account's CLI sign-in is saved without any action in the app: signing in
  with `/login` in a terminal is enough.
- When an account has no saved CLI sign-in yet, switching to it still switches
  Claude Desktop, leaves the CLI on its current account, and tells the user to
  sign in once in the terminal.

## Scope

In:

- Moving the CLI's default sign-in during a switch and a Put Back.
- Saving each account's CLI sign-in automatically, and re-saving the outgoing
  one at each switch.
- Showing the CLI account in the panel.
- Deleting an account's saved CLI sign-in when the account is removed.

Out:

- claude.ai in a web browser (deferred below).
- `CLAUDE_CONFIG_DIR` profiles and their Keychain items.
- Moving Claude Desktop when the CLI's account changes in the terminal.
- Any new confirmation step: moving the CLI does not stop terminal work.

## Behavior

### Saving CLI sign-ins

- Whenever the CLI is signed in to a saved account, the app keeps a copy of
  that CLI sign-in for the account, refreshing the copy when it changes. It
  checks while the app runs, at least when the panel opens and at the start of
  each switch.
- A CLI sign-in for an account that is not saved is not kept.
- A CLI sign-in is matched to a saved account by account id and organization
  id from `~/.claude.json`.
- Saved CLI sign-ins are kept in the app's own Keychain items, never in a file,
  because unlike the Desktop sign-in they are not encrypted by Claude.

### Switching

The existing switch runs as before. The CLI step is added after Claude
confirms the target account:

1. The outgoing CLI sign-in is saved again (it may hold a token the CLI rotated).
2. If the target account has a saved CLI sign-in, it is put in place: the
   default Keychain item and the account fields in `~/.claude.json`. The CLI's
   refresh locks are held while doing so, so a refresh in a running `claude`
   cannot write the old account back.
3. If the target has no saved CLI sign-in, the CLI is not changed and an alert
   says, for example, "The CLI is still on Personal. Run `claude` and `/login`
   as Work once; after that it follows every switch."
4. If moving the CLI fails, Claude Desktop stays switched and an alert says the
   CLI stayed on the previous account.

- When the Desktop switch fails, the CLI is not changed.
- Put Back (after a failed switch) also returns the CLI to the account it was
  on, when the CLI had been moved.
- Add account does not change the CLI. After the new account signs in to
  Claude, the existing alert flow also mentions signing in to the CLI once.
- Remove account also deletes that account's saved CLI sign-in. The CLI's
  current sign-in is not changed.

### Panel

- The account the CLI is on carries a small monochrome "CLI" tag beside its
  name, in whichever section it appears.
- When the CLI is signed in to an account that is not saved, or is signed out,
  no account carries the tag, and the "⋯" menu shows "CLI: not on a saved
  account" or "CLI: signed out".
- An account with no saved CLI sign-in shows that on hover (for example "CLI
  not signed in yet").

## Acceptance criteria

1. With CLI sign-ins saved for A and B, switching from A to B makes
   `claude auth status` (or `/status`) in a new terminal report B.
2. A `claude` session already running under A when the switch to B happens
   makes its next request as B within about 60 seconds, without a restart.
3. After `claude` refreshes its token under A and the user switches A → B → A,
   the CLI is signed in to A and works without `/login`.
4. Switching to an account with no saved CLI sign-in leaves `~/.claude.json`
   and the default Keychain item unchanged, completes the Desktop switch, and
   shows the sign-in-once alert naming both accounts.
5. Signing in with `/login` as a saved account makes the panel tag that account
   "CLI" and lets the next switch to it move the CLI, with no action in the app.
6. Switching while a `claude` process is refreshing its token never leaves the
   CLI on the old account or with a token that no longer works.
7. A failed Desktop switch leaves the CLI unchanged; Put Back after a switch in
   which the CLI moved returns it to the previous account.
8. Removing an account deletes its saved CLI sign-in and leaves the CLI's
   current sign-in and `~/.claude.json` unchanged.
9. A `CLAUDE_CONFIG_DIR` profile's Keychain item and folder are unchanged by
   any switch.
10. No CLI token appears in any file the app writes, or in its logs.
11. `ClaudeDesktopBaton --status` also reports the CLI account and whether the
    target would move the CLI, without printing credentials.

## Settled constraints and rationale

- Move the CLI in place, not through per-account config folders; the CLI never
  gets Desktop's tokens; re-save the outgoing CLI sign-in; leave the CLI alone
  when no sign-in is saved. See [cli-sign-in](../../decisions/cli-sign-in.md).
- Never sign the CLI out and never end a server-side session: a local sign-out
  would break running terminal work, and Claude's Log Out ends the session the
  saved copy depends on.
- claude.ai in the browser is not part of this work (the user's choice on
  2026-11-07); see Deferred.

## Assumptions (overridable)

- The CLI moves after Claude Desktop confirms the target, so a failed Desktop
  switch never leaves the two on different accounts because of the app.
- The panel marks the CLI account with a "CLI" tag rather than a separate row;
  it stays a usage view.
- No confirmation for running terminal sessions: they keep running and continue
  as the new account.
- The CLI sign-in is checked when the panel opens and at each switch; a CLI
  `/login` made while the panel is closed is saved at the next check.

## Off-limits

- Signing the CLI out, or calling any endpoint that ends a session.
- Writing CLI tokens to files or logs (including the app's account files and
  `previous.json`).
- `CLAUDE_CONFIG_DIR` folders and their Keychain items.
- Changing the Claude Code CLI or its settings files beyond the account fields
  in `~/.claude.json`.

## Deferred

- **claude.ai web login.** Not switched. What was found on 2026-11-07, for when
  it is picked up:
  - claude.ai has no switcher between accounts with different emails.
  - Chrome 156 on this Mac binds claude.ai sessions to the device (DBSC, a
    `Device Bound Sessions` entry plus `__Host-sessionBinding` cookies), so
    writing Chrome's cookie database or reusing Claude Desktop's `sessionKey`
    is likely to fail, and sharing Desktop's session with a browser could get
    Desktop signed out.
  - Realistic options: open claude.ai in a Chrome profile linked to each
    account (robust, no cookies touched, the window changes rather than the
    tab), or a companion extension that saves and swaps the browser's own
    cookies (same tab; needs an extension and is untested against DBSC).
  - Existing extensions (for example
    [claude-switch-account](https://github.com/Smeagolworms4/claude-switch-account))
    swap cookie snapshots and handle no device binding.
- Running two accounts at once in different terminals.

## Remaining risks

- The CLI's Keychain item name, `oauthAccount` fields, 30-second cache, and lock
  files are undocumented and can change with a CLI update; the app should check
  what it reads and leave the CLI unchanged instead of guessing.
- Reading or writing the CLI's Keychain item may raise a macOS Keychain prompt,
  depending on how the item's access list treats the app.
- A saved CLI sign-in unused for a long time may expire; the CLI then asks for
  `/login`, and the next sign-in is saved again.
- A running `claude` mid-request when the account changes may finish that
  request under the old account.

## Setup before implementation

- A CLI sign-in for at least two saved accounts, to test switching — done when `claude auth status` reports each account after `/login` as it, on this Mac.
- A recent Claude Code CLI to verify against — done when `claude --version` reports 2.1.319 or later.
