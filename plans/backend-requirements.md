# Backend requirements — validation we need to add

**Status:** plan, nothing implemented. Branch `build/backend-requirements`.
**Audit basis:** every rule ERD §7.1 promises was verified present in code on 2026-08-20, including
the one most likely to have been aspirational (`ContractTemplateModificationEntityServer` forcing the
parent `HasModifications` flag true on a standalone save — it does, `forceParentFlag`). So nothing
below is a broken promise. These are rules nobody wrote down yet.

**Coverage today.** 2 of 7 entities carry hand-written validation: `Contract` (shared `Validate` +
server `ValidateAsync`) and `ContractTemplateModification` (server). `ContractTemplate`,
`ContractTemplateProvision`, `ContractType`, `ContractTemplateType` and `ContractSequence` have none
beyond what CodeGen derived from CHECK constraints.

**Status marks.** `✅ READY` = decided, an agent may implement it as specced. `⏸ BLOCKED` = one named
question must be answered first. `🗣 DISCUSSION` = the design itself is still open; do not implement.
Items are marked from Marcelo's review of 2026-08-20.

---

## The three enforcement tiers, and how to choose

This app should pick tiers the way **bizapps-accounting** already does, because it has litigated this
and the pattern is proven there:

| Tier | Use it when | Accounting's example |
|---|---|---|
| **CHECK constraint** | The rule reads only columns of the SAME ROW | `CK_Contract_Dates` |
| **DB trigger** | The rule crosses rows or tables and must hold against ANY writer | `trg_JournalEntry_Immutability`, `trg_JEL_CompanyMatch` |
| **Entity subclass** | You want a field-named, actionable message — and for cross-entity reads | `GLAccountEntityServer` identity lock |

**A CHECK constraint cannot reference another table.** Every rule below that depends on a second
table is therefore trigger-or-code, never a CHECK.

**Accounting uses trigger AND code together where the stakes are high**, and that is deliberate: the
trigger is the floor nothing can bypass (raw SQL, a future service, another app), the subclass exists
so a human sees *"Code cannot change — identity fields are immutable from creation"* instead of a
constraint name. `JournalEntryBatchEntityServer` says so in-source: "The DB immutability trigger
freezes Approved/Sent/Posted content but does not police the [rest]" — floor plus judgment.

**The cost of a trigger** is that it is invisible from TypeScript, fires on paths you did not write,
and its message reaches the user as a raw SQL error unless code catches the case first. So: trigger
where a bypass would be *silent corruption*; code alone where a bypass would merely be *a bad edit by
someone using our own UI*.

---

## R-1 · A template's provisions must not change once a contract references them — ✅ READY

**Severity: highest.** This is the app's central promise, and nothing enforces it.

The ERD: a template version "never goes away, so a customer who signed in June 2026 stays bound to
the June 2026 version." But `ProvisionText`, `Title` and `ProvisionNumber` are freely editable on a
template that signed contracts already incorporate. Editing one silently rewrites what a customer
agreed to — and every `ContractTemplateModification` beside it now compares negotiated language
against standard language that was never offered. Nothing errors. The contract still renders.

**Tier: trigger + code**, exactly as accounting does for JE immutability.

- **Trigger** `trg_ContractTemplateProvision_Immutability` on `ContractTemplateProvision`
  `AFTER UPDATE, DELETE`: reject a change to `ProvisionNumber` / `Title` / `ProvisionText` (and any
  DELETE) when `EXISTS (SELECT 1 FROM Contract c WHERE c.ContractTemplateID = <the provision's
  template>)`. Cosmetic fields (`Description`, `Sequence`) stay editable — ordering a document is not
  changing its terms.
- **Code** `ContractTemplateProvisionEntityServer.ValidateAsync()`: the same rule, as a message that
  names the field and says what to do instead — *publish a new template version; a signed version is
  a historical record.* Use the `field.OldValue !== field.Value` dirty-check shape from
  `GLAccountEntityServer.LOCKED_IDENTITY_FIELDS` rather than a DB probe for the field comparison, and
  one `RunView` `count_only` for the "is it referenced" question.

**RULED (Marcelo, 2026-08-20): gate on ANY reference.** A person drafting does not expect the
provision to shift under them either, so the Draft carve-out buys nothing and costs a hole.

### Cost, and the one trap that is not about cost

The probe is `EXISTS (SELECT 1 FROM Contract WHERE ContractTemplateID = @t)`. MJ auto-indexes every
FK (`IDX_AUTO_MJ_FKEY_Contract_ContractTemplateID`), so it is an index seek that stops at the first
hit — a handful of logical reads, at any contract volume this app will ever see. Two conditions keep
it there:

1. **Write the trigger SET-BASED** — one `EXISTS` over `inserted`/`deleted` joined, never a cursor or
   a per-row probe. A bulk provision edit then costs one probe per STATEMENT. Accounting's
   immutability triggers are written this way; copy their shape.
2. **Compare OLD vs NEW values — do not merely detect that an UPDATE happened.** This is the trap,
   and it is operational rather than performance. `metadata/contract-provisions/` is pushed by
   `mj sync push`, which UPDATEs existing provision rows, and **a trigger fires on UPDATE even when
   every value is identical**. So the moment any contract references the MA, a routine seed re-push
   would start failing — the path this repo uses constantly. Accounting's triggers dodge exactly this
   by comparing (`i.EntryNumber <> d.EntryNumber OR …`), which lets an identical re-push pass
   untouched. **Not optional.** A trigger written without the value comparison will break
   `mj sync push` and the breakage will look like a metadata problem, not a trigger problem.

## R-2 · ~~Four CHECK constraints have no code-level validation~~ — WITHDRAWN, the premise was false

