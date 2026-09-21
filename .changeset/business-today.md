---
'@mj-biz-apps/contracts-ng': minor
'@mj-biz-apps/contracts-entities': minor
---

Contract lifecycle and dates are judged on the business day (bc-aidp-next-golive#168).

`vwContracts` compared every date against the server's UTC calendar day, which is already tomorrow
for the whole American evening: a contract ending 31 December read as Expired from 6 PM Central on
the 31st (CST is UTC-6; on CDT the roll is an hour later), and `DaysToEnd`, `DaysUntilNoticeDeadline`,
`NonRenewalOutcome` and the cancellation window all moved an evening early. The view now cross joins
bizapps-common's `fnBusinessToday()` once and compares all nine boundaries against `bt.Today`, the
calendar day in the instance's business time zone. The dates panel's `AsInput`/`SetDate` delegate to
the shared calendar-day helpers, which also fixes an offset-bearing stored value rendering as the
next day and an unreadable one being written as an `Invalid Date`. First dependency on
`@mj-biz-apps/common-entities`.

Every other reader of "today" moves with it, because half a fix is worse than none: before the
migration the view and the UI were both on the UTC day and AGREED, so nothing looked broken. The
"Notice window open"/"passed" pills, the dashboard's notice-deadline tile, the left-nav renewals badge
and the overdue-task fragment took their day from `CAST(GETUTCDATE() AS date)`, and the Overview
panel's `NoticeClock`, `NoticeTone`, `Health` and `NextMove` computed it from the UTC clock — so from
6 PM Central a contract the view still gave notice time on had already dropped out of the pill, and
one card printed `DaysToEnd` from the view next to a countdown a day ahead of it.

They read the VIEW's own answer now, not a second clock. `DaysUntilNoticeDeadline` is
`DATEDIFF(day, bt.Today, RenewalNoticeDeadline)` in the same row as the `DaysToEnd` and `State` beside
it, so the four notice predicates become `>= 0` / `< 0` / `BETWEEN 0 AND n` (`lib/data/business-day.ts`,
stated once for the pill, the tile and the badge) and the Overview reads the column instead of
recomputing it. A predicate with no clock in it has no hour at which it can be a day out, and no
dependence on a browser clock or a cached engine setting. `Tasks.DueAt` is the one column with no
day-count of ours to read, so its comparison resolves `fnBusinessToday()` in SQL — the same function,
the same configuration row, evaluated per query exactly as `GETUTCDATE()` was.

Read-only dates stop rendering a day early too. The four `DATE` columns, the hero's three date stats
and the renewal deadline hint went through Angular's `| date` pipe, which formats in the VIEWER'S
zone — so one screen showed 31 Dec in the date input and 30 Dec in the read-only field beside it.
They render from UTC parts now, like every other calendar-day reader.

The same migration restores issue #28 item 16, which `V202609202354` reverted when it re-created the
view: `IsAwaitingDocument` counts only a file in the 'Executed Agreement' category again, and
`contract-state.test.ts` now resolves the newest definer whichever spelling it uses, so the next
re-creation that drops a decision fails instead of passing silently.

⚠ Requires `[__mj_BizAppsCommon].[fnBusinessToday]()` from bizapps-common; the migration fails with a
readable message if it is not applied first.
