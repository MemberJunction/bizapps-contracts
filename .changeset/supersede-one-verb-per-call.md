---
'@mj-biz-apps/contracts-core-entities-server': patch
---

`Contracts.Supersede` now refuses a call carrying both `PredecessorID` and `ReleasePredecessorID`.

With the same id in both fields it used to release the contract and re-link it inside one request, then report both outcomes: `Released: ['CTR-0001']` came back alongside a `Supersedes` list that still contained CTR-0001, and the row took two writes, so the audit trail records a release that never held. With two different ids it worked, and is refused anyway — releasing one contract while linking another is two decisions in one request, and the Re-papering panel sends one verb at a time.

The guard runs before anything is loaded, so a rejected call reads and writes nothing.
