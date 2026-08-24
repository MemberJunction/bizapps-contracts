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

## What belongs here, and what does not

**Here:** structural metadata (`schema-info`, `entities`, `entity-fields`,
`entity-relationships`, `applications`) and genuine **vocabulary** — the contract types and
template types every install needs to function.

**Not here:** any specific organisation's data, including their agreement text. This folder is
what an install seeds, via `V*__Metadata_Sync.sql`, so anything in it is installed into every
consumer's database as reference data.

`contract-templates/` and `contract-provisions/` used to live here and carried Blue Cypress's
own Master Services Agreement — 71 verbatim provisions. They moved to `demo-data/` on 2026-08-24;
see that folder's README. The distinction to hold on to: *"a Statement of Work is a kind of
contract"* is vocabulary and ships; *"here is our Master Agreement"* is one company's content and
does not.
