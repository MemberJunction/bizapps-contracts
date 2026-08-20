# bizapps-contracts — testing ledger

The running record of what is covered, what is not, and what needs a person. Coverage is measured
against the **matrix**, not against the tests that happen to exist — an empty box is a gap even when
every written test is green.

> **Last run:** 2026-08-20, branch `build/backend-requirements`, instance `contracts-mj6`.
> **Totals: 127 unit assertions (11 files), all passing.** Build `exit 0` on all 6 packages (real `tsc`,
> not a grep). Plus a **live GraphQL check** against a restarted MJAPI for R-6 — create with no text,
> with `''`, with whitespace, and a valid create — each observed, and the probe rows deleted after.
> **Totals: 64 unit assertions (4 files), all passing.** Plus a **live render check** in system
> Chrome against a running Explorer: three sections, the full rail, the dashboard and its counts, with
> **zero console errors and zero pageerrors** (screenshot in `design-docs/ui-design/`). Every number below was observed, not
> estimated. Where something was not run, it says so.
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
# Unit — pure logic, no DB, no Angular compile, no provider. From the app root:
pnpm run test:unit                 # vitest run, root config, packages/*/src/**/*.test.ts   → 44

# The instance workspace does not install the app root's own devDependencies, so in a dev-linked
# instance invoke the binary the Angular package already has:
./packages/Angular/node_modules/.bin/vitest run --config vitest.config.ts

