---
"@mj-biz-apps/contracts-core-entities-server": patch
---

The parent/successor cycle check, the template-clearing modification count and the modification template-ancestry check send PostgreSQL its own SQL instead of SQL Server T-SQL, so the saves that run them work on a PostgreSQL host once the PostgreSQL baseline ships.
