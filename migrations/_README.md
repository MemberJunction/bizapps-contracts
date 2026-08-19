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

## Why the baseline is ONE file

`B…__Baseline.sql` carries everything: the schema, the `__mj.SchemaInfo` registration, all seven
tables and their constraints, and the CodeGen output. Applying it to an empty database produces an
**installed app**, not bare tables — `mj sync push` then seeds the reference vocabulary.

It used to be two files (`…__Schema_and_Types` + `…__Tables_and_Objects`), split following
bizapps-orders so a user-defined table type would be COMMITTED before any trigger declaring a
variable of it was compiled. **That hazard is real but this app does not have it — it declares no
table types.** Carrying a second file for a problem we do not have cost a reader one more hop and
bought nothing.

**If this app ever adds a table type, split it back out**, and read this first:

> A trigger declaring a variable of a user-defined table type cannot be compiled inside the
> transaction that created the type — SQL Server needs a schema lock the creating transaction still
> holds, and it dies with `Msg 1205 … deadlocked with another process` on a single-connection run.
> It surfaces at an innocent-looking CodeGen `__mj_CreatedAt` backfill hundreds of batches later and
> reads as server instability rather than an ordering bug.

Two things make that hazard survivable now, and both are recent:

1. **Migrations run one transaction per FILE.** `@memberjunction/open-app-engine` did not set
   `TransactionMode`, so skyway-core's `per-run` default wrapped an app's whole migration set in ONE
   transaction — which silently defeated the split for every open app. Fixed in
   `packages/OpenApp/Engine/src/install/migration-runner.ts`; see `MJ-UPSTREAM.md`.
2. **The split only helps across files.** Putting a `CREATE TYPE` and a trigger that uses it in the
   SAME file re-creates the deadlock even under `per-migration`.

## The 50-blank-line rule (where hand-written DDL stops and CodeGen output starts)

**In any migration that carries both, exactly 50 empty lines separate the hand-written DDL from the
CodeGen capture.** The hand-written half ends with its `GO`; then 50 blank lines; then the capture's
banner comment and the generated SQL. A migration with no capture has no separator; a capture-only file
puts the separator below its header comment so the boundary is still findable.

It reads like formatting and is not. A capture is **replaced wholesale** on regeneration, so anyone
re-capturing needs an unambiguous mark for "everything below here is generated — delete it and paste the
new run." A banner comment cannot be that mark, because banner comments appear *inside* CodeGen output
dozens of times. Fifty consecutive blank lines appear nowhere else in a SQL file, which is exactly why
the number is absurd.

Verify with a longest-blank-run check over `migrations/*.sql`: every file carrying a capture must report
**50**, and `V202608182001` (hand-written wrapper, no capture) must report **1**. `bizapps-orders` is the
reference implementation — `V202608131541`, `V202608131542`, `V202607061432`.

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
dependency chain and rolled back: **8 views, 21 CRUD procedures, 7 entities, 77 entity fields, 6 derived columns** — measured on a wiped database, 2026-08-18.
Re-run that check after any edit:

```bash
# concatenate both files between BEGIN TRANSACTION / ROLLBACK TRANSACTION and run with
# sqlcmd -b against a DB that already has __mj + common + accounting + orders
```
