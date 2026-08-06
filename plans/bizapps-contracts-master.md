# BizApps Contracts — master plan

> **This is the app's source of truth**, kept in-repo alongside the code it governs (the same
> convention `bizapps-orders` follows with `plans/bizapps-orders-master.md`).
>
> **Decisions:** L-10…L-12, L-15, L-18 · **Open:** D-2, D-5
> **Repo:** `MemberJunction/bizapps-contracts` · **Schema:** `__mj_BizAppsContracts`
> **Status:** Baseline schema landed, **applied and CodeGen'd** on instance `contracts-dev`
> (10 tables, 10 entities, 5 packages building). The two orders seams in §4 still gate the billing
> engine. **§10 below carries every ruling made after this document was first written — read it
> before §3, because it supersedes parts of the data model described there.**
>
> **The ERD is generated, not written:** [`plans/ERD.md`](./ERD.md) is read straight out of
> `sys.tables`/`sys.foreign_keys` on a database built from the migrations. Regenerate it after any
> migration change rather than hand-editing it.
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

> ⚠ **AS-BUILT DIVERGENCE (2026-08-05).** This section describes the schema as PLANNED. Three of its
> statements are no longer true of the shipped migration, and each was changed deliberately by a later
> section of this same plan — the corrections existed, the pointers back to here did not:
>
> - **"Nine tables" — there are TEN.** `ContractSequence` was added for `CTR-{seq}` numbering, the
>   same singleton-counter shape orders uses for `ORD-`/`PAY-`.
> - **`DocumentFileID` is gone** from `Contract`, `ContractTerm` and `ContractAmendment` — see §10.2.
> - **`ContractTerm.Status` has five values, not four** — `PendingSignature` was added.
>
> The original text below is left exactly as written: it is the record of what was intended, and
> rewriting it in the past tense would lose the reason each change was made. **Ground truth is
> `migrations/V202608040002__v0.1.x__Tables_and_Objects.sql`**, with `docs/ERD.md` as the readable
> projection of it. (Logged as X.4 in `plans/FEATURE-LIST.md`.)

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

> ⚠ **As built:** `DocumentFileID` was **removed** (§10.2 — files attach through
> `__mj.FileEntityRecordLink`), and two columns were **added** that are not listed above:
> `SupersededByContractID` (the successor a `Superseded` contract names) and `PricedAt` (the as-of
> date every price on the agreement resolves from — §12).

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

> ⚠ **As built:** `DocumentFileID` was **removed** (§10.2). And `ApprovalTaskID` is a **hard FK**, not
> a soft reference — §10.1 #4's no-soft-keys mandate overrides the DG-6 rationale quoted here, which
> is the contradiction logged as X.3. The prose is left as written because reconciling the two
> rationales is a call for Amith, not a typo to fix.

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
| **C1** | Repo bootstrap, `mj-app.json`, baseline migration (nine tables — **ten as built**, see §3), CodeGen, `ContractType` seed metadata |
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

---

## 10. Rulings since this document was written (2026-08-04)

Everything in this section **supersedes** the corresponding text above. It is kept as an addendum
rather than edited into §3 so the original design intent stays legible next to what changed and why.

### 10.1 Answered by Amith

| # | Question | Ruling |
|---|---|---|
| 1 | Should orders be the definitive billing location? | **Yes — orders is the only place anyone is billed, full stop.** Contracts is the correct superset for consolidating mixed revenue streams onto one document. No "billing groups" in orders for now. The billing engine (§5) therefore stays here. |
| 2 | Who owns discounting? | **Orders owns the mechanics; a contract-level discount OVERRIDES what sits beneath it in the order** — it does not stack. `ContractLine.DiscountPct` states negotiated intent that outranks order-level discounting. |
| 3 | Which `AsOf` does the billing engine pass on renewal? | **Open — Andrew's call.** Probably the individual subscription end dates. Until it is settled, nothing here stores a resolved price (see 10.3). |
| 4 | Hard vs soft cross-app references | **There is no such thing as a soft key, and there must never be one.** A mandate, not a preference. The only acceptable non-FK reference in MJ is a genuine polymorphic pair (`EntityID`/`RecordID`, as in `__mj.TagLink`) used when the target entity is not knowable in advance — that is a typed polymorphic link, not a soft key. Every cross-app reference in this schema is a real FK. §3's description of `PaymentTermsTypeID` as a *"soft ref → orders"* is **withdrawn**; it was already a hard FK in the migration. |

