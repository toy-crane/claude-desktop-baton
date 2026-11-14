# Limit resets in the panel

Show the reset grants each saved account can use, so the user can see which
account has a reset available without switching accounts or opening Claude.

- [Approved prototype](prototype.html) governs the badge placement and the
  expanded details. Its account names and dates are illustrative.
- [Panel columns](https://github.com/toy-crane/claude-desktop-baton/blob/d0c5d52/docs/specs/panel-columns/spec.md)
  governs the usage blocks. [Switch to order](https://github.com/toy-crane/claude-desktop-baton/blob/d0c5d52/docs/specs/switch-to-order/spec.md)
  governs the separate Week limit reached group.
- [Glossary](../../../GLOSSARY.md) defines Saved account and Limit reset.
- [Claude's limit reset guide](https://support.claude.com/en/articles/17007452-what-is-a-limit-reset)
  explains the grant types and what each restores.

## Behavior

1. Show a compact badge beside the account name when Claude reports at least
   one usable, unexpired reset for that account. Show the sum of the remaining
   uses, with singular and plural labels such as `1 reset` and `2 resets`.
2. Clicking the badge toggles details in that account's row. Show each usable
   reset type, its remaining uses, and its expiry in the Mac's local time when
   Claude provides one. The badge and its details are separate click targets
   from switching accounts.
3. Use the same badge and details in Signed in, Switch to, and Week limit
   reached. A grant does not change which group an account belongs to. Fable
   can restore Fable usage without restoring the whole weekly allowance.
4. Hide the badge after the last usable grant passes its expiry or a refresh
   confirms that no usable grants remain. An unavailable grant reading does
   not represent a count of zero. If the grant reading is unavailable, hide
   the count and keep displaying any independently available usage meters.
5. The panel shows grant availability only. Actual redemption stays in
   Claude's Settings → Usage.

## Acceptance criteria

- A saved account with one Full reset and one Fable reset shows `2 resets`.
  Opening it reveals two entries with their own counts and expiry times.
- Clicking either a full account row's badge or a Week limit reached row's
  badge does not switch accounts. A Week limit reached row keeps its scheduled
  reset time visible.
- An account with no usable grants has no badge. Expired or currently
  unusable grants do not inflate the count. An unavailable grant reading
  does not suppress otherwise available usage meters.
- The layout fits the existing 300-point panel in light and dark. The badge
  can be opened and closed using the keyboard.

## Assumptions

- Details start collapsed when opening the panel.
- For an unfamiliar grant type, show Claude's label when available without
  guessing what it restores.

## Remaining risks

The read-only reset query returned grant data in a signed-in browser and
with four of Baton's saved Desktop sign-ins. An account without grants and
a rejected reset query were verified with test responses. Claude does not
document the response as a public API. If it changes, usage meters should
keep working. Revisit this data source if Claude offers a documented read API.

## Setup before implementation

None.
