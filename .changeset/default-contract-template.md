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

A default also LEAVES with the type that supplied it: change an Order Form to a Change Order and
the template the form filled in is withdrawn. Nothing downstream would have caught it otherwise —
the server refuses a MISSING template on a type that requires one and says nothing about a present
one on a type that does not, so the contract would have saved claiming to incorporate standard
terms nobody chose.

What it will not do: touch a saved contract, or touch a template the user picked by hand — that one
is neither overwritten nor withdrawn. It never defaults onto a Change Order, which carries
`TemplateRequired = 0` and no template of its own. A contract type that cannot be READ decides
nothing in either direction, which is why the type read is three-way rather than a boolean: folding
a failed query into "does not require one" would quietly withdraw a legitimate default. A failed or
empty template read is silent — the field stays empty and the picker still works.

Scoping was the issue's one open decision: the newest published usable template wins regardless
of template type. `ContractType` carries no `ContractTemplateTypeID`, so there is nothing in the
data to scope by, and of the two seeded template types only Master Agreement has templates behind
it — Statement of Work is seeded deliberately unused.

The four decisions (`CurrentTemplateFilter`, `CurrentTemplateOrderBy`, `ShouldDefaultTemplate`,
`ShouldWithdrawDefaultTemplate`) live in `contracts-entities`, where a unit test reaches them
without standing up Angular's DI — the same split as `supersede-candidates.ts`. Defaulting and
withdrawing read one shared comparison for "is this value ours", so the two directions cannot
drift apart.
