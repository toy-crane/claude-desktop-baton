# Agent CLI

A command, `claude-desktop-baton`, lets agents and scripts see the saved
accounts and their usage and ask for a switch, for example an agent in a
terminal that reaches a limit and moves to the account with the most room.

- Product contract this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md).
  That spec listed "command-line modes" as out of scope; the user reversed that
  on 2026-11-07 for this command. The rest of its contract (switch steps,
  alerts, off-limits) still applies.
- Decision contract: [agent-cli](../../decisions/agent-cli.md) governs that
  reads run in the command's process and switches are carried out by the
  running menu bar app.
- Decision contract: [session-sync](../../decisions/session-sync.md) — there is
  still no sync command.
- Related: [cli-follows-switch](../cli-follows-switch/spec.md). When it has
  shipped, a switch also moves the terminal CLI, which is what lets a terminal
  agent keep working after it switches. This spec does not depend on it.

## User-visible outcomes

- An agent can run `claude-desktop-baton accounts`, `status` and `usage` and get
  the saved accounts, who is signed in, and each account's Session and Week
  usage, as text or JSON.
- An agent can run `claude-desktop-baton switch <account>` or `switch --best`.
  The menu bar app performs the switch exactly as if the user had clicked it:
  the menu bar shows the spinner and any failure shows the usual alert with Put
  Back. The command reports the outcome.
- A switch the user would have been asked to confirm, or one requested from
  inside Claude Desktop, is refused unless the agent passes `--force`.
- The user installs the command once from the panel.

## Scope

In:

- Commands: `accounts`, `status`, `usage`, `switch`, `help`.
- Installing the command from the panel.
- JSON output and exit codes for agents.

Out:

- Adding and removing accounts from the command line.
- A sync command (rejected by session-sync).
- An MCP server, an agent skill file, and Homebrew distribution (deferred).

## Behavior

### Commands

- `accounts`: every saved account in panel order, with its display name,
  email, account id, and whether it is signed in to Claude Desktop.
- `status`: what the existing `--status` mode reports (Claude running, signed-in
  account, working sessions in the last 2 minutes, what a switch would sync),
  plus whether the menu bar app is running and, once cli-follows-switch ships,
  the CLI account. `--status` keeps working as before.
- `usage`: Session and Week percent used and reset times for each saved
  account, with the time they were fetched. Values fetched in the last 2 minutes
  are reused; `--refresh` fetches again.
- `switch <account>`: `<account>` matches a display name, an email, or a
  unique prefix of an account id. No match or more than one match is an error
  that lists the candidates.
- `switch --best`: the saved account other than the signed-in one with no limit
  at 100% and the lowest Session percent, then the lowest Week percent. When
  none qualifies, nothing is switched and the reason is reported.
- `help`: usage written so an agent can use the command without other docs,
  including the refusal rules and exit codes.
- Every command accepts `--json`.

### Switching from the command line

1. The command sends the request to the menu bar app. If the app is not
   running, the command launches it first.
2. The app refuses, without touching Claude, when:
   - a switch is already in progress;
   - the target is already signed in;
   - a session was working in the last 2 minutes (the case where the panel
     would ask), unless `--force`;
   - the request comes from an agent running inside Claude Desktop, unless
     `--force`, because the switch would stop that agent and its neighbours.
3. Otherwise the app runs the normal switch: spinner, the same steps, the same
   failure and sync-warning alerts for the user.
4. The command waits for the outcome (up to 3 minutes) and reports it. With
   `--no-wait` it returns as soon as the app accepts. If the command is killed
   while waiting, the switch still completes.

### Output and exit codes

- Text by default; `--json` gives a stable object per command, with an `error`
  field on failure.
- Exit codes: 0 success; 1 error; 2 refused by a rule above; 3 the menu bar app
  could not be reached or launched.
- No output includes cookies, tokens, or other credentials.

### Installing

