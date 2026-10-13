---
"@mj-biz-apps/contracts-actions": minor
"@mj-biz-apps/contracts-ng": minor
"@mj-biz-apps/contracts-core-entities-server": minor
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-server": minor
---

The provision guard trigger refuses an edit or delete of a clause on a published template with its own message (50102, 50101) instead of SQL Server error 3915, "Cannot use the ROLLBACK statement within an INSERT-EXEC statement". Migration only; no schema or metadata change.
