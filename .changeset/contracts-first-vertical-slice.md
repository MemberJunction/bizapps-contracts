---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-actions': minor
'@mj-biz-apps/contracts-server': minor
'@mj-biz-apps/contracts-core-entities-server': minor
'@mj-biz-apps/contracts-ng': minor
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

Pre-1.0 and unpublished, so `minor` rather than `major` despite the schema edits: the
baseline is still being edited in place per the repo's pre-production practice.
