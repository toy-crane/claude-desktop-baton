# Session sync

## Decisions

- Session records are synced only as a step of an account switch, while Claude
  Desktop is closed, before it reopens under the target account.
- There is no separate sync tool: no background agent, no periodic or
  file-watch sync, no manual sync command, and no Node.js dependency. The app
  that performs the switch performs the sync.
- Every non-archived session is synced. An archived session is synced only
  when its `lastActivityAt` is within the last 30 days; older archived
  sessions are not copied or updated.
- A session is treated as deleted only when some account folder holds
  Claude's own `deleted_<sessionId>` marker. Its copies in other folders are
  moved to the app's own trash, and it is never copied again, whatever its
  age. A record that vanished without a marker is not a deletion; it is filled
  back from another folder's copy.
- The app keeps no state of its own to detect deletions.
- Remote Control sessions (run by a `claude remote-control` server) have no
  record to sync. After Claude confirms the target account, the app opens each
  running one that no account folder has a record or deletion marker for, with
  the link Claude Code's `/desktop` command uses
  (`claude://resume?session=<id>`). Claude writes the record itself; from the
  next switch on it is synced like any other.

## Boundaries

- A sign-in change made outside this app (Claude's own sign-in screen) does
  not trigger a sync.

## Why

Claude Desktop holds the signed-in account's session folder in memory and
writes it back from memory, so any write to that folder while Claude runs can
be lost or overwritten. Continuous sync needed protection and deferral rules
for the loaded folder and still rewrote records hundreds of times a day.
During a switch Claude is closed, so no folder is loaded and every folder can
be brought up to date safely in one pass.

Archived sessions are still synced because orchestrator sessions search them
(`search_session_transcripts` with `include_archived`) and unarchive them, and
those tools only see the signed-in account's records. Each folder needs its own
full copy of a record (Claude refuses linked files), and records are large, so
the window keeps the copies to what that search actually reaches.

Without propagating deletions, a session deleted under one account would be
copied back from another folder at the next switch. Claude already marks each
deletion in the folder where it happened, so following that marker needs no
remembered state and no bulk-removal hold; when a marker is missing the
failure is a session that reappears, never one that is lost.

## Reconsider when

- Claude Desktop starts re-reading a loaded session folder from disk, or
  offers its own cross-account session list.
- Sessions must appear under another account without switching to it.
- Orchestrator sessions start finding or unarchiving archived sessions older
  than 30 days.
- A session deleted in Claude reappears after a switch (Claude no longer
  writes a `deleted_` marker for some deletions), or the marker's format
  changes.
- Claude Desktop stops taking over a session from the `/desktop` link, or a
  Remote Control server's sessions start following the CLI's account on their
  own.

## Still-rejected alternatives

- Writing a `local_<uuid>.json` record for each Remote Control session — the
  format is undocumented and the records Claude writes when it takes over a CLI
  session carry values only the running app has; the `/desktop` link has Claude
  write the same record itself. Revisit only if that link stops working.
- Only telling the user which Remote Control sessions stay behind and handing
  out `claude --resume` commands — it left the work to the user at every
  switch; revisit if opening sessions in Claude after a switch proves
  disruptive.
- Background sync on file changes and a fixed interval (the reference
  project's approach) — writes into the loaded folder race with Claude's
  in-memory copy and require protect-and-defer rules; revisit only if Claude
  re-reads the folder from disk.
- A manual "sync now" action while Claude runs — reintroduces the same
  loaded-folder race; revisit under the same condition.
- Detecting deletions from the app's own memory of which records existed, with
  a hold when many vanish at once (the reference project's approach) — needs
  persistent state and can mistake a reset folder for deletions; revisit only
  if Claude stops writing `deleted_` markers.

## Evidence worth preserving

- On 2026-11-10, after a switch, four sessions run by `claude remote-control`
  servers (worktrees `<repo>/.claude/worktrees/bridge-cse_<id>`) were missing
  from the new account while every Code-tab record was in sync. None of the
  2,135 records had such a worktree as its `cwd`. The 34 records marked
  `adoptedFromOtherSurface` all had `sessionId` equal to `local_` plus the
  `cliSessionId`, and each carried a `remoteMcpServersConfig` of 10–90 KB and
  other snapshots written by the running app.
- The same day, opening `claude://resume?session=<id>` for a Remote Control
  session from 2026-10-17 that had no record made Claude Desktop 4.23118.1 write
  `local_<id>.json` (`adoptedFromOtherSurface` and `fromCliTranscript` true)
  within seconds and start the session. Claude Code 2.1.319 builds that link
  for `/desktop` and opens it with `open`.
- The same day, each of those four sessions was open in two processes at once
  (the server's child and a resumed copy), found through
  `~/.claude/sessions/<pid>.json` entries sharing one `sessionId`.

- On this Mac, the reference project's background sync logged 265–408 passes
  with changes per day (2026-11-02 to 2026-11-04), each rewriting 12–24
  records across 7 account/organization folders of about 1,995 records each.
- On 2026-11-05: 1,968 of 1,996 sessions were archived. Records had a median
  size of 200 KB, 519 MB per folder and 3.4 GB across the 7 folders. Of 538
  sessions returned by orchestrator searches, 68% were under 7 days old, 31%
  7–30 days, 1.3% 30–90 days and none older; all 5 unarchived sessions were
  under 7 days old. A 30-day archived window plus all active sessions came to
  487 records, 168 MB per folder.
- On 2026-11-05, 29 `deleted_<sessionId>` files (13 bytes each, a millisecond
  timestamp, dated 2026-07-22 to 2026-10-21) sat in 2 of the 7 folders, and
  none of those sessions had a record left in any folder.
