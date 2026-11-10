---
'@mj-biz-apps/contracts-ng': patch
---

Fix the dashboard's "Overdue tasks" tile and the All Contracts overdue-task pill on MJ 6.2.

MJ 6.2's GraphQL boundary refuses a client `ExtraFilter` whose FROM names anything but an entity
base view. The overdue-task filter read the business day with a subquery on bizapps-common's
`fnBusinessToday()` inside its `EXISTS`, so both surfaces raised an error.

- `BUSINESS_TODAY_SQL` is now `[__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET())`, a scalar
  call the screen accepts. It resolves the zone through the same `fnBusinessToday()` `vwContracts`
  uses and runs when the query runs.
- `mj-app.json` raises its bizapps-common floor to 5.51.0, the release that added `fnBusinessDayOf`.
