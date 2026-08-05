# `bizapps-contracts` — planned ERD changes

> **This file is for schema changes we intend but have NOT built.** The as-built ERD lives at
> [`docs/ERD.md`](../docs/ERD.md) and is generated from the live database — it must never contain
> speculation. This file is the opposite: it is only speculation, and every entry leaves it the
> moment the change lands in a migration (at which point `docs/ERD.md` is regenerated and the row
> here is deleted).
>
> **Why the split.** An ERD that mixes what exists with what is wanted cannot be trusted for either
> purpose — a developer reads it as truth and a planner reads it as intent, and both are wrong.

---

## Open — intended, not built

| # | Change | Driver | Status |
|---|---|---|---|
| P-1 | `ContractLine` → `OrderLine` mapping (a link row, or an identifier stamped on the generated order line) | Renewal pricing walks the previous term's orders to find what a line cost. Matching by `ProductID` inside the order works when a product appears once and is ambiguous when it does not. | **Needed before the renewal engine (C4).** Deliberately NOT solved by shadow-copying prices onto `ContractLine` — see `docs/ERD.md` §8. |
| P-2 | Usage metering source for `LineType='Usage'` | The value is in the list; nothing supplies a quantity. Orders' metering engine is deferred. | Out of v1 by decision. The value stays so the schema does not change when metering arrives. |
| P-3 | Index source for `EscalationBasis='Index'` | Same shape as P-2: the value exists, nothing resolves it. A bare code column was tried and rejected as insufficient. | Deferred until a real index feed exists. |
| P-4 | Term-level `PricedAt` | `Contract.PricedAt` is the as-of date for the ORIGINAL pricing. A renewal term priced on a different date, or a backdated manual renewal, may want its own. | **Open question.** Contract-level is what was ruled; raise it if a renewal needs to price as of its own moment rather than the contract's. |
| P-5 | `Contract`/`ContractTerm` ↔ `Deal` reverse-lookup view | "Which deals produced this contract" is a real screen need, and the link is `Deal.ContractID` pointing down from `bizapps-sales`. | Blocked — `bizapps-sales` does not exist yet. **No column here, ever** (L-15). |

## Rejected — recorded so they are not re-proposed

These are in `docs/ERD.md` §8 with full reasoning: `ContractLine.ResolvedUnitPrice`/`ResolvedAt`,
`ContractTerm.EscalationIndexCode`, `DocumentFileID` on any table, renaming `DiscountPct`, and
`Contract.DealID` in any form.
