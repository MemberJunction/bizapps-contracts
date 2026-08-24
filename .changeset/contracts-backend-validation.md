---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

Enforce the eight backend rules the schema promised and nothing checked.

`plans/backend-requirements.md` audited every rule the ERD claims and found that most of them existed
only as prose. **All ten ready items are now done**, each at the cheapest tier that can hold it — CHECK constraint
where the rule reads one row, trigger where a bypass would be silent corruption, entity subclass where
the point is a message a person can act on.

- **R-1** a referenced template's provisions are immutable — trigger plus a subclass that explains it.
  The trigger compares OLD to NEW values, without which an identical `mj sync push` of the 73 seeded
  provisions would start failing the moment any contract referenced the agreement.
- **R-3** lineage cycles are refused on both `ParentContractID` and `SupersededByContractID`, naming
  the ring. A cycle was not merely untidy: `vwContracts` computes root pointers by walking the chain,
  and a ring makes those columns silently NULL on every read.
- **R-4** `ParentStatusRequirement` becomes `MustBeRoot` / `MustBeChild` / `TemplateRequired`, and a
  modification may cite any provision of a template **at or above its contract in the tree**. That
  second half is what makes change orders work at all — a change order carries no template of its own,
  so every modification recorded on one was previously refused.
- **R-5** a retired contract type or template type cannot be *newly* selected, while contracts already
  using one keep saving. Order Form and Payment Link are retired accordingly.
- **R-6** `ModificationText` is required — `NOT NULL` **and** a not-blank CHECK, because `NOT NULL`
  accepts the empty string and MJ's nullability check only tests null.
- **R-7** the `ContractSequence` counter table becomes a SQL `SEQUENCE`. The table existed only because
  CodeGen registers tables as entities, which made the counter API-writable; a sequence is not a table,
  so the entity, the grid and the hole all disappear together.
- **R-8** deletes explain themselves instead of surfacing a foreign-key constraint name, counting what
  blocks them.
- **R-10** one modification per provision × contract combo. `UQ_ContractTemplateModification_Contract_Provision`
  already made this the rule; it now explains itself instead of surfacing a raw unique-index violation.
  Caught in the picker, among staged rows, and against saved rows.

Four migrations, all idempotent and written for a database that already has data.
- **R-11** provision ordering comes from `ProvisionNumber` via a derived, indexed collation key. The
  hand-maintained `Sequence` column it replaces had **already collided** in the seeded data — `1` and
  `1.1` both claiming position 1 — which is the failure mode of a second copy of an order the number
  already states.
- **R-12** `SourceURL` becomes nullable and a derived `IsUsable` says whether the standard terms can
  actually be read. A template with neither a URL nor a file is *incomplete*, not invalid, so it gets a
  chip rather than a refusal; the refusal lives one step downstream, where a contract would incorporate
  terms nobody can read.

Seven migrations, all idempotent and written for a database that already has data.
