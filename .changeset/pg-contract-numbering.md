---
"@mj-biz-apps/contracts-core-entities-server": patch
---

Contract numbering sends PostgreSQL a SELECT of the numbering function instead of the SQL Server T-SQL batch, so new contracts can be saved on a PostgreSQL host once the PostgreSQL baseline ships.

Every PostgreSQL query in this package (contract numbering, the lineage check, the modifications count and the template ancestry check) now names the schema `__mj_bizappscontracts`, the name the PostgreSQL baseline creates. MJ's PostgreSQL provider quotes mixed-case identifiers, so the earlier `__mj_BizAppsContracts` reached PostgreSQL as a schema that does not exist.
