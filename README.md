<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/MemberJunction/MJ/raw/main/MJ_logo_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/MemberJunction/MJ/raw/main/MJ_logo.webp">
    <img alt="MemberJunction" src="https://github.com/MemberJunction/MJ/raw/main/MJ_logo.webp" width="220">
  </picture>
</p>

<h1 align="center">BizApps Contracts</h1>

<p align="center">
  <strong>The agreement envelope — commitment, term, escalation, renewal, and the billing event — for the <a href="https://github.com/MemberJunction/MJ">MemberJunction</a> platform</strong>
</p>

<p align="center">
  <a href="#what-this-is--and-is-not">What this is</a> &middot;
  <a href="#the-one-rule-that-governs-everything">The rule</a> &middot;
  <a href="#what-you-get">What you get</a> &middot;
  <a href="#the-billing-event">Billing event</a> &middot;
  <a href="#entity-model">Entity model</a> &middot;
  <a href="#build-sequence">Build sequence</a>
</p>

<p align="center">
  <img alt="Status" src="https://img.shields.io/badge/Status-Bootstrap%20%2F%20no%20schema%20yet-red?style=flat-square" />
  <img alt="MJ Version" src="https://img.shields.io/badge/MemberJunction-5.50%2B-blue?style=flat-square" />
  <img alt="Angular" src="https://img.shields.io/badge/Angular-21-DD0031?style=flat-square&logo=angular&logoColor=white" />
  <img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-5.9-3178C6?style=flat-square&logo=typescript&logoColor=white" />
  <img alt="SQL Server" src="https://img.shields.io/badge/SQL%20Server-2019%2B-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white" />
  <img alt="PostgreSQL" src="https://img.shields.io/badge/PostgreSQL-17-336791?style=flat-square&logo=postgresql&logoColor=white" />
  <img alt="License" src="https://img.shields.io/badge/License-BUSL%201.1-blue?style=flat-square" />
</p>

---

