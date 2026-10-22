# metadata/

MJ metadata authored as files and pushed with `pnpm exec mj sync push --dir metadata` — the dev-time
source of truth. A host never runs that push: an install applies migrations only, and `metadata/`
reaches a host inside the `V…__Metadata_Sync.sql` migration generated at release.
Two have shipped, `V202608240300__v0.1.x__Metadata_Sync.sql` and
`V202610092210__v0.8.x__Metadata_Sync.sql`; changes made since the second wait for the next one
(issue #112). `rr: metadata shipped` fails a release PR while a substantive change here has no
Metadata_Sync behind it. [`docs/database-migrations.md`](../docs/database-migrations.md#what-a-host-has-today)
lists what each carries.

**How to format and write metadata records:** MJ's
[MetadataSync README](https://github.com/MemberJunction/MJ/blob/next/packages/MetadataSync/README.md).

Every folder with its own `.mj-sync.json` is pushed: those listed in `.mj-sync.json` →
`directoryOrder` first, in that order, then the rest alphabetically. Within a folder, the
dot-prefixed `.json` files are records (`filePattern: **/.*.json`), so don't park drafts in this tree.

| Folder | Entity |
|---|---|
| `applications` | `MJ: Applications` |
| `contract-template-types` | `MJ_BizApps_Contracts: Contract Template Types` |
| `contract-types` | `MJ_BizApps_Contracts: Contract Types` |
| `entities` | `MJ: Entities` |
| `entity-fields` | `MJ: Entity Fields` |
| `entity-relationships` | `MJ: Entity Relationships` |
| `entity-settings` | `MJ: Entity Settings` |
| `queries` | `MJ: Queries` |
| `query-categories` | `MJ: Query Categories` |
| `schema-info` | `MJ: Schema Info` — no records; see [`schema-info/README.md`](schema-info/README.md) |
| `user-views` | `MJ: User Views` |

## What belongs here, and what does not

What `metadata/` may contain, and why the sample agreement lives in `demo-data/` instead:
[`docs/database-migrations.md`](../docs/database-migrations.md). The predictive-scoring bench (the
training pipeline, its model versions, the scoring record process and its binding) lives in
`demo-data/` for the same reason: its fitted statistics come from one dataset (issue #89).
