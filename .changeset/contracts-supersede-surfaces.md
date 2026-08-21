---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Re-papering gets two surfaces, the lineage tree gets MJ's hierarchy control, and a contract number is no longer stripped out of its own validation.

**Two surfaces, one each for the two halves.** "What this agreement supersedes" is now a stock
related-entity grid on its own rail section (`Supersedes`) — see every superseded contract, open any of
them, un-supersede one — enabled by flipping `DisplayInForm` + `Configuration.UI.inclusion` on the
`SupersededByContractID` self-relationship in `.form-chrome.json`. That row previously set
`inclusion: 'None'`, reviewed twice, on the argument that a grid meaning "contracts naming me as their
successor" needs explaining. The argument was right about the label and wrong about the need; the label
is now `Supersedes` and the original reasoning is preserved in the row's comments.

A related grid cannot LINK an existing record (its New creates a new one), so the picker keeps exactly
one job: **add**. It moved out of Lineage into a `Re-papering` field panel in Details, because the
related-entity panel variant renders any non-AG-Grid child blank (MJ#3999) — which is what made it
invisible. It is always visible rather than edit-mode-gated, uses `mj-combobox` / `mjButton` /
`mj-alert` instead of hand-rolled controls, and reads as an ordinary form line via MJ's own
`mj-forms-field` markup. `Superseded by` moved to Details alongside it, so both directions of the
relationship read together.

**Changing the pick now un-points the previous one.** The schema deliberately permits many predecessors
to name one successor (consolidation), so setting the new one alone left the old one still pointing here
and the agreement quietly superseded both. A single-select control means one predecessor: release, then
link, with each failure reporting what actually landed.

**Lineage uses `mj-hierarchy-tree`.** `ParentContractID` is an ordinary self-referential hierarchy, so
the panel declares a config instead of querying — and its nodes NAVIGATE, which the hand-rolled table
could not. `@memberjunction/ng-hierarchy-tree` is a peer at the same range as every other MJ peer.

**`dropSavePopulatedFieldErrors` is deleted.** It searched the validation result for
`Source === 'ContractNumber'` and removed it, so a new contract saved despite MJ correctly reporting a
NOT NULL field as null — a real error suppressed on the belief that something later would fix it. In its
place, `refuseReservedContractNumber` refuses a hand-typed `CTR-<digits>`, because that shape is what the
sequence mints and a hand-typed one can collide with a value the sequence has not reached yet — surfacing
months later on somebody else's save. `ContractEntityServer` marks its own minted numbers so the rule
cannot refuse them.

**The `ContractNumber` DEFAULT was added and reverted in the same batch, deliberately kept as two
migrations.** It was valid SQL and would have satisfied MJ's client-side validator, but CodeGen
string-quotes an expression default into the generated create procedure, which then fails to compile and
leaves `spCreate<Entity>` dropped — contracts could not be created at all (MJ#4000). Reverted
forward-only rather than by editing an applied migration. The underlying problem is still open.

Also: the contract-number failure message named a table dropped two migrations ago, and
`@mj-biz-apps/accounting-ng` was declared as a dependency and imported nowhere.
