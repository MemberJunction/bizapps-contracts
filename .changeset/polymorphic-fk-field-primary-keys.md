---
"@mj-biz-apps/contracts-entities": minor
---

`metadata/entities/.polymorphic-fk-entity-fields.json` gives every `MJ: Entity Fields` entry a `primaryKey` lookup (`@lookup:MJ: Entity Fields.EntityID=@lookup:MJ: Entities.Name=<entity>&Name=<field>`). The entries had none, and `mj sync push` creates a new row for any record without a `primaryKey`, so on a fresh database push would try to insert a second field row instead of updating the one CodeGen created (MemberJunction/MJ#6006). With the lookup, push updates that row and sets its `EntityIDFieldName`.
