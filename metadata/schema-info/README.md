# schema-info — ⚠️ FILL THIS OUT before your first metadata sync

This folder registers your app's schema in `__mj.SchemaInfo` — the record that
gives your entities their name prefix and ID range. **It ships as an inert
`.template` file that `mj sync` cannot see**, so nothing placeholder ever
reaches a database. Until you activate it, a sync push over `metadata/` pushes
nothing for this folder (and your schema stays unregistered — codegen won't
apply your entity-name prefix).

## To activate (one-time)

1. Copy `schema-info.json.template` → **`.schema-info.json`** (note the
   leading dot — that's what makes it a record file).
2. Fill every `TODO`:
   - `SchemaName` — exactly your `mj-app.json` `schema.name` (this template: `__mj_BizAppsContracts`)
   - `EntityIDMin` / `EntityIDMax` — an integer ID range reserved for your
     app's entities, non-overlapping with other apps (e.g. `10000001` / `10099999`)
   - `EntityNamePrefix` — the prefix for your entity names (e.g. `Sample App`);
     must agree with `mj.config.cjs` `NameRulesBySchema`
   - `Description` — one line about the schema
   - `primaryKey.ID` — **generate a UUID** (`uuidgen`) and never change it
     once pushed anywhere; the pinned ID is what makes the row deterministic
     across databases
3. Push: the row is CREATED with your ID on the first
   `mj sync push` (autoCreateMissingRecords).

Full guide: [`docs/template-docs/metadata.md`](../../docs/template-docs/metadata.md)
(§ Schema registration).