### 10.2 Documents and signatures are MJ platform capabilities, not columns here

**Documents.** `DocumentFileID` has been **removed** from `Contract`, `ContractTerm` and
`ContractAmendment`. All three attach files through **`__mj.FileEntityRecordLink`** (`EntityID` +
`RecordID`). One record can then carry the signed PDF *and* its exhibits *and* a countersigned
amendment; a column caps it at one and forces a new column onto every future table that acquires paper.

**Signatures.** MJ ships e-signature in core — `@memberjunction/esignature-{docusign,dropboxsign,pandadoc}`
— and `__mj.SignatureRequest` already carries `EntityID` + `RecordID`, so a contract or a term links to
its envelope with **zero columns and zero migration** on our side. Around it sit
`SignatureRequestRecipients`, `SignatureRequestDocuments` and `SignatureRequestLogs`. Both patterns point
*down* into this schema, which keeps the dependency direction correct.

This closes a lifecycle the schema was already half-built for:

```
ContractType.RequiresSignature  →  raise a SignatureRequest against the Contract or ContractTerm
                                →  Status = 'PendingSignature' (driven by the envelope, not by hand)
                                →  SignatureRequest.CompletedAt  →  ExecutedDate stamped
                                →  executed PDF attached via FileEntityRecordLink
                                →  VoidReason covers the rejection path
```

### 10.3 Data-model changes applied to the baseline

Edited **into** the baseline migration rather than stacked as fix-ups — the app is pre-production and
the practice is to edit in place and rebuild on a clean database.

**Added**

| Change | Why |
|---|---|
| `Contract.SupersededByContractID` (self-FK) | `Status` already allowed `Superseded` with no way to name the successor, while `ContractTerm` had `RenewalOfTermID`. The schema tracked continuity at the term level and rupture at the contract level, and gave the chain to only one of them. |
| `ContractTerm.ExecutedDate` + `PendingSignature` status | Amendments had paper and renewals did not. It also silently assumed the evergreen pattern (one signed document, many periods) and could not express the re-papered-each-period pattern at all. |
| `ContractTerm.MaxEscalationPercent` + `RenewalNoticeDays`, with `ContractType` defaults | An uncapped "then-current list" increase is the most disputed clause in a B2B renewal, and the notice obligation had nowhere to live (`CancellationWindowDays` is a different clause that often shares its value). |
| `ContractLine.SubscriptionTypeID` (FK → `orders.SubscriptionType`) | `orders.Subscription.SubscriptionTypeID` is `NOT NULL`, so the engine cannot materialize a subscription without knowing its type — and `SubscriptionID` is only set *after* materialization, so it could not answer. Which kind of subscription a line becomes is a negotiated contract provision. |

**Considered and rejected** — recorded so they are not re-proposed:

| Rejected | Why |
|---|---|
| `ContractLine.ResolvedUnitPrice` / `ResolvedAt` | Conflates the apps. Orders owns pricing and price history; each generated bill **is** an order carrying the real price and date, already linked from `ContractBillingEvent.OrderID`. A second copy here has no authority and can only drift. |
| `ContractTerm.EscalationIndexCode` | A bare code names an index but nothing resolves it, so an `Index` basis still could not execute. The schema's own `LineType='Usage'` precedent is the right one: keep the **value** so the schema does not change when the capability arrives, add no **column** until there is something real to read. |
| Renaming `DiscountPct` | It is a fraction (0–1) wearing a percent name — but orders uses the identical shape for `OrderLine.DiscountPct` and `SalesAuthority.MaxDiscountPct`. Family consistency beats local correctness. |

### 10.4 What the UI is — and is not

**This app has its own UI. It does not re-expose orders' order form, and it does not reimplement
orders either.** The distinction is about *authority*, not about screens:

- **Contracts decides**: the customer, which products are covered, *how* each is covered, **which
  subscription type it becomes**, the coverage window, the negotiated price, and the term's clauses
  (escalation, cap, renewal notice, cancellation window). These get a first-class contract-native
  surface, because choosing them is a contract act.
- **Contracts never computes**: no totals, no tax, no proration, no resolved prices. The engine
  assembles a draft, prices it through `Orders.PreviewOrder`, and materializes one order via
  `Orders.CreateOrderInState`. Every number comes back from orders.

Round-2 mockups: [`design-docs/ui-design/mockups/`](../design-docs/ui-design/mockups/index.html).

**Two components MJ does not have and this app must build**, both record-scoped and polymorphic, and
both strong **MJ-base donation candidates** (every app that acquires paper or signatures wants them):

