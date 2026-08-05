# Overnight autonomous build — 2026-08-05

**Branch:** `mjdev/contracts-night` (instance `contracts-dev`) · **PR branch `mjdev/contracts-dev` is frozen**
except for cherry-picked review fixes. **Never push.** Marcelo pushes when he wakes.

## Rules

1. **One item per cycle**, verified and committed, before starting the next.
2. **Verify, never assume.** `npx ngc` → `mjdev app build` → Explorer bundle clean. If the change is
   user-visible, drive it with `test-harnesses/golden-path.mjs`. If it writes, check the database.
3. **Never fabricate a result.** A failure is written down as a failure.
4. **Two consecutive failures for the same reason → stop building.** Write what happened here and wait.
5. **A decision only a human can make is a STOP**, not a guess. Log it under Blocked and move on.
6. **PR feedback outranks the queue.** Fix on this branch, verify, then cherry-pick onto
   `mjdev/contracts-dev` so Marcelo's push carries it.

## 🔁 AFTER EVERY COMPACTION — do this BEFORE writing any code (Marcelo, 08:0x)

A compaction drops the *reasoning*, not the *requirements*. Re-read, in this order:

1. **This file** — the Direction block below, the queue, the Blocked table, the Log.
2. **The live task list** (`TaskList`) — it carries intent across the compact; work it in ID order.
3. **`~/MJDev/AGENTS.md` + `.mjdev-docs/`** — harness rules (never push, dual-layer validation,
   honesty, heavy slots, per-slug locks).
4. **`mj/CLAUDE.md`** — MJ's own rules outrank the mjdev docs for anything MemberJunction:
   no `any`, no `.Get()/.Set()`, derive field types from the entity, `EntityByName`, `ProviderToUse`.
5. **`plans/bizapps-contracts-master.md`** + **`plans/FEATURE-LIST.md`** — what we said we'd build.
6. **Marcelo's design requirements** (restated in Direction below) **and Amith's UI requirements** —
   the 4-layer form architecture, MJ's grid, MJ tokens on every control including dropdowns,
   custom priority-2 forms, headers/subheaders with quick-filter buttons.

**Do not resume mid-file from memory.** Re-open the file being edited and re-check field names
against the live schema — the last compaction cost a round of wrong column names
(`LineNumber`/`DiscountPercent`/`TerminationDate` do not exist).

## Direction (Marcelo, 06:45 — supersedes anything below that conflicts)

- **Demo is EVENING**, not morning. ~9h until he wakes; more runway after. Target: **the full chain**.
- **Priority order when forced to choose:** (1) the flows *within* the app working end to end,
  (2) a very well built UI + backend validation + viewing/editing with validation,
  (3) cross-app integration and deep testing — bonuses, wanted if reachable.
- **Guessing is allowed** where a human ruling is missing — build it, then ASK on the PR.
  Post open questions to PR #2 **before 05:00**, in one comment headed **"AI questions from the overnight work"**.
- **Orders: switch early, rebuild once.** (Item 0 below.)
- **3 compactions allowed.** Keep durable state in THIS file + `TASKS.md` so a compaction costs nothing.
- Standards restated: `ProviderToUse` · BaseEntity subclass overloads (not helper classes) ·
  BaseEngine caching for high-read/low-write · custom forms for view+edit · MJ grid for viewing ·
  MJ tokens for every control incl. dropdowns · transactions around anything multi-write ·
  remotable ops where the UI needs a preview · MJ's 4-layer form architecture ·
  **FKs point UPSTREAM only; downstream adapts to upstream.**

## Item 0 — rebuild on the current orders (IN PROGRESS)

