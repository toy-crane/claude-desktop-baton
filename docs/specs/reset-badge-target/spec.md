# Reset badge target in the panel

Make the limit reset badge safe to aim at and recognizable as a control, so
reading an account's resets never costs an unwanted account switch. What the
badge shows and where it sits stays exactly as approved; only its target, its
hover feedback, and its focus marking change.

- [Approved prototype](prototype.html) governs the safe target, the hover fill,
  and the keyboard-only focus marking. Its account names and dates are
  illustrative.
- [Panel limit resets](../panel-limit-resets/spec.md) governs the badge itself:
  its placement, label, counting rules, expanded detail rows, and which group an
  account belongs to. This work reopens none of that.
- [Glossary](../../../GLOSSARY.md) defines Saved account and Limit reset.

The shipped build drew the badge with no hover feedback at all, although the
approved prototype gave it one. Restoring that feedback is part of this work,
not a new idea.

## Behavior

1. The badge keeps the placement, label, and expand-collapse behavior settled by
   Panel limit resets. This work changes nothing about what it reports.
2. The badge claims a safe area wider than its drawn border on every side. A
   click landing anywhere in that area opens or closes that account's resets,
   and never switches accounts.
3. While the pointer rests on the badge or its safe area, the badge fills with a
   shade clearly distinct from the row's own hover highlight. The row beneath is
   hovered at the same moment, so a fill matching the row's reads as no feedback
   at all.
4. The badge marks focus only when focus arrives from the keyboard. Opening the
   badge with the pointer leaves no marking behind once the click is done, and
   no marking persists until the panel closes.
5. Keyboard operation is unchanged: the badge takes focus in the panel's tab
   order, and Space or Return toggles the focused badge.

## Acceptance criteria

- Clicking up to 4pt outside the badge's drawn border opens that account's
  resets and leaves the signed-in account untouched. Clicking the account block
  anywhere further out still switches accounts as before.
- With the pointer on the badge, the badge's fill is visibly different from the
  hovered row behind it, in light and dark.
- Moving keyboard focus to the badge shows the accent marking. Clicking the
  badge with the pointer shows none, and once the click is done no badge in the
  panel carries a marking.
- Space and Return toggle the badge holding keyboard focus.
- The panel stays 300pt wide and each account block keeps the height it has
  today, give or take the badge's own small growth.
- An account with no usable grants still shows no badge and no safe area.

## Assumptions

These are agent-chosen defaults, overridable without reopening the behavior
above.

- The safe area reaches about 5pt past the drawn border on every side, which
  keeps it inside the account block's 10pt inset and clear of the account name.
- The badge's hover fill is one step denser than the row hover fill rather than
  a newly invented color.
- The drawn badge grows roughly 2pt taller. Its label text, font size, and
  corner radius stay as approved.

## Off-limits

Panel limit resets governs what the badge reports, where it sits, how the count
is derived, what the expanded rows contain, and which group an account belongs
to. This work changes only how the badge is aimed at and how it answers the
pointer and the keyboard, so none of that is revisited here.

## Deferred

- Whether the whole top-right corner of an account block should be excluded from
  the switch target, beyond the badge's own safe area. Interim behavior, until
  that is decided: only the badge's safe area is excluded, as stated in Behavior
  2.

## Remaining risks

- Apple publishes no minimum pointer target size for Mac, so the cushion is a
  judgement verified in a browser prototype rather than measured against a
  guideline. Real trackpad use may still show it is too tight.
- Hover and keyboard-only focus were verified in a browser, where
  `:focus-visible` separates keyboard focus from pointer focus for free. AppKit
  and SwiftUI offer no equivalent for a view made focusable this way, so the
  behavior in Criterion 3 has to be confirmed on a real build before this is
  considered met. If it cannot be matched, releasing focus when the pointer
  leaves the account block is the fallback, and it should be confirmed rather
  than assumed.

## Setup before implementation

None.
