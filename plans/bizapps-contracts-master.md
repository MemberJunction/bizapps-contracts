# BizApps Contracts — master plan

> **This is the app's source of truth**, kept in-repo alongside the code it governs (the same convention
> `bizapps-orders` follows).
>
> **Status:** the app is being **rebuilt from a clean sheet.** The v1 schema (10 tables, a billing engine,
> a pricing resolver) is retired in full and nothing of the new design is built yet.
> **Repo:** `MemberJunction/bizapps-contracts` · **Schema:** `__mj_BizAppsContracts`
>
> **Schema detail lives in [`ERD-planned.md`](./ERD-planned.md)** — every table, column, constraint, the
> reversal log and the future-phase list. This file is the *why* and the *what next*; that file is the *what*.
>
> **Provenance and authority, most recent first:**
> 1. Amith's written review of the plan — **2026-08-18**
> 2. Meeting notes — **2026-08-18** (naming, field removals)
> 3. The contracts planning meeting transcript, *Contracts App Convo* — **2026-08-16**
>
> The reviewed plan that produced these rulings, plus its Word/HTML/PDF renderings, is kept at
> `~/MJDev/reports/contracts-v2-plan/`. The **v1 master plan** this file replaced is in git history
> (`git show HEAD:plans/bizapps-contracts-master.md`); it describes a billing engine that no longer exists
> and is history only.

---

## 1. What this app is

**The source of truth for our obligations, and the place to find the documents that show them** — the
executed document, the standard agreement it incorporates, the provisions we negotiated away from that
standard, and the forward-looking commitments that never appear on an invoice.

It is a **record-keeping and lookup system, not a transaction engine.**

### Owns

Executed documents and their links · which version of the Master Agreement a customer signed · which
provisions of that agreement were modified · renewal and cancellation terms as the paper states them ·
the annual increase · the agreement's own lifecycle (effective, executed, end, terminated) · change-order
and supersession lineage.

### Does not own

Pricing · billing cadence · invoices · payments · revenue recognition · subscriptions · order creation ·
the customer master · the sale · **approval of negotiated terms** (that is sales, on the deal).

### Why it narrowed

The old system existed to **drive revenue recognition** — it tracked contract terms, the products on
those terms, and their renewals. Subscriptions in `bizapps-orders` do that now, and rebuilding it here
would leave two systems that have to agree about money. So the billing engine, the pricing plugin,
commitment tracking and the amendment approval workflow all go away.

**10 tables → 7**, and the drop in complexity is far larger than that count suggests.

---

## 2. The flow

```
deal worked in sales
   → order created alongside it (quote status): products, pricing, quote history
   → deal terms approved  ── approval lives in SALES, on the deal
   → deal marked Closed Won
        → contract record created automatically  ── the only automation in v1
        → task created for finance
   → finance: link the document, set the agreement version, record modifications
```

**Contracts is the end of the chain and triggers nothing downstream.** It does not create orders — the
deals process does.

**The order and the contract are peers.** The order records what we *offered*; the contract records what
we *signed*. Closed Won confirms the order and creates the contract, and **confirmation locks the order
against further change**, so the two cannot drift apart. Neither generates the other, so no fact is stored
twice with two owners — and where a field name appears on both, the contract states what the paper says
while the order states what the system will do.

---

## 3. The data model

Seven tables. Full detail in [`ERD-planned.md`](./ERD-planned.md).

| Table | Role |
|---|---|
| `Contract` | One piece of signed (or implied) paper. The centre of the app |
| `ContractTemplate` | One version of a standard agreement — in practice the Master Agreement, by its dated URL |
| `ContractTemplateProvision` | The numbered clause list of a template version (`3.5(b)` + heading) |
| `ContractTemplateModification` | *This contract modified that provision.* A lean join — no wording stored |
| `ContractType` | Lookup: Order Form · Statement of Work · Payment Link · Change Order |
| `ContractTemplateType` | Lookup: Master Agreement · Statement of Work |
| `ContractSequence` | The counter behind `CTR-####` |

**Change orders and re-papered agreements are contracts**, pointing at the one they amend
(`ParentContractID`) or replace (`SupersededByContractID`). A renewal is simply the next contract.

### The four rules that explain the schema

1. **Every reference is a real foreign key.** The one exception is a genuine polymorphic pair.
2. **Contracts may never hard-FK into `bizapps-sales`** — sales depends on us, so the deal link is
   `CreatingEntityID` + `CreatingRecordID`.
3. **Structured obligations are columns; textual deviations are modification rows.** This is the test to
   apply to every future field request — it is what removed `TerminationPolicy`.
4. **Documents, signatures and audit are MJ's.** `FileEntityRecordLink`, `SignatureRequest` and
   `RecordChange` all point *at* us; we add no columns for them.

---

## 4. Decisions, as ruled

Every item below is settled. §5 lists what is still open.

