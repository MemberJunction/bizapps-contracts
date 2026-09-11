---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-ng': minor
---

Three fixes to what the contract form asserts and what it lets you type (#28 items 16, 18 and 20).

**"Awaiting document" cleared as soon as any file was linked**, so an exhibit, a draft or the wrong PDF silenced the warning — the system could not tell the executed agreement from a scan of a business card, which makes the chip worse than absent. `vwContracts.IsAwaitingDocument` now requires a linked file carrying MJ's file category **Executed Agreement**, and the migration seeds that category idempotently by name. A category rather than a column on `Contract`, because ERD R-8 ships no `ExecutedDocumentFileID` FK and "what kind of document is this" is a property of the file.

**Contract Number, Has Modifications and Superseded By Contract** rendered as editable inputs even though the server assigns all three — the number is minted under a lock, the flag is settled in `ValidateAsync()`, and the supersession FK is written only by `Contracts.Supersede` on the successor, so editing it here sets the opposite direction from the Re-papering panel. All three are now read-only. Parent Contract stays editable, as item 11 requires.

**The term countdown** appeared in both the header and the Dates tab, computed separately in each. The header keeps it.

The migration re-creates `vwContracts` in full, as `CREATE OR ALTER` requires, so it also carries forward the inclusive `Terminated` boundary that item 13 set in `V202608300100`. Sorting later than that file, it would otherwise have reverted it.

Minor: the branch carries a versioned migration.
