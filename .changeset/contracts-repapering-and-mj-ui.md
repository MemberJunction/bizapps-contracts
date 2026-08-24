---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Contracts can be re-papered, Order Form and Payment Link are back, and three hand-rolled panels are now MJ components.

**Re-papering (C-US9).** A contract can now name the agreement that replaces it, from the successor's
own form, while the successor is still being created. `SupersededByContractID` stays on the
PREDECESSOR — the direction was reviewed and kept, because one column there makes "superseded at most
once" structurally true, it lets several agreements consolidate into one, and it keeps `Superseded`
derivable from a column on the row the base view already projects rather than an `EXISTS` subquery on
the app's hottest read path. No `SupersedesID` was added: a second FK would store one relationship
twice, which is the defect D-19/R-18 removed when it deleted the stored `Status`.

The operation is two steps in one order — save the successor, then set the predecessor's field. A
`TransactionGroup` was tried and removed: it defers writes until `Submit()`, so the predecessor
validated against a successor that had an ID and no row, and the guard could not tell an unwritten
sibling from a bad reference. That ambiguity was the only thing making a genuinely missing contract
read as success.

**Supersession is scoped to the same level of the tree**, not to root contracts. "Root only" would
forbid a change order superseding another change order under one agreement — real, and the alternative
is deleting history — while still permitting a change order to claim it replaced the agreement it
hangs off. Type is deliberately unconstrained, so `Payment Link → Order Form` remains a legal upgrade.

**Self-reference is now checked in full, in one place.** `refuseSelfReferences` reports self-parent and
self-supersession unconditionally, comparing by value. Previously the cycle guard detected `A → A` and
declined to report it, deferring to the generated validator — and `ParentContractID → self` had no
other check at all. Those validators are LLM-authored and both emitted `===` on a `uniqueidentifier`,
so they miss two ids differing only in casing (MJ#3984). A rule worth checking is checked whole.

**Order Form and Payment Link are Active again**, reversing R-4's retirement. Both now require a
template, which their own descriptions already implied: each says its terms live in the Master
Agreement it references. Payment Link remains the only type with `RequiresExecutedDocument = 0` — the
reason that column exists, and what keeps a self-serve sale off the Awaiting-documents worklist.

**Three hand-rolled UI surfaces are gone.** Provisions, Modifications and the lineage children table
each re-implemented something MJ ships, and each lost functionality doing it. Provisions and
Modifications now use MJ's stock related-entity grid — which also fixes a silent clip, where a plain
table inside `Variant="related-entity"` had all 73 provisions in the DOM and only the first few
reachable, with no scrollbar to suggest otherwise. Lineage uses `mj-hierarchy-tree`, so the panel
declares a config instead of querying, and its nodes NAVIGATE: the old table could show a change
order's number and give no way to reach it.

`@memberjunction/ng-hierarchy-tree` is added as a peer at the same range as every other MJ peer, and
deliberately not pinned.
