# 5 · CodeGen & migrations

## What CodeGen generates (never write these by hand)

From your schema + metadata, CodeGen produces and maintains:

1. **Entity classes** → `packages/Entities/src/generated/` — typed BaseEntity
   subclasses + zod schemas, value-list unions from CHECK constraints.
2. **GraphQL resolvers** → `packages/Server/src/generated/`.
3. **Angular forms** → `packages/Angular/src/lib/generated/`.
4. **Database plumbing** — base views, `spCreate/spUpdate/spDelete`,
   `__mj_CreatedAt`/`__mj_UpdatedAt` columns + triggers, FK indexes
   (`IDX_AUTO_MJ_FKEY_*`), permissions.

Rules: never edit `/generated/` output (regenerated over you); never assume
types are current without running CodeGen after a schema change; commit
regenerated code **with** the migration that caused it.

## The change workflow (order matters)

1. Write the migration (rules below) and any `metadata/` JSON.
2. Apply, push, regenerate — in this order, so CodeGen reads the settings the
   push wrote:
   ```sh
   pnpm run mj:migrate
   pnpm exec mj sync push --dir metadata
   pnpm run mj:codegen
   ```
3. Append CodeGen's SQL output (written to `migrations/codegen/`) to the
   migration, below 50 blank lines and the CodeGen banner.
4. **Only then** write TypeScript against the new fields — with generated
   types, not `.Get()`/`.Set()` weak typing.

This repo's loop-level detail (the migration train, the 50-blank-line
separator, how `metadata/` reaches a host, verifying from zero):
[`../database-migrations.md`](../database-migrations.md).

## Migration authoring rules

- **Naming**: `V<YYYYMMDDHHMM>__v<major>.<minor>.x__<Description>.sql`
  (e.g. `V202609211200__v0.7.x__vwContracts_business_today.sql`); timestamps
  strictly increasing (CI-gated in this repo).
- **Migrations run in order, exactly once** — no idempotency guards: no
  `IF NOT EXISTS`, no `IF COL_LENGTH(...) IS NULL`, no guarded
  `sp_addextendedproperty`. Guards add noise and make the PostgreSQL
  conversion (`mj migrate convert`) harder. A bad migration in your dev
  database is fixed by rebuilding that database, not by making the script
  re-runnable.
- **`${flyway:defaultSchema}`** for your schema — never a hardcoded schema
  name. `${mjSchema}` for MJ core (`mj.config.cjs` maps it to `__mj`).
- **No MJ metadata rows in SQL.** Anything you would INSERT/UPDATE into an
  `__mj.*` configuration table (`EntitySetting`, `EntityField` settings,
  `FileCategory`, …) is declarative JSON in `metadata/`, applied by
  `mj sync push` ([doc 8](08-metadata-and-sync.md)). A PR contributes only the
  JSON (and a `minor` changeset); the `V…__Metadata_Sync.sql` that delivers it
  to hosts is generated at release time.
- **Hardcoded UUIDs** for any row a migration seeds into this app's own
  tables — never `NEWID()` (`migration-conventions.test.ts` checks it).
- **Never include what CodeGen owns**: no `__mj_CreatedAt`/`__mj_UpdatedAt`
  columns, no FK indexes.
- **One `ALTER TABLE … ADD` per table** — every new column, and its
  constraints declared inline, in that one statement:

```sql
ALTER TABLE [${flyway:defaultSchema}].[MyTable] ADD
    [MyColumn] INT NULL,
    [MyOtherColumn] BIT NULL,
    CONSTRAINT [CK_MyTable_MyColumn] CHECK ([MyColumn] IS NULL OR [MyColumn] >= 0);
```

- **CodeGen output** appended to a migration sits below the hand-written SQL,
  after exactly 50 blank lines and the CodeGen banner.
- **`sp_addextendedproperty` (`MS_Description`) for every new column** (except
  PKs/FKs) — CodeGen turns these into entity-field descriptions:

```sql
EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'What this column means',
  @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
  @level1type = N'TABLE',  @level1name = N'MyTable',
  @level2type = N'COLUMN', @level2name = N'MyColumn';
```

- **Immutability**: an applied/published migration is never edited — add a new
  one. Within a published major version, changes are **additive only** (no
  drops, renames, narrowed types) — breaking changes force a major bump (MJ's
  `packages/OpenApp/PUBLISH_NO_BREAK_POLICY.md`).
- Value-list changes: alter the CHECK constraint in a migration (drop +
  re-add), then CodeGen regenerates the TypeScript union.

## Record Changes (built-in versioning)

MJ tracks all record changes automatically unless disabled per-entity — don't
build custom versioning; query the Record Changes entities instead.
