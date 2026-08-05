# bizapps-contracts — testing ledger

The running record of what is covered, what is not, and what needs a person. Coverage is measured
against the **matrix**, not against the tests that happen to exist — an empty box is a gap even when
every written test is green.

> **Last full sweep:** 2026-08-05, branch `mjdev/contracts-night`, instance `contracts-dev`.
> **Totals: 32 tier-1 + 92 tier-2 + 69 tier-5 = 193 assertions, all passing.** Every number below was
> observed, not estimated. Where something was not run, it says so.

---

## How to run it

Tier 2 needs the instance database. Tiers 3 and 5 additionally need MJAPI **ready** (not merely
started) and, for tier 5, MJExplorer.

```sh
# Tier 1 — pure logic, no DB, no Angular compile. Run from the INSTANCE WORKTREE root:
#   the app-root `npm test` cannot resolve turbo tasks from inside a dev-linked member.
npx turbo run test --filter=@mj-biz-apps/contracts-ng    # 32

# Tier 2 — in-process, direct SQL, MJAPI-free
npx tsx test-harnesses/server/invariants.ts     # 22
npx tsx test-harnesses/server/lifecycle.ts      # 45
npx tsx test-harnesses/server/constraints.ts    # 25

# Tier 5 — real Chrome, driven only through the UI
URL=$(mjdev explorer-url contracts-dev | grep -oE 'http://localhost:[0-9]+/#token=[A-Za-z0-9._-]+')
node test-harnesses/ui-lifecycle.mjs       "$URL"   # 8
node test-harnesses/ui-form-editing.mjs    "$URL"   # 11
node test-harnesses/ui-history.mjs         "$URL"   # 5
node test-harnesses/ui-navigation.mjs      "$URL"   # 25
node test-harnesses/ui-create-to-active.mjs "$URL"  # 11 — CREATES a contract
node test-harnesses/ui-full-loop.mjs       "$URL"   # 9  — WRITES to the demo contract
```

**Two of the UI harnesses write, and both ship their undo.** `ui-create-to-active` stamps every
contract it makes with a `UI-E2E ` number prefix → `demo/cleanup-ui-e2e.sql`. `ui-full-loop` genuinely
renews and activates the demo contract → `demo/restore-demo-after-loop.sql` puts it back to its seeded
three terms. Run the cleanup after either. A test that leaves the demo in a different state than it
found it is a test that breaks the demo.

**After any schema or metadata change, restart the API before running tiers 3–5** (`mjdev restart
contracts-dev api`). MJAPI caches the entity manifest and loads API keys at boot; a stale cache
produces a red tier-3/4/5 against green tier-2, which is an environment artefact and not a defect.

---

## Coverage matrix

`✓` exact values, real behaviour · `⚠` deliberately covered at a cheaper tier, with the reason ·
`✗` **a real gap** · `—` no machinery at this tier routes it.

