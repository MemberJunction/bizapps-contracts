# BizApps Contracts — master plan

> **This is the app's source of truth**, kept in-repo alongside the code it governs (the same
> convention `bizapps-orders` follows with `plans/bizapps-orders-master.md`).
>
> **Decisions:** L-10…L-12, L-15, L-18 · **Open:** D-2, D-5
> **Repo:** `MemberJunction/bizapps-contracts` · **Schema:** `__mj_BizAppsContracts`
> **Status:** Baseline schema landed (hand-authored DDL). The two orders seams in §4 gate the
> billing engine.
>
> **Provenance.** Derived from sub-plan 02 of the *Sales & Deal Management* plan set in Blue
> Cypress's internal `new-products` repository, which remains the home of the CROSS-APP strategy
> (positioning, commercial model, the three-app split, the L-1…L-21 decision log). That parent
> document is private and deliberately not mirrored here. **Anything app-specific is now owned by
> this file** — amend it here rather than upstream, and the two will not fight.

---

## 1. What this app is

The **agreement envelope**: what was committed to, for how long, at what escalation — and the thing
that decides **when a bill is produced and what goes on it**.

It is not a second transaction engine. Orders owns pricing, tax, receivables and booking. Contracts
owns commitment and the calendar, and it produces orders through orders' own operations.

### Owns

Commitment (contracted vs. consumed) · term structure and renewal · escalators and rate increases ·
cancellation and early-termination policy · **the billing event** · contracted pricing (as a
registered resolver plugin) · co-terming · milestone and installment schedules · executed documents ·
the immutable agreement audit trail.

### Does not own

Line pricing mechanics · tax · JE booking · payment capture · subscription cadence mechanics ·
customer master · anything orders already does.

### 🚫 The reference that must never be added

Contracts carries **no reference to a Deal** — no `Contract.DealID`, hard or soft. The link lives in
`bizapps-sales` as `Deal.ContractID`, pointing down. **Two independent reasons, either of which alone
is sufficient (L-15):**

1. **Direction.** Contracts sits below sales in the dependency graph, so a reference upward inverts
   the app graph — the same rule that removed `Order.ContractID` from orders (D44) and
   `AccountingCompanyProfile.DefaultPaymentTermsTypeID` from accounting.
2. **Cardinality.** It is **one contract to many deals.** The original sale is a deal; every renewal
   is another deal; expansions and cross-sells are more. The contract persists across all of them. A
   single `Contract.DealID` could only ever name one, and would quietly degrade into "whichever deal
   we happened to write last" — a field that looks authoritative and is not.

This will feel wrong at least once during the build — the moment someone wants "which deal produced
this contract?" on the contract form. The answer is a reverse lookup from sales (`Deal.ContractID` /
`Deal.RenewsContractID`), which correctly returns the *set* of deals, never a column here.

---

## 2. Repo bootstrap

Standard BizApps Open App skeleton (clone the `bizapps-orders` / `bizapps-caliber` shape).

| | |
|---|---|
| npm scope | `@mj-biz-apps/contracts-*` — `contracts-entities`, `contracts-actions`, `contracts-server`, `contracts-core-entities-server`, `contracts-ng` |
| Schema | `__mj_BizAppsContracts` |
| Entity prefix | `MJ_BizApps_Contracts:` (set in `mj.config.cjs` `newEntityDefaults`) |
| Ports | MJAPI **4151**, MJExplorer **4351** |
| Dependencies (`mj-app.json`) | `mj-bizapps-common`, `mj-bizapps-tasks`, `mj-bizapps-accounting`, `mj-bizapps-orders` |
| Platform | T-SQL source of truth; PG by `sql-converter`, CI-validated |
| Branching | `next` → `main`; feature branches track same-named remotes |

**Pre-production migration practice:** while nothing is deployed, edit the original baseline
migration in place and rebuild on a clean database rather than stacking fix-up migrations — the
practice orders adopted. Switch to additive-only at first publish.

---

## 3. Data model

Nine tables. Configuration-as-data throughout, following the Sonar/Caliber doctrine: a `ContractType`
row carries the defaults, and the engine reads them rather than branching on a type string.

### 3.1 `ContractType` — the rules

Named defaults for a class of agreement: `Code`, `Name`, `DefaultTermMonths`, `DefaultBillingFrequency`,
`DefaultAutoRenew`, `RequiresSignature`, `DefaultEscalationPercent`, `DefaultCancellationWindowDays`,
`RenewalMode`, `AllowsCoterm`, `DriverClass` (nullable).

