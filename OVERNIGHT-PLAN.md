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

## Direction (Marcelo, 06:45 — supersedes anything below that conflicts)

- **Demo is EVENING**, not morning. ~9h until he wakes; more runway after. Target: **the full chain**.
- **Priority order when forced to choose:** (1) the flows *within* the app working end to end,
  (2) a very well built UI + backend validation + viewing/editing with validation,
  (3) cross-app integration and deep testing — bonuses, wanted if reachable.
- **Guessing is allowed** where a human ruling is missing — build it, then ASK on the PR.
  Post open questions to PR #2 **before 05:00**, in one comment headed **"AI questions from the overnight work"**.
- **Orders: switch early, rebuild once.** (Item 0 below.)
- **3 compactions allowed.** Keep durable state in THIS file + `TASKS.md` so a compaction costs nothing.
- Standards restated: `ProviderToUse` · BaseEntity subclass overloads (not helper classes) ·
  BaseEngine caching for high-read/low-write · custom forms for view+edit · MJ grid for viewing ·
  MJ tokens for every control incl. dropdowns · transactions around anything multi-write ·
  remotable ops where the UI needs a preview · MJ's 4-layer form architecture ·
  **FKs point UPSTREAM only; downstream adapts to upstream.**

## Item 0 — rebuild on the current orders (IN PROGRESS)

`origin/mjdev/orders-flow` (PR #31) is **22 commits ahead** of what we installed, including
"Merge origin/next: take its regenerated baseline" and "orders now installs from zero" — an 83k-line
migration diff, i.e. **new entity UUIDs**.

Our contracts baseline hardcodes **no** orders UUIDs (its FKs are to TABLES by name, and contracts'
CodeGen tail is generated into the DB at install, not into the migration), so no UUID surgery is
expected on our side. The risk is ordering, not identity.

Sequence: update the orders worktree → `mjdev wipe-db --yes` → `reapply-migrations` (core, then apps
in dependency order) → per-app setup/codegen/build → re-seed from `demo/seed-demo-contract.sql` →
re-drive the golden path. If the rebuild leaves the stack worse than it is now, say so plainly in the
Log rather than papering over it.

## Key finding — use MJ's 4-layer forms instead of hand-rolled edit surfaces

`guides/FORMS_ARCHITECTURE_GUIDE.md`. The layering is
`form/container → MjEntityFormHostComponent → shells → MJFormPresenterService`, all in
`@memberjunction/ng-base-forms` with no Explorer/Router coupling. What it gives us:

- **`MJFormPresenterService.Open({...})`** — open any entity's form imperatively from anywhere.
- **`<mj-form-dialog>` / `<mj-form-slide-in>`** — declarative modal / slide-in shells.
- **`EntityFormConfig`** — per-instance toolbar / sections / width / collapsibility **without
  regenerating** the form.
- **`SectionName="…"`** — render ONE section standalone, which is exactly a quick-edit affordance.

**Consequence for our UI:** the workspace should PRESENT our priority-2 custom Contract form through
these shells rather than duplicating its fields by hand — one definition of what a contract looks
like, reused in the workspace, in a dialog from the roster, and in a slide-in from anywhere. Term and
Line editing become slide-ins over their own custom forms rather than more grids. Rewrite the
workspace edit pane on this before adding any more hand-built fields.

## Queue — ordered by value, unblocked first

- [x] **1. `ContractType` seed metadata.** ✅ DONE — six types in `metadata/contract-types/`, proven
      on a from-zero rebuild (wipe → migrate → codegen → sync). Original text: Today's types came from raw SQL in `demo/`. Author them as
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

- **07:10** — **Item 0 done.** Orders updated to `origin/mjdev/orders-flow` (PR #31), 22 commits
  including its regenerated baseline. Full rebuild from zero: wipe-db → core + common + tasks +
  accounting migrated by `mjdev reapply-migrations`; **orders hit the known TVP deadlock at batch
  307 again**, applied the documented `mj migrate` workaround; contracts migrated clean.
  Result: accounting 24 / common 11 / contracts 11 / orders 50 / tasks 20 tables. As predicted, our
  baseline needed NO UUID surgery — contracts hardcodes no orders UUIDs.
- **07:15** — **Item 1 done.** ContractType metadata seeded and verified from a clean install
  (10 contracts entities registered, 6 types present, Application row intact). Demo SQL no longer
  inserts types — metadata owns them, sharing the same pinned UUIDs.

- **06:30** — Branch cut from `mjdev/contracts-dev` @ `bb73c29`. PR watcher armed on
  MemberJunction/bizapps-contracts#2. Work loop scheduled every 23 min. Queue above is the plan of record.
