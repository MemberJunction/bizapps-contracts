# BizApps Contracts — master plan

> **This is the app's source of truth**, kept in-repo alongside the code it governs (the same convention
> `bizapps-orders` follows).
>
> **Status:** the app is being **rebuilt from a clean sheet.** The v1 schema (10 tables, a billing engine,
> a pricing resolver) is retired in full and nothing of the new design is built yet.
> **Repo:** `MemberJunction/bizapps-contracts` · **Schema:** `__mj_BizAppsContracts`
>
> **Schema detail lives in [`ERD-planned.md`](./ERD-planned.md)** — every table, column, constraint, the
> reversal log and the future-phase list. This file is the *why*, the *how* and the *what next*; that
> file is the *what*.
>
> **Provenance and authority, most recent first:**
> 1. Amith's rulings relayed in chat (Marcelo) — **2026-08-18**: adopt the **Related-Record Collections**
>    approach and bind the Angular UI directly to the BaseEntity subclass, with orders as the reference
>    (*"See how I did this in Orders repo… next is up to date there"*); **provision text ships in v1**;
>    and the modification row's template FK is dropped (D-13…D-15, ERD §9 R-15/R-16)
> 2. Amith's written review of the plan — **2026-08-18**
> 3. Meeting notes — **2026-08-18** (naming, field removals)
> 4. The contracts planning meeting transcript, *Contracts App Convo* — **2026-08-16**
>
> The reviewed plan that produced these rulings, plus its Word/HTML/PDF renderings, is kept at
> `~/MJDev/reports/contracts-v2-plan/`. The **v1 master plan** this file replaced is in git history;
> it describes a billing engine that no longer exists and is history only.

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
| `ContractTemplateProvision` | The numbered clause list of a template version — `3.5(b)` + heading + **the clause's own text** (D-13) |
| `ContractTemplateModification` | *This contract modified that provision.* A lean join — the negotiated wording stays in the PDF |
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

And a corollary that trimmed the modification row (D-14): **store a fact, derive a projection** (ERD
§7.2). `ContractTemplateModification` carries no `ContractTemplateID` — the provision it names belongs
to exactly one template, so the template is always derivable and a stored copy could only agree or lie.

---

## 4. Decisions, as ruled

Every item below is settled (D-14 carries a confirmation flag — see O-3). §5 lists what is still open.

