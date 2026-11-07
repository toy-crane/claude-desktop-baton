# CLI sign-in

## Decisions

- An account switch also moves the Claude Code CLI to the target account by
  replacing the CLI's own sign-in in place: the default Keychain login
  (`Claude Code-credentials`, no config-dir suffix) and the account fields in
  `~/.claude.json`. Every `claude` started without `CLAUDE_CONFIG_DIR` follows,
  including ones already running, and all accounts keep one shared history in
  `~/.claude`.
- Each account's CLI sign-in is its own login, captured from the CLI after the
  user signs in there once. It is never derived from Claude Desktop's sign-in.
- The outgoing CLI sign-in is saved again at every switch before the target's
  is put in place, so a token the CLI rotated since the last save is kept.
- When the target account has no saved CLI sign-in, the CLI is left as it is;
  the app says which account the CLI is on and asks the user to sign in there
  once. The app never signs the CLI out.

## Boundaries

- Config folders chosen with `CLAUDE_CONFIG_DIR` and their Keychain items are
  not touched.
- A sign-in change made in the terminal (`/login`, `/logout`) only updates the
  saved CLI sign-in for that account; it does not move Claude Desktop.
- Nothing here ends a server-side session.

## Why

The switch exists to hand work to another account in one click. Swapping in
place reaches the terminals the user already has open (the CLI re-reads the
Keychain within about 30 seconds) and keeps one conversation history, which
matches how Baton hands Code sessions over. Claude Desktop's cached tokens carry
no refresh token, so they cannot become a lasting CLI login. Signing the CLI out
when no login is saved would break running terminal work to prevent a
wrong-account mistake the user can see and fix with one `/login`.

## Reconsider when

- Claude Code stops re-reading its Keychain login while running, or changes the
  item's name, the `oauthAccount` fields, or its refresh lock protocol.
- Claude Code offers its own account switcher.
- The user needs two accounts running in parallel terminals.

## Still-rejected alternatives

- One `CLAUDE_CONFIG_DIR` per account with a shell shim (hotseat,
  claude-code-profiles) — only newly started `claude` processes switch, history
  splits per folder unless symlinked, and apps started outside a shell miss the
  variable; revisit if parallel accounts become a need.
- Long-lived `claude setup-token` tokens in `CLAUDE_CODE_OAUTH_TOKEN` —
  inference only, no Remote Control or connectors, and a change needs a restart.
- Reusing Claude Desktop's token cache for the CLI — it holds short-lived
  access tokens without a refresh token.

## Evidence worth preserving

- Claude Code 2.1.319 (checked 2026-11-07): the Keychain service is
  `Claude Code-credentials`, plus `-` and the first 8 hex digits of
  `sha256(CLAUDE_CONFIG_DIR)` when that variable is set (so setting it to
  `~/.claude` reads a different item than leaving it unset); the account is
  `$USER`; the item is cached for 30 seconds; a refresh replaces the stored
  refresh token. Refresh is guarded by `proper-lockfile` locks
  `~/.claude/.oauth_refresh.lock` and `~/.claude.lock`, which
  [claude-swap](https://github.com/realiti4/claude-swap) holds while swapping.
- The CLI's `oauthAccount.accountUuid` uses the same account ids as Claude
  Desktop: on 2026-11-07 the CLI was signed in to a saved account
  (`361f7049…`) while Desktop was on another (`3cb0fc11…`), same organization.
- The CLI's Keychain item is one JSON object holding the login under
  `claudeAiOauth` and every MCP server's tokens under `mcpOAuth` (32 KB on
  this Mac on 2026-11-07), so only `claudeAiOauth` is saved per account and
  replaced; replacing the whole item would swap the user's MCP logins too.
  Claude Code writes it with `security add-generic-password -U … -X <hex>`,
  through `security -i` stdin when the line fits in 4096 bytes and through
  arguments otherwise.
- This Mac also holds a `Claude Code-credentials-4058bcae` item from some
  `CLAUDE_CONFIG_DIR` profile; it is out of scope.
