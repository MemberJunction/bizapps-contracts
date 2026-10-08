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
form layout), its home is `metadata/` and `mj sync push` **while you are developing**.

**But a push does not ship.** `mj sync push` seeds *your* database; MJ treats `mj-app.json`'s
`metadata.directory` as a dev-time pointer and `mj app install` applies migrations and nothing else.
`metadata/` reaches a host exactly one way — inside `V…__Metadata_Sync.sql`, regenerated at release
— which is what `docs/database-migrations.md` means by calling `metadata/` the **install seed**.
Read [§ What `metadata/` may contain](docs/database-migrations.md) before adding anything there.

The consequence, because it fails quietly: a `metadata/` edit that a host needs is not "done" when
it merges. Nothing in CI detects a pending metadata change with no migration behind it — the app
installs cleanly either way — so it is done only when a release carries it.

The model, and the Open App steps that differ from core (`--schema`, the `${mjSchema}` substitution): [Release Metadata Migrations Guide](https://github.com/MemberJunction/MJ/blob/next/guides/RELEASE_METADATA_MIGRATIONS_GUIDE.md).

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

## MemberJunction versions — the LTS line AIDP Next runs

AIDP Next runs MemberJunction's 6.1 LTS line, pinned exactly in `aidp-next/package.json`. This repo builds, tests and runs CodeGen against that same version, so what passes here is what runs there (bc-aidp-next-golive#298).

- **Declared ranges.** In a published package, `@memberjunction/*` (and any other app's `@mj-biz-apps/*`) is a **peer** with a caret range, `^6.1.N`, and never appears in `dependencies`: the host installs one copy, and a `~6.1.N` or exact peer makes every 6.2 host install a second 6.1 tree, which splits the ClassFactory. Each peer has an **exact** entry in the same package's `devDependencies` (`6.1.N` for MJ, where 6.1.N is the version AIDP Next runs); that anchor is what installs locally, so builds, tests and CodeGen still run against it. Never an edge or prerelease range (`6.1.0-edge.x` sorts *before* 6.1.0 and has none of the LTS fixes). `.github/scripts/check-dependency-model.mjs` enforces this in CI. Packages MJ versions separately (`@memberjunction/connector-*`, `@memberjunction/skyway-*`) keep their own ranges.
- **`pnpm.overrides`.** `@memberjunction/core` and `@memberjunction/global` are pinned **exactly** to AIDP Next's version (for example `"6.1.5"`), not to a range. A range override can still leave two copies of `core`, and two copies split the ClassFactory: registrations land in one factory while the resolver reads the other, and nothing errors. Overrides are workspace-local and never published. This is the rule under "Publishing" above, now tied to AIDP Next's version. Do not exact-pin sibling `@mj-biz-apps/*` packages here; how the apps declare each other is bc-aidp-next-golive#265.
- **One copy of each.** After any install, `pnpm why @memberjunction/core` must show a single version. A sibling app package that exact-pins an old MJ build brings a second copy in (for example `@mj-biz-apps/common-ng@5.37.0` pinned edge.3 packages); fix it by raising that package's floor, not with more overrides.
- **Bumping to a new 6.1.N**, when AIDP Next moves: update every `^6.1.N` peer floor, every exact `6.1.N` devDependencies anchor and both overrides; `pnpm install`; confirm one copy; `mjVersionRange` in `mj-app.json` follows in the Version Packages PR (`ci/sync-mj-app-version.mjs`); rebuild the database from migrations on MJ core `v6.1.N` and regenerate (below); run the full test suite; add a `patch` changeset; commit the lockfile. If CI then fails on the lockfile although a clean local install works, GitHub is testing the merge with `next`: merge `next` in, run `pnpm install --no-frozen-lockfile`, and commit the lockfile.
- **Never patch MemberJunction.** No `pnpm patch`, `patchedDependencies`, patch-package or `sed` against `@memberjunction/*` `dist/`. That is AIDP Next's hard rule (`.github/workflows/MJ_PATCH_REGISTER.md` in aidp-next). Fix MJ on its `next` branch and bring the fix to the line with the `backport lts/6.1` label, or with a hand-port PR against `lts/6.1` when the fix can't be isolated; then wait for the patch release.

### CodeGen output must be reproducible from this repo

Generated files are committed, and AIDP Next ships them as they are: it excludes every `__mj_BizApps*` schema from its own CodeGen and installs the published packages. So the committed output has to be what this repo's toolchain produces from its migrations.

- Run CodeGen only with this repo's pinned MJ version, against a database built from migrations (MJ core `v6.1.N`, then the apps this one depends on, then this repo), after `mj sync push` of `metadata/`.
- Set an AI key in your gitignored `.env`: `AI_VENDOR_API_KEY__GeminiLLM` (every CodeGen prompt ranks Gemini first), or `AI_VENDOR_API_KEY__OpenRouterLLM`. Without one, CodeGen silently drops AI-written output: check-constraint `Validate*()` methods, display names, descriptions and form layouts.
- Never hand-edit generated files, and never paste in generated output from another toolchain or another database. That is how OrderLine lost `OrderHeader`'s `@Field` (bc-aidp-next-golive#295).
- Review what AI wrote. Validators, names and descriptions are not deterministic between runs.
- If CodeGen has to create metadata in the database that the generated code depends on (fields, value lists, relationships, validator code), ship it in a migration in the same PR. Otherwise every host installed from migrations drifts from the code.