| # | Decision | Source |
|---|---|---|
| D-1 | **Renewal obligations live in contracts** — auto-renew, notice periods, annual increase. Subscriptions know nothing of them; orders assumes auto-renewal until a sub is cancelled and prices renewals from then-current product rules. **Finance reconciles the difference manually** — *"no worse than current, as everything is manual right now"* | Amith 08-18 |
| D-2 | **No approval workflow in contracts.** Approval of negotiated terms lives in `bizapps-sales`, on the deal, modelling Johanna's levels of authority. At current volume she may approve manually; the contract is generated *after* deal approval | Amith 08-18 |
| D-3 | **No versioned SOW templates in v1.** SOWs have standard language but no versioned template today — *"that will change for sure as we scale PS"* | Amith 08-18 |
| D-4 | ~~Modifications are structured, not textual~~ &rarr; **superseded by D-16.** A modification names a provision **and** carries the negotiated wording | Amith, 08-18 (ERD R-17) |
| D-5 | **`ContractTemplateProvision` is required** — the clause list, so modifications categorise cleanly | Amith 08-18 |
| D-6 | **No termination-policy field.** It is *"simply one of the provisions in a contract"* | Amith 08-18 |
| D-7 | **No document is required to create a contract**, and no named document column exists — the link table is sufficient | 08-18 |
| D-8 | **Direct PDF handling is first-class in v1**; PandaDoc retrieval through MJ's eSignature driver is the end state | 08-18 |
| D-9 | **Document downloads restricted** to sales leadership, finance and legal; everyone else sees the record | Amith 08-18 |
| D-10 | **No library of reusable clause text** — *"a nightmare to manage."* Distinct from D-5, which is a list of provision *identities*, and from D-13, which is the standard text those identities carry | meeting |
| D-11 | **A payment-link sale still gets a contract** — it references the MA even though nothing is signed. Pure self-serve web orders get none | transcript |
| D-12 | **No grouping construct above `Contract`** — the customer organisation is the grouping | transcript |
| D-13 | **Provision text ships in v1.** `ContractTemplateProvision.ProvisionText` (nullable `nvarchar(max)`), seeded from the current Master Agreement. This does **not** touch D-4 or D-10: it is the *standard* clause's own text, there for reference while categorising a modification — the *negotiated* wording still lives only in the PDF, and there is still no reusable-clause library. Was future-phase F-3; now in scope (ERD §9 R-15) | Amith via Marcelo, 08-18 chat — *"Do you want the provision's text in the provision table?" "yep"* |
| D-14 | **The modification row carries no template FK.** `Modification → Provision → Template` derives it, and the derivation survives the multi-template future intact — a provision belongs to exactly one template no matter how many templates a contract incorporates. Keeping the column would demand a "named template = provision's template" server rule to stop rows lying. Reverses the 08-18 "keep" (ERD §9 R-16); flagged for Amith's nod — O-3 | Marcelo, 08-18 |
| D-15 | **The app is built on MJ 6's composition and forms stack.** The 1:N dependents (`Contract.Modifications`, `ContractTemplate.Provisions`) are metadata-declared **related-record collections**; the Angular UI binds **directly to the BaseEntity subclass** and one `Save()` persists the graph; forms are the generated forms customised by **`BaseFormPanel` contributions**, not bespoke editors. *"Make sure to use the new Related Records approach in Contracts … directly bind the Angular UI to the BaseEntity subclass. See how I did this in Orders repo."* §6 is the design; orders on `next` is the reference | Amith via Marcelo, 08-18 |
| D-16 | **Both texts are stored, and read as a pair.** `ContractTemplateProvision.ProvisionText` holds the standard clause; `ContractTemplateModification.ModificationText` holds what this contract says instead. Supersedes D-4, which rested on the transcript &mdash; **Amith overruled it**. Corollary he stated with it: *all contract text ends up in provisions*; the template holds no prose of its own | Amith, 08-18 |
| D-17 | **Forms use the left-nav rail.** `Entity.Configuration.UI.Form.Layout = "left-nav"` with `RelatedRolePolicy: "smart"` and a `PrimaryRelatedBudget`, matching what orders sets on every entity. Supersedes &sect;6.4's `Layout: 'auto'` &mdash; at six sections on the Contract form the rail is the point, and family consistency settles it anyway | Marcelo, 08-18 |
| D-18 | **Reference data is cached in an engine, not re-queried per form.** A `BaseEngine` subclass caches contract types, template types, templates and **provisions** &mdash; without it the provision picker issues a `RunView` every time a row is added. See &sect;6.6 | Marcelo, 08-18 |
| D-19 | **No `Status` column; lifecycle is derived.** Four of its five values were projections of the dates and the two self-FKs, and the fifth (`Draft`) was the finance task wearing a status. The layered base view exposes `State`, `IsAwaitingDocument` and `IsChangeOrder`. ERD &sect;4.5 / R-18 | Marcelo, 08-18 |
| D-20 | **`AutoRenew` is a plain true/false bit.** No "not stated" third value; the day counts stay nullable | Marcelo, 08-18 |
| D-21 | **The watchlist ships with fixed default filters and no saved views.** Users drive the filters in-session; persisting custom watchlists is phase 2 or never. The screen is the **stock MJ grid** plus minor chrome, using MJ's own tokens | Marcelo, 08-18 |
| D-22 | **Modifications get a custom form as well as the inline panel — one shared editor component, two hosts.** MJ cannot embed a child entity's form inside a parent, so the same component renders inline in the contract's panel (joining the parent's single save) and as the body of the modification's own custom form (reached via *Open*). No duplicated logic, and the single transaction survives | Marcelo, 08-18 |
| D-23 | **Grids and pickers select the BASE VIEWS, never raw tables**, so foreign keys display names rather than IDs. MJ's generated base views already expose the joined name columns | Marcelo, 08-18 |

The full reversal log — sixteen items, each with owner and date — is **§9 of the ERD**.

---

## 5. Open items

| # | Item | Owner |
|---|---|---|
| O-1 | **Migration.** We need a correct list of all active contracts as ground truth before go-live. Scope and source of that data is pending | Andrew Schwartz Crane |
| O-2 | **The deal-approval model** — Johanna's authority levels, documented so Josue can build it in the sales app. Contracts-side impact is nil; it gates when the contract gets created | Marcelo + Johanna |
| O-3 | **Amith's nod on R-16** — dropping `ContractTemplateModification.ContractTemplateID` reverses his 08-18 "keep" (his stated future-proofing concern is unaffected; see D-14). Raise at the next review; the schema below assumes the drop | Marcelo |

---

## 6. How the app is built — composition and forms

This section is new with D-15 and is the architecture the work in §7 implements. MJ 6 gives an app
three composition axes ([`related-record-collections.md`], [`embedded-records.md`], both in
`MJ/packages/MJCore/docs/`) and one forms stack ([`FORMS_ARCHITECTURE_GUIDE.md`] in `MJ/guides/`).
Contracts uses each exactly where its shape fits, and orders (`next`) is the worked reference for all
of it.

### 6.1 Related-record collections — what contracts declares

v1 had `ContractTerm`/`ContractLine` hanging off a hub; v2's analogs are the two 1:N dependents, and
both are declared as collections **in metadata, never in code** — a `RelatedRecordCollection` blob on
the `EntityRelationship` row, which CodeGen turns into a typed `DeclareRelatedRecords(...)` on the
**generated** entity class, so browser and server both get it and no subclass has to exist:

| Collection | On | Config |
|---|---|---|
| `Contract.Modifications` | `Contract → Contract Template Modifications` (join `ContractID`) | `{ "Name": "Modifications", "Source": "database", "Load": "explicit", "OnRemove": "delete", "OrderBy": "__mj_CreatedAt ASC" }` |
| `ContractTemplate.Provisions` | `Contract Template → Contract Template Provisions` (join `ContractTemplateID`) | `{ "Name": "Provisions", "Source": "database", "Load": "explicit", "OnRemove": "delete", "OrderBy": "Sequence ASC", "Sequence": { "Field": "Sequence", "From": 1 } }` |

Notes that keep these honest:

- **`Modifications` declares no `Sequence` policy** — the row has no positional column; a modification
  is identified by which provision it names, not by position. Same reasoning as orders' Payment Lines
  (ordered by `AllocatedAt`, no sequence), and declaring a sequence against a field that does not exist
  fails at save time.
- **`Provisions` is the Lines-shaped one** — `Sequence` is genuinely positional (ERD §5.1: provision
  numbers do not sort as text), so the collection renumbers gap-free across adds and removals.
- **`OnRemove: 'delete'` on both** — true composition. A modification without its contract, or a
  provision without its template version, means nothing.
- Metadata files follow orders' layout exactly: `metadata/entity-relationships/.entity-relationships.json`
  with `"RelatedRecordCollection": "@file:modifications-collection.json"` per row, keyed by **name
  lookups, never hardcoded UUIDs** (`@lookup:MJ: Entity Relationships.Entity=…&RelatedEntity=…`) —
  relationship IDs are minted by CodeGen and would stop matching on a from-zero rebuild.
  `RelatedEntity`/`RelatedEntityJoinField` are **not** repeated inside the blob; they are columns on
  the same row.

**Deliberately not declared**, so it is not re-litigated:

| Candidate | Why not |
|---|---|
| `Contract.ChangeOrders` (self-FK `ParentContractID`) | A change order is a **first-class contract** with its own lifecycle, number and deal — not a companion that should ride its parent's save, and no `OnRemove` mode is right (deleting destroys signed paper; orphaning erases lineage). The lineage is read-only UI (§6.4), loaded per-set via `RunView({ IncludeRelatedRecords })` or a related grid |
| Anything on `SupersededByContractID` | Same reasoning; supersession is set once by the re-papering flow (§6.3) |
| Reverse collections on the lookups (`ContractType`, `ContractTemplateType`, `Company`, `Organization`) | A lookup's dependents are unbounded lists, not a composition unit |

**For result sets, never loop**: `RunView({ EntityName: 'MJ_BizApps_Contracts: Contracts',
ResultType: 'entity_object', IncludeRelatedRecords: ['Modifications'] })` costs 1+K queries for the
whole set — that is what the customer view and the watchlist use.

### 6.2 Embedded records — none here, one next door

Contracts v1 declares **no** `EntityField.EmbeddedRecord`. Every FK on `Contract` is a lookup
(`ContractTypeID`, `CompanyID`, `CustomerOrganizationID`, …) or lineage (`ParentContractID`,
`SupersededByContractID`) — none is an owned 1:1 peer, and an embed's construct cost is only worth
paying on conversion-shaped relationships. Recorded so nobody retrofits one for symmetry.

The one place the embed pattern genuinely fits is **on the sales side of work item 10**: sales depends
on contracts, so `Deal.ContractID` can be a hard FK, and declaring it embedded
(`{ "OnClear": "orphan" }` — deleting a deal must never delete signed paper) makes the Closed-Won
automation exactly the doc's worked example: populate `deal.ContractID_EnsureObject()`, one
`deal.Save()`, one transaction creating the contract and stamping the FK. That declaration is the
**sales app's** to ship; §7 item 10 records what contracts expects of it.

### 6.3 What a save is, and where every rule runs

One `contract.Save()` persists the header **and** its modifications: in the browser the graph
serialises into a single `MJ.SaveEntityGraph` remote operation and the server runs the same executor
inside one transaction; every node is written by that record's own `Save()`, so Record Changes,
validation and subclass hooks all fire per row. `Validate()` runs over the complete set — including
pending removals — **before any write, in the browser too**, because the rules live on shared
subclasses.

This deletes machinery, which is the point. v1 hand-rolled all of it: the `Contracts.SaveContract`
remote operation, `ContractDraft` (688 lines), `ChildCollection.ts`, and the client-draft hydration
that existed only to carry children over the wire — the exact inventory orders' own changeset lists as
replaced by collections. **v2 ships zero remote operations.**

Class chain, copied from orders: generated `mjBizAppsContractsContractEntity` → shared
`ContractEntity` (`packages/Entities`, `@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')`,
**no `Save()` override**) → server `ContractEntityServer` (`packages/CoreEntitiesServer`, registered
later so ClassFactory priority resolves it server-side while the browser keeps the shared class).

| Rule (ERD §7.1) | Where it runs | How |
|---|---|---|
| `ContractNumber` = `CTR-{seq}` | `ContractEntityServer.Save()` | Copy orders' `nextSequence` verbatim (`OrderEntityServer.ts`): `UPDLOCK, HOLDLOCK` counter take with `OUTPUT … INTO` (bare OUTPUT is forbidden by the `__mj_UpdatedAt` trigger), inside the save's transaction, only when `!IsSaved && !ContractNumber`. Contracts needs **no** `SkipRelatedCollections` dance — nothing prepares child rows, so the plain graph save carries `Modifications` |
| `HasModifications` monotonic — must be true when modification rows exist, never auto-cleared | **Shared** `ContractEntity.Validate()` (browser preflight + server authority) **and** `ContractTemplateModificationEntityServer` | `Validate()`: reject `HasModifications === false` when `Modifications.Count > 0` — with orders' unloaded-collection guard (`Count === 0 && (!IsSaved \|\| Modifications.IsLoaded)` means *known* empty; empty+saved+unloaded means *unknown*, settled server-side). The server modification subclass forces the parent flag true on a **standalone** modification save, so the invariant holds outside the graph path too |
| A modification's provision must belong to the template this contract incorporates | `ContractTemplateModificationEntityServer` (authoritative) + the picker (preflight) | Needs a cross-entity read, so the hard check is server-side; the UI never offers an out-of-template provision in the first place (§6.4). New with D-14 — this rule replaces the column that could lie |
| `ContractType = 'Change Order'` ⇒ `ParentContractID IS NOT NULL` | Server subclass | Needs the type-table join, as the ERD rules |
| `Status = 'Superseded'` ⇔ `SupersededByContractID`; no self-parent/self-successor | `CHECK` constraints | In the baseline migration |
| Re-papering is one graph | `ContractEntity.Supersede(successor)` on the shared subclass | Sets predecessor `Status = 'Superseded'` + `SupersededByContractID`; the entity method is the API, mirroring orders' `Confirm()` |
| Validation errors reach the user attributed | shared subclasses + a `SectionForField()` static | Graph errors arrive as `Modifications[2].ContractTemplateProvisionID`; map `/^Modifications\[/` to the modifications section for red-dot navigation, as `OrderHeaderEntity.SectionForField` does |

### 6.4 Forms — generated forms plus contributions, one bespoke editor

Orders' current direction, adopted wholesale: **keep the generated form registered** and layer the
app's UX on as `BaseFormPanel` contributions; a full custom form replacement is a last resort (orders
needed exactly one, for the line editor + tab strip). Contracts expects to need **none** at first —
the pieces below are all panels on generated forms. Panels live in `contracts-ng` under
`src/lib/form-panels/`, registered `@RegisterClassEx(BaseFormPanel, { key, metadata })`, declared in a
module whose import fires the decorators, loaded after the generated forms module.

