# Usage in the menu bar

The menu bar item shows the signed-in account's usage at a glance, so the user
knows how much of the current session is left without opening the panel.

- Product contract this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  (usage rules, refresh schedule, panel). This spec states only what changes:
  the menu bar item described there as "a menu bar icon" that "shows a spinner"
  while switching.
- Prototype: [prototype.html](prototype.html) governs how the item looks in
  each state below, on light and dark menu bars, at actual size and enlarged.
  Its state names match the "Behavior" list here.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Saved account, Switch).

## User-visible outcomes

- Without opening the panel, the user sees in the menu bar how much of the
  signed-in account's Session (5-hour) and Week limits is used, and the
  Session percent as a number.
- When a limit stops the user, the menu bar shows how long until they can use
  Claude again, instead of a percent that would look like room to spare.
- When usage cannot be refreshed, the last known usage stays visible, dimmed,
  so it reads as not current.

## Scope

In:

- The menu bar item's content in every state below.

Out:

- The panel. Its layout, meters, "—" on a failed fetch, and reset notes stay as
  they are.
- Any setting for the menu bar item. There is no toggle back to the icon-only
  item (user decision).
- Showing other saved accounts, the CLI account, or an account picker in the
  menu bar.
- Color. The item stays monochrome.

## Behavior

The item shows the account in the panel's "Signed in" section, that is, the
account Claude Desktop is signed in to.

The item is a meter followed by a text:

- **Meter**: two horizontal bars stacked. The top, thicker bar is the Session
  limit; the bottom, hairline bar is the Week limit. Each fills from the left in
  proportion to its percent used, over a faint track.
- **Text**: the Session percent, written as the panel writes it (`0%`, `<1%`,
  `42%`, `100%`).

States:

1. **Usage known, no limit reached**: meter at both percents; text is the
   Session percent (`42%`, `<1%`, `91%`).
2. **Session limit reached**: top bar full; text is `↻` and the time until the
   Session limit resets, in the panel's format (`↻ 1h 12m`).
3. **Week limit reached, Session not**: bottom bar full; text is `↻` and the
   time until the Week limit resets (`↻ 2d 3h`), not the Session percent.
4. **Both limits reached**: both bars full; text is `↻` and the later of the two
   reset times, the moment the user can use Claude again.
5. **Switching** (including an account add in progress): the existing turning
   spinner replaces the meter and text, as today. When the switch ends, the item
   shows the new signed-in account's usage.
6. **Usage could not be refreshed** (offline, sign-in expired, Keychain
   refused, claude.ai refused or returned something unexpected): the item keeps
   the last usage it showed for this account, meter and text, dimmed. When a
   refresh succeeds it returns to full strength.
7. **No usage received yet for this account**: dimmed empty meter and `—`.
8. **Signed-in account not saved, or Claude signed out, or no saved accounts**:
   the baton icon alone, as today.

Usage refreshes on the existing schedule (every 2 minutes, and when the panel
opens if older than 1 minute). Clicking the item opens the panel as today.

## Acceptance criteria

1. With the signed-in account at Session 42% and Week 18%, the menu bar shows a
   top bar filled to about 42%, a bottom hairline filled to about 18%, and
   `42%`, without opening the panel.
2. The item's percent matches the "Signed in" account's Session percent in the
   panel at the same moment.
3. With Session at 100%, the text is `↻` followed by the time until the Session
   reset, matching the reset time the panel shows for that account.
4. With Week at 100% and Session below 100%, the text is `↻` followed by the
   time until the Week reset, and no percent is shown.
5. With both at 100%, the text shows the later of the two reset times.
6. During a switch the item shows the spinner only; within 2 minutes after the
   switch completes it shows the target account's usage.
7. With the network off after a successful fetch, the item still shows the last
   values, visibly dimmed; after the network returns and a refresh succeeds, it
   is no longer dimmed.
8. With the signed-in account not saved, the item shows the baton icon alone.
9. On light and dark menu bars, and when the item is highlighted while the
   panel is open, the meter and text stay legible.
10. The panel looks and behaves as before.

## Settled constraints and rationale

- **Two-bar meter, not the baton, beside the number.** Next to a number the
  baton does not say what the number measures; a meter does, the way the
  battery glyph does for its percent. Researched references (CodexBar, Claude
  Usage Tracker, Usage4Claude, claude-meter, ClaUse Bar, ClaudeUsageBar) mostly
  make the glyph itself read as a usage gauge. Rejected: baton + percent,
  baton + `5h 42%` label, a ring gauge around the baton (reads as a "no entry"
  sign when nearly full), two stacked lines of text (too small to read at a
  glance).
- **Both bars stay, in this order.** The user chose two bars over a single
  Session bar, accepting that which bar is which is learned rather than
  self-evident. Top thick = Session, bottom hairline = Week, as in CodexBar.
- **The text means "how much can I use now".** A percent while usable; once any
  limit stops the user, the time until usable again. A Session percent shown
  while the Week limit is reached would suggest room that does not exist.
- **Dimmed last value on failure, not a warning glyph.** Most failures are brief
  (sleep, Wi-Fi drop) and clear on the next refresh; a warning glyph would flash
  each time and hide still-useful numbers. A small badge beside full-strength
  values was rejected because the values would read as current. The reason
  stays in the panel's hover indicator.
- **No setting to turn it off** (user decision).
- **Monochrome.** The item adapts to light and dark menu bars and the
  highlighted state like the current icon; red stays a panel-only signal.

## Assumptions (overridable)

- The meter is about the width of the current icon (about 18 pt); the top bar
  is clearly thicker than the hairline.
- Digits are tabular so the item does not shift as the percent changes; the
  item still widens when the text becomes a reset time.
- The reset countdown updates at least once a minute.
- If a reached limit has no reset time, the text shows `100%`.
- "Last usage it showed" includes usage cached from before the app restarted,
  when the app has it; otherwise state 7 applies until the first fetch.
- The item's accessibility label states the usage in words, for example
  "Claude Desktop Baton: Session 42%, Week 18%", or the reset time when a limit
  is reached.

## Off-limits

- The panel and its usage rules: out of scope, and the user reviewed only the
  menu bar item. The panel keeps showing "—" on a failed fetch even while the
  menu bar shows a dimmed last value.
- Switching, CLI, and session-sync behavior: unrelated to this change.

## Deferred

None.

## Remaining risks

- On a crowded menu bar, especially beside the notch, a wider item may push
  other items out of view, and there is no setting to shrink it.
- The two bars are not labeled; a new user learns which is which from the
  panel. Accepted by the user.
- A dimmed value can be hours old if failures persist (for example, the saved
  sign-in expired); only the panel says why.

## Setup before implementation

None.
