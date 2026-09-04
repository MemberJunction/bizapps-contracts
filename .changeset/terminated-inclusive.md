---
'@mj-biz-apps/contracts-ng': minor
---

A contract is Terminated **on** its Terminated Date, not the day after (#28 item 13).

`vwContracts` read `TerminatedDate < CAST(GETUTCDATE() AS date)`, so setting Terminated Date = today saved successfully and left the state chip reading Active until the next day — while the Dates tab promised the opposite. The boundary is now `<=`.

This reverses a documented decision, which is why the migration sets out the reasoning rather than quietly overwriting it. `V202608240200` derived the exclusive boundary from `EndDate` — a period ending on a date runs through the end of that date, an agreement "terminating on 31 December" being in force all of 31 December — and applied "the same treatment" to `TerminatedDate`. The symmetry is the part that does not hold: `EndDate` is the last day **of** the term, so `<` is right there and is deliberately left alone, whereas `TerminatedDate` records the date the agreement **was ended** — an event, not the natural close of a period. Two columns both being `date` does not make an event and a period boundary the same kind of thing.

A future Terminated Date still reads Active, which was the earlier file's genuine fix and is unaffected: only the same-day case moves. `Superseded` is untouched, as the issue confirms.

Minor: the branch carries a versioned migration.