**On the Contract form:**

| Panel | Registration | What it does |
|---|---|---|
| Contract hero | `slot: 'before-fields'`, `sortKey: 100`, `contributionKey: 'header'`, `replacesSectionKey: 'details'` | `ContractNumber` + status chip + type + customer org + the date strip. Replaces the generic Details section (orders' Scenario B) |
| Renewal terms | `slot: 'after-fields'`, own `contributionKey` | The `AutoRenew` / notice / increase block, **labelled "as stated in the agreement"** (ERD §4.3) so nobody mistakes it for the subscription's operational setting |
| Modifications editor | `slot: 'after-related'`, `relatedEntity: 'MJ_BizApps_Contracts: Contract Template Modifications'` | **The D-15 centrepiece** — binds to `Record.Modifications` (see below); claiming `relatedEntity` hides the baked grid |
| Documents | `slot: 'after-fields'`, `sortKey: 60` | `RecordFilesPanelBase` carried forward from v1 (§6.5) |
| Lineage | `slot: 'after-related'`, `relatedEntity: 'MJ_BizApps_Contracts: Contracts'`, `relatedJoinField: 'ParentContractID'` | Change orders + supersession chain, read-only; claiming the self-FK is orders' product-category-hierarchy precedent |

**The modifications editor is the order-lines-editor pattern**
(`orders/packages/Angular/src/lib/custom/OrderHeader/order-lines-editor.component.ts`), simplified —
no pricing, no IS-A extensions:

- Bind the input entity; expose `get Modifications() { return [...(this._contract?.Modifications.Items ?? [])] }`
  (spread so Angular sees a fresh reference). On bind: `if (saved && !IsLoaded) await Modifications.Load()`.
- Add = `const m = await contract.Modifications.Create()` — the collection stamps `ContractID`; the
  editor sets `ContractTemplateProvisionID` from a picker **filtered to the contract's template's
  provisions** (one `RunView` on provisions by `ContractTemplateID`, or `template.Provisions`), plus
  optional `Notes`. Adding the first row sets `contract.HasModifications = true` in the same graph.
- Remove = `contract.Modifications.Remove(m)` — deleted on save (`OnRemove: 'delete'`).
- **The editor never saves.** The form container's Save toolbar drives one `record.Save()`; header +
  rows land in one transaction, or nothing does. Errors surface via the shared `Validate()` before the
  round trip, and save failures parse the serialised `ValidationResult` (orders' `ReadableSaveError`).
- Show `ProvisionText` (D-13) inline/expandable in the picker and rows, so finance reads the standard
  clause while recording that it was modified.

**The modifications editor is ONE component with TWO hosts (D-22).** MJ has no way to embed a child
entity's form inside a parent form, so rather than choose between the panel and a form we build a single
`modification-editor` component and render it in both places: inline inside the contract's panel, where it
binds to `Record.Modifications` and joins the parent's one `record.Save()`; and as the body of the
modification's **own custom form**, reached from the row's *Open* action for standalone editing. The
component takes the contract as an input, so in the form host the contract is fixed rather than editable.

**Grids and pickers read base views, not tables (D-23).** Every grid and lookup selects the generated base
view so FK columns render as names — `ContractType`, `CustomerOrganization`, `ContractTemplate` — instead of
UUIDs. This is free; the views already carry the joined name columns.

**On the ContractTemplate form:** a Provisions editor panel bound to `Record.Provisions` — same
pattern, `Sequence` handled by the collection, drag-to-reorder optional later. Seeding (§7 item 4)
writes through this same collection, so the registry UI and the seed exercise one code path.

**On other apps' forms — the customer view is mostly this.** Contracts owns the relationship rows its
FKs create, so it ships the chrome metadata and contributions onto Common's forms, exactly as orders
does (`person-orders.panel.ts` / `.form-chrome.json`):

- `Organization → Contracts`: `Configuration.UI.inclusion: 'Primary'`, `DisplayName: 'Agreements'` —
  plus (or instead) an agreements panel claiming the grid, with `NewRecordValues` seeding
  `CustomerOrganizationID` so **New** opens pre-linked.
- `Person → Contracts` (via `PrimaryContactPersonID`): `inclusion: 'More'`.
- `Company → Contracts`, `Entity → Contracts` (the polymorphic half), `Provision → Modifications`:
  `inclusion: 'None'` / `DisplayInForm: false` — plumbing, not UX.
- Contract's own related list from the modification FK is claimed by the editor panel above, so no
  stock grid doubles it.

**Chrome + overlays:** `Entity.Configuration.UI.Form` on Contract with **`Layout: 'left-nav'`** (D-17), plus `RelatedRolePolicy: 'smart'` and a `PrimaryRelatedBudget` &mdash; the settings orders carries on every entity. (An earlier draft said `Layout: 'auto'` was fine at this
section count). Quick capture anywhere (e.g. "record a modification" from the watchlist) uses the
stock overlays — `<mj-form-dialog>` / `MJFormPresenterService.Open({ Presentation: 'slide-in' })` —
never a bespoke dialog. List/watchlist pages are `BaseResourceComponent` surfaces registered by
DriverClass in `metadata/applications/`, as v1's nav already did.

### 6.5 Documents — assembly, not construction

MJ already ships file upload, a file grid with download, an **in-app PDF viewer** (PDF.js), viewers
for docx/xlsx/images/video, seven storage drivers including SharePoint, and a **PandaDoc** eSignature
driver. Verified against MJ `next` on 2026-08-18: the one missing piece is still a **record-scoped
"documents on this record" panel** — nothing in MJ's Angular tree queries `FileEntityRecordLink` at
runtime (`mj-files-grid` and `mj-files-file-upload` are category-scoped only).

**v1 already built the read half**: `packages/Angular/src/lib/panels/record-files.panel.ts` —
`RecordFilesPanelBase`, deliberately entity-agnostic ("donation-shaped": reads
`Record.EntityInfo.ID` + `Record.PrimaryKey`, knows nothing about contracts). It **survives the
rebuild**: re-register its thin subclasses for `Contracts` and `Contract Templates`, then finish it —
upload through MJ storage (`CreateFile` → pre-auth URL → link row), **register-an-existing-SharePoint-
object** (create the `File` row with `ProviderID` + `ProviderKey`, no bytes moved — the PandaDoc →
HubSpot → SharePoint reality), pre-auth download links gated by D-9, and `SigningProviderURL` as the
always-works fallback. Then offer it upstream to MJ.

Reading PDFs straight out of SharePoint needs an Azure app registration from IT. **That is deliberately
off the critical path** — finance can attach documents through platform storage meanwhile, and switching
to SharePoint later is configuration, not redesign. Details and the honest caveats:
[`mj-storage-and-esignature-notes.md`](./mj-storage-and-esignature-notes.md).

---

### 6.6 Caching — reference data loads once, not per form (D-18)

Four things are read constantly and change rarely: **contract types**, **template types**, **templates**, and
**provisions**. Without a cache the provision picker issues a `RunView` every time a row is added, and every
contract form re-reads the type lists to render two dropdowns.

So contracts ships a `BaseEngine` subclass — the pattern orders and accounting already use — configured with
those four entities and loaded once per session:

| Cached | Why it is safe to cache | Read by |
|---|---|---|
| `ContractType` | Lookup; changes when a business user adds a type | Every form, the list views, `RequiresExecutedDocument` |
| `ContractTemplateType` | Lookup | Template form |
| `ContractTemplate` | A handful of rows — one per MA version, ever | Contract form, the version registry |
| `ContractTemplateProvision` | Tens of rows per template, and immutable once a version is published | **The provision picker**, and the standard-text pane beside every modification |

Two rules that keep it honest: the engine is **read-through for reference data only** — never contracts,
never modifications, which are per-record and must come from the record's own collection; and the provision
picker filters the **cached** set by the contract's `ContractTemplateID` in memory rather than issuing a
scoped query, which is what makes §7.1's "provision must belong to a template this contract incorporates"
rule cheap to preflight in the browser.

---

## 7. The work

Fourteen pieces. The first four are the critical path; **the target is as soon as we can get there**,
with correct active-contract data in place before go-live. Every piece names what "done" means; the
copy-from pointers are orders `next` and MJ `next` file paths verified 2026-08-18.

**Ordering rule that gates all of it** (MJ CLAUDE.md): migration → `mj migrate` → **`mj sync push`
before `mj codegen`** — CodeGen reads JSONType-bearing metadata from the database, and running it
against stale rows silently deletes properties. And one database per agent, always.

### 1 · Retire v1; write the new baseline migration

The pre-production practice stands (`migrations/_README.md`): **edit the baseline in place and rebuild
from zero** — no stacked fix-ups until first publish. The rebuild deletes, in the same change:

| Where | What dies |
|---|---|
| `migrations/` | The 10-table v1 body of `B202608040001` — replaced by the 7-table schema (now incl. `ProvisionText`, excl. the modification's `ContractTemplateID`), its CHECKs (ERD §7.1), `ContractSequence` singleton (`CK … CHECK (ID = 1)` + seed row, orders' shape), and fresh CodeGen capture |
| `packages/Entities` | v1 generated classes (regenerated), `contract-draft.ts` |
| `packages/CoreEntitiesServer` | All 9 v1 `*EntityServer`s, `ContractsEngine`, `BillingDraft`, `ChildCollection`, all 7 operations — the billing engine wholesale |
| `packages/Server` | v1 generated resolvers (regenerated) |
| `packages/Angular` | v1 generated forms (regenerated), the v1 custom forms, billing worklist, workspace tabs. **Keep** `record-files.panel.ts` (re-registered) and the test conventions |
| `packages/IntegrationTests` | v1 bundles CC/SC/BE/AM (replaced — item 13) |
| `metadata/` | v1 contract-type seeds (new vocabulary in item 2), all 5 remote operations + category + their 10 type files (v2 has none — §6.3), the Billing nav item |
| `.changeset/` | The six v1-work changesets are rewritten to describe the rebuild (the mj6-pnpm and hide-schema-app ones stand) |

Baseline authoring rules that already bit once: hardcoded UUIDs never `NEWID()`; `MS_Description` on
every column (becomes entity-field descriptions); one ALTER per table; apply-time `MAX(Sequence)+1`
for any `EntityField` INSERT; **layered-view flags ship in the migration** (`BaseViewGenerated = 0`,
`GeneratedBaseViewName = 'vwContractsGenerated'`) *before* first CodeGen on a fresh environment, or
CodeGen DROP/CREATEs the public name and destroys the wrapper — orders documents the trap in
`V202608131541__…_layered_inner_view.sql`. T-SQL only; PG is the release toolchain's.

**Done when:** `mj migrate` from zero succeeds on a private DB (`bootstrap-clean-db` skill); v1 source
is gone; install-order note in `_README.md` says common only.

### 2 · Metadata: seeds, collection declarations, form chrome

All under `metadata/`, all name-keyed lookups, no hardcoded relationship UUIDs, **no SQL INSERTs**:

- **Seeds** (ERD §7): `ContractType` — Order Form · Statement of Work · Payment Link (`RequiresExecutedDocument: false`) · Change Order; `ContractTemplateType` — Master Agreement · Statement of Work.
- **Collection declarations** — `metadata/entity-relationships/.entity-relationships.json` +
  `modifications-collection.json` / `provisions-collection.json` blobs per §6.1. Copy orders'
  `metadata/entity-relationships/` layout and its `_comments` discipline.
- **Form chrome** — a `.form-chrome.json` with the §6.4 inclusion rows (Organization Primary
  "Agreements", Person More, the None list).
- **Application + nav** — rewrite `.contracts-application.json`: Contracts (list), Watchlist, Setup
  (templates + types). DriverClass names must exactly match `@RegisterClass(BaseResourceComponent, …)`
  registrations in `contracts-ng`.
- Fix `metadata/.mj-sync.json` `directoryOrder` — it lists only `schema-info` today; it must order all
  record folders (types before templates before provisions, relationships after entities exist).

**Done when:** `mj sync push` is clean on the fresh DB, then item 3's CodeGen emits the collections.

### 3 · CodeGen + entity packages

Run CodeGen after the push (ordering rule above). Then the hand-written classes, thin by design:

- `packages/Entities` (shared, browser + server — nothing server-only may leak in):
  `ContractEntity` — `Validate()` (HasModifications guard per §6.3), `NewRecord()` defaults
  (`Status = 'Draft'`), `Supersede()`, `static SectionForField()`. `ContractTemplateEntity` only if a
  rule earns it. **No `DeclareRelatedRecords` by hand — CodeGen emits them from item 2's metadata**
  ("edit that row, not this file").
- `packages/CoreEntitiesServer`: `ContractEntityServer` (CTR numbering per §6.3),
  `ContractTemplateModificationEntityServer` (flag-forcing + provision-template consistency).
- Verify the generated `remote_operations.ts` no longer re-exports other apps' operations (v1's
  PR2-Q10 CodeGen scoping leak) — if it still does, file it against MJ CodeGen rather than shipping.

**Done when:** all packages build; a unit test pins ClassFactory resolution per entity (orders'
`__tests__` pattern); vitest replaces the `echo "No tests configured yet"` stubs it touches.

### 4 · Seed the provision list — with its text (D-13)

A prerequisite, not a nicety: with the provision FK mandatory, finance cannot record a modification
until the clause list exists. Capture the current MA's numbered provisions **including each clause's
`ProvisionText`** from its dated URL into `metadata/` seeds (template row + provision rows, `@parent`
refs). Text is nullable so an incomplete capture never blocks listing the provisions — but the seed
should be complete.

**Done when:** a fresh install lists every MA provision with number, heading, text, in canonical order.

### 5 · Contract list and detail screens

The core surface. Detail = the **generated** Contract form + the §6.4 panels (hero, renewal block,
documents, lineage). List = a `BaseResourceComponent` page over `vwContracts` with the derived columns
(item 12's view), status/type/org filters, query-param round-trip. UI layering rules apply (L0–L3;
nothing below the surface package imports Router; design tokens only).

**Done when:** create → list → open → edit round-trips through Explorer, with `NotifyLoadComplete()`
and the golden-path harness green.

### 6 · Entity CRUD

Mostly free: generated forms already cover `ContractType`, `ContractTemplateType`, and the raw
`ContractTemplateModification` row (kept reachable for admin use even though the editor panel is the
real path). Confirm each generated form opens clean; add lookup-header panels only if the defaults
embarrass (orders' `lookup-headers.panels.ts` shape).

### 7 · Agreement version registry

`ContractTemplate` form + the Provisions editor panel bound to `template.Provisions` (§6.4). Register
each MA version by its dated `SourceURL`; provisions listed/edited in canonical order; one `Save()`
writes template + provisions.

**Done when:** finance can register the next MA version and its clause list without a developer.

### 8 · Modification capture

The modifications editor panel per §6.4 — picker filtered to the contract's template, `ProvisionText`
visible, flag flips in the same graph, one Save, whole-graph validation. This piece is the acceptance
test for D-15 itself: **no remote operation, no draft object, no second network call.**

**Done when:** recording N modifications is one transaction; clearing the flag while rows exist is
rejected in the browser before the round trip and by the server regardless.

### 9 · Document handling

Finish `RecordFilesPanelBase` per §6.5: upload, register-existing-SharePoint-object, pre-auth
download, D-9 gating, `SigningProviderURL` fallback. Wire the in-app PDF viewer for the executed
document. Offer the panel upstream to MJ once it settles.

**Done when:** finance attaches (or registers) the executed PDF and opens it in one click; a
non-privileged user sees the record but no download.

### 10 · Deal → Contract automation, with the finance task

Joint with the sales app, which supplies the Closed-Won trigger, the deal id, and the modified flag.
Contracts' side of the contract: rows arrive with `CreatingEntityID` (Deals) + `CreatingRecordID`,
`CustomerOrganizationID`, `ContractTypeID`, `HasModifications` as sales asserted it, `Status = 'Draft'`
— numbering and defaults are the server subclass's, automatically. Recommended sales-side shape:
`Deal.ContractID` as a hard FK declared **embedded** (`OnClear: 'orphan'`), so creation is
`deal.ContractID_EnsureObject()` + one `deal.Save()` (§6.2); the finance task rides the same flow.

**Done when:** Closed Won in sales yields a numbered Draft contract linked both ways, plus the task.

### 11 · Customer view

Every agreement and document for an organisation — delivered as §6.4's contributions on Common's
Organization (and Person) forms, not a new screen: inclusion metadata + the agreements panel with
`NewRecordValues` seeding, statuses and end dates in the grid. An org-scoped roster page only if the
form contribution proves insufficient.

### 12 · Renewal and expiry watchlist

Kept as a screen (ruled 2026-08-18), but deliberately thin: the **stock MJ grid** over the layered base
view, plus four default filter pills (next 120 days · notice window open · auto-renewing · all active) and
an advanced filter for everything else. **No saved views** — users drive filters in-session; persisting
custom watchlists is phase 2 or never (D-21). Uses MJ's own design tokens throughout, and the grid selects
the base view so customers and types show as names (D-23).

The layered base view (orders' `vwOrderHeaders` two-migration split): `vwContractsGenerated` inner +
hand-written `vwContracts` outer adding `IsAwaitingDocument` (`RequiresExecutedDocument` AND no
`FileEntityRecordLink` `EXISTS` — ERD §7.1), `IsChangeOrder`, `DaysToEnd`, `RenewalNoticeDeadline`
(`EndDate - RenewalNoticeDays`), `IsInCancellationWindow`. Each exposed as a virtual `EntityField`
(apply-time `MAX(Sequence)+1`), captured behind the wrapper in the migration train. Watchlist page
sorts by the deadline; the notice-period rule renders once (orders' `overdue.ts` single-statement
pattern: one predicate rendered into SQL and tests).

**Done when:** the watchlist answers "what must finance act on this quarter" from view columns alone.

### 13 · Migration of active contracts, test coverage and demo data

Gated on O-1. Demo/migration data loads **through the entity layer, never raw SQL** — v1's seed that
violated its own cap proved why (PR2-Q9). New integration bundles replace CC/SC/BE/AM:
`contracts-graph-save` (header+modifications atomicity, rollback on invalid, flag invariant),
`contracts-numbering` (CTR sequence under concurrency), `contracts-provisions` (seed completeness incl.
text, sequence renumbering), `contracts-watchlist` (derived columns). Update `testing.md`'s matrix to
the v2 schema — it still lists seven retired harnesses and three plans/ files that no longer exist.

### 14 · Rewrite the README

The README is 658 lines still specifying the v1 billing engine — it opens with *"this README is the
specification we are building to"*, and its own documentation table describes this plan as covering
*"the billing-event engine, the orders seams"*. The repo's front door should describe the
record-keeping app. **Last on the list deliberately**: a README should describe what shipped, so it is
written once against the real schema and screens rather than twice. (`docs/ERD.md` is regenerated from
`sys.tables` at the same moment — its banner already says so.)

**Done when:** nothing in the README or `docs/` asserts a capability the rebuild removed.

### The v1 question docs, absorbed

`PR2-QUESTIONS-DRAFT.md` and `docs/WORKFLOW-WALKTHROUGH.md` catalogued v1's open questions; both now
describe a retired UI and stay only as history. Their survivors, so nothing is lost: **status
vocabulary** — settled by ERD §4.5 (five statuses; Expired vs Terminated are distinct facts);
**termination reason's home** — `Notes` + Record Changes, no dedicated column (rule 3);
**seeds-through-entity-layer** — item 13; **the CodeGen remote-ops scoping leak** — item 3's check.
Everything about billing anchors, escalation clamps, renewal `AsOf`, `ContractLine → OrderLine`
mapping and the price resolver died with the billing engine.

---

## 8. Future phases

Recorded so they are not re-litigated. Full list in **§10 of the ERD**.

- **Per-product renewal-pricing override** from the contract — a child table keyed on contract +
  product (and, when it lands, a `Contract.RenewalPriceOverrides` collection — the pattern is already
  paid for). Today orders renews on then-current product pricing and finance reconciles by hand.
- **Deeper contract ↔ subscription integration**, so a renewal reads the agreement's escalation.
- **PandaDoc retrieval** through the MJ eSignature driver — scoped as *"spike the existing driver"*,
  not *"build an integration"*.
- **Versioned SOW templates**, as professional services scales.

*(F-3, `ProvisionText`, moved into v1 by D-13.)*

---

## 9. Build conventions

| | |
|---|---|
| Schema | `__mj_BizAppsContracts` |
| Entity prefix | `MJ_BizApps_Contracts:` |
| npm scope | `@mj-biz-apps/contracts-*` — `contracts-entities` (shared subclasses; nothing server-only), `contracts-core-entities-server` / `contracts-server`, `contracts-ng`, `contracts-actions`, `contracts-integration-tests` |
| Platform | T-SQL source of truth; PG via the release toolchain (`mj migrate convert`), never hand-authored |
| Migrations | **Pre-production:** edit the baseline in place and rebuild from zero rather than stacking fix-ups. Switch to additive-only at first publish |
| Seed data | Metadata sync (`metadata/`), never SQL `INSERT`s |
| Collections | Declared as `EntityRelationship.RelatedRecordCollection` **metadata**; CodeGen emits the typed accessor — never hand-write `DeclareRelatedRecords` for a schema relationship (D-15) |
| Ordering | migration → `mj migrate` → `mj sync push` → `mj codegen` → TypeScript. One database per agent |
| Server rules | Cross-row invariants on **shared** subclasses where the browser can preflight them; server subclasses stay authoritative and carry what needs SQL or secrets — §6.3 |
| Forms | Generated forms + `BaseFormPanel` contributions; full custom form only when a bespoke editor demands it (§6.4). Overlays via `ng-base-forms` shells, never bespoke dialogs |
| Derived values | Layered base views (`vwContracts` over `vwContractsGenerated`), orders' `IsOverdue` pattern — §7 item 12 |
| UI layering | L0→L3 per `MJ/guides/UI_LAYERING_GUIDE.md`; design tokens; `mjc-` selector prefix |
