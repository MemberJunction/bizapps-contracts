# @mj-biz-apps/contracts-integration-tests

Integration check bundles for BizApps Contracts. **Private — never published.** Importing this
package registers its bundles on `IntegrationCheckRegistry`; that is its entire runtime job.

```
mj.config.cjs → testing.checkModules → this package → IntegrationCheckRegistry → IntegrationTestDriver
```

## Where the seam lives — read this before concluding anything is unwired

The seam is split across two repos, and mistaking one half for the whole is the standing trap:

| Half | Where | What it is |
|---|---|---|
| **Mechanism** | MJ — `packages/TestingFramework/CLI/src/utils/check-module-loader.ts`, consumed by `commands/run.ts` + `commands/suite.ts`; registry at `packages/TestingFramework/testing-integration/src/check-registry.ts` | Side-effect-imports each configured specifier, then resolves bundles by string lookup |
| **Declaration** | **This repo** — [`../../mj.config.cjs`](../../mj.config.cjs) `testing.checkModules` | Names *this* package, so *our* bundles register |

Nothing needs adding to the MJ worktree, and nothing needs adding to mjdev. `mj test` loads its
config with cosmiconfig `search()` from `process.cwd()`, which walks **up** — so run from this repo
and it finds *this repo's* `mj.config.cjs`, never MJ's. MJ's own docs (`guides/INTEGRATION_TESTING_QUICKSTART.md`)
say "the repo root `mj.config.cjs`" throughout, meaning **MJ's** root; that phrasing has already
convinced one agent the wiring was impossible from here. It is not — line 100 of our config is the wiring:

```js
testing: {
  checkModules: ['@mj-biz-apps/contracts-integration-tests'],
},
```

There is also an ad-hoc `--checks-module <package-or-path>` flag on `mj test run` / `mj test suite`,
appended to whatever the config lists. `bizapps-orders` uses the identical arrangement.

## Running

```bash
# The fast inner loop. Boots the provider directly, no metadata, stack traces on failure.
# contracts-world COMMITS a portfolio (CTR-WORLD) so Explorer has rows; the other bundles roll back.
node test-harnesses/integration.mjs                       # every bundle (world first)
node test-harnesses/integration.mjs contracts-world        # seed visible contracts
node test-harnesses/integration.mjs contracts-graph-save   # one bundle
node test-harnesses/integration.mjs contracts-graph-save.GS3  # one check
```

Needs a working database and the instance `.env` (found by `test-harnesses/load-env.mjs`, which
walks up rather than counting directories — both the 6.x parent-workspace and the legacy nested
topology resolve).

`TypeError: provider.QuoteSchemaAndView is not a function` on startup is **benign, pre-existing
bootstrap noise** — observed, not suppressed. See `test-harnesses/parent-requirement.mjs:16`.

### The recorded path (`mj test`) is not usable from this repo yet

`mj test` resolves bundles out of `MJ: Tests` metadata records, and **this repo has none** — there
is no `metadata-tests/` here. `bizapps-orders/metadata-tests/tests/*.json` is the model to copy when
we want runs recorded as `MJ: Test Runs`. Until those records exist, the standalone runner above is
the only path, and it reads the same registry, so there is no drift.

When the records land, run the **workspace** CLI, never a global `mj` — a global install ships its
own published testing packages and cannot resolve this private one, so every bundle dispatch fails
with `Unknown integration check bundle`:

```bash
MJ_INTEGRATION_TEST=1 ./node_modules/.bin/mj test suite --name "BizApps Contracts Integration"
```

## Current state

Plan item 13's four bundles are built, plus `contracts-world` so the app is not empty in Explorer.
v1's `contracts-composition` / `contracts-save-contract` / `contracts-billing` / `contracts-amendment`
tested machinery the rebuild deleted and stay gone.

