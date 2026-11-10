/**
 * @fileoverview The notice-window predicates, filtered on the day-counts `vwContracts` derives.
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
 * The same holds where no day-count exists. The overdue-task filter (`task-filters.ts`) compares
 * `Task.DueAt`, a date in another app's view, with the contract row's `BusinessToday` — the view's
 * `bt.Today` published as a column — rather than reading the day on the client. It also cannot call
 * `fnBusinessToday()` itself: MJ 6.2's GraphQL boundary refuses a client filter whose FROM names
 * anything but an entity base view.
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