`DriverClass` is **optional**, following `SubscriptionType`'s pattern rather than
`RevenueRecognitionType`'s: the columns *are* the rules, a base behaviour class reads them, and a
driver is supplied only when a customer needs something the columns cannot express — subclassing the
base rather than replacing it. A driver-only model would force a class per permutation of
term × cadence × renewal × escalation, which is exactly the combinatorial explosion configuration
avoids.

Seeded types: `Standard`, `MSA`, `SOW`, `Membership`, `Evergreen`, `Pilot`.

### 3.2 `Contract` — the agreement

`ContractNumber` (sequence, `CTR-{seq}`) · `ContractTypeID` · `CompanyID` (**selling** company, MJ
core) · `CustomerOrganizationID` / `CustomerPersonID` (common; exactly one, `CHECK`-enforced) ·
`PrimaryContactPersonID` · `OwnerUserID` · `ParentContractID` (self-FK — MSA→SOW nesting, D-5) ·
`Status` (`Draft` | `PendingSignature` | `Active` | `Expired` | `Terminated` | `Superseded`) ·
`Description` · `EffectiveDate` · `ExecutedDate` · `DocumentFileID` (MJ `Files`) · `AutoRenew` ·
`CancellationWindowDays` · `TerminationPolicy` · `ExternalReferenceID`.

### 3.3 `ContractTerm` — the period

`ContractID` · `TermNumber` · `StartDate` / `EndDate` · `Status` (`Pending` | `Active` | `Completed`
| `Terminated`) · `RenewalOfTermID` (self-FK, the chain back through prior terms) · `CommittedAmount`
· `EscalationPercent` · `EscalationBasis` (`PriorTerm` | `ListPrice` | `Index`) · `BillingFrequency`
(`Monthly` | `Quarterly` | `SemiAnnual` | `Annual` | `Milestone` | `Custom`) · `BillingAnchorMonth` /
`BillingAnchorDay` · `PaymentTermsTypeID` (soft ref → orders, which owns payment terms) ·
`EarlyTerminationDate` · `RenewalProbability` · `Notes`.

`RenewalProbability` earns its place: it is what a renewal forecast in sales reads.

### 3.4 `ContractLine` — what is covered

`ContractTermID` · `ProductID` (→ orders catalog) · `LineType` (`Subscription` | `OneTime` |
`Milestone` | `Usage` | `Minimum`) · `Quantity` · `ContractedUnitPrice` (**nullable — null means
resolve normally**) · `DiscountPct` · `StartDate` / `EndDate` (co-term stubs live here) ·
`SubscriptionID` (→ orders, the materialized subscription for `LineType='Subscription'`) ·
`Description`.

`LineType` is what makes one table serve subscriptions, one-time fees, milestone draws, usage
true-ups and minimum commitments. The billing engine reads it; nothing else branches on it.

### 3.5 `ContractBillingSchedule` — the plan

`ContractTermID` · `ScheduleType` (`Cadence` | `Milestone` | `Custom`) · `Frequency` · `AnchorDate` ·
`IsActive` · `Notes`. One term may carry more than one schedule — a quarterly subscription cadence
*and* a milestone schedule for the attached SOW.

### 3.6 `ContractBillingEvent` — each occurrence, and the audit trail

`ContractBillingScheduleID` · `ContractTermID` · `ScheduledDate` · `Status` (`Scheduled` |
`Generated` | `Skipped` | `Failed`) · `OrderID` (→ orders — a legal downward reference) ·
`ComputedAmount` · `GeneratedAt` · `FailureReason` · `Notes`.

This is the record that answers "why did the customer get this bill on this date, and what produced
it." A failed generation stays `Failed` with a reason rather than silently retrying into a duplicate.

### 3.7 `ContractCommitment` — minimums, prepaid draws, true-ups

`ContractTermID` · `CommitmentType` (`Minimum` | `Prepaid` | `Draw`) · `CommittedAmount` ·
`ConsumedAmount` · `PeriodStart` / `PeriodEnd` · `TrueUpPolicy` (`BillShortfall` | `Forfeit` |
`Rollover`) · `Status`.

### 3.8 `ContractAmendment` — mid-term change

`ContractTermID` · `AmendmentNumber` · `EffectiveDate` · `AmendmentType` (`AddProduct` |
`ChangeQuantity` | `ChangePrice` | `Coterm` | `PartialTerminate` | `Other`) · `Description` ·
`DocumentFileID` · `Status` · `ApprovalTaskID` (soft ref → tasks).

Amendments change a live term. **Renewals start a new one** — see §5 and D-1.

### 3.9 `ContractEvent` — immutable lifecycle log

