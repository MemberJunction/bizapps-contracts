---
'@mj-biz-apps/contracts-core-entities-server': patch
---

`Contracts.Supersede` refuses a call that both links and releases.

The two branches share a single pre-release snapshot of the predecessor list — release checks its target is in it, link checks its target is not — so passing the same id as `PredecessorID` and `ReleasePredecessorID` released the contract and then skipped the link, having found it in a list taken before the release. The caller asked for a link and got none, silently. Both inputs set is now refused before anything is read, so a rejected call writes nothing. Refused rather than ordered: releasing X while linking Y is two decisions in one request, and the panel sends one verb at a time.
