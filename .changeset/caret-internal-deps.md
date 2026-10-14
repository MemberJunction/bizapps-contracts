---
---

The packages' dependencies on each other are caret ranges (`^0.7.3`) instead of exact versions. A host that pins or overrides one package of this app at a later compatible version no longer forces an exact-match copy of its siblings. Changesets keeps the caret and moves its floor on each release.
