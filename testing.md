# bizapps-contracts — testing ledger

The running record of what is covered, what is not, and what needs a person. Coverage is measured
against the **matrix**, not against the tests that happen to exist — an empty box is a gap even when
every written test is green.

> **Last run:** 2026-08-18, branch `build/contracts-v2`, instance `contracts-mj6`.
> **Totals: 44 unit assertions (2 files), all passing.** Every number below was observed, not
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
| `ContractNumber` minting under concurrency | ✗ | ✗ | `contracts-numbering` bundle, item 13. Lock behaviour is only observable against a real DB |
| Graph save: header + modifications atomicity | ✗ | ✗ | `contracts-graph-save`, item 13 — the acceptance test for D-15 itself |
| Provision/template consistency (server rule) | ✗ | ✗ | `contracts-graph-save`, item 13 |
| Change-order-needs-parent (server rule) | ✗ | ✗ | item 13 |
| Provision seed completeness incl. text | ✗ | ✗ | `contracts-provisions`, item 13 — gated on item 4 |
| Derived columns on the base view | ⚠ half | ✗ | `State` is covered above; `IsAwaitingDocument`, `IsChangeOrder`, `DaysToEnd`, `RenewalNoticeDeadline`, `IsInCancellationWindow` are **verified present and typed** but their VALUES are untested — `contracts-watchlist`, item 13 |
| Migration installs from zero | ✅ manual | — | measured on a wiped DB: 8 views, 21 sprocs, 7 entities, 77 fields, 6 derived columns, flags set. **Not yet automated** |
| Metadata push | ✅ manual | — | `errorCount: 0`, 7 created / 9 updated, twice from zero. Not automated |
| Screens (list, form, watchlist, editors) | ✗ | ✗ | not built yet — items 5/6/7/8/11/12 |

**Honest reading of that table:** the cheap tier is real and the expensive tiers are empty. Everything
in the `✗` rows needs either an entity instance or a live database, which is `mj test`'s job, and no
bundle exists yet. Do not read "44 passing" as the app being tested.

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
