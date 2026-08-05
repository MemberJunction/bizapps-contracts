---
'@mj-biz-apps/contracts-entities': patch
'@mj-biz-apps/contracts-actions': patch
'@mj-biz-apps/contracts-server': patch
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

First working vertical slice of BizApps Contracts: schema, generated entities, GraphQL
resolvers and an Explorer UI that creates a contract, lists it and opens it for editing.

**Schema** — the baseline gains `Contract.SupersededByContractID` and `PricedAt`,
`ContractTerm.ExecutedDate` / `MaxEscalationPercent` / `RenewalNoticeDays`,
`ContractLine.SubscriptionTypeID`, `PendingSignature` on both status lists, and
`ContractType` defaults for the cap and notice. Documents move to MJ's polymorphic
`__mj.FileEntityRecordLink` rather than `DocumentFileID` columns. The
`ExecutedDate >= EffectiveDate` CHECK is removed — agreements are routinely signed before
they take effect.

**Wiring** — the generated Angular forms are exported from `contracts-ng` and the
generated GraphQL resolvers from `contracts-server`; without either, Explorer fails to
build or every write dies with `Unknown type "Create…Input"`.

**UI** — an Explorer section with a nav rail and page header: roster, workspace
(edit + section tabs), contract entry on the shared workspace card, and a billing worklist.

`patch` deliberately, despite the schema edits: nothing here has been published, the
baseline is still edited in place per the repo's pre-production practice, and version
numbers should not start climbing before there is anything to be compatible with.
