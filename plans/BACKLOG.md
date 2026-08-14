# Backlog — bizapps-contracts

Work identified but not started. Promote an item into `plans/bizapps-contracts-master.md` (or an
action plan) when it is picked up; delete it when it ships. Anything blocked on a **person** belongs
in `plans/QUESTIONS.md` instead, and anything already broken belongs in an issue — this file is for
work that is understood, unstarted, and nobody's yet.

---

## B-1 · PostgreSQL migration parity

**Target:** `migrations-pg/`, `.github/workflows/pg-migrations.yml`
**Goal:** the app's schema can be built on PostgreSQL, and CI proves it.

Nothing is converted today; the app is SQL Server only. `migrations-pg/README.md` states that and
documents the toolchain. The CI gate is live but scoped to **partial** adoption: with no PG files it
reports a notice, and the first `.pg.sql` committed makes parity a hard gate for every migration
including the baseline.

The work is one 581 KB baseline through `mj sql-convert`, then making it actually apply to a fresh
Postgres 17 — the workflow runs it, so a converter that emits `-- TODO:` or output that will not
execute fails visibly. Fix converter rules upstream in MJ rather than hand-editing output.

Not urgent: no deployment target needs PG. Do it deliberately, not alongside an unrelated change.

## B-2 · Raise the `ng-ui-components` range once MJ's disabled-tab change publishes

**Target:** `packages/Angular/package.json`
**Trigger:** MJ commit `2acd4dc7cb` ("mj-tab-nav gains a disabled state with a required reason")
reaching a published release. Tracked in the workspace `MJ-UPSTREAM.md`.

`TabConfig.disabled` / `disabledReason` do not exist in published `@memberjunction/ng-ui-components@5.51.0`,
but the declared range is `^5.50.0`, which resolves to it happily. The consequences today:

- three `TS2339` in `contract-tabs.test.ts`, which is half of why `contracts-ng` will not compile on
  a runner (the other half is unpublished `@mj-biz-apps/accounting-ng`);
- more importantly at runtime, `ToTabConfigs` sets `disabled` and published `mj-tab-nav` ignores it
  — an unreachable tab would render as clickable, with the reason nowhere.

When it publishes, bump the range to that version so a clean install cannot resolve a copy without
the feature, and re-check that CI's build goes green on its own.

## B-3 · Advance `ConsumedAmount`; milestone marking

**Target:** billing engine + a migration
Both are buildable and both need schema. The shortfall maths is correct, but nothing advances
`ConsumedAmount` — its input is manual today, which means the true-up path is only as right as
whoever typed the number. Carried over from the 2026-08-07 session handoff.

## B-4 · Port the 103 tsx server assertions onto the integration tier

**Target:** `test-harnesses/server/*` → `test-harnesses/integration.mjs`
Deprioritised, and deliberately so: they pass and leave no residue — checked. Worth doing only to
retire the tsx tier for consistency, not for coverage.

---

## Share upward — found here, belongs to another repo

Each is a one-liner in someone else's repo. None is ours to push.

- **accounting** — `.github/workflows/pg-migrations.yml` has failed on **every** run since it landed,
  `next` included, because `migrations-pg/` there holds only a README. Its own README claims "you
  cannot land a T-SQL migration without a working PG counterpart"; nothing enforces that, because the
  check has never passed and the branch is not protected. Same scoping fix as B-1 above applies.
- **accounting** — `vite ^7.1.5` on `accounting-core-entities-server`. It uses vitest 4, which needs
  `vite ^6||^7`; npm hoisting hides the mismatch and pnpm will not.
- **orders** — `enableQuotedIdentifier: true` in `test-harnesses/seed-demo-data.mjs`'s pool. `--reset`
  is broken today: every DELETE against a filtered-index table fails with `Msg 1934`, so Product
  survives, ProductCategory cannot go, and the re-seed collides on `UQ_Company_Name`. Its delete list
  is also missing `ProductPrice`, `ProductBundleItem` and `OrderAdjustment`.
- **orders** — could take this repo's registry-parity id-uniqueness/namespacing assertions and the
  `verify` entry point.