> ⚠ **CORRECTED 2026-08-19 (main agent).** This item said CodeGen generated validators only for the
> three single-column constraints. It did not: **all seven `Contract` CHECK constraints have a
> generated `Validate()` counterpart**, and both `ContractSequence` constraints do too. Verified in
> `packages/Entities/src/generated/entity_subclasses.ts:1397-1405`, which calls
> `ValidateCreatingEntityAndRecordCoexistence`, `ValidateEndDateAfterOrEqualToEffectiveDate`,
> `ValidateParentContractIDNotEqualToID` and `ValidateSupersededByContractIDNotSelf` — the four named
> below as missing — each with a field-named `Source` and readable prose
> (*"The contract end date must be on or after the effective date."*).
>
> **Implementing this item would have produced a second copy of four working rules**, in the shared
> class, where they would drift from the generated ones the next time a constraint changed. That is
> the exact failure the plan's own §7.2 forbids.
>
> What IS missing is the `IN (…)` constraints — see **R-9**. Those genuinely have no TypeScript
> counterpart, and the reason is instructive: CodeGen renders them as value-list metadata rather than
> as validators, which is defensible, but MJ then never validates the list.
>
> **Re-checked 2026-08-20 at Marcelo's request, and it holds — with one refinement.** All four
> validator bodies were read against the `CHECK` expressions in the baseline migration and are
> semantically equivalent. The baseline itself settles the intent, in a comment above
> `CK_Contract_CreatingPairBothOrNeither`: *"CodeGen derives the generated validator from this
> expression, so each column is named ONCE"* — the schema author wrote these constraints **expecting**
> the validators, and even records the failure mode of getting it wrong. This was never an oversight.
>
> **The one real divergence, which is narrow and worth knowing rather than fixing.**
> `ValidateCreatingEntityAndRecordCoexistence` treats an EMPTY STRING as absent
> (`!= null && !== ""`); the SQL `CHECK` treats it as present, because `''` is not `NULL`. So
> `CreatingEntityID = NULL` with `CreatingRecordID = ''` passes in TypeScript and is refused by the
> database. TypeScript is the more permissive of the two, which is the safe direction for a
> divergence — the floor still holds — and the case needs someone to write an empty string into a
> polymorphic record id.
>
> **Whose problem is that divergence? Neither ours nor a filed MJ bug, and the reason generalises.**
> These validators are written by CodeGen's `ParseCheckConstraints` **AI** pass — which is on in this
> instance (`enableAdvancedGeneration: true`) and is visible in the generated prose itself
> (*"This prevents circular references in the contract hierarchy"* is not something a T-SQL parser
> writes). So a generated validator is an **AI interpretation of the constraint, not a mechanical
> translation of it**. Treating `''` as absent is a defensible reading a careful human would also
> likely write; it simply is not identical to `IS NULL`.
>
> The durable consequence, which is worth more than the specific case: **do not assume a generated
> validator is exactly equivalent to its `CHECK`.** The constraint remains the floor — that is why it
> is still in the database — and the validator is there to produce a good message before you reach it.
> Where an exact rule matters more than a friendly message, write it explicitly rather than relying on
> what was generated. Not filed upstream: non-equivalence is inherent to an AI-authored translation
> rather than a defect in it, and there is no bug report that would change the design. Worth revisiting
> only if a divergence is ever found in the UNSAFE direction — TypeScript accepting what the database
> would reject in a case a user can actually reach.

The original text follows, struck through, so the reasoning is not lost:

~~These four have no counterpart, so violating them produces a raw SQL constraint error rather than a
message on the offending field:~~

| Constraint | Rule |
|---|---|
| `CK_Contract_Dates` | `EndDate >= EffectiveDate` when both set |
| `CK_Contract_ParentNotSelf` | a contract is not its own parent |
| `CK_Contract_SupersededNotSelf` | a contract is not its own successor |
| `CK_Contract_CreatingPairBothOrNeither` | `CreatingEntityID` and `CreatingRecordID` are both set or both null |

**Tier: SHARED `Validate()`** — and note *why* that is available: all four read only fields of the
row in hand, so the browser can preflight them with no round trip, which is the same reason the
`HasModifications` guard lives in the shared class (§7.1). No trigger needed; the CHECK is already
the floor.

Keep the messages field-named (`ValidationErrorInfo` `Source` = `EndDate`, `ParentContractID`, …) so
the form marks the field rather than showing a banner.

## R-3 · Lineage cycles — ✅ READY

**How the hole works.** The two CHECKs stop only `A → A`. Nothing stops `A → B → A`, or a longer
ring, in either `ParentContractID` or `SupersededByContractID`. Each individual save looks perfectly
legal: setting B's parent to A is fine, and later setting A's parent to B is fine *in isolation* —
the row being written references a different row, which is all a CHECK can see.

**Can a save-time check prevent it, efficiently? Yes.** The insight is that a cycle can only be
*created by the edge you are adding*. So the question at save time is narrow: **starting from the
proposed parent, can I reach myself?** One upward walk:

```sql
WITH lineage AS (
    SELECT ID, ParentContractID, 1 AS Depth
      FROM __mj_BizAppsContracts.Contract WHERE ID = @proposedParentID
    UNION ALL
    SELECT c.ID, c.ParentContractID, l.Depth + 1
      FROM __mj_BizAppsContracts.Contract c
      JOIN lineage l ON c.ID = l.ParentContractID
     WHERE l.Depth < 50
)
SELECT TOP 1 1 FROM lineage WHERE ID = @thisContractID;
```

**It is cheap for the reason the data is shaped well:** the walk follows a single indexed FK one row
per level, and change-order chains are 1–3 deep in practice. The `Depth < 50` bound matters twice —
it caps the walk, and it means an *already-corrupt* ring terminates instead of spinning. Run it only
when the FK is dirty (`field.OldValue !== field.Value`), so ordinary saves pay nothing.

**Tier: server `ValidateAsync`** for both self-references. A trigger is defensible later if we decide
the floor matters, but unlike R-1 a cycle corrupts nothing silently — it makes the Lineage panel walk
forever, which is loud.

**Related finding, needs a decision.** `RootParentContractID` and `RootSupersededByContractID` are
registered as **virtual `EntityField`s in MJ metadata but exist neither as table columns nor in
`vwContracts`**. Someone intended a root-pointer walk and it was never built. Contract loads
currently work, so this is not breaking anything today — but it is metadata describing fields
nothing returns, which is the exact shape of the `IsChangeOrder` trap we just removed. Either build
them (a recursive view column, which then *needs* R-3 to terminate) or delete the metadata rows.

## R-4 · Modifications, templates, and the contract tree — ✅ READY

Ruled: **a contract that needs a template must have one, and a modification may point at any template
at or above it in the tree.**

That second half is new and it changes the EXISTING consistency rule. Today
`ContractTemplateModificationEntityServer` compares the provision's template against the contract's
own single `ContractTemplateID`. Under the tree model it must compare against the **ancestor set** —
the templates reachable at or above this contract via `ParentContractID`. The reason is the change
order: a change order carries no template of its own but is the child of a contract that does, and a
modification recorded ON the change order is where the negotiated wording physically lives. So the app
must be able to say *"this modification is written in the change order, and it may point at anything
at or above that change order in the tree."*

### The type gains a second rule column

`ContractType.TemplateRequired BIT NOT NULL DEFAULT 0` — whether a contract of this type must carry
its own `ContractTemplateID`. Today only the root type needs one, but a future type could differ,
which is exactly why it belongs on the type rather than being inferred from `ParentStatusRequirement`.

### RULED — `ParentStatusRequirement` is replaced by two booleans

Marcelo, 2026-08-20: the three-state string was confusing and overly complex, and the transposition
argument above is the proof — a column whose values invert the rule when read in the wrong order is a
column that will be read in the wrong order. **Replace it with two flags:**

