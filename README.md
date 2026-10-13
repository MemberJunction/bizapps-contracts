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
  <a href="#the-six-tables">The six tables</a> &middot;
  <a href="#the-app">The app</a> &middot;
  <a href="#predicted-renewal-risk">Renewal risk</a> &middot;
  <a href="#four-rules-the-schema-obeys">Four rules</a> &middot;
  <a href="#install">Install</a> &middot;
  <a href="#developing">Developing</a>
</p>

<p align="center">
  <img alt="Status" src="https://img.shields.io/badge/Status-Pre--release-orange?style=flat-square" />
  <img alt="MJ Version" src="https://img.shields.io/badge/MemberJunction-%3E%3D6.1.5%20%3C7.0.0-blue?style=flat-square" />
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
| Who is selling this, and did it close? | No | [bizapps-sales](https://github.com/MemberJunction/bizapps-sales) |
| Who approves this contract? | No | bizapps-sales — approval lives with the deal |

---

## The six tables

```
ContractTemplateType ──< ContractTemplate ──< ContractTemplateProvision
                                 │                        │
                                 │  (incorporates)        │  (deviates from)
                                 ▼                        ▼
        ContractType ──<     Contract     ──< ContractTemplateModification
                                 │
                                 ├──< Contract   (ParentContractID — change orders)
                                 └──< Contract   (SupersededByContractID — re-papering)

seq_ContractNumber   SQL sequence behind CTR-000001 (not a table)
```

| Table | What it is |
|---|---|
| **Contract** | The agreement. Counterparty organisation, which of our companies is party to it, the dates, the renewal terms *as the paper states them*, lineage to what it amends or what replaced it, and a [renewal-risk prediction](#predicted-renewal-risk) |
| **ContractType** | Order Form · Statement of Work · Payment Link · Change Order. Carries rules — `RequiresExecutedDocument`, `MustBeRoot` / `MustBeChild` (where in the tree a contract may sit), `TemplateRequired` — and four renewal defaults that pre-fill a new contract. The form applies them; code that creates a contract calls `SeedRenewalDefaultsFromType()` itself (see its JSDoc for the order) |
| **ContractTemplate** | One **dated version** of a standard-terms document — a Master Agreement. Never edited in place: signed contracts reference it |
| **ContractTemplateProvision** | One numbered clause of one version, **with its text** |
| **ContractTemplateModification** | *This contract deviates from that provision, and here is the negotiated language.* The point of the app |
| **ContractTemplateType** | Master Agreement · Statement of Work |

`CTR-` numbers come from the SQL sequence `seq_ContractNumber` through `spAssignNextContractNumber`,
called when a new contract is saved without a number.

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

The same view derives `IsAwaitingDocument` (the contract *type* expects paper and no linked file is
marked as the executed agreement), `DaysToEnd`, `RenewalNoticeDeadline` and `IsInCancellationWindow`,
plus the renewal-risk model's label and features: `NonRenewalOutcome`, `TermLengthDays`,
`DaysUntilNoticeDeadline`, `HasModificationsFlag`, `AutoRenewFlag`, `HasParentContract`,
`HasCancellationWindow` and `HasAnnualIncrease`. "Today" in these columns is the **business day** from
bizapps-common's `fnBusinessToday()`, not the server's UTC date. Definitions:
[`docs/ERD.md`](docs/ERD.md) §4.

---

## The app

Three sections in MJ Explorer, each with a left rail:

| Section | Pages |
|---|---|
| **Contracts** | Dashboard · All contracts · Renewals & expiry · Awaiting documents · Modifications |
| **Templates** | All templates · All provisions |
| **Configuration** | Contract types · Template types |

Every grid is MJ's own `mj-explorer-entity-data-grid` over the **base view**, so foreign keys render
as names. Every worklist filter compares a *derived column* rather than re-deriving a date in
TypeScript — which is why the dashboard, the rail badges and the worklists cannot disagree.

All six entity forms are the **generated** ones and nothing replaces them, so CodeGen can regenerate
freely. The contract form adds contributed panels: a hero above the sections, then Overview,
Agreement, Parties, Dates, Renewal terms, Notes, Provenance, Change orders, Re-papering, Executed
agreement, Modifications and Lineage. Contracts also adds an **Agreements** panel to bizapps-common's
Organization and Person forms.

### Recording a modification

The contract form's **Modifications** panel is MJ's stock related-entity grid, scoped to the contract
and shown once the contract is saved. A new row opens the generated modification form with the
contract filled in: pick the provision, write the negotiated text. The **Modifications** page under
Contracts lists every modification across contracts, with the most-modified provisions as filters.

The rules:

- **The text is required.** `ModificationText` is `NOT NULL` and must not be blank. The shared
  subclass replaces MJ's "cannot be null" messages with ones that say what to do.
- **The provision must belong to the contract's tree.** Its template must be the contract's own or one
  above it through `ParentContractID`, so a modification on a change order can cite the parent's
  template. A contract with no template anywhere in its ancestry is exempt. Server-side
  (`ContractTemplateModificationEntityServer`).
- **One modification per provision per contract.** The server refuses a second one with a message;
  `UQ_ContractTemplateModification_Contract_Provision` is the floor underneath.
- **`HasModifications` never trails the rows.** Saving a modification sets its contract's flag,
  through the contract entity so Record Changes logs it, and the flag cannot be cleared while
  modifications exist.

An API caller can also save a contract together with staged `Modifications` in one graph save;
duplicate provisions among the staged rows are refused before anything is written.

### Attachments and the executed agreement

Files use MJ's **standard attachments**, not a contracts-owned documents feature. On a saved record
the form toolbar's Attachments button opens the stock panel; files land in `__mj.File` and link
through `__mj.FileEntityRecordLink` (`EntityID` + `RecordID`). That button shows for every entity
unless `Configuration.Attachments.Enabled` is `false`, and Contracts does not turn it off.

`IsAwaitingDocument` reads the same links, but only a file in the file category named **Executed
Agreement** clears it — attaching an exhibit or a draft does not. `V202609010100` seeds the category.
The stock panel cannot set a file's category, so the contract form has an **Executed agreement**
panel: it lists the contract's linked files and marks or unmarks one as the executed agreement,
which sets or clears that file's category. It works on a saved contract outside edit mode, and
marking needs update permission on `MJ: Files`.

`SigningProviderURL` stays as the always-works fallback to the document in the signing provider
(PandaDoc) when storage is not configured yet, or when a sync has broken.

The **Awaiting documents** worklist is a filter on that derived flag. It is not a second file UI.

---

## Predicted renewal risk

`V202609202354` added three nullable columns to `Contract` for a non-renewal prediction:

| Column | Holds |
|---|---|
| `PredictedNonRenewalRisk` | The predicted probability, `0` to `1`, that the agreement does not renew |
| `PredictedRenewalRiskBand` | `Low` · `Medium` · `High` · `Critical` (`CK_Contract_PredictedRenewalRiskBand`). The column description sets the bands at under 20%, 20–50%, 50–80% and 80% or more |
| `PredictedRenewalScoredAt` | When the contract was last scored |

No code in this repo writes them. MJ Predictive Studio records in `demo-data/` (opt-in, never shipped) are set up to:

- **Train** — `ml-training-pipelines/` holds the classification pipeline "Predict Contract Non-Renewal
  Risk" over Contracts, and `ml-models/` three model versions from it. The label is `NonRenewalOutcome`;
  the models' features are the seven other engineered columns plus `AnnualIncreasePercent`,
  `CancellationWindowDays`, `RenewalNoticeDays` and `ContractType`. `State`, `EndDate`,
  `TerminatedDate` and the supersession columns are denied as leakage.
- **Score** — `record-processes/` and `ml-model-scoring-bindings/` hold a record process that, once
  enabled, scores contracts whose outcome is still open (`NonRenewalOutcome IS NULL`) on the 1st of
  each month (UTC) or on demand, mapping the scorer's `score`, `band` and `scoredAt` to the three
  columns. It is pushed `Disabled` with its schedule off; enable it only after training a model with
  an artifact (a run against a model with none fails every contract, MemberJunction/MJ#4829).

The label and features are derived columns on `vwContracts` ([`docs/ERD.md`](docs/ERD.md) §4). The
pipeline and its models are in `Draft` status. None of it ships to hosts (issue #89): the models'
fitted preprocessing and feature importance come from one dataset, and they carry no trained artifact.
A host installed from migrations has the columns, and each organisation trains and schedules its own
model.

---

## Four rules the schema obeys

1. **Every reference is a real foreign key.** The one exception is the typed polymorphic pair
   (`CreatingEntityID` → `__mj.Entity` plus a soft `CreatingRecordID`), which is how a contract records
   that a bizapps-sales deal created it without contracts depending on bizapps-sales.
2. **Derive, don't store,** anything a projection can produce — see `State` above.
3. **Audit is MJ's.** `TrackRecordChanges` is on; there are no hand-rolled history tables and no
   "reason" columns where `Notes` plus Record Changes already answer the question.
4. **MJ metadata rows live in `metadata/`,** as JSON applied by `mj sync push` — never as SQL
   `INSERT`/`UPDATE` in a migration. Hosts receive them through the `V…__Metadata_Sync.sql` generated
   at release. Entity and field registration, which CodeGen owns, ships in migrations because an
   install never runs CodeGen. One shipped migration breaks the rule and stays, because a shipped
   migration does not change: `V202609010100` inserts the `Executed Agreement` file category with SQL.

---

## Install

`mj-app.json` declares MemberJunction `>=6.1.5 <7.0.0` and two other BizApps:

| App | Range | What contracts uses |
|---|---|---|
| [bizapps-common](https://github.com/MemberJunction/bizapps-common) | `>=5.42.0 <6.0.0` | `Organization` and `Person` (foreign keys from `Contract`), and `fnBusinessToday()` |
| [bizapps-tasks](https://github.com/MemberJunction/bizapps-tasks) | `>=1.4.0 <2.0.0` | Tasks, read by the dashboard's open-task tiles and the "Has open task" filter |

`V202609211200` stops unless `[__mj_BizAppsCommon].[fnBusinessToday]()` exists, and bizapps-common
ships that function from **5.43.0**. A host on bizapps-common 5.42.x upgrades it first.

```bash
mj app install https://github.com/MemberJunction/bizapps-contracts --dangerously-ignore-dbl-underscore-schema-rule
```

`mj app install` takes the repository URL and installs missing dependencies first, at the highest
release within each range. The flag is needed because the installer refuses to create a schema whose
name starts with `__`, a prefix reserved for MemberJunction's own schemas, and this app's schema is
`__mj_BizAppsContracts`.

On the database side an install applies `migrations/` and nothing else — no CodeGen, no
`mj sync push`. The migrations produce an **installed app** — entities, base views, CRUD procedures,
permissions — not bare tables. `V202608240300__…__Metadata_Sync.sql` seeds the four contract types,
the two template types, entity, field and relationship metadata, and the Contracts application row. No
template or provision is seeded: those are demo data, loaded only by `pnpm run demo:load` from
`demo-data/`. [`docs/database-migrations.md`](docs/database-migrations.md) explains what `metadata/`
holds and what `demo-data/` holds.

**Before the first Order Form or Payment Link, publish a template.** Both types require the contract to
reference the agreement version it incorporates, and a new contract takes the newest Published
template that has a document or source URL. With none, every save of those types is refused, including
contracts other apps create, such as bizapps-sales at Closed Won. Create the template under
**Templates**, attach the document or record its URL, and set it to Published. For a demo database,
`pnpm run demo:load` loads a published one.

Metadata added to `metadata/` after that migration — the dashboard's special-terms query, the
watchlist view, entity settings and the renewal-risk ML rows — reaches a host only when a release
regenerates the metadata-sync migration. Issue #80 tracks it.

---

## Developing

### Setup

**Prerequisites:** Node.js 18 or later (`engines`; CI uses 24) · pnpm 10.33.0 (`packageManager`) ·
SQL Server with MemberJunction `>=6.1.5 <7.0.0`, then bizapps-common (5.43.0 or later, below 6.0.0)
and bizapps-tasks `>=1.4.0 <2.0.0` migrated into the same database.

**Configuration.** Connection settings come from a gitignored `.env`, never from `mj.config.cjs`:

| Variable | Read by |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_DATABASE` | the `mj` CLI and the test harnesses |
| `CODEGEN_DB_USERNAME`, `CODEGEN_DB_PASSWORD` | `mj migrate`, `mj codegen` |
| `DB_USERNAME`, `DB_PASSWORD` | `mj sync push`, the test harnesses |
| `AI_VENDOR_API_KEY__GeminiLLM` or `AI_VENDOR_API_KEY__OpenRouterLLM` | `mj codegen`, which without one drops AI-written validators, display names, descriptions and form layouts |

The `mj` CLI loads `.env` from the current directory; the test harnesses walk up from
`test-harnesses/` to the first `.env` or `mj/.env`. `mj.config.cjs` holds what is specific to this
repo: the entity package name, CodeGen's output folders, the schema scope
(`includeSchemas: ['__mj_BizAppsContracts']`), the `MJ_BizApps_Contracts: ` entity-name prefix, the
integration-check module `mj test` loads, and the folder CodeGen logs its SQL to
(`migrations/codegen/`).

**Inside an MJ workspace.** In an MJ 6.x dev instance this repo sits beside `mj/` in a parent pnpm
workspace that links MemberJunction from source ([`CLAUDE.md`](CLAUDE.md)). Then:

- The instance's `.env` is `../mj/.env`. The harnesses find it; for the CLI, prefix the command with
  `DOTENV_CONFIG_PATH=../mj/.env`, as [`demo-data/README.md`](demo-data/README.md) shows.
- The parent workspace does not install this repo's root devDependencies, so run vitest through
  `packages/Angular` ([`testing.md`](testing.md)).
- mjdev manages parts of the `package.json` files that carry an `mjdevManaged` note; leave those parts
  alone.
- Linked MJ hides packaging problems, so check a release from a standalone clone, as `CLAUDE.md`
  describes.

### Build, migrate, generate

```bash
pnpm install
pnpm run build          # 6 packages, turbo
pnpm run test:unit      # vitest

# against a database
pnpm run mj:migrate     # mj migrate --schema __mj_BizAppsContracts --dir ./migrations
pnpm exec mj sync push --dir metadata
pnpm run mj:codegen
pnpm run demo:load      # optional: demo template, provisions and contracts from demo-data/
```

**Ordering matters:** migration → `mj migrate` → `mj sync push` → `mj codegen`. CodeGen reads
collection metadata *from the database*, so running it before the push silently emits no collection
accessors.

### Tests

| Command | What it runs |
|---|---|
| `pnpm run test:unit` | vitest over `packages/*/src/**/*.test.ts`; no database |
| `pnpm run test:state` | `State` and `NonRenewalOutcome` fixtures against the view |
| `pnpm run test:integration` | the integration check bundles, through MJ's testing framework |
| `pnpm run test:parent-rule` | `MustBeRoot` / `MustBeChild` enforcement through real saves |
| `npx tsx test-harnesses/erd-schema-diff.ts` | `docs/ERD.md` against the live schema |

[`testing.md`](testing.md) has the coverage matrix and the gaps. Run `mj test` with this repo's
`pnpm exec mj`, not a global install, which cannot see the private integration-test package.

### Releasing

`next` is the integration branch and `main` the release branch; a push to `main` publishes to npm.
A change to be released carries a changeset (`pnpm run change`); a PR that adds a migration needs at
least `minor`, and CI checks it. The branch model and release steps are in
[`branching.md`](docs/template-docs/branching.md) and [`publishing.md`](docs/template-docs/publishing.md).

### Packages

| Package | Role |
|---|---|
| `contracts-entities` | Generated entity classes + the **shared** subclasses. Rules here run in both tiers |
| `contracts-core-entities-server` | Server-only rules: contract numbering, rules that read other records (tree placement, templates, lineage, supersession, duplicate modifications), delete guards, and the `Contracts.Supersede` remote operation |
| `contracts-server` | Server bootstrap: generated GraphQL resolvers; loads the server subclasses and actions |
| `contracts-ng` | Generated forms, plus Explorer sections, pages and form panels |
| `contracts-actions` | Action package; holds no actions yet |
| `contracts-integration-tests` | Integration check bundles (private) |

### Where validation lives

A ladder, and a rule lands on the lowest rung that can hold it: **field rules** are generated;
**cross-record rules** go on the *shared* subclass so the browser preflights exactly what the server
enforces; **server-only rules** (reads of other records) go in the server subclass's `ValidateAsync()`,
whose verdicts reach the UI through the save's attributed `ValidationResult`. The app ships **one**
remote operation, `Contracts.Supersede`: re-papering writes the predecessor contract from the
successor's form, so the write runs on the server, where `ContractEntityServer`'s rules fire. It has
no `MJ: Remote Operations` metadata row; the server resolves it by key from the class factory, and the
Re-papering panel calls it through `RouteOperation`.

### Documentation

| Document | What it covers |
|---|---|
| [`docs/ERD.md`](docs/ERD.md) | The schema as built: columns, keys, constraints, derived columns |
| [`docs/database-migrations.md`](docs/database-migrations.md) | Migration conventions, what `metadata/` and `demo-data/` hold, how to verify from zero |
| [`docs/ui-architecture.md`](docs/ui-architecture.md) | UI and data-access rules: components use entities, `RunView`, `RunQuery` and remote operations directly; no data-access service layer |
| [`docs/claude/`](docs/claude/README.md) | MemberJunction's development rules, adapted for this app and split by topic |
| [`testing.md`](testing.md) | The coverage matrix, how to run each tier, and what is not covered |
| [`demo-data/README.md`](demo-data/README.md) | The opt-in demo records and how to load them |
| [`packages/IntegrationTests/README.md`](packages/IntegrationTests/README.md) | How `mj test` finds this app's integration check bundles |
| [`plans/WORKAROUNDS.md`](plans/WORKAROUNDS.md) | Workarounds for gaps outside this app's code, and how to remove each |
| [`docs/template-docs/branching.md`](docs/template-docs/branching.md), [`publishing.md`](docs/template-docs/publishing.md) | Branch model and release pipeline |
| [`plans/`](plans/) — **historical** | The build-time plan, the planned ERD with its reversal log, and build notes. Not kept current |

---

<p align="center"><sub>Part of the MemberJunction BizApps family · <a href="LICENSE">BUSL-1.1</a></sub></p>
