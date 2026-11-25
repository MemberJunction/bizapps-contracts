---
"@mj-biz-apps/contracts-entities": minor
---

Saving an existing contract works again on SQL Server. The 1.0.0 single-write migration recreated `spUpdateContract` without the `CarryDiscountOnRenewal` parameter, so every update failed with "@CarryDiscountOnRenewal is not a parameter for procedure spUpdateContract". A new migration recreates the procedure with the parameter and the single-write `__mj_UpdatedAt` stamp. PostgreSQL was not affected.
