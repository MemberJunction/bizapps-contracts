---
'@mj-biz-apps/contracts-ng': minor
'@mj-biz-apps/contracts-entities': minor
---

Contract lifecycle and dates are judged on the business day (bc-aidp-next-golive#168).

`vwContracts` compared every date against the server's UTC calendar day, which is already tomorrow
for the whole American evening: a contract ending 31 December read as Expired at 7 PM Central on the
31st, and `DaysToEnd`, `DaysUntilNoticeDeadline`, `NonRenewalOutcome` and the cancellation window all
moved an evening early. The view now cross joins bizapps-common's `fnBusinessToday()` once and
compares all nine boundaries against `bt.Today`, the calendar day in the instance's business time
zone. The dates panel's `AsInput`/`SetDate` delegate to the shared calendar-day helpers, which also
fixes an offset-bearing stored value rendering as the next day and an unreadable one being written
as an `Invalid Date`. First dependency on `@mj-biz-apps/common-entities`.

The same migration restores issue #28 item 16, which `V202609202354` reverted when it re-created the
view: `IsAwaitingDocument` counts only a file in the 'Executed Agreement' category again, and
`contract-state.test.ts` now resolves the newest definer whichever spelling it uses, so the next
re-creation that drops a decision fails instead of passing silently.

⚠ Requires `[__mj_BizAppsCommon].[fnBusinessToday]()` from bizapps-common; the migration fails with a
readable message if it is not applied first.
