# An update that fails verification stays offered in the panel

**Symptom**: After Install… shows "Update Error! The update is improperly signed
and could not be validated." and the user chooses Cancel Update, the panel keeps
showing "Update available · <version>" with Install…, and every click ends in the
same error until a later check finds no update.

**Observed evidence**: 2026-11-07 end-to-end run of two Developer ID test builds
(0.3.0 → 0.3.1 from a local feed at `http://127.0.0.1:47812/appcast.xml`), then
a feed entry for 0.3.2 whose `sparkle:edSignature` was altered. The app stayed on
0.3.1 and showed the error; after cancelling, an accessibility snapshot of the
panel still listed `Update available · 0.3.2` and `Install…`.

**Suspected cause**: `AppUpdater` (Sources/ClaudeDesktopBaton/AppUpdater.swift)
clears the update notice only on Skip and on `updaterDidNotFindUpdate`; it does
not handle `updater(_:didAbortWithError:)`, so a verification or install failure
leaves the notice as it was. That delegate also fires for network failures,
where the spec wants the row kept, so it cannot simply clear on every abort.

**What was tried**: Nothing in code. The release script refuses to finish
without an EdDSA signature in `appcast.xml`, which makes a badly signed feed
unlikely in normal releases.

**Proposed next step**: Decide with the user whether a failed verification
should hide the row until a newer version appears; if so, clear the notice in
`didAbortWithError` only for Sparkle's signature/validation error codes
(`SUSignatureError`, `SUValidationError`) and add an `UpdateNotice` test for it.
