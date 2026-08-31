---
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Re-papering writes one record per verb, fixing two ways it wrote records nobody asked it to (#28 items 9 and 10). Unlink released **every** contract the agreement superseded rather than the one whose button was clicked: the panel took the clicked ID and discarded it, calling `Contracts.Supersede` with `PredecessorID: null`, which the operation read as "release them all". And Link released every existing predecessor before adding the picked one, so linking a second contract silently unlinked the first and reported it as "Released CTR-0001."

`SupersedeInput` now names each target explicitly — `PredecessorID` adds one predecessor and leaves the rest alone, `ReleasePredecessorID` releases exactly the one named — and neither has a null sentinel meaning "all". A release is refused unless that contract is currently superseded by this agreement, so a stale list cannot clear an unrelated record, and re-linking a contract that is already linked stays a no-op. A contract may supersede many earlier agreements, which is the consolidation case the schema always allowed; removal is now only ever via Unlink.