`origin/mjdev/orders-flow` (PR #31) is **22 commits ahead** of what we installed, including
"Merge origin/next: take its regenerated baseline" and "orders now installs from zero" — an 83k-line
migration diff, i.e. **new entity UUIDs**.

Our contracts baseline hardcodes **no** orders UUIDs (its FKs are to TABLES by name, and contracts'
CodeGen tail is generated into the DB at install, not into the migration), so no UUID surgery is
expected on our side. The risk is ordering, not identity.

Sequence: update the orders worktree → `mjdev wipe-db --yes` → `reapply-migrations` (core, then apps
in dependency order) → per-app setup/codegen/build → re-seed from `demo/seed-demo-contract.sql` →
re-drive the golden path. If the rebuild leaves the stack worse than it is now, say so plainly in the
Log rather than papering over it.

## Key finding — use MJ's 4-layer forms instead of hand-rolled edit surfaces

`guides/FORMS_ARCHITECTURE_GUIDE.md`. The layering is
`form/container → MjEntityFormHostComponent → shells → MJFormPresenterService`, all in
`@memberjunction/ng-base-forms` with no Explorer/Router coupling. What it gives us:

- **`MJFormPresenterService.Open({...})`** — open any entity's form imperatively from anywhere.
- **`<mj-form-dialog>` / `<mj-form-slide-in>`** — declarative modal / slide-in shells.
- **`EntityFormConfig`** — per-instance toolbar / sections / width / collapsibility **without
  regenerating** the form.
- **`SectionName="…"`** — render ONE section standalone, which is exactly a quick-edit affordance.

**Consequence for our UI:** the workspace should PRESENT our priority-2 custom Contract form through
these shells rather than duplicating its fields by hand — one definition of what a contract looks
like, reused in the workspace, in a dialog from the roster, and in a slide-in from anywhere. Term and
Line editing become slide-ins over their own custom forms rather than more grids. Rewrite the
workspace edit pane on this before adding any more hand-built fields.

## Queue — ordered by value, unblocked first

- [x] **1. `ContractType` seed metadata.** ✅ DONE — six types in `metadata/contract-types/`, proven
      on a from-zero rebuild (wipe → migrate → codegen → sync). Original text: Today's types came from raw SQL in `demo/`. Author them as
      real `metadata/contract-types/` records so a clean install has them. Verify with a
      drop-schema → setup → sync cycle.
- [x] **2. Entity-server subclasses (invariants).** ✅ DONE — 16/16 tier-2 assertions pass. Original: `ContractEntity` / `ContractTermEntity`:
      auto-assign `ContractNumber` from `ContractSequence`, default `PricedAt` to today, derive
      `TermNumber` as max+1. These are the rules that must hold no matter who writes the row.
- [x] **3. Status transitions.** ✅ DONE — `ActivateTerm` / `RenewTerm` / `TerminateContract`, 38/38
      tier-2 assertions. **Built as REMOTE OPERATIONS, not Actions** — orders settled the family
      convention (Actions = agent/workflow-invocable; operations that MUTATE = the API the UI calls),
      which overrides master plan §10.5. Raised for Amith on PR #2 rather than changed silently.
      `SendForSignature` / `RecordExecution` / `RecordRejection` come after the signature panel.
- [x] **3b. Lifecycle wired into the UI.** ✅ Activate / Renew (with a real preview) / Terminate in the
      workspace, driven through the app's own generated typed clients. Needed `RemoteOperations` added
      to `mj.config.cjs` output — it was missing, so codegen emitted no client shells at all.
      Proven tier 3 (GraphQL) + tier 5 (10/10 real Chrome).
- [x] **3c. Coverage entry at creation.** ✅ **This was a real dead end:** `Create()` made a contract +
      term but NO lines, and `ActivateTerm` refuses an uncovered term — so nothing created in the app
      could ever be activated or renewed. The lifecycle only worked on seeded data. Fixed with a
      coverage editor on the create page; `ActivateTerm` now also promotes Draft → Active on the
      contract (a contract whose term is live is a live contract).
- [x] **4. Custom forms** for `ContractTerm` and `ContractLine`. ✅ DONE — priority-2 overrides, same
      pattern as the Contract form. Term reads period → committed → cadence → renewal → ending; Line
      reads covered → price → subscription → window. Every panel carrying a rule the server enforces
      says so next to the field, because a refusal a person could have avoided is worse UX than a
      sentence. Proven in Chrome that the OVERRIDE wins dispatch (the generated form would still look
      fine, which is exactly why that needed asserting).
- [ ] **5. BLOCKED — `<mj-record-files>` upload path.** 7 storage PROVIDERS are registered but
      **0 storage ACCOUNTS** are configured, so nothing can be uploaded and nothing could be
      demonstrated. Which provider and whose credentials is Marcelo's call. Original:
      **5. `<mj-record-files>` upload path.** The panel lists linked files; wire attach through MJ's
      storage providers and create the `FileEntityRecordLink` row.
- [ ] **6. BLOCKED — signature panel.** Reading `__mj.SignatureRequest` works, but there are 0 rows
      and 0 signature accounts, so the panel would render an empty state and prove nothing. Needs a
      provider account. Original:
      **6. `<mj-record-signature-status>` panel** on Contract + ContractTerm, reading
      `__mj.SignatureRequest` (`EntityID`/`RecordID`). Read-only first; sending needs a provider account.
- [x] **7. Tier-2 server test harness.** ✅ DONE — three harnesses, 85 assertions:
      `invariants.ts` (19), `lifecycle.ts` (45), `constraints.ts` (21, every one a REFUSAL).
- [x] **8. Unit tests** for the pure helpers. ✅ DONE — 32 Vitest assertions replacing this package's
      `echo "No tests configured yet"` stub, which passed vacuously. Helpers extracted to
      `lib/contract-format.ts` (decomposition, not a test seam — nothing was widened for a test) and
      the component now DELEGATES, so there is one implementation rather than two.
- [x] **8b. FEATURE-LIST contradictions.** ✅ DONE — X.5, X.6, X.9, X.12, X.14, X.15, X.16 all closed
      (4 CHECKs + 1 filtered unique index + 2 entity-layer guards), 19/19 refusal assertions in
      `test-harnesses/server/constraints.ts`. X.10 (ComputedAmount >= 0 forbids a credit) deliberately
      LEFT OPEN — it is a scope decision, raised on the PR rather than guessed. Naming the event
      vocabulary exposed a live split: the seed wrote `TermRenewed`, the operation wrote `Renewed`.
      Original: **8b. FEATURE-LIST contradictions worth fixing in schema** (from the enumeration agent):
      X.15 ContractEvent is neither immutable nor vocabulary-constrained · X.5/X.6/X.12/X.14 four
      missing "state implies field" CHECKs (Subscription line without SubscriptionTypeID, Superseded
      without successor, Generated without GeneratedAt, Approved without approval task) ·
      X.8 RenewalOfTermID may cross contracts · X.9 ContractLine.SubscriptionID is not unique
      (a duplicate-billing shape) · X.10 ComputedAmount >= 0 forbids a credit · X.16 mj-app.json
      still ships `"license": "<Set-this>"`.
- [x] **9. Workspace coverage editing.** ✅ DONE — clicking a coverage row opens the line in its own
      custom form, and an Add line control targets the contract's LIVE term (or the latest when none
      is live, and is disabled when there are no terms — rather than producing an orphan).
