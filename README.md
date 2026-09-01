<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://github.com/MemberJunction/MJ/raw/main/MJ_logo_dark.png">
    <source media="(prefers-color-scheme: light)" srcset="https://github.com/MemberJunction/MJ/raw/main/MJ_logo.webp">
    <img alt="MemberJunction" src="https://github.com/MemberJunction/MJ/raw/main/MJ_logo.webp" width="220">
  </picture>
</p>

<h1 align="center">BizApps Contracts</h1>

<p align="center">
  <strong>The record of what we agreed — the agreement, the standard terms it incorporates, the provisions negotiated away from those terms, and the executed paper — for the <a href="https://github.com/MemberJunction/MJ">MemberJunction</a> platform</strong>
</p>

<p align="center">
  <a href="#what-this-is-and-is-not">What this is</a> &middot;
  <a href="#the-seven-tables">The seven tables</a> &middot;
  <a href="#the-app">The app</a> &middot;
  <a href="#four-rules-the-schema-obeys">Four rules</a> &middot;
  <a href="#install">Install</a> &middot;
  <a href="#developing">Developing</a>
</p>

<p align="center">
  <img alt="Status" src="https://img.shields.io/badge/Status-Pre--release-orange?style=flat-square" />
  <img alt="MJ Version" src="https://img.shields.io/badge/MemberJunction-6.1%2B-blue?style=flat-square" />
  <img alt="Angular" src="https://img.shields.io/badge/Angular-21-DD0031?style=flat-square&logo=angular&logoColor=white" />
  <img alt="TypeScript" src="https://img.shields.io/badge/TypeScript-5.9-3178C6?style=flat-square&logo=typescript&logoColor=white" />
  <img alt="SQL Server" src="https://img.shields.io/badge/SQL%20Server-2019%2B-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white" />
</p>

---

## What this is, and is not

Contracts answers one question: **what did we agree, and where is the paper that proves it?**

It is a **tracking surface**, not an engine. It records obligations a document already states — the
dates, the renewal terms as written, which standard terms apply, and what this customer negotiated
away from them — and it holds the link to the executed document.

