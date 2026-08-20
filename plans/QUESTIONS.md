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
- **Reviewer:** Marcelo · **Raised:** 2026-08-18 · **Status:** ANSWERED 2026-08-18
- **Answer:** the deny rule was removed. `build/contracts-v2` pushes, PR #9 is open as a draft, and the
  review-as-I-go loop is running. Note the general lesson, since it cost a cycle to find: **deny
  outranks allow** in the permission model, so adding an allow rule alongside a broader deny does
  nothing — the deny line itself has to go.

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

## Q-5 · The Master Agreement's provision list — I will not invent legal text

- **Proposed solution / what I am doing:** shipping the seed *structure* (`metadata/contract-templates/`
  and `metadata/contract-provisions/`, ordered in `directoryOrder`, wired to the `Provisions`
  collection) with **no provision rows in it**, and building every screen against provisions created
  through the UI instead. Dropping in the real list is then one file, no code change.
- **The question:** where is the current Master Agreement, and what is its dated `SourceURL`? I need
  the numbered provisions with each clause's **heading, number, and full `ProvisionText`** (R-15 / D-16
  store the standard text so it can be read beside the negotiated one).
- **Why I am not guessing.** Every other seed in this app I could derive from the transcript and the
  rulings. This one is the actual wording of a contract the business signs. Plausible-looking clause
  text committed to `metadata/` would install into a real database and appear on screen next to a
  customer's negotiated language, and nobody downstream would know it was synthetic. The failure is
  silent and the blast radius is legal, so it is the one gap I am leaving open rather than filling with
  a best guess. Per the plan's own rule, ambiguity blocks certainty and never coverage — but this is
  not ambiguity, it is **absent source material**.
- **What is blocked, precisely:** nothing structural. `ContractTemplateProvisionID` is mandatory on a
  modification, so **finance cannot record a modification against a real contract until the real list
  exists** (plan item 4 calls this a prerequisite, not a nicety). Item 7's registry UI is how the list
  gets entered if no machine-readable source exists — a person can type it once.
- **Reviewer:** Marcelo (or Amith / Joanna for the document itself) · **Raised:** 2026-08-18 ·
  **Status:** ANSWERED 2026-08-18 — seeded and verified
- **Answer:** `https://bluecypress.io/masteragreement20260202/` (Marcelo). Captured: 16 sections,
  **71 numbered provisions**, all with verbatim `ProvisionText`, seeded and pushed clean.
- **The one thing worth carrying forward from this.** I first pulled the document through a
  summarising fetch, and it silently rewrote the text: 9.1's limitation of liability came back in
  sentence case instead of the original ALL CAPS, and 1.1's *"shall mean the particular company"*
  became *"means the company"*. Both read as faithful. Capitalisation in a liability clause can carry
  legal weight, and `ProvisionText` exists precisely so finance reads the standard clause beside the
  negotiated one — so a paraphrase there is worse than an empty column, because it looks
  authoritative. **Any recapture must parse the page source, not a summary of it.** The integrity
  check to re-run is in `.contract-provisions.json`'s comment block.


## Q-6 · `ContractTemplate.SourceURL` is NOT NULL — which forecloses a file-only template version

- **Proposed solution / what I am doing:** leaving the column NOT NULL and changing nothing. The
  primary case is a Blue Cypress-hosted URL we maintain, which the current shape suits exactly, and
  loosening a NOT NULL later is additive and cheap while tightening one is a data migration.
- **The question:** the ERD asks a template version to record *"a public URL that never goes away"*.
  Two parts, and only one is answerable in the schema. **Reachability cannot be enforced at all** —
  whether a URL still resolves is a fact about the outside world, so no `CHECK`, trigger or subclass
  can assert it, and format validation (`https://…`) is weak because a well-formed dead link passes.
  What IS a real decision is whether NOT NULL is right: it forecloses a template version that exists
  only as an **attached file**, which is a supported shape everywhere else here — documents attach
  through `__mj.FileEntityRecordLink` and this schema ships no named file column on purpose (R-8).
- **The options, if it matters:** (a) keep NOT NULL and accept that a file-only version records the
  file's URL; (b) make it nullable plus a rule that a template has *either* a `SourceURL` or a linked
  file — the both-or-neither shape of `CK_Contract_CreatingPairBothOrNeither`, but cross-table, so
  subclass-tier rather than a `CHECK`.
