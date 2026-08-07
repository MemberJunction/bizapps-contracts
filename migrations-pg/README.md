# PostgreSQL migrations — not adopted yet

**Contracts is SQL Server only today.** This directory holds no migrations, and that is the current
state of the app rather than an oversight: nothing has been converted, nothing has been applied to a
PostgreSQL database, and no claim is made here that the T-SQL in `migrations/` would run on one.

The directory exists so the state is visible in the repo instead of only in a CI log.

## What CI does about it

`.github/workflows/pg-migrations.yml` gates on **partial** adoption, not on non-adoption:

| `migrations/` | `migrations-pg/` | Result |
| --- | --- | --- |
| empty | empty | skipped |
| has files | empty | a notice — PG parity unadopted, nothing to check |
| has files | has files | **hard gate**: every T-SQL migration must have a counterpart, and the PG set must apply to a fresh Postgres 17 |

So the first `.pg.sql` file committed here turns parity into a blocking check for every migration in
the repo, including the baseline. A half-converted history — the state in which a PG database
silently drifts from SQL Server — cannot pass.

The gate was originally copied from `bizapps-accounting` in its unconditional form, where it fails
on every run for exactly this reason (that repo's `migrations-pg/` also holds only a README). A
check that cannot pass gets ignored, which costs more than the gap it was marking.

## Adopting it

SQL Server stays the source of truth; PG files are produced by the MemberJunction SQL converter.

```bash
npx mj sql-convert \
  migrations/B202608040001__v0.1.x__Baseline.sql \
  --from tsql --to postgres \
  --output migrations-pg/B202608040001__v0.1.x__Baseline.pg.sql \
  --schema __mj_BizAppsContracts \
  --verbose
```

Converted files are `*.pg.sql`; hand-written PG-only patches (patterns with no clean T-SQL
equivalent) are `*.pg-only.sql`. `mj migrate` picks the directory from `DB_PLATFORM`
(`sqlserver` → `migrations/`, `postgresql` → here). If the converter emits `-- TODO:` comments it
could not handle a pattern — fix the rule upstream in MJ and re-convert rather than hand-editing
the output.

`bizapps-accounting`'s `migrations-pg/README.md` documents the toolchain in full.

**One caveat before starting.** The baseline is a single 581 KB file, and this app's `disabled`-tab
work already depends on unpublished MJ. Converting it is a real piece of work with a real
verification burden — the workflow applies the result to a live Postgres and will say so if it does
not run. It is not a formality to tick off alongside an unrelated change.
