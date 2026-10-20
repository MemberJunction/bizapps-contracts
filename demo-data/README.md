# `demo-data/` — sample records for demos and manual exploration

**Not shipped.** An install applies migrations and nothing else. `metadata/` reaches a host inside
the `V…__Metadata_Sync.sql` migration generated at release; nothing carries this directory there.
It reaches a database only when someone pushes it:

```bash
pnpm run demo:load          # = mj sync push --dir demo-data

# from inside an mjdev instance, where the env lives one level up:
DOTENV_CONFIG_PATH=../mj/.env pnpm exec mj sync push --dir demo-data --format=json
```

Push order is fixed by `.mj-sync.json` → `directoryOrder`: the template and its provisions first,
then the companies, organisations, contracts and modifications that cite them. Every record is
keyed by a fixed UUID, so a re-push **updates** rather than duplicating. The records look up contract
types and template types by name, so the vocabulary `metadata/` ships must already be in the
database.

## What is in here

`organizations/`, `contracts/` and `modifications/` are **invented** — made-up organisations with
made-up fees, safe to publish and safe to demo. `companies/` holds one record, the company on our
side of every demo agreement, under its real name.

`contract-templates/` and `contract-provisions/` are **not invented**: a real Master Services
Agreement, 2026-02-02 edition — 71 provisions carrying their verbatim text, captured from the dated
public URL it is published at ([`contract-templates/README.md`](contract-templates/README.md)).

`ml-training-pipelines/`, `ml-models/`, `record-processes/` and `ml-model-scoring-bindings/` are
the **predictive-scoring bench**: the "Predict Contract Non-Renewal Risk" pipeline, three model
versions fitted on bench data, and the record process and binding that write a score back to
`Contract`. They live here because a fitted model belongs to the data it was fitted on (issue #89).
The models have no trained artifact, so the record process is pushed `Disabled` with its schedule
off: a scheduled run against a model with no artifact fails every contract (MemberJunction/MJ#4829).
Train a model in Predictive Studio before enabling it.

Why that agreement lives here and not in `metadata/`:
[`docs/database-migrations.md`](../docs/database-migrations.md), on what `metadata/` may contain.

## Why metadata sync rather than a script

MetadataSync writes through **BaseEntity**, which is the rule for demo data (plan item 13: through the
entity layer, never raw SQL). It also means no bootstrap code of our own: a hand-rolled seeding script
has to boot a provider, refresh the user cache and load the right entity subclasses, and getting that
wrong produces a split copy of MJCore whose symptom is `InitializeEmbeddedRecords is not a function`.
The CLI already does all of it correctly.

Records are keyed by fixed UUIDs, so re-pushing UPDATES rather than duplicating.

## The one compromise

`ContractNumber` is normally minted by `ContractEntityServer`, which calls
`spAssignNextContractNumber` to take the next value of the `seq_ContractNumber` database SEQUENCE.
That subclass is **not loaded in the CLI's process**, so these records carry explicit `CTR-9000xx`
numbers — a deliberately separate block from the real sequence, so demo rows can never collide with
contracts the app mints.

That does mean **this data does not exercise the numbering path.** Creating a contract through the UI
does, and that is where numbering should be demonstrated.

## What is here, and why each row exists

The set is chosen so every derived `State` and every worklist has content:

| Contract | State it derives | What it demonstrates |
|---|---|---|
| `CTR-900001` Northwind | `Active` | The ordinary case, **plus two modifications** — the point of the app |
| `CTR-900002` Cascadia | `Active` | Notice window already **passed** while the contract runs on |
| `CTR-900003` Meridian | `Executed` | **R-19**: signed, starts next month. Used to read as `Draft` |
| `CTR-900004` Harbor Point | `Active` | **Awaiting document** — executed, never filed |
| `CTR-900005` Northwind | `Active` | A **Payment Link**: nobody signs, so it never reports as awaiting paper |
| `CTR-900006` Cascadia | `Expired` | Term ran out, not renewed |
| `CTR-900007` Meridian | `Draft` | Being prepared — a task, not a wait |
| `CTR-900008` Northwind | `Active` | A **Change Order** naming `CTR-900001` as parent — populates lineage |

Dates are absolute rather than relative-to-today, because a metadata file cannot compute. They were
chosen around **2026-08-19**; if you are reading this much later, the derived states will have drifted
(the `Executed` one will have become `Active`, and more will have `Expired`). Re-date the files, or
create records through the UI instead.
