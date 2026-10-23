---
'@mj-biz-apps/contracts-entities': minor
---

Release seed for 0.9: `V202610230230__v0.9.x__Metadata_Sync.sql` and its PostgreSQL counterpart carry `EntityIDFieldName = 'CreatingEntityID'` on Contracts.CreatingRecordID (the polymorphic foreign key) to hosts, which install by migration and never read `metadata/`.
