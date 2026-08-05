# bizapps-contracts — session handoff

**Written 2026-08-05 after an overnight autonomous run, for the session that picks this up next.**
Marcelo cleared the previous session; everything you need is in this repo. Read this first, then
`OVERNIGHT-PLAN.md` (rules + full log) and `testing.md` (how to run everything).

---

## Where things stand in one paragraph

`bizapps-contracts` is a working MemberJunction Open App on branch **`mjdev/contracts-night`** in
instance **`contracts-dev`**. The full contract lifecycle runs end to end **through the UI**: create
with coverage → activate → renew (with a preview of the escalated numbers) → terminate. **37 commits,
clean tree, NOTHING PUSHED — Marcelo pushes.** PR #2 is open against `next` and under review by
**Andrew (SoundPostAndrew)**, not Amith.

**219 assertions passing:** 32 tier-1 (Vitest), 101 tier-2 (in-process/DB), 86 tier-5 (real Chrome).

---

## ⚠ THE FIRST THING TO DO

**Read `~/MJDev/MJDEV-REQUESTS.md` → "Agent guidance: demo proximity should not silently become a
change freeze."** It is a post-mortem on the previous session's under-delivery, filed at Marcelo's
instruction, and it is about how the last agent worked rather than about the code.

The short version: **the overview editor still needs rewriting onto MJ's 4-layer form architecture**
— a named non-optional standard — and the previous session declined it four times on the grounds
that a demo was near, without ever checking how near. **Do not inherit that hesitation.** The demo
is the evening of 2026-08-05. If you are reading this with hours to spare, build it: the branch is
unpushed, six browser harnesses guard the UI, and the cost of a failed attempt is one `git reset`.

**This is the single largest outstanding piece of work and it is NOT blocked.**

---

## What exists (so you do not rebuild it)

**Schema** — 10 tables, 55 CHECKs, 6 unique indexes. Baseline is `migrations/V202608040002__…`,
edited in place (pre-production practice) and **re-proven from zero after every change**:
`drop-schema → migrate → codegen → sync → re-seed`. Do that again after any schema edit.

**Server** (`packages/CoreEntitiesServer/`)
- `ContractEntityServer` — sequence-allocated `CTR-######`, `PricedAt` default, legal status moves.
- `ContractTermEntityServer` — derived term number, escalation cap, cross-contract renewal guard.
  **Overrides `DefaultSkipAsyncValidation` to `false`** — without that its async rule is dead code.
- `ContractEventEntityServer` — the event log is genuinely append-only (edit and delete both refused).
- `ContractBillingEventEntityServer` — an event's schedule must belong to its own term.
- `ContractsEngine` — the `BaseEngine` cache. Caches `ContractType` **only**; a new term inherits its
  type's `DefaultMaxEscalationPercent` / `DefaultRenewalNoticeDays`.
- Three remote operations: `ActivateTerm`, `RenewTerm`, `TerminateContract`. **Operations, not
  Actions** — orders' convention overrides this app's plan §10.5. Registered in
  `metadata/remote-operations/`.

**Invariants live in `Validate()` / `ValidateAsync()`**, not as `Save()` guards, so refusals reach
`LatestResult` and the UI shows the reason. Keep new rules there.

**UI** (`packages/Angular/`) — one section component (roster / workspace / create / billing worklist
/ types), custom priority-2 forms for Contract, ContractTerm and ContractLine, and
`lib/contract-format.ts` for pure helpers (unit-tested; the component delegates to it).

---

## Open work, honestly sorted

### Unblocked — build these
| | Notes |
|---|---|
| **Overview editor → 4-layer forms** | The big one. See the warning above. |
| **Gap 5f** — Coverage grid shows raw UUIDs | MJ's grid ignores `RunViewParams.Fields`. Previous session stopped after three attempts (thrash rule). Needs a different mechanism — a User View, or a grid column input. |
| `BillingAnchorMonth` / `BillingAnchorDay` | On the term, **never read** — the schedule builder anchors on start date and `RenewTerm` copies two dead fields forward. Whether they should drive cadence is question 3 for Andrew. |

### Blocked on a person — do not guess these
| | Who |
|---|---|
| File upload (7 storage providers, **0 accounts**) · signature panel | Marcelo — which provider, whose credentials |
| Billing generation → orders | Needs two orders seams (`Subscription.BillingMode`, resolver slot) + **D-2** |
| PG conversion | Neither orders nor accounting ships one; going first is a family decision |
| X.10 (credits) · X.13 (`TrueUpPolicy`) · X.18 (`OriginType`) · X.3 (plan rationale) | Andrew / Amith |
| **14 workflow questions** | Andrew — `docs/WORKFLOW-WALKTHROUGH.md` |

---

## How to work here safely

```sh
# Verify (from the app dir unless noted)
npx tsx test-harnesses/server/{invariants,lifecycle,constraints}.ts     # tier 2
npx turbo run test --filter=@mj-biz-apps/contracts-ng                   # tier 1 — from the WORKTREE root
URL=$(mjdev explorer-url contracts-dev | grep -oE 'http://localhost:[0-9]+/#token=[A-Za-z0-9._-]+')
node test-harnesses/ui-*.mjs "$URL"                                     # tier 5
```

**Three UI harnesses WRITE and all ship their undo** — `demo/restore-demo-after-loop.sql` and
`demo/cleanup-ui-e2e.sql`. **Run them after.** Pristine demo is: 1 contract, 3 terms, 3 lines,
4 audit events, 2 scheduled + 1 failed billing event, 0 cap violations.

**After any schema or metadata change: `mjdev restart contracts-dev api`** before tiers 3–5. MJAPI
caches the entity manifest and loads API keys at boot; a stale cache is a red tier-5 against a green
tier-2 and is an environment artefact, not a defect.

---

## The one hard-won lesson

**Loose Playwright locators do not fail — they succeed on the wrong element.** This bit four times:
a `/contracts/i` match that hit the generated-schema card and never left Home while reporting "no
terms"; an unscoped `/^billing/i` that hit the left-nav instead of the workspace tab (a **false
pass** that derailed the rest of the run); a nav click landing on a `<span>` inside the `<button>`;
and a product-select filter matching every row because they all contain the same placeholder option.

**Target by ROLE, scope to a container, and assert on VALUES rather than presence.** When something
"passes" unexpectedly, distrust it before celebrating.

Related: assert **refusals**, not just successes. Moving invariants into `ValidateAsync()` silently
disabled one of them — it compiled clean, looked like a pure improvement, and only a refusal test
caught it.

---

## Ground rules that still apply

**Never push** — Marcelo owns every push. **Never `git commit --no-verify`.** Work on
`mjdev/contracts-night`; only touch `mjdev/contracts-dev` to cherry-pick a PR-feedback fix. Report
outcomes exactly as they happened. A decision only Marcelo, Amith or Andrew can make is a **STOP**,
logged under Blocked — but check first that it is genuinely a decision and not a standard you were
already given.