| Component | Gap it fills |
|---|---|
| `<mj-record-files>` | `@memberjunction/ng-file-storage` ships `mj-file-browser` / `mj-files-grid` / `mj-files-file-upload`, but they are **category**-scoped. Nothing in the MJ Angular tree queries `FileEntityRecordLink` at runtime — the only references are generated CRUD forms for the link entity itself. |
| `<mj-record-signature-status>` | Same gap for `SignatureRequest`: six entities and three providers exist, with no bespoke UI beyond generated forms. |

### 10.5 Status transitions are MJ Actions

Status changes are **not** ad-hoc entity writes. They are MJ Actions, following the pattern orders
already runs in this instance: `@RegisterClass(BaseAction, 'Orders.SendDocument')` in
`packages/Server/src/custom/*.action.ts`, registered as metadata in `metadata/actions/` +
`metadata/action-categories/`. The pattern is proven and available to us today.

Planned action set (none built yet):

| Action | Transition | Notes |
|---|---|---|
| `Contracts.SendForSignature` | `Draft` → `PendingSignature` | Raises a `SignatureRequest` against the contract *or* term. Gated on `ContractType.RequiresSignature`. Irreversible + reaches a person outside the company, so it is its own action — the same reasoning that split orders' `SendDocument` from `GenerateInvoice`. |
| `Contracts.RecordExecution` | `PendingSignature` → `Active` | Driven by the envelope completing: stamps `ExecutedDate`, attaches the executed PDF via `FileEntityRecordLink`, writes a `ContractEvent`. |
| `Contracts.RecordRejection` | `PendingSignature` → `Draft` \| `Terminated` | Carries `SignatureRequest.VoidReason`. |
| `Contracts.ActivateTerm` | term `Pending` → `Active` | Generates the billing schedule and its events. |
| `Contracts.RenewTerm` | creates the next term | Called by sales when a renewal deal closes (L-18); also callable by the Scheduled Job for auto-renew types. |
| `Contracts.TerminateContract` | → `Terminated` | Honours `CancellationWindowDays` / `EarlyTerminationDate`. |

**Why actions rather than entity-server logic:** a transition has side effects that reach outside the
record (an envelope, a file, a task, an order), it needs to be callable from a UI button, a scheduled
job and another app alike, and it should appear in the audit trail as a named thing that happened.

### 10.6 Build-sequence status

| Phase | State |
|---|---|
| **C0** — orders seams | **Blocked on D-2.** `Subscription.BillingMode` is straightforward; the resolver slot needs a defined multi-registrant contract first (ClassFactory resolves one instance per key, so an unkeyed pre-walk slot admits exactly one app). |
| **C1** — bootstrap, baseline, CodeGen | ✅ **Done.** Five packages `@mj-biz-apps/contracts-*`, baseline applied, 10 entities generated, building. `ContractType` seed metadata still to author. |
| **C2** — `ContractPriceResolver` | Blocked on C0. |
| **C3** — billing engine | Not started. Needs the concurrency claim state (a `Generating` status, or a conditional `UPDATE … WHERE Status='Scheduled'`) — `CK_ContractBillingEvent_GeneratedHasOrder` is a good invariant but does not stop two overlapping runs from both selecting the same row. |
| **C4** — `CreateFromDeal`, renewal, amendment, co-term | Not started; unblocked by D-2, so this and the §10.5 actions are the natural next work. |
| **C5** — Angular | Mockups at round 2; the two missing components in §10.4 are the first build. |
| **C6** — PG conversion, docs, release | Not started. |

---

## 11. Engineering standards for this app (non-negotiable)

These are house rules, not preferences. They exist because the alternatives have all been tried
somewhere in this family and cost someone a week.

### 11.1 Data access from the UI — exactly four methods

The UI reaches data through **`RunView`, `RunQuery`, `BaseEntity`, and RemotableOperation. Nothing
else.** No bespoke fetch, no hand-rolled GraphQL document, no service that wraps a socket.

**Never create a new provider. Always use `ProviderToUse`.** A second provider splits the metadata
and the class factory, and the failure is silent — registrations land in one factory and are read
from another, so entities simply do not appear and nothing throws.

### 11.2 Invariants live in `BaseEntity` subclasses

Anything that must be true on **every** create/update/delete goes in the entity subclass, not in a
caller. If a rule can be violated by writing the row from somewhere else, it is not enforced.
Status transitions with outside effects are the exception — those are Actions (§10.5) — but the
entity subclass still guards the invariant the transition depends on.

