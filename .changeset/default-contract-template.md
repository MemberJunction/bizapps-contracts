---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-ng': minor
---

Default a new contract's template to the current published version (golive #218).

Story C-US1 says `ContractTemplateID` starts on the current template and the user corrects it
if the executed document cites an older version. Nothing defaulted it, so every new Order Form,
Statement of Work and Payment Link opened with the field empty — and all three carry
`TemplateRequired = 1`, so the save was refused until the user found the picker themselves.

The Agreement panel now fills the field when a new contract is opened with a type already set,
and again whenever the type is changed on an unsaved one. The candidate is the newest
`Published` template with `IsUsable = 1`, ordered by `IntroducedDate` — both clauses restate what
`ContractEntityServer.refuseUnusableTemplate()` enforces on save, so the default can never offer
something the server then rejects.

What it will not do: touch a saved contract, replace a template the user picked by hand (only the
value this session defaulted may be overwritten), or default onto a Change Order, which carries
`TemplateRequired = 0` and no template of its own. A failed or empty read is silent — the field
stays empty and the picker still works.

Scoping was the issue's one open decision: the newest published usable template wins regardless
of template type. `ContractType` carries no `ContractTemplateTypeID`, so there is nothing in the
data to scope by, and of the two seeded template types only Master Agreement has templates behind
it — Statement of Work is seeded deliberately unused.

The three decisions inside the query (`CurrentTemplateFilter`, `CurrentTemplateOrderBy`,
`ShouldDefaultTemplate`) live in `contracts-entities`, where a unit test reaches them without
standing up Angular's DI — the same split as `supersede-candidates.ts`.