```sql
MustBeRoot  BIT NOT NULL DEFAULT 0   -- may not name a ParentContractID
MustBeChild BIT NOT NULL DEFAULT 0   -- must name one
CONSTRAINT CK_ContractType_RootOrChild CHECK (NOT (MustBeRoot = 1 AND MustBeChild = 1))
```

Both false = no restriction on where in the tree this type may sit, which is the honest default.
"Only one may be true" is a same-row rule, so **the CHECK is the right tier** — and CodeGen will
generate a TypeScript validator for it, exactly as it does for the two-column
`CK_Contract_CreatingPairBothOrNeither` (see the R-2 correction; multi-column CHECKs are handled).

| Type | MustBeRoot | MustBeChild | TemplateRequired |
|---|---|---|---|
| Statement of Work | **true** | false | **true** |
| Change Order | false | **true** | **false** |

Every other type: all three false.

**This reworks shipped code.** `ParentStatusRequirement` was merged in PR #10 — the column, its CHECK,
its metadata seed, the `typeRule()` read and both branches of the server validation. Dropping it is
part of this item, not a follow-up: two overlapping mechanisms for one rule is worse than either.
The validation becomes `MustBeChild && !ParentContractID` → refuse, and
`MustBeRoot && ParentContractID` → refuse, with the same messages.

### Removing Order Form and Payment Link — RULED: retire

Contracts does no billing, so both go. They are **in use by 7 of 9 contracts** (Order Form 5, Payment
Link 2) and every FK is `NO_ACTION`, so a DELETE is simply refused. Ruled: **retire them with
`Status = 'Inactive'`** via metadata, and let the demo rows age out.

Marcelo's note on why this is the better path anyway: it **gives us a live test of R-5** — two
genuinely retired types, referenced by existing contracts, is exactly the state the
Inactive-selection rule has to handle correctly (existing contracts keep working; new selection is
refused).

### The rules to implement, once unblocked

- **Modification side** — reject when the parent contract's ancestor set contains no template at all,
  and reject when the provision's template is not IN the ancestor set. One recursive walk plus a join;
  see R-3 for why the walk is cheap.
- **Contract side (certain half, implement now)** — reject clearing `ContractTemplateID` when the
  type's `TemplateRequired` is true, and reject clearing it while modifications on THIS contract point
  at provisions of THAT template.
- **Contract side (full half, DEFERRED — sequenced after the tree model, ruled 2026-08-20)** — the complete rule is *"reject clearing when
  a modification anywhere in the tree references that template and it is not reachable elsewhere in
  the tree."* Marcelo asked whether the `and it is not present elsewhere` clause is too expensive: **it
  is not** — it is the same recursive walk R-3 already needs, chains are 1–3 deep, and modifications
  are indexed by contract, so the whole check is dozens of logical reads. **Keep the clause; do not
  weaken it.** The reason to defer is not cost but sequencing: this rule, the modification rule above,
  and the post-execution lock (R-9) all read the same ancestor set, and writing that walk once against
  a settled tree model beats writing it three times.

## R-5 · An Inactive type must not be newly selected — ✅ READY

Ruled, with the qualifier that matters: **this is a modification check.** A contract that already
references a type keeps working — we assume the type was Active when it was chosen — so the rule fires
only when `ContractTypeID` (or `ContractTemplateID`, whose type carries the same `Status`) is **dirty
and pointing at an Inactive row**.

**A CHECK cannot do this** — `Status` lives on another table. Ruled: **a trigger is not worth it
here**, because the failure mode is a user picking a retired value in our own UI, not silent
corruption. So: code only, enforced in `ValidateAsync`, using the same `field.OldValue !== field.Value`
dirty-check shape as everything else, with one `count_only` when the FK changes.

This also makes the Configuration page honest — it currently promises that an Inactive type "stops
being offered for new contracts", which today nothing enforces.

## R-6 · A modification must say what was agreed — ✅ READY

- **`ModificationText` becomes NOT NULL** (migration + validation). A modification that asserts "this
  provision was negotiated" without recording the negotiated language is the one row in this schema
  that cannot be worth keeping — the standard-clause-beside-negotiated-language pair is the app's
  reason to exist.
- **`Notes` stays nullable** — commentary is genuinely optional.
- **`ContractID` and `ContractTemplateProvisionID` are already NOT NULL** at the database level, so
  this is a message-quality task, not a correctness one: add field-named validation so a missing
  contract or provision reads as *"choose the provision this modification changes"* rather than as a
  NOT NULL violation.

**The UI-side rule folds in here (ruled 2026-08-19, Marcelo).** `modification-editor.component.ts`
currently enforces this on its own — `[disabled]="!DraftText.trim()"` on the *Add to list* button —
which is the app's only statement of the rule and reaches exactly ONE of the three write paths. The
generated modification form and any API caller write NULL happily. So: the requirement moves onto the
entity, and **the UI check is deleted rather than kept as a belt-and-braces preflight**, because once
`ModificationText` is NOT NULL the generated form derives the requirement from the column itself and
`mj-form-field` marks it. A hand-written disable that duplicates a metadata-derived rule is a second
copy that drifts. This is the merge of what was raised separately as a frontend-enforcement finding —
**R-6 is its single home.**

**Migration order (ruled 2026-08-20):** backfill filler text into any NULL rows in the same
migration, THEN `ALTER COLUMN … NOT NULL`, then re-run CodeGen so the generated entity and its
validation reflect non-nullable. Written idempotently and for a database that already has data, per
`docs/database-migrations.md`. Do not let `ALTER COLUMN` meet a NULL and fail — that leaves the
migration half-applied on exactly the databases that have real content.

## R-7 · Replace `ContractSequence` with a real SQL sequence — ✅ READY

**Accounting does not solve this, so there is nothing to copy.** All six sequence entities across the
three apps are fully writable through the API:

| Entity | AllowCreateAPI | AllowUpdateAPI | AllowDeleteAPI |
|---|---|---|---|
| Journal Entry Batch Sequences | true | true | true |
| Journal Entry Sequences | true | true | true |
| **Contract Sequences** | true | true | true |
| Order Sequences | true | true | true |
| Payment Sequences | true | true | true |
| Subscription Sequences | true | true | true |

So a user can edit `NextSequenceNumber` downward in any of them and mint duplicate numbers until the
unique index starts rejecting saves. It is a family-wide hole, and worth telling the accounting and
orders owners rather than fixing only ours.

### Does the sproc use something separate from the entity? Yes — completely

That is the whole point, and it is why the entity surface is pure liability:

- **`ContractSequence` is a TABLE.** Because it is a table, CodeGen registered it as an MJ **entity**,
  which is what gives it a grid, a form and writable API flags.
- **`spAssignNextContractNumber` never touches that entity.** It runs
  `UPDATE … ContractSequence WITH (HOLDLOCK, UPDLOCK)` — raw SQL against the table, bypassing
  `BaseEntity` entirely. So nothing legitimate reads or writes the row through the entity layer.
