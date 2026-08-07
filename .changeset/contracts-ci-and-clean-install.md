---
'@mj-biz-apps/contracts-ng': patch
---

The repo installs from a clean clone again, and CI runs the unit tests.

**`npm ci` failed on a fresh checkout** — verified by exporting `HEAD` to an empty directory and
installing exactly as a runner would. Three independent breaks, none of which anything caught,
because nothing ever installed this repo outside a dev-linked instance:

- The root pinned the whole MJ toolchain at exactly `5.44.0` (seven `devDependencies` plus two
  `overrides`), while `contracts-ng` peer-requires `@memberjunction/ng-ui-components ^5.50.0`. The
  5.44.0 chain drags in `ng-ui-components@5.44.0` and npm cannot resolve it. Bumped to `5.51.0`,
  which is both the published latest and the version this app develops against.
- `contracts-ng` peer-depends on `@mj-biz-apps/accounting-ng`, which is **unpublished**. It is a
  real peer — contracts' workspace reuses accounting's card — but not required to build or run
  contracts alone, so it is now `peerDependenciesMeta.optional`. Without that, npm 404s on every
  clean install.
- **`vitest` was never declared.** It resolved only through the MJ workspace under a dev-link, so on
  a clean clone `npx vitest run` died with `ERR_MODULE_NOT_FOUND` before a single test executed.
  Declared on `contracts-ng` at `^4.0.18`, matching orders.

After the fix, on a clean clone: `npm ci` succeeds, `build:packages` builds 5 of 6, and the 55 unit
tests pass.

**A fourth break, which only the runner had:** `npm ci` died there with `Missing: chokidar@3.6.0
from lock file` — before the build, so no test ran and the summary table above was never written.
The lockfile is not stale; regenerating it produces a zero-line diff. It is an npm MAJOR
disagreement. Seven copies of `nunjucks@3.2.4` (via the MJ CLI and server) want `chokidar@^3.3.0`
while `@angular/compiler-cli` pulls `chokidar@5`: npm 11 hoists the 5 and marks those edges invalid,
npm 10 refuses and demands nested `chokidar@3.6.0` entries the lock does not carry. `ci.yml` asked
for Node 22, which ships npm 10 — the clean-clone check above ran on the local npm 11 and could not
see it. Pinned to Node 24, matching `build.yml`, `pg-migrations.yml`, and the machine that writes
the lockfile. Reproduced both ways in a clean clone before and after.

**CI (`ci.yml`), adapted from bizapps-orders.** Builds with `--continue`, runs the unit tests,
writes a summary table, and fails deliberately at the END so a build break cannot collapse the job
onto itself and hide the tally. `contracts-ng` will not compile on a runner — that red is expected
and clears itself with nothing to revert — but it takes **two** publishes, not one:

- `@mj-biz-apps/accounting-ng` is unpublished: `TS2307`, plus two `TS7006` downstream of it.
- MJ's `TabConfig` has no `disabled` / `disabledReason` in the published `ng-ui-components@5.51.0`:
  three `TS2339` in `contract-tabs.test.ts`. The field comes from an MJ commit that is local to the
  dev instance and not on `origin/next` (tracked in `MJ-UPSTREAM.md`). Note this is not only a test
  problem — `ToTabConfigs` sets `disabled` at runtime, and against published MJ `mj-tab-nav` ignores
  it, so unreachable tabs would render as clickable. **When that MJ change publishes, raise the
  `ng-ui-components` range past `^5.50.0`**, which today resolves to a version without the feature.

It is honest about its limits: **55 of this repo's 526 assertions can run on a hosted runner.** The
other 471 need a SQL Server or a browser, and the workflow header lists the exact commands. Orders'
`RUN_MUTATION_TESTS` step is deliberately NOT copied — contracts' checks are not declared
`RequiresMutation` and this runner does not read that variable, so importing it would have added a
step that reads as meaningful and is not.
