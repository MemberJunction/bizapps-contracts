---
'@mj-biz-apps/contracts-ng': patch
---

Take the rest of what is good from bizapps-orders' CI, and add the piece it was missing.

**The anti-vacuity floor, which contracts did not have.** `registry-parity.test.ts` asserts the
integration registry's shape — which bundles exist, how many checks each holds, that every id is
unique and namespaced to its bundle. A suite that silently shrinks now fails on a runner, with no
database: a bundle added to `checks/` but never imported, a rename that breaks the `contracts-`
prefix, a check removed mid-refactor — all previously green. Proved by breaking it two ways (a wrong
expected count, and a bundle genuinely un-registered); both fail, with the message naming the gap.

**`scripts/assert-check-count.mjs` guards the other half.** The parity test proves the registry has
48; only a real run proves 48 EXECUTED. It reads the expected total out of the parity test, so the
two cannot drift into agreeing on a shrunken suite. Proved against a doctored short log and a
truncated one — both fail, and a run that never reached its summary is treated as a failure rather
than a missing file.

**Named entry points**, so 533 assertions stop being things only whoever wrote them knows how to
run: `test:unit` (turbo, both suites), `test:integration`, `test:server`, `test:erd`,
`test:coverage-gate`, and `verify` — the pre-merge gate that runs everything a local machine can, in
order, with the integration tally checked rather than trusted.

**`pg-migrations.yml`**, adapted from orders: every T-SQL migration must have a PG counterpart that
applies to a fresh Postgres. It will be RED until `migrations-pg/` exists — that gap is real and was
previously invisible.

**Three more things a clean clone exposed**, all pre-existing: `turbo.json` declared no `test` task
(so `test:unit` reached nothing), `tsx` was never declared (it resolved only through the dev-linked
MJ workspace), and `packages/IntegrationTests` had no `repository.url` — caught by the repo's own
validator the first time it ran here.

Unit coverage on a runner goes from 55 to 69.
