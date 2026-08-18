# Build state — contracts v2

**Purpose:** this file is the durable memory of the build. It survives context compaction, agent
handoff and machine restarts. **Update it at every phase boundary**, not just at the end.

**Last updated:** 2026-08-18, after item 3 (CodeGen) landed.
**Branch:** `build/contracts-v2` · **Draft PR:** MemberJunction/bizapps-contracts#9
**Instance:** `contracts-mj6` (parent-workspace / pnpm / MJ 6.1.0-edge.2 at `origin/next`)

---

## 1. Governing documents, in order of authority

1. `plans/bizapps-contracts-master.md` — the master plan. Decisions **D-1…D-23**, work items 1–14,
   §6 the composition/forms architecture, §6.6 caching.
2. `plans/ERD-planned.md` — the schema to build. **§9 is the reversal log (R-1…R-18)**: every ruling
   that changed the shape, with owner and date. Read it before changing any column.
3. `plans/QUESTIONS.md` — answer-first open questions. Proceed by default; do not stall.
4. `WORKAROUNDS.md` — what this build steps around and why. **Read before any clean-deploy claim.**
5. `plans/mj-storage-and-esignature-notes.md` — MJ platform capabilities for documents.

Both plan docs are already merged to `next` (PR #6), so `build/contracts-v2` builds *against* them.

---

## 2. Work items — status

| # | Item | Status |
|---|---|---|
| 1 | Retire v1; new baseline migration | ✅ **done**, verified from zero |
| 2 | Metadata: seeds, collection declarations, form chrome | ⏭ **NEXT** |
| 3 | CodeGen + entity packages | ✅ **done**, AI enrichment verified |
| 4 | Seed the provision list with `ProvisionText` | ⏭ after 2 |
| 5 | Contract list + detail screens | to do |
| 6 | Entity CRUD | to do |
| 7 | Agreement version registry | to do |
| 8 | Modifications editor (shared component, two hosts) | to do |
| 9 | Document handling | to do |
| 10 | Deal → Contract automation | ❌ **SKIP** — ruled out of scope; `bizapps-sales` does not exist |
| 11 | Customer view | to do |
| 12 | Renewal + expiry watchlist | to do |
| 13 | Migration of active contracts | ❌ **SKIP** — ruled out of scope; data pending from Andrew |
| 14 | Rewrite the README | **last**, after everything else |

Testing: the **MJ Testing Framework** (`mj test`) plus the repo's `test-harnesses/`. **No Playwright**
(ruled). Verify live in Explorer via `mjdev explorer-url contracts-mj6`.

---

## 3. THE CRITICAL ENVIRONMENT FACT

**mjdev's app-engine is broken against MJ 6 `next`** (MJDev#28): it calls `sdp.UserCache.Instance`, and
MJ moved `UserCache` into `@memberjunction/generic-database-provider`. So **`mjdev app migrate`,
`app codegen` and `app activate` all fail** with `Cannot read properties of undefined (reading
'Instance')`.

**Use each app's own MJ CLI script instead. This is the working loop:**

```bash
cd ~/MJDev/instances/contracts-mj6/bizapps-contracts
DOTENV_CONFIG_PATH=../mj/.env pnpm run mj:migrate     # mj migrate --schema __mj_BizAppsContracts --dir ./migrations
DOTENV_CONFIG_PATH=../mj/.env pnpm run mj:codegen     # AI enrichment ON (GeminiLLM key resolves globally)
```

Same pattern works for the sibling apps (`bizapps-common`, `-tasks`, `-accounting`, `-orders`).
`mjdev setup <slug> deps|build|migrate` (MJ core) **do** work — only the *app-engine* steps are broken.

### Ad-hoc SQL against the instance DB (verification)

`/private/tmp/claude-502/.../scratchpad/q.mjs` — reads `mj/.env`, imports mssql by absolute path from
`instances/contracts-mj6/node_modules/.pnpm/mssql@12.7.0/node_modules/mssql/index.js` (note: `index.js`,
**not** `lib/index.js`). Recreate it if the scratchpad is gone; it is verification-only, never committed.

```bash
node <scratchpad>/q.mjs "SELECT ... FROM __mj.Entity WHERE SchemaName='__mj_BizAppsContracts'"
```

---

## 4. What is actually in the database right now

- **7 tables** in `__mj_BizAppsContracts`, column counts: Contract 23, ContractTemplate 7,
  ContractTemplateProvision 7, ContractTemplateModification 5, ContractType 5,
  ContractTemplateType 4, ContractSequence 2 (+ `flyway_schema_history`).
- **7 entities** registered with the `MJ_BizApps_Contracts: ` prefix, 7 base views, **21 CRUD sprocs**,
  7 triggers, 12 FK constraints, 11 CHECKs.
- `IsNameField` resolved to `ContractNumber` (Contracts) and `ProvisionNumber` (Provisions) — proof the
  AI smart-field pass ran.
- MJ core + all four sibling apps migrated (common 12, tasks 4, accounting 2, orders 9).
- **No seed data yet** — contract types, template types and the MA provisions are all item 2 / item 4.

---

## 5. Gotchas already paid for — do not rediscover these

1. **`excludeSchemas` does not scope CodeGen.** It names what to *skip*, so a linked workspace makes
   CodeGen generate against every sibling app. Fixed in the committed `mj.config.cjs` with
   **`includeSchemas: ['__mj_BizAppsContracts']`** (a positive opt-in). Keep it.
2. **CodeGen exits non-zero even on success** because its AFTER commands shell out to `npm` in a pnpm
   workspace (W-3). Check for `✔ MJ CodeGen complete` in the output; **do not gate a script on the exit
   code.**
3. **An orders entity blocks CodeGen for everyone** until its API flags are off in the dev DB (W-2).
   The DB gets rebuilt regularly, which **restores the flags and re-blocks CodeGen** — re-apply:
   `UPDATE __mj.Entity SET AllowCreateAPI=0, AllowUpdateAPI=0 WHERE Name='MJ_BizApps_Orders: Event Order Lines'`
4. **Background `nohup` exit codes lie.** A completed task notification reported success while the
   install had actually failed with a 404. Always grep the log for `"success": true` / `error`.
5. **`git checkout -- .` in the MJ worktree is blocked** by the permission classifier; ask the user.
6. **Layered base views need TWO migrations** and the flags must exist before the first CodeGen, or
   CodeGen DROP/CREATEs the public view name and destroys the wrapper. Orders documents the trap in
   `V202608131541__…_layered_inner_view.sql`; the `UPDATE __mj.Entity` is keyed by entity **name** and
   skips cleanly when absent. **Not yet done for contracts** — `State`, `IsAwaitingDocument` and
   `IsChangeOrder` still need their wrapper.
7. **Push is allowed only to `build/contracts-v2`** (`Bash(git push origin build/contracts-v2:*)`).
   Commenting is permitted **only** on PR #9.

---

## 6. UI structure to build (ruled 2026-08-18)

Explorer gets a **top nav bar** with three sections:

- **Contracts** — the contracts view; create a contract; the **watchlist / dashboard** (the watchlist
  can serve as the dashboard); modifications shown through the contract entity; plus a **view-all-
  modifications** nav-rail tab (grid); plus a **worklist of contracts awaiting files**.
- **Templates** — templates view + edit (generated forms); provisions as **related records**; a
  **custom form for templates** so provisions are visible when viewing a template; plus an
  **all-provisions** tab (grid).
- **Configuration** — contract types, template types, and CRUD for the remaining entities.

Form architecture (D-15, D-17, D-22, D-23):
- `UI.Form.Layout = "left-nav"` with `RelatedRolePolicy: "smart"` and a `PrimaryRelatedBudget`, as
  orders sets on every entity. The rail **routes** — one section renders at a time.
- Related-record collections are **metadata-declared** (`EntityRelationship.RelatedRecordCollection`);
  never hand-write `DeclareRelatedRecords` for a schema relationship.
- The modifications editor is **one component with two hosts** — inline in the contract's panel
  (joining the parent's single `record.Save()`) and as the body of the modification's own custom form.
- **Grids and pickers select the BASE VIEWS**, so FK columns show names rather than UUIDs.
- Mockups to build to: `design-docs/ui-design/mockups-v2/` (`contract-form.html` is clickable —
  the rail routes; `modifications-editor.html`; `renewal-watchlist.html`).

---

## 7. Immediate next actions, in order

1. **Item 2 — metadata.** Replace the v1 seeds in `metadata/`: delete the five remote-operation
   definitions + their 10 type files + the category (v2 has **no** remote operations, §6.3), rewrite
   `contract-types/` for the new vocabulary (Order Form / Statement of Work / Payment Link / Change
   Order, with `RequiresExecutedDocument`), add `contract-template-types/` (Master Agreement /
   Statement of Work), declare the two related-record collections, and add form chrome
   (`Layout: left-nav`).
2. **Item 4 — seed the MA provisions** with `ProvisionText`. Prerequisite for the modifications
   editor: with the provision FK mandatory, finance cannot record a modification until the clause
   list exists.
3. `pnpm run build` (from the instance dir for filters), then `mj sync push` for the metadata.
4. **Item 5/6** — screens and CRUD; then 8, 7, 9, 11, 12, then tests, then 14.
5. Comment on PR #9 at each phase boundary so the reviewing agent can course-correct.

---

## 8. Reporting protocol

Every response is bracketed with a task header at top and bottom naming batch+letter, a short
descriptive name, the branch and the instance. Test results are reported exactly as they happened —
pass is pass, fail is fail with output, not-run is not-run.
