# 8 · Metadata & mj-sync

How MJ metadata records (applications, lookup seeds, actions, prompts,
queries…) are authored as files and pushed. This app's `metadata/` folder
follows these rules. Authoring syntax with worked examples is MJ's
[MetadataSync README](https://github.com/MemberJunction/MJ/blob/next/packages/MetadataSync/README.md);
what may go in `metadata/` (versus `demo-data/`) and how it reaches a host
(the release-time `V…__Metadata_Sync.sql` migration) is in
[`../database-migrations.md`](../database-migrations.md).

## File organization

- One subdirectory per entity: `.mj-sync.json` (entity name + push/pull
  options) + `.<records>.json` (array of `{ "fields": {...} }` objects).
- New records **omit `primaryKey` and `sync`** — mj-sync writes them back on
  first push. Re-pushing is safe (upsert semantics).
- List folders in the root `metadata/.mj-sync.json` `directoryOrder` so
  dependencies push in order; an unlisted folder is pushed after the listed
  ones, in alphabetical order.
- **Externalize complex JSON values** with `@file:` references
  (`"FieldSchema": "@file:schemas/api-key.schema.json"`) instead of escaped
  JSON strings; keep them in typed subfolders (`schemas/`, `templates/`).
- Cross-record references resolve via `@lookup:`, `@parent:`, `@template:`,
  `@root:`.

## Seeding lookup/reference tables

Never seed lookup tables or MJ configuration rows with `INSERT`s in a
migration — author the records as metadata files (version-controlled,
readable, upsertable, `@lookup:` resolution) and let the release-time
`V…__Metadata_Sync.sql` produce the SQL that ships. Example:
`metadata/contract-types/.contract-types.json`.

## Applications & nav items

An `Applications` record gives your app UI presence in Explorer. Each
`DefaultNavItems` entry with `ResourceType: "Custom"` needs `DriverClass` to
exactly match an
`@RegisterClass(BaseResourceComponent, '<DriverClass>')` component in your
Angular package (+ a tree-shaking prevention export). One `isDefault: true`
per app. Example: `metadata/applications/.contracts-application.json`.

## Commands

```sh
pnpm exec mj sync validate --dir metadata   # validate before pushing
pnpm exec mj sync push --dir metadata       # push to your database
```

Validation understands virtual properties, defaults, and reference integrity;
`push` runs it automatically. Remember: `mj sync push` is a **dev-time** tool
that writes to your own database — installs receive metadata only through the
release-time `V…__Metadata_Sync.sql` migration, never by running sync.
