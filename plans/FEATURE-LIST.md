# bizapps-contracts — feature list

> Derived from the migration + master plan on 2026-08-05. Stable IDs; never renumber.

**Sources, in authority order:** `migrations/B202608040001__v0.1.x__Schema_and_Types.sql` +
`migrations/V202608040002__v0.1.x__Tables_and_Objects.sql` (ground truth) ·
`plans/bizapps-contracts-master.md` §10–§13 · `docs/ERD.md` · `design-docs/ui-design/mockups/*.html`.

**Scope of the schema as built:** 10 tables · **55** CHECK constraints · 13 internal FKs · 13
cross-app FKs · **6** unique indexes (two filtered) · 2 covering read indexes.

> **Re-counted against a from-zero re-migration on 2026-08-05** — i.e. what the committed migration
> alone produces, not what the live database happened to have (was 48 CHECKs and 5 unique indexes). The five added: `CK_Contract_SupersededHasSuccessor`,
> `CK_ContractLine_SubscriptionNeedsType`, `CK_ContractBillingEvent_GeneratedHasTimestamp`,
> `CK_ContractAmendment_ApprovedHasTask`, `CK_ContractEvent_EventType`, plus
> `CK_ContractType_MaxEscalationPercent` and `CK_ContractType_RenewalNoticeDays` — and the new
> filtered `UQ_ContractLine_Subscription`. `CK_ContractBillingEvent_Status` was WIDENED (it gained
> `Cancelled`) rather than added, so it is not part of the +7.
>
> The Appendix below still enumerates the original 48 and has NOT been re-derived; §7.1 of
> `docs/ERD.md` carries the new ones. Saying so is the point — an un-re-derived appendix that claims
> to be complete is worse than one that admits its date.

**Test tiers** (per `.mjdev-docs/TEST-ARCHITECTURE.md`):
`unit` = pure logic, no DB · `server` = tier-2, in-process direct SQL / `BaseEntity` against the real
DB · `api` = tier-3, the app's real client over MJAPI · `ui` = tier-4 component+API headless, or
tier-5 Playwright where the browser is the point.

**Reading a CHECK row:** "working" means *the write is rejected by that named constraint*. A test
that merely proves a legal value saves is not coverage — every constraint row needs a **rejected**
case and an **accepted** boundary case. Where a constraint is `X IS NULL OR <rule>`, NULL is a third
required case.

---

## A. Contract identity, numbering and the sequence

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| A.1 | `CTR-{seq}` number assignment | Saving a new `Contract` with no `ContractNumber` allocates the next value from `ContractSequence` and writes `CTR-000001`-shaped text; `ContractSequence.NextSequenceNumber` advances by exactly 1. Two concurrent creates get two different numbers and the counter lands at start+2 (no gap-free guarantee, but no duplicate). **Not built** — the create mockup shows "CTR-001852 — assigned on create"; today the number is typed. | `ContractEntity` subclass (queue item 2) | server |
| A.2 | `ContractNumber` is globally unique | Inserting a second `Contract` with an existing `ContractNumber` fails on `UQ_Contract_ContractNumber`. Case sensitivity follows the DB collation — assert the actual behaviour, don't assume. | A.1 | server |
| A.3 | `CK_ContractSequence_Singleton` | `INSERT INTO ContractSequence (ID, NextSequenceNumber) VALUES (2, 1)` is rejected by `CK_ContractSequence_Singleton`; `ID = 1` is accepted. The table can never hold a second counter row. | — | server |
| A.4 | `CK_ContractSequence_NextSeq` | Setting `NextSequenceNumber = 0` or `-1` is rejected by `CK_ContractSequence_NextSeq`; `1` is accepted. The counter can never be reset to a non-positive value. | — | server |
| A.5 | The counter row exists after a clean install | After `migrate` on an empty DB, `SELECT NextSequenceNumber FROM ContractSequence WHERE ID = 1` returns exactly one row with value `1` — seeded by the migration's own `INSERT` (the deliberate exception to "seeds ship via metadata"). | Q.1 | server |
| A.6 | The counter is reachable through the generated CRUD | `MJ_BizApps_Contracts: Contract Sequences` is a full MJ entity with generated `spUpdate`/`spDelete`, so any user with entity permission can rewrite or delete the counter. Test: prove the entity exists and prove what permission is required to write it — then decide whether that is acceptable. This is an exposure to rule on, not a bug yet. | Q.5 | api |

---

## B. Contract lifecycle and every status transition

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| B.1 | `CK_Contract_Status` — the six-value list | `Status` accepts exactly `Draft`, `PendingSignature`, `Active`, `Expired`, `Terminated`, `Superseded`. `'active'` (wrong case), `'Cancelled'`, `''` are each rejected by `CK_Contract_Status`. Six accept cases, three reject cases. | — | server |
| B.2 | `Draft` is the default | Inserting a `Contract` without naming `Status` yields `Draft`. The create mockup's identity band shows `Draft` before save; the form must not send a different default. | B.1 | server + ui |
| B.3 | `Draft → PendingSignature` via `Contracts.SendForSignature` | The action raises a `__mj.SignatureRequest` against the contract (or term) `EntityID`/`RecordID`, sets `Status = 'PendingSignature'`, and writes a `ContractEvent`. Gated on `ContractType.RequiresSignature = 1` — a type with `RequiresSignature = 0` refuses the action with a named reason. **Status is never set to `PendingSignature` by a direct entity write** (master §10.2/§10.5). **Not built.** | D.7, N.5, N.7 | api + ui |
| B.4 | `PendingSignature → Active` via `Contracts.RecordExecution` | Driven by `SignatureRequest.CompletedAt`: stamps `Contract.ExecutedDate`, attaches the executed PDF via `FileEntityRecordLink`, sets `Status = 'Active'`, writes a `ContractEvent`. A contract with `PricedAt IS NULL` cannot reach `Active` (B.11) — the action must fail with that reason rather than a raw constraint error. **Not built.** | B.11, N.1, N.5 | api |
| B.5 | `PendingSignature → Draft \| Terminated` via `Contracts.RecordRejection` | Carries `SignatureRequest.VoidReason` into the `ContractEvent` payload. Both destinations are reachable and the caller chooses. **Not built.** | B.3 | api |
| B.6 | `Active → Expired` | A contract whose terms have all `EndDate < today` and which is not auto-renewing becomes `Expired`. No schema rule enforces this — it is engine/scheduled-job behaviour, and the transition must be provable by driving the job, not by asserting a column. **Not built; no owner named in the plan.** | E.1, F.9 | server |
| B.7 | `→ Terminated` via `Contracts.TerminateContract` | Honours `CancellationWindowDays` and `ContractTerm.EarlyTerminationDate`: terminating inside the notice window is refused (or flagged for approval), outside it succeeds and stamps the terminating `ContractEvent`. **Not built.** | B.12, E.14, L.5 | api |
| B.8 | `→ Superseded` names its successor | Setting `Status = 'Superseded'` and `SupersededByContractID` to the replacement contract makes `SELECT` on the successor chain navigable both ways. **See "Contradictions found" X.6 — the schema does NOT require `SupersededByContractID` when `Status = 'Superseded'`.** Test the intended rule at the entity layer. | B.9, X.6 | server |
| B.9 | `CK_Contract_SupersededNotSelf` | `UPDATE Contract SET SupersededByContractID = ID` is rejected by `CK_Contract_SupersededNotSelf`. `NULL` accepted; another contract's ID accepted. | — | server |
| B.10 | `CK_Contract_ParentNotSelf` | `UPDATE Contract SET ParentContractID = ID` is rejected by `CK_Contract_ParentNotSelf`. `NULL` accepted; another contract's ID accepted (the MSA→SOW case). | — | server |
| B.11 | `CK_Contract_PricedWhenActive` | Saving a `Contract` with `Status = 'Active'` and `PricedAt IS NULL` is rejected by `CK_Contract_PricedWhenActive`. `Status = 'Draft'` with `PricedAt IS NULL` is accepted. `Status = 'Active'` with `PricedAt = '2026-01-01'` is accepted. **Note the hole: `Expired`/`Terminated`/`Superseded` with `PricedAt IS NULL` is also accepted** (X.7). | G.1 | server |
| B.12 | `CK_Contract_CancellationWindow` | `CancellationWindowDays = -1` is rejected by `CK_Contract_CancellationWindow`; `0` and `90` are accepted; `NULL` is accepted (fall back to `ContractType.DefaultCancellationWindowDays`). | D.5 | server |
| B.13 | `ExecutedDate` before `EffectiveDate` is **legal** | Saving `ExecutedDate = 2025-12-14`, `EffectiveDate = 2026-01-01` succeeds. This is the ordinary annual-term case (sign in December, effective Jan 1); the CHECK that forbade it was removed on 2026-08-04 after realistic demo data caught it. A regression test must pin this **acceptance** so nobody re-adds the constraint. | B.1 | server |
| B.14 | `ExternalReferenceID` round-trips | An arbitrary 255-char external key saves and reads back byte-identical; it is not unique and duplicates are legal (two contracts migrated from the same CDP record). | — | server |
| B.15 | `TerminationPolicy` free text | `NVARCHAR(MAX)` clause text saves and renders in the workspace Overview without truncation or HTML injection. | P.3 | server + ui |
| B.16 | `AutoRenew` default `0` | A contract created without naming `AutoRenew` reads `0`; the create form pre-fills it from `ContractType.DefaultAutoRenew` and that pre-fill is the only place the type's default is applied (the DB default stays `0`). | D.7 | server + ui |
| B.17 | `Description` free text | `NVARCHAR(MAX)` saves and reads back. | — | server |
| B.18 | `ParentContractID` — MSA → SOW nesting | An SOW contract saved with `ParentContractID` = the MSA's ID resolves, and the list view renders "under CTR-001812" as the mockup shows. Deleting the parent while a child references it **fails** (no cascade — Q.4). | B.10, Q.4 | server + ui |
| B.19 | Multi-hop parent/supersession cycles are **not** prevented | `A.ParentContractID = B` and `B.ParentContractID = A` both save — the CHECKs only block direct self-reference, and the migration comment says deeper cycles "are the engine's problem." A test must prove the cycle saves today, and a second test must prove whatever guard the engine eventually adds. | B.10 | server |

---

## C. Customer, parties and the XOR rule

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| C.1 | `CK_Contract_CustomerXor` — exactly one customer | Four cases, all required: (a) `CustomerOrganizationID` set + `CustomerPersonID` NULL → accepted; (b) Person set + Org NULL → accepted; (c) **both set → rejected by `CK_Contract_CustomerXor`**; (d) **both NULL → rejected by `CK_Contract_CustomerXor`**. The constraint is written as a `CASE`-sum equalling 1 precisely so each column is named once — CodeGen derives the generated validation method name from the expression, and repeating a column makes it emit a call to a method it never defines (a generated-code build break orders already hit). So a fifth test: **the generated entity subclass compiles**, and its generated validator rejects (c) and (d) client-side too. | O.4, O.5 | server + unit |
| C.2 | Customer = organization | `CustomerOrganizationID` resolves to a real `__mj_BizAppsCommon.Organization`; a random GUID is rejected by `FK_Contract_CustomerOrganization`. | O.4 | server |
| C.3 | Customer = person | `CustomerPersonID` resolves to a real `__mj_BizAppsCommon.Person`; a random GUID is rejected by `FK_Contract_CustomerPerson`. The B2C path. | O.5 | server |
| C.4 | `PrimaryContactPersonID` is independent of the customer | An org-customer contract may name a person as primary contact; that person need not belong to the customer org (no constraint says so). Both "set" and "NULL" save. | O.6 | server |
| C.5 | `CompanyID` is the **selling** company, not the customer | `CompanyID` is `NOT NULL` and resolves to `__mj.Company`. The workspace identity band must read "sold by Blue Cypress" — a UI test that labels it "customer" is a real defect. | O.1 | server + ui |
| C.6 | `OwnerUserID` — the account director | Nullable FK to `__mj.User`; saves set and NULL. Surfaces as "owner Dana Whitfield" in the identity band. | O.2 | server + ui |
| C.7 | **No `Contract.DealID`, in any form** (L-15) | `SELECT * FROM sys.columns` for `Contract` returns no column whose name contains `Deal`, and no FK targets any `bizapps-sales` object. A test that asserts this **absence** is the guard against someone "helpfully" adding it. The reverse lookup is `Deal.ContractID` / `Deal.RenewsContractID` in sales and returns a **set**. | Y.5 | server |

