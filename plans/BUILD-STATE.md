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

## 2. Work items — status (updated 2026-08-19 late, all requested items done in code)

| Item | State | Evidence |
|---|---|---|
| 1 Retire v1 + baseline | **DONE** | from-zero: 8 views, 21 sprocs, 7 entities, 77 fields |
| 2 Metadata | **DONE** | push errorCount 0; collections emit accessors |
| 3 CodeGen + entity classes | **DONE** | 3 classes; 72 unit tests |
| 4 Provision seed | **DONE** | 71 provisions verbatim, 0 missing text |
| 5 List + detail | **DONE**, list PROVEN in browser | 7 rows, names not UUIDs, State column |
| 6 Entity CRUD | **DONE**, proven | configuration pages render |
| 7 Version registry | **DONE**, proven | versions + provisions pages render |
| 8 Modification capture | **DONE (code)** | editor + 2 hosts; **panel not yet seen rendering** |
| 9 Attachments | **DONE** | MJ stock attachments on the form; custom `RecordFilesPanelBase` removed. Upload still needs a storage account. |
| 11 Customer view | **DONE (code)** | Organization panel; **not yet seen rendering** |
| 12 Watchlist | **DONE**, proven | renewals page + all 6 derived columns verified against data |
| 14 README | **DONE** | 658 v1 lines → 227 describing what shipped |
| 10, 13 | **SKIPPED** | ruled out of scope |

### What is PROVEN in a browser vs only compiled

**Proven** (system Chrome, logged in, zero console errors): all three sections; the Contracts rail
with badges; the dashboard with non-zero counts; the contract LIST with 7 rows showing names and the
derived `State`; renewals; awaiting-documents (and the Payment Link correctly ABSENT from it); the
modifications page; templates; all-provisions; configuration. **The contract FORM opens** (after the
`(Navigate)` fix).

**Also proven (2026-08-19, screenshot in `design-docs/ui-design/contract-form-rendered.png`):** the
contract FORM and its panels — hero (`Active` chip, `Modified` flag, customer + date strip), the FK
fields rendering as names, the renewal panel with its "as stated in the agreement" framing and the
DERIVED notice deadline, and the modifications panel showing provision 9.1's standard clause in its
original ALL CAPS beside the negotiated language. Zero console errors.

**Also proven:** the New-record flow — the toolbar's New opens a blank contract form; the hero derives
`Draft` and shows "Unnumbered" with its numbering explanation; the renewal and documents panels render
their EMPTY states (including "no storage account is configured"); and **saving without the required
foreign keys is refused with per-field messages** — validation rung 1, observed, with nothing written
and the sequence NOT consumed.

**Still NOT proven — a SUCCESSFUL save, and here is exactly how far the attempts got** so the next one
does not start over:

1. **Through the form:** blocked only by FK dropdown automation. The form opens, refuses correctly, and
   the create-path blocker is fixed — so a HUMAN can now do this in the UI. Try that first; it is
   probably five minutes by hand and it is the truest proof.
2. **Through MJAPI GraphQL** (mutation `CreatemjBizAppsContractsContract`, input type confirmed, no
   `ContractNumber` supplied — the right shape for testing the minting): blocked by
   **API key scopes**. `mjdev key` mints a key without `entity:create`, the mutation returns
   `Access denied … requires the 'entity:create' scope`, and mjdev exposes no command to grant it.
   Granting it means editing MJ's key-scope rules directly. That is the blocker to solve, and it is
   worth solving once because it unlocks scripted write tests generally.
3. **Through metadata sync:** cannot test minting at all — `ContractEntityServer` is not loaded in the
   CLI process, which is why `demo-data/` supplies explicit numbers.

What remains unobserved, precisely: `ContractNumber` minted by the server, and D-15's header + rows
committing in one transaction. Everything about the READ path and the refusal path is observed.

Also unproven: item 9's document actions (register/open need a configured storage account, which
needs an Azure AD app registration — an IT task), item 11's Organization panel, and **no WRITE path has
been executed through the UI**: nothing has created or saved a contract in the browser, so the
one-transaction graph save (D-15) and the CTR numbering remain runtime-unverified. That is item 13's
job and it is the honest remaining gap.

