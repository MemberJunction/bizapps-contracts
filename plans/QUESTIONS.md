# bizapps-contracts — open questions (answer-first)

Every entry LEADS with the **Proposed solution** — the action already being implemented — and the
question follows as supporting information for the reviewer. **We proceed by default**; a reviewer's
ruling adjusts course rather than unblocking work. Only `OPEN — ⏸ HOLD` means we are genuinely
waiting, and that is reserved for decisions expensive to reverse.

Convention: `.mjdev-docs/PLANNING-SYSTEM.md` §7. IDs are append-only and never reused.

## Priority index

| # | Question | Reviewer | Status |
|---|---|---|---|
| [Q1](#q1) | May a contract be Active with no term? | Andrew | OPEN — proceeding |

---

<a id="q1"></a>

### Q1 · May a contract be Active with no term? — review: Andrew — added 2026-08-05

- **Status:** OPEN — proceeding
- **Requested reviewer:** Andrew (SoundPostAndrew)
- **Features:** contract lifecycle; the Active status

- **Proposed solution (what we are implementing):** **No — an Active contract must have at least one
  term, and an Active term must have at least one coverage line.** Both are enforced in
  `ValidateAsync` on the entity, so every writer gets the same answer: the UI, an operation, a
  fixture, an agent.

  The reasoning is that the header and the term carry different halves of an agreement. The header
  records WHO agreed and on what paper; the TERM records the dates, the money, the billing cadence
  and the coverage. A contract that is Active with no term is therefore live in name only — it
  cannot bill, cannot renew, and appears as current in every roster and report. The same argument
  one level down: a term with no coverage entitles the customer to nothing, and a billing run
  against it produces an empty draft with no error to explain why.

  The status machine already models this: contracts are born `Draft` and move to `Active`. Draft is
  where an agreement is assembled. Until today the entity could not compose a tree, so the ONLY
  possible order was save-header-then-add-term — which is why two existing test fixtures created
  contracts directly in `Active` and added terms afterwards. That constraint is gone: a contract,
  its terms and their coverage are now composed in memory and written in one transaction.

- **The question for Andrew:** (1) Is there a real business case for an Active contract with no
  term — for example, a signed master agreement whose first order form has not yet been papered?
  (2) If so, should that state be `Active`, or does it want its own status (`Executed`, say) that
  distinguishes "signed" from "running"? (3) Same question one level down: is a term ever
  legitimately Active with no coverage?

- **Context to share:** `plans/bizapps-contracts-master.md` §6; `ContractEntityServer.
  checkActiveHasATerm` and `ContractTermEntityServer.checkHasCoverageWhenActive`; integration checks
  `contracts-composition.CC8`, `CC12`, `CC15`, `CC16`.

- **What motivates this now:** the entity gained child collections on 2026-08-05, which made the
  rule both enforceable and cheap. Before that it could not have been enforced without refusing the
  only creation order available.

- **Fixed constraints (not up for debate):** whatever the answer, the rule lives in `ValidateAsync`
  on the entity rather than in the UI — a rule enforced anywhere else holds only until somebody
  saves the entity directly.

- **Additional context (for a verifying agent):** the two fixtures updated for this are
  `test-harnesses/server/lifecycle.ts` (main fixture and `mkFixture`) and
  `test-harnesses/server/invariants.ts` (B.4/B.5, which now use their own contract). Both were
  changed because the behaviour intentionally changed, not to make a red test green — they assert
  status-transition rules and were using a bare contract as a fixture convenience.

- **Answer:** _(pending)_
