# Open questions — answer-first

Convention (PLANNING-SYSTEM.md §7): every entry **leads with the action already taken**, so work never
stalls waiting for a reply. The question is supporting information. `⏸ HOLD` only where a decision is
expensive to reverse.

---

## Q-1 · Push permission is denied by workspace policy — the draft PR cannot be opened

- **Proposed solution / what I am doing:** committing every work item to `build/contracts-v2` locally,
  with self-describing messages, and continuing. Nothing is lost; it just isn't offsite.
- **Question:** `Bash(git push:*)` sits in the **deny** list of `MJDev/.claude/settings.json`, so the
  verbal go-ahead cannot reach the agent. Add a narrow allow rule
  (`Bash(git push origin build/contracts-v2:*)`), or push manually when back?
- **Reviewer:** Marcelo · **Raised:** 2026-08-18 · **Status:** OPEN
- **Consequence while open:** the review-as-I-go loop with the other agent does not exist.

## Q-2 · CodeGen AI enrichment on every iteration costs real money

- **Proposed solution / what I am doing:** following the explicit instruction — enrichment **ON** — and
  reducing cost by minimising the *number* of CodeGen runs rather than by disabling AI. I get the schema
  right before running it, and I verify enrichment truly ran via token spend in `__mj.AIPromptRun`
  rather than trusting MJ's `✔ Advanced generation completed`, which prints even when the provider call
  fails.
- **Question:** for throwaway rebuild loops, is AI-off acceptable so long as the **committed** capture is
  enriched?
- **Reviewer:** Marcelo · **Raised:** 2026-08-18 · **Status:** OPEN

## Q-3 · Amith's nod on R-16 (dropping the modification's template FK)

- **Proposed solution:** built without `ContractTemplateModification.ContractTemplateID`. The provision FK
  derives the template in every future, and the "provision must belong to a template this contract
  incorporates" rule replaces it (ERD §7.1).
- **Question:** this reverses an explicit Amith "keep". Adding the column back later is additive, so it is
  cheap to reverse.
- **Reviewer:** Amith, via Marcelo · **Raised:** 2026-08-18 · **Status:** OPEN — proceeding

## Q-4 · Migration of existing active contracts

- **Proposed solution:** none needed for the build; the schema and screens do not depend on it.
- **Question:** scope and source of the ground-truth list of active contracts.
- **Reviewer:** Andrew Schwartz Crane · **Raised:** 2026-08-18 · **Status:** OPEN — work item 13 blocked

---

## Answered

*(none yet)*
