---
"@mj-biz-apps/contracts-core-entities-server": patch
---

Contract numbering sends PostgreSQL a SELECT of the numbering function instead of the SQL Server T-SQL batch, so new contracts can be saved on a PostgreSQL host once the PostgreSQL baseline ships.
