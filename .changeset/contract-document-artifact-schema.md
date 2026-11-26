---
"@mj-biz-apps/contracts-entities": minor
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-actions": patch
"@mj-biz-apps/contracts-server": minor
"@mj-biz-apps/contracts-ng": minor
---

Add nullable `Contract.DocumentArtifactID` (`UNIQUEIDENTIFIER NULL`, `FK -> [__mj].[Artifact]([ID])`) additive 4-part T-SQL migration, deterministic `split-bake v1` PostgreSQL counterpart, regenerated entity/GraphQL/form classes, lowercase PostgreSQL schema-casing fixes in server/action PlatformSQL, multi-domain MJ Docs seed script, and dual-DBMS integration checks.