- **Reviewer:** Marcelo · **Raised:** 2026-08-19 · **Status:** ANSWERED 2026-08-19
- **Answer (Marcelo):** *"NOT NULL is wrong for now."* The column becomes nullable. The conditional
  rule — a URL **or** an attached file — is wanted but cannot be enforced at entry time, and the
  reason is ordering rather than verdicts: a file links through `__mj.FileEntityRecordLink` keyed on
  `RecordID`, so **it cannot be attached to a record that does not exist yet**. A remotable operation
  was considered and rejected for the same reason — it would restate a rule the save channel already
  carries (D-24 rung 4) without solving the create-ordering problem.
- **Refined the same day (Marcelo):** refusing the referencing contract would work, but reads as
  confusing to a user. A template with neither is **incomplete, not invalid** — an ordinary state to
  pass through while authoring one. So the requirement becomes a **derived `IsUsable` bit** in an
  app-owned layered view (the same shape as `Contract.IsAwaitingDocument`: a column plus an `EXISTS`
  over `FileEntityRecordLink`), which the UI renders as a red "Unusable" chip until a URL or a file
  exists. Visible and fixable, rather than discovered by being blocked.
- **Routed to** `plans/backend-requirements.md` **R-12**, which carries the migration, the view pair
  and the UI work. Whether a contract should ALSO be refused for citing an unusable template is left
  open there — cheap to add once the flag exists, and recommended only if it turns out to happen.


## Answered

*(none yet)*

## Q-R6a · Should `MODIFICATION_REQUIRED_FIELD_PROSE` exist at all? — OPEN (Marcelo asked 2026-08-20)

**Proposed solution (implemented, proceeding by default): KEEP it.** It is not a workaround for the
message-plumbing bug, so #3973 landing does not make it redundant. But the maintenance question is
real and the reviewer should rule.

**The question as asked:** is the prose map in `packages/Entities/src/ContractTemplateModificationEntity.ts`
actually accounting for the message issue the other agent is fixing in
[MJ#3973](https://github.com/MemberJunction/MJ/pull/3973) — in which case we should delete it and pull
their changes in instead?

**Answer: no. They fix different layers, and both are needed.**

| | What it fixes | Without it, the user sees |
|---|---|---|
| **MJ#3973** (+ the `ResolverBase` follow-up) | **HOW** a refusal travels — `CompleteMessage` rendered `ValidationErrorInfo` as a JSON blob, and update/delete never called it at all | `{"Source":"ModificationText","Message":"…","Value":null}` — or, on an update, the literal text `Unknown error` |
| **The prose map** | **WHAT** the refusal says — replaces MJ's `"<Display Name> cannot be null"` | `Modification Text cannot be null` — correct, field-named, and mute on what to do |

So with #3973 alone the user gets `"Modification Text cannot be null"` rendered cleanly. The map is
what makes it `"Record what this contract says instead of the standard clause…"`. Verified in this
order on a live instance: the prose only arrived at all *because* #3973 is applied locally, and it only
said something useful because of the map. **They compose; neither substitutes for the other.**

**The genuine review question underneath, which is worth ruling on:** is hand-written prose per field
worth its maintenance? Honest arguments both ways.

- **For keeping it.** These three fields are the app's reason to exist, and two of them are FKs whose
  flat message is actively unhelpful ("Contract Template Provision cannot be null" does not tell anyone
  to pick a clause). It also owns the DE-DUPLICATION, which is not cosmetic: `ModificationText`
  genuinely produces two absence errors (MJ's nullability check plus CodeGen's
  `ValidateModificationTextNotEmpty`), and something has to collapse them. Deleting the map means
  either living with the double error or writing a separate collapse.
- **Against.** It is a second place where a field's meaning is written down, keyed on string field
  names that a rename would silently orphan (mitigated: `fieldIsAbsent` returns false for a field the
  entity does not have, so a drifted key stops rewording rather than rewording the wrong thing — but it
  stops silently). And a per-field prose table does not scale to seven entities; if this pattern is
  right, it probably belongs in MJ as `EntityField.RequiredFieldMessage` metadata rather than in every
  app's subclass.
- **A third option worth considering:** put the prose in `__mj.EntityField.Description` (already
  displayed as form help text) and ask MJ to fall back to it in the nullability message. That is an MJ
  feature request, and it would delete this file from every app at once.

**Reviewer:** Marcelo. **Route the ruling to:** the R-6 item in `plans/backend-requirements.md`, and — if
the third option is chosen — a new entry in `MJ-UPSTREAM.md`.
