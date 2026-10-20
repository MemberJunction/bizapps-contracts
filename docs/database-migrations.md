# Database migrations

**Binding for this repo.** Skyway (Flyway-compatible) migrations for
`__mj_BizAppsContracts`, in `migrations/`, applied in filename order against this app's
schema at install/upgrade and during development.

The short version, if you read nothing else: **schema changes are new `V` migrations, never
edits to the baseline**; a migration runs once, in order, so it carries no idempotency guards; a
filename must sort after everything the target branch has already shipped; a migration that
changes a table's shape needs a CodeGen capture behind it or MJ cannot see the column; and MJ
metadata rows live in `metadata/`, never in migration SQL.

## Naming

    B<YYYYMMDDHHMM>__v<major>.<minor>.x__<Description>.sql    baseline (exactly one, sorts first)
    V<YYYYMMDDHHMM>__v<major>.<minor>.x__<Description>.sql    everything after

For example `V202609211200__v0.7.x__vwContracts_business_today.sql`.

- Timestamps must be strictly increasing. **Enforced by CI** (`changes.yml` compares every
  newly added migration against the highest timestamp already on the base branch) and by
  `packages/Entities/src/__tests__/migration-conventions.test.ts`, which also checks the name
  shape. Flyway applies in filename order, so a migration numbered behind one already applied is
  skipped silently on an existing database and applied in the wrong order on a fresh one.
- `${flyway:defaultSchema}` for THIS schema; `${mjSchema}` for MJ core (`mj.config.cjs`
  `SQLOutput.schemaPlaceholders` maps it to `__mj`).
- Do **not** add `__mj_CreatedAt` / `__mj_UpdatedAt` columns or FK indexes — CodeGen does.

## Writing a migration

- **Migrations run in order, exactly once**, so a script never defends itself against a database
  that already has its changes: no `IF NOT EXISTS`, no `IF COL_LENGTH(...) IS NULL`, no
  `sp_addextendedproperty` behind an existence check. Guards add noise and make the PostgreSQL
  conversion (`pnpm run mj:migrate:convert`) harder.
- **New columns on a table go in one `ALTER TABLE … ADD`**, with their constraints declared
  inline in that statement. `V202609140100` is the model.
- **A bad migration in a dev database is fixed by rebuilding that database** from zero, not by
  making the script re-runnable.
