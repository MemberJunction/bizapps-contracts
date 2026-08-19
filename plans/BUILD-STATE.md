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

## 2. Work items — status (updated 2026-08-19, after items 1–7 + 11–12)

| Item | State | Evidence |
|---|---|---|
| 1 Retire v1 + baseline | **DONE** | from-zero: 8 views, 21 sprocs, 7 entities, 77 fields, 6 derived cols |
| 2 Metadata | **DONE** | `mj sync push` errorCount 0; collections emit `DeclareRelatedRecords` |
| 3 CodeGen + entity classes | **DONE** | 3 hand-written classes; 64 unit tests |
| 4 Provision seed | **DONE** | 71 provisions, 0 missing text, Sequence 1..71 contiguous |
| 5 List + detail | **DONE (code)** | 3 grid pages + 4 contract panels; NOT yet rendered in a browser |
| 6 Entity CRUD | **DONE (code)** | 3 configuration pages over generated base views |
| 7 Version registry | **DONE (code)** | versions + all-provisions pages, provisions editor panel |
| 11 Customer view | **DONE (code)** | Organization agreements panel + chrome metadata |
| 12 Watchlist | **DONE (code)** | layered view + 6 derived cols + renewals page |
| 8 Modification capture | **DONE (code)** | shared editor, 2 hosts (D-22); inline panel + custom form |
| 9 Document handling | **NOT STARTED** | `record-files.panel.ts` carried forward, upload/register unfinished |
| 14 README | **NOT STARTED** | last by design |
| 10, 13 | **SKIPPED** | ruled out of scope by Marcelo |

**The honest gap:** everything marked DONE (code) compiles and is committed; **as of this
line nothing has been confirmed rendering in a browser.** Explorer was starting when this
was written. Do not describe the UI as working until you have seen it.

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

---

## 9. Open-app registration is HAND-WIRED here (read before touching it)

`mjdev app register` CANNOT be used on this instance. Its engine leg dies on MJDev#28
(`UserCache.Instance`) and **its rollback DELETED the entire app worktree** — filed as
**MJDev#29**. Recovery was `git worktree prune && git worktree add
/Users/marcelotorres/MJDev/instances/contracts-mj6/bizapps-contracts build/contracts-v2`,
lossless only because everything was committed and pushed. **Commit before running any
mjdev app command.**

So registration is hand-written, and these are the four things that make the app visible:

1. `mj/mj.config.cjs` → `dynamicPackages.server` (`@mj-biz-apps/contracts-server`,
   StartupExport `LoadMjBizappsContractsServer`) and `.client` (`contracts-ng`,
   `contracts-entities`). Marked with an `MJDEV-MANAGED REGION` banner explaining why it is
   hand-written. Shape copied from `instances/orders-mj6-ws`, which mjdev generated.
2. `mj/packages/MJAPI/package.json` → dependency on `@mj-biz-apps/contracts-server`.
3. `mj/packages/MJExplorer/package.json` → deps on `contracts-ng` + `contracts-entities`.
4. **The Explorer manifest must be regenerated** or none of it loads:
   ```bash
   cd ~/MJDev/instances/contracts-mj6/mj/packages/MJExplorer
   DOTENV_CONFIG_PATH=../../.env pnpm exec mj codegen manifest \
     --exclude-packages @memberjunction \
     --output ./src/app/generated/class-registrations-manifest.ts \
     --open-app-client-bootstrap
   ```
   Expect "19 classes from 2 packages" and "2 client packages wired". An EMPTY manifest
   ("0 packages contain @RegisterClass") means the host deps or dynamicPackages are missing.

⚠ `mjdev link <slug>` re-adds workspace membership (the rollback strips
`bizapps-contracts` from `pnpm-workspace.yaml`) and is safe. `pnpm install` at the
INSTANCE dir after that.

## 10. Verification method — do NOT grep build output

I reported "all six packages build clean" from
`pnpm ... run build 2>&1 | grep -E "error TS|error NG"` and it was FALSE. Two independent
reasons: turbo **caches** tasks, so a package that once built reports nothing on a later
broken run; and Angular's NG-prefixed template errors did not all match the pattern. A
filter that can only produce a false GREEN is not a check.

**Use the exit code**, which is what CI uses:
```bash
cd ~/MJDev/instances/contracts-mj6/bizapps-contracts
pnpm run build; echo "EXIT=$?"     # must be 0, "6 successful, 6 total"
./packages/Angular/node_modules/.bin/vitest run --config vitest.config.ts   # 64 passing
```
The instance workspace does not install the app root's own devDependencies, which is why
vitest is invoked through the Angular package's binary.

## 11. Angular gotchas already paid for

- `ExplorerEntityDataGridComponent` is **not standalone** — import `BaseFormsModule`, never
  the component (NG2011).
- A custom form MUST declare `public record!: <EntityType>` — `BaseFormComponent` declares it
  abstract (TS2515).
- Page mounting uses `setTimeout`, **never `queueMicrotask`** — a microtask drains inside the
  current CD pass, so an async `ngOnInit` resolves between check and verify → NG0100, which
  aborts the update with nothing scheduling another tick. Symptom is a screen frozen on its
  pre-fetch render (orders saw a dashboard of zeroes against a full database).
- The styles kit ships via `styleUrls` + `ViewEncapsulation.None` on the section shell. A
  stylesheet nothing references is compiled into dist and never loaded by a real Explorer.
- No `toolbar` slot in the shell: a wrapper div defeats MJ's `:empty` rule and costs ~29px of
  dead header on every section, forever.
- `mj-page-body-interior` is REQUIRED inside `mj-left-nav-content` or content past the fold is
  unreachable (a `::ng-deep` child rule forces `overflow:hidden`).

## 12. Decisions added after the plan merged

D-24 (validation ladder), D-25 (provider scoping — bare `new RunView()`/`new Metadata()` is a
defect; helpers in `packages/Angular/src/lib/data/provider.ts`), D-26 (correlated writes share
one transaction), R-19 (`State` has SIX values; `Executed` = signed-not-yet-effective).
