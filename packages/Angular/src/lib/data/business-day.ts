/**
 * @fileoverview The notice-window predicates, and "today" for the one column the view cannot answer.
 *
 * ## What was wrong
 *
 * `V202609211200` moved every date comparison in `vwContracts` onto the BUSINESS day — `bt.Today`,
 * from bizapps-common's `fnBusinessToday()` (bc-aidp-next-golive#168). Every OTHER consumer of
 * "today" in this package stayed on `CAST(GETUTCDATE() AS date)`, the SERVER'S UTC calendar day,
 * which is already tomorrow for the whole American evening.
 *
 * Before that migration both sides were wrong and AGREED, so nothing looked broken. Afterwards they
 * disagree for exactly the window #168 is about: at 6 PM Central `vwContracts` still reports notice
 * time left on a contract that the "Notice window open" pill, the dashboard tile and the left-nav
 * badge have already dropped, because their `>=` compares the deadline against tomorrow. A row
 * visible in one place and absent from another reads as a stale page rather than as a defect.
 *
 * (6 PM is the CST roll — Central is UTC-6 in winter, UTC-5 on CDT, so the window opens at 7 PM for
 * the daylight half of the year. Every "from 6 PM Central" in this package and in `V202609211200`
 * means the same thing: the whole American evening, whichever hour it starts.)
 *
 * ## Why these predicates carry no date at all
 *
 * The obvious repair — read the business day on the client and paste it in — makes the two sides
 * agree only as long as two clocks and one cached engine setting agree. The view already publishes
 * its own answer: `DaysUntilNoticeDeadline` is `DATEDIFF(day, bt.Today, RenewalNoticeDeadline)`,
 * computed in the same row, from the same `bt.Today`, as the `DaysToEnd` and `State` the screen
 * prints beside it. Filtering on that column cannot disagree with the view, at any hour, on any
 * clock, whatever zone the instance books in — and the day is re-derived on every query, exactly as
 * `GETUTCDATE()` was, rather than frozen when a component initialised.
 *
 * It is also already the house pattern in this very file's callers: the Renewals page's first pill
 * has always read `DaysToEnd IS NOT NULL AND DaysToEnd BETWEEN 0 AND 120`. The notice pills were the
 * outliers, and the deadline's own day-count column did not exist until V202609202354 added it.
 *
 * `DaysUntilNoticeDeadline` is NULL under exactly the conditions `RenewalNoticeDeadline` is (no end
 * date, or no notice period recorded), and every comparison below drops a NULL — so the explicit
 * `IS NOT NULL` these predicates used to carry is preserved, not lost.
 *
 * @module @mj-biz-apps/contracts-ng
 */

/**
 * We can still give renewal notice in time — the deadline is today or later.
 *
 * ONE definition for the "Notice window open" pill and the nav badge's lower bound, for the reason
 * `task-filters.ts` states at length about open tasks: a badge or tile that counts rows the page then
 * fails to show reads as a stale screen, not as a bug.
 */
export const NOTICE_WINDOW_OPEN = 'DaysUntilNoticeDeadline >= 0';

/** The deadline to give notice has gone by — surfaced rather than hidden. */
export const NOTICE_WINDOW_PASSED = 'DaysUntilNoticeDeadline < 0';

/**
 * The notice deadline falls within the next `days` days, today included.
 *
 * `BETWEEN 0 AND n` rather than a pair of dates: both ends are then offsets from the one `bt.Today`
 * the row was computed with, so the window cannot straddle two different notions of today.
 */
export function NoticeWindowWithin(days: number): string {
    if (!Number.isInteger(days) || days < 0) {
        throw new RangeError(`NoticeWindowWithin expects a whole number of days >= 0, got ${String(days)}`);
    }
    return `DaysUntilNoticeDeadline BETWEEN 0 AND ${days}`;
}

/**
 * Today on the BUSINESS calendar, as a scalar expression for an `ExtraFilter`.
 *
 * FOR A COLUMN NO VIEW OF OURS DERIVES A DAY-COUNT FOR — in practice `Tasks.DueAt`, which lives in
 * another app's view and is reached through a correlated `EXISTS` (see `task-filters.ts`). Prefer a
 * derived day-count column wherever one exists; this is the fallback, not the default.
 *
 * IN SQL RATHER THAN ON THE CLIENT, deliberately, and it is the same choice as above for the same
 * reason. `BusinessTimeZoneEngine.Instance.Today()` would read the day in the browser — from a cached
 * engine that falls open to UTC until something calls `Config()`, which is the precise failure this
 * is fixing, silently reintroduced; and the value would be fixed at the moment the filter string was
 * built rather than at the moment the query runs.
 *
 * A SCALAR CALL, NOT A SUBQUERY. bizapps-common's `fnBusinessDayOf(@At)` returns the business day an
 * instant falls on, resolving the zone through `fnBusinessToday()` — the function `vwContracts`
 * cross joins — so the two cannot disagree. Passed `SYSDATETIMEOFFSET()`, it is today, evaluated when
 * the query runs. This used to be `(SELECT b.[Today] FROM fnBusinessToday() b)`, which MJ 6.2's
 * GraphQL boundary refuses: its screen (`ClientClauseScreen`) parses every client filter and accepts
 * a FROM item only when it names an entity base view. It does not screen scalar calls, except the
 * dialect's forbidden list (`OPENROWSET` and the like).
 *
 * `[__mj_BizAppsCommon]` is named literally because the schema is fixed by bizapps-common's own
 * migration, and it is already a hard requirement of this app: `V202609211200` refuses to apply
 * without `fnBusinessToday()`, with a message saying so. `fnBusinessDayOf` arrived in bizapps-common
 * 5.51 (`V202610062305`), which is `mj-app.json`'s floor for that dependency.
 */
export const BUSINESS_TODAY_SQL = '[__mj_BizAppsCommon].[fnBusinessDayOf](SYSDATETIMEOFFSET())';
