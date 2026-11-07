# Agent CLI

## Decisions

- The app ships a command line for agents and scripts. Read commands (accounts,
  current account, usage, status) run in the command's own process and work
  whether or not the menu bar app is running.
- A switch requested from the command line is carried out by the running menu
  bar app, never by the command's own process. The command sends the request,
  launches the app first when it is not running, and waits for the result; the
  switch completes even when the command is killed while waiting.
- The menu bar app decides whether to accept a requested switch, using the same
  rules as a click in the panel, and shows the same spinner and alerts.
- There is no command that syncs sessions on its own; syncing stays a step of a
  switch ([session-sync](session-sync.md)).

## Boundaries

- Adding and removing accounts stay in the panel: adding needs a person to sign
  in, and removing cannot be undone.
- The command line never prints credentials.

## Why

A switch quits Claude Desktop and can take a minute and a half. Callers such as
an agent's shell tool time out or get killed, and an agent running inside
Claude Desktop is itself stopped when Claude quits; a switch run in the caller's
process would then stop halfway, leaving Claude closed or signed in to the wrong
account. The long-lived menu bar app finishes every switch, keeps one place that
switches, and lets the user see why Claude restarted. Concurrent switches were a
minor concern; caller lifetime and visibility decided it.

## Reconsider when

- The app stops running in the background by default (no launch at login).
- Agents need to switch on a Mac where the menu bar app cannot run.

## Still-rejected alternatives

- The command performs the switch in its own process — it can be killed
  mid-switch and the user sees no spinner or alerts; revisit only if the menu
  bar app goes away.
- A URL scheme as the request channel — it cannot return a result to the
  caller.
- An MCP server as the first interface — needs per-client setup, while every
  agent can already run a command; revisit if agents without a shell need it.
