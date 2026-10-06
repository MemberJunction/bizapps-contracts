---
"@mj-biz-apps/contracts-actions": patch
"@mj-biz-apps/contracts-ng": patch
"@mj-biz-apps/contracts-core-entities-server": patch
"@mj-biz-apps/contracts-entities": patch
"@mj-biz-apps/contracts-server": patch
---

Builds against MemberJunction 6.1.5, the 6.1 LTS line AIDP Next runs, and regenerates from a database built from migrations. Contract Type gets back its four renewal defaults (`DefaultAutoRenew`, `DefaultRenewalNoticeDays`, `DefaultCancellationWindowDays`, `DefaultAnnualIncreasePercent`) in the entity class, GraphQL types and form, and `PrimaryContactPerson` widens to 201 characters to match the view.
