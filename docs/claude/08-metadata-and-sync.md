# 8 · Metadata & mj-sync

How MJ metadata records (applications, lookup seeds, actions, prompts,
queries…) are authored as files and pushed. This app's `metadata/` folder follows these rules; the full authoring guide
with worked examples is [`../template-docs/metadata.md`](../template-docs/metadata.md),
and the app-repo capture flow (metadata → `V*_Metadata_Sync.sql` migration) is in
[`../template-docs/codegen-and-metadata-migrations.md`](../template-docs/codegen-and-metadata-migrations.md).

## File organization

- One subdirectory per entity: `.mj-sync.json` (entity name + push/pull
  options) + `.<records>.json` (array of `{ "fields": {...} }` objects).
- New records **omit `primaryKey` and `sync`** — mj-sync writes them back on
  first push. Re-pushing is safe (upsert semantics).
- List folders in the root `metadata/.mj-sync.json` `directoryOrder` so
  dependencies push in order.
- **Externalize complex JSON values** with `@file:` references
  (`"FieldSchema": "@file:schemas/api-key.schema.json"`) instead of escaped
  JSON strings; keep them in typed subfolders (`schemas/`, `templates/`).
- Cross-record references resolve via `@lookup:`, `@parent:`, `@template:`,
  `@root:`.

## Seeding lookup/reference tables

Never seed lookup tables with raw `INSERT`s you hand-write **as the source of
truth** — author the records as metadata files (version-controlled, readable,
upsertable, `@lookup:` resolution) and let the sync→migration capture produce
the SQL that ships. Worked example: [`../template-docs/metadata.md`](../template-docs/metadata.md).

## Applications & nav items

An `Applications` record gives your app UI presence in Explorer. Each
`DefaultNavItems` entry with `ResourceType: "Custom"` needs `DriverClass` to
exactly match an
`@RegisterClass(BaseResourceComponent, '<DriverClass>')` component in your
Angular package (+ a tree-shaking prevention export). One `isDefault: true`
per app. Worked example: [`../template-docs/metadata.md`](../template-docs/metadata.md).

## Commands

```sh
npx mj-sync validate --dir=metadata          # validate before pushing
npx mj sync push --dir=metadata --format=json  # push (non-interactive)
```

Validation understands virtual properties, defaults, and reference integrity;
`push` runs it automatically. Remember: `mj sync push` is a **single-author,
dev-time** tool — teammates and installs receive metadata via migrations, not
by running sync.
