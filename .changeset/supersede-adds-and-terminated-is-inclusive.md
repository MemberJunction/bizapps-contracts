---
'@mj-biz-apps/contracts-core-entities-server': minor
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-ng': patch
---

Re-papering: linking adds, releasing targets one contract. Terminated is inclusive of its date. End Date is validated in words.

The first four items of contracts#28, all in the same area of the form.

**`Contracts.Supersede` no longer replaces (items 9 and 10).** Two reported defects turned out to be
opposite halves of one wrong idea, and it was a deliberate one — `SupersedeOperation` argued REPLACE,
NOT ADD from the fact that the picker is a single-select. So linking CTR-0002 quietly released
CTR-0001, and clicking "Unlink CTR-0001" released every predecessor, because the panel passed the
clicked ID to a handler that discarded it. A contract may legitimately supersede several earlier ones,
so **linking now adds** and leaves existing predecessors alone, and **releasing takes an explicit
`ReleasePredecessorID`** that clears exactly the contract named. The module's docstring is rewritten
rather than left arguing the old case.

**A note on the input shape.** `SupersedeInput.PredecessorID` was required and `null` meant "release
every predecessor". Both `PredecessorID` and the new `ReleasePredecessorID` are now optional, and a
call carrying neither is **refused with an error** rather than treated as the old release-everything.
That is the one behaviour worth flagging: a stale caller sending the old shape gets told, instead of a
green result that changed nothing. The only caller in the workspace is the panel, which is updated in
the same change; the type is exported, hence `minor` rather than `patch`.

**Terminated is inclusive (item 13).** `vwContracts` derived Terminated from `TerminatedDate < today`,
so a contract terminated today read Active until midnight — while the Dates tab told the user that
setting the date marks it Terminated *from* that date. `V202608300100` moves that one branch to `<=`.
`Expired` deliberately stays `<`: an End Date is the last day the agreement covers, a Terminated Date
is the day it stops, and making them symmetric would expire every contract a day early.

**End Date before Effective Date says so (item 12).** The pair was guarded only by `CK_Contract_Dates`,
so the user got raw constraint text naming no field. `ContractEntity.Validate()` now reports
"End Date must be on or after the Effective Date." on the End Date field, in the browser and on the
server. The constraint stays as the backstop. The rule mirrors the constraint exactly — equal dates
pass, because a one-day agreement is real and a validator stricter than the database is a worse defect
than the error it replaces.

**A test that was green and wrong.** `contract-state.test.ts` reads the migration and asserts the view
says what we think it says, but it read a *pinned* filename — so item 13's new migration left it
passing while describing a superseded one. It had already been hand-repointed once before. It now
resolves the newest migration that defines the view, which removes the whole class of failure.
