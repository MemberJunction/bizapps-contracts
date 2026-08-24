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

1. Write the migration (rules below).
2. Run migrations, then CodeGen.
3. **Only then** write TypeScript against the new fields — with generated
   types, not `.Get()`/`.Set()` weak typing.

This repo's loop-level detail (capturing codegen SQL, metadata-sync
migrations, what to fold vs what CodeGen re-applies everywhere):
[`../template-docs/codegen-and-metadata-migrations.md`](../template-docs/codegen-and-metadata-migrations.md).

## Migration authoring rules

- **Naming**: `V<YYYYMMDDHHMM>__v<app-version>_<Description>.sql`; timestamps
  strictly increasing (CI-gated in this repo).
- **`${flyway:defaultSchema}`** for your schema — never a hardcoded schema
  name. Literal `__mj` only for rows you insert into MJ core tables.
- **Hardcoded UUIDs** for metadata rows — never `NEWID()` (breaks
  reproducibility across installs).
- **Never include what CodeGen owns**: no `__mj_CreatedAt`/`__mj_UpdatedAt`
  columns, no FK indexes.
- **One `ALTER TABLE` per table** — multiple `ADD` clauses comma-separated,
  not repeated statements.
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
