# bizapps-contracts — testing ledger

The running record of what is covered, what is not, and what needs a person. Coverage is measured
against the **matrix**, not against the tests that happen to exist — an empty box is a gap even when
every written test is green.

> **Last unit run:** 2026-10-11, `origin/next` at `f5bef7e`. `pnpm run build:packages` exited 0 on
> all 6 packages, then `pnpm run test:unit`: **29 files, 407 tests, all passing.** Run without the
> build first, 4 of the 29 files fail to load: they import `@mj-biz-apps/contracts-entities` through
> its built `dist/`.
>
> **Nothing that needs a database or a browser was re-run on that date.** Those entries keep their
> last recorded result and date: from-zero install, metadata push and first render 2026-08-18; live
> GraphQL and SQL probes 2026-08-20; browser checks of the stock grids and the lineage tree
> 2026-08-21; the integration bundles 2026-08-31, when they landed. Where something was not run, it
> says so.
>
> ⚠ **This ledger was reset with the v2 rebuild.** The previous version claimed *296 assertions
> across four tiers* — 52 tier-1, 101 tier-2 tsx, 48 integration, 95 tier-5 Playwright. Those numbers
> were true when written and are now meaningless: they tested the v1 ten-table billing schema, and
> every table they asserted against has been dropped. The harnesses were deleted rather than edited to
> pass, because a test whose subject no longer exists is not a test. `test-harnesses/README-ui.md` and
> the seven retired browser harnesses went with them.
>
> **Playwright is out of scope for v2** (ruled 2026-08-18). Browser coverage, when it comes, goes
> through MJ's own integration testing framework (`mj test`), not a parallel Playwright suite.

---

## How to run it

```sh
# Build first, as CI does: four test files import @mj-biz-apps/contracts-entities through its dist/.
pnpm run build:packages

# Unit — no database, no provider. From the app root:
pnpm run test:unit                 # vitest run, root config, packages/*/src/**/*.test.ts

# The instance workspace does not install the app root's own devDependencies, so in a dev-linked
# instance invoke the binary the Angular package already has:
./packages/Angular/node_modules/.bin/vitest run --config vitest.config.ts
```

Everything below except `render-check.mjs` needs a database and the instance `.env`, which
`test-harnesses/load-env.mjs` finds by walking up from `test-harnesses/`. Run from the app root.
"Built packages" means `pnpm run build:packages` has run: these harnesses import
`@mj-biz-apps/contracts-entities`, `@mj-biz-apps/contracts-core-entities-server` and (integration
only) `@mj-biz-apps/contracts-integration-tests`, each of which resolves to its `dist/`.

| Command | What it checks | Also needs |
|---|---|---|
| `pnpm run test:state` | `State` and `NonRenewalOutcome` through the deployed `vwContracts`, with raw-SQL fixtures at each date boundary | bizapps-common's `fnBusinessToday()` |
| `pnpm run test:parent-rule` | `MustBeChild` / `MustBeRoot` gate `ParentContractID`, through `BaseEntity` saves | built packages; the seeded contract types |
| `pnpm run test:integration` | every integration bundle. `node test-harnesses/integration.mjs <bundle>` runs one, `<bundle>.<checkId>` one check. `contracts-world` commits rows; the rest roll back | built packages |
| `node test-harnesses/contract-number-mint.mjs` | the server mints a `CTR-` number when none, or a blank, is supplied | built packages; one top-level contract that has a template |
| `node test-harnesses/supersede.mjs` | `Supersede()` then `Save()` persists `SupersededByContractID`, then clears it again | built packages; two top-level contracts of one customer, neither superseded. Prints `PERSISTED` or `NOT PERSISTED` and exits 0 either way |
| `npx tsx test-harnesses/erd-schema-diff.ts` | the `docs/ERD.md` diagrams against `sys.columns`; read-only | `tsx` is not a devDependency, so `npx` downloads it |
| `node test-harnesses/render-check.mjs` | ad hoc, not part of the suite: the app renders and shows data | MJAPI and Explorer running, a magic-link URL in `/tmp/mjcurl.txt`, system Chrome. Its Playwright import is an absolute path on one developer's machine; point it at a local Playwright install first |

