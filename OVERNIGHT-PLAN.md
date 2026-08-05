# Overnight autonomous build — 2026-08-05

**Branch:** `mjdev/contracts-night` (instance `contracts-dev`) · **PR branch `mjdev/contracts-dev` is frozen**
except for cherry-picked review fixes. **Never push.** Marcelo pushes when he wakes.

## Rules

1. **One item per cycle**, verified and committed, before starting the next.
2. **Verify, never assume.** `npx ngc` → `mjdev app build` → Explorer bundle clean. If the change is
   user-visible, drive it with `test-harnesses/golden-path.mjs`. If it writes, check the database.
3. **Never fabricate a result.** A failure is written down as a failure.
4. **Two consecutive failures for the same reason → stop building.** Write what happened here and wait.
5. **A decision only a human can make is a STOP**, not a guess. Log it under Blocked and move on.
6. **PR feedback outranks the queue.** Fix on this branch, verify, then cherry-pick onto
   `mjdev/contracts-dev` so Marcelo's push carries it.

## Queue — ordered by value, unblocked first

- [ ] **1. `ContractType` seed metadata.** Today's types came from raw SQL in `demo/`. Author them as
      real `metadata/contract-types/` records so a clean install has them. Verify with a
      drop-schema → setup → sync cycle.
- [ ] **2. Entity-server subclasses (invariants).** `ContractEntity` / `ContractTermEntity`:
      auto-assign `ContractNumber` from `ContractSequence`, default `PricedAt` to today, derive
      `TermNumber` as max+1. These are the rules that must hold no matter who writes the row.
- [ ] **3. MJ Actions for status transitions** (master plan §10.5), in dependency order:
      `Contracts.ActivateTerm` → `Contracts.RenewTerm` → `Contracts.TerminateContract`.
      `SendForSignature` / `RecordExecution` / `RecordRejection` come after the signature panel.
- [ ] **4. Custom forms** for `ContractTerm` and `ContractLine`, same priority-2 override pattern as
      the Contract form — group by what a person reads, not schema order.
- [ ] **5. `<mj-record-files>` upload path.** The panel lists linked files; wire attach through MJ's
      storage providers and create the `FileEntityRecordLink` row.
- [ ] **6. `<mj-record-signature-status>` panel** on Contract + ContractTerm, reading
      `__mj.SignatureRequest` (`EntityID`/`RecordID`). Read-only first; sending needs a provider account.
- [ ] **7. Tier-2 server test harness** (`test-harnesses/server/`) — in-process, direct SQL: sequence
      allocation, term numbering, the XOR customer rule, escalation-cap bounds. Exact values, not liveness.
- [ ] **8. Unit tests** for the pure helpers (percent↔fraction, term fill state, tone mapping).
- [ ] **9. Workspace coverage editing** — add/edit `ContractLine` rows inline rather than grid-only.
- [ ] **10. Regenerate `docs/ERD.md`** from the live schema after any migration change, and re-pin
      `plans/bizapps-contracts-master.md` §10.3.
- [ ] **11. PG conversion** (`mj migrate convert`) + CI wiring — the C6 tail.

## Blocked — do NOT guess these

| Item | Blocked on |
|---|---|
| `ContractPriceResolver` (C2) | **D-2** — whether the orders resolver slot is a general pre-walk or a dedicated `Agreement:` key, and how multiple registrants coexist (ClassFactory resolves one instance per key). Amith. |
| `Contracts.GenerateBillingEvent` (C3) | The two orders seams — `Subscription.BillingMode` and the resolver slot. Needs the orders PR, which needs D-2. |
| `Contracts.CreateFromDeal` caller | `bizapps-sales` does not exist. The operation can be built; nothing can call it. |
| Renewal `AsOf` semantics | **Andrew** — likely the individual subscription end dates. |
| `ContractLine → OrderLine` mapping (P-1) | Needed before renewal pricing is trustworthy. Design call. |
| Usage metering | Out of v1 by decision. |

## Log

- **06:30** — Branch cut from `mjdev/contracts-dev` @ `bb73c29`. PR watcher armed on
  MemberJunction/bizapps-contracts#2. Work loop scheduled every 23 min. Queue above is the plan of record.