> **🚧 Status: repo bootstrap. Nothing is built yet.**
>
> There is no schema, no migration, no package code. **This README is the specification we are
> building to, not a description of what exists.** Every table, operation and behaviour below is a
> commitment, not a claim. The design is settled — see
> [`plans/bizapps-contracts-master.md`](plans/bizapps-contracts-master.md)
> (decisions **L-10…L-12**, **L-15**, **L-18**) — and the build sequence is in
> [Build Sequence](#build-sequence) below. Sections describing unbuilt behaviour say so.

A customer signs one agreement covering three subscription products, a services SOW and a setup fee,
and expects **one quarterly bill**. Three independently-billing subscriptions cannot physically
produce that document. **That is the problem this app exists to solve.**

BizApps Contracts is the **agreement envelope**: what was committed to, for how long, at what
escalation — and the thing that decides **when a bill is produced and what goes on it**. It sits
directly above [BizApps Orders](https://github.com/MemberJunction/bizapps-orders) in the dependency
stack and produces orders *through orders' own operations*.

It is emphatically **not a second transaction engine.** Orders owns pricing, promotions, charges,
tax, receivables and booking. Contracts owns **commitment and the calendar**.

---

## The one rule that governs everything

> **The billing engine decides *what* to bill. It never decides *what it costs*.**

Every number on a contract-generated bill comes back from `Orders.PreviewOrder` — the same pricing
pipeline that prices an ad-hoc order, run against a draft this app assembles. Contracts performs no
arithmetic of its own: no multiplication, no proration, no discount application, no rounding.

This is not a stylistic preference. It is the reason a contract's bill and a manually-placed order
for the same products cannot disagree. Orders states the obligation from its own side, and it
applies with equal force here:

> *"A preview computed by a parallel simplified implementation is worse than no preview, because
> people trust it and it diverges silently — the quote says one number and the invoice says another,
> and nobody can say which is wrong."*

The failure mode this prevents arrives by accretion — "just this one proration case" — so it is
enforced by an integration check, not by a paragraph asking nicely.

### This is not a rule against overriding prices

Negotiated pricing is the entire point of an agreement, and this app exists to hold it.
`ContractLine.ContractedUnitPrice` and `DiscountPct` are how — subject to approval at whatever level
the organization configures (see [Approvals](#approvals-run-on-bizapps-tasks)).

**An override is an input to the pricing pipeline, never a replacement for it.** Contracts names the
price; orders honours it and **still** applies charges, tax and proration on top, then returns the
totals. Contracts stamps what came back.

```
ContractLine.ContractedUnitPrice = 50,000    ← what was negotiated
        │
        ▼
Orders.PreviewOrder                          ← honours it, THEN applies charges +
        │                                       tax + proration on top
        ▼
ContractBillingEvent.ComputedAmount = 53,240 ← stamped, never derived here
```

Computing `quantity × contracted price` here would yield **50,000** — silently dropping tax and
charges, so the contract's bill and an ad-hoc order for the same goods disagree. That, not the
negotiated number, is what the rule forbids.

**Contracted pricing goes further and does it cleaner:** `ContractPriceResolver` registers *inside*
orders' `BasePriceResolver` walk, so contracts never overrides orders from the outside — it
**participates in orders' own computation** as a registered plugin. That is precisely why contracted
prices apply to ad-hoc orders too, and why the arithmetic stays in exactly one place.

---

## What This Is — and Is Not

| ✅ This is | ❌ This is not |
|---|---|
| The **agreement envelope**: commitment, term, escalation, renewal, cancellation policy | A pricing or tax engine (orders owns `ResolvePrice`, promotions, charges, tax) |
| The **billing event** — consolidating many revenue streams onto one document | A general ledger (orders emits JEs into [BizApps Accounting](https://github.com/MemberJunction/bizapps-accounting)) |
| **Contracted pricing**, shipped as a registered resolver plugin so it applies to ad-hoc orders too | A subscription engine (orders owns cadence and entitlement continuity per product) |
| **Co-terming** — the capability standalone subscriptions structurally cannot deliver | A payment processor (orders owns capture, refund, chargeback) |
| Commitment tracking: minimums, prepaid draws, usage true-ups | A CRM or a customer master (that is `bizapps-common`, fronted by [BizApps Sales](https://github.com/MemberJunction/bizapps-sales)) |
| Milestone and installment schedules; executed documents via MJ `Files` | An e-signature product (integrate DocuSign / Dropbox Sign; do not build) |

---

## The reference that must never be added

**Contracts carries no reference to a Deal.** No `Contract.DealID`, hard or soft. The link lives in
`bizapps-sales` as `Deal.ContractID`, pointing *down* the dependency graph.

Two independent reasons, either sufficient on its own (**L-15**):

1. **Direction.** Contracts sits below sales, so a reference upward inverts the app graph — the same
   rule that removed `Order.ContractID` from orders (**D44**) and
   `AccountingCompanyProfile.DefaultPaymentTermsTypeID` from accounting.
2. **Cardinality.** It is **one contract to many deals.** The original sale is a deal; every renewal
   is another deal; expansions and cross-sells are more. The contract persists across all of them. A
   single `Contract.DealID` could only ever name one, and would quietly degrade into "whichever deal
   we happened to write last" — a column that looks authoritative and is not.

This will feel wrong at least once during the build: the moment someone wants *"which deal produced
this contract?"* on the contract form. The answer is a reverse lookup from sales
(`Deal.ContractID` / `Deal.RenewsContractID`), which correctly returns the **set** of deals — never a
column here.

---

## Installation

BizApps Contracts is a [MemberJunction Open App](https://github.com/MemberJunction/MJ/tree/main/packages/OpenApp).
Once published:

```bash
mj app install https://github.com/MemberJunction/bizapps-contracts
```

The CLI resolves the dependency chain automatically — installing contracts pulls in
[Orders](https://github.com/MemberJunction/bizapps-orders) (catalog, pricing, subscriptions,
receivables), [Accounting](https://github.com/MemberJunction/bizapps-accounting) (JE primitives),
[Common](https://github.com/MemberJunction/bizapps-common) (Person / Organization) and
[Tasks](https://github.com/MemberJunction/bizapps-tasks) (the approval substrate).

> **Not yet installable.** Orders and Accounting are not published to npm, so during development
> this repo resolves them through sibling checkouts — see [Local development](#local-development).

---

## Dependency position

Contracts sits one rung above orders. Every reference it makes points **down** the graph, so every
foreign key is legal and no polymorphic gymnastics are required.

```
__mj                     MJ core: Company, User, Employee, File, Actions, Scheduled Jobs
   ↑
bizapps-common           Person, Organization, Address, ContactMethod
   ↑
bizapps-tasks            Task primitives; approval gates; TaskType Action hooks
   ↑
bizapps-accounting       GL roles/links, JournalEntry primitives, Currency, dimensions
   ↑
bizapps-orders           Catalog, pricing/promotions/charges/tax, Order-as-A/R,
   ↑                     Subscriptions, Payments, RevRec, Entitlements
bizapps-contracts   ◄── you are here
   ↑
bizapps-sales            Accounts, contacts, pipelines, deals, forecasting
```

| | |
|---|---|
| **Schema** | `__mj_BizAppsContracts` |
| **Entity prefix** | `MJ_BizApps_Contracts:` |
| **npm scope** | `@mj-biz-apps/contracts-*` |
| **Ports** | MJAPI **4151** · MJExplorer **4351** |
| **Branching** | `next` → `main`; feature branches track same-named remotes |
| **Keys** | UUID primary keys throughout |

### What contracts consumes

`orders` — the product catalog, `Subscription`, `Orders.PreviewOrder`, `Orders.CreateOrderInState`,
the pricing resolver walk, `PaymentTermsType` · `common` — Organization / Person ·
`tasks` — approval gates · MJ `Files` — executed documents · MJ Scheduled Jobs — the billing driver.

### What contracts provides

The agreement envelope · the billing event · contracted pricing as a registered `BasePriceResolver`
plugin · commitment/consumption tracking · the renewal and amendment lifecycle ·
`Contracts.CreateFromDeal` (called *by* sales — the operation lives here, the caller lives above).

---

## The two seams required in `bizapps-orders`

Both additive, both small, both **land first** — the billing engine cannot be finished without them,
and they are cheap now and awkward later. Verified absent against `bizapps-orders@next` as of
2026-08-03.

### 1. `Subscription.BillingMode`

```sql
Subscription.BillingMode NVARCHAR(20) NOT NULL DEFAULT 'Self'
    CHECK (BillingMode IN ('Self','External'))
```

`Orders.SpawnRenewals` skips `External`. That is the entire change on the orders side — **orders
never learns the word "contract"**; the linkage (`ContractLine.SubscriptionID`) lives here, pointing
up the graph.

**Why a column and not a convention:** it makes *"exactly one thing spawns orders for a given
subscription"* true **by construction**. Two engines that could both spawn for one subscription is a
duplicate-billing bug, and duplicate billing is the kind of defect a customer finds before we do. A
`Self` subscription covered by an active contract line is a validation failure on the contracts side,
not a race.

**`AutoRenew = 0` cannot substitute.** It expresses renewal *intent*, not billing *ownership* — a
contract-billed subscription genuinely does renew, it simply does not spawn its own order.
Overloading it would corrupt renewal forecasting and cancellation policy alike.

**Migration impact:** default `'Self'` means every existing subscription keeps today's behaviour. No
backfill, no behaviour change on install.

### 2. A pricing-resolver slot ahead of `Product:`

Orders' master plan states a contract-override slot is *"reserved at the top of the pricing
precedence chain."* **It is not there.** `ResolvePrice` walks:

```
Product:{ProductID} → Category:{chain, nearest first} → Company:{CompanyID} → unkeyed default
```

Those keys are product- and company-shaped. A contracted price is **customer × product × time**,
which none of them can express. Registering at `Company:{sellingCompanyId}` would hijack that slot
for *all* pricing under that company and collide with any genuine company-level plugin — not an
option.

**The good news:** `PriceResolutionContext` **already carries** `OrganizationID`, `PersonID` and
`AsOf`. The context is sufficient as-is, so this is a change to the **key walk only** — no signature
change, no context change, no caller churn.

Contracts then ships `ContractPriceResolver extends BasePriceResolver`, which:

1. finds the active contract line for `(OrganizationID | PersonID, ProductID, AsOf)`;
2. returns `ContractedUnitPrice` with escalation applied from the term's rules, plus a
   `PriceComponentDraft` trail so the explanation names the contract;
3. returns `null` when no contract covers it — declining, so the walk continues normally;
4. **refuses** when two active contracts cover the same product for the same customer, naming both.

That last point matters, and it matches the contract `Orders.PreviewPrice` already documents: *"an
ambiguous rule set is a refusal, not a fault: it is a configuration problem the caller can fix, and
the message names the rules that collided."* Silently picking one would be a wrong answer wearing a
right answer's clothes.

**The payoff:** contracted prices apply to **ad-hoc orders too**, not just billing-schedule output.
That is precisely where hand-maintained contract pricing normally leaks, and it comes free from
putting the logic in the resolver rather than in the billing engine.

---

## What You Get

### Database (`__mj_BizAppsContracts` schema)

Nine tables. Configuration-as-data throughout: a `ContractType` row carries the defaults and the
engine **reads** them rather than branching on a type string.

| Table | Purpose |
|---|---|
| **`ContractType`** | Named defaults for a class of agreement — term length, billing frequency, auto-renew, escalation, cancellation window, renewal mode, co-term allowance. Optional `DriverClass`. Seeded: *Standard, MSA, SOW, Membership, Evergreen, Pilot* |
| **`Contract`** | The agreement. `CTR-{seq}` numbering, selling `CompanyID`, customer (Organization **xor** Person, `CHECK`-enforced), `ParentContractID` self-FK for MSA→SOW nesting, status, executed-document `FileID` |
| **`ContractTerm`** | The period. Start/end, committed amount, escalation percent + basis, billing frequency and anchor, `RenewalOfTermID` chain back through prior terms, `RenewalProbability` |
| **`ContractLine`** | What is covered. `LineType` (`Subscription` \| `OneTime` \| `Milestone` \| `Usage` \| `Minimum`) is what lets **one table** serve all five; nullable `ContractedUnitPrice` (null = resolve normally); `SubscriptionID` → the materialized orders subscription |
| **`ContractBillingSchedule`** | The plan. One term may carry more than one — a quarterly subscription cadence *and* a milestone schedule for the attached SOW |
| **`ContractBillingEvent`** | Each occurrence **and the audit trail**. Answers *"why did the customer get this bill on this date, and what produced it"*. Carries `OrderID` → orders (a legal downward reference) |
| **`ContractCommitment`** | Minimums, prepaid draws, true-ups. `TrueUpPolicy`: `BillShortfall` \| `Forfeit` \| `Rollover` |
| **`ContractAmendment`** | Mid-term change — add product, change quantity or price, co-term, partial terminate. Amendments change a **live** term; renewals start a **new** one |
| **`ContractEvent`** | Immutable lifecycle log, mirroring orders' `SubscriptionEvent`. Never edited, never deleted |

`ContractType.DriverClass` is **optional**, following `SubscriptionType`'s pattern rather than
`RevenueRecognitionType`'s: the columns *are* the rules, a base behaviour class reads them, and a
driver is supplied only when a customer needs something the columns cannot express. A driver-only
model would force a class per permutation of term × cadence × renewal × escalation — exactly the
combinatorial explosion configuration exists to avoid.

> **`ContractEvent` and `Activity` are not the same thing.** Customer-visible contract events
> (executed, renewed, terminated) also write a `common.Activity` row via `Common.LogActivity`, so the
> agreement appears on the account timeline. `ContractEvent` is the **system** record; the Activity is
> the **human** one. Neither replaces the other. *(Activity lands with the `bizapps-common` spine;
> contracts degrades gracefully without it.)*

### TypeScript Packages

| Package | NPM Name | Role |
|---|---|---|
| **Entities** | `@mj-biz-apps/contracts-entities` | Strongly-typed entity classes, Zod validation, generated remote-operation bases |
| **Actions** | `@mj-biz-apps/contracts-actions` | Action subclasses — the scheduled billing driver, renewal sweeps |
| **Server** | `@mj-biz-apps/contracts-server` | GraphQL resolvers, remote operations, `ContractsEngine` |
| **Core Entities Server** | `@mj-biz-apps/contracts-core-entities-server` | Server-only entity subclasses — `Save()` overrides, lifecycle hooks, `ContractPriceResolver` |
| **Angular** | `@mj-biz-apps/contracts-ng` | Contract workspace, term timeline, billing-schedule view, amendment dialog |
| **Integration Tests** | `@mj-biz-apps/contracts-integration-tests` | Check bundles dispatched by `mj test` |

---

## Entity model

```
 BizAppsCommon              __mj                       BizAppsOrders
 Organization / Person   Company · User · File     Product · Subscription · Order
      │ customer            │ selling co.                 ▲          ▲        ▲
      ▼                     ▼                             │          │        │
 ┌─────────────────────────────────┐                      │          │        │
 │            Contract             │  ParentContractID ───┐          │        │
 │  CTR-{seq} · type · status      │◄─────────────────────┘          │        │
 │  customer (Org XOR Person)      │   (MSA → SOW nesting)           │        │
 └────────────────┬────────────────┘                                 │        │
                  │ 1 → N                                            │        │
     ┌────────────▼────────────┐   RenewalOfTermID (self-FK,          │        │
     │      ContractTerm       │◄── the chain back through terms)     │        │
     │  dates · committed amt  │                                      │        │
     │  escalation · frequency │                                      │        │
     └──┬──────┬──────┬────────┘                                      │        │
        │      │      │                                               │        │
        │      │      └──────────────► ContractCommitment             │        │
        │      │                       (minimum / prepaid / draw)     │        │
        │      │                                                      │        │
        │      └──► ContractLine ──────── ProductID ──────────────────┘        │
        │            LineType:                SubscriptionID ─────────┘        │
        │            Subscription | OneTime |                                  │
        │            Milestone | Usage | Minimum                               │
        │                                                                      │
        ├──► ContractBillingSchedule ──► ContractBillingEvent ── OrderID ──────┘
        │      (Cadence | Milestone       ONE consolidated order         (a legal
        │       | Custom)                 per event                    downward ref)
        │
        ├──► ContractAmendment ──── ApprovalTaskID ──► BizAppsTasks (soft ref)
        │      (mid-term change; renewals start a NEW term)
        │
        └──► ContractEvent  (immutable lifecycle log)
```

**Cross-app references**

| Reference | Refers to | Lives in |
|---|---|---|
| `Contract.CustomerOrganizationID` / `CustomerPersonID` | `Organization.ID` / `Person.ID` (exactly one) | `bizapps-common` |
| `Contract.CompanyID`, `OwnerUserID`, `DocumentFileID` | `Company` · `User` · `File` | `__mj` |
| `ContractLine.ProductID`, `ContractLine.SubscriptionID` | `Product` · `Subscription` | `bizapps-orders` |
| `ContractBillingEvent.OrderID` | `Order.ID` | `bizapps-orders` |
| `ContractTerm.PaymentTermsTypeID` | `PaymentTermsType` (soft ref — orders owns payment terms) | `bizapps-orders` |
| `ContractAmendment.ApprovalTaskID` | `Task` (soft ref) | `bizapps-tasks` |

Cross-OpenApp-schema **hard** FKs are avoided per Caliber's **DG-6** — a package dependency is not a
schema dependency, because the other app's migrations may not have run.

---

## The billing event

The forcing case, restated: one agreement, three subscription products, a services SOW and a setup
fee, **one quarterly bill**.

Ownership is declared **on the subscription**, so exactly one spawner exists per subscription by
construction:

```
Standalone  (B2C, self-serve, most volume)
    Subscription.BillingMode = 'Self'
    → Orders.SpawnRenewals emits one Order per cycle.        [unchanged from today]

Contract-billed  (most B2B)
    Subscription.BillingMode = 'External'
    → SpawnRenewals skips it.
    → The contract's billing schedule assembles:
          covered subscriptions' current periods
        + one-time fees whose window opens this period
        + milestone / installment draws marked reached
        + usage true-ups for the period
        + minimum-commitment shortfalls per TrueUpPolicy
    → prices the whole thing via Orders.PreviewOrder
    → materializes ONE consolidated Order via Orders.CreateOrderInState.
```

Subscriptions exist happily without contracts and many will — B2C especially. Contracts are the norm
for B2B, but **never required by the model**.

### `Contracts.GenerateBillingEvent(BillingEventID)`

One remote operation, one transaction *(not yet built — phase C3)*:

1. Load the term, its lines, its commitments, and the event.
2. Assemble the draft from the five line types above.
3. Build a `HydratableHeader` + `HydratableLine[]` and call **`Orders.PreviewOrder`** to price it —
   contracted prices resolve through the plugin, so the engine performs no arithmetic of its own.
4. Materialize **one** consolidated order via **`Orders.CreateOrderInState`**.
5. Stamp `OrderID` / `ComputedAmount` / `GeneratedAt`, advance covered subscriptions' periods, write
   a `ContractEvent`.

**All-or-none.** A failure marks the event `Failed` with a reason and does **not** partially bill.

### Driving the schedule

An MJ **Scheduled Job** walks `ContractBillingEvent` rows with `Status='Scheduled'` and
`ScheduledDate <= today`, invoking the operation per event. Bounded per run and idempotent —
re-running must not double-bill, which the `Status` transition guarantees. **`Failed` events surface
in a worklist for a human and are never auto-retried into a duplicate.**

### Co-terming — the thing subscriptions structurally cannot do

Adding a product mid-term creates a `ContractAmendment` plus a `ContractLine` whose `StartDate` is
the amendment date and whose `EndDate` is the **term's** end date. The stub period is prorated on the
next billing event.

This is the capability customers actually ask for and the one per-subscription billing cannot
deliver — because **the contract owns the calendar**.

### Renewal — a renewal is a deal (L-18)

`Contracts.RenewTerm(ContractTermID)` creates the next `ContractTerm` with `RenewalOfTermID` set,
applies the escalator, rolls lines forward (minus anything with a hard end date), regenerates the
billing schedule and re-points covered subscriptions.

**Who triggers it:** `bizapps-sales` calls it when a renewal deal closes — so renewal gets its own
pipeline, forecast and win-rate rather than happening invisibly inside a contract record. This is the
same fact that makes the cardinality one-contract-to-many-deals. Auto-renew without a deal stays
available for evergreen and B2C (`ContractType.RenewalMode`); that path calls the same operation from
the Scheduled Job.

Mid-term changes that do **not** restart a term stay amendments.

---

## Approvals run on BizApps Tasks

Non-standard terms, discounts beyond a rep's `SalesAuthority` (orders), and early-termination waivers
raise an **Approval Request Task** in [BizApps Tasks](https://github.com/MemberJunction/bizapps-tasks),
linked to the contract or amendment and routed to an approver role. `TaskType` `OnComplete` /
`OnReject` Action hooks call back into contracts to advance or reject.

Tasks is the **state machine for long-arc human review** across the BizApps family — the same
substrate accounting uses for batch approval and sales uses for close-won routing. Contracts does not
invent a second one.

**Approval level is data, and it varies by organization.** The caps live in orders' `SalesAuthority`
(`MaxDiscountPct`, `MaxOrderValue`, allowed payment terms and product categories); the audit trail
lives on `OrderAdjustment` (`AuthorizedBySalesAuthorityID`, `ApprovedByUserID`, `ApprovedAt`); the
routing lives in tasks. Nothing here is hardcoded.

> **Open question — escalation ladders.** `SalesAuthority` is a *flat cap per rep*. It expresses
> single-gate approval well ("Johanna clears up to 20%") but cannot express tiers (">20% to the
> manager, >40% to the CFO") as configuration. If an org needs tiers, that is a threshold→role table
> belonging in **orders** beside `SalesAuthority` — ad-hoc order confirm needs it too, not only
> contracts and deals. Not built until confirmed.

---

## Local development

Orders and Accounting are **not published to npm**, so this repo resolves them through sibling
checkouts declared in `.mj-links.json` and symlinked by `scripts/link-local-apps.mjs` on
`postinstall`. Check out the whole family as peers:

```
develop/M5/
├── bizapps-common/         (npm: @mj-biz-apps/common-*@5.32.0 ✓ published)
├── bizapps-tasks/          (npm: @mj-biz-apps/tasks-*@1.2.0   ✓ published)
├── bizapps-accounting/     (unpublished — sibling link required)
├── bizapps-orders/         (unpublished — sibling link required)
└── bizapps-contracts/      ← this repo
```

> **This is a known-bad interim hack, and it is deliberate.** Raw symlinks avoid `npm link`'s global
> invisible state and `file:`'s transitive-resolution failure, but they put contracts **two hops**
> from an unpublished dependency (contracts → orders → accounting) where orders is only one. The
> module-identity collapse that makes this work — `type-graphql`, `graphql` and `reflect-metadata`
> must resolve to exactly one copy — has never been exercised at this depth. A pnpm-based fix is in
> flight from the platform team; this survives until then. Read the header comment in
> `scripts/link-local-apps.mjs` before touching anything about resolution.

---

## Database support

SQL Server is the **source of truth** for migrations. PostgreSQL is supported via automatic
conversion using [`@memberjunction/sql-converter`](https://github.com/MemberJunction/MJ/tree/main/packages/SQLConverter).

```
migrations/       ←  T-SQL, hand-written (source of truth)
migrations-pg/    ←  PG, produced by `npx mj sql-convert` (+ .pg-only patches)
```

**Pre-production practice:** while nothing is deployed, schema changes **edit the baseline migration
in place** and rebuild on a clean database, rather than stacking fix-up migrations. This is the
practice orders adopted, and it is only safe because rebuilding from zero is routine
(`scripts/rebuild-db.sh`). **Switch to additive-only at first publish.**

---

## Testing

Two layers, following the orders convention exactly.

**Unit** — `npm test` per package. Pure logic only (escalation arithmetic, proration, commitment
true-up banding), no database.

**Integration** — check bundles driving a live database through the real stack, dispatched by
`mj test`. Nothing is mocked. Each check owns a transaction that always rolls back.

```bash
# fast inner loop
node test-harnesses/integration.mjs contract-pricing

# the CI path
RUN_MUTATION_TESTS=1 MJ_INTEGRATION_TEST=1 \
  npm run mj -- test suite --name "BizApps Contracts Integration"
```

> **`RUN_MUTATION_TESTS=1` is not optional.** Every check is `RequiresMutation`, and MJ's driver
> contains `if (check.RequiresMutation && !mutationEnabled) continue;` — so a run without it executes
> **nothing and reports success**. `scripts/assert-check-count.mjs` exists because a green tally is
> not evidence on its own; it fails if fewer checks ran than the registry declares.

CI runs **unit tests only, deliberately** — the integration suite needs SQL Server plus sibling
checkouts of two unpublished repos, which is a local development environment and not a hosted runner.
A red X everyone learns to ignore is worse than a documented manual gate. The integration suite is a
**pre-merge step run locally**.

The checks that must exist before this app is trustworthy:

- contracted price **wins** over list price, **declines** cleanly when no contract covers a product,
  and **refuses** when two contracts collide;
- a `Self` subscription covered by an active contract line is a **validation failure**;
- `GenerateBillingEvent` produces exactly one order, and a forced failure mid-assembly bills
  **nothing**;
- re-running the scheduled driver over an already-`Generated` event does **not** double-bill;
- a co-term stub prorates to the term end date, not to a subscription anniversary.

---

## Repository structure

```
bizapps-contracts/
├── mj-app.json                    # MJ Open App manifest (schema __mj_BizAppsContracts)
├── mj.config.cjs                  # CodeGen config + SQL → PG placeholder rules
├── .mj-links.json                 # sibling links to unpublished orders + accounting
├── apps/
│   ├── MJAPI/                     # GraphQL API server (port 4151)
│   └── MJExplorer/                # Angular UI application (port 4351)
├── packages/
│   ├── Entities/                  # @mj-biz-apps/contracts-entities
│   ├── Actions/                   # @mj-biz-apps/contracts-actions
│   ├── Server/                    # @mj-biz-apps/contracts-server
│   ├── CoreEntitiesServer/        # @mj-biz-apps/contracts-core-entities-server
│   ├── IntegrationTests/          # @mj-biz-apps/contracts-integration-tests
│   └── Angular/                   # @mj-biz-apps/contracts-ng
├── migrations/                    # T-SQL migrations (source of truth)
├── migrations-pg/                 # PG migrations (converter output)
├── metadata/                      # Seed data — ContractType et al., synced via mj-sync
├── metadata-tests/                # MJ: Tests + Test Suite records
├── scripts/                       # rebuild-db.sh, append-codegen.sh, link-local-apps.mjs
├── test-harnesses/                # standalone dispatchers
└── plans/
    └── bizapps-contracts-master.md
```

All seed vocabulary ships as `metadata/<type>/` with **hardcoded UUIDs**, following the
`bizapps-common` `address-types` pattern. **Never** SQL `INSERT`s in a migration.

---

## Build sequence

| Phase | Work | Status |
|---|---|---|
| **C0** | **Orders PR** — `Subscription.BillingMode` + the resolver pre-walk slot. **Land first.** | Not started |
| **C1** | Repo bootstrap, `mj-app.json`, baseline migration (nine tables), CodeGen, `ContractType` seed metadata | In progress |
| **C2** | `ContractPriceResolver` + registration; integration checks proving contracted price wins, declines cleanly, and refuses on ambiguity | Not started |
| **C3** | Billing-event engine + `Contracts.GenerateBillingEvent` + the Scheduled Job | Not started |
| **C4** | `Contracts.CreateFromDeal` · renewal · amendment · co-term operations | Not started |
| **C5** | Angular: contract workspace, term timeline, billing-schedule view, amendment dialog | Not started |
| **C6** | PG conversion, docs, ERD, changeset, release | Not started |

### Open questions

| # | Question | Recommendation |
|---|---|---|
| **D-2** | Does the resolver slot ship as an `Agreement:`-keyed step, or a general pre-walk registration any downstream app may use? | **General pre-walk** — same cost, and the next downstream app needing a pricing override does not require a third orders PR |
| **D-5** | Does contracts own an `Agreement`/MSA level *above* `Contract`? | **Defer** — `ParentContractID` self-FK handles MSA→SOW nesting; promote to a distinct entity only if the two genuinely diverge |
| — | **Usage metering source.** `LineType='Usage'` needs a quantity from somewhere; orders' metering engine is deferred | **Out of v1** — keep `Usage` in the value list so the schema need not change when it arrives |
| — | **Multi-currency.** Orders defers FX (D24) | Record `CurrencyID` on the term for forward-compatibility; **do no conversion** |

---

## On CDP

CDP's `finance.Contract` / `ContractTerm` / `ContractTermLineItem` / `ContractTermPaymentSchedule` is
**not a reference design and is not an input to this model** (**L-20**). It is what Blue Cypress runs
right now: INT primary keys, no shared product catalog, a private payment-schedule table, JE status
copied onto the contract, and no way to consolidate a bill across revenue streams. It does not scale
and we are replacing it, not porting it.

The model above was derived from the problem. The only reason to open CDP during this build is
**data migration** at cutover — a migration exercise with its own document, not a design activity.

---

## Documentation

| Document | Description |
|---|---|
| [Master plan](plans/bizapps-contracts-master.md) | **The app's source of truth** — data model, the billing-event engine, the orders seams, build sequence |
| [BizApps Orders](https://github.com/MemberJunction/bizapps-orders) | The catalog, pricing engine and receivable this app produces into |
| [BizApps Sales](https://github.com/MemberJunction/bizapps-sales) | The pipeline that calls `Contracts.CreateFromDeal` |
| [BizApps Tasks](https://github.com/MemberJunction/bizapps-tasks) | The approval substrate |
| [BizApps Accounting](https://github.com/MemberJunction/bizapps-accounting) | The ledger orders emits into |

---

## Tech stack

| Layer | Technology | Version |
|---|---|---|
| **Platform** | [MemberJunction](https://github.com/MemberJunction/MJ) | 5.50+ |
| **Runtime** | Node.js | 18+ |
| **Language** | TypeScript | 5.9 (strict) |
| **Database (primary)** | SQL Server / Azure SQL | 2019+ |
| **Database (secondary)** | PostgreSQL | 17 |
| **API** | GraphQL (Apollo Server) | — |
| **UI Framework** | Angular | 21 |
| **Build** | Turborepo | 2.7 |
| **Validation** | Zod | 3.24 |

---

## License

Business Source License 1.1 — see [LICENSE](./LICENSE) for details.

---

<p align="center">
  Built on <a href="https://github.com/MemberJunction/MJ">MemberJunction</a> — the metadata-driven application platform.
</p>
