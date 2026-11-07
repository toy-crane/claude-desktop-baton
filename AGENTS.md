# Agent instructions

<!-- BEGIN stack-context: Sparkle -->
## Sparkle (app updates)

Sparkle is the app's update framework; its version is pinned in `Package.swift`.
It publishes no agent skill or `llms.txt`. When work touches update checks,
update alerts, the appcast, update signing, or how the release scripts embed and
sign `Sparkle.framework`, read the current official documentation first:

- https://sparkle-project.org/documentation/ (setup, publishing, gentle
  reminders, customization, API reference)
- https://github.com/sparkle-project/Sparkle/releases (release notes)

Reconcile what the documentation says with the version pinned in
`Package.swift`, and check the headers of that tagged version when the two
disagree.
<!-- END stack-context: Sparkle -->