# Integration — MJ's testing framework. NO BUNDLES YET (item 13).
node test-harnesses/integration.mjs            # will report zero known bundles until item 13
```

---

## Coverage matrix

| Area | Unit | Integration | Notes |
|---|---|---|---|
| `State` derivation, all six branches | ✅ 28 | — | incl. both R-19 cases and its inverse; both sides of the today/yesterday/tomorrow boundaries |
| SQL ⇄ TypeScript parity for `State` | ✅ | — | reads the committed migration and asserts `StateSQL()` still matches it |
| ClassFactory resolution, all 7 entities | ✅ 16 | — | plus 7 assertions that no v1 entity name still resolves |
| `HasModifications` monotonic guard | ✗ | ✗ | needs an entity instance (provider); the collection-count logic is the part worth covering — item 13 |
| `ModificationText` required (R-6) — NOT NULL + not-blank | ✅ 14 | ✅ manual | the free function is covered by unit tests (incl. the collapse of the two absence errors); the CREATE path was driven through live GraphQL and refuses null, `''` and whitespace with the app's own prose |
| Required-field prose on the UPDATE path (R-6) | ✅ 14 | ⚠ **refused but unreadable** | the update IS correctly refused, but MJ returns `"Unknown error"` — `ResolverBase.ts:1335` reads `LatestResult.Message` where create reads `CompleteMessage`. Logged in `MJ-UPSTREAM.md`; **not an app bug and not fixable from here** |
| Retired type/template not newly selected (R-5) | ✅ 9 | ✅ manual | the `IsNewlySelected` predicate is unit-covered incl. the create case and UUID casing; 5 live GraphQL probes covered both FKs and both directions (refuse a new selection, still allow an existing one) |
| Refusal messages on the UPDATE/DELETE paths | ✅ 10 (in mj) | ✅ manual | needs the local `ResolverBase` patch (`Message` → `CompleteMessage`); commented onto MJ#3973. Without it every refusal on an update reads "Unknown error" |
| Delete refusals explain themselves (R-8) | ✅ 9 | ✅ manual | 6 live probes: provision-with-modifications, template-with-contracts-and-provisions, type-in-use, template-type-in-use, contract-with-modifications-and-a-child all refused with counts; an unreferenced type still deleted (the counter-test). Registration guard red-proven |
| Provision immutability (R-1) | — | ✅ manual | 5 direct-SQL trigger probes (term change blocked, Description/Sequence allowed, DELETE blocked, **identical 73-row rewrite allowed**) + a real `mj sync push` at `errorCount: 0` + 4 live GraphQL probes on the code half |
| Contract numbering from a SQL SEQUENCE (R-7) | ✅ (registration) | ✅ manual | two live creates minted CTR-900010 then CTR-900011 sequentially through the unchanged sproc signature; entity/table/metadata all verified gone with zero orphans; both probe contracts deleted |
| Lineage cycle prevention (R-3) | — | ✅ manual | 7 live probes across both FKs: 2-node ring refused, 3-node ring refused with the full chain, legal parent + legal supersession accepted, superseded ring refused. No unit test — the logic is a recursive CTE and a TS restatement is not an oracle for SQL |
| Modification uniqueness (R-10) | ✅ 8 | ✅ manual | staged-duplicate counting unit-covered incl. UUID casing / blanks / triplicates (red-proven); live probes confirm a saved duplicate is refused with prose and an ordinary re-save is not |
| Tree placement + template rules (R-4) | ✅ (generated CHECK validator) | ✅ manual | live probes: MustBeChild refused a parentless change order; MustBeRoot + TemplateRequired both refused in one response; **a modification on a change order citing the parent's template is now accepted** (previously impossible); an out-of-tree provision still refused |
| Provision natural ordering (R-11) | ✅ 10 | ✅ manual | live API returns 73 provisions in natural order (`1.9` → `1.10` → `1.11`); boundary cases incl. `1.2.3`, `1.1A`, `2.10B`, `10.1` verified through the function. The unit tests guard the READERS (a reader drifting back to `Sequence` fails only at the provider, on one grid) and the migration's invariants — the ordering itself is SQL, and a TS restatement would not be an oracle for it |
| Template usability (R-12) | — | ✅ manual | full loop through live GraphQL: template with no URL → `IsUsable: false` → contract reference refused → URL added → `IsUsable: true` → reference accepted. **Gotcha 6 proven** by running CodeGen afterwards and confirming the wrapper, the inner view and the EntityField all survived |
| Migration re-runnability (V202608192340) | ✅ manual | — | history row deleted and the migration re-applied twice from scratch; the CodeGen capture's `DROP`/`CREATE PROCEDURE` observed executing (sproc `modify_date` moved to the migration's own timestamp, not CodeGen's) |
| `ContractNumber` minting under concurrency | ✗ | ✗ | `contracts-numbering` bundle, item 13. Lock behaviour is only observable against a real DB |
| Graph save: header + modifications atomicity | ✗ | ✗ | `contracts-graph-save`, item 13 — the acceptance test for D-15 itself |
| Provision/template consistency (server rule) | ✗ | ✗ | `contracts-graph-save`, item 13 |
| Change-order-needs-parent (server rule) | ✗ | ✗ | item 13 |
| Provision seed completeness incl. text | ✗ | ✗ | `contracts-provisions`, item 13 — gated on item 4 |
| Derived columns on the base view | ⚠ half | ✗ | `State` is covered above; `IsAwaitingDocument`, `IsChangeOrder`, `DaysToEnd`, `RenewalNoticeDeadline`, `IsInCancellationWindow` are **verified present and typed** but their VALUES are untested — `contracts-watchlist`, item 13 |
| Migration installs from zero | ✅ manual | — | measured on a wiped DB: 8 views, 21 sprocs, 7 entities, 77 fields, 6 derived columns, flags set. **Not yet automated** |
| Metadata push | ✅ manual | — | `errorCount: 0`, 7 created / 9 updated, twice from zero. Not automated |
| Screens render at all | ✅ manual | — | driven in system Chrome: 3 sections, 5 rail items, dashboard tiles, 0 console errors. **Not automated** |
| Screen BEHAVIOUR (filter, open, edit, save) | ✗ | ✗ | nothing clicks through a create → filter → open → edit → save cycle yet. This is the biggest single gap |
| Documents: register / open / gating | ✗ | ✗ | item 9 code lands unexercised — needs a configured storage account, which needs an Azure AD app registration (an IT task) |
| Modification editor (the D-15 acceptance test) | ✗ | ✗ | `contracts-graph-save`, item 13. Compiles and renders; the one-transaction claim is **unproven at runtime** |

**Honest reading of that table:** the cheap tier is real, the expensive tiers are empty, and the UI has
been proven to RENDER but not to WORK. Everything in the `✗` rows needs either an entity instance or a
live database, which is `mj test`'s job, and no bundle exists yet. Do not read "64 passing" as the app
being tested.

**The one thing a reader should take from this file:** the schema, the metadata, the entity rules and
the seeded data are verified from zero, repeatedly. The screens are verified to compile and to appear.
**No user journey has been executed end to end.** That is the honest state, and it is what item 13's
integration bundles exist to close.

---

## What needs a person

Nothing currently blocked. Open questions live in `plans/QUESTIONS.md`; the one that touches testing
is **Q-4** (Andrew's migration data), which gates item 13's demo/migration coverage.

---

## Notes that keep the numbers honest

- **The half-covered row is marked half deliberately.** Five derived columns exist, are typed, and are
  registered as virtual `EntityField`s — all verified. That is *presence*, not *correctness*: nothing
  yet asserts that `RenewalNoticeDeadline` is actually `EndDate - RenewalNoticeDays`, or that
  `IsAwaitingDocument` goes false the moment a file is linked. Presence is the cheaper claim and it is
  the only one made.
- **`integration.mjs` names four bundles that do not exist yet** (`contracts-graph-save`,
  `contracts-numbering`, `contracts-provisions`, `contracts-watchlist`). It will report zero known
  bundles until item 13. That is intentional — the names are the plan, in the runner, where the next
  person looks.
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
