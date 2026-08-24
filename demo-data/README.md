# `demo-data/` — sample records for demos and manual exploration

**Not shipped.** This directory is deliberately OUTSIDE `metadata/`, so `mj sync push --dir metadata`
(what an install runs) never touches it. Pushing it is an explicit, separate act:

```bash
pnpm run demo:load          # = mj sync push --dir demo-data

# from inside an mjdev instance, where the env lives one level up:
DOTENV_CONFIG_PATH=../mj/.env pnpm exec mj sync push --dir demo-data --format=json
```

Push order is fixed by `.mj-sync.json` → `directoryOrder`: the template and its provisions first,
then the companies, organisations, contracts and modifications that cite them. Every record is
keyed by a fixed UUID, so a re-push **updates** rather than duplicating.

## What is in here, and the one part that is real

`companies/`, `organizations/`, `contracts/` and `modifications/` are **invented** — made-up
organisations with made-up fees, safe to publish and safe to demo.

`contract-templates/` and `contract-provisions/` are **not invented**. They are Blue Cypress's
actual Master Services Agreement, 2026-02-02 edition — 71 provisions carrying their verbatim text,
captured from the dated public URL the agreement is published at.

**They moved here from `metadata/` on 2026-08-24, and that was a correctness fix rather than
housekeeping.** `metadata/` is what an install seeds, and it ships inside
`V202608240300__…__Metadata_Sync.sql` — so every consumer of this app was receiving one company's
contract terms as though they were reference data. Contract *types* and template *types* are
genuine vocabulary and stay in `metadata/`; a specific company's agreement text never was.

It also makes this directory self-contained, which it previously was not: `contracts/` and
`modifications/` cite the template by `VersionLabel=2026-02-02` and its provisions by number, so
pushing `demo-data/` only worked because `metadata/` happened to be shipping the agreement. Now the
push order (`.mj-sync.json` → `directoryOrder`) puts the template and its provisions first, and
nothing outside this folder is required.

## Why metadata sync rather than a script

MetadataSync writes through **BaseEntity**, which is the rule for demo data (plan item 13: through the
entity layer, never raw SQL). It also means no bootstrap code of our own: a hand-rolled seeding script
has to boot a provider, refresh the user cache and load the right entity subclasses, and getting that
wrong produces a split copy of MJCore whose symptom is `InitializeEmbeddedRecords is not a function`.
The CLI already does all of it correctly.

Records are keyed by fixed UUIDs, so re-pushing UPDATES rather than duplicating.

## The one honest compromise

`ContractNumber` is normally minted by `ContractEntityServer` from the `ContractSequence` counter, under
a lock. That subclass is **not loaded in the CLI's process**, so these records carry explicit
`CTR-9000xx` numbers — a deliberately separate block from the real sequence, so demo rows can never
collide with contracts the app mints.

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