| Bundle | Covers |
|---|---|
| `contracts-world` | COMMITS CTR-WORLD: a published template, four customers, and a contract in every derived `State`, with relative dates and minted `CTR-` numbers |
| `contracts-graph-save` | header + modifications atomicity, rollback on invalid, `HasModifications` monotonic, type/template rules — the D-15 acceptance test |
| `contracts-numbering` | `ContractNumber` CTR sequence, uniqueness under concurrency, reserved `CTR-` namespace |
| `contracts-provisions` | seed completeness incl. text, natural order via `ProvisionSortKey` (`1.9` before `1.10`) |
| `contracts-watchlist` | derived column **values** (`IsAwaitingDocument`, `DaysToEnd`, `RenewalNoticeDeadline`, `IsInCancellationWindow`, `State`). `IsChangeOrder` was removed from the view — W8 asserts `ParentContractID` instead |

`contracts-world` is the only bundle that leaves rows. Re-running it updates dates so the watchlist does not drift. The rest wrap each check in a provider transaction and roll it back.

## Writing a bundle

```ts
import { IntegrationCheckRegistry } from '@memberjunction/testing-integration';
import type { IntegrationCheckContext } from '@memberjunction/testing-integration/registry';

for (const check of checks) IntegrationCheckRegistry.Instance.Register(check);

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-graph-save', {
    Setup: async (ctx) => { /* create the shared fixture */ },
    Teardown: async (ctx) => { /* FK-ordered sweep; must never throw */ },
});
```

- **A check is a function that THROWS on failure and RETURNS on pass.** `NamedCheck` is
  `{ Id, Name, Fn, RequiresMutation?, RequiresLiveModel? }`. The driver wraps each in try/catch and
  maps the outcome onto an `OracleResult` — there is no per-check result type to return.
- **`Id` must be `<bundle>.<localId>`** (e.g. `contracts-graph-save.GS3`). `GetBundle` is a literal
  `Id.startsWith(prefix + '.')` filter, so the id prefix *is* the bundle — there is no separate
  registration of a bundle name.
- **Prefix every bundle `contracts-`.** The registry is a `BaseSingleton` and therefore
  process-global. An instance with orders and contracts both dev-linked loads both apps' bundles into
  one registry, and orders already owns a bundle called `composition` — so an unprefixed
  `composition` bundle would hand `GetBundle('composition')` both apps' checks as one bundle.
- **Import the context type from the `/registry` subpath, not the barrel.** The root barrel
  re-exports `./bootstrap` (which pulls `@memberjunction/server-bootstrap-lite` and `mssql`) plus
  every MJ check module; `/registry` is deliberately server-free.
- **Context is `{ User, Provider, Pool?, Schema?, Storage }`.** `Storage` (the instrumented cache) is
  `undefined` for us — only MJ's own cache bundles read it, and fabricating one would mean claiming
  to own the process for no benefit. `Pool` is the raw `mssql` connection for fixture SQL.
- **Resolve fixtures, don't extend MJ's context type.** `IntegrationCheckContext` declares named
  fixture slots for MJ's *own* bundles (`RunQueryFixtures`, `RlsFixture`, …) and ours is not among
  them. Follow `bizapps-orders/packages/IntegrationTests/src/client-world.ts`: a `Resolve…(ctx)`
  helper that queries what it needs, rather than a new field on a type we don't own.

## The import trap that cost a day

`test-harnesses/integration.mjs` imported `@memberjunction/server-bootstrap-lite`,
`@mj-biz-apps/common-entities` and `@mj-biz-apps/orders-entities` — **none of them a declared
dependency of this repo.** Under pnpm's strict `node_modules` an undeclared package is unresolvable
from the importing file, so the script died at bootstrap with `ERR_MODULE_NOT_FOUND` naming an MJ
package, *before ever reaching the registry*. That reads like "this repo can't see the MJ side," and
it is why the seam was reported missing when it had been wired all along.

Only import what this repo declares. `bootstrap-lite` merely preloads MJ **core** class
registrations and nothing here touches a core subclass — `parent-requirement.mjs:54` already
documents the same conclusion. What actually matters is importing the packages whose subclasses carry
the invariants under test:

```js
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');
```

Without those the checks exercise the plain generated entities and pass while proving nothing.
