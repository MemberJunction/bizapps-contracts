---
"@mj-biz-apps/contracts-entities": minor
---

Adds the PostgreSQL counterpart of the single-write `__mj_UpdatedAt` migration (V202611201235). It changes nothing on PostgreSQL, where the `__mj_UpdatedAt` trigger already stamps the row in place before the update, so a save is already one write.