- Therefore the editable entity is a surface that exists only for a user to break: edit
  `NextSequenceNumber` downward and the sproc happily re-mints numbers already in use, until
  `UQ_Contract_ContractNumber` starts rejecting saves — one contract at a time, with no hint why.

**A SQL Server SEQUENCE is a different KIND of object, not a table.** `CREATE SEQUENCE` +
`SELECT NEXT VALUE FOR …`. It is atomic by design, needs no `HOLDLOCK`/`UPDLOCK`, and — the part that
matters here — **CodeGen never sees it, because it is not a table.** No entity, no grid, no editable
field, nothing to protect. The counter row, the table, the entity metadata and the hole all disappear
in one move, and the sproc keeps its name and signature so no application code changes.

### Will it survive a fresh install, a restart, and an upgrade over existing data?

Asked directly (Marcelo, 2026-08-20). Yes to all three, but each needs something specific:

**Fresh server → starts at the beginning. RULED: `START WITH 1`** (Marcelo, 2026-08-20) — the
existing format is `CTR-000001`, and starting at 0 would mint `CTR-000000` as the first contract.

**Server restart → recovers, never reuses; may skip. RULED: skips are fine here, keep the default
cache.** (Marcelo, 2026-08-20.)

The mechanism, in full, because it is finicky and the plan should not require re-deriving it:

- A sequence's **current value is persisted in the database catalog** (`sys.sequences.current_value`),
  not held in memory. So a restart — clean or not — can never hand the same number out twice. That is
  the guarantee that matters, and it holds unconditionally.
- For throughput, SQL Server **hands out values in cached blocks**. It writes the *end* of the block
  to the catalog once, then serves values from memory without touching disk again. Default cache size
  is engine-chosen (commonly 50).
- On a **clean** shutdown the unused remainder is written back, so nothing is lost. On an **unclean**
  one (crash, container kill, `docker stop -t 0`) the in-memory position is gone and the engine
  resumes from the catalog value — which is the END of the block it had reserved. Everything between
  the last number actually issued and that boundary is **skipped**: never used, never reused.
- So a hard restart after minting `CTR-000031` out of a block reserved to 50 makes the next contract
  `CTR-000051`. Numbers are still unique and still ascending; the sequence just has a hole.
- **`NO CACHE`** writes the catalog on every call, which removes the hole entirely at the cost of one
  extra write per contract.

**Why the default is right for contracts:** the numbering has never promised gap-free — the sproc it
replaces already burns a number on any failed save, and `UQ_Contract_ContractNumber` is the real
guard. A hole after a crash is cosmetic here.

**Where `NO CACHE` probably IS worth it — accounting's journal entries** (Marcelo's note). A JE number
is an audit artifact reviewers reconcile in sequence, and accounting's own sproc comment claims
gap-free numbering ("plan D19: gap-free, per company, per fiscal year"). If those ever move to
sequences, `NO CACHE` is the option that keeps that promise true. **Not our change to make** — worth
raising with the accounting owners alongside the R-7 sequence-table issue.

**Upgrade over an existing database → must be seeded from the data.** `CREATE SEQUENCE` cannot take a
subquery in `START WITH`, so the migration does it in two steps:

```sql
-- 1. create it low, unconditionally and idempotently
IF NOT EXISTS (SELECT 1 FROM sys.sequences WHERE name = 'seq_ContractNumber' …)
    CREATE SEQUENCE …seq_ContractNumber AS INT START WITH 1 INCREMENT BY 1;  -- default cache: skips OK

-- 2. then RESTART it above whatever has already been minted
DECLARE @next INT = (
    SELECT ISNULL(MAX(TRY_CAST(SUBSTRING(ContractNumber, 5, 20) AS INT)), 0) + 1
      FROM …Contract WHERE ContractNumber LIKE 'CTR-%'
);
EXEC(N'ALTER SEQUENCE …seq_ContractNumber RESTART WITH ' + CAST(@next AS NVARCHAR(20)));
```

`TRY_CAST` rather than `CAST` is load-bearing: a hand-entered or legacy number that does not match
`CTR-<digits>` returns NULL instead of failing the whole migration, and `ISNULL(...,0)` makes the
empty-table case start at 1. On this database that computes 27 — one past `CTR-000026`.

**One caveat to state rather than discover:** the current counter table and the new sequence must not
both be live. Drop the table in the same migration, so there is never a window where two mechanisms
could mint the same number.

**RULED (Marcelo, 2026-08-20): switch to the sequence here, and FILE the family-wide hole as issues
against accounting and orders** rather than fixing their tables from this repo.

Implementation, one migration:
1. `CREATE SEQUENCE` starting above the highest minted number.
2. Rewrite `spAssignNextContractNumber` to read it — the `HOLDLOCK`/`UPDLOCK` block goes away.
3. Drop the `ContractSequence` table and delete its entity + entity-field metadata rows (the same
   cleanup the `IsChangeOrder` removal needed — metadata describing a table that no longer exists is
   the trap, not the table itself).
4. Re-run CodeGen; the generated `mjBizAppsContractsContractSequenceEntity` and its two generated
   validators disappear with it.

**Interim option if step 1–4 is not scheduled immediately:** set `AllowCreateAPI` / `AllowUpdateAPI` /
`AllowDeleteAPI` to false on `MJ_BizApps_Contracts: Contract Sequences` (metadata only, no schema
change). Nothing legitimate breaks, because the sproc does not use the entity.

## R-8 · Deletes fail as raw foreign-key errors — ✅ READY

Every FK in the schema is `NO_ACTION`, which is the correct behaviour — a delete that would orphan
data is refused. But it reaches the user as an FK constraint message.

**Tier: code, `Delete()` override** on the parents people actually try to delete:

| Deleting | Blocked by | Message should say |
|---|---|---|
| `ContractTemplateProvision` | modifications referencing it | how many contracts negotiated this clause |
| `ContractTemplate` | its provisions, and contracts incorporating it | that signed contracts reference this version |
| `Contract` | modifications; children naming it as parent or successor | which contracts point at it |
| `ContractType` / `ContractTemplateType` | contracts/templates using it | that retiring means `Status = 'Inactive'`, not deleting |

One `count_only` per dependency, only on delete. The last row doubles as the fix for a real usability
trap: the Configuration page tells people to retire a type by setting Status, but the grid still
offers Delete with no explanation of why it fails.

### Where this code goes

**`BaseEntity` has no delete-validation hook** — no `ValidateDelete`, no `BeforeDelete`. The only seam
is overriding `public async Delete(options?: EntityDeleteOptions)` (`baseEntity.ts:4267`), checking
first and returning `false` with the message before calling `super.Delete()`.

