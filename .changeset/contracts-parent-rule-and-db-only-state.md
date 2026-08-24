---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Contract types decide whether a parent is allowed, lifecycle state is derived in one place, and Details leads the rail.

**`ContractType.ParentStatusRequirement` replaces a string comparison.** "A change order must name the contract it changes" was enforced by comparing the type row's *name* to `'Change Order'`. A display name is not a rule — renaming that lookup row silently stopped the check from ever firing. The type now carries the constraint: `'Required'`, `'Prohibited'`, or NULL for no restriction, modelled as `NVARCHAR` + `CHECK` so CodeGen's `ParseCheckConstraints` renders it as a dropdown and the grid picks it up from `DefaultInView` with no app code. Both directions are enforced; the value is seeded through metadata sync rather than a migration, so it has one owner.

**The derived `IsChangeOrder` column is gone.** It restated `ParentContractID IS NOT NULL` under a name implying a type distinction it never read: a Change Order whose parent was not yet set reported `0`, and an Order Form beneath a master agreement reported `1`.

**Lifecycle state is derived in the view and nowhere else.** The rule was rendered twice — a T-SQL `CASE` and a TypeScript function generated from one module — on the theory that a single source could not drift. It drifted anyway, on the termination boundary, and the guard missed it because it compared the two renderings as *text*. TypeScript no longer derives state; it reads `contract.State`, and the module keeps only the value list the client needs for chips and typing. The tradeoff is stated rather than hidden: the rule's semantics can no longer be tested without a database, so `state-derivation.mjs` covers all six states plus the three-way termination boundary against the deployed view, and the DB-free test checks the migration against a hand-written statement of the rule that lives in the test.

A contract being edited now shows its last-saved state instead of a live projection of unsaved dates — deliberate, since a chip reacting to an unsaved date asserts something no query would agree with.

**Every read goes through `RunView`**, including the modification `EXISTS` check (`count_only`) and a cross-template check that had been a four-table join. Where a provider is still needed it is MJ's own `BaseEntity.RunViewProviderToUse`. The one thing that cannot be a view — the atomic number counter — moved into `spAssignNextContractNumber`, following accounting's pattern, which leaves no dialect-specific SQL in the application at all.

**Details is first in the form rail.** The rail is assembled as fixed bands — leads, then Details, then related, then More — and a panel joins the lead band purely by declaring `inclusion: 'Primary'`, which is why Details sat fourth. Reordering the groups from a form policy cannot fix it: the band order is re-imposed after any policy runs, silently. Dropping `Primary` puts the panels in the related band, ordered by sort key: Details, Dates, Renewal terms, Documents, Modifications, Lineage.