- [x] **10. `docs/ERD.md` re-checked against the live schema.** ✅ Entity and field lists were already
      correct (verified column-by-column, not assumed). What was stale was the CONSTRAINT
      documentation: added `Cancelled`, the `ContractEvent.EventType` vocabulary, a new §7.1 for the
      four state-implies-field CHECKs + the filtered unique index, and the three rules that live in
      the entity layer because no constraint can express them. Also corrected the table count back to
      10 — an earlier edit of mine said 11, counting Flyway's own history table. Original:
      **10. Regenerate `docs/ERD.md`** from the live schema after any migration change, and re-pin
      `plans/bizapps-contracts-master.md` §10.3.
- [ ] **11. PG conversion** (`mj migrate convert`) + CI wiring — the C6 tail.

## Blocked — do NOT guess these

| Item | Blocked on |
|---|---|
| `ContractPriceResolver` (C2) | **D-2** — whether the orders resolver slot is a general pre-walk or a dedicated `Agreement:` key, and how multiple registrants coexist (ClassFactory resolves one instance per key). Amith. |
| `Contracts.GenerateBillingEvent` (C3) | The two orders seams — `Subscription.BillingMode` and the resolver slot. Needs the orders PR, which needs D-2. |
| `Contracts.CreateFromDeal` caller | `bizapps-sales` does not exist. The operation can be built; nothing can call it. |
| Renewal `AsOf` semantics | **Andrew** — likely the individual subscription end dates. |
| `ContractLine → OrderLine` mapping (P-1) | Needed before renewal pricing is trustworthy. Design call. |
| Usage metering | Out of v1 by decision. |
| **PG conversion (item 11)** | **Neither bizapps-orders NOR bizapps-accounting ships a PostgreSQL variant** — both have the same SQL-Server-only layout we do. Making contracts the FIRST app in the family to carry PG migrations is a project decision about the family's direction, not a mechanical task, and doing it unilaterally would diverge from the structural model I am told to follow. Needs Amith. |

