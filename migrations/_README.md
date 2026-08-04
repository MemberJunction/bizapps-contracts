# migrations/ — Skyway (Flyway-compatible) migrations for `__mj_BizAppsContracts`

Applied in filename order against this app's schema at install/upgrade and during
development.

## Naming

    B<YYYYMMDDHHMM>__v<app-version>__<Description>.sql    baseline (first schema drop of a new app)
    V<YYYYMMDDHHMM>__v<app-version>__<Description>.sql    everything after

- Timestamps must be strictly increasing. **Not enforced by CI.** Flyway applies in filename
  order, so a migration numbered behind one already applied is skipped silently on an existing
  database and applied in the wrong order on a fresh one.
- Use `${flyway:defaultSchema}` for THIS schema; literal `__mj` for MJ core rows.
- Do **not** add `__mj_CreatedAt` / `__mj_UpdatedAt` columns or FK indexes — CodeGen does.

## Why the baseline is two files

`B…__Schema_and_Types.sql` commits the schema, the `__mj.SchemaInfo` registration and any
user-defined table types. `V…__Tables_and_Objects.sql` carries everything else.

Migrations run as **one transaction per file**. A trigger declaring a variable of a
user-defined table type cannot be compiled inside the transaction that created the type —
SQL Server needs a schema lock the creating transaction still holds, and it dies with
`Msg 1205 … deadlocked with another process` on a single-connection run. That reads as server
instability rather than an ordering bug. Merging the two files back re-creates it.

This app declares no table types *yet*; the split exists so the first rollup trigger does not
require restructuring an already-applied baseline.

## Standing pre-production practice

While nothing is deployed, schema changes **edit the original baseline in place** and rebuild
on a clean database — no incremental fix-up migrations. This is only safe because rebuilding
from zero is routine. **Switch to additive-only at first publish**, after which an applied
migration is immutable.

The authoring loop:

```bash
scripts/rebuild-db.sh                      # drop → MJ core → common → accounting → orders → contracts
npm run mj:codegen                         # regenerate entity metadata + SQL objects
scripts/append-codegen.sh                  # fold that output BELOW the migration's banner
npm run mj -- sync push --dir metadata     # seed ContractType et al.
```

`append-codegen.sh` is **not optional**. The generated half of the baseline — entity/field
metadata, base views, CRUD procedures, permissions — is what makes a fresh `mj migrate` produce
a *working* database rather than bare tables. Skipping it after a CodeGen run silently discards it.

## Install-order dependency

`bizapps-common`, `bizapps-accounting` and `bizapps-orders` **must** be installed first. The
cross-app foreign keys in §4.A are the dependency check: applying this baseline without them
fails there, deliberately, rather than producing a schema that looks installed and dangles.

`bizapps-tasks` is a required dependency of this app but is **not yet in the chain**, which is
why `ContractAmendment.ApprovalTaskID` is the one soft reference. See §4.B for the TODO that
closes it.

## Cross-app reference hardness

References into an upstream app are **hard, nullable FKs** — not soft UUID columns. Dependency-order
install makes them safe and MJ's OpenApp publish policy expects them. The earlier
soft-ref-until-CodeGen-include-mode ruling was withdrawn (Amith, 2026-08-03); see
`bizapps-orders` PR #29.

A reference is soft **only** when the target app is genuinely absent from the chain — never as a
workaround for a tooling defect.

## Verification

The baseline has been applied inside a transaction against a database carrying the full
dependency chain and rolled back: **10 tables, 25 foreign keys, every cross-app target resolved.**
Re-run that check after any edit:

```bash
# concatenate both files between BEGIN TRANSACTION / ROLLBACK TRANSACTION and run with
# sqlcmd -b against a DB that already has __mj + common + accounting + orders
```