- **No MJ metadata rows.** Anything you would INSERT or UPDATE into an `__mj.*` configuration
  table (`EntitySetting`, `EntityField` settings, `FileCategory`, …) is declarative JSON in
  `metadata/`, applied by `mj sync push` (see [the authoring loop](#the-authoring-loop)).

Some applied files break these rules: `V202609010100` inserts a `FileCategory` row behind a
guard, and `V202609202354` guards its columns, constraint and descriptions. They are immutable;
do not copy them.

## The 50-blank-line rule (where hand-written DDL stops and CodeGen output starts)

**In any migration that carries both, exactly 50 empty lines separate the hand-written DDL from the
CodeGen capture.** The hand-written half ends with its `GO`; then 50 blank lines; then the CodeGen
banner comment and the generated SQL. A migration with no capture has no separator; a capture-only file
puts the separator below its header comment so the boundary is still findable.

It reads like formatting and is not. A capture is **replaced wholesale** on regeneration, so anyone
re-capturing needs an unambiguous mark for "everything below here is generated — delete it and paste the
new run." A banner comment cannot be that mark, because banner comments appear *inside* CodeGen output
dozens of times. Fifty consecutive blank lines appear nowhere else in a SQL file, which is exactly why
the number is absurd.

`migration-conventions.test.ts` (run by `pnpm run test:unit`) enforces it: a file containing CodeGen
output must have a longest blank run of exactly 50, and every other file less than 50. The files
carrying a capture today are the baseline, `V202608240100`, `V202609140100` and `V202609202354`.
`V202608240300` is entirely SQL-logger output and carries no separator. `bizapps-orders` is the
reference implementation — `V202608131541`, `V202608131542`, `V202607061432`.

## Baseline edits are CLOSED as of the 2026-08-23 flatten

Pre-publish practice was to **edit the baseline in place** and rebuild from zero, which is safe
only while no database anyone depends on has run it. The [flatten](#the-2026-08-23-flatten) was
the last exercise of that licence.

**From here the rule inverts, and the repo's `CLAUDE.md` states it as binding: schema changes are
new `V` migrations.** An edit to the baseline is invisible to any database that already ran it —
the column simply never appears, and nothing reports a problem — and Flyway checksums the script,
so every existing database refuses to migrate until someone repairs the history by hand.

## The authoring loop

Dev order is migrate, then push, then CodeGen. The push has to land before CodeGen runs, or
CodeGen regenerates without the settings it reads.

```bash
# write a new V migration and/or edit metadata/, then:
pnpm run mj:migrate                      # apply it
pnpm exec mj sync push --dir metadata    # apply metadata/ JSON to your database
pnpm run mj:codegen                      # regenerate entity metadata, SQL objects and code
# append CodeGen's SQL output (migrations/codegen/) below 50 blank lines and the banner
pnpm run change                          # minor changeset (changes.yml requires one with a migration)
```

A CodeGen capture is **not optional** whenever a migration changes the shape of a table. Its
absence is exactly what produced the three latent bugs the flatten fixed: the column exists in
SQL and MJ cannot see it, on every fresh install, silently.

A metadata change contributes only the JSON and a `minor` changeset. The `V…__Metadata_Sync.sql`
that delivers `metadata/` to hosts is generated at release time: the SQL logger's output from a
push against an empty database (`metadata/.mj-sync.json` → `sqlLogging`). MJ's
[Release Metadata Migrations Guide](https://github.com/MemberJunction/MJ/blob/next/guides/RELEASE_METADATA_MIGRATIONS_GUIDE.md)
covers the process; authoring syntax (`@lookup:`, `@file:`, …) is in MJ's
[MetadataSync README](https://github.com/MemberJunction/MJ/blob/next/packages/MetadataSync/README.md).

## An install runs migrations and NOTHING ELSE

It never runs CodeGen and never runs `mj sync push`, which is why both of their outputs ship as
migrations: CodeGen's as captures inside the schema migrations, `metadata/` as
`V…__Metadata_Sync.sql`. Skipping either produces a database that looks installed and isn't:
bare tables with no entity metadata, or entities with no vocabulary.

### What `metadata/` may contain — vocabulary, never one organisation's content

`metadata/` is the **install seed**: it ships inside `V…__Metadata_Sync.sql` and lands in every
consumer's database. So the test for anything added there is not "is it correct?" but "should
*everyone* receive it?"

- **`metadata/`, the install seed:** structural metadata and configuration (`entities`,
  `entity-fields`, `entity-relationships`, `entity-settings`, `applications`, `queries`,
  `query-categories`, `user-views`) and genuine vocabulary: contract types, template types.
  `schema-info` holds no records; the baseline registers the schema.
- **`demo-data/`, never shipped:** any particular organisation's records, *including their
  agreement text*. It holds invented organisations, contracts and modifications, the selling
  company they are written against, one real agreement, and the predictive-scoring bench
  (training pipeline, model versions, scoring record process and binding), and is pushed only on
  request (`pnpm run demo:load`).

**A KIND of contract is vocabulary; a particular company's AGREEMENT is content.** This was got
wrong once: `metadata/contract-templates/` and `metadata/contract-provisions/` carried one
company's actual Master Services Agreement — 71 verbatim provisions — so the published migration
seeded that company's contract terms into every install as reference data. They moved to
`demo-data/` on 2026-08-24. `plans/QUESTIONS.md` Q-5 (historical) records the ruling.

**A model is fitted to one organisation's data.** The ML models' fitted preprocessing and feature
importance are statistics from the dataset they were trained on, and a scheduled record process
against a model with no artifact fails every record it touches. So the predictive-scoring bench
lives in `demo-data/`, with its record process `Disabled` and its schedule off (issue #89).

### What a host has today

Three `Metadata_Sync` migrations ship:

- `V202608240300` carries `metadata/` as of 2026-08-24: contract types, template types,
  entity/field/relationship metadata and the application row.
- `V202610092210` carries what changed after it: the Contracts query category, the Contracts
  Special Terms query with its `CompanyIDs` parameter, the shared "Contracts: Watchlist" view, and
  entity, field and entity-setting changes (form sections, the Default Contract Terms category,
  display names, search flags).

- `V202610200101` carries the two records changed after `V202610092210` was captured: Statement
  of Work's `TemplateRequired: false`, and `ContractType.Code` with `ExtendedType` and `CodeType`
  cleared (issue #112). The contract-type seed codes needed no sync: `V202610122200` sets them.

Left out on purpose: the predictive-scoring
records (record process, training pipeline, models, scoring binding) live in `demo-data/` and are
never shipped (issue #89).

`rr: metadata shipped` (`ci/check-metadata-shipped.sh`) fails a release PR while any substantive
`metadata/` change since the last tag has no Metadata_Sync behind it. A feature PR may still merge
metadata first.

When generating a Metadata_Sync that carries a query, check its parameters. `metadata/`
deliberately does not declare the Special Terms query's `CompanyIDs` parameter row: the server's
query-extraction pipeline creates it during the push, and the capture picks it up only because SQL
logging records the server's writes as well as the sync's. `V202610092210` carries it (grep for
`spCreateQueryParameter`). Without it, the dashboard's "Clients with special terms" tile renders a
dash, because the parameter processor rejects an undeclared parameter.

## The train

| file | what it is |
| --- | --- |
| `B202608040001__…__Baseline.sql` | schema, `__mj.SchemaInfo`, the sequence, the sort-key function, all six tables + constraints, the two app-owned programmable objects, then the CodeGen capture |
| `V202608240100__…__Layered_base_view_flags.sql` | flips two entities to layered base views + the capture that re-points CodeGen to `vw*Generated` |
| `V202608240200__…__Layered_base_views_and_derived_fields.sql` | the two application-owned wrapper views + explicit registration of the 8 columns they add |
| `V202608240300__…__Metadata_Sync.sql` | `metadata/` as of 2026-08-24 (see above) |
| `V202608300100__…__Terminated_date_is_inclusive.sql` | `vwContracts` reads a contract as Terminated from its Terminated Date, not the day after |
| `V202609010100__…__IsAwaitingDocument_executed_agreement.sql` | seeds the `Executed Agreement` file category; `IsAwaitingDocument` clears only when a file in that category is linked |
| `V202609140100__…__Contract_type_renewal_defaults.sql` | four renewal-default columns on `ContractType`, copied onto a new contract when its type is picked, + capture |
| `V202609202354__…__Predictive_Contract_Renewal_Fields.sql` | prediction write-back columns on `Contract` and engineered feature columns in `vwContracts`, + capture |
| `V202609211200__…__vwContracts_business_today.sql` | `vwContracts` compares dates against the business day from bizapps-common's `fnBusinessToday()` instead of the UTC day; restores the executed-agreement rule `V202609202354` dropped |
| `V202610092200__…__Risk_band_value_list.sql` | the `PredictedRenewalRiskBand` value list (Low, Medium, High, Critical) CodeGen derives from its check constraint; capture only, no schema change |
| `V202610092210__…__Metadata_Sync.sql` | `metadata/` changes since `V202608240300` (see above) |
| `V202610121200__…__Provision_guard_throws_without_rollback.sql` | the published-provision guard trigger refuses with `THROW` alone, so MJ's save and delete see the rule instead of error 3915 |
| `V202610122200__…__ContractType_Code.sql` | a required, unique `Code` on `ContractType`, set by ID for the shipped types, + capture |
| `V202610200101__…__Metadata_Sync.sql` | the two `metadata/` records changed after `V202610092210` (see above) |

**Why `V202608240100`–`0300` were not folded into the baseline.** The
[flatten](#the-2026-08-23-flatten) folded in everything it could; these three are a genuine
sequence:

1. The layered-view flags live on `__mj.Entity` rows that **do not exist** until the
   baseline's own capture inserts them, so the flags cannot be in the baseline.
2. A wrapper view cannot be created before the view it selects `FROM` — SQL Server has
   deferred name resolution for procedure bodies but **not** for views — so the wrappers
   cannot share a file with the flags.
3. Seed data has to follow the schema and the metadata it references.

## Install-order dependency

`mj-app.json` declares two app dependencies:

| app | range | why |
| --- | --- | --- |
| `mj-bizapps-common` | `>=5.42.0 <6.0.0` | the baseline's FKs to `__mj_BizAppsCommon.Organization` and `__mj_BizAppsCommon.Person`; `V202609211200` reads `[__mj_BizAppsCommon].[fnBusinessToday]()` |
| `mj-bizapps-tasks` | `>=1.4.0 <2.0.0` | the dashboard's "To process" tile and the "Has open task" pill read Tasks views at runtime; no migration references Tasks |

`fnBusinessToday()` first shipped in bizapps-common **5.43.0** (its
`V202609160900__v5.43.x__Business_Time_Zone` migration). The manifest's floor, 5.42.0, admits a
release without it; on such a database `V202609211200` fails with a message naming the missing
function. Apply bizapps-common 5.43.0 or later first.

Beyond those, the migrations touch only MJ core (`__mj.Company`, `__mj.Entity`, …). A clean host
carrying MJ core + bizapps-common 5.43.0 or later is enough to apply this whole train, which is
how it is verified.

## Cross-app reference hardness

References into an upstream app are **hard, nullable FKs** — not soft UUID columns. Apps install
in dependency order, so the target table exists when the FK is created, and MJ's Open App no-break
policy (`packages/OpenApp/PUBLISH_NO_BREAK_POLICY.md`) is written for cross-app FKs.

Every reference is a real FK. There are no soft keys. The one exception is a polymorphic
EntityID/RecordID pair, whose target table is not known ahead of time: the EntityID half has an FK
to `__mj.Entity`, and the RecordID half cannot have one. Here that is `CreatingEntityID`/
`CreatingRecordID` on `Contract`, the same shape as `__mj.TagLink`'s TargetEntityID/TargetRecordID.

## Verification

The train is proven **from zero**, not by inspection. The method, which any change to
these files must repeat:

1. Build a clean host — an empty database with MJ core + bizapps-common (5.43.0 or later)
   migrated into it, and nothing else.
2. Apply the migrations with `pnpm run mj:migrate`.
3. Compare against a from-zero replay of the previous train, object-by-object: columns
   with types/nullability/defaults, CHECK constraints, indexes with their filters,
   sequences, and every view/procedure/function/trigger; then the `__mj.Entity` and
   `__mj.EntityField` rows. `mj baseline compare --left <a> --right <b> --fail-on-diff`
   is the shipped MJ command if you want it whole-database rather than schema-scoped.
4. Prove the seed independently: apply the migrations to a second clean database, and
   diff its seeded rows against a database seeded by a real `mj sync push`.

**Do not verify by re-reading the SQL.** The flatten's one real error — `SourceURL`
silently reverting to `NOT NULL` — was invisible on inspection and caught immediately by
step 3, because the `ALTER COLUMN` that relaxed it was buried inside an `IF EXISTS` block
in a migration whose filename was about something else entirely.

## History

### The 2026-08-23 flatten

Pre-publish practice was to edit the baseline in place; that slipped, and 22 incremental files
accumulated. On 2026-08-23, immediately before the first publish, they were folded back into the
baseline. That removed real garbage rather than merely tidying: a `DEFAULT` added and reverted
one file later (MJ#4000), a filtered unique index replaced by a plain one, a
`ParentStatusRequirement` column added and then dropped for the `MustBeRoot`/`MustBeChild` flags
that replaced it, a `ContractSequence` counter table created and then retired for a real
`SEQUENCE`, three successive versions of one trigger, and two migrations patching
`__mj.UserSetting` grid layouts that do not exist on a fresh install.

It also **fixed three latent bugs**, all the same shape — a column added by `ALTER TABLE`
with no CodeGen capture behind it, so a fresh install got a column MJ could not see.
`ContractTemplate.Status`, `ContractTemplateProvision.ProvisionSortKey`, and
`ContractType.MustBeRoot`/`MustBeChild`/`TemplateRequired` were all invisible to MJ on a
from-zero install of the old train. They are registered now because their columns are
part of `CREATE TABLE`, which the baseline's capture sees.

Two CodeGen artifacts were **deliberately dropped**: `fnContractParentContractID_GetRootID`
and `fnContractSupersededByContractID_GetRootID`, with their `Root*ID` metadata rows.
Current CodeGen no longer generates them; the old train only had them because its captures
were frozen output from an earlier version. Nothing reads them, which settled the open question
in `plans/backend-requirements.md` (historical) in favour of deleting the metadata rows.

Verified from zero (MSSQL, MJ `6.1.0-edge.2`): **161 schema objects, zero differences** against
the previous train except the two intentionally-dropped root-ID functions; **79 seed rows
identical including every UUID**; `mj sync push` after migrating reported `created: 0`.

### Why the first three V files are numbered Aug 24, not Aug 4

They were originally `V202608040002`-`0004`, chosen to sit immediately after the baseline so
the four files read as one sequence. **CI rejected that, correctly.** `changes.yml` compares
every newly added migration against the highest timestamp already on the base branch, and
`next` carried migrations up to `V202608192200` — so a file numbered Aug 4 sorts *behind*
migrations an existing database has already applied. Flyway applies in filename order, so such
a file is skipped silently on that database and applied in the wrong order on a fresh one.

The rule is that a migration filename must be monotonic against **everything the target branch
has ever shipped**, not just against its own train. Grouping numerically with the baseline is
cosmetic; ordering is not.

### A database built from the pre-flatten train cannot migrate onto this one

The baseline's contents changed, so its Flyway checksum changed, and any database that already
applied the old `B202608040001` refuses to migrate — reporting a checksum mismatch on a file it
has no way to reconcile. The 22 collapsed V files are also gone from disk while their history
rows remain. Such a database is rebuilt from zero. There is no supported upgrade path from the
old train, and there did not need to be: nothing had shipped.

### Earlier dependency rules

The install-order dependency once read "`bizapps-common`, `bizapps-accounting` and
`bizapps-orders` must be installed first", with a `ContractAmendment.ApprovalTaskID` soft
reference. Neither was true of the flattened schema: there is no `ContractAmendment` table (the
v2 rebuild replaced it with `ParentContractID` on `Contract` itself), no soft reference, and no
FK into accounting, orders or tasks. An earlier rule also kept cross-app references soft until
CodeGen had an include mode; it was withdrawn on 2026-08-03 in favour of hard FKs.