**One cosmetic gap:** the form's rail shows `Details` + `More` rather than six named sections, and the
hero renders ABOVE the Details fields rather than replacing them — `replacesSectionKey: 'details'` did
not take. Everything is visible and usable; it is a chrome refinement, not a defect.

⚠ **Two of my own passing assertions were false positives**, both from matching text present for the
wrong reason: "form opened" matched a grid row, and 11/11 checks passed while the grid rendered ZERO
rows. **Text assertions cannot see layout or context.** Look at the screenshots.

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

---

## 13. Running the app (the exact sequence, all of it hard-won)

```bash
# 1. services
cd ~/MJDev && ./bin/mjdev run contracts-mj6 api --wait
./bin/mjdev run contracts-mj6 explorer          # ~5 min first compile

# 2. a logged-in URL
./bin/mjdev explorer-url contracts-mj6 | grep -oE 'http://localhost:[0-9]+/#token=\S+' > /tmp/mjcurl.txt

# 3. render check (needs both services up)
cd instances/contracts-mj6/bizapps-contracts && node test-harnesses/render-check.mjs
```

**MJAPI must be restarted after any change to `mj/mj.config.cjs` `dynamicPackages`** — otherwise its
GraphQL schema has no contracts resolvers and the form fails with
`Cannot query field "mjBizAppsContractsContract" on type "Query"`. Use `mjdev restart`, never `run`
(on a live target `run` is a no-op). MJAPI's **prestart regenerates its own manifest and may ADD
dependencies to its package.json**, printing "run npm install at repo root" — when it does, run
`pnpm install` at the INSTANCE dir and restart again, or the API crashes with an opaque
`[Object: null prototype] {}`.

## 14. Demo data

`demo-data/` (outside `metadata/`, never shipped). Push it with:

```bash
DOTENV_CONFIG_PATH=../mj/.env pnpm exec mj sync push --dir demo-data --format=json
```

8 contracts + 4 orgs + 1 company + 2 modifications, chosen so every derived `State` and every worklist
has content. Verified: CTR-900001 Active(+2 mods) · 900002 Active(notice passed) · 900003 **Executed**
· 900004 Active(awaiting doc) · 900005 Active(Payment Link, NOT awaiting) · 900006 Expired ·
900007 Draft · 900008 Active(Change Order).

**Dates are absolute around 2026-08-19.** Read much later the states drift — that is the derivation
working, not the data rotting.

## 15. If you are picking this up cold — do these first

1. **Confirm the contract form's panels render.** Open CTR-900001 (double-click in All contracts) and
   check the hero, renewal ("as stated in the agreement"), modifications (standard clause beside the
   negotiated text), lineage (the change order), documents. This is the last unproven surface.
2. If a panel is missing, suspect the **left-nav layout** first (D-17 routes: only the active rail
   section renders) before suspecting registration.
