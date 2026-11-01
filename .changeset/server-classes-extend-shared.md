---
"@mj-biz-apps/contracts-core-entities-server": patch
---

`ContractTypeEntityServer` and `ContractTemplateTypeEntityServer` now extend the shared `ContractTypeEntity` and `ContractTemplateTypeEntity` instead of the generated classes. Before, the server classes replaced the shared ones when registered, so their `Validate()` override, which checks `Status` against its value list, never ran on the server; a wrong status reached the database CHECK constraint instead of a field-level validation error.
