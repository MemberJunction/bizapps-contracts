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

## W-4 · `mjdev app register` cannot be used at all — registration is hand-wired

**What breaks:** every mjdev *app-engine* command on this instance dies with
`Cannot read properties of undefined (reading 'Instance')` — MJ moved `UserCache` to
`@memberjunction/generic-database-provider` and mjdev still reads it off
`sqlserver-dataprovider`. That is MJDev#28, and its affected-command list is incomplete: it also
breaks `app drop-schema` and `app register`.

**Why it matters more than the others:** `app register` is the ONLY sanctioned way to wire an open app
into MJAPI/MJExplorer, so an unregistered app is invisible in Explorer with no supported route to fix
it. Worse, **its rollback DELETED the entire app worktree** while printing "instance restored, retry is
clean" — filed as **MJDev#29**. Recovery was lossless only because everything was committed and pushed.

**Workaround (hand-wiring, all in the instance's MJ worktree, all regenerable):**
1. `mj/mj.config.cjs` → `dynamicPackages.server` + `.client` entries (shape copied from
   `instances/orders-mj6-ws`, which mjdev generated itself)
2. `mj/packages/MJAPI/package.json` → dep on `@mj-biz-apps/contracts-server`
3. `mj/packages/MJExplorer/package.json` → deps on `contracts-ng` + `contracts-entities`
4. regenerate Explorer's manifest: `mj codegen manifest --exclude-packages @memberjunction
   --output ./src/app/generated/class-registrations-manifest.ts --open-app-client-bootstrap`
   (expect "19 classes from 2 packages"; an empty manifest means step 2/3 is missing)
5. `mjdev link <slug>` restores workspace membership (the rollback strips it from
   `pnpm-workspace.yaml`), then `pnpm install` at the INSTANCE dir
6. **restart MJAPI** — its GraphQL schema has no contracts resolvers until it reboots, and its
   prestart may add its own dependencies and then crash with an opaque
   `[Object: null prototype] {}` until you install again

**COMMIT BEFORE RUNNING ANY mjdev app COMMAND.** That is the whole mitigation for #29.

## W-5 · No published MJ can compile current `next` CodeGen output

**What breaks:** `pnpm run build:packages` in a standalone clone fails with 7 × TS2554 on
`NewRecordValues(entity, field)`.

**Cause:** MJ commit `84f276e` (2026-08-15, on `next`) added a second parameter, and CodeGen emits the
two-argument call. The newest PUBLISHED MJ is `6.1.0-edge.2`, whose typings declare one parameter —
same version string, different signature, because the change landed after the edge publish without a
bump. `bizapps-common` has 21 of the identical calls committed, so this is family-wide.

**Workaround: none, and none should be attempted.** Hand-editing generated code is not a fix. CI
`build-only` and the PG check are **accepted red while unpublished** (Marcelo, 2026-08-19) — verify the
unit tests instead. Resolves itself when MJ publishes an edge carrying the two-parameter signature.