### 11.3 Forms are overrides of the MJ base form

Input views are **custom forms** — subclasses/overrides of `BaseFormComponent` — wherever a form
will do. Generated forms already exist for all ten entities; the work is overriding the ones that
need a real editing experience, not building parallel screens beside them.

### 11.4 Check MJ before building anything

Search MJ core first, every time. This app has already been saved twice by doing so: `FileEntityRecordLink`
replaced a `DocumentFileID` column we had designed, and `SignatureRequest` replaced an entire
signature subsystem we would otherwise have modelled. Both cost zero columns because MJ points *at*
our records. **The default assumption is that MJ already has it.**

### 11.5 MJ tokens and UI standards before hand-rolling

Use `@memberjunction/ng-shared`'s tokens (`_tokens.scss` — 255 tokens, light and dark) and MJ's
existing components. Where something genuinely valuable and reusable must be hand-rolled, build it
**donation-shaped** from the start: record-scoped, app-agnostic inputs, no contracts-specific types
in its public surface.

### 11.6 Follow MJ's own `CLAUDE.md`, and code to convention

MJ's `CLAUDE.md` is the highest authority for MJ behaviour: strong typing always (no `any`, no
`.Get()`/`.Set()` in place of generated properties), the generated ORM is the schema's source of
truth, `mj sync push` before `mj codegen`. Match the surrounding code's structure and naming before
inventing.

### 11.7 Components: built here, donated after

The two components MJ lacks (§10.4) are **built, tested, finalized and polished in this repo**, then
handed to Matt to bring into MJ base. Deliberately not the other way round: gating every UI change
in this app on an MJ PR would make the app's iteration speed a function of MJ's release cadence.

---

## 12. Pricing — the as-of rule (Andrew, 2026-08-04)

**The price quoted when the deal was struck is the price that belongs in the contract.** This was a
schema hole; `Contract.PricedAt` closes it.

### 12.1 How a price gets into a contract

| Path | What happens |
|---|---|
| **From a closed deal** | `PricedAt` is the deal's pricing moment; the deal's prices are written into `ContractLine.ContractedUnitPrice`. |
| **Entered manually** | `PricedAt` defaults to today. The UI shows the catalog price **as of `PricedAt`** and locks it into the line on save. **Backdatable**, because a contract signed last month may be entered today and must price as of when it was agreed. |

**Why the lock matters:** a manager opens a contract, reviews the numbers, saves — and the value must
not have moved underneath them because the catalog changed in between. Unexpected change here is not
a rounding annoyance; it is the number the customer signed.

### 12.2 How renewals price

```
first renewal of a line with ContractedUnitPrice = NULL
    → resolve the catalog price AS OF Contract.PricedAt
    → apply the agreed escalation (EscalationPercent, capped by MaxEscalationPercent)
    → WRITE the result into the line

every renewal after that
    → escalate from the contract's OWN prior price
    → never re-read the catalog
```

An agreement, once priced, becomes **self-referential**. The catalog is consulted exactly once.

### 12.3 Why this does not resurrect `ResolvedUnitPrice`

`ContractedUnitPrice` is the negotiated price — a contract fact, and always was a column. What was
rejected was storing a *second*, engine-derived copy of a price orders already owns. Renewal pricing
still reads the **previous term's order lines** for what was actually billed; `PricedAt` only supplies
the as-of date for the one catalog read at the start of the chain. **Open dependency:** this needs the
`ContractLine → OrderLine` mapping tracked as **P-1** in `plans/ERD-planned.md`.

---

## 13. Structural questions for the first PR

Genuinely open, and better answered by reviewers than guessed:

1. **How much of orders does a contract legitimately restate?** A contract needs the data required to
   *be* a contract, and much of that overlaps the order it will produce — product, quantity, price,
   subscription type. Some overlap is unavoidable. The question is where the line sits, and whether
   **custom forms over shared entities** can carry the overlap instead of parallel tables. Concretely:
   how do contract-specific subscriptions get expressed without reimplementing subscription
   management? *(Raised by Marcelo, 2026-08-04.)*
2. **Is "Coverage" the right concept, or the right name?** The workspace tab currently called Coverage
   holds "what the agreement covers" — the contract lines. It may be conflating the agreement's scope
   with an order's line items.
3. **`ContractLine → OrderLine` mapping (P-1)** — needed before renewal pricing is trustworthy.