`ContractID` · `ContractTermID` · `EventType` · `EventDate` · `Payload` (JSON) · `PerformedByUserID`.
Mirrors orders' `SubscriptionEvent`. Never edited, never deleted.

> Also write a `common.Activity` row for customer-visible contract events (executed, renewed,
> terminated) via `Common.LogActivity`, so the agreement shows up on the account timeline. The
> `ContractEvent` log is the system record; the Activity is the human one. They are not the same
> thing and neither replaces the other.

---

## 4. The two seams required in `bizapps-orders`

Both additive, both small. **Land these first** — contracts cannot be finished without them, and
they are cheap now and awkward later. One PR against orders.

### 4.1 `Subscription.BillingMode`

```
Subscription.BillingMode NVARCHAR(20) NOT NULL DEFAULT 'Self'
    CHECK (BillingMode IN ('Self','External'))
```

`Orders.SpawnRenewals` skips `External`. That is the whole change on the orders side — orders never
learns the word "contract," and the linkage (`ContractLine.SubscriptionID`) lives here, pointing up
the graph.

**Why a column and not a convention:** it makes "exactly one thing spawns orders for a given
subscription" true *by construction*. Two engines that could both spawn for the same subscription is
a duplicate-billing bug, and duplicate billing is the kind of defect a customer discovers before we
do. A `Self` subscription covered by an active contract line should be a validation failure on the
contracts side, not a race.

**Migration note:** default `'Self'` means every existing subscription keeps today's behaviour. No
backfill, no behaviour change on install.

### 4.2 A pricing-resolver slot ahead of `Product:`

**The orders master plan states a contract-override slot is "reserved at the top of the [pricing
precedence] chain." Verified against the code: it is not there.** `ResolvePrice`
(`packages/CoreEntitiesServer/src/PriceResolver.ts`) walks:

```
Product:{ProductID}  →  Category:{chain, nearest first}  →  Company:{CompanyID}  →  unkeyed default
```

Those keys are product- and company-shaped. A contracted price is **customer × product × time**,
which none of them can express. Registering at `Company:{sellingCompanyId}` would hijack that slot
for *all* pricing under that company and collide with any genuine company-level plugin — not an
option.

**Recommended shape (D-2): a general pre-walk registration.** A key tried before `Product:` that any
downstream app may register — contracts today, whatever needs it next without a third orders PR. The
narrower alternative is a dedicated `Agreement:` step; same cost, less reach.

Contracts then ships `ContractPriceResolver extends BasePriceResolver`, which:

1. finds the active contract line for `(OrganizationID | PersonID, ProductID, AsOf)`;
2. returns `ContractedUnitPrice` with escalation applied from the term's rules, and a
   `PriceComponentDraft` trail so the explanation names the contract;
3. returns `null` when no contract covers it — declining, so the walk continues normally;
4. **refuses** when two active contracts cover the same product for the same customer, naming both.

That last point matters and matches the contract `Orders.PreviewPrice` already documents: *"an
ambiguous rule set is a refusal, not a fault: it is a configuration problem the caller can fix, and
the message names the rules that collided."* Silently picking one would be a wrong answer that looks
like a right one.

**The payoff:** contracted prices apply to *ad-hoc* orders too — not just billing-schedule output.
That is exactly where hand-maintained contract pricing normally leaks, and it comes free from putting
the logic in the resolver instead of in the billing engine.

---

## 5. The billing-event engine

### 5.1 Generating a bill

`Contracts.GenerateBillingEvent(BillingEventID)` — one remote operation, one transaction:

1. Load the term, its lines, its commitments, and the event.
2. Assemble the draft:
   - `Subscription` lines → charges for the period being billed;
   - `OneTime` lines whose window opens in this period;
   - `Milestone` lines whose milestone is marked reached;
   - `Usage` lines → metered quantity for the period;
   - `Minimum` commitments → shortfall, per `TrueUpPolicy`.
3. Build a `HydratableHeader` + `HydratableLine[]` and call **`Orders.PreviewOrder`** to price it —
   contracted prices resolve through the plugin (§4.2), so the engine performs no arithmetic of its
   own.
4. Materialize **one** consolidated order via **`Orders.CreateOrderInState`**.
5. Stamp `ContractBillingEvent.OrderID` / `ComputedAmount` / `GeneratedAt`, advance covered
   subscriptions' periods, write a `ContractEvent`.

All-or-none. A failure marks the event `Failed` with a reason and **does not** partially bill.

**The rule the engine must obey:** it decides *what to bill* and never *what it costs*. Every number
comes back from orders.