- The panel's "⋯" menu has "Install Command Line Tool". It creates
  `~/.local/bin/claude-desktop-baton`, a link to the command inside the app, so
  it runs with the app's signature and the user's existing "Claude Safe
  Storage" approval. When `~/.local/bin` is not on `PATH`, an alert says so and
  gives the line to add.
- When the link already exists, the menu item reads "Command Line Tool
  Installed" and is disabled; a broken link (for example after moving the app)
  is replaced.

## Acceptance criteria

1. `claude-desktop-baton accounts --json` lists every saved account in the
   panel's order and marks the signed-in one, with the menu bar app running or
   not.
2. `usage --json` returns Session and Week percent for each account; a second
   call within 2 minutes makes no new request to claude.ai; `--refresh` does.
3. `switch <name>` with no working session ends with Claude signed in to that
   account, exit code 0, and the menu bar showed the spinner during the switch.
4. With a session working in the last 2 minutes, `switch <name>` exits 2 and
   Claude keeps running; adding `--force` switches.
5. Run from an agent inside Claude Desktop, `switch <name>` exits 2 without
   touching Claude; `--force` switches.
6. Killing the command right after it sends `switch` still ends with Claude
   signed in to the target account.
7. With the menu bar app quit, `switch <name>` launches it and completes the
   switch.
8. A failed switch requested from the command line shows the user the usual
   alert with Put Back and makes the command exit 1 with the reason.
9. `switch --best` picks the account with no reached limit and the lowest
   Session percent; when every other account has a limit at 100%, it exits 2.
10. An ambiguous or unknown `<account>` exits 1 and lists the candidates.
11. No command's output, in text or JSON, contains a credential.
12. "Install Command Line Tool" makes `claude-desktop-baton status` work in a
    new terminal whose `PATH` includes `~/.local/bin`, with no new Keychain
    prompt.
13. There is no command that syncs sessions without switching.

## Settled constraints and rationale

- Reads run in the command's process; switches are handed to the running menu
  bar app, which finishes them even if the caller dies and shows the user what
  happened. See [agent-cli](../../decisions/agent-cli.md).
- Command name `claude-desktop-baton` (the user's choice): mostly typed by
  agents, so being unambiguous matters more than being short. On 2026-11-07 it
  was unused locally, on npm, and in Homebrew; "baton" and npm "claude-baton"
  are taken.
- Adding and removing accounts stay in the panel: adding needs a person to sign
  in, removing cannot be undone.

## Assumptions (overridable)

- The request channel is a local socket in the app's data folder that only the
  same user can open.
- One `--force` overrides both the working-session and the inside-Desktop
  refusals.
- `--best` ranks by Session percent, then Week percent.
- Usage fetched by the command is cached in the app's data folder; percentages
  and reset times are not secret.
- The command waits up to 3 minutes for a switch.
- Install location `~/.local/bin`, which needs no administrator rights (other
  command line tools on this Mac use it).

## Off-limits

- Printing or writing credentials anywhere, including the usage cache.
- Running a switch in the command's own process.
- Syncing sessions outside a switch.
- Adding or removing accounts from the command line.

## Deferred

- An agent skill file or an MCP server that wraps the command. Revisit when
  agents without a shell need it or `help` proves insufficient.
- Homebrew (cask with a `binary` link) and other distribution.
- Whether a switch requested by an agent should be marked as such in the alerts.

## Remaining risks

- An agent passing `--force` inside Claude Desktop stops itself and its
  neighbouring sessions; nothing resumes them automatically.
- Detection of "inside Claude Desktop" relies on the environment Claude
  Desktop gives its Code sessions (`CLAUDE_CODE_ENTRYPOINT=claude-desktop` on
  2026-11-07), which is undocumented and can change.
- Agents that call `usage --refresh` in a loop could still hit claude.ai's
  undocumented endpoint too often.

## Setup before implementation

None.
