# GENERAL RULE
Don't say "You're absolutely right" each time I correct you. Mix it up, that's so boring!

# BizApps Contracts Development Guide

This is an **open app** built on top of the [MemberJunction](https://github.com/MemberJunction/MJ) platform.

**MemberJunction's own `CLAUDE.md` is the authoritative guide — read it first.** The `@`-imports
below inline it into context; only the path matching this repo's topology resolves, the other is
inert. Prefer either over [GitHub](https://github.com/MemberJunction/MJ/blob/next/CLAUDE.md) — the
local copy is version-matched to the MJ this repo actually runs against.

@../mj/CLAUDE.md
@../../../CLAUDE.md

*(`../mj/` = MJ 6.x parent-workspace, where this repo is a flat sibling of `mj/`. `../../../` =
legacy nested 5.x, `<instance>/mj/packages/dev-apps/<app>/`.)*

MJ's guide is MJ-repo-centric — "the repo root" always means *MJ's* root. How **this** app plugs into
MJ's extension points is documented here. Notably, integration-check bundles load through a config
seam MJ's CLAUDE.md never mentions: [`packages/IntegrationTests/README.md`](packages/IntegrationTests/README.md).

## UI architecture — READ BEFORE TOUCHING ANGULAR

**[`docs/ui-architecture.md`](docs/ui-architecture.md) is binding for this repo.**

The short version: **there is no data-access service layer.** Components bind directly to
`BaseEntity` subclasses and call Remote Operation classes. Those are already strongly typed from the
schema and already network-transparent — the same object works in the browser and on the server — so
a service wrapping them replaces generated types with hand-written DTOs and loses the compiler.

Angular services remain legitimate for Angular-shaped, non-persistent state — wizard step, selection,
filter panels, router coordination. If a method on one loads, saves, validates or maps entity data,
it is in the wrong place.

The review test: *could a non-Angular host do this same work with the same objects?* If yes, the
logic belongs on the entity, its shared subclass, or a Remote Operation.


## Database changes — INCREMENTAL MIGRATIONS ONLY

**[`docs/database-migrations.md`](docs/database-migrations.md) is binding for this repo.**

Schema changes are **new `V` migrations**. Do **not** edit the baseline, and do not rebuild the
database as part of ordinary development.

Editing the baseline was correct while the schema changed constantly and nothing depended on it.
That phase is over: an edit to the baseline is invisible to any database that already ran it — the
column never appears and nothing reports a problem — and flyway checksums the script, so every
existing database refuses to migrate until someone repairs it by hand.

**The one sanctioned exception has already been used, and it is closed.** On 2026-08-23,
immediately before the first publish, the 23-file train was flattened back into the baseline —
collapsing DDL that had been added and then reverted, and fixing three columns a fresh install
left invisible to MJ. That was legitimate only because nothing had shipped. Standing up a clean
database is a from-zero `mj migrate` against an empty database carrying MJ core +
`bizapps-common`; there is no `rebuild-db.sh` in this repo and the reference to one was stale.

**Four migrations, and the count is forced rather than stylistic**: the layered-view flags live on
`__mj.Entity` rows the baseline's own capture creates, a wrapper view cannot be created before the
view it selects `FROM`, and seed data follows both. **An install runs migrations and NOTHING ELSE**
— never CodeGen, never `mj sync push` — so both of their outputs ship as migrations. Omitting
either produces a database that looks installed and isn't. **A filename must sort after everything
the target branch has already shipped** (`changes.yml` enforces it). **Fifty blank lines** separate
hand-written DDL from a CodeGen capture. **Verify from zero, not by inspection** — the flatten's one
real error was invisible on a read and caught immediately by a from-zero diff.

The reasoning behind each of those, the install-order dependency, and the verification procedure are
in [`docs/database-migrations.md`](docs/database-migrations.md).

Write migrations idempotently (`IF NOT EXISTS`, `IF COL_LENGTH(...) IS NULL`) and assume the database
already has data. A migration that reads `__mj.Entity` must skip cleanly when the row is absent —
CodeGen runs *after* migrations — and if the change is really about metadata (field categories,
form layout), its home is `metadata/` and `mj sync push`, not a migration.

The review test: *if a colleague pulls this branch onto a database that already has last week's
schema and runs `pnpm run mj:migrate`, do they get exactly the schema this branch describes?*

## Publishing — what must be true before a release

**`.github/scripts/validate-package-files.sh` enforces this in CI** (wired into both `build.yml`
and `publish.yml`). The rules are here so the reason survives, not just the check.

**Every publishable package declares `files` and `publishConfig`:**

```json
"files": ["/dist"],
"publishConfig": { "access": "public" }
```

npm ships **everything not excluded** when a package declares neither a `files` field nor an
`.npmignore`. This repo declared neither, so `pnpm publish -r --dry-run` packed 71 `src/`,
`*.test.*` and `tsconfig` entries — the full TypeScript source, shipped to consumers next to
`dist`. Nothing fails: the publish succeeds and no consumer complains about source it will never
compile, so the only way to catch it is to look, which is why it is a gate. It is also the family
convention — `bizapps-accounting` (5/5), `bizapps-common` (5/5) and `bizapps-tasks` (6/6) all
carry both fields on every package; this repo was the outlier. `publishConfig.access` matters
separately: a scoped package defaults to **restricted**, so its absence turns the first publish
into a 402 that reads like a billing problem.

`private: true` packages are exempt and need neither field — `pnpm publish -r` and
`changeset publish` both skip them (`@changesets/cli` filters on `!pkg.packageJson.private`), so
`packages/IntegrationTests` leaves the publish set with no configuration at all. That is the
integration tier working as designed: a published framework plus private content, the same split
MJ uses between `@memberjunction/testing-integration` and `@memberjunction/integration-test-suite`,
with the bundles reaching the CLI through `mj.config.cjs` → `testing.checkModules`.

**Pin `@memberjunction/core` and `global` to EXACT versions in `pnpm.overrides`**, not ranges. A
range override still lets pnpm keep more than one satisfying copy per peer context, and two copies
of `core` is the split-ClassFactory failure mode: registrations land in a different factory than
the resolver reads and **nothing errors**. Overrides are workspace-local and never appear in a
published tarball, so every package still ships caret ranges.

**The review test:** run the publish path the way CI and a consumer will — from a **standalone
clone**, no mjdev instance, every dependency resolved from the registry. Inside an instance the
parent workspace links MJ from source and hides the exact packaging state you are checking:

```sh
pnpm install --frozen-lockfile
pnpm run build                                  # all tasks green
ls node_modules/.pnpm/@memberjunction+core@*    # expect exactly ONE
pnpm publish -r --dry-run --no-git-checks       # publishable packages only, no src/
```
