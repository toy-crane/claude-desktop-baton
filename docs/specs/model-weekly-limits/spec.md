# Model weekly limits in the panel

Besides the Session and Week limits, Claude now gives some plans a weekly
limit for one model (today: Fable, "Up to 50% of your weekly limit"). The panel
shows that limit for each saved account, so the user can tell whether an
account still has room for that model before switching to it.

- Product contract this extends: [claude-desktop-baton](../claude-desktop-baton/spec.md)
  (usage rules, refresh schedule, panel layout, failure display). This spec
  states only what changes: a third meter under Session and Week when an
  account has a model weekly limit. Everything else stays as written.
- Menu bar: [menu-bar-usage](../menu-bar-usage/spec.md) is unchanged by this
  spec.
- Terms: [GLOSSARY.md](../../../GLOSSARY.md) (Saved account).

## Evidence

Checked 2026-11-11 against the signed-in account, with a scratch program
outside the repository making the same claude.ai usage request the app already
makes (`/api/organizations/<org>/usage`):

- The response carries a `limits` list. Besides `kind: "session"` and
  `kind: "weekly_all"`, it holds an entry with `kind: "weekly_scoped"`,
  `scope.model.display_name: "Fable"`, `percent: 24`, and `resets_at` equal to
  the Week reset.
- `weekly_scoped_shares` holds `allowance_percent_of_weekly: 50` for that
  entry (by `limit_index`), which is Claude's "Up to 50% of your weekly limit".
- The older per-model fields (`seven_day_opus`, `seven_day_sonnet`) were null.
- These numbers matched Claude's own usage screen at the same moment (Fable
  24% used, up to 50%, resets Thu 11:00 AM).

The endpoint is undocumented, as it already is for Session and Week; field
names may change without notice.

## User-visible outcomes

- In the panel, an account with a model weekly limit shows a third meter under
  Week, labeled with the model's name ("Fable"), with its percent used.
- Accounts without such a limit look exactly as they do today.
- The menu bar item does not change.

## Scope

In:

- A meter per model weekly limit, for every saved account in the panel (the
  signed-in account and the "Switch to" list).
- Its reset time and allowance on hover, like the other meters.

Out:

- The menu bar item, in every style and layout (user decision: keep it small).
- Extra usage, credits, spend, and any other field of the response.
- Alerts, switching, and refresh timing.

## Behavior

1. **Which limits** — every `weekly_scoped` limit in the response that names a
   model gets one meter, in the order the response lists them. A scoped limit
   without a model name is not shown.
2. **Label and value** — the label is the model's display name as Claude sends
   it (no name is hard-coded). The percent is the limit's own percent used,
   the same number Claude's usage screen shows ("24%"), written like the other
   meters.
3. **Hover** — the account's hover text adds the model limit's reset and its
   allowance, e.g. "Fable resets Thu 11:00 AM · up to 50% of Week". When the
   allowance is missing, only the reset is shown.
4. **Reached limit** — at 100% its bar and number turn red, as for Session and
   Week.
5. **No such limit** — an account whose last successful response has no model
   weekly limit shows only Session and Week; no empty third meter.
6. **Failed refresh** — when usage cannot be fetched, a model meter that the
   account had before shows "—" and an empty bar, like Session and Week; the
   existing failure indicator explains why.
7. **At launch** — model meters appear from saved usage before the first
   refresh, as Session and Week do.

## Acceptance criteria

1. For an account whose response holds a `weekly_scoped` Fable limit at 24%,
   the panel shows "Fable" with 24% under Week, and the bar a quarter full.
2. For an account whose response has no `weekly_scoped` entry, its panel block
   is identical to today's.
3. A response with two model limits shows two meters, in response order, each
   with its model's name.
4. A model limit at 100% is red; one below 100% is not.
5. Hovering an account with a Fable limit shows its reset time and "up to 50%
   of Week".
6. After a failed refresh, a previously shown Fable meter reads "—" with an
   empty bar.
7. Quitting and relaunching the app while offline still shows the last Fable
   value (from saved usage) before any refresh succeeds.
8. The menu bar item, in every style, is unchanged with and without a model
   limit.
9. A response missing `limits` or holding unexpected values there still shows
   Session and Week as today (the model meter is simply absent).

## Settled constraints

- **Panel only** (user decision): the menu bar stays at Session and Week.
- **Read from the response the app already fetches**: no extra request per
  refresh.

## Assumptions (agent-chosen, overridable)

- The meter shows the model limit's own percent (24%), not its share of Week
  (12%), because that is what Claude shows and what reaches 100% when the
  model is blocked.
- The label is the model name alone ("Fable"), matching "Session" and "Week";
  the "up to 50%" note goes to hover to keep the block compact.
- When Week reaches 100% the user is blocked for every model regardless; the
  Fable meter still shows its own value as received.

## Deferred

None.

## Remaining risks

- The `limits` list and its field names are undocumented and may change; the
  meter would then disappear quietly (criterion 9) rather than show wrong
  numbers.
- A third meter makes each account block taller; with many saved accounts the
  panel grows accordingly.

## Setup before implementation

None.
