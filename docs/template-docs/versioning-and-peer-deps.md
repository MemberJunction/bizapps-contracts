# Versioning & peer dependencies

## One version for the whole app

All `@mj-biz-apps/contracts-*` packages version **together** (fixed versioning): the
`.changeset/config.json` `"fixed": [["@mj-biz-apps/contracts-*"]]` entry makes
`changeset version` bump every package to the same number, and the publish
workflow copies that number into `mj-app.json` `"version"` — which must match
the GitHub release tag. One app = one version, everywhere.

Bump sizes follow the content (CI + the publish workflow enforce/verify):

| Change | Bump |
|---|---|
| New migration (additive schema/metadata) | **minor** (minimum — CI enforces) |
| Breaking change (see publishing.md no-break policy) | **major** |
| Code-only fix, no migration | patch |

Declare the bump in your PR with `npx changeset`.

## The three kinds of dependency (see the real examples in `packages/*/package.json`)

| Dependency on… | Declare as | Version spec | Why |
|---|---|---|---|
| A **sibling package of this app** (e.g. `@mj-biz-apps/contracts-entities` from `Server`) | `dependencies` | **exact** (`1.0.0`) | Siblings ship in lock-step (fixed versioning); an exact pin means an install always gets the matched set |
| **`@memberjunction/*`** | `peerDependencies` | caret range (`^5.44.0`) | The HOST provides MJ exactly once. A hard dep could nest a second copy of `@memberjunction/global`/`core`, which splits MJ's class-factory registry and silently breaks registration — the single-copy invariant |
| **`@angular/*`** | `peerDependencies` | range (`>=21.0.0 <22.0.0`) | Same reasoning; the host Explorer owns the Angular version |
| Ordinary libraries the package truly owns (e.g. `zod`) | `dependencies` | caret | Normal npm semantics |
| Build tooling (`typescript`, `@angular/compiler-cli`) | `devDependencies` | caret/pinned | Never shipped |

Worked examples in this template:
- `packages/Entities/package.json` — peers only + `zod`
- `packages/Server/package.json` — exact-pinned sibling deps + MJ peers
- `packages/Angular/package.json` — Angular peer ranges + MJ peers

## Root `overrides`

The root `package.json` pins `@memberjunction/core`/`@memberjunction/global`
(and, if you add more Angular tooling, the `@angular/*` set) via `overrides` so
a standalone `npm install` resolves ONE version tree. Bump these when you move
to a new MJ release.

## `mjVersionRange`

The manifest's `mjVersionRange` declares which MJ versions the app supports.
You set it once; on every publish the workflow **re-derives** it from the
`@memberjunction/core` peer dependency in `packages/Entities/package.json`
(`>=<that version> <next-major>`), so keeping the peer dep honest keeps the
manifest honest.

## Upgrading the MJ baseline

1. Bump every `@memberjunction/*` peer dep + the root `overrides` to the new
   version.
2. Re-run the loop (migrate → codegen → build) against an MJ instance of that
   version; commit regenerated code.
3. Changeset: minor (or major if you drop support for an older MJ).
