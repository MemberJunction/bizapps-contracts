---
"@mj-biz-apps/contracts-entities": patch
---

`metadata/entities/.polymorphic-fk-entity-fields.json` gives its `MJ: Entity Fields` entry a `primaryKey` lookup (`@lookup:MJ: Entity Fields.EntityID=@lookup:MJ: Entities.Name=MJ_BizApps_Contracts: Contracts&Name=CreatingRecordID`). Without one, `mj sync push` creates a new row, so on a fresh database it tried to insert a second `CreatingRecordID` field and the app's whole metadata push rolled back. Same fix as bizapps-common #366 and bizapps-orders #946.
