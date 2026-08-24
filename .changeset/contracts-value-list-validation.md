---
'@mj-biz-apps/contracts-entities': patch
---

Value-list fields are now validated — a stopgap for an MJ gap, plus the ERD that describes the schema
we actually have.

**The gap.** Three columns are constrained by `CHECK (… IN (…))`: `ContractType.Status`,
`ContractType.ParentStatusRequirement` and `ContractTemplateType.Status`. CodeGen renders that kind of
constraint as value-list METADATA (`ValueListType='List'` plus `__mj.EntityFieldValue` rows) rather
than as a generated `Validate()` method — which is right, because that metadata is also what the UI
needs to render a dropdown. But `BaseEntity` never reads it: `EntityField.Validate()` checks
nullability, `MaxLength`, date parseability and numeric range and stops. So this is the one class of
schema rule with **no representation in TypeScript at all** — neither the browser nor a server
subclass can preflight it, and an out-of-list value is refused only by SQL Server, as a raw constraint
violation attached to no field.

The dropdown is why this goes unnoticed: it protects the *form* path and nothing else. `mj sync push`,
the GraphQL mutations, an Action, a subclass assigning the field in code and any data load are all
unguarded — precisely the paths where a typo is least likely to meet a human first. It also made
D-24 rung 1 untrue as written (*"generated validation from the schema (CHECKs, nullability, value
lists) … free everywhere"* — true for the first two, false for the third), and because the failure is
silent the belief survived review.

Filed upstream as [MJ#3969](https://github.com/MemberJunction/MJ/issues/3969).

**What this adds.** `ValidateValueLists()` in `packages/Entities/src/value-list-validation.ts`, called
from two new shared subclasses (`ContractTypeEntity`, `ContractTemplateTypeEntity`). It is generic
rather than three named checks — it loops fields whose `ValueListTypeEnum` is `List` — so a value-list
field added later is covered by adding the call, not by writing another check. Three exclusions matter
as much as the rule, and each has a test: `ListOrUserEntry` is skipped (that mode exists to permit
values outside the list), an unseeded value set is skipped (it would otherwise reject every value
including the correct one), and null is left to the nullability check so one mistake yields one error.
The message names the legal values, because a refusal that does not say what would have been accepted
sends the user back to guess.

The file header records how to delete it — one file, two call sites, one test — when MJ#3969 lands.

**`docs/ERD.md` regenerated.** It still described the **v1** schema: seven tables that no longer exist,
`Contract` missing nine real columns and inventing six, `ContractType` missing three and inventing
thirteen, and header counts of 10 tables / 54 CHECK constraints against an actual 7 / 12. It is now
generated from the live schema and passes the repo's own drift check, 33 of 33.

**And that check now runs.** `test-harnesses/erd-schema-diff.ts` was resolving `.env` three directories
up — correct for the pre-6.x nested layout, resolving to the workspace root under the parent-workspace
topology. `dotenv` does not error on a missing path, so `DB_PORT` stayed undefined and it failed with
"Failed to connect to localhost:1433", which reads like Docker being down rather than a path bug. The
`.mjs` harnesses were moved onto the shared `load-env.mjs` resolver when that bit us there; this one
was missed, which is a fair part of why the ERD drift went unnoticed. It is on the shared resolver now
and verified to find its own env with every `DB_*` variable unset.
