---
'@mj-biz-apps/contracts-entities': patch
---

Hide the schema-named application from new users, as accounting and orders already do.

The baseline created `__mj_BizAppsContracts` — the CodeGen bucket app that carries the entity
links, role grants and `SchemaAutoAddNewEntities` — **without** naming `DefaultForNewUser` in the
column list. That column defaults to **1** in the database, so every new user got the raw
`__mj_BizAppsContracts` entry in their app switcher alongside the real `Contracts` app: a container
for admin access, with no nav items and no icon, presented as a destination.

MJ's CodeGen calls this out in `manage-metadata.ts` in as many words — *"Schema-named bucket apps
are plumbing, not products — hide them from new users. Application.DefaultForNewUser defaults to 1
in the DB, so omitting the column here is what put raw `__mj_*`-named apps in every new user's app
switcher."* Contracts' baseline was captured before that fix; accounting and orders were captured
after it and both emit `..., AutoUpdatePath, DefaultForNewUser) VALUES (..., 1, 0)`. Contracts now
emits the same.

Edited in the baseline in place rather than added as a fix-up migration, per this repo's standing
pre-production practice (`migrations/_README.md`): while nothing is deployed, the baseline is
amended and the database rebuilt from zero. Switch to additive-only at first publish.

The user-facing `Contracts` application is unaffected — its metadata record already sets
`DefaultForNewUser: true`, matching `Accounting` and `Orders`.
