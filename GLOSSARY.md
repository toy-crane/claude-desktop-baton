# Glossary

Claude Desktop Baton moves one person's Claude accounts between Claude Desktop
and the Claude Code CLI on one Mac.

**Saved account**:
A Claude account (account and organization) the app keeps sign-ins for and can switch to.
_Avoid_: Profile

**Switch**:
The one-click change that makes a saved account the active one in Claude Desktop and, when its CLI sign-in is saved, in the CLI.
_Avoid_: Swap, login change

**Desktop sign-in**:
What makes Claude Desktop signed in to an account: its token cache entries and claude.ai cookies, kept encrypted as Claude stored them.

**CLI sign-in**:
The Claude Code CLI's own login for an account, from the default Keychain item and the account fields in `~/.claude.json`; separate from the Desktop sign-in.
_Avoid_: CLI token, credentials

**CLI account**:
The account the CLI is signed in to right now; it can differ from the account Claude Desktop is signed in to.

**Update notice**:
The dot on the menu bar item (the baton or the usage meter) and the "Update available" row in the panel that say a newer version of this app is ready to install; separate from Sparkle's update window, which opens only from it or from Check for Updates.
_Avoid_: Update alert, update popup