| Feature / invariant | T1 unit | T2 server | T3 API | T5 browser | Notes |
|---|---|---|---|---|---|
| Status/event tone + label mapping | ✓ | — | — | ✓ | 32 assertions on the pure helpers, including that an unmapped event type falls back to the RAW value so a widened CHECK looks wrong rather than invisible. |
| Percent ↔ fraction conversion | ✓ | — | — | — | Round-trips without drift; null stays null, because blank is an absence and zero is a claim. |
| Coverage subtotal | ✓ | — | — | ✓ | Catalog-priced lines are EXCLUDED, not counted as zero. |
| `ContractNumber` allocation from the sequence | — | ✓ | ⚠ | ⚠ | Allocation is a read-modify-write in `Save()`; T2 asserts the number shape AND that the sequence advances by exactly 1. Nothing above adds machinery. |
| `PricedAt` defaults rather than staying null | — | ✓ | ⚠ | ⚠ | Same. |
| An explicit contract number is not overwritten | — | ✓ | ⚠ | ⚠ | Same. |
| Contract legal status **moves** | — | ✓ | ⚠ | ✓ | The CHECK knows only the legal SET. T2 proves `Terminated → Active` is refused, did not persist, AND that the refusal explains itself. T5 proves the control offers only the legal moves, so the error is one nobody has to read. |
| Refusals reach the caller, not just the console | — | ✓ | — | — | The rules live in `Validate()`/`ValidateAsync()`, so `LatestResult` carries the reason. T2 asserts the MESSAGES, not only the `false`. |
| Term numbering derived as max+1 | — | ✓ | ⚠ | ⚠ | |
| Contract-type defaults applied to a NEW term | — | ✓ | — | — | 4 assertions incl. the two negatives: an explicit value is never overwritten, and an EXISTING term is never retrofitted — that would change an agreement. |
| Escalation cap enforced | — | ✓ | ⚠ | ✓ | T2 proves the refusal; T5 shows the "capped" badge and the ceiling actually applied. |
| A null cap means uncapped, not zero | — | ✓ | — | — | |
| **ActivateTerm** — status + schedule + events, atomically | — | ✓ | ✓ | ✓ | T2 asserts exactly 4 events on the term anchor; T5 drives the button and re-reads the DB. |
| Activation refuses an uncovered term | — | ✓ | — | ✓ | T5 asserts the create page WARNS before the save rather than failing at it. |
| Activation refuses a second activation | — | ✓ | — | — | |
| Activation promotes the contract Draft → Active | — | ✓ | — | ✓ | Found by reading the DB after a UI run, not by an assertion. |
| Schedule arithmetic at month boundaries | — | ✓ | — | — | 7 assertions: Jan-31 monthly gives 12 not 11, Feb clamps to 28, leap Feb to 29, May returns to 31, short term bills once, Milestone invents nothing. |
| **RenewTerm** — successor, escalated coverage, prior term Completed | — | ✓ | ✓ | ✓ | Exact money: 1000.00 → 1030.00; 250.50 → 258.02 (not 258.015). |
| Renewal preview writes nothing | — | ✓ | ✓ | ✓ | Asserted at T2 by re-querying, at T5 by cancelling and checking no term appeared. |
| Over-cap escalation is clamped, not rejected | — | ✓ | — | ✓ | |
| Renewal refuses a second renewal of one term | — | ✓ | — | — | |
| Renewal carries committed amount + line prices forward | — | ✓ | — | ✓ | T5 verifies in the DB: 471,744 × 1.04 = 490,613.76. |
| **TerminateContract** — cancels FUTURE events, retains past | — | ✓ | — | ⚠ | The load-bearing one. T2 re-reads the schedule and asserts the exact split. T5 asserts the control + preview; the write path is proven at T2. |
| Termination requires a reason | — | ✓ | — | ✓ | |
| Termination preview writes nothing | — | ✓ | — | — | |
| Termination skips Completed terms | — | ✓ | — | — | Found by a test: `Completed` is terminal, so including them rolled back the whole transaction. |
| X.5 Subscription line needs its type | — | ✓ | — | ✓ | T5 asserts the page demands it before saving. |
| X.6 Superseded needs a successor | — | ✓ | — | — | |
| X.8 renewal chain cannot cross contracts | — | ✓ | — | — | Entity layer; a CHECK cannot see the other row. |
| X.9 one subscription, one line | — | ✓ | — | — | Bypass proof: the filtered unique index exists. |
| X.12 Generated needs a timestamp | — | ✓ | — | — | Bypass proof. |
| X.14 Approved amendment needs its task | — | ✓ | — | — | Bypass proof. |
| X.15 event vocabulary is closed | — | ✓ | — | ✓ | T5 asserts the timeline renders sentences and NOT raw enum strings. |
| X.15 event log is append-only | — | ✓ | — | ✓ | T2 proves edit and delete are both refused AND that the row is unchanged in the DB afterwards. |
| Creating a contract with coverage | — | ⚠ | — | ✓ | Driven end-to-end through the UI; T2 covers the entity rules underneath. |
| Term / line editing via MJ's form shells | — | — | — | ✓ | jsdom cannot route the overlay mount; asserted by diffing `document.body.children`. |
| Custom priority-2 forms WIN dispatch | — | — | — | ✓ | Asserted on the custom panel names. The generated form still renders and still shows the data, so a lost registration would look fine — which is why this needs its own check. |
| Audit timeline rendering | — | — | — | ✓ | |
| Workspace search + status filter | — | — | — | ✓ | 10 assertions: exact-match, description match, no-match says so, status filter both ways, Clear. |
| Billing worklist page | — | — | — | ✓ | Renders and surfaces the failed event. |
| Contract types setup page | — | — | — | ✓ | All six seeded types listed **by name**. |
| Coverage / Billing / Commitments / Amendments tabs | — | — | — | ✓ | Asserted on VALUES belonging to the open contract, so a wrong `ExtraFilter` fails. |
| Coverage rows open for editing | — | — | — | ✓ | Row-click opens the CUSTOM line form; asserted on its panel names, since the generated form would also open and look fine. |
| Documents tab (file links) | — | — | — | ✗ | **Gap `5d`** — feature not built. |
| Signature status panel | — | — | — | ✗ | **Gap `5e`** — feature not built; needs a provider account. |
| Billing event generation | — | ✗ | ✗ | ✗ | **Blocked, not a gap** — needs the orders seams (D-2). Nothing to test yet. |

