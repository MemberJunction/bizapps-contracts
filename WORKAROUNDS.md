# Workarounds in force

Environment or upstream problems this build steps around, so none of them is silently
load-bearing. Each entry says **what is wrong**, **what we did instead**, and **what removing
it depends on**. Review this before any clean-deploy claim.

Routing: mjdev-tool bugs → `~/MJDev/MJDEV-ISSUES.md` + the MJDev tracker; MJ-core or
sibling-app bugs → `~/MJDev/MJ-UPSTREAM.md`. This file indexes the ones being worked around
**in this repo or this instance**.

---

## W-1 · mjdev's app-engine is broken against MJ 6 `next` — we use the MJ CLI directly

- **Wrong:** every mjdev app-engine operation (`app migrate`, `app codegen`, `app activate`)
  dies with `Cannot read properties of undefined (reading 'Instance')`. mjdev's generated
  engine entry calls `sdp.UserCache.Instance`, and MJ moved `UserCache` out of
  `@memberjunction/sqlserver-dataprovider` into `@memberjunction/generic-database-provider`.
- **Instead:** run each app's own MJ CLI script from its directory —
  `DOTENV_CONFIG_PATH=../mj/.env pnpm run mj:migrate` / `… mj:codegen`. Verified across all
  four sibling apps plus contracts.
- **Cost:** mjdev's per-app status flags are not updated, so `mjdev app list` under-reports
  what has actually been migrated. Cosmetic, but do not trust those flags.
- **Removing it depends on:** MJDev#28.

## W-2 · `MJ_BizApps_Orders: Event Order Lines` API flags disabled in the dev DB

- **Wrong:** CodeGen emits `spCreateEventOrderLine` / `spUpdateEventOrderLine` **permissions**
  files for that entity but never generates the **stored procedures**, so the permissions step
  fails with `Cannot find the object 'spCreateEventOrderLine'`. That aborts CodeGen *before*
  TypeScript generation, blocking every app in the workspace rather than just contracts.
  Reproduced from **orders' own** `mj:codegen`, so it is not a contracts-side scoping problem.
  `spDeleteEventOrderLine` and `vwEventOrderLines` exist; only Create/Update are missing, while
  the entity has `AllowCreateAPI`/`AllowUpdateAPI` true.
- **Instead:** `UPDATE __mj.Entity SET AllowCreateAPI=0, AllowUpdateAPI=0 WHERE Name =
  'MJ_BizApps_Orders: Event Order Lines'` — **in the `contracts-mj6` dev database only.** No
  repository file touched; nothing in contracts depends on that entity.
- **Cost:** that orders entity is not create/update-able via the API *in this dev instance*.
  Irrelevant to contracts; it would matter to someone testing orders here.
- **Reverse it with:** the same UPDATE setting both flags back to 1. Note the DB is rebuilt
  from zero regularly, which restores the flags and re-blocks CodeGen until this is re-applied
  or fixed upstream.
- **Removing it depends on:** a fix in orders (or MJ CodeGen) so sprocs are generated whenever
  a permissions file is. For `MJ-UPSTREAM.md`.

## W-3 · CodeGen "AFTER commands" call `npm` in a pnpm workspace

- **Wrong:** CodeGen completes (`✔ MJ CodeGen complete — 492 entities`) then fails its
  post-generation AFTER commands with `COMMAND: "npm" FAILED`, exiting 1. Those commands shell
  out to `npm`, but this is a pnpm parent-workspace where npm cannot resolve the members.
- **Instead:** tolerated — generation itself is complete and correct, and the build runs
  separately under pnpm. **The non-zero exit means CodeGen cannot be used as a script gate
  until this is fixed.**
- **Removing it depends on:** making those commands package-manager-agnostic in
  `mj.config.cjs` (or in MJ's defaults). Candidate fix inside this repo.

---

## Fixed properly rather than worked around

- **CodeGen generated against every sibling app's schema**, not just this one, because
  `excludeSchemas` names what to skip and the linked workspace contains the siblings. Fixed in
  the committed `mj.config.cjs` with `includeSchemas: ['__mj_BizAppsContracts']`, a positive
  opt-in scope. Not a workaround — the config now enforces what its own comment always claimed.
