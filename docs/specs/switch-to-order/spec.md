# "Switch to" order and accounts out of Week

The "Switch to" list shows saved accounts in the order they were saved, and an
account whose Week limit is used up looks like any other: the user has to read
every block to find one they can actually move to. This change lists accounts
by name and moves the ones whose Week limit is at 100% into a short group at
the bottom, one line each with the time the limit resets.

- Product contract this changes: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  (panel section: "Switch to" lists accounts "in the order they were saved";
  settled constraint "Accounts are listed in the order they were saved, not
  sorted by usage"). Both are replaced by the order below. Everything else in
  that panel section stays as written.
- Layout: [panel-columns prototype](../panel-columns/prototype.html) still
  governs how an account block looks (name, limit columns, dividers, hover,
  switching, light and dark). This spec adds only the bottom group and its
  one-line rows.
- Command line: [agent-cli](../agent-cli/spec.md) says `accounts` lists
  accounts "in panel order"; see Behavior 8.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Saved account, Switch).

## User-visible outcomes

- Accounts under "Switch to" appear in name order, so the user finds an
  account where they expect it.
- Accounts whose Week limit is used up sit apart at the bottom under "Week
  limit reached", each on one line with when it resets, so the accounts above
  are the ones the user can work in now.
- The panel gets shorter when accounts are out of Week, because those rows
  drop their limit columns.

## Scope

In:

- The order of accounts under "Switch to".
- The "Week limit reached" group and its one-line rows, in light and dark and
  in the switching state.
- The order of `claude-desktop-baton accounts` and of the "Remove account ›"
  menu.

Out:

- The "Signed in" section: the signed-in account stays at the top in its full
  block even when its Week limit is at 100% (its Week column is red, as today).
- The menu bar item.
- What usage is fetched or when, meter values, hover text, alerts.
- Panel width, colors, and the column layout itself.

## Behavior

1. **Name order** — accounts under "Switch to" are sorted by their display
   name (the name the panel shows, e.g. "Acme · sam", "Personal"), the way
   Finder sorts file names: letter case is ignored, and numbers inside a name
   compare by value, so "toycrane", "toycrane 1", "toycrane 2", "toycrane 3",
   "toycrane 4", … "toycrane 10" (a name comes before the same name followed
   by a number, and 10 after 9). Accounts with the same display name cannot
   occur (display names are already made unique).
2. **Out of Week** — an account is out of Week when its last successfully
   fetched Week limit is at 100% and its Week reset time has not passed yet.
   Nothing else counts:
   - Session at 100% keeps the account in the main list (it resets within
     hours); its Session column is red, as today.
   - A model limit (e.g. Fable) at 100% keeps the account in the main list;
     other models can still be used.
   - An account whose usage could not be fetched, or has never been fetched,
     stays in the main list with "—" as today.
   - Once the Week reset time passes, the account returns to the main list
     right away, even before the next refresh confirms it.
3. **Main list** — the accounts that are not out of Week, in name order, as
   full blocks exactly as today.
4. **Bottom group** — after the main list, a small uppercase label "WEEK LIMIT
   REACHED" (same style as "SWITCH TO"), then the out-of-Week accounts in name
   order. The group and its label appear only when at least one account is
   out of Week.
5. **One-line row** — the account name on the left (lighter weight than a
   full block's name), and "↻ <reset>" on the right in muted text, written as
   the Week column writes it ("↻ Fri 9:18 PM"). No limit columns, no bars, no
   percent. A long name ends with "…" so the reset stays visible. The CLI tag
   stays beside the name when the CLI is signed in to that account. Hover text
   is the same as the account's full block.
6. **Still switchable** — a one-line row highlights on hover and switches on
   click, with the same confirmation rules as any other account. While a
   switch runs, the target row shows the spinner before its name and the other
   rows dim, as for full blocks.
7. **Moving between groups** — after each refresh (and when a reset time
   passes) accounts move between the main list and the bottom group. When
   every other account is out of Week, the main list is empty and only the
   bottom group shows under "Switch to".
8. **Elsewhere** — `claude-desktop-baton accounts` lists every saved account
   by display name in the same name order (no grouping by usage; it does not
   report usage). The "Remove account ›" menu lists accounts in the same name
   order.

## Acceptance criteria

1. With other accounts "Studio", "Acme · sam", and "personal" (none out of
   Week), "Switch to" shows "Acme · sam", "personal", "Studio".
1a. With other accounts "toycrane 2", "toycrane 10", "toycrane", "toycrane 1"
   (none out of Week), "Switch to" shows "toycrane", "toycrane 1",
   "toycrane 2", "toycrane 10".
2. With "Acme · jordan" at Week 100% resetting Fri 9:18 PM, it appears under
   "WEEK LIMIT REACHED" at the bottom as one line reading "Acme · jordan" and
   "↻ Fri 9:18 PM", with no bars.
3. Two out-of-Week accounts in the bottom group are in name order.
4. An account at Session 100% and Week 62% stays in the main list as a full
   block with a red Session column.
5. An account at Fable 100% and Week below 100% stays in the main list.
6. An account whose usage failed to load stays in the main list showing "—".
7. With no account out of Week, there is no "WEEK LIMIT REACHED" label.
8. Clicking a one-line row starts a switch to that account (or asks first when
   sessions are working), and the row shows the spinner.
9. An account whose Week reset time has passed moves back to the main list
   without waiting for a refresh.
10. The signed-in account at Week 100% stays under "Signed in" in its full
    block.
11. `claude-desktop-baton accounts` and "Remove account ›" list accounts in
    name order.
12. Light and dark both show the bottom group legibly.

## Settled constraints

- **Name order, not save order** (user decision, 2026-11-11): replaces the
  original "order they were saved" rule.
- **Out-of-Week accounts go to a separate bottom group, one line each**
  (user decision, 2026-11-11; option C of three compared: dimmed in place,
  bottom group of full blocks, bottom group of one-line rows). Reason: once
  Week is used up, the only thing worth reading is when it resets, and full
  blocks would keep the panel long for accounts the user cannot use.
- **Only Week counts** as "cannot be used": Session resets within hours and a
  model limit blocks only that model.

## Assumptions (agent-chosen, overridable)

- Out-of-Week accounts stay clickable; someone may want Claude Desktop on that
  account for things other than new usage.
- The bottom group is ordered by name rather than by soonest reset, so there
  is one ordering rule.
- The one-line row shows only the reset, not "Week 100%"; the group label
  already says why the account is there.
- The command line keeps a plain name order without grouping, since `accounts`
  shows no usage.

## Deferred

None.

## Remaining risks

- Accounts move between groups after a refresh, so an account can jump while
  the panel is open; the user may click a different row than intended if a
  refresh lands mid-click.
- The Week limit comes from Claude's undocumented usage response, as before;
  if it stops arriving, no account is treated as out of Week (they all stay in
  the main list showing "—").

## Setup before implementation

None.
