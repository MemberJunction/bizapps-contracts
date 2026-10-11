# schema-info

The baseline migration registers this app's schema: section 2 of
`migrations/B202608040001__v0.1.x__Baseline.sql` inserts the `__mj.SchemaInfo` row for
`__mj_BizAppsContracts`, with the entity-name prefix `MJ_BizApps_Contracts: `. `mj.config.cjs`
`newEntityDefaults.NameRulesBySchema` gives CodeGen the same prefix.

This folder therefore holds no record file, and a push writes nothing for it. It stays because
`metadata/.mj-sync.json` lists it in `directoryOrder`.