**It does not bill, and it does not price.** [bizapps-orders](https://github.com/MemberJunction/bizapps-orders)
does that. A number in this app is never a number about money owed. That boundary is the single most
important thing to understand about the design, because the previous version of this app crossed it:
it owned term structure, escalation, billing schedules and a billing engine, which meant two systems
had to agree about money. This version was rebuilt from a clean sheet to stop that.

| Question | Answered here? | Where instead |
|---|---|---|
| What did we agree, and when does it end? | **Yes** | — |
| Which standard terms apply, and what was negotiated away? | **Yes** | — |
| Where is the signed document? | **Yes** | — |
| Do we owe notice before this renews? | **Yes** — derived, on the watchlist | — |
| What do they owe us, and did they pay? | No | orders |
| What is this priced at? | No | orders |
| Who is selling this, and did it close? | No | a sales app (not yet built) |
| Who approves this contract? | No | a sales app — approval workflow lives with the deal |

---

## The seven tables

```
ContractTemplateType ──< ContractTemplate ──< ContractTemplateProvision
                                 │                        │
                                 │  (incorporates)        │  (deviates from)
                                 ▼                        ▼
        ContractType ──<     Contract     ──< ContractTemplateModification
                                 │
                                 ├──< Contract   (ParentContractID — change orders)
                                 └──< Contract   (SupersededByContractID — re-papering)

ContractSequence   singleton counter behind CTR-000001
```

| Table | What it is |
|---|---|
| **Contract** | The agreement. Counterparty organisation, which of our companies is party to it, the dates, the renewal terms *as the paper states them*, and lineage to what it amends or what replaced it |
| **ContractType** | Order Form · Statement of Work · Payment Link · Change Order. One column carries a rule: `RequiresExecutedDocument` |
| **ContractTemplate** | One **dated version** of a standard-terms document — a Master Agreement. Never edited in place: signed contracts reference it |
| **ContractTemplateProvision** | One numbered clause of one version, **with its text** |
| **ContractTemplateModification** | *This contract deviates from that provision, and here is the negotiated language.* The point of the app |
| **ContractTemplateType** | Master Agreement · Statement of Work |
| **ContractSequence** | The `CTR-` counter, taken under a lock inside the save that uses it |

**Both texts are stored and read as a pair** — the standard clause on the provision, the negotiated one
on the modification — so a reader sees what was agreed against what was offered without opening two
records.

### There is no `Status` column

Lifecycle is **derived** on an app-owned layered base view, because four of the five values a stored
status would hold are projections of the dates and the two self-FKs — and a stored copy of a
projection can only agree or lie.

`State` has six values, in strict precedence: `Terminated` · `Superseded` · `Expired` · `Active` ·
`Executed` · `Draft`. The sixth exists because the first cut of the derivation dropped
signed-but-not-yet-effective contracts into `Draft`, hiding every agreement signed weeks before its
term starts — the ordinary case in renewal season — behind the word for "unfinished". `Draft` is a
**task**; `Executed` is a **wait**.

The same view derives `IsAwaitingDocument` (the contract *type* expects paper and none is linked),
`IsChangeOrder`, `DaysToEnd`, `RenewalNoticeDeadline` and `IsInCancellationWindow`.

---

## The app

Three sections in MJ Explorer, each with a left rail:

| Section | Pages |
|---|---|
| **Contracts** | Dashboard · All contracts · Renewals & expiry · Awaiting documents · Modifications |
| **Templates** | Agreement versions · All provisions |
| **Configuration** | Contract types · Template types · Numbering |

Every grid is MJ's own `mj-explorer-entity-data-grid` over the **base view**, so foreign keys render
as names. Every worklist filter compares a *derived column* rather than re-deriving a date in
TypeScript — which is why the dashboard, the rail badges and the worklists cannot disagree.

The contract form is the **generated** form plus contributed panels — a hero, the renewal block, the
modifications editor, and lineage. Files on a contract (or a template version) are MJ's **standard
attachments**: the form toolbar opens `mj-record-attachments` for every entity unless
`Configuration.Attachments.Enabled` is `false`. Contracts does not turn that off, and does not ship
a second documents panel. Nothing replaces a generated form except the modification's own, so
CodeGen can regenerate freely.

### Recording a modification

The editor binds the contract's `Modifications` collection and **never saves**: the form's Save
toolbar drives one `contract.Save()`, so the header and its modifications land in one transaction or
not at all. The provision picker only offers clauses of the version this contract incorporates.

It is **one component with two hosts** — inline on the contract form, and as the body of the
modification's own form — because MJ cannot embed a child entity's form inside a parent's, and two
implementations of the same editor would drift.

### Attachments

MJ's standard attachments, not a contracts-owned documents feature. A paperclip on the record form
opens the stock attachments panel; files land in `__mj.File` and link through
`__mj.FileEntityRecordLink` (`EntityID` + `RecordID`). The same link table is what
`IsAwaitingDocument` reads: the contract *type* expects executed paper **and** no file is linked.

`SigningProviderURL` stays as the always-works fallback to the document in the signing provider
(PandaDoc) when storage is not configured yet, or when a sync has broken.

The **Awaiting documents** worklist is a filter on that derived flag. It is not a second file UI.

---

## Four rules the schema obeys

1. **Every reference is a real foreign key.** The one exception is the typed polymorphic pair
   (`CreatingEntityID` → `__mj.Entity` plus a soft `CreatingRecordID`), which is how a contract records
   that a deal created it without contracts depending on a sales app that does not exist yet.
2. **Derive, don't store,** anything a projection can produce — see `State` above.
3. **Audit is MJ's.** `TrackRecordChanges` is on; there are no hand-rolled history tables and no
   "reason" columns where `Notes` plus Record Changes already answer the question.
4. **Seed data goes through metadata sync,** never SQL `INSERT`s.

---

## Install

Dependencies, in order: **bizapps-common**, then this app. (`bizapps-tasks`, `bizapps-accounting` and
`bizapps-orders` are in the family but are not required by contracts.)

```bash
mj install MemberJunction/bizapps-contracts
```

The baseline migration applies to an empty database and produces an **installed app** — entities,
base views, CRUD procedures, permissions — not bare tables. Metadata sync then seeds the contract
types, the template types, and the Master Agreement's provision list.

---

## Developing

```bash
pnpm install
pnpm run build          # 6 packages, turbo
pnpm run test:unit      # vitest

# against a live instance
pnpm run mj:migrate     # mj migrate --schema __mj_BizAppsContracts --dir ./migrations
pnpm exec mj sync push --dir metadata
pnpm run mj:codegen
```

**Ordering matters:** migration → `mj migrate` → `mj sync push` → `mj codegen`. CodeGen reads
collection metadata *from the database*, so running it before the push silently emits no collection
accessors.

### Packages

| Package | Role |
|---|---|
| `contracts-entities` | Generated entity classes + the **shared** subclasses. Rules here run in both tiers |
| `contracts-core-entities-server` | Server-only rules — a lock, two cross-entity reads |
| `contracts-server` | Generated GraphQL resolvers |
| `contracts-ng` | Explorer sections, pages and form panels |
| `contracts-actions` | Action subclasses |
| `contracts-integration-tests` | Integration check bundles (private) |

### Where validation lives

A ladder, and a rule lands on the lowest rung that can hold it: **field rules** are generated;
**cross-record rules** go on the *shared* subclass so the browser preflights exactly what the server
enforces; **server-only rules** (locks, cross-entity reads) go in the server subclass's
`ValidateAsync()`, whose verdicts reach the UI through the save's attributed `ValidationResult`. A
remotable operation is justified only when the UI needs a server verdict *before* a save — and this
app ships **zero** of them.

### Documentation

| Document | What it covers |
|---|---|
| [`plans/bizapps-contracts-master.md`](plans/bizapps-contracts-master.md) | The plan: what the app is, decisions D-1…D-26, the fourteen work items |
| [`plans/ERD-planned.md`](plans/ERD-planned.md) | The schema in detail, plus §9's reversal log — every ruling that changed its shape, with owner and date |
| [`plans/BUILD-STATE.md`](plans/BUILD-STATE.md) | Build state, the working command loop, and the gotchas already paid for |
| [`docs/database-migrations.md`](docs/database-migrations.md) | Migration conventions: the train, filename ordering, the 50-blank-line capture separator, how to verify from zero |
| [`testing.md`](testing.md) | The coverage matrix, and an honest account of what is *not* covered |
| [`WORKAROUNDS.md`](WORKAROUNDS.md) | Tooling defects this build steps around |

---

<p align="center"><sub>Part of the MemberJunction BizApps family · <a href="LICENSE">ISC</a></sub></p>