## Log

- **10:20** — **Design-token audit + a brittleness fix.** Checked the "MJ tokens for every control"
  standard properly rather than assuming: 96 of 97 hex values in the section were already correct
  `var(--mj-x, #fallback)` fallbacks; one bare `#fff` was not, now `var(--mj-text-inverse, #fff)`.
  The forms and panels audited clean. On dropdowns the family answer turned out to be documented in
  orders' own CSS — *"MJ styles `.mj-input, .mj-textarea` but ships no select rule"* — so orders
  defines `.mj-select` itself and accounting uses `.mj-input`. A native `<select>` with a
  token-styled class IS the convention; there is no MJ dropdown component being bypassed.
  Also removed a brittle assertion: "filtering to Active finds exactly one contract" is true of a
  pristine demo and false of any real system — and was already false the moment a test-created
  contract was left behind. It now asserts the demo contract is AMONG the matches and that every
  match really is Active, which is both robust and a stronger claim.

- **10:05** — **BaseEngine standard applied** (it was the one named standard with no implementation
  here — orders and accounting both have an engine, contracts had none). `ContractsEngine` caches
  `ContractType`, the app's only genuinely high-read/low-write entity; contracts/terms/lines are the
  opposite shape and caching them would trade a cheap query for a stale read.
  Its first real consumer: a NEW term now inherits `DefaultMaxEscalationPercent` and
  `DefaultRenewalNoticeDays` from its contract's type — which is what "the columns ARE the rules"
  means in practice, rather than a term being created with no ceiling at all.
  **That change broke a test, correctly:** `D.3 a null cap means uncapped` assumed a new Standard-type
  term has no cap, and now it inherits 5%. The RULE is unchanged; the fixture was stale. Rewritten to
  prove it on a SOW contract, whose type genuinely sets no default — plus a fixture-check that SOW's
  default really is null, and a complement asserting the SAME 20% IS refused on a Standard contract.
  A better test than the one it replaced. 92 tier-2 assertions now.

- **09:40 — QUEUE EXHAUSTED.** Every numbered item is DONE (1, 2, 3, 3b, 3c, 4, 7, 8, 8b, 9, 10) or
  BLOCKED on something only a person can decide (5 storage account · 6 signature account · 11 whether
  contracts should be the first app in the family to ship PG migrations).
  **Final sweep, all green: 32 tier-1 · 85 tier-2 · 69 tier-5 = 186 assertions.** Demo restored and
  verified pristine (terms=3 lines=3 audit=4 billing=3, zero cap violations).
  **The one unblocked thing I am NOT doing without a ruling:** rewriting the working overview editor
  onto MJ's 4-layer forms. It is the right change and the standards call for it, but it replaces a
  verified-working surface hours before a demo, and the term/line editing that most needed those
  shells already has them. That is Marcelo's call, not mine.

- **09:25** — **Item 10 done; item 11 BLOCKED and logged.** The ERD's entities and fields were already
  right — I verified column-by-column rather than assuming, which also caught that a header edit of
  mine had said "11 tables" by counting Flyway's `flyway_schema_history`. The genuinely stale part
  was constraints, now documented including the rules no CHECK can express.
  **Item 11 (PG conversion) is a STOP, not a task:** neither orders nor accounting ships a PostgreSQL
  variant — both have our exact SQL-Server-only layout. Making contracts the FIRST app in the family
  to carry PG migrations is a decision about the family's direction, and doing it unilaterally would
  diverge from the structural model I am told to follow. Needs Amith.