### 5.2 Driving the schedule

An MJ **Scheduled Job** walks `ContractBillingEvent` rows with `Status='Scheduled'` and
`ScheduledDate <= today`, invoking the operation per event. Bounded per run and idempotent —
re-running must not double-bill, which the `Status` transition guarantees. `Failed` events are
surfaced in a worklist for a human, never auto-retried into a duplicate.

### 5.3 Renewal *(gated on D-1)*

`Contracts.RenewTerm(ContractTermID)` creates the next `ContractTerm` with `RenewalOfTermID` set,
applies the escalator, rolls forward lines (minus anything with a hard end date), regenerates the
billing schedule, and re-points covered subscriptions.

**Who triggers it — resolved (L-18).** A renewal **is a deal**. Contracts exposes the operation;
`bizapps-sales` calls it when a renewal deal closes, so renewal gets its own pipeline, forecast and
win-rate rather than happening invisibly inside the contract record. This is the same fact that
makes the cardinality one-contract-to-many-deals (§1): the original sale is a deal, every renewal is
another, and the contract persists across all of them.

Auto-renew without a deal remains available for evergreen and B2C contracts
(`ContractType.RenewalMode`); that path calls the same operation from the Scheduled Job. Mid-term
changes that do **not** restart a term stay amendments (§3.8).

### 5.4 Co-terming

Adding a product mid-term creates a `ContractAmendment` plus a `ContractLine` whose `StartDate` is
the amendment date and whose `EndDate` is the **term's** end date. The stub period is prorated on the
next billing event. This is the capability standalone subscriptions structurally cannot provide, and
it is why the contract owns the calendar.

---

## 6. Approvals

Non-standard terms, discounts beyond a rep's `SalesAuthority`, and early-termination waivers raise an
**Approval Request Task** in `bizapps-tasks`, linked to the contract or amendment and routed to an
approver role. `TaskType` `OnComplete` / `OnReject` Action hooks call back into contracts to advance
or reject. `ContractAmendment.ApprovalTaskID` is a soft ref (per Caliber's DG-6: package dependency
≠ schema dependency; cross-OpenApp-schema hard FKs are avoided because the other app's migrations may
not have run).

---

## 7. Note on CDP's `finance` schema

CDP's `finance.Contract` / `ContractTerm` / `ContractTermLineItem` / `ContractTermPaymentSchedule`
is **not a reference design and is not an input to this model.** It is what BC happens to run right
now: INT primary keys, no shared product catalog, a private payment-schedule table, JE status copied
onto the contract, and no way to consolidate a bill across revenue streams. It does not scale and we
are replacing it, not porting it (L-9).

The model in §3 was derived from the problem, not from that schema. The only reason to open CDP
during this build is **data migration** — mapping live agreements onto the new model at cutover —
and that is a migration exercise with its own document, not a design activity. Nothing in CDP should
constrain a decision here.

---

## 8. Build sequence

| Phase | Work |
|---|---|
| **C0** | Orders PR: `Subscription.BillingMode` + the resolver slot (§4). Land first. |
| **C1** | Repo bootstrap, `mj-app.json`, baseline migration (nine tables), CodeGen, `ContractType` seed metadata |
| **C2** | `ContractPriceResolver` + registration; integration checks proving contracted price wins, declines cleanly, and refuses on ambiguity |
| **C3** | Billing-event engine + `Contracts.GenerateBillingEvent` + the Scheduled Job |
| **C4** | `Contracts.CreateFromDeal` (called *by* sales — the operation lives here, the caller lives above) · renewal + amendment + co-term operations |
| **C5** | Angular: contract workspace, term timeline, billing-schedule view, amendment dialog |
| **C6** | PG conversion, docs, ERD, changeset, release |

---

## 9. Open questions

1. **D-2 (blocks §4.2):** general pre-walk resolver registration vs. a dedicated `Agreement:` key.
   *Recommendation: general pre-walk.*
2. **D-5 (blocks §3.2):** is `Agreement`/MSA a distinct entity above `Contract`?
   *Recommendation: defer — `ParentContractID` self-FK until the two genuinely diverge.*
3. **Usage metering source.** `LineType='Usage'` needs a quantity from somewhere. Orders ships usage
   pricing fields but the metering engine is deferred (orders §21). Does contracts read a meter, or
   is usage out of v1? *Recommendation: out of v1;* keep `LineType='Usage'` in the value list so the
   schema does not need to change when it arrives.
4. **Multi-currency.** Orders defers FX (D24). Contracts should record `CurrencyID` on the term for
   forward-compatibility but do no conversion. Confirm.