**FILED UPSTREAM as a feature request: [MJ#3971](https://github.com/MemberJunction/MJ/issues/3971)**
(Marcelo, 2026-08-20) — MJ has a save-validation seam with a `ValidationResult` contract and field-named
errors, and no counterpart for delete, so every app hand-rolls this. Accounting already has two
overrides; contracts is about to add four. The issue proposes `ValidateDelete()` /
`ValidateDeleteAsync()`, or a vetoable `before_delete` event, or — the higher-value option — a generic
metadata-driven message derived from `EntityRelationship` when the provider reports an FK violation,
which would need no subclass at all. **Implement the overrides now regardless**; they are what the
issue asks MJ to make unnecessary, and they delete cleanly if it lands.

**Precedent exists in the family:** `JournalEntryTypeEntityServer.Delete()` and
`JournalEntryLineEntityServer.Delete()` in bizapps-accounting. Match their shape.

**Files** — server subclasses in `packages/CoreEntitiesServer/src/`, since every check is a
cross-entity read. Three of the four do not exist yet and must be created:

| New file | Guards the delete of |
|---|---|
| `ContractTemplateProvisionEntityServer.ts` | a provision modifications reference *(also the home for R-1's code half)* |
| `ContractTemplateEntityServer.ts` | a template with provisions or contracts |
| `ContractTypeEntityServer.ts` + `ContractTemplateTypeEntityServer.ts` | a type in use |
| `ContractEntityServer.ts` *(exists)* | a contract with modifications or lineage children |

Each new file needs its `@RegisterClass(BaseEntity, '<entity name>')`, an export from the package
index, and an entry in the anti-tree-shake anchor — and then `class-registration.test.ts` must be
updated, because it asserts which class each entity name resolves to and will fail on a new subclass
that is not listed. That test failing is the system working.

---

## R-9 · Value-list fields are validated NOWHERE — and the plan says otherwise — **IMPLEMENTED**

**This is the real version of what R-2 tried to describe, and it is filed upstream:
[MJ#3969](https://github.com/MemberJunction/MJ/issues/3969).**

> ✅ **DONE 2026-08-19.** `packages/Entities/src/value-list-validation.ts` (`ValidateValueLists`),
> called from two new shared subclasses in `ContractTypeEntity.ts`. 7 unit tests, three of which pin
> the EXCLUSIONS (`ListOrUserEntry`, an unseeded value set, null) because a guard that rejects too
> much is worse than the gap. Suite 69/69, build 6/6 exit 0. `class-registration.test.ts` caught the
> new registrations and its expectation table was updated — the guard stayed, the expectation moved.
> Delete the file, the two `ValidateValueLists` calls and the test when MJ#3969 lands.
>
> **Upstream is under way (2026-08-19):** another agent is fixing MJ#3969. Nothing here changes until
> it ships — the stopgap and the upstream fix produce the same errors from the same metadata, so they
> can coexist safely; the only cost of leaving ours in after the fix lands is a duplicate message, and
> the file header says how to remove it in one commit.

Three fields carry an exhaustive value set: `ContractType.Status`, `ContractTemplateType.Status`,
`ContractType.ParentStatusRequirement`. Each has a `CHECK (… IN (…))` in the database and
`ValueListType='List'` plus `__mj.EntityFieldValue` rows in metadata.

**Nothing validates membership at any rung.** `EntityField.Validate()` checks nullability, `MaxLength`,
date parseability and numeric range, and never reads `EntityFieldValues` —
`grep -rn "ValueListType\|EntityFieldValues" packages/MJCore/src/generic/baseEntity.ts` returns
nothing. The metadata is consumed only by the UI (`form-field.component.ts` `PossibleValues`). So an
out-of-list value passes layers 1–5 and is refused by SQL Server as a raw, unattributed constraint
violation.

**It is not a CodeGen failure.** Turning `CHECK (Status IN ('Active','Inactive'))` into a value list
rather than a validator is the right call — the value list is what the dropdown needs. The gap is that
MJ never validates it, which leaves this class of constraint with **no TypeScript counterpart at all**,
so neither a client nor a subclass can preflight it.

**The dropdown is not the answer**, and is probably why this went unnoticed: it protects the *form*
path only. `mj sync push`, the GraphQL mutations, an Action, a subclass setting the field in code and
any data load are all unguarded — the paths where a typo is least likely to meet a human first.

**It also makes D-24 rung 1 untrue as written.** The ladder promises *"generated validation from the
schema (CHECKs, nullability, value lists). Free everywhere; never restated by hand."* True for CHECKs
and nullability, false for value lists. Because the failure is silent, the belief survives review —
that is what earned this its own item rather than a footnote.

**Tier: shared `Validate()`, as a generic helper, explicitly as a stopgap.** Not three hand-written
checks — a loop over `this.Fields` asserting membership for `ValueListTypeEnum === 'List'`, so it
covers every present and future value-list field without naming any of them. Three details decide
whether it is safe:

1. **`List` only, never `ListOrUserEntry`** — the latter exists to permit values outside the list.
2. **Skip an empty value set** — a `List` field whose `EntityFieldValue` rows are unpopulated must not
   reject everything.
3. **Leave null to the nullability check** — one mistake should produce one error, not two.

Put it where it can be deleted in one commit when MJ#3969 lands, and say so in the file header.

## R-10 · Uniqueness is enforced nowhere above the database — ✅ READY

> Marked ready 2026-08-20 (main agent, reviewing the second agent's item). It picks a pattern per
> rule from established family precedent, the picker fix costs nothing extra on a read that already
> happens, and no schema or product decision is pending. The `RelatedEntityFilter` idea noted at the
> end is a possible MJ feature request, not a blocker.

Six unique indexes (`docs/ERD.md` §3.2), none mirrored in TypeScript. The one a user reaches by
ordinary use is `UQ_ContractTemplateModification_Contract_Provision`: the modifications editor's
picker does **not** exclude provisions already modified, so a duplicate can be staged and dies at save
as a raw unique-violation.

**What the family already does, since this was worth checking before inventing a policy.** Three
distinct patterns exist across the sibling apps, and they are chosen by the shape of the rule:

| Pattern | Where | When it is used |
|---|---|---|
| **DB-authoritative, no TS check** | `GLAccountEntityServer` — *"Code format/uniqueness are DB CHECK/UQ constraints"* | a plain single-column unique the UI cannot realistically collide with |
| **TS pre-check in `ValidateAsync`** | `GLAccountLinkEntityServer`, `IntercompanyAccountMatchEntityServer` — *"They are duplicated on purpose"* | **conditional/filtered** uniqueness a plain UQ index cannot express, or where the message is worth a round trip |
| **Translate the DB error** | orders' `CapturePaymentOperation` — `/UX_PaymentHeader_IdempotencyKey\|duplicate key/i.test(message)` | a hot path where a pre-check would be a wasted read most of the time |

So: **do not add a pre-check for the other five.** They are single-column uniques on names and on a
server-minted number; the index is the right and cheapest floor, and a `RunView` before every save to
restate it would be pure cost. Accounting reached the same conclusion in writing.

**Do add one for the modification pair**, and for the reason accounting gives — the message. Two
things, both cheap:

- **Preflight in the editor**: the picker already issues its own `RunView` for the template's
  provisions, so filtering out the ones the contract has already modified costs nothing extra and
  removes the error entirely for the normal path.
- **Rule on the shared subclass**, covering the API and the standalone form: the collection is in hand
  during a graph save, so a duplicate among *staged* rows is detectable with no query at all. The
  saved-rows case needs one `count_only` and belongs in the server subclass.

**There is no organic MJ path for the picker.** Checked, because it would have been the better answer:
`EntityField` has no filter column (only `RelatedEntity*` ones), and `form-field.component.ts` builds
its FK-dropdown `ExtraFilter` from the typed search query alone. A metadata-declared scoping filter on
an FK picker does not exist. Ours is a bespoke component that owns its own read, so we can simply do
it — but a `RelatedEntityFilter` on `EntityField` is a reasonable MJ feature request if this recurs.

## R-11 · Delete `ContractTemplateProvision.Sequence`; order from `ProvisionNumber` — ✅ READY

> Marked ready 2026-08-19 (Marcelo). Two things unblocked it. **The design question** — maintained
> column vs. derived — is answered below and measured against all 73 real provision rows. **The
> ruling** — this reverses ERD R-14, which kept `Sequence` because *"provision numbers do not sort as
> text and a legal document has a canonical order"*. The premise is correct and the conclusion does
> not follow: a derived sort key preserves the canonical order without a maintained column, and the
> kept column has **already failed at the job it was kept for** (see the collision below). Logged as
> **R-20** in `plans/ERD-planned.md` §9, per the reversal-log convention.

**`Sequence` is already wrong in the live data, which settles whether this is worth doing.** It is an
`int` defaulting to 0 with no unique constraint and no rule, and the seeded Master Agreement already
contains a collision:

```
ProvisionNumber   Sequence
'1'               1
'1.1'             1        <-- same order as its own parent section
```

Two rows in one template claim the same position, nothing errors, and the grid picks between them
arbitrarily. That is the failure mode of a hand-maintained copy of an order the `ProvisionNumber`
already states — the stored projection §7.2 forbids.

### Ordering by `ProvisionNumber` directly does not work

It is `nvarchar`, so string comparison puts `1.10` before `1.9` and `10.1` before `2.1`.

### The standard solution is natural sort, and JavaScript has it built in

This is a named, solved problem — the **alphanum algorithm**, a.k.a. natural sort; Windows ships it as
`StrCmpLogicalW`. No formula needs inventing:

```js
[...numbers].sort(new Intl.Collator(undefined, { numeric: true }).compare)
// 1.1 | 1.1A | 1.1B | 1.2 | 1.9 | 1.10 | 1.11 | 2.1A | 2.1D | 2.10B | 10.1 | 12.3
```

**Yes, it avoids the traps.** `Intl.Collator` compares runs of digits as NUMBERS and everything else
as text, so `1.10 > 1.9` and `1.1A` lands between `1.1` and `1.2` with no encoding step at all.

### Why the letter→digit encoding cannot work — recorded so it is not re-proposed

Mapping `A→1` and appending (`1.1A → 1.11`, `2.1D → 2.14`) reads well and collides as soon as any
segment reaches two digits. Measured:

| Input | Encodes to | Collides with |
|---|---|---|
| `1.10` | `1.1` | `1.1` — the tenth sub-clause becomes the first |
| `1.1A` | `1.11` | `1.11` — the eleventh sub-clause |

The root problem is that a decimal number has one decimal point, and a provision number has an
arbitrary number of independent segments. Squeezing the second into the first must lose information.

### The catch, and why a comparator is not enough

**The grid sorts server-side.** Pages come back already ordered by a SQL `ORDER BY`, so a JavaScript
comparator can only reorder the rows on the current page — which is not sorting, it is shuffling a
window. SQL Server has no natural-sort collation, so the order has to be expressible in SQL.

### What zero-padding actually does — the part that was unclear

String comparison walks left to right, character by character, and stops at the first difference. It
therefore compares the FIRST CHARACTER of one number against the FIRST CHARACTER of another —
regardless of how many digits each has. `'9'` vs `'1'` in `10` decides it: `9 > 1`, so `"9" > "10"`.
The comparison is not wrong, it is *misaligned* — it is comparing a units digit against a tens digit.

Padding fixes the alignment rather than the comparison. Give every number the same width and the
digits line up by place value, so character-by-character comparison becomes place-by-place comparison,
which is exactly what comparing numbers means:

```
unpadded:  "9"     vs "10"      -> compares '9' to '1'  -> wrong
padded:    "000009" vs "000010" -> compares '0' to '0', … , '9' to '1' at the last place -> right
```

It is the same reason dates are written `2026-08-19` rather than `8/19/2026`: fixed-width fields make
a plain text sort agree with the real order. Trailing letters keep working because they sit at the
same offset in both keys once the digits are padded, so `000001.000001` < `000001.000001A` <
`000001.000002` — `1.1`, `1.1A`, `1.2`. This is a **collation key** (a.k.a. sort key), a completely
standard technique; it is what ICU builds internally to make `Intl.Collator` fast.

### Store it as a PERSISTED COMPUTED COLUMN — indexable, and no layered view at all

The first draft of this item proposed a layered view. **Testing beat that answer**, and the result is
both simpler and faster. All three of the following were run against SQL Server before this was
written:

**1. The expression is deterministic, so `PERSISTED` is accepted.** It uses only `CHARINDEX`,
`PATINDEX`, `LEFT`, `SUBSTRING`, `RIGHT`, `UPPER` and concatenation. A computed column is only allowed
to persist if SQL Server can prove the value cannot change on its own; it accepted this one.

**2. It is INDEXABLE.** `CREATE INDEX … ON (SortKey)` succeeded on the persisted column. That answers
the real question directly: the all-provisions grid can sort by index rather than sorting rows at
query time, so the concern about the cross-template view disappears and no sort option has to be
turned off anywhere.

**3. It reaches the entity and the grid for free.** The CodeGen-generated base view is
`SELECT c.*, …` (`vwContractTemplateProvisions`, baseline line 6472), so a new column on the table
appears in the view automatically. **No layered view is needed** — which also means BUILD-STATE §5
gotcha 6 (a layered view needs two migrations with the entity flags set before the first CodeGen, or
CodeGen DROP/CREATEs over the wrapper) **does not apply to this item at all.** That trap is avoided by
not building a wrapper, not by being careful around one.

Verified ordering, on a persisted+indexed column over the boundary cases:

```
0 | 1 | 1.1 | 1.1A | 1.9 | 1.10 | 2.1 | 10.1
```

**And CodeGen already handles computed columns correctly.** `vwSQLColumnsAndEntityFields` marks any
column with a `computed_columns.definition` as `IsVirtual=1, IsComputed=1`;
`EntityFieldInfo.IsSPParameter()` returns false for both, and `generateInsertFieldString` skips
`IsVirtual` — so `spCreate`/`spUpdate` never pass it and inserts cannot fail on it. It surfaces as a
read-only field on the generated entity, which is exactly right: nobody should be able to set a sort
key.

**Why this beats the alternatives, now that it is measured:**

| | maintained `int` (today) | layered view | **persisted computed column** |
|---|---|---|---|
| Can drift | **yes — already has** | no | no |
| Indexable | yes | **no** | **yes** |
| Needs maintenance code | yes | no | no |
| Extra migration complexity | — | two migrations + flags before CodeGen | one `ALTER TABLE` |

**A layered view is NOT indexable here, and that is worth stating plainly** since it was asked: an
indexed (materialised) view in SQL Server requires `WITH SCHEMABINDING` and **cannot reference another
view** — ours would sit on top of the CodeGen-generated inner view, which disqualifies it outright.
Being committed in a migration makes a view *permanent*; it does not make it *materialised*. Those are
different properties, and only the second one gives you an index.

### Depth

The current data has at most two segments (`MAX` dots = 1, max length 5), so the two-segment expression
covers everything that exists. A third segment would sort as though its tail were part of segment two
— wrong, but visible on screen rather than silent. The implementer should either generalise via a
deterministic scalar UDF (still fine at this scale, and still persistable) **or** add a `CHECK` that
refuses a `ProvisionNumber` with more than two segments, and say in the migration which was chosen.

### The work

1. Migration: `ALTER TABLE ContractTemplateProvision ADD ProvisionSortKey AS (<expression>) PERSISTED`,
   then `CREATE INDEX IX_ContractTemplateProvision_SortKey ON … (ContractTemplateID, ProvisionSortKey)`
   — composite, because every real query is scoped to one template.
2. Drop `Sequence` in the same migration.
3. Re-run CodeGen so the entity picks the column up as read-only, and the `Sequence` field row goes.
4. Repoint every reader: `ORDER BY Sequence ASC` in the modifications editor and the provisions page,
   and `directoryOrder` in the metadata seed.
5. A test that pins the ORDER over a fixture including `1`, `1.1`, `1.9`, `1.10`, `1.1A`, `2.1` —
   written from the expected order, not from what the expression returns.

## R-12 · `ContractTemplate.SourceURL` nullable, plus a derived `IsUsable` — ✅ READY

> **Ruled 2026-08-19 (Marcelo).** `SourceURL` becomes nullable. The "URL or file" requirement is
> surfaced as a **derived usability flag the UI can show**, rather than as a save-time refusal —
> because a refusal at the wrong moment is confusing, and this is a state a person should be able to
> SEE and fix rather than discover by being blocked.

**Reachability is not enforceable, by anything.** Whether a URL still resolves is a fact about the
outside world: no `CHECK`, trigger, subclass or remote operation can assert it, and format validation
(`https://…`) is weak because a well-formed dead link passes. Nothing below tries.

### Why a remotable operation is not the answer

Easy to build, and it buys nothing, because the obstacle is **ordering, not verdicts**. A file attaches
through `__mj.FileEntityRecordLink`, keyed on `RecordID` — **it cannot be linked to a record that does
not exist yet.** So on CREATE the file half of "URL or file" is unsatisfiable in principle and no
pre-save check of any kind changes that. On UPDATE the check is one `count_only` read that
`ValidateAsync` already does cheaply. A remote op would restate a rule the save channel already
carries, which D-24 rung 4 warns against.

### The design: derive `IsUsable`, do not refuse

A template with neither a URL nor a linked file is not *invalid* — it is **incomplete**, which is an
ordinary state to pass through while authoring one. The right expression of that is a status the UI
renders, not an error that stops a save. So:

**`IsUsable` (bit) derived in an app-owned layered base view over `ContractTemplate`:**

```
IsUsable = 1 when SourceURL IS NOT NULL AND LEN(LTRIM(SourceURL)) > 0
        OR an __mj.FileEntityRecordLink row exists for this template
```

This is the **exact shape `Contract.IsAwaitingDocument` already uses** — a flag combining a column with
an `EXISTS` over `FileEntityRecordLink`, with the `Entity` id looked up BY NAME rather than hardcoded
so it survives a from-zero rebuild. Precedent, not invention; copy that CASE expression.

**It has to be a view, and this is the contrast with R-11.** R-11's sort key is a pure function of one
column in one row, so it is a computed column and needs no view. `IsUsable` reads **another table**, and
a computed column cannot do that. This is exactly where the layered-view pattern earns its keep — and
therefore **BUILD-STATE §5 gotcha 6 applies to THIS item**: a layered base view needs two migrations,
with the entity flags set before the first CodeGen, or CodeGen DROP/CREATEs the public view name over
the wrapper. Read `V202608182000` and `V202608182001` (the `vwContracts` pair) as the worked example
before writing either file.

**A bit, flavoured in the UI.** The view returns the boolean; the template form and the templates grid
render it — a red "Unusable" chip until a URL or a file exists, with the reason. Keeping the semantics
in one bit and the presentation in the UI means a later third state (say, "URL recorded but unreachable"
once something checks) is a view change and a chip colour, not a schema migration.

### What about the contract that cites an unusable template?

Left as a **question, not built**. `IsUsable` makes the state visible, which was the actual ask; whether
a contract should additionally be REFUSED for referencing an unusable template is a separate product
call, and it is now cheap to add because the flag exists — `ContractEntityServer.ValidateAsync()` would
read one bit. Recommend shipping the flag first and seeing whether anyone ever cites an unusable
template; a block nobody needs is a block that will eventually be in someone's way.

### The work

1. Migration: `ALTER COLUMN SourceURL … NULL`, then re-run CodeGen — the current NOT NULL is what makes
   the generated form mark it required.
2. The layered view pair adding `IsUsable`, following `vwContracts` and gotcha 6.
3. UI: the chip on the template form and the templates grid.
4. `plans/QUESTIONS.md` Q-6 records the ruling; update it to match this design.

**Open (not blocking):** should a contract be refused for referencing an unusable template, or is the
visible flag enough?

## R-13 · The message plumbing that made all of the above invisible — FIXED UPSTREAM

Worth recording here because it changes what every other item in this document is worth.

A subclass's `ValidateAsync()` refusal reached the user as
`{"Source":"ParentContractID","Message":"…","Value":null,"Type":"Failure"}` in a toast.
`BaseEntityResult.CompleteMessage` — the string `ResolverBase` puts in the `GraphQLError` and
`SaveEntityGraphOperation` puts in `ErrorMessage` — rendered each error as
`err.message || JSON.stringify(err)`, **lowercase**, while MJ's `ValidationErrorInfo` carries
`Message`. `Errors` is typed `any[]`, so nothing could catch it.

Both of this app's server-side rules were affected. **Fixed** in
`random-projects/mj-completemessage-fix/` (branch `fix/completemessage-drops-validation-prose`,
commit `9b79794fd0`, off `origin/next`) and applied live in `instances/contracts-mj6/mj`: MJCore
2074/2074, `tsc` exit 0, regression test red-proven. Logged in `MJ-UPSTREAM.md`.

**Handed off 2026-08-19 (Marcelo):** another agent owns the verification and the PR from here.
Nothing in this repo depends on it landing — the fix is already live in this instance's MJ worktree,
so the messages are legible here today; the PR is what makes that true for everyone else. Changesets
on that PR are **patch-level only** for now (Marcelo, 2026-08-19).

**Consequence for this plan:** rung-3 rules are now worth writing. Before this, every server-only rule
we added would have shipped its explanation as JSON.

---

---

## R-14 · Locking a contract after execution — 🗣 DISCUSSION, do not implement yet

Raised in review: *"shouldn't it be locked after it is active? only a change order should be able to
change it after it is executed?"* Split out of R-5 at Marcelo's request (2026-08-20) because it is a
bigger design conversation than the rest of this plan, and because R-4's tree rules and R-3's ancestor
walk both feed it.

**Why it is not just another validation.** Everything else here is a rule about one row or one FK.
This is a policy about what a contract IS after paper exists — and the answer determines whether the
change-order mechanism is load-bearing or decorative.

**The lock key should be `ExecutedDate IS NOT NULL`, not the derived `State`.** `State` is computed in
the view and turns over with the calendar, so a lock keyed on it would freeze and unfreeze rows
without anyone touching them, and a trigger would have to recompute the whole precedence chain
inline. `ExecutedDate` is a single stored field: visible to a trigger, testable in-memory by the
shared class, and it means the thing we actually care about — someone signed something.

**Proposed frozen set once executed** — the terms a counterparty agreed to:
`ContractTypeID`, `CompanyID`, `CustomerOrganizationID`, `ContractTemplateID`, `EffectiveDate`,
`EndDate`, `ExecutedDate`.

**Proposed still-editable** — facts recorded later, and transcription that may be corrected:
`TerminatedDate` (termination is a later event, and §7.1 explicitly refuses to tie it to the term),
`ParentContractID` / `SupersededByContractID` (lineage is recorded after the fact),
`Description`, `Notes`, `PrimaryContactPersonID`, `SigningProviderURL`, `HasModifications`.

**The open question inside the open question:** the renewal-terms fields (`AutoRenew`,
`RenewalNoticeDays`, `CancellationWindowDays`, `AnnualIncreasePercent`). They are *transcription of
what the paper says* — which argues correctable — but they are also *terms*, and they drive the
watchlist finance acts on. Freezing them means a typo needs a change order; leaving them open means
the watchlist can be edited after signature. This needs a ruling, not an inference.

**Why the lock is acceptable at all:** you do not edit an executed contract, you write a Change Order
whose `ParentContractID` names it — which R-4's `ParentStatusRequirement` enforces. The lock and the
change-order requirement are two halves of one design, so shipping the lock without R-4 settled would
leave users with no legal way to record a change.

**Tier, once decided:** shared `Validate()` for the field-level "you cannot change this" message
(in-memory `OldValue` check, no DB read — same shape as `GLAccountEntityServer`), plus a DB trigger if
we decide the floor matters. Accounting has both for JE immutability; whether contracts need the floor
depends on whether anything other than our own UI will ever write these rows.

## Suggested order

Marked from the 2026-08-20 review. An agent may pick up anything marked ✅ READY without further
input; ⏸ and 🗣 items need the named answer first.

1. **R-6** ✅ — backfill, then NOT NULL, then CodeGen. Smallest closed loop.
2. **R-5** ✅ — Inactive-type modification check. Code only, no schema.
3. **R-8** ✅ — delete messages. Creates three server subclasses the later items also need.
4. **R-1** ✅ — provision immutability. Trigger + code, and read the value-comparison warning first;
   a trigger without it breaks `mj sync push`.
5. **R-7** ✅ — the sequence swap, plus filing the accounting/orders issues.
6. **R-3** ✅ — cycle prevention; the ancestor walk it builds is reused by R-4 and R-14.
7. **R-4** ✅ — the two-boolean rework, the type retirements, and the tree-scoped modification rule.
   Reworks shipped code (`ParentStatusRequirement`), so it wants a clear run rather than being
   squeezed between other items. Its deferred half rides with R-14.
8. **R-10** ✅ — uniqueness: the picker preflight plus the staged-rows rule.
9. **R-11** ✅ — a PERSISTED computed column plus its index, then drop `Sequence`. One `ALTER TABLE`
   and a CodeGen run; no layered view, so gotcha 6 does not apply here.
10. **R-12** ✅ — `SourceURL` nullable, plus a derived `IsUsable` in a layered view. This one DOES
    need two migrations with the entity flags set before the first CodeGen (gotcha 6) — read the
    `vwContracts` pair first.
11. **R-14** 🗣 — the post-execution lock. Needs the frozen-set ruling, especially renewal terms.

R-2 is **withdrawn** (premise false — the correction was re-checked at Marcelo's request on
2026-08-20 and holds, with one narrow empty-string divergence noted). R-9 is **implemented**; R-13 is
**fixed and handed to another agent** for verification and PR. R-9–R-13 were authored by the main
agent; R-1–R-8 and R-14 by the second agent. Every ✅ above is now a Marcelo ruling rather than an
agent's judgement, so **a third agent may pick up any of them without further input** — read the item
in full first, several carry a warning that costs a rebuild if skipped.

## Open questions for review

- ~~**R-11:** dropping `ContractTemplateProvision.Sequence` reverses ERD R-14~~ — **ANSWERED
  2026-08-19 (Marcelo): drop it.** Logged as ERD R-20.
- **R-12 (not blocking):** ship the visible `IsUsable` flag only, or ALSO refuse a contract that
  references an unusable template? Recommendation: flag first.
- **R-11 (not blocking):** generalise the sort key to arbitrary segment depth via a scalar UDF, or add
  a `CHECK` refusing a third segment? Current data has at most two.
- **R-14:** the frozen field set, and specifically whether renewal-terms fields are transcription
  (correctable) or terms (frozen).
- **R-3:** build `RootParentContractID` / `RootSupersededByContractID`, or delete the metadata rows
  that describe fields nothing returns?
- **R-7:** who files the accounting + orders sequence issues, and against which repos?