- **09:10** — **Item 9 done.** Coverage is editable, not just listed: row-click opens the custom line
  form, Add line targets the live term. Asserted on the CUSTOM panel names, because the generated
  form would also open and would also look fine — the failure mode being guarded is a lost
  registration, not a missing overlay. ui-navigation 25/25.

- **08:55** — **Item 8 done.** 32 tier-1 assertions, replacing a stub that passed vacuously. Worth
  recording HOW it went: I wrote the extracted module from what I assumed the component did, and the
  tests then disagreed with the shipped code — `Fill` returns `now|done|next` (the only three classes
  with CSS) and `Tone` returns `''` for the unrecognised, not `'info'`. **The implementation won**:
  changing rendering to match expectations I had just invented would have been backwards, and my
  `past`/`cut` would have rendered unstyled bars. The tests now pin the real behaviour and explain
  why it is that way. Run from the WORKTREE root — the app-root `npm test` cannot resolve turbo tasks
  from inside a dev-linked member.

- **08:10** — **Item 4 done.** Custom `ContractTerm` + `ContractLine` forms at priority 2. The term
  form is the one that matters: the generated version lists 21 columns in schema order, so
  `MaxEscalationPercent` sits next to `EscalationPercent` with nothing to say it is a NEGOTIATED
  CEILING the entity layer will refuse a save over. Now grouped and explained in reading order.
  Line form does the same for the three fields carrying invisible rules — null price means
  *resolve from the catalog* (not zero), subscription type is required here and forbidden elsewhere,
  and `SubscriptionID` is system-written and unique.
  Also fixed an assertion that had gone quietly wrong: in edit mode the fields render as `<input>`,
  and `innerText` does not include input values — so "the form carries real data" was testing
  something the DOM cannot show. It reads the input values now.

- **07:20** — **Final sweep, all green, demo pristine.** 85 tier-2 + 65 tier-5 assertions passing;
  both writing flows run and restore cleanly. **Invariants moved into MJ's `Validate()` /
  `ValidateAsync()`** so a refusal reaches the caller instead of only the server console — the
  workspace used to show "Save failed: unknown error" for a rule that had a perfectly good reason.
  That refactor **silently killed the cross-contract renewal guard** (`DefaultSkipAsyncValidation` is
  TRUE, so a rule in `ValidateAsync` is dead code without an override) and only the constraints
  harness noticed — the argument for asserting refusals, not just successes, in one incident.
  The status control now offers only the moves that will succeed, so the good error message is one
  nobody has to read.
  **Also caught by checking rather than trusting:** `restore-demo-after-loop.sql` deleted by
  EventType and so ate the SEEDED `TermActivated` event, quietly shrinking the demo's history by one
  entry every run. Now identifies the loop's events structurally; proven idempotent across two full
  loop+restore cycles (terms=3 lines=3 audit=4 billing=3, both times).

- **05:25** — **Coverage ledger + gap closing.** `testing.md` now exists (the protocol requires it and
  it did not): how to run every tier, a feature×tier matrix, and every remaining gap CODED with the
  reason. **80 tier-2 + 63 tier-5 assertions, all passing.** Closed gaps 5a/5b/5c with a new
  `ui-navigation.mjs` (21 assertions over the pages and tabs that had none). The History tab now
  renders a real audit timeline — event types as sentences, payload detail pulled out — which is where
  the invariant work becomes visible to a person.
  **Found while doing it:** (a) `CK_ContractLine_SubscriptionNeedsType` correctly refused the create
  page's own lines, because the page never collected a subscription type — the invariant was right and
  the UI had not caught up; it now demands the type BEFORE the save. (b) Gap **5f** — MJ's grid renders
  the entity's raw columns and does NOT take its column set from `RunViewParams.Fields`, so Coverage
  shows `ProductID` as a bare UUID. Recorded rather than fought after three attempts.
  **Four harness self-deceptions caught**, all of which had produced confident wrong results: a search
  asserted on the wrong page, nav clicks landing on a `<span>` inside the nav `<button>` (fixed by
  targeting by ROLE — which TEST-ARCHITECTURE already says), an unscoped `/^billing/i` matching the
  left-nav item instead of the workspace tab (a FALSE PASS that derailed the rest of the run), and
  contract types asserted by code when the page lists them by name.