---

## D. `ContractType` — configuration as data

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| D.1 | `CK_ContractType_BillingFrequency` | `DefaultBillingFrequency` accepts exactly `Monthly`, `Quarterly`, `SemiAnnual`, `Annual`, `Milestone`, `Custom`, or NULL. `'Weekly'` is rejected by `CK_ContractType_BillingFrequency`. Six accepts + NULL + one reject. | — | server |
| D.2 | `CK_ContractType_RenewalMode` | `RenewalMode` accepts exactly `Deal`, `Auto`, `Manual` — **NULL is NOT allowed** (column is `NOT NULL DEFAULT 'Deal'`). `'None'` is rejected by `CK_ContractType_RenewalMode`. | F.9 | server |
| D.3 | `CK_ContractType_TermMonths` | `DefaultTermMonths = 0` and `-12` are rejected by `CK_ContractType_TermMonths`; `1` and `12` accepted; NULL accepted. | — | server |
| D.4 | `CK_ContractType_EscalationPercent` | `DefaultEscalationPercent = -0.01` is rejected by `CK_ContractType_EscalationPercent`; `0`, `0.04` accepted; NULL accepted. Stored as a **fraction** — `0.04` is 4%. | G.8 | server |
| D.5 | `CK_ContractType_CancellationWindow` | `DefaultCancellationWindowDays = -1` is rejected by `CK_ContractType_CancellationWindow`; `0` and `90` accepted; NULL accepted. | B.12 | server |
| D.6 | `UQ_ContractType_Code` | A second `ContractType` with `Code = 'MSA'` fails on `UQ_ContractType_Code`. `Name` is deliberately **not** unique — renaming a type is safe, changing its `Code` is not (`bizapps-sales`' `CloseWonPolicy` references `Code`). | — | server |
| D.7 | `RequiresSignature` / `DefaultAutoRenew` defaults | A type inserted without naming them reads `RequiresSignature = 1`, `DefaultAutoRenew = 0`. `RequiresSignature` is the gate on `Contracts.SendForSignature` (B.3). | B.3, B.16 | server |
| D.8 | `DefaultMaxEscalationPercent` — the renewal ceiling | Saves and flows into `ContractTerm.MaxEscalationPercent` as the create-form default. **There is no CHECK on this column** — `-0.05` saves today. See X.2. | F.3, X.2 | server |
| D.9 | `DefaultRenewalNoticeDays` — written notice before a price change | Saves and flows into `ContractTerm.RenewalNoticeDays`. **Distinct from `DefaultCancellationWindowDays`** — many agreements set them equal but they are different clauses, and the UI must label them separately (the create mockup does). **No CHECK on this column** — `-30` saves today. See X.2. | F.4, X.2 | server + ui |
| D.10 | `AllowsCoterm` | Default `1`. A type with `AllowsCoterm = 0` must make the workspace's "Add product (amendment)" co-term path unavailable, and the co-term amendment must refuse. **Nothing reads this column today** — a grep proving no consumer exists is itself the current finding. | H.17, L.7 | server + ui |
| D.11 | `DriverClass` is optional | NULL is the normal case: the columns *are* the rules and a base behaviour class reads them. When set, it is a ClassFactory key resolving to a `ContractType` behaviour subclass. Test both: NULL type drives the base behaviour; a registered driver overrides exactly the step it means to. **No base behaviour class exists yet.** | — | unit + server |
| D.12 | `IsActive` | Default `1`. An inactive type must not appear in the create form's type picker but must still resolve on existing contracts. | P.2 | ui |
| D.13 | Type defaults populate the create form and are then **decoupled** | Choosing "MSA" pre-fills term months, billing frequency, escalation, cap, notice days, cancellation window and auto-renew on the new contract/term. Changing the type afterwards re-prefills only untouched fields. Editing the type later does **not** retroactively change existing contracts — the defaults are copied at create time, not read through. | D.1–D.10 | ui |
| D.14 | Seeded types: `Standard`, `MSA`, `SOW`, `Membership`, `Evergreen`, `Pilot` | After a clean `migrate` + `sync`, all six rows exist with stable hardcoded UUIDs, sourced from `metadata/contract-types/`. **NOT BUILT — this is the highest-severity gap in the app: `metadata/` contains only `applications/` and `schema-info/`, so a clean install has ZERO contract types, and `Contract.ContractTypeID` is `NOT NULL`. No contract can be created on a fresh install.** The only type in the dev DB (`MSA`) came from raw SQL in `demo/seed-demo-contract.sql`, which does not ship. | Q.8 | server |

---

## E. Term structure, numbering and dates

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| E.1 | `CK_ContractTerm_Status` — the five-value list | Accepts exactly `Pending`, `PendingSignature`, `Active`, `Completed`, `Terminated`. `'Expired'` is rejected by `CK_ContractTerm_Status` (that value belongs to `Contract`, not the term — a real trap). Default is `Pending`. Note `PendingSignature` on the **term** is what makes the re-papered-each-period pattern expressible; master plan §3.3 still lists only four values (X.4). | X.4 | server |
| E.2 | `CK_ContractTerm_Dates` | `EndDate = StartDate - 1 day` is rejected by `CK_ContractTerm_Dates`. `EndDate = StartDate` is **accepted** (a one-day term is legal). `EndDate > StartDate` accepted. | — | server |
| E.3 | `CK_ContractTerm_TermNumber` | `TermNumber = 0` and `-1` are rejected by `CK_ContractTerm_TermNumber`; `1` accepted. Terms are 1-based. | — | server |
| E.4 | `UQ_ContractTerm_Contract_TermNumber` | A second term with the same `(ContractID, TermNumber)` fails on `UQ_ContractTerm_Contract_TermNumber`. The **same** `TermNumber` on a *different* contract succeeds. | E.3 | server |
| E.5 | `TermNumber` is derived, not typed | Saving a new term with no `TermNumber` assigns `MAX(TermNumber) + 1` for that contract; the first term gets `1`. Two concurrent renewals of the same contract must not both get the same number — the unique index (E.4) is the backstop and one of the two must fail cleanly, not deadlock. **Not built** (queue item 2). | E.4 | server |
| E.6 | `CK_ContractTerm_BillingFrequency` | `BillingFrequency` is `NOT NULL` and accepts exactly `Monthly`, `Quarterly`, `SemiAnnual`, `Annual`, `Milestone`, `Custom`. NULL is rejected by the column's nullability; `'Weekly'` is rejected by `CK_ContractTerm_BillingFrequency`. | I.2 | server |
| E.7 | `CK_ContractTerm_AnchorMonth` | `BillingAnchorMonth = 0` and `13` are rejected by `CK_ContractTerm_AnchorMonth`; `1` and `12` accepted; NULL accepted. | E.8 | server |
| E.8 | `CK_ContractTerm_AnchorDay` | `BillingAnchorDay = 0` and `32` are rejected by `CK_ContractTerm_AnchorDay`; `1` and `31` accepted; NULL accepted. **The schema permits `BillingAnchorMonth = 2, BillingAnchorDay = 31`** — a date that does not exist. The billing engine must define what Feb 31 means (clamp to month end is the usual answer) and a test must pin that choice. | E.7 | server + unit |
| E.9 | `CK_ContractTerm_CommittedAmount` | `CommittedAmount = -1` is rejected by `CK_ContractTerm_CommittedAmount`; `0` accepted; `486000.0000` accepted at full `DECIMAL(19,4)` precision (assert no silent rounding). NULL accepted. | — | server |
| E.10 | `CK_ContractTerm_RenewalProbability` | `-0.01` and `1.01` are rejected by `CK_ContractTerm_RenewalProbability`; `0`, `0.85`, `1` accepted; NULL accepted. Stored as a **fraction** — the workspace renders `0.85` as "85%". A UI test must prove the ×100 conversion in **both** directions (display and entry). | P.3 | server + ui |
| E.11 | `ContractTerm.ExecutedDate` — per-term paper | A renewal term that produced its own signed document stamps its own `ExecutedDate`; an auto-renewing term legitimately leaves it NULL. This plus term-level `PendingSignature` is what lets one schema serve both the evergreen pattern (one document, many periods) and the re-papered pattern. | E.1, N.2 | server |
| E.12 | `PaymentTermsTypeID` → orders | Resolves to `__mj_BizAppsOrders.PaymentTermsType`; a random GUID is rejected by `FK_ContractTerm_PaymentTermsType`. NULL accepted. The create form's "Payment terms" list is populated **from orders**, not from a local copy. | O.12 | server + ui |
| E.13 | `CurrencyID` → accounting, recorded only | Resolves to `__mj_BizAppsAccounting.Currency`; NULL accepted. **Nothing in this app converts between currencies** (orders defers FX per D24). A test must prove no code path reads this column to compute anything — a grep for consumers is the assertion. | O.13 | server |
| E.14 | `EarlyTerminationDate` | Saves; read by `Contracts.TerminateContract` to decide whether a termination is early. No CHECK relates it to `StartDate`/`EndDate` — a date outside the term saves today. | B.7 | server |
| E.15 | `Notes` free text | `NVARCHAR(MAX)` round-trips. | — | server |
| E.16 | Terms may **overlap** — no constraint prevents it | Two `Active` terms on one contract covering the same calendar period both save. Only `TermNumber` is unique. The billing engine would then bill both. Test: prove the overlap saves today; then test whatever entity-level guard is added. | E.4 | server |
| E.17 | `Contracts.ActivateTerm` — `Pending → Active` | Generates the term's `ContractBillingSchedule` rows **and** their `ContractBillingEvent` occurrences from `BillingFrequency` + anchor, then writes a `ContractEvent`. Concretely: activating a 12-month term with `BillingFrequency='Quarterly'`, anchor Jan 1, produces exactly 4 `Scheduled` events dated Jan 1 / Apr 1 / Jul 1 / Oct 1. Re-running it must not produce 8. **Not built.** | I.4, J.1 | api |

---

## F. Renewal chain, escalation and its cap

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| F.1 | `CK_ContractTerm_RenewalNotSelf` | `UPDATE ContractTerm SET RenewalOfTermID = ID` is rejected by `CK_ContractTerm_RenewalNotSelf`; NULL and another term's ID accepted. | — | server |
| F.2 | `CK_ContractTerm_EscalationBasis` | Accepts exactly `PriorTerm`, `ListPrice`, `Index`, or NULL. `'CPI'` is rejected by `CK_ContractTerm_EscalationBasis`. `Index` is in the list deliberately although no index feed exists (P-3) — a test must prove the value **saves** and that the engine **refuses to execute** an `Index` basis with a named reason rather than silently escalating by zero. | Y.3 | server |
| F.3 | `CK_ContractTerm_MaxEscalationPercent` | `MaxEscalationPercent = -0.01` is rejected by `CK_ContractTerm_MaxEscalationPercent`; `0` and `0.05` accepted; NULL accepted (no ceiling). | — | server |
| F.4 | `CK_ContractTerm_RenewalNoticeDays` | `RenewalNoticeDays = -1` is rejected by `CK_ContractTerm_RenewalNoticeDays`; `0` and `60` accepted; NULL accepted. Distinct clause from `Contract.CancellationWindowDays` — assert both can hold different values on the same agreement. | B.12, D.9 | server |
| F.5 | `EscalationPercent` accepts a **negative** rate | `EscalationPercent = -0.05` saves — there is **no** CHECK on this column, though `ContractType.DefaultEscalationPercent` has `>= 0`. See X.1. Test: prove `-0.05` saves today, and prove the entity-level guard once added. | X.1 | server |
| F.6 | The escalation **cap** is not enforced at write time | `EscalationPercent = 0.08` with `MaxEscalationPercent = 0.05` **saves successfully** — there is no `CK_ContractTerm_EscalationWithinCap`. The plan calls an uncapped increase "the single most disputed clause in a B2B renewal," so the cap must be enforced somewhere: the entity subclass on save, and the resolver at escalation time (min(EscalationPercent, MaxEscalationPercent)). Test all three: the write is currently permitted; the entity guard rejects it; the resolver clamps. **See X.1 — this is the highest-value contradiction in the app.** | F.3, F.5, X.1 | server + unit |
| F.7 | `Contracts.RenewTerm(ContractTermID)` | Creates the next `ContractTerm` with `RenewalOfTermID` set to the source term, `TermNumber` = source + 1, dates rolled forward by the term length, the escalator applied, lines rolled forward **minus anything with a hard `EndDate`**, a regenerated billing schedule, and re-pointed subscriptions. Concretely, from the mockup: Term 2 committed $460,800 renewing at 4.0% produces Term 3 at $486,000 — assert the exact number, not "a term was created". **Not built.** | E.5, F.6, G.3, H.17 | api |
| F.8 | The renewal chain is navigable | Walking `RenewalOfTermID` from the newest term reaches every prior term in order and terminates at the original (`RenewalOfTermID IS NULL`). The workspace "Term history" panel renders that chain with each term's delta ("+4.0% on prior term"). | F.7 | server + ui |
| F.9 | `RenewalMode` drives **who** renews | `Deal` — nothing in this app initiates renewal; `bizapps-sales` calls `Contracts.RenewTerm` when a renewal deal closes (L-18), and renewal gets its own pipeline. `Auto` — the Scheduled Job calls the same operation with no deal. `Manual` — a human triggers it, no automation. Test each mode's trigger path independently; the `Deal` path cannot be tested until sales exists (Y.5). | D.2, F.7 | api |
| F.10 | Renewal ≠ amendment (the model's central distinction) | A renewal creates a **new** `ContractTerm`; a mid-term change creates a `ContractAmendment` against the **existing** one. A test asserting that `RenewTerm` never mutates the source term's `StartDate`/`EndDate`/lines, and that applying an amendment never creates a term, pins the distinction the plan calls "the single most common contract-model mistake." | F.7, L.8 | server |
| F.11 | `RenewalOfTermID` may point at a term on a **different contract** | Nothing constrains the renewed term to the same `ContractID`. `A.Term1` can be recorded as the renewal of `B.Term3` and it saves. See X.8. | F.1, X.8 | server |

---

## G. Pricing — the as-of rule (§12)

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| G.1 | `Contract.PricedAt` locks the catalog read | On save, every `ContractLine` whose price the user accepted from the catalog has that price **written into `ContractedUnitPrice`**, resolved as of `PricedAt`. Concretely: catalog price for product P is $100 on 2026-06-01 and $120 on 2026-08-01; a contract with `PricedAt = 2026-06-15` saves the line at **$100** and it stays $100 after the catalog moves. | O.7 | server + api |
| G.2 | `PricedAt` is backdatable | Setting `PricedAt` to a past date is accepted and resolves the catalog **as of that date** — a contract signed last month entered today must price as of when it was agreed. `PricedAt` defaults to today on manual entry (the create mockup shows "Priced as of 2026-08-04"). Backdating past a catalog change must change the resolved price. | G.1 | ui + api |
| G.3 | First renewal of a NULL-priced line reads the catalog **once** | A line with `ContractedUnitPrice IS NULL` renewed for the first time: resolve the catalog price as of `Contract.PricedAt`, apply `EscalationPercent` capped by `MaxEscalationPercent`, **write the result into the line**. Assert the written number exactly (e.g. catalog $100 as of `PricedAt`, escalation 4%, cap 5% → $104.00 stored). | F.6, G.1 | server |
| G.4 | Every renewal after the first is **self-referential** | The second and later renewals escalate from the contract's **own prior price** and never re-read the catalog. Assert: after G.3 wrote $104.00, a catalog move to $200 does not affect the next renewal, which produces $108.16 (104 × 1.04). This "the catalog is consulted exactly once" property is the whole point of §12 and must be tested with a catalog change in between. | G.3 | server |
| G.5 | No shadow price columns | `ContractLine` has no `ResolvedUnitPrice` / `ResolvedAt` and must never acquire them. Orders owns pricing and price history; each generated bill **is** an order carrying the real price and date, linked from `ContractBillingEvent.OrderID`. A test asserting the columns' **absence** guards a decision that has already been re-proposed once. | J.5 | server |
| G.6 | `ContractPriceResolver` returns the contracted price | Registered ahead of `Product:` in orders' pricing walk, it finds the active contract line for `(OrganizationID \| PersonID, ProductID, AsOf)` and returns `ContractedUnitPrice` with escalation applied, plus a `PriceComponentDraft` trail naming the contract. **The payoff to test: contracted prices apply to *ad-hoc* orders too**, not only billing-schedule output. **Blocked on D-2.** | Y.1 | api |
| G.7 | The resolver **declines** and **refuses** correctly | Returns `null` when no contract covers the product (the walk continues normally — assert the catalog price wins). **Refuses**, naming both contracts, when two active contracts cover the same product for the same customer — never silently picks one. The billing worklist mockup shows exactly this failure text: "Two active contracts cover Data migration services for this customer — CTR-001842 and CTR-001799". **Blocked on D-2.** | G.6, J.3 | api |
| G.8 | Contract discount **overrides**, it does not stack | `ContractLine.DiscountPct = 0.10` on a line that would also attract a 5% order-level discount produces **10%**, not 14.5% and not 15%. Orders owns the mechanics; the contract states negotiated intent that outranks them (Amith, 2026-08-04). Stored as a fraction, matching `OrderLine.DiscountPct`. | H.9 | api |

---

## H. Contract lines and `LineType` — all five values

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| H.1 | `CK_ContractLine_LineType` | Accepts exactly `Subscription`, `OneTime`, `Milestone`, `Usage`, `Minimum`. NULL is rejected by nullability; `'Recurring'` is rejected by `CK_ContractLine_LineType`. Five accepts, two rejects. | — | server |
| H.2 | `LineType = 'Subscription'` behaviour | The billing engine emits charges **for the period being billed** — a quarterly cadence bills one quarter of an annual subscription line, not the annual figure. The line materializes an `orders.Subscription` of type `SubscriptionTypeID`, whose ID lands in `SubscriptionID`, and whose `BillingMode` is set to `External` so `Orders.SpawnRenewals` skips it. **Blocked on the orders seam (Y.2).** | H.11, H.12, Y.2 | api |
| H.3 | `LineType = 'OneTime'` behaviour | Billed **once**, in the period whose window contains the line's `StartDate` — the mockup's "Onboarding setup fee · Month 1". Running the next billing event must not bill it again. Assert the second event's assembled draft omits it. | J.7 | api |
| H.4 | `LineType = 'Milestone'` behaviour | Billed when its milestone is marked reached, not on the cadence. The mockup shows "Data migration services · 3 milestones" driven by a separate `ScheduleType='Milestone'` schedule on the same term. **Where "reached" is recorded is not in the schema** — see Y.6. | I.1, Y.6 | api |
| H.5 | `LineType = 'Usage'` — value present, capability out of v1 | The value **saves** (so the schema does not change when metering arrives), and the billing engine must **refuse with a named reason** rather than bill zero. Nothing supplies a quantity: orders' metering engine is deferred (P-2). Test both halves. | Y.4 | server + api |
| H.6 | `LineType = 'Minimum'` behaviour | Pairs with a `ContractCommitment` — the shortfall against the commitment is what gets billed, per `TrueUpPolicy`. The mockup's "Annual minimum · $400,000.00 · full term" line carries the price with no quantity. | K.8 | api |
| H.7 | `CK_ContractLine_Quantity` | `Quantity = -1` is rejected by `CK_ContractLine_Quantity`; `0` is **accepted** (a zero-quantity line is legal today — decide whether it should be); `1` and `12.5000` accepted at `DECIMAL(18,4)` precision. Default is `1`. | — | server |
| H.8 | `CK_ContractLine_ContractedUnitPrice` | `-0.01` is rejected by `CK_ContractLine_ContractedUnitPrice`; `0` accepted (a $0 covered line is legal — a bundled entitlement); NULL accepted and **means something specific** (H.13). | H.13 | server |
| H.9 | `CK_ContractLine_DiscountPct` | `-0.01` and `1.01` are rejected by `CK_ContractLine_DiscountPct`; `0`, `0.10`, `1` accepted; NULL accepted. Stored as a **fraction**; the workspace renders `0.10` as "10%". The name was deliberately kept despite being a fraction, for family consistency with `OrderLine.DiscountPct` — a UI test must prove the ×100 conversion both ways. | G.8 | server + ui |
| H.10 | `CK_ContractLine_Dates` | `EndDate < StartDate` is rejected by `CK_ContractLine_Dates`. All of `StartDate NULL`, `EndDate NULL`, both NULL, and `EndDate = StartDate` are **accepted** — the constraint is `StartDate IS NULL OR EndDate IS NULL OR EndDate >= StartDate`, so a half-open window is legal. Both-NULL means "full term". | H.17 | server |
| H.11 | `CK_ContractLine_SubscriptionOnlyOnSubscriptionLine` | Setting `SubscriptionID` on a line whose `LineType = 'OneTime'` is rejected by `CK_ContractLine_SubscriptionOnlyOnSubscriptionLine`. `SubscriptionID` set on a `Subscription` line is accepted; NULL is accepted on any type. | H.2 | server |
| H.12 | `CK_ContractLine_SubscriptionTypeOnlyOnSubscriptionLine` | Setting `SubscriptionTypeID` on a `Milestone` line is rejected by `CK_ContractLine_SubscriptionTypeOnlyOnSubscriptionLine`. Set on a `Subscription` line: accepted. NULL on any type: accepted — **including on a `Subscription` line, which is the gap in X.5**. | H.15 | server |
| H.13 | `ContractedUnitPrice IS NULL` means **resolve normally** | The line is covered by the agreement but priced through orders' normal walk. The workspace renders it as the literal word "catalog", not as blank or `$0.00`. Assert both the engine behaviour (catalog price is used, coverage still applies) and the UI rendering. | G.6, H.8 | server + ui |
| H.14 | `DisplayOrder` | Default `0`. Lines render in `DisplayOrder` then a stable tiebreak; reordering in the UI persists and survives a reload. | P.3 | server + ui |
| H.15 | A `Subscription` line **without** a `SubscriptionTypeID` is schema-legal but un-materializable | It saves. Then the billing engine cannot create the subscription, because `orders.Subscription.SubscriptionTypeID` is `NOT NULL`. Test: the row saves; the engine fails with a **named** reason (not a raw FK/NULL error) and the event goes `Failed` with that reason. The rule belongs in the entity subclass. See X.5. | H.12, J.3, X.5 | server + api |
| H.16 | `SubscriptionID` is **not** unique across lines | Two `ContractLine` rows may point at the same `orders.Subscription` — there is no unique index. Given the whole point of `BillingMode='External'` is that exactly one thing spawns orders for a subscription, a double link is a duplicate-billing shape. Test: prove the duplicate saves today; then test the guard. See X.9. | H.2, X.9 | server |
| H.17 | Co-terming — the mid-term stub | Adding a product mid-term creates a `ContractAmendment` **plus** a `ContractLine` whose `StartDate` is the amendment's effective date and whose `EndDate` is the **term's** `EndDate`, so the stub period prorates on the next billing event. Concretely, the mockup: "Premium support · Mar 15 – Dec 31" on a Jan 1–Dec 31 term. **Nothing in the schema enforces `line.EndDate = term.EndDate`** — the engine must, and the test must assert the exact stub dates. Gated on `ContractType.AllowsCoterm`. | D.10, H.10, L.7 | server + api |

---

## I. Billing schedules

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| I.1 | `CK_ContractBillingSchedule_ScheduleType` | Accepts exactly `Cadence`, `Milestone`, `Custom`; `'Recurring'` is rejected by `CK_ContractBillingSchedule_ScheduleType`; NULL rejected by nullability. | — | server |
| I.2 | `CK_ContractBillingSchedule_Frequency` | Accepts the same six values as the term (`Monthly`…`Custom`) or NULL; `'Weekly'` is rejected by `CK_ContractBillingSchedule_Frequency`. | E.6 | server |
| I.3 | `CK_ContractBillingSchedule_CadenceNeedsFrequency` | `ScheduleType = 'Cadence'` with `Frequency IS NULL` is rejected by `CK_ContractBillingSchedule_CadenceNeedsFrequency` — a cadence with nothing to iterate. `ScheduleType = 'Milestone'` with `Frequency IS NULL` is **accepted**. `Cadence` + `Quarterly` accepted. Three cases. | I.1, I.2 | server |
| I.4 | One term, **many** schedules | A single term carries a `Cadence`/`Quarterly` schedule **and** a `Milestone` schedule simultaneously (the SOW-attached-to-an-MSA case). Both generate their own events against the same `ContractTermID`, and the workspace "Upcoming billing" panel interleaves them by date, labelling each with its schedule ("Quarterly cadence" vs "Migration milestone 2"). | J.1 | server + ui |
| I.5 | `IsActive` | Default `1`. Setting a schedule inactive stops the scheduled job generating further events from it **without** deleting the events already scheduled. Assert both halves. | J.7 | server |
| I.6 | `AnchorDate` | Nullable. When set, cadence occurrences are computed from it; when NULL, from the term's `StartDate` + `BillingAnchorMonth`/`BillingAnchorDay`. Assert the fallback explicitly — an off-by-one anchor is a wrong invoice date. | E.7, E.8 | unit + server |

---

## J. Billing events — the queue and the audit trail

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| J.1 | `CK_ContractBillingEvent_Status` | Accepts exactly `Scheduled`, `Generated`, `Skipped`, `Failed`. `'Generating'`, `'Pending'`, `''` are each rejected by `CK_ContractBillingEvent_Status`. Default is `Scheduled`. Note there is **no claim state** — see J.13. | — | server |
| J.2 | `CK_ContractBillingEvent_GeneratedHasOrder` | Setting `Status = 'Generated'` with `OrderID IS NULL` is rejected by `CK_ContractBillingEvent_GeneratedHasOrder`. `Generated` + a real `OrderID` accepted. `Scheduled`/`Failed`/`Skipped` with `OrderID IS NULL` accepted. This is the invariant that makes the status transition a real idempotency guard rather than a label. | J.5, O.10 | server |
| J.3 | `CK_ContractBillingEvent_FailedHasReason` | `Status = 'Failed'` with `FailureReason IS NULL` is rejected by `CK_ContractBillingEvent_FailedHasReason`. `Failed` + `'   '` (whitespace only) is **also rejected** — the constraint is `LEN(LTRIM(ISNULL(FailureReason,''))) > 0`. `Failed` + a real reason accepted. Three cases, and the whitespace case is the one an implementation gets wrong. | J.9 | server |
| J.4 | `CK_ContractBillingEvent_ComputedAmount` | `-0.01` is rejected by `CK_ContractBillingEvent_ComputedAmount`; `0` accepted; NULL accepted. **A negative amount is forbidden, so a credit/refund bill cannot be stamped here** — see X.10. | X.10 | server |
| J.5 | `UQ_ContractBillingEvent_Order` — one order per event, filtered | Two events naming the same `OrderID` fail on `UQ_ContractBillingEvent_Order`. **Many** events with `OrderID IS NULL` coexist happily (the index is filtered `WHERE OrderID IS NOT NULL`) — assert that explicitly, because an unfiltered unique index here would break every `Scheduled` row. | J.2 | server |
| J.6 | `IX_ContractBillingEvent_Due` — the driver's access path | The scheduled job's query `Status='Scheduled' AND ScheduledDate <= today` uses `IX_ContractBillingEvent_Due` (which `INCLUDE`s `ContractTermID`) and does not scan. Assert via the plan, not by timing. | J.7 | server |
| J.7 | `Contracts.GenerateBillingEvent(BillingEventID)` — all-or-none | One remote operation, one transaction: load term + lines + commitments + event → assemble the draft per `LineType` → build `HydratableHeader`/`HydratableLine[]` → **`Orders.PreviewOrder`** to price → **`Orders.CreateOrderInState`** to materialize **one consolidated order** → stamp `OrderID`/`ComputedAmount`/`GeneratedAt` → advance covered subscriptions' periods → write a `ContractEvent`. **A failure anywhere rolls back everything and partially bills nothing** — assert by injecting a failure at the materialize step and proving no order, no partial event stamp, and no advanced subscription period survive. **Not built; blocked on Y.1/Y.2.** | H.2–H.6, K.8, M.1 | api |
| J.8 | Idempotency — re-running never double-bills | Invoking `GenerateBillingEvent` twice on the same event produces exactly one order. The `Scheduled → Generated` transition plus `CK_ContractBillingEvent_GeneratedHasOrder` (J.2) plus `UQ_ContractBillingEvent_Order` (J.5) are the three mechanisms; test that the **second** call is refused and says why, rather than succeeding as a no-op. | J.2, J.5 | api |
| J.9 | `Failed` is terminal until a human clears it | A failed event is **never auto-retried** — the scheduled job skips `Failed` rows entirely on subsequent runs. The worklist surfaces them with the engine's recorded reason and a deliberate "Re-run selected" action. Assert: run the job twice over a `Failed` event and prove no order was produced either time. | J.3, J.15 | api + ui |
| J.10 | `ComputedAmount` is a **stamp**, never a computation | The value equals exactly what `Orders.PreviewOrder` returned for the assembled draft. Contracts performs no arithmetic of its own. Test: feed a draft whose correct total is a non-obvious number (multi-line, discounted, prorated stub) and assert the stamp equals orders' figure to the cent — and that no code path in this app adds, multiplies or rounds it. | J.7 | api |
| J.11 | Event / schedule / term consistency is **not** constrained | An event may carry `ContractBillingScheduleID` pointing at a schedule on **term A** while its own `ContractTermID` is **term B** — both FKs resolve and the row saves. See X.11. | X.11 | server |
| J.12 | `GeneratedAt` is not enforced on `Generated` | `Status = 'Generated'` with a real `OrderID` and `GeneratedAt IS NULL` **saves** — there is no CHECK, though the plan's step 5 stamps it. See X.12. | J.2, X.12 | server |
| J.13 | There is **no** concurrency claim state | Two overlapping scheduled-job runs can both `SELECT` the same `Scheduled` row before either writes. `CK_ContractBillingEvent_GeneratedHasOrder` is a good invariant but does not prevent this; the plan's own §10.6 names the gap. The fix is a `Generating` status (which needs a migration, since `CK_ContractBillingEvent_Status` forbids the value) or a conditional `UPDATE … WHERE Status='Scheduled'` claim. Test: drive two concurrent generations of one event and assert exactly one order results. | J.1, J.8 | server + api |
| J.14 | `Skipped` | An event the engine deliberately did not bill (nothing to bill this period, or an inactive schedule) records `Skipped`. No reason is required by the schema — decide whether one should be, and whether `Skipped` is distinguishable from `Failed` in the worklist. | J.9 | server |
| J.15 | The billing worklist screen | Four stat tiles (due today, due in 7 days with an estimated total, failed with the age of the oldest, generated this month with the billed total); a **Failed** table carrying the engine's recorded reason per row and deep-linking to the offending **orders** record (three of the four mockup failures are fixed in orders, not here); a **Scheduled — next 7 days** table listing the lines each event will assemble and its estimated amount. "Estimated" means "what `Orders.PreviewOrder` returns today" and must be labelled as such. | J.9, J.10 | ui |

---

## K. Commitments, minimums and true-up policies

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| K.1 | `CK_ContractCommitment_CommitmentType` | Accepts exactly `Minimum`, `Prepaid`, `Draw`; `'Credit'` is rejected by `CK_ContractCommitment_CommitmentType`; NULL rejected by nullability. | — | server |
| K.2 | `CK_ContractCommitment_TrueUpPolicy` | Accepts exactly `BillShortfall`, `Forfeit`, `Rollover`; `'Ignore'` is rejected by `CK_ContractCommitment_TrueUpPolicy`. `NOT NULL DEFAULT 'BillShortfall'` — a row inserted without naming it reads `BillShortfall`. | — | server |
| K.3 | `CK_ContractCommitment_Status` | Accepts exactly `Open`, `Closed`, `TruedUp`, `Forfeited`; `'Consumed'` is rejected by `CK_ContractCommitment_Status`. Default `Open`. | — | server |
| K.4 | `CK_ContractCommitment_CommittedAmount` | `-1` is rejected by `CK_ContractCommitment_CommittedAmount`; `0` accepted; the column is `NOT NULL` so NULL is rejected by nullability. | — | server |
| K.5 | `CK_ContractCommitment_ConsumedAmount` | `-1` is rejected by `CK_ContractCommitment_ConsumedAmount`; `0` accepted (the default). **`ConsumedAmount > CommittedAmount` is deliberately ACCEPTED** — over-consumption against a minimum is a real state to record and report, not an error to reject at write time. That acceptance needs its own regression test so nobody "fixes" it into a constraint. | K.7 | server |
| K.6 | `CK_ContractCommitment_Period` | `PeriodEnd < PeriodStart` is rejected by `CK_ContractCommitment_Period`. Either NULL, both NULL, and `PeriodEnd = PeriodStart` are all accepted. | — | server |
| K.7 | Consumption tracking and its display | `ConsumedAmount` accumulates as bills are generated against the term. The workspace renders "$284,000 consumed / $116,000 remaining · 71% consumed" — assert the exact percentage arithmetic (284000/400000 = 71%) and that **over**-consumption renders sensibly (>100%, negative remaining), since K.5 permits it. | K.5 | unit + ui |
| K.8 | `TrueUpPolicy = 'BillShortfall'` | At period end with `CommittedAmount 400000` and `ConsumedAmount 284000`, the next billing event's assembled draft carries a shortfall line of exactly **116,000** and the commitment moves to `TruedUp`. | H.6, J.7 | api |
| K.9 | `TrueUpPolicy = 'Forfeit'` | Same inputs: **no** shortfall line is added, and the commitment moves to `Forfeited`. Assert the generated order does **not** contain the 116,000. | K.8 | api |
| K.10 | `TrueUpPolicy = 'Rollover'` | Same inputs: no shortfall billed; the unconsumed 116,000 carries forward — either into the next period's `CommittedAmount` or as a new commitment row. **Which of the two is not specified anywhere.** Pin the choice with a test and record it. | K.8, Y.7 | api |
| K.11 | `TrueUpPolicy` applies to every `CommitmentType`, including nonsensical pairs | `CommitmentType = 'Prepaid'` with `TrueUpPolicy = 'BillShortfall'` saves — there is no cross-check, and `TrueUpPolicy` is `NOT NULL` so every `Prepaid`/`Draw` row carries one whether it means anything or not. See X.13. | K.1, K.2, X.13 | server |
| K.12 | `Status` and `TrueUpPolicy` may contradict | A commitment with `TrueUpPolicy = 'Forfeit'` may be set `Status = 'TruedUp'`, and vice versa — nothing constrains the pair. See X.13. | K.3, X.13 | server |

---

## L. Amendments and approvals

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| L.1 | `CK_ContractAmendment_AmendmentType` | Accepts exactly `AddProduct`, `ChangeQuantity`, `ChangePrice`, `Coterm`, `PartialTerminate`, `Other`; `'Renewal'` is rejected by `CK_ContractAmendment_AmendmentType` — **which is the point**: a renewal is not an amendment. | F.10 | server |
| L.2 | `CK_ContractAmendment_Status` | Accepts exactly `Draft`, `PendingApproval`, `Approved`, `Rejected`, `Applied`, `Cancelled`; `'Pending'` is rejected by `CK_ContractAmendment_Status`. Default `Draft`. Six accepts. | — | server |
| L.3 | `CK_ContractAmendment_AmendmentNumber` | `0` and `-1` are rejected by `CK_ContractAmendment_AmendmentNumber`; `1` accepted. | — | server |
| L.4 | `UQ_ContractAmendment_Term_Number` | A second amendment with the same `(ContractTermID, AmendmentNumber)` fails on `UQ_ContractAmendment_Term_Number`; the same number on a different term succeeds. Numbering is **per term**, not per contract — assert that, since "Amendment 3" of a contract is ambiguous across terms. | L.3 | server |
| L.5 | `ApprovalTaskID` → `bizapps-tasks` | Resolves to a real `__mj_BizAppsTasks.Task`; a random GUID is rejected by `FK_ContractAmendment_ApprovalTask`; NULL accepted. **This is a hard FK, not a soft reference** — the master plan §6 still calls it soft (X.3). The task's `TaskType` `OnComplete`/`OnReject` Action hooks call back into contracts to move the amendment to `Approved`/`Rejected`. | O.11, X.3 | server + api |
| L.6 | `Approved` does not require an approval task | `Status = 'Approved'` with `ApprovalTaskID IS NULL` **saves** — there is no CHECK. So an amendment can be marked approved with no approval record. See X.14. | L.2, L.5, X.14 | server |
| L.7 | Each `AmendmentType` does its own thing | `AddProduct` → a new `ContractLine` with a co-term window (H.17). `ChangeQuantity` → the target line's `Quantity` changes and the change takes effect from `EffectiveDate`, not retroactively. `ChangePrice` → `ContractedUnitPrice` changes from `EffectiveDate`. `Coterm` → align an existing line's `EndDate` to the term end. `PartialTerminate` → a line's `EndDate` is pulled in before the term end. `Other` → recorded, no automatic effect. **Six behaviours, six tests. None built.** | H.10, H.17 | api |
| L.8 | Amendments apply only to a **live** term | Applying an amendment to a `Completed` or `Terminated` term is refused. Nothing in the schema says so — the guard must live in the entity/action, and the test must prove the refusal names the term status. | E.1, F.10 | server |

---

## M. The immutable event log

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| M.1 | Lifecycle events are written | Every status transition and every generated bill appends a `ContractEvent` with `ContractID`, optional `ContractTermID`, `EventType`, `EventDate` (default `SYSDATETIMEOFFSET()`), JSON `Payload`, and `PerformedByUserID`. Assert per transition: after `RecordExecution`, exactly one new event exists whose payload names the signature request. | B.3–B.8, J.7 | server + api |
| M.2 | `EventType` is **unconstrained free text** | `ContractEvent` is the only table in the schema with a vocabulary column and **no CHECK** — `EventType = 'asdf'` saves. Every other value list is CHECK-enforced. Test both: the free-text write succeeds today, and the app's own emitted set is a closed list you can enumerate. See X.15. | X.15 | server |
| M.3 | "Never edited, never deleted" is **not enforced** | CodeGen generates full CRUD for this entity, so `spUpdateContractEvent` and `spDeleteContractEvent` exist and work. A test that updates and then deletes an event row **succeeds today** — proving the immutability claim is documentation, not a mechanism. The guard belongs in the entity subclass (refuse `Save` on an existing record, refuse `Delete`) and/or entity permissions. See X.15. | Q.5, X.15 | server + api |
| M.4 | `IX_ContractEvent_Contract_Date` — the timeline read path | The workspace History tab's query (`WHERE ContractID = @id ORDER BY EventDate DESC`) uses `IX_ContractEvent_Contract_Date` and does not sort in memory. | P.3 | server |
| M.5 | `Payload` is JSON | Round-trips a nested JSON document unaltered (no double-escaping); the History tab renders it readably and does not break on a payload it does not recognise. | M.1 | server + ui |
| M.6 | `PerformedByUserID` | Resolves to `__mj.User`; a random GUID is rejected by `FK_ContractEvent_PerformedByUser`. NULL is accepted — which is how a **system**-performed event (the scheduled job) is recorded. Assert both. | O.3 | server |
| M.7 | `ContractTermID` is optional | A contract-level event (executed, superseded) leaves it NULL; a term-level event (activated, renewed, billed) sets it. Both save. **Nothing constrains the term to belong to the event's contract** — the same shape as X.11. | O.- | server |
| M.8 | Customer-visible events **also** write a `common.Activity` | Executed / renewed / terminated additionally call `Common.LogActivity` so the agreement appears on the account timeline. The `ContractEvent` is the system record and the Activity is the human one; **neither replaces the other**, so the test asserts *both* rows exist after one transition. **Not built.** | M.1 | api |

---

## N. Documents and signatures — polymorphic pairs, zero columns

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| N.1 | A **contract** carries many documents | Files attach via `__mj.FileEntityRecordLink` with `EntityID` = the `MJ_BizApps_Contracts: Contracts` entity ID and `RecordID` = the contract's ID. Concretely: the executed MSA PDF **and** Exhibit A both link to one contract and both list. A one-document cap is a failure. | Q.3 | server + ui |
| N.2 | A **term** carries its own paper | Same pattern with the `Contract Terms` entity — "Term 3 renewal order form.pdf" attaches to the term, not to the contract. This is what makes the re-papered-each-period pattern work. | E.11, N.1 | server + ui |
| N.3 | An **amendment** carries its countersigned document | Same pattern with the `Contract Amendments` entity. | N.1 | server + ui |
| N.4 | `<mj-record-files>` — a component MJ does not have | Record-scoped, polymorphic file list + attach. `@memberjunction/ng-file-storage` ships `mj-file-browser` / `mj-files-grid` / `mj-files-file-upload` but they are **category**-scoped; nothing in the MJ Angular tree queries `FileEntityRecordLink` at runtime. Built here, donation-shaped (record-scoped, app-agnostic inputs, no contracts types in its public surface), donated to MJ base after. **Partially built** — `packages/Angular/src/lib/panels/record-files.panel.ts` lists linked files; the **upload path is not wired** (queue item 5). Test: list, attach, delete-link, empty state, and error state. | N.1 | ui |
| N.5 | Signature envelopes link with **zero columns** | `__mj.SignatureRequest` already carries `EntityID` + `RecordID`, plus `Status`, `SentAt`, `CompletedAt`, `VoidReason`, `ExternalEnvelopeID`, and `SignatureRequestRecipients`/`Documents`/`Logs` around it. A contract or a term links to its envelope with no migration on our side. Provider-agnostic across DocuSign, Dropbox Sign and PandaDoc, all seeded in MJ core. | B.3 | server |
| N.6 | `<mj-record-signature-status>` — the second missing component | Renders envelope status, provider, envelope ID, sent/completed dates, and per-recipient signed state (the workspace mockup's Signature card). Read-only first; **sending needs a provider account**, so the send path may be untestable locally. **Not built.** | N.5 | ui |
| N.7 | `RequiresSignature` drives the lifecycle end to end | `ContractType.RequiresSignature = 1` → `SendForSignature` raises the envelope → `Status = 'PendingSignature'` **driven by the envelope, never set by hand** → `SignatureRequest.CompletedAt` → `ExecutedDate` stamped → executed PDF attached via `FileEntityRecordLink` → `VoidReason` covers the rejection path. Test the whole chain, and separately test that a direct entity write to `PendingSignature` is refused. | B.3, B.4, D.7 | api |
| N.8 | **No `DocumentFileID` column, on any table** | `Contract`, `ContractTerm` and `ContractAmendment` each have no column named `DocumentFileID`. A test asserting the absence guards a decision that was already made and reversed once — the master plan §3.2/§3.8 text still mentions the column (X.4). | X.4 | server |

---

## O. Cross-app foreign keys — all thirteen, each a real FK

Every one: a valid target ID saves; a random GUID is **rejected by the named FK**; NULL is accepted
where the column is nullable and rejected by nullability where it is not. All thirteen point **up**
the dependency graph (`common → tasks → accounting → orders → contracts → sales`), and §4.A of the
baseline fails loudly if a dependency app is not installed — which *is* the dependency check.

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| O.1 | `FK_Contract_Company` | `Contract.CompanyID` → `__mj.Company(ID)`. `NOT NULL`. The **selling** company. | C.5 | server |
| O.2 | `FK_Contract_OwnerUser` | `Contract.OwnerUserID` → `__mj.[User](ID)`. Nullable. | C.6 | server |
| O.3 | `FK_ContractEvent_PerformedByUser` | `ContractEvent.PerformedByUserID` → `__mj.[User](ID)`. Nullable — NULL means system-performed. | M.6 | server |
| O.4 | `FK_Contract_CustomerOrganization` | `Contract.CustomerOrganizationID` → `__mj_BizAppsCommon.Organization(ID)`. Nullable (XOR partner). | C.1, C.2 | server |
| O.5 | `FK_Contract_CustomerPerson` | `Contract.CustomerPersonID` → `__mj_BizAppsCommon.Person(ID)`. Nullable (XOR partner). | C.1, C.3 | server |
| O.6 | `FK_Contract_PrimaryContactPerson` | `Contract.PrimaryContactPersonID` → `__mj_BizAppsCommon.Person(ID)`. Nullable, independent of the customer. | C.4 | server |
| O.7 | `FK_ContractLine_Product` | `ContractLine.ProductID` → `__mj_BizAppsOrders.Product(ID)`. `NOT NULL` — every covered line names a catalog product. | G.1, H.1 | server |
| O.8 | `FK_ContractLine_SubscriptionType` | `ContractLine.SubscriptionTypeID` → `__mj_BizAppsOrders.SubscriptionType(ID)`. Nullable. The **decision**: which kind of subscription this line becomes, negotiated before anything exists. | H.12, H.15 | server |
| O.9 | `FK_ContractLine_Subscription` | `ContractLine.SubscriptionID` → `__mj_BizAppsOrders.Subscription(ID)`. Nullable. The **result**: the subscription actually materialized. Not redundant with O.8 — one is input, one is output. | H.11, H.16 | server |
| O.10 | `FK_ContractBillingEvent_Order` | `ContractBillingEvent.OrderID` → `__mj_BizAppsOrders.OrderHeader(ID)`. Nullable, uniquely indexed when set (J.5). A legal **downward** reference: contracts sits above orders. | J.2, J.5 | server |
| O.11 | `FK_ContractAmendment_ApprovalTask` | `ContractAmendment.ApprovalTaskID` → `__mj_BizAppsTasks.Task(ID)`. Nullable. A **hard FK** — the plan's §6 "soft ref" language is stale (X.3). | L.5 | server |
| O.12 | `FK_ContractTerm_PaymentTermsType` | `ContractTerm.PaymentTermsTypeID` → `__mj_BizAppsOrders.PaymentTermsType(ID)`. Nullable. Orders owns payment terms; accounting delegates to it and so do we. | E.12 | server |
| O.13 | `FK_ContractTerm_Currency` | `ContractTerm.CurrencyID` → `__mj_BizAppsAccounting.Currency(ID)`. Nullable. **Forward-compatibility only** — nothing converts. | E.13 | server |
| O.14 | Installing without a dependency **fails loudly** | Applying the baseline against a DB missing `bizapps-common` / `tasks` / `accounting` / `orders` fails at §4.A with a named FK error, leaving no half-installed schema. That failure is the dependency check and must be tested by omission, not assumed. | Q.1 | server |
| O.15 | **No FK ever points into `bizapps-sales`** | `sys.foreign_keys` for this schema contains no reference to a sales object, now or ever (L-15). Assert the absence. | C.7 | server |

**Internal FKs (13), all `NO ACTION` — no cascades anywhere:** `FK_Contract_ContractType`,
`FK_Contract_ParentContract`, `FK_Contract_SupersededByContract`, `FK_ContractTerm_Contract`,
`FK_ContractTerm_RenewalOfTerm`, `FK_ContractLine_ContractTerm`,
`FK_ContractBillingSchedule_ContractTerm`, `FK_ContractBillingEvent_ContractBillingSchedule`,
`FK_ContractBillingEvent_ContractTerm`, `FK_ContractCommitment_ContractTerm`,
`FK_ContractAmendment_ContractTerm`, `FK_ContractEvent_Contract`, `FK_ContractEvent_ContractTerm`.
Covered as a behaviour by **Q.4**.

---

## P. UI surfaces (from the round-2 mockups)

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| P.1 | Contracts list — the roster | Four health tiles: **Active contracted value** (`SUM(ContractTerm.CommittedAmount)` over `Status='Active'` terms — assert the exact sum against seeded data), **Renewing this quarter** (terms whose `EndDate` falls in the quarter), **Billing due next 7 days** (count of `Scheduled` events), **Failed billing events**. Then a filterable grid: contract number, customer, type, current term + dates, billing frequency, committed, status, source. Filters on status / type / company / renewal window, saved views, export. | E.9, J.1 | ui |
| P.2 | Contract creation — one card, one form | Deliberately **not** a draft-tab workspace and **not** a wizard: manual entry runs a few times a year. Two modes — **Fast entry** (one scroll) and **Detailed** (the same sections as the viewer, tab for tab) — switchable at any time, losslessly. Sections: Agreement · Term · Coverage · Billing · Commitments · Documents. Contract-native selection throughout: customer (org XOR person), products, subscription types, coverage windows, negotiated prices, clauses. **No order is created here** and no total is shown. Saves as `Draft`; "Create & send for signature" runs `Contracts.SendForSignature`. | B.2, B.3, C.1, D.13, G.2, H.1 | ui |
| P.3 | Contract workspace — eight section tabs | Overview · Terms · Coverage · Billing · Commitments · Amendments · Documents · History, with a provenance strip (Deal → Contract → orders → accounting → next bill) and an identity band (number, status, auto-renew, currency, customer, type, selling company, owner, effective date). Persistent record tabs so several contracts open at once with dirty state marked — renewals are compared against their predecessors constantly. Each tab's count badge must match its row count. | B.15, E.10, F.8, H.13, H.14, I.4, K.7, M.4, N.1 | ui |
| P.4 | Billing worklist | See **J.15**. | J.15 | ui |
| P.5 | Nav rail — five destinations | Contracts (with count) · New contract · Billing worklist (with count) · Renewals · Amendments (with count) · Setup → Contract types. Counts are live, not hardcoded. Related links out to Orders and Accounting. | P.1 | ui |
| P.6 | Forms are **overrides of the MJ base form**, using the 4-layer architecture | Custom forms are subclasses/overrides of `BaseFormComponent`, presented through `MJFormPresenterService.Open()` / `<mj-form-dialog>` / `<mj-form-slide-in>`, with `EntityFormConfig` for per-instance toolbar/sections and `SectionName="…"` for standalone quick-edit. **One definition of what a contract looks like**, reused in the workspace, in a dialog from the roster, and in a slide-in. Generated forms exist for all ten entities; the work is overriding the ones that need a real editing experience, never building parallel screens beside them. **Built so far:** a custom `contract.form.component.ts` and a 1,081-line `contracts-section.component.ts`; term and line custom forms are queue item 4. | Q.5 | ui |
| P.7 | MJ design tokens, no hardcoded colour | Every control — including dropdowns — uses `@memberjunction/ng-shared`'s `_tokens.scss` (255 tokens, light and dark). The repo's `npm run check:ui` gate passes. Both themes render legibly. | — | ui |
| P.8 | Data access is exactly four methods | The UI reaches data through `RunView`, `RunQuery`, `BaseEntity` and RemotableOperation — **nothing else**. No bespoke `fetch`, no hand-rolled GraphQL document, no socket wrapper. And **never a new provider**: always `ProviderToUse`, because a second provider splits the metadata and the class factory and the failure is *silent*. Test: grep the Angular package for `fetch(`/`new GraphQLDataProvider`/`gql\`` and assert zero hits. | — | unit + ui |

---

## Q. Install, packaging and generated artifacts

| ID | Feature | What "working" means, concretely | Depends on | Test tier |
|---|---|---|---|---|
| Q.1 | Install order is enforced by the database | `bizapps-common`, `bizapps-tasks`, `bizapps-accounting` and `bizapps-orders` must be installed first; applying the baseline without them fails at §4.A. `mj-app.json` declares all four with version ranges. | O.14 | server |
| Q.2 | `SchemaInfo` registration | Exactly one `__mj.SchemaInfo` row for `__mj_BizAppsContracts` with ID `1A531C07-5F1A-448D-A2BF-B986801F4F1D`, `EntityNamePrefix = 'MJ_BizApps_Contracts: '`, and no suffix. A second install must not collide. | Q.3 | server |
| Q.3 | Entity naming | All ten entities carry the `MJ_BizApps_Contracts: ` prefix and match `mj.config.cjs` `newEntityDefaults`. Resolving `MJ_BizApps_Contracts: Contracts` from metadata returns the entity; the unprefixed name throws. | Q.2 | server |
| Q.4 | **No cascades anywhere** | Deleting a `ContractTerm` that has lines fails loudly against `FK_ContractLine_ContractTerm` rather than quietly taking them. Test each of the 13 internal FKs' parent-delete path — a contract is financial provenance. | O.- | server |
| Q.5 | CodeGen produces a **working** database, not bare tables | After migrate + codegen, each of the ten entities has a base view, `spCreate`/`spUpdate`/`spDelete`, permissions, and `__mj_CreatedAt`/`__mj_UpdatedAt` (CodeGen owns those — the migration must not add them). The generated tail lands below the banner in the baseline via `scripts/append-codegen.sh`. Extended properties surface as entity/field descriptions in Explorer. | Q.3 | server |
| Q.6 | PostgreSQL parity | T-SQL is the source of truth; the PG counterpart is produced via `@memberjunction/sql-converter` and CI-validated. **Not started (C6).** | — | server |
| Q.7 | `mj-app.json` is publish-ready | **It is not today:** `"license": "<Set-this>"`, `"categories": ["Template"]`, `"tags": ["template","sample","starter"]` are unedited template leftovers. A publish gate must fail on the literal `<Set-this>`. | — | unit |
| Q.8 | Seed metadata ships | `metadata/` currently holds only `applications/` and `schema-info/`. The six `ContractType` rows (D.14) must become real `metadata/contract-types/` records with hardcoded UUIDs, verified by a drop-schema → setup → sync cycle. | D.14 | server |
| Q.9 | Extended properties are the adopter-facing documentation | Every `sp_addextendedproperty` in §5 of the baseline lands on the right table/column and is written for the reader about to get something wrong. Assert presence for the documented set (ContractType ×5, Contract ×6, ContractTerm ×5, ContractLine ×5, BillingSchedule ×1, BillingEvent ×3, Commitment ×2, Amendment ×2, Event ×1). | Q.5 | server |

---

## Contradictions found

Ordered by how much they cost if left. Each is a rule someone stated that the schema does not
enforce, or a schema behaviour the plan does not describe.

> **✅ = closed on 2026-08-05**, with what closed it in the final column. Fourteen of the eighteen are
> closed (✅), and one is partly addressed (◐ X.3 — the schema is right, the plan prose needs a ruling). The text of each contradiction is left as originally written rather than rewritten in the
> past tense — the finding is the record of what was wrong, and editing it to read as though it never
> happened would lose the reason the fix exists. **X.10 is deliberately still open:** whether a
> billing event may carry a credit is a scope decision, raised on PR #2 rather than guessed.

| # | Contradiction | Where | Why it matters | Suggested resolution |
|---|---|---|---|---|
| X.1 ✅ | **The escalation cap is not enforced anywhere.** `EscalationPercent = 0.08` with `MaxEscalationPercent = 0.05` saves cleanly — there is no `CK_ContractTerm_EscalationWithinCap`, and no entity subclass exists to guard it. Worse, **`EscalationPercent` has no `>= 0` CHECK at all** while `ContractType.DefaultEscalationPercent` does. | Migration lines 179–181 vs 210; master §10.3 ("an uncapped 'then-current list' increase is the most disputed clause in a B2B renewal"), §12.2 ("capped by `MaxEscalationPercent`") | The plan added `MaxEscalationPercent` *specifically* to record "increases shall not exceed 5%". A cap you can save past is not a cap. A negative escalation silently reduces a renewal price. | Add `CK_ContractTerm_EscalationPercent (EscalationPercent IS NULL OR EscalationPercent >= 0)` and `CK_ContractTerm_EscalationWithinCap (MaxEscalationPercent IS NULL OR EscalationPercent IS NULL OR EscalationPercent <= MaxEscalationPercent)`; **and** clamp in the resolver, since a cap can also be breached by escalation arithmetic rather than by a stored value. **CLOSED 2026-08-05 — the cap is enforced in `ContractTermEntityServer.Validate()` (a two-column CHECK breaks CodeGen validation naming, so it cannot live in SQL), and `RenewTerm` CLAMPS to the ceiling rather than proposing a rejected number. 3 tier-2 assertions.** |
| X.2 ✅ | **`ContractType.DefaultMaxEscalationPercent` and `DefaultRenewalNoticeDays` have no CHECKs**, while their `ContractTerm` counterparts (`CK_ContractTerm_MaxEscalationPercent`, `CK_ContractTerm_RenewalNoticeDays`) and their `ContractType` siblings (`DefaultEscalationPercent`, `DefaultCancellationWindowDays`) all do. | Migration lines 45, 49 vs 64–65, 210–211 | A negative default flows into every term created from that type, where it *would* have been rejected had it been typed directly. The validation is inconsistent by accident, not by design. | Add `CK_ContractType_MaxEscalationPercent` and `CK_ContractType_RenewalNoticeDays`, both `>= 0`. **CLOSED 2026-08-05 — `CK_ContractType_MaxEscalationPercent` and `CK_ContractType_RenewalNoticeDays` added. This became load-bearing when `ContractsEngine` started applying these defaults to every new term.** |
| X.3 ◐ | **`ContractAmendment.ApprovalTaskID` is documented as a soft reference and implemented as a hard FK.** §6 still says "soft ref (per Caliber's DG-6: … cross-OpenApp-schema hard FKs are avoided because the other app's migrations may not have run)" — a rationale that directly contradicts §10.1 #4's mandate and the install-order dependency. §3.8 repeats it. | master §3.8, §6 vs migration line 575 (`FK_ContractAmendment_ApprovalTask`) | §10.1 #4 explicitly withdrew the soft-ref language for `PaymentTermsTypeID` but **not** for `ApprovalTaskID`. A reader of §6 will design around a constraint that does not exist, or "fix" the FK away. | Withdraw the §6 soft-ref paragraph the same way §10.1 #4 withdrew §3.3's. **PARTLY ADDRESSED 2026-08-05 — an as-built marker now sits at §6 noting the column is a HARD FK and that §10.1 #4 overrides the DG-6 rationale. The prose itself is left for Amith: reconciling two stated rationales is a ruling, not a typo.** |
| X.4 ✅ | **§3 of the master plan describes a schema that no longer exists**, in four places: "Nine tables" (there are **ten** — `ContractSequence`); `Contract.DocumentFileID` and `ContractAmendment.DocumentFileID` (both removed per §10.2); `ContractTerm.Status` listed as four values (the schema has five — `PendingSignature` was added); `PaymentTermsTypeID` as a soft ref. | master §3.2, §3.3, §3.8, §8 vs the migration and `docs/ERD.md` | §10 says it supersedes §3, but §3 is what a new reader reaches first and it names columns that will fail to compile. | Mark the superseded lines inline in §3 pointing at the §10 ruling that changed them, rather than relying on a reader reaching §10 first. **CLOSED 2026-08-05 — §3 now carries an as-built divergence marker (ten tables not nine, `DocumentFileID` removed, five term statuses not four, plus the two added `Contract` columns), and the C1 row is annotated. Original text left intact — it records what was intended, and rewriting it in the past tense would lose why each change was made.** |
| X.5 ✅ | **A `Subscription` line with no `SubscriptionTypeID` is schema-legal but un-materializable.** `CK_ContractLine_SubscriptionTypeOnlyOnSubscriptionLine` prevents the type being set on a *non*-subscription line, but nothing **requires** it on a subscription line. | Migration line 271 vs master §10.3 ("`orders.Subscription.SubscriptionTypeID` is `NOT NULL`, so the billing engine cannot create one without this") | The column was added precisely because the engine cannot materialize without it. The failure lands at billing time — a `Failed` event on a live contract — instead of at write time on a draft. | Add `CK_ContractLine_SubscriptionNeedsType (LineType <> 'Subscription' OR SubscriptionTypeID IS NOT NULL)`, mirroring `CK_ContractBillingSchedule_CadenceNeedsFrequency`, which solves the identical shape one table over. **CLOSED 2026-08-05 — `CK_ContractLine_SubscriptionNeedsType`. The UI also demands the type BEFORE the save rather than letting the write fail.** |
| X.6 ✅ | **`Status = 'Superseded'` does not require `SupersededByContractID`.** The column was added *because* `Superseded` had no way to name its successor — and it is still optional. | Migration lines 105–110, 135 | Asymmetric with `CK_ContractBillingEvent_GeneratedHasOrder`, which does exactly this for the analogous case one table over. A superseded contract with no successor is the state the column was added to eliminate. | Add `CK_Contract_SupersededHasSuccessor (Status <> 'Superseded' OR SupersededByContractID IS NOT NULL)`. **CLOSED 2026-08-05 — `CK_Contract_SupersededHasSuccessor`.** |
| X.7 ✅ | **`CK_Contract_PricedWhenActive` only covers `Active`.** A contract can reach `Expired`, `Terminated` or `Superseded` with `PricedAt IS NULL`, including by moving out of `Active` and then nulling it. | Migration line 154 vs master §12 | Renewal pricing reads `Contract.PricedAt` as the as-of for the one catalog read (§12.2). A terminated contract that gets revived, or a superseded one whose successor inherits lines, loses its as-of date silently. | Extend to `Status IN ('Draft','PendingSignature') OR PricedAt IS NOT NULL`. **CLOSED 2026-08-05 — `CK_Contract_PricedWhenActive` widened from `Status <> 'Active'` to `Status = 'Draft'`, so every state past Draft needs the pricing moment. Draft stays exempt on purpose. Proven with a RAW-SQL bypass, because the entity layer defaults `PricedAt` and so cannot reach the bad state at all.** |
| X.8 ✅ | **`RenewalOfTermID` may point at a term on a different contract.** Only self-reference is blocked. | Migration lines 212, 455–457 | The renewal chain is the app's continuity model and the workspace's Term-history panel walks it. A cross-contract link makes that walk produce another customer's terms. | Enforce same-contract in the entity subclass (a CHECK cannot see the other row); assert it in tests. **CLOSED 2026-08-05 — enforced in `ContractTermEntityServer.ValidateAsync()` (a CHECK cannot read the row it points at). Note: `DefaultSkipAsyncValidation` is TRUE, so the override to `false` is what makes it run at all.** |
| X.9 ✅ | **`ContractLine.SubscriptionID` is not unique.** Two lines may point at the same `orders.Subscription`. | Migration §3.5, no unique index | The `BillingMode='External'` design exists to make "exactly one thing spawns orders for a subscription" true **by construction** (master §4.1); two contract lines owning one subscription re-opens the duplicate-billing hole from the other side. | Add a filtered unique index `WHERE SubscriptionID IS NOT NULL`, exactly like `UQ_ContractBillingEvent_Order`. **CLOSED 2026-08-05 — filtered `UQ_ContractLine_Subscription`.** |
| X.10 | **`CK_ContractBillingEvent_ComputedAmount >= 0` forbids a credit.** `AmendmentType = 'PartialTerminate'` and `TrueUpPolicy = 'Rollover'` both describe situations that can net negative, and `ComputedAmount` is a **stamp** of whatever `Orders.PreviewOrder` returned — so if orders returns a negative total, the stamp cannot be written and the event cannot complete. | Migration line 326 vs lines 387, 358 | A constraint on a stamped value asserts something about *orders'* output that this app does not control. | Decide explicitly: either credits are out of scope for a billing event (document it), or drop the `>= 0` and let the stamp be faithful. |
| X.11 ✅ | **An event's schedule and its term need not agree.** `ContractBillingScheduleID` may reference a schedule belonging to a different `ContractTermID` than the event's own. `ContractEvent.ContractTermID` has the same shape against `ContractID` (M.7). | Migration lines 307–308, 470–478 | `ContractBillingEvent` is "the record that answers why the customer got this bill" — a mismatched pair makes that answer wrong while every FK resolves. | Enforce in the entity subclass, or denormalize the check via a composite FK on `(ContractTermID, ID)`. **CLOSED 2026-08-05 — enforced in `ContractBillingEventEntityServer.ValidateAsync()`; a CHECK cannot read the schedule's row. A composite FK would be the better long-term shape and is worth proposing rather than making unilaterally.** |
| X.12 ✅ | **`Status = 'Generated'` does not require `GeneratedAt`.** The engine's step 5 stamps `OrderID`, `ComputedAmount` **and** `GeneratedAt`; only `OrderID` is enforced. | Migration line 322 vs master §5.1 step 5 | The audit trail's "when did this bill get produced" is optional in the one status where it must exist. | Extend `CK_ContractBillingEvent_GeneratedHasOrder`, or add a sibling `CK_ContractBillingEvent_GeneratedHasTimestamp`. **CLOSED 2026-08-05 — `CK_ContractBillingEvent_GeneratedHasTimestamp`.** |
| X.13 | **`TrueUpPolicy` is `NOT NULL` on every commitment type, with no consistency rules.** `Prepaid` + `BillShortfall` saves; `TrueUpPolicy='Forfeit'` + `Status='TruedUp'` saves. | Migration lines 354, 357–359 | `TrueUpPolicy` describes what happens to an unconsumed **minimum**; forcing a value onto `Prepaid`/`Draw` rows means the engine must ignore a non-null column, which is exactly the kind of "field that looks authoritative and is not" the plan rejects elsewhere (L-15's reasoning). | Either make it nullable with `CK` requiring it on `Minimum` only, or document that it is ignored for the other two types. |
| X.14 ✅ | **`ContractAmendment.Status = 'Approved'` does not require `ApprovalTaskID`.** | Migration lines 385, 388 | §6 says non-standard terms, out-of-authority discounts and early-termination waivers **route through** an approval task. An amendment marked approved with no task is an approval with no record — the exact thing the task integration exists to prevent. | Add `CK_ContractAmendment_ApprovedHasTask (Status NOT IN ('Approved','Rejected') OR ApprovalTaskID IS NOT NULL)`. **CLOSED 2026-08-05 — `CK_ContractAmendment_ApprovedHasTask`, covering Rejected as well as Approved.** |
| X.15 ✅ | **The "immutable" event log is neither constrained nor immutable.** `ContractEvent.EventType` is the schema's only unconstrained vocabulary column (every other value list has a CHECK), and CodeGen generates working `spUpdate`/`spDelete` so rows can be edited and deleted. | Migration §3.10 vs its own comment ("Never edited, never deleted") and §7 of `docs/ERD.md` | An audit trail whose immutability is a comment is not an audit trail. And free-text `EventType` means the History tab cannot render a closed set, and no query can trust a type filter. | Add a `CK_ContractEvent_EventType` value list (the §10.5 action set is the natural vocabulary), and enforce append-only in the entity subclass + entity permissions. **CLOSED 2026-08-05 — `CK_ContractEvent_EventType` closes the vocabulary, and `ContractEventEntityServer` refuses edit and delete. Naming the set exposed a live split: the seed wrote `TermRenewed` while the operation wrote `Renewed`.** |
| X.16 ✅ | **`mj-app.json` still carries template metadata** — `"license": "<Set-this>"`, `"categories": ["Template"]`, `"tags": ["template","sample","starter"]`. | `mj-app.json` | It publishes as an unlicensed template. | Set them before first publish; gate on the literal `<Set-this>`. **CLOSED 2026-08-05 — `mj-app.json` now carries `ISC` (matching bizapps-orders) with real categories and tags.** |
| X.17 ✅ | **Seeded `ContractType` rows exist in the plan and in `demo/`, but not in `metadata/`.** `Contract.ContractTypeID` is `NOT NULL`, so a clean install has no creatable contracts. | master §3.1 / §10.6 C1 ("`ContractType` seed metadata still to author") vs `metadata/` (only `applications/`, `schema-info/`) | This is the difference between "the app installs" and "the app works". A clean-install test today produces a database in which no contract can be created. | Author `metadata/contract-types/` with the six hardcoded-UUID rows; verify with drop-schema → setup → sync. **CLOSED 2026-08-05 — `ContractType` ships as metadata, so a clean install has all six types.** |
| X.18 | **The mockup's "Source" column has no schema backing** — and the mockup says so. There is no `Contract.OriginType`, and the manual-entry case (the one the column exists to mark) leaves no trace at all. | `contracts-list.html` callout | Either the column ships or the roster loses a column reviewers have already seen. | Either add `Contract.OriginType`, or write a first `ContractEvent` whose `EventType` is the origin — which then depends on X.15's vocabulary. |
| X.19 | **`ExecutedDate >= EffectiveDate` was deliberately removed and nothing records that as a rule.** It lives only as a comment in the migration. | Migration lines 149–152 | The next person to see a December execution on a January contract will re-add the constraint, and it will reject correct data again. | The regression test (**B.13**) is the durable record — write it. |

---

## Cannot be tested yet, and why

| # | Blocked item | Blocked on | What becomes testable when it lands |
|---|---|---|---|
| Y.1 | `ContractPriceResolver` — contracted price wins, declines cleanly, refuses on ambiguity (**G.6, G.7**) | **D-2**: whether orders gets a *general pre-walk* resolver slot or a dedicated `Agreement:` key — and how multiple registrants coexist, since MJ's ClassFactory resolves **one** instance per key, so an unkeyed pre-walk slot admits exactly one app. **Amith's call.** Orders' own master plan claims the slot is "reserved at the top of the chain"; verified against `PriceResolver.ts`, it is not there. | All of section G's engine rows, and the payoff the design exists for: contracted prices applying to **ad-hoc** orders, not just billing-schedule output. |
| Y.2 | `Subscription.BillingMode` — `Self` \| `External`, with `Orders.SpawnRenewals` skipping `External` (**H.2**) | The orders PR (C0). Additive, defaulted `'Self'` so no existing behaviour changes and no backfill is needed — but it is not merged. | Subscription-line materialization end to end, and the "exactly one engine spawns orders for a subscription" invariant that prevents duplicate billing. |
| Y.3 | `EscalationBasis = 'Index'` (**F.2**) | **P-3** — no index feed exists, and a bare `EscalationIndexCode` column was proposed and rejected (a code names an index but nothing resolves it). | Index-based escalation. Until then the only testable behaviour is that the **value saves** and the engine **refuses to execute it with a named reason**. |
| Y.4 | `LineType = 'Usage'` (**H.5**) | **P-2** — orders' metering engine is deferred (orders §21); nothing supplies a quantity. Out of v1 by decision; the value stays so the schema does not change when metering arrives. | Usage true-ups. Same interim rule as Y.3: the value saves, the engine refuses. |
| Y.5 | Everything involving a **deal** — `Contracts.CreateFromDeal`, `RenewalMode='Deal'` (**F.9**), the workspace provenance strip's Deal step, the list's "9 with no renewal deal yet" tile (**P.1**) | `bizapps-sales` **does not exist**. The operation can be built here; nothing can call it. The reverse lookup (`Deal.ContractID` / `Deal.RenewsContractID`) has no source. | Deal-sourced creation, renewal-as-a-deal, and the renewal forecast that reads `ContractTerm.RenewalProbability`. Note **C.7/O.15 are testable today** and should be — they assert the *absence* that must survive sales' arrival. |
| Y.6 | `LineType = 'Milestone'` — "milestone is marked reached" (**H.4**) | **No ruling and no schema.** `ContractBillingSchedule.ScheduleType='Milestone'` says a milestone schedule exists; nothing anywhere records that a milestone *was reached*, or by whom. | Milestone draws. Needs either a column, a `ContractEvent` type, or a decision that reaching a milestone simply means a human sets the event's `ScheduledDate`. |
| Y.7 | `TrueUpPolicy = 'Rollover'` exact behaviour (**K.10**) | **Unspecified.** Whether the unconsumed balance increases the next period's `CommittedAmount` or creates a new commitment row is not stated in the plan, the ERD or the migration comments. | The third true-up path. `BillShortfall` and `Forfeit` (K.8, K.9) are specified and testable as soon as the engine exists. |
| Y.8 | Renewal `AsOf` semantics (**G.3, F.7**) | **Andrew's call** (master §10.1 #3) — probably the individual subscription end dates, but open. Nothing stores a resolved price until it is settled. | Which moment the engine prices a renewal at. §12's first-renewal-vs-later-renewal rule is testable now; *which date the first renewal uses* is not fully pinned. |
| Y.9 | "What did this line cost last term" (**P-1**) | **No `ContractLine → OrderLine` mapping.** Deriving it means matching by `ProductID` inside the term's orders — fine when a product appears once, ambiguous when it does not (and co-term stubs make repeats normal). Explicitly **not** to be solved by shadow-copying prices onto `ContractLine` (G.5). | Trustworthy renewal pricing from actual billed amounts. Needed **before** the renewal engine (C4). |
| Y.10 | Term-level `PricedAt` (**P-4**) | **Open question.** Contract-level was ruled; a renewal term priced on a different date, or a backdated manual renewal, may want its own. | Per-term as-of pricing. Raise it if a renewal needs to price as of its own moment. |
| Y.11 | `Contracts.GenerateBillingEvent` and the whole of section J's engine behaviour | Y.1 **and** Y.2 — the two orders seams. Plus the concurrency claim state (X.13's sibling, **J.13**), which needs a migration because `CK_ContractBillingEvent_Status` has no `Generating` value. | J.7–J.14, K.8–K.10, H.2–H.6 — i.e. most of what the app is *for*. |
| Y.12 | `<mj-record-signature-status>` **send** path (**N.6**) | A real e-signature **provider account** (DocuSign / Dropbox Sign / PandaDoc). Read-only rendering against seeded `SignatureRequest` rows is testable without one. | The full §10.2 lifecycle, envelope-driven. |
| Y.13 | PostgreSQL parity (**Q.6**) | C6 not started; `mj migrate convert` + CI wiring. | Cross-platform install. Note the 48 CHECK constraints are the most likely conversion casualties — the PG suite must re-run all of them. |
| Y.14 | `ContractType.AllowsCoterm` and `DriverClass` behaviour (**D.10, D.11**) | **Nothing reads either column.** No base behaviour class exists; no co-term gate is implemented. | Type-driven behaviour. Until then the only honest test is a grep proving no consumer exists — which is itself worth committing, so the day one appears the test fails and gets updated. |

---

## Appendix — all 48 CHECK constraints, mapped

Verify none is missing: 48 names, 48 IDs.

| Table | Constraint | ID |
|---|---|---|
| `ContractType` | `CK_ContractType_BillingFrequency` | D.1 |
| `ContractType` | `CK_ContractType_RenewalMode` | D.2 |
| `ContractType` | `CK_ContractType_TermMonths` | D.3 |
| `ContractType` | `CK_ContractType_EscalationPercent` | D.4 |
| `ContractType` | `CK_ContractType_CancellationWindow` | D.5 |
| `ContractSequence` | `CK_ContractSequence_Singleton` | A.3 |
| `ContractSequence` | `CK_ContractSequence_NextSeq` | A.4 |
| `Contract` | `CK_Contract_Status` | B.1 |
| `Contract` | `CK_Contract_CustomerXor` | C.1 |
| `Contract` | `CK_Contract_ParentNotSelf` | B.10 |
| `Contract` | `CK_Contract_SupersededNotSelf` | B.9 |
| `Contract` | `CK_Contract_PricedWhenActive` | B.11 |
| `Contract` | `CK_Contract_CancellationWindow` | B.12 |
| `ContractTerm` | `CK_ContractTerm_Status` | E.1 |
| `ContractTerm` | `CK_ContractTerm_Dates` | E.2 |
| `ContractTerm` | `CK_ContractTerm_TermNumber` | E.3 |
| `ContractTerm` | `CK_ContractTerm_EscalationBasis` | F.2 |
| `ContractTerm` | `CK_ContractTerm_BillingFrequency` | E.6 |
| `ContractTerm` | `CK_ContractTerm_AnchorMonth` | E.7 |
| `ContractTerm` | `CK_ContractTerm_AnchorDay` | E.8 |
| `ContractTerm` | `CK_ContractTerm_RenewalProbability` | E.10 |
| `ContractTerm` | `CK_ContractTerm_CommittedAmount` | E.9 |
| `ContractTerm` | `CK_ContractTerm_MaxEscalationPercent` | F.3 |
| `ContractTerm` | `CK_ContractTerm_RenewalNoticeDays` | F.4 |
| `ContractTerm` | `CK_ContractTerm_RenewalNotSelf` | F.1 |
| `ContractLine` | `CK_ContractLine_LineType` | H.1 |
| `ContractLine` | `CK_ContractLine_Quantity` | H.7 |
| `ContractLine` | `CK_ContractLine_ContractedUnitPrice` | H.8 |
| `ContractLine` | `CK_ContractLine_DiscountPct` | H.9 |
| `ContractLine` | `CK_ContractLine_Dates` | H.10 |
| `ContractLine` | `CK_ContractLine_SubscriptionOnlyOnSubscriptionLine` | H.11 |
| `ContractLine` | `CK_ContractLine_SubscriptionTypeOnlyOnSubscriptionLine` | H.12 |
| `ContractBillingSchedule` | `CK_ContractBillingSchedule_ScheduleType` | I.1 |
| `ContractBillingSchedule` | `CK_ContractBillingSchedule_Frequency` | I.2 |
| `ContractBillingSchedule` | `CK_ContractBillingSchedule_CadenceNeedsFrequency` | I.3 |
| `ContractBillingEvent` | `CK_ContractBillingEvent_Status` | J.1 |
| `ContractBillingEvent` | `CK_ContractBillingEvent_GeneratedHasOrder` | J.2 |
| `ContractBillingEvent` | `CK_ContractBillingEvent_FailedHasReason` | J.3 |
| `ContractBillingEvent` | `CK_ContractBillingEvent_ComputedAmount` | J.4 |
| `ContractCommitment` | `CK_ContractCommitment_CommitmentType` | K.1 |
| `ContractCommitment` | `CK_ContractCommitment_TrueUpPolicy` | K.2 |
| `ContractCommitment` | `CK_ContractCommitment_Status` | K.3 |
| `ContractCommitment` | `CK_ContractCommitment_CommittedAmount` | K.4 |
| `ContractCommitment` | `CK_ContractCommitment_ConsumedAmount` | K.5 |
| `ContractCommitment` | `CK_ContractCommitment_Period` | K.6 |
| `ContractAmendment` | `CK_ContractAmendment_AmendmentType` | L.1 |
| `ContractAmendment` | `CK_ContractAmendment_Status` | L.2 |
| `ContractAmendment` | `CK_ContractAmendment_AmendmentNumber` | L.3 |

**Constraints the plan implies but the schema does not have** (each has a `CK_`-shaped name proposed
in the contradictions table): `CK_ContractTerm_EscalationPercent` (X.1) ·
`CK_ContractTerm_EscalationWithinCap` (X.1) · `CK_ContractType_MaxEscalationPercent` (X.2) ·
`CK_ContractType_RenewalNoticeDays` (X.2) · `CK_ContractLine_SubscriptionNeedsType` (X.5) ·
`CK_Contract_SupersededHasSuccessor` (X.6) · `CK_ContractBillingEvent_GeneratedHasTimestamp` (X.12) ·
`CK_ContractAmendment_ApprovedHasTask` (X.14) · `CK_ContractEvent_EventType` (X.15).