3. `mjdev app register` DESTROYS the app worktree on failure (MJDev#29). **Commit before any mjdev app
   command.**

---

# UI SESSION (2026-08-19) — read this before touching any form or stylesheet

Marcelo reviewed the running app and rejected most of the UI. Everything below is either a fix that
landed or a fact that cost real time to establish.

## 16. MJ form chrome — the three rules that made the rail work

The rail DOES support many named sections; my implementation was wrong three ways at once. All of this
is in `mj/guides/FORMS_ARCHITECTURE_GUIDE.md` §7d and `base-forms/PANELS.md` — **read them in full, do
not grep them.** Grepping is how I missed this for hours.

1. **Field panels collapse into one `Details` rail item BY DESIGN.** Named rail entries come only from
   Primary **contributions** and Primary **related grids** — never from generated field sections. The
   generated Contract form declares nine perfectly good sections and left-nav shows none of them.
2. **`contributionKey` MUST equal the panel's own `SectionKey`.** The container resolves inclusion by
   `contributionKey` (`contributionRailKey`) but builds rail groups from the rendered panels'
   `SectionKey` (`BuildDefaultChromeSpec` over `visiblePanels`). Mismatched, `Primary` is computed and
   attaches to nothing, so the panel folds into Details.
3. **A panel whose own `SectionKey` equals its `replacesSectionKey` HIDES ITSELF** — the replacement
   adds that key to `HiddenSectionKeys`, which filters out the panel. This deleted the Dates and
   Renewal sections from the form entirely.

Also: a panel with **no** `contributionKey` and no `relatedEntity` returns null from
`contributionRailKey()` and chrome skips it — it can never be a rail item however it is configured.
That was Documents.

**Band order is FIXED: lead contributions → Details → Primary related → More.** A Primary contribution
is *always* a lead (`isLeadContribution` requires `inclusion === 'Primary'` and no `chromeGroup`), so
there is no way to have a contribution keep a first-class rail item *and* sit after Details. To order
Details ahead of something, that something must be `chromeGroup: 'more'` (or not Primary).

`FormChromeGroup` is one rail ITEM (`{Key, Title, Icon, SectionKeys, IsMore, IsLead}`) — **there is no
rail group-header concept.** The mockup's "Sections / Related / More" headings are not expressible;
the grouping they imply falls out of the band order anyway.

⚠ `Layout: 'accordion'` was set briefly as a workaround and REVERTED. It treats the symptom. D-17's
`left-nav` stands.

## 17. Design tokens — semantics only, and the trap

MJ's rule (`mj/.claude/rules/design-tokens.md`): **"NEVER use primitive tokens
(`--mj-color-neutral-*`, `--mj-color-brand-*`) in component CSS. Primitives don't adapt to dark
mode."**

`contracts-kit.css` had twelve, ported verbatim from the mockup's `tokens.css` — harmless in a
standalone page, a full theming break in a component stylesheet. Fixed; the mapping is written in the
file header. **Zero primitives and zero hex now remain in shipped source.**

Two traps worth keeping:

- **Hex fallbacks inside `var()` are worse than no fallback.** `var(--mj-text-muted, #64748b)` renders
  the hex the moment the token name is wrong, silently pinning a light colour into a dark theme.
  `record-files.panel.ts` had seven.
- **A misnamed token fails SILENTLY.** An earlier kit used `--mj-font-size-sm`, `--mj-text-tertiary`,
  `--mj-color-warning-text` and five others that do not exist — so every font size fell back to browser
  default and the chips had no colour. **Check a token exists before using it:**
  `grep -c -- "--<token>:" mj/packages/Angular/Generic/shared/src/lib/_tokens.scss`

## 18. The grid has NO filter UI — I was wrong about this

I told Marcelo the grid already had filtering via `ToolbarConfig.showFilterToggle`, having read it in
`GridToolbarConfig`. It does not. Verified in
`mj/packages/Angular/Generic/entity-viewer/src/lib/entity-data-grid/` — **four half-built or disabled
hooks, no filter UI anywhere:**

| Hook | Where | State |
| --- | --- | --- |
| `ToolbarConfig.showFilterToggle` | `models/grid-types.ts:249` | declared + in the README; **read nowhere**. No template branch renders a filter button. |
| `AllowColumnFilters` input | `entity-data-grid.component.ts:554-561` | setter/getter stores `_allowColumnFilters`; **read nowhere else**. Dead input. |
| `_filterState: FilterState[]` | `entity-data-grid.component.ts:1511` | declared; never read or written. |
| `defaultColDef.filter` | `entity-data-grid.component.ts:1457` | **hardcoded `false`** — AG Grid per-column filters off, and no input flips it. No `floatingFilter`, no `filterParams`. |

**What the grid DOES have** is the `ShowSearch` box (`entity-data-grid.component.html:12-29`), which
sets AG Grid `quickFilterText` (`onFilterTextChanged`, `:2193`) — a **client-side substring match over
the rows already loaded**. It is not structured filtering and it is not server-side, so it cannot
answer any of the mockup's ten questions.

So the pages pass `showFilterToggle: true` and it does nothing. Options: build the filter popover the
mockup draws (`mockups-v2/renewal-watchlist.html` specifies ten named filters) in our own page chrome,
which we own; or file it upstream on MJ. **Do not tell anyone the stock grid can filter.**

## 19. Sibling apps are ALL wired now (they were not)

Hand-wiring registration for contracts only meant no other app's forms existed in the bundle — the
symptom was `No form is registered for "MJ_BizApps_Common: People"` and it would hit any cross-app
click. All five apps (common, tasks, accounting, orders, contracts) are now in `dynamicPackages`
(dependency-ordered) and in both host `package.json`s. Manifest went **19 classes / 2 packages → 170 /
12**.

⚠ **`bizapps-orders` had a stale exact pin**: `@mj-biz-apps/common-ng` and `common-entities` at
`5.33.2` while the local sibling is `5.34.0`, so pnpm resolved a *published registry copy* predating
two exports orders imports. Healed to `5.34.0` in orders' working tree — **UNCOMMITTED, and it is
another repo.** Backup: `/tmp/orders-ng-pkg.bak`. This is what `app register --heal-pins` exists for.

## 20. THE WRITE PATH IS PROVEN

`CTR-000001` was created through the UI by Marcelo. The server minted the number
(`ContractSequence.NextSequenceNumber` advanced 1 → 2) and `State` derived as `Executed`. That closes
the last gap §15 listed as unproven.

## 21. Still open (UI)

- **Filter UI** — nothing exists; see §18.
- **Modifications panel vs mockup 2** — the table + click-to-expand pair and the searchable picker with
  the **modified text pre-filled from the standard clause** are written but NOT verified on screen.
- **Overview lead panel** — written but NOT applied. It replaces `details` and would put Overview
  first in the Contract rail (MJ's own comment says *"Overview is the usual case"* for a lead).
- **Watchlist countdown columns** (mockup 3: "in 41 days" + progress bar, "overdue by 19 days").
- **Stale generated-field noise** — `IncludeInGeneratedForm: false` pushed for 8 fields
  (`RootParentContractID`, `RootSupersededByContractID`, and the six derived columns) but the Explorer
  had not picked it up when last seen.
- **Date fields render with a time** (`10/17/2026, 7:00:00 PM`) on `date` columns.
- **Template rail** — set to Details → Provisions → More(Documents); needs an API restart to confirm.

## 22. Restart discipline (costs 10 minutes each time it is forgotten)

A metadata push does NOT reach the running app. `mjdev restart contracts-mj6 api`. If MJAPI dies with
an opaque `[Object: null prototype] {}`, its prestart added dependencies to its own `package.json` —
run `pnpm install` at the INSTANCE dir and restart again. Explorer caches entity metadata at load, so
field-visibility changes need it restarted too.

## 23. Modification CRUD, and why the form was a blank spinner (2026-08-19)

Marcelo opened a modification and got one line — "Loading the contract this modification belongs
to…" — and no fields. Three separate causes, fixed and each verified in a real browser.

### 23.1 The form: a priority-2 override was shadowing a better generated form

`custom/modification.form.component.ts` replaced the whole form with a shell that loaded the PARENT
contract, then rendered `mjc-modification-editor` against `contract.Modifications`. The parent load
never completed the render, so the form had no fields, no dropdowns, no way to save.

**Deleted rather than debugged**, because the generated form is strictly better here — and this is
the reusable lesson: **replacing a form costs you every generated affordance.** CodeGen already
emits `ContractID` and `ContractTemplateProvisionID` with `LinkType="Record"`, which `mj-form-field`
renders as **searchable FK dropdowns** (a result grid with sortable columns and a "Create …" row),
plus a `Modification Details` section for `ModificationText` + `Notes` and `System Metadata` under
More. That is exactly what Marcelo asked for — "very similar to creating a provision" — and it is
what a form REPLACEMENT threw away. Reach for a panel unless you mean to replace all of it.

The editor component stays: it is still the contract form's inline Modifications panel. Its
`SingleRowMode` / `OnlyModificationID` inputs are now set by nobody (the deleted form was the only
host) — harmless, but do not go looking for their caller.

**Verified end to end**, not just rendered: created a modification through the UI — picked
`CTR-900002` and provision `9.1` in the dropdowns, typed the clause, saved — and confirmed the row in
SQL (`100F1188-…`, CTR-900002 / 9.1) with `Contract.HasModifications` flipped `true` by the server
subclass. 0 console errors throughout.

### 23.2 FK links looked clickable and were inert — an MJ wrapper gap

The grid emits `ForeignKeyClick`; `mj-explorer-entity-data-grid` never binds it and declares no
equivalent, so the event dies in the wrapper. **Every FK link in every wrapper-hosted grid is
dead.** Fixed app-side with `lib/directives/fk-navigate.directive.ts` (`mjcFkNavigate`) on all 9
grid tags across 5 files — it injects the wrapper, subscribes to the inner component's own `@Output`,
and navigates via `NavigationService.OpenEntityRecord` with a `CompositeKey` built from the related
entity's real primary-key field name. Full write-up + how to delete it: `plans/WORKAROUNDS.md` → W-1.
**File upstream.**

Verified: clicking the `CTR-900002` link on the Modifications grid opens that contract's form (hero
card, dates strip, full rail).

### 23.3 The raw-UUID columns are STILL THERE, and hiding them is a real trade-off

The Modifications grid shows four link columns, two of them bare UUIDs. Those two are the FK fields
themselves — MJ derives an FK field's DisplayName by dropping `ID`, so `ContractID` presents as
"Contract". The readable ones are the app's virtual `Contract` / `ContractTemplateProvision` fields
(DisplayName "Contract Reference" / "Provision Reference").

I hid the UUID pair with a migration setting `DefaultInView = 0` (the grid picks default columns by
that flag — `shouldShowField`, which is `field.DefaultInView === true`). It worked: two clean
columns. **It also killed every link on the page — 12 anchors to 0.** The reason is the pairing
mechanism: a virtual display field links to its FK partner found BY NAME CONVENTION (`Contract` +
`ID`, `:2773`) and reads the target id from **`params.data[fkField.Name]`** (`:2823`). Hide the FK
column and that lookup returns `''`, so the readable cell degrades to plain text. Adding
`Params.Fields` to keep the ids in the payload did **not** restore the anchors (measured).

**So I reverted it** — migration deleted, flags back to `1`, the `flyway_schema_history` row removed
— because losing click-through is worse than two ugly columns, and click-through is what Marcelo
actually asked for. Getting both wants either a `[Columns]` input on the wrapper (it has none) or an
MJ fix. **This is a decision for Marcelo, not a bug to grind on.**

### 23.4 Two caches that make metadata work look broken

MJAPI caches metadata at boot: a `__mj.EntityField` change is right in SQL and invisible in Explorer
until `mjdev restart <slug> api`. Independently, the grid persists a per-user default column set as
a `__mj.UserSetting` row keyed `default-view-setting/<Entity Name>`, which pins columns for that
persona regardless of metadata. Check the DB value, then restart, before concluding a migration
failed. (`plans/WORKAROUNDS.md` → W-3.)

### 23.5 Things I broke and put back

- **Ran `mj codegen manifest` from the MJ root.** It regenerated the wrong manifest (973 classes/91
  packages) and **added 91 dependencies to the MJ root `package.json`**. Reverted both files; the
  legitimate dev-link wiring in `packages/MJAPI|MJExplorer/package.json` was left alone. The correct
  invocation is the root script `mj:manifest:explorer` (`--appDir ./packages/MJExplorer --output
  ./packages/MJExplorer/src/app/generated/… --lazy-config …`), which yields 145 classes / 9 packages.
  Deleting an exported class REQUIRES this regen — the Explorer build fails on the stale import.
- **`accounting-ng` contributes 0 classes to that manifest**, and that is not a break: its classes
  are not exported from its `public-api`, so the scanner skips them (it reports 128 such skips) and
  the package self-registers through its own bundled manifest.
- **The proof row's Notes** said "Recorded through the UI to prove modification CRUD end to end",
  which would read badly in a demo; reworded to realistic business text rather than deleted, since
  deleting the row would leave `HasModifications` set on CTR-900002 (the server subclass computes it
  on save, not on delete).

### 23.6 Corrections to §18 and to the page docblocks

§18's evidence was imprecise ("the grid template has zero occurrences of filter" — false, the search
box is there). Rewritten with line references, and it now names **four** dead hooks, not one:
`showFilterToggle` (`grid-types.ts:249`, read nowhere), the `AllowColumnFilters` input
(`:554-561`, stored and never read), `_filterState` (`:1511`, never touched), and
`defaultColDef.filter` **hardcoded `false`** (`:1457`). The same wrong claim was copy-pasted into
five docblocks across four page files ("MJ's grid ALREADY has a filter toggle…") — all replaced with
the measured truth. `modifications.page.ts` also declared `GridToolbar` and never bound it; now bound.