- **03:20** — **Invariants hardened + questions posted.** PR #2 comment "AI questions from the
  overnight work" is up (10 items, each naming the guess and what changes if the answer differs) —
  https://github.com/MemberJunction/bizapps-contracts/pull/2#issuecomment-5189321195
  Then closed 7 of the 8 enumeration contradictions. **The baseline was dropped and re-migrated from
  the committed migration ALONE and everything re-verified on the rebuilt schema** — so the migration
  and the database provably agree, which matters because the baseline has been edited in place all
  night. Totals now: **tier 2 73/73** (16 invariants · 38 lifecycle · 19 constraints), **UI 17/17**
  across two Chrome harnesses, plus the create→activate 10/10 and full-loop 9/9 flows.
  Term and line editing now go through **MJ's 4-layer forms** (`MJFormPresenterService` slide-ins) —
  deliberately ADDITIVE; the working overview editor is untouched, since rewriting it the night
  before a demo risks the thing that is currently good for something merely more correct.

- **02:15** — **Items 3b + 3c done.** The lifecycle is now reachable AND usable end to end from
  nothing: create with coverage → activate → renew (preview then commit) → terminate. Verified at
  three layers (tier 2: 38/38 + 16/16 · tier 3: GraphQL · tier 5: 10/10 + 9/9 real Chrome, console
  clean). **Three real defects found, none by a passing test:**
  (a) the seeded demo escalated term 2 by 6.67% under a 5% cap — data violating the invariant the
  entity layer enforces, spotted by LOOKING at a screenshot; the fixture now escalates 5% then 4%
  with committed amounts that are the arithmetic result (432,000 → 453,600 → 471,744).
  (b) creation produced unactivatable contracts (above).
  (c) activating a term left the contract in Draft while it was billing.
  Also two harness bugs that produced convincing FALSE results rather than errors: a loose
  `/contracts/i` locator matched the generated-schema card and never left Home while reporting "no
  terms"; and a roster round-trip typed into Explorer's global search, so a run "verified" a contract
  it had not created. Lesson banked: **loose locators do not fail, they succeed on the wrong thing.**

- **07:45** — **Item 2 done, proven.** `ContractEntityServer` + `ContractTermEntityServer` with a
  tier-2 harness: 16/16. Two real defects found while building: (a) a bare `OUTPUT` clause cannot be
  used on a table with triggers, and CodeGen puts an `__mj_UpdatedAt` trigger on every table — fixed
  with `OUTPUT ... INTO`; (b) the demo seed was planting its own `NET30` PaymentTermsType, which
  collided with orders' `Net30` under case-insensitive collation and failed orders' ENTIRE metadata
  push. Downstream adapts to upstream: the seed now ADOPTS orders' seeded lookups and creates only
  what orders genuinely does not seed (ProductType — verified zero rows after a full sync).
- **07:20** — Feature-enumeration agent returned: **221 features, all 48 CHECKs, 19 contradictions**
  in `plans/FEATURE-LIST.md`. It independently confirmed X.1 (escalation cap unenforced) and X.17
  (clean install cannot create a contract) — both now fixed by items 1 and 2. Remaining findings
  folded into the queue below.

- **07:10** — **Item 0 done.** Orders updated to `origin/mjdev/orders-flow` (PR #31), 22 commits
  including its regenerated baseline. Full rebuild from zero: wipe-db → core + common + tasks +
  accounting migrated by `mjdev reapply-migrations`; **orders hit the known TVP deadlock at batch
  307 again**, applied the documented `mj migrate` workaround; contracts migrated clean.
  Result: accounting 24 / common 11 / contracts 11 / orders 50 / tasks 20 tables. As predicted, our
  baseline needed NO UUID surgery — contracts hardcodes no orders UUIDs.
- **07:15** — **Item 1 done.** ContractType metadata seeded and verified from a clean install
  (10 contracts entities registered, 6 types present, Application row intact). Demo SQL no longer
  inserts types — metadata owns them, sharing the same pinned UUIDs.

- **06:30** — Branch cut from `mjdev/contracts-dev` @ `bb73c29`. PR watcher armed on
  MemberJunction/bizapps-contracts#2. Work loop scheduled every 23 min. Queue above is the plan of record.
