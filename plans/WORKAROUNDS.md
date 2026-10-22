# Workarounds carried by this app

Every place this app or its development setup compensates for something outside its own code — an
MJ gap, a dev-tool bug, a platform behaviour we cannot change from here. They are logged so none of
them is silently load-bearing: each entry states **what breaks without it**, **why the fix is not
upstream yet**, and **how to remove it**. Review this before any clean-deploy claim.

An entry leaves this file only when the workaround is *removed*, not when it stops bothering anyone.

---

## W-1 · The Explorer grid wrapper swallows foreign-key clicks

**Carried by:** `packages/Angular/src/lib/directives/fk-navigate.directive.ts`, applied to the
`<mj-explorer-entity-data-grid>` grids in four pages: `lib/pages/contract-grid.page.ts`,
`templates.page.ts`, `modifications.page.ts` and `configuration.page.ts`. The grid in
`lib/form-panels/organization.panels.ts` does not carry it.

**What breaks without it.** Nothing errors — that is the problem. `mj-entity-data-grid` renders
every FK cell as a blue underlined anchor (`.cell-fk-link`), hit-tests the click, and emits
`ForeignKeyClick` carrying the related entity + FK value (`entity-data-grid.component.ts` →
`onAgCellClicked`). The wrapper the forms and our pages use — `mj-explorer-entity-data-grid` — does
not forward that event and declares no `ForeignKeyClick` output of its own (checked in
`@memberjunction/ng-base-forms` 6.1.5 and on MJ `next`, 2026-10-11). So every FK link in every
wrapper-hosted grid is inert while still *looking* clickable.

**Why not fixed in MJ.** It should be — it is a one-output change on the wrapper, and it affects
every app that uses it, not just ours. No upstream issue is filed yet.

**How to delete this workaround.** When the wrapper exposes `ForeignKeyClick`: delete the directive,
drop `mjcFkNavigate` + the import from the four pages, and bind `(ForeignKeyClick)` instead. The
directive deliberately uses MJ's public API (the wrapper's public `innerGrid` ViewChild and the inner
component's own `@Output`) rather than re-reading the DOM `data-*` attributes, so behaviour is
identical either way.

---

## W-2 · mjdev's app engine cannot boot against MJ 6 — use the MJ CLI and hand-wire registration

**Not carried in code** — a procedure for anyone developing inside an mjdev instance.

**What breaks.** Every mjdev app-engine command (`app migrate`, `app codegen`, `app activate`,
`app register`, `app drop-schema`) dies at provider boot with
`Cannot read properties of undefined (reading 'Instance')`, without applying anything. mjdev's
generated engine reads `sdp.UserCache.Instance`, and MJ moved `UserCache` from
`@memberjunction/sqlserver-dataprovider` to `@memberjunction/generic-database-provider`. Tracked as
MJDev#28. `app register`'s rollback also **deletes the entire app worktree** while reporting a clean
retry — MJDev#29. **Commit and push before running any mjdev `app` command.**

**Instead:**
- Migrate and generate with this repo's own scripts, pointed at the instance's `.env`:
  `DOTENV_CONFIG_PATH=../mj/.env pnpm run mj:migrate` / `… pnpm run mj:codegen`.
- Register the app by hand, in the instance's MJ worktree (all regenerable):
  1. `mj/mj.config.cjs` → `dynamicPackages.server` + `.client` entries.
  2. `mj/packages/MJAPI/package.json` → dependency on `@mj-biz-apps/contracts-server`.
  3. `mj/packages/MJExplorer/package.json` → dependencies on `contracts-ng` + `contracts-entities`.
  4. Regenerate Explorer's manifest: `mj codegen manifest --exclude-packages @memberjunction
     --output ./src/app/generated/class-registrations-manifest.ts --open-app-client-bootstrap`
     (an empty manifest means step 2 or 3 is missing).
  5. `mjdev link <slug>` restores workspace membership, then `pnpm install` in the instance.
  6. Restart MJAPI — its GraphQL schema has no contracts resolvers until it reboots.

**Cost.** mjdev's per-app status flags are not updated, so `mjdev app list` under-reports what has
been migrated.

**Removing it depends on:** MJDev#28 and MJDev#29.

---

## W-3 · Metadata edits need an API restart before the UI reflects them

**Not carried in code** — a rule that looks like a broken change until you know it.

MJAPI caches entity metadata at boot. A change to `__mj.EntityField` settings — for example
`DefaultInView` in `metadata/entity-fields/`, applied with `mj sync push` — is correct in the database
immediately and **invisible in Explorer until MJAPI is restarted**.

Check the database value first, then restart before concluding anything. There is a second,
independent cache in the same area: the grid persists a per-user default column set as a
`__mj.UserSetting` row keyed `default-view-setting/<Entity Name>`, which pins columns for that user
regardless of metadata.

---

## W-4 · CodeGen's after-generation commands call `npm`

**Not carried in code** — tolerated.

**What breaks.** `mj.config.cjs` runs `npm run build` in each package after generation. In a pnpm
parent workspace npm cannot resolve the members, so CodeGen finishes generating and then exits 1 with
`COMMAND: "npm" FAILED`. Generation itself is complete; the build runs separately under pnpm. The
non-zero exit means CodeGen cannot be used as a script gate.

**Removing it depends on:** making those four commands package-manager-agnostic in `mj.config.cjs`.

---

## Fixed rather than worked around

- **CodeGen generated against every sibling app's schema**, not just this one, because
  `excludeSchemas` names what to skip and a linked workspace contains the siblings. Fixed in
  `mj.config.cjs` with `includeSchemas: ['__mj_BizAppsContracts']`, a positive opt-in scope.