**Root runner note:** the canonical test command is `npx vitest run` from the app root — 75/75, exit
0. `npm test` (turbo, `--filter=@mj-biz-apps/contracts-*`) fails with "Could not find task `test`"
in this parent-workspace topology; pre-existing, unrelated to this work. `pnpm -r run test` is now
green (the Angular package's `vitest run` had no specs and exited 1; it is `--passWithNoTests` so the
runner stays wired for when specs land).

## 24. The state divergence, and the test that can see it (2026-08-19, fast-follow)

`build/contracts-v2` merged as PR #9 with a KNOWN divergence, disclosed at the time: TypeScript said a
contract terminated today or tomorrow was `Active`; the view said `Terminated`. Fixed on
`fix/contract-state-view-agreement`.

**The boundary is `< today`, and it is contract law, not preference.** A period ending on a date runs
through the END of that date — "terminating on 31 December" is in force all of 31 December. So
terminated-today is still in force today and reads Terminated tomorrow, matching how `EndDate` is
already treated. A `date` column carries no time, so end-of-day is the only reading available. My
earlier `<=` recommendation was WRONG and Marcelo's `<` was right.

**Why the guard failed, which is the durable lesson.** `StateSQL()` compares TEXT, so a change on the
TypeScript side alone left it green — 77 tests passed while the two implementations disagreed. Text
cannot detect a semantic split. The replacement is `test-harnesses/state-equivalence.mjs`
(`npm run test:state`): it scores rows through the DEPLOYED view and through the function, over live
data and then over its own fixtures covering all six states plus terminated yesterday/today/tomorrow.
It asserts **three** things per fixture — view, function, and the expected answer — because two
implementations agreeing on a wrong answer is what a text comparison blesses. **Proven to fail:**
restoring the old predicate makes it exit 1 naming both boundary rows.

**Two harness defects found on the way in — the committed suite was UNRUNNABLE, not just thin.**
`dotenv`/`mssql` were imported by `integration.mjs` and declared in no manifest; and its `.env` path
counted four directories up, correct for the pre-6.x nested layout but resolving to `~/MJDev` under
the parent-workspace topology — where dotenv silently loads nothing, `DB_PORT` stays undefined, and it
dies with "Failed to connect to localhost:1433", which reads like Docker being down. Both scripts now
share `test-harnesses/load-env.mjs`, which walks up and asks the filesystem.

**Mechanics worth remembering:** applying a view by hand needs the **CodeGen** credentials (MJ_Connect
gets error 3701 on ALTER) and BOTH placeholders substituted (`${flyway:defaultSchema}` **and**
`${mjSchema}`). Declaring deps means refreshing `pnpm-lock.yaml` via `pnpm install --lockfile-only` in
a THROWAWAY CLONE and copying it back — `lockfile-covers-manifests.test.ts` caught the omission, which
is the third time that test has earned its keep.