The integration bundles, and what each covers, are listed in
[`packages/IntegrationTests/README.md`](packages/IntegrationTests/README.md#current-state).

---

## Coverage matrix

| Area | Unit | Integration | Notes |
|---|---|---|---|
| `State` derivation, all six branches | ✅ 17 | — | checks the newest migration that defines `vwContracts` against branches and a precedence written in the test. Whether the SQL evaluates that way, R-19 and both sides of each date boundary included, is `pnpm run test:state` (database) |
| ClassFactory resolution, all 6 entities | ✅ 16 | — | plus 8 assertions that no v1 entity name still resolves |
| Self-reference guard — structure (MJ#3984 workaround) | ✅ 6 | ✗ | Source-level, like `migration-conventions`. Pins that the guard EXISTS, covers **both** axes, compares by value (`UUIDsEqual`), has no early return deferring the rule elsewhere, and runs before the two guards that skip the self case. Its behaviour still needs the server tier. Delete alongside the guard when MJ#3984 lands. |
| Lineage tree renders + navigates (MJ `mj-hierarchy-tree`) | — | — | Browser check, 2026-08-21: tree mounted, 23 nodes, active record highlighted, per-node open-record affordance, hand-rolled table gone. Logs 4 transient SVG `translate(NaN,NaN)` errors on first layout (measures before the panel has dimensions) — renders correctly after; MJ's, not ours. |
| Provisions via MJ's stock related-entity grid | — | — | Browser check, 2026-08-21: 19 AG rows of 73 (virtualized, internal scroll), custom panel absent. Replaced a hand-rolled table that CSS-clipped at 800px with no scrollbar. |
| Modifications via MJ's stock related-entity grid | — | — | Browser check, 2026-08-21: 1 grid, 2 rows matching the contract's two modifications, zero console errors; bespoke editor absent. |
| Same-level supersession — `IsSameContractLevel` (C-US9) | ✅ 7 | ✗ | the pure predicate: both-null is the SAME level, one-null is not, UUID casing ignored, two children of different parents refused. The three cases a plain nullable compare gets wrong are each pinned. |
| Same-level supersession — the server guard `refuseCrossLevelSupersession` | — | ✗ | **a real gap.** Needs an entity instance against the DB (one read of the successor's `ParentContractID`). The predicate above is covered; the *wiring* — that `ValidateAsync` calls it, gates on `isNewlySelected`, and returns the prose — is not. |
| Re-papering write path — the `Contracts.Supersede` operation (C-US9) | ✅ 11 | ✗ | against a fake provider: linking adds, releasing clears only the contract named, and a call naming neither, both or itself is refused. No bundle drives the operation against a database; `test-harnesses/supersede.mjs` drives `Supersede()` + `Save()` on a real one, and no run of it is recorded here |
| `HasModifications` monotonic guard | ✅ 7 | ✅ GS3–GS5 | unit: the browser-side decision table, restated from the spec. graph-save: staged rows refuse a false flag; clearing after save is refused; standalone modification save forces the parent flag |
| `ModificationText` required (R-6) — NOT NULL + not-blank | ✅ 14 | ✅ manual | the free function is covered by unit tests (incl. the collapse of the two absence errors); the CREATE path was driven through live GraphQL and refuses null, `''` and whitespace with the app's own prose |
| Required-field prose on the UPDATE path (R-6) | ✅ 14 | ⚠ not re-probed | the update was correctly refused when probed, but MJ then returned `"Unknown error"`: its update resolver read `LatestResult.Message` where create read `CompleteMessage`. MemberJunction 6.1.5, this app's floor, reads `CompleteMessage` on create, update and delete, so the prose should now arrive; no live probe since |
| Retired type/template not newly selected (R-5) | ✅ 9 | ✅ manual | the `IsNewlySelected` predicate is unit-covered incl. the create case and UUID casing; 5 live GraphQL probes covered both FKs and both directions (refuse a new selection, still allow an existing one) |
| Refusal messages on the UPDATE/DELETE paths | in MJ | ⚠ manual, on a patched MJ | the 2026-08-20 probes ran against a locally patched `ResolverBase` (`Message` → `CompleteMessage`); before MemberJunction 6.1.5 every refusal on an update read "Unknown error". 6.1.5, this app's floor, ships that change with its own tests, so no patch is needed; the refusals have not been re-probed on it |
| Delete refusals explain themselves (R-8) | ✅ 9 | ✅ manual | 6 live probes: provision-with-modifications, template-with-contracts-and-provisions, type-in-use, template-type-in-use, contract-with-modifications-and-a-child all refused with counts; an unreferenced type still deleted (the counter-test). Registration guard red-proven |
| Provision immutability (R-1) | — | ✅ manual | 5 direct-SQL trigger probes (term change blocked, Description/Sequence allowed (`Sequence` since dropped, R-11), DELETE blocked, **identical 73-row rewrite allowed**) + a real `mj sync push` at `errorCount: 0` + 4 live GraphQL probes on the code half |
| Contract numbering from a SQL SEQUENCE (R-7) | ✅ (registration) | ✅ manual | two live creates minted CTR-900010 then CTR-900011 sequentially through the unchanged sproc signature; entity/table/metadata all verified gone with zero orphans; both probe contracts deleted |
| Lineage cycle prevention (R-3) | — | ✅ manual | 7 live probes across both FKs: 2-node ring refused, 3-node ring refused with the full chain, legal parent + legal supersession accepted, superseded ring refused. No unit test — the logic is a recursive CTE and a TS restatement is not an oracle for SQL |
| One modification per provision × contract combo (R-10) | ✅ 8 | ✅ manual | staged-duplicate counting unit-covered incl. UUID casing / blanks / triplicates (red-proven); live probes confirm a saved duplicate is refused with prose and an ordinary re-save is not |
| Tree placement + template rules (R-4) | ✅ (generated CHECK validator) | ✅ manual | live probes: MustBeChild refused a parentless change order; MustBeRoot + TemplateRequired both refused in one response; **a modification on a change order citing the parent's template is now accepted** (previously impossible); an out-of-tree provision still refused. `pnpm run test:parent-rule` repeats the MustBeChild / MustBeRoot cases against a database |
| Provision natural ordering (R-11) | ✅ 8 | ✅ manual | live API returns 73 provisions in natural order (`1.9` → `1.10` → `1.11`); boundary cases incl. `1.2.3`, `1.1A`, `2.10B`, `10.1` verified through the function. The unit tests guard the READERS (a reader drifting back to `Sequence` fails only at the provider, on one grid) and the migration's invariants — the ordering itself is SQL, and a TS restatement would not be an oracle for it |
| Template usability (R-12) | — | ✅ manual | full loop through live GraphQL: template with no URL → `IsUsable: false` → contract reference refused → URL added → `IsUsable: true` → reference accepted. **Gotcha 6 proven** by running CodeGen afterwards and confirming the wrapper, the inner view and the EntityField all survived |
| `ProvisionText` required (R-6 extended to provisions) | ✅ 5 | ✅ manual | 5 live probes: omitted / `''` / whitespace all refused with the app's prose; real text accepted; blanking an existing provision refused. Note the backfill needed R-1's trigger held off — the one NULL row was on a template 7 contracts reference |
| Template publication lifecycle + the INSERT guard | ✅ (registration) | ✅ manual | 9 live probes: add-to-draft allowed; publish-without-URL refused; contract→draft refused; publish-with-URL allowed; add/edit/delete on a published version all refused **with the app's own sentences**; un-publish refused; contract→published allowed. Plus 4 direct-SQL trigger branches, and a raw INSERT confirmed blocked with **no row written** |
| `ContractNumber` minting under concurrency | ✗ | ✅ N1–N5 | minted `CTR-<digits>`, sequential and concurrent uniqueness, custom numbers kept, reserved `CTR-` refused |
| Graph save: header + modifications atomicity | ✗ | ✅ GS1–GS2 | one Save writes header+two mods; a blank modification refuses and writes no header |
| Provision/template consistency (server rule) | ✗ | ✅ GS11 | a modification citing a provision of another template is refused |
| Change-order-needs-parent (server rule) | ✗ | ✅ GS7–GS8 | MustBeChild without parent refused; MustBeRoot with parent refused |
| Provision seed completeness incl. text | ✗ | ✅ P1–P5 | IT template text + `1.9` before `1.10`; MSA 2026-02-02 asserted when that demo template is present |
| Derived columns on the base view | ⚠ half | ✅ W1–W8 | values on CTR-WORLD: awaiting document, payment-link never awaiting, DaysToEnd, notice deadline, cancellation window, all six States. `IsChangeOrder` is gone; W8 asserts `ParentContractID`. Recorded before `V202609211200` moved the view onto the business-zone day: W3 still expects `DaysToEnd` counted from the UTC day, so it can fail on a correct view while the two days differ |
| Migration installs from zero | ✅ manual | — | measured 2026-08-18, before the 2026-08-23 flatten, on a wiped DB: 8 views, 21 sprocs, 7 entities, 77 fields, 6 derived columns, flags set. Not re-measured since. **Not yet automated** |
| Metadata push | ✅ manual | — | 2026-08-18: `errorCount: 0`, 7 created / 9 updated, twice from zero. Not automated. Issue #80 records a later push into an empty database rolling back on `FK_MLModelScoringBinding_MLModel`, because `directoryOrder` does not list the `ml-*` folders |
| Screens render at all | ✅ manual | — | driven in system Chrome, 2026-08-18: 3 sections, 5 rail items, dashboard tiles, 0 console errors; screenshots in `design-docs/ui-design/`. `test-harnesses/render-check.mjs` scripts the check outside the suite. **Not automated** |
| Screen BEHAVIOUR (filter, open, edit, save) | ✗ | ✗ | nothing clicks through a create → filter → open → edit → save cycle yet. This is the biggest single gap |
| Attachments and the executed agreement | ✅ 15 | — | files attach through MJ's stock `mj-record-attachments` on the form toolbar. `IsAwaitingDocument` clears only when a linked file carries the file category 'Executed Agreement' (latest `vwContracts`, `V202609211200`), which the app's Executed agreement panel sets. The unit tests pin that one category name across the migration seed, the view and the panel. Upload needs a configured storage account; clearing the flag by marking a file is not exercised |

Unit files with no row above: `default-template`, `renewal-defaults`, `seed-renewal-defaults-entity`,
`source-deal-lookup`, `source-record-candidates`, `supersede-candidates`,
`supersede-panel-outlives-its-record`, `hero-parties-and-copy`, `contract-date-order`,
`dates-executed-doc-and-readonly`, `value-list-validation`, `migration-conventions`,
`lockfile-covers-manifests`, `server-default-template`, `bundle-registration`, and the Angular
package's `business-day` and `contract-dates-panel`. Each file's header says what it pins.

**Reading that table:** the cheap tier is real, and the live-provider bundles now exist
(`contracts-world` plus the four item-13 bundles). Screen behaviour (click through create → filter →
open → edit → save) is still unautomated. Do not read unit-test counts as the app being tested.

**The one thing a reader should take from this file:** the schema, the metadata, the entity rules and
the seeded data are verified from zero, repeatedly. The screens are verified to compile and to appear.
**No user journey has been executed end to end.** The integration bundles exercise the entity layer,
not the screens, so that gap is still open.

---

## What needs a person

The last recorded question that touches testing is **Q-4** in [`plans/QUESTIONS.md`](plans/QUESTIONS.md)
(historical): the scope and source of the list of existing active contracts to migrate, which gated
item 13's demo/migration coverage.

---

## Notes on the numbers

- **The half-covered row is marked half deliberately.** The unit tier checks parts of the view's SQL
  text (`contract-state.test.ts`, `dates-executed-doc-and-readonly.test.ts`), not the values it
  returns. W4 asserts `RenewalNoticeDeadline` is `EndDate - RenewalNoticeDays` on CTR-WORLD; nothing
  yet asserts that `IsAwaitingDocument` goes false once a linked file carries the 'Executed Agreement'
  category.
- **Migration-from-zero is verified but manual.** It is the single most valuable thing to automate
  next, because it is the check that caught the missing CodeGen capture, and it caught it on review
  rather than in CI.
- **The render check found a bug nothing else could**, which is the argument for automating it:
  `super.ngOnDestroy?.()` type-checks, builds clean, and produces a bundle esbuild cannot parse —
  killing every `@RegisterClass` in the package so the app rendered no nav tab at all. A unit test
  cannot see that; only running the app can.
- **Do not verify builds by grepping their output.** Turbo caches tasks, so a package that once built
  reports nothing on a later broken run, and Angular's NG-prefixed template errors do not all match a
  `error TS` pattern. Use the exit code: `pnpm run build; echo "EXIT=$?"`. A filter that can only
  produce a false green is not a check — this was learned by making the claim and being wrong.