---

## Open gaps, coded

| Code | Gap | Why it is still open |
|---|---|---|
| `5f` | The Coverage grid shows `ProductID` as a raw UUID and no description | **A real UX problem, not a test gap.** MJ's `mj-explorer-entity-data-grid` renders the entity's own columns and does **not** take its column set from `RunViewParams.Fields` — setting `Fields` changed nothing. So a person reading Coverage sees `22222222-0000-…` where they want "Onboarding setup fee". Needs the right MJ mechanism (a User View, or a grid column input); raised on the PR. The tab's tests assert prices instead, which still prove the binding. |
| `5d` | Documents tab | Feature not built — the panel lists links but the upload path is not wired. |
| `5e` | Signature status panel | Feature not built; sending needs a provider account. |
| `1b` | The operations' date helpers still have no tier-1 tests | They are module-private to the operation files, and exporting them purely for tests is a seam the protocol forbids. Covered through the operations at tier 2, where the month-boundary cases live (7 assertions). The presentation helpers were extractable because they are genuinely standalone functions; these are not. |
| `4a` | No tier-4 (component + API, headless) | Not initialized for this app. It would absorb much of what tier 5 currently carries. Opt-in, and not initialized without being asked. |

**No box above is empty for the reason "it is covered at another tier."** Where a `⚠` appears, it
names the specific reason that tier's machinery adds nothing (allocation happens in `Save()`, so the
API routes it without changing it) rather than deferring to a cheaper tier out of convenience.

---

## Needs a person

Ten open questions were posted to PR #2 as
["AI questions from the overnight work"](https://github.com/MemberJunction/bizapps-contracts/pull/2#issuecomment-5189321195).
The ones that would change tests if answered differently:

- **Remote operations vs Actions** for status transitions. Changes registration, not behaviour — the
  tier-2 assertions would transplant unchanged.
- **`ContractedUnitPrice` null = "resolve from the catalog"** vs "not yet priced, block activation".
  The second reading would need a new refusal test and a UI gate.
- **Escalation clamped vs rejected** over the cap. The current tests assert clamping.
- **X.10** — `ComputedAmount >= 0` forbids a credit. Deliberately unchanged and untested pending the
  scope decision; testing it now would pin behaviour nobody has agreed to.

---

## Known non-defects

- **Tier 3/5 red while tier 2 is green, right after a schema change** — MJAPI's cached manifest.
  `mjdev restart contracts-dev api`. Not a code bug.
- **`ClassFactory: no registration found for base class 'BaseEntity'`** during `mj sync push` — a
  benign fallback warning, not an error.
- **A tier-5 harness failing ONCE immediately after `mjdev restart api`** — Explorer reconnects to a
  freshly-restarted API on its own schedule, so a run started the instant the API answers can catch
  it mid-reconnect. Seen once on `ui-lifecycle`; not reproducible in three subsequent runs. If it
  happens, re-run before investigating. Recorded rather than dismissed, because "it passed the second
  time" is exactly how a real intermittent failure gets talked away.
- **Orders' TVP deadlock during `reapply-migrations`** — a known filed issue with a documented
  `mj migrate` workaround; unrelated to this app.
