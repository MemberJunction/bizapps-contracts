---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

The billing engine, and amendments that co-term.

**`Contracts.GenerateBillingEvent` + `RunDueBillingEvents`.** Until now the app modelled the
agreement and produced no bill, which is the part it exists for. The engine claims an event
with a conditional `UPDATE … WHERE Status='Scheduled'` and `@@ROWCOUNT` so two runners cannot
bill the same occurrence, assembles the draft per line type, and records a failure OUTSIDE
the rolled-back transaction — a Failed event with no surviving reason is a bill nobody can
explain later.

The two calls into orders sit behind a registered BRIDGE with an honest unavailable default.
When the C0 seams land, orders registers an implementation and the engine does not change.

**The billing anchor is honoured.** `BillingAnchorMonth` / `BillingAnchorDay` were written by
`RenewTerm` and read by nothing, so a term that negotiated a January anchor billed from
whenever it happened to start. The schedule now anchors on them, and never before the term
begins.

**`Contracts.AmendTerm`** applies `AddProduct` and `Coterm` exactly as master plan §5.4
specifies: a mid-term addition creates a line whose window ends with the TERM, so the new
product lands on the same renewal date as everything else the customer already has. That is
the capability standalone subscriptions structurally cannot provide, and it is why the
contract owns the calendar.

`ChangeQuantity`, `ChangePrice` and `PartialTerminate` are REFUSED with the reason rather
than half-implemented: `ContractAmendment` records that a term changed, not which line
changed or to what, so applying them would mean guessing — and a wrong guess produces an
amendment marked Applied against a term nothing actually changed on. Raised as Q2.

**One real bug fixed on the way:** a one-time line billed in EVERY period, because the guard
only fired when the line stated its own start date. It now opens with the term.