| # | Decision | Source |
|---|---|---|
| D-1 | **Renewal obligations live in contracts** — auto-renew, notice periods, annual increase. Subscriptions know nothing of them; orders assumes auto-renewal until a sub is cancelled and prices renewals from then-current product rules. **Finance reconciles the difference manually** — *"no worse than current, as everything is manual right now"* | Amith 08-18 |
| D-2 | **No approval workflow in contracts.** Approval of negotiated terms lives in `bizapps-sales`, on the deal, modelling Johanna's levels of authority. At current volume she may approve manually; the contract is generated *after* deal approval | Amith 08-18 |
| D-3 | **No versioned SOW templates in v1.** SOWs have standard language but no versioned template today — *"that will change for sure as we scale PS"* | Amith 08-18 |
| D-4 | **Modifications are structured, not textual.** A modification names a provision; the wording stays in the PDF | transcript + 08-18 |
| D-5 | **`ContractTemplateProvision` is required** — the clause list, so modifications categorise cleanly | Amith 08-18 |
| D-6 | **No termination-policy field.** It is *"simply one of the provisions in a contract"* | Amith 08-18 |
| D-7 | **No document is required to create a contract**, and no named document column exists — the link table is sufficient | 08-18 |
| D-8 | **Direct PDF handling is first-class in v1**; PandaDoc retrieval through MJ's eSignature driver is the end state | 08-18 |
| D-9 | **Document downloads restricted** to sales leadership, finance and legal; everyone else sees the record | Amith 08-18 |
| D-10 | **No library of reusable clause text** — *"a nightmare to manage."* Distinct from D-5, which is a list of provision *identities*, not text | meeting |
| D-11 | **A payment-link sale still gets a contract** — it references the MA even though nothing is signed. Pure self-serve web orders get none | transcript |
| D-12 | **No grouping construct above `Contract`** — the customer organisation is the grouping | transcript |

The full reversal log — thirteen items, each with owner and date — is **§9 of the ERD**.

---

## 5. Open items

| # | Item | Owner |
|---|---|---|
| O-1 | **Migration.** We need a correct list of all active contracts as ground truth before go-live. Scope and source of that data is pending | Andrew Schwartz Crane |
| O-2 | **The deal-approval model** — Johanna's authority levels, documented so Josue can build it in the sales app. Contracts-side impact is nil; it gates when the contract gets created | Marcelo + Johanna |

---

## 6. The work

Fourteen pieces. The first four are the critical path; **the target is as soon as we can get there**, with
correct active-contract data in place before go-live.

| # | Piece | Notes |
|---|---|---|
| 1 | Retire the v1 schema; write the new baseline migration | 7 tables. The `mj-app.json` pass — dependencies trimmed to `common`, description and tags rewritten — landed with this plan |
| 2 | CodeGen + entity packages | Regenerate from the new schema |
| 3 | Seed reference data | Contract types, template types, numbering |
| 4 | **Seed the provision list** from the current Master Agreement | A prerequisite, not a nicety: with the provision FK mandatory, finance cannot record a modification until the clause list exists |
| 5 | Contract list and detail screens | The core surface |
| 6 | Entity CRUD | |
| 7 | Agreement version registry | Register each MA version by its dated URL |
| 8 | Modification capture | Pick a provision, save the row, flag flips |
| 9 | Document handling | Attach, view and download through MJ storage + the link table |
| 10 | Deal → Contract automation, with the finance task | Joint with the sales app, which supplies the Closed-Won trigger, the deal id, and the modified flag |
| 11 | Customer view | Every agreement and document for an organisation |
| 12 | Renewal and expiry watchlist | Driven by `EndDate` and the notice fields |
| 13 | Migration of active contracts, test coverage and demo data | Gated on O-1 |
| 14 | **Rewrite the README** | 658 lines still specifying the v1 billing engine — *"this README is the specification we are building to"* — and its own documentation table describes this plan as covering *"the billing-event engine, the orders seams"*. The repo's front door should describe the record-keeping app. Last on the list because it should be written against what actually shipped |

### Document handling is assembly, not construction

MJ already ships file upload, a file grid with download, an **in-app PDF viewer** (PDF.js, already a
platform dependency), viewers for docx/xlsx/images/video, seven storage drivers including SharePoint, and
a **PandaDoc** eSignature driver. The one missing piece is a **record-scoped "documents on this record"
panel** — small to build, and a good candidate to contribute upstream to MJ rather than keep local.
Details and the honest caveats are in [`mj-storage-and-esignature-notes.md`](./mj-storage-and-esignature-notes.md).

Reading PDFs straight out of SharePoint needs an Azure app registration from IT. **That is deliberately
off the critical path** — finance can attach documents through platform storage meanwhile, and switching
to SharePoint later is configuration, not redesign.

---

## 7. Future phases

Recorded so they are not re-litigated. Full list in **§10 of the ERD**.

- **Per-product renewal-pricing override** from the contract — a child table keyed on contract + product.
  Today orders renews on then-current product pricing and finance reconciles by hand.
- **Deeper contract ↔ subscription integration**, so a renewal reads the agreement's escalation.
- **`ProvisionText`** on the provision list — one additive column.
- **PandaDoc retrieval** through the MJ eSignature driver.
- **Versioned SOW templates**, as professional services scales.

---

## 8. Build conventions

| | |
|---|---|
| Schema | `__mj_BizAppsContracts` |
| Entity prefix | `MJ_BizApps_Contracts:` |
| npm scope | `@mj-biz-apps/contracts-*` |
| Platform | T-SQL source of truth; PG via `sql-converter`, CI-validated |
| Migrations | **Pre-production:** edit the baseline in place and rebuild from zero rather than stacking fix-ups. Switch to additive-only at first publish |
| Seed data | Metadata sync (`metadata/`), never SQL `INSERT`s |
| Server rules | Cross-row invariants live in entity subclasses — see ERD §7.1 |
| Derived values | Layered base views, following orders' `vwOrderHeaders` / `IsOverdue` pattern |
