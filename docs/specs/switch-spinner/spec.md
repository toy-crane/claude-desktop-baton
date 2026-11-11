# Turning spinner while switching

While a switch runs, the menu bar item visibly turns, so the user can tell at a
glance that the app is still working and when it has finished.

- Product contracts this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  ("While switching, the icon shows a spinner") and
  [menu-bar-usage](../menu-bar-usage/spec.md) (Behavior 5, "Switching",
  including an account add). Both already promise a turning spinner; this spec
  makes it actually turn and narrows when it shows during an account add.
  Everything else in those specs stays as written.
- Decision contract that applies: [agent-cli](../../decisions/agent-cli.md) —
  a switch asked for on the command line shows the same spinner as a click.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Switch, Saved account, Update notice).

## Why

The spinner promised since the first release never moves. The menu bar item
draws a still picture of the turning-arrows symbol, so during a switch (often
10–30 seconds while Claude quits, sessions sync, and Claude reopens) the user
sees an icon that looks frozen and cannot tell whether the app is working or
stuck.

Evidence (checked 2026-11-11 on macOS 27.2, in a scratch app outside the
repository): a `MenuBarExtra` label given a symbol with a rotate symbol effect
is rendered as one still image on the status item button, with no animation
attached. A label whose image is replaced on a timer (10 frames per second)
does update in the menu bar. The fix therefore cannot rely on SwiftUI symbol
effects in the label; that would reopen only if a later macOS animates
`MenuBarExtra` labels.

## User-visible outcomes

- During a switch, the menu bar item shows the turning-arrows icon and it
  keeps turning, smoothly and continuously, until the switch ends.
- When the switch ends (succeeded or failed), the turning stops before any
  result alert appears, and the item returns to what the chosen menu bar
  style shows for the now signed-in account.
- During an account add, the icon turns only while the app itself is working
  (signing Claude out, quitting and reopening it). Once Claude has reopened
  signed out and is waiting for the user to sign in, the item looks as it does
  when idle, so "the app is busy" and "it is your turn" look different.

## Scope

In:

- The menu bar item's look during a switch, a Put Back switch, a switch
  started from the command line, and the working part of an account add.

Out:

- Step-by-step progress text in the menu bar or the panel (user chose the
  turning icon alone; the item keeps one fixed width throughout a switch).
- The panel. While a switch runs it keeps showing the target row with its
  spinner and every row and action disabled, as specified.
- What the panel allows while an account add waits for sign-in (rows and
  actions stay disabled until the new account is saved or 15 minutes pass,
  as today).
- Alerts, switch steps, timing, and the CLI.

## Behavior

1. **Switch in progress** — from the moment a switch starts (panel click,
   confirmed alert, Put Back, or command line) until it ends, the item shows
   only the turning-arrows icon, in every menu bar style (icon, usage, icon and
   usage; any layout). It turns continuously; no frame holds still long enough
   to look stuck.
2. **Switch ends** — the turning stops and the item shows the signed-in
   account's usage (or the baton) per the chosen style, before any result
   alert ("Switched to …", "Couldn't switch to …") opens.
3. **Account add, app working** — while the app signs Claude out and restarts
   it, the item turns as in 1.
4. **Account add, waiting for sign-in** — once Claude has reopened signed out
   and the "Sign in to another account" alert is shown, the item stops turning
   and shows what it shows when idle with no account signed in (the baton). If
   adding fails before that point ("Couldn't sign Claude out"), it stops as in 2.
5. **Accessibility** — while turning, the item is announced as switching, as
   today.

## Acceptance criteria

1. During a switch, two screenshots of the menu bar item taken about 0.2
   seconds apart show the arrows at different angles, at any point from start
   to end of the switch.
2. The item turns for a switch started from the panel, from the confirm alert,
   from Put Back, and from `claude-desktop-baton switch`.
3. With each menu bar style (icon; usage in columns, bars, stack; icon and
   usage), the item during a switch is the turning-arrows icon alone, and its
   width does not change while it turns.
4. When a switch ends, the item has stopped turning by the time the result
   alert is on screen, and shows the signed-in account per the chosen style.
5. During an account add, the item turns until the "Sign in to another
   account" alert appears, then shows the baton and does not turn while the
   app waits for sign-in.
6. With no switch or add in progress, the item never turns, and the app does
   not redraw it more often than it does today.
7. VoiceOver reads the turning item as switching.

## Settled constraints

- **Turning icon only, no step text** (user decision): the menu bar keeps one
  narrow, fixed width during a switch and does not push other items around.
- **Turn only while the app is doing work** (user decision): waiting for the
  user to sign in during an account add is shown as idle, not as loading.
- **Must actually move in the menu bar**: an animation that runs only in a
  SwiftUI view but not in the status item does not satisfy this spec (see
  Evidence above).

## Assumptions (agent-chosen, overridable)

- Speed is about one full turn per second, in the clockwise direction the
  symbol's arrows point, monochrome like the rest of the item.
- The update notice's dot is not drawn while turning (as today); it returns
  with the idle item.
- With macOS "Reduce motion" on, the icon still turns; it is the only sign of
  progress and is small. Revisit if a user asks for a still icon.
- The animation stops cleanly if the app quits mid-switch; nothing is
  persisted.

## Deferred

None.

## Remaining risks

- A later macOS may change how menu bar items accept image updates; the
  per-frame approach was verified on macOS 27.2 only.
- Redrawing the item many times per second for up to ~30 seconds uses a little
  CPU; acceptance criterion 6 guards that it never runs while idle.

## Setup before implementation

None.
