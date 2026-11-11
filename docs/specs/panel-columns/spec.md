# Panel limits in columns

The panel's accounts read as one long list today: account names are about the
same size and weight as the limit names under them, and accounts are separated
only by space. With a model limit (Fable) added, each account got taller and
the list got harder to scan. This change lays each account's limits out side
by side, so every account is one short, distinct block and the percents are
the first thing the eye lands on.

- Prototype: [prototype.html](prototype.html) is the approved layout (option C
  of three compared on 2026-11-11). It governs how the panel looks: type
  sizes, spacing, column layout, dividers, the switching state, light and
  dark. Its sample data is illustrative.
- Product contracts this changes: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  (panel section: "a Session bar and a Week bar, each with its percent") and
  [model-weekly-limits](../model-weekly-limits/spec.md) ("a third meter under
  Week"). What each meter shows, its failure and reached-limit rules, hover
  text, sections, and footer stay as those specs say; only the arrangement and
  labels change here.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Saved account, Switch).

## User-visible outcomes

- Each account in the panel is a compact block: its name, then its limits in
  equal-width columns next to each other.
- Within a column the percent is the largest text, so the user can compare
  accounts at a glance.
- Accounts in "Switch to" are separated by a thin line, so one account's
  limits never read as the next account's.

## Scope

In:

- The layout of every account block in the panel ("Signed in" and "Switch
  to"), in light and dark, in every state the panel already has (normal,
  hover, reached limit, usage unavailable, switching, CLI tag).
- The panel screenshots in the README (`docs/images/panel-light.png`,
  `panel-dark.png`), regenerated so they match.

Out:

- The menu bar item.
- What usage is fetched or when; meter values, hover text, alerts.
- Section labels ("Signed in", "Switch to"), the update row, and the footer.
- Panel width (stays 300 points) and colors (monochrome, red only for a
  reached limit).

## Behavior

1. **Header** — the account name on its own line, larger and bolder than any
   limit label (the signed-in account larger again, with its email under it).
   The CLI tag and the usage-failure indicator stay beside the name.
2. **Columns** — under the header, one column per limit, in this order:
   Session, Week, then each model limit in the order the response lists them.
   Columns share the block's width equally.
3. **Column content**, top to bottom: a small uppercase label ("SESSION",
   "WEEK", or the model's name such as "FABLE"); the percent used, the
   largest text in the block apart from the name; the bar; the time until it
   resets ("↻ 4h 40m", "↻ Fri 9:13 PM"), small and muted.
4. **Labels** — "5-hour limit" and "Weekly" become "SESSION" and "WEEK",
   matching the menu bar's 5H/WK and the glossary's "Session" and "Week".
5. **Long text** — a reset or model name too long for its column ends with
   "…" on one line; the full reset stays in the account's hover text.
6. **Reached limit** — that column's percent and bar are red.
7. **Usage unavailable** — the percent reads "—", the bar is empty, and no
   reset is shown, as today.
8. **Dividers** — a hairline between accounts in "Switch to"; it is hidden
   next to an account the pointer is over, so the hover highlight reads as one
   shape.
9. **Switching** — the target account shows the spinner before its name; every
   other account and the footer action are dimmed, as today.

## Acceptance criteria

1. With two limits, an account block shows SESSION and WEEK side by side, each
   with label, percent, bar, and reset, in the prototype's arrangement.
2. With a model limit, a third column (labeled with the model name) appears to
   the right of WEEK, and all three columns are the same width.
3. An account name is visibly larger and bolder than every limit label in the
   panel.
4. Each pair of adjacent "Switch to" accounts has a hairline between them;
   hovering one shows its highlight without a line cutting through it.
5. A reached limit's percent and bar are red; nothing else is red.
6. An account whose usage could not be fetched shows "—" and empty bars with
   no reset.
7. During a switch the target shows the spinner and the others are dimmed.
8. In light and dark, nothing overflows the 300-point panel: with three
   columns and a long reset ("↻ Mon 12:45 PM"), the reset ends in "…" rather
   than overlapping the next column.
9. The README panel screenshots show the new layout.

## Settled constraints

- **Layout C, limits in columns** (user decision, from a three-way comparison
  against cards and dividers).
- Monochrome and 300 points wide, as before.

## Assumptions (agent-chosen, overridable)

- More than three limits (not seen today) wrap to a second row of columns
  rather than shrinking every column further.
- The signed-in account keeps its larger name and email; it gets no divider of
  its own beyond the existing rule between sections.
- Percent text is about 15 points; labels and resets about 9.5–10.5 points,
  as in the prototype.

## Deferred

None.

## Remaining risks

- Three columns in 300 points leave about 80 points per column; weekday resets
  in some locales may truncate often. The hover text still carries them.

## Setup before implementation

None.
