---
"@mj-biz-apps/contracts-core-entities-server": patch
---

Default a new contract's template on the server, not only in the form (golive #269).

The #218 default lived in the Agreement panel, so a contract created by any other path — Closed Won
in sales, an import, a script — reached validation with no template. Order Form and Payment Link
carry `TemplateRequired = 1`, so every such contract was refused.

`ContractEntityServer.Save()` now fills an empty `ContractTemplateID` on an unsaved contract whose
type requires one, using the panel's rule: the newest `Published` template with `IsUsable = 1`
(`CurrentTemplateFilter` / `CurrentTemplateOrderBy`). A supplied template is never replaced, a saved
contract is never touched, and a type with `TemplateRequired = 0` gets nothing. With no candidate
the field stays empty and the existing `TemplateRequired` refusal applies.
