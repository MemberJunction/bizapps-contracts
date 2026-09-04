---
'@mj-biz-apps/contracts-ng': patch
---

The Source stat hides itself when the provenance names a record that does not exist.

`CreatingEntityID`/`CreatingRecordID` can point at nothing — a hand-typed pair, a deleted row — and the stat rendered an "Open" button that navigated nowhere. A link that cannot work is worse than an absent stat: it invites a click and spends the reader's trust.

The fix distinguishes two cases the code had conflated. A name read that **succeeds and matches nothing** means the record is not there, so the stat hides. A read that **throws** means the record may exist and simply be unreadable by this user, so the link stays and the value falls back to "Open" — which is what the original fallback was written for. Treating both as "no name" is what made a dead button look deliberate.
