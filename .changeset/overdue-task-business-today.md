---
'@mj-biz-apps/contracts-entities': minor
'@mj-biz-apps/contracts-server': minor
'@mj-biz-apps/contracts-ng': minor
---

Fix the dashboard's "Overdue tasks" tile and the All Contracts overdue-task pill on MJ 6.2.

MJ 6.2's GraphQL boundary refuses a client `ExtraFilter` whose FROM names anything but an entity
base view. The overdue-task filter read the business day from bizapps-common's `fnBusinessToday()`
inside its `EXISTS`, so both surfaces raised an error.

- `V202611101800` re-creates `vwContracts` with one new column, `BusinessToday`: the `bt.Today` the
  view already cross joins and compares every other date against. Its CodeGen capture registers the
  field and regenerates Contract's base view and procedures.
- `HasOverdueTask` compares `Task.DueAt` with the outer contract row's `BusinessToday`.
  `BUSINESS_TODAY_SQL` is removed; nothing else used it.
- The generated Contract entity, GraphQL types and form gain `BusinessToday`. The same CodeGen run
  also brings the committed code up to MJ 6.2.1's templates and to `NonRenewalOutcome` being a
  stored column.
