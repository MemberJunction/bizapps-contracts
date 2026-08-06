# metadata/

MJ metadata authored as files and pushed with `mj sync` — the dev-time source
of truth (installs receive it as `V*_Metadata_Sync.sql` migrations instead).

**How to format and write metadata records:**
[`docs/template-docs/metadata.md`](../docs/template-docs/metadata.md).

⚠️ **`schema-info/` requires fill-out before it does anything**: it ships as
an inert `.template` file with TODO placeholders that `mj sync` cannot see.
Follow `schema-info/README.md` (copy → `.schema-info.json`, fill the TODOs,
generate a stable UUID) to register your schema — until then a sync pushes
nothing for it and your entity-name prefix isn't applied. Keep the folder
either way (the sync loop needs at least one entity folder listed in
`directoryOrder`).

Only dot-prefixed `.json` files inside folders listed in `.mj-sync.json`
`directoryOrder` are treated as records — don't park drafts in this tree.
