/**
 * "Today" as every worklist, tile and badge in this package reads it — and the five call sites that
 * were still reading the SERVER'S UTC day after `V202609211200` moved `vwContracts` onto the business
 * one (bc-aidp-next-golive#168).
 *
 * THERE IS NO PINNED ZONE HERE, AND THAT IS THE RESULT RATHER THAN A GAP. The sibling suite
 * `form-panels/__tests__/contract-dates-panel.test.ts` pins `America/Chicago` and asserts across
 * instants where the UTC day, the browser day and the business day disagree, because it tests code
 * that reads a zone. These predicates deliberately read none: four of the five now filter on the
 * view's own `DaysUntilNoticeDeadline`, which the same row derives from the same `bt.Today` as the
 * `DaysToEnd` and `State` printed beside it, and the fifth resolves the day in SQL from the function
 * the view joins. A predicate with no clock in it has no instant at which it can be one day out —
 * which is a stronger property than agreeing with a chosen zone at a chosen instant, and the reason
 * a client-side business day was not the fix.
 *
 * What still has to be proved, then, is the two things that could silently come untrue: that no call
 * site has gone back to a clock, and that the column they filter on still MEANS "days from the
 * business day to the deadline". The second is asserted against the migration in
 * `packages/Entities/src/__tests__/contract-state.test.ts`, which resolves the newest definer of the
 * view; duplicating that resolution here is the staleness trap that file documents three times.
 */
import { describe, expect, it } from 'vitest';
import {
    BUSINESS_TODAY_SQL,
    NOTICE_WINDOW_OPEN,
    NOTICE_WINDOW_PASSED,
    NoticeWindowWithin,
} from '../business-day';

/**
 * The column every notice predicate is written against.
 *
 * Named once, in the test as well as in the source, because the whole point is that all of them read
 * the SAME derived column: a predicate that drifts onto `RenewalNoticeDeadline` and a date is back to
 * comparing the deadline against whatever day the comparand happens to name.
 */
const DAY_COUNT = 'DaysUntilNoticeDeadline';

describe('the notice-window predicates', () => {
    it('are written against the view’s own day-count, not against a date at all', () => {
        expect(NOTICE_WINDOW_OPEN).toBe(`${DAY_COUNT} >= 0`);
        expect(NOTICE_WINDOW_PASSED).toBe(`${DAY_COUNT} < 0`);
        expect(NoticeWindowWithin(60)).toBe(`${DAY_COUNT} BETWEEN 0 AND 60`);
        expect(NoticeWindowWithin(120)).toBe(`${DAY_COUNT} BETWEEN 0 AND 120`);
    });

    it('name no clock, no date literal and no zone', () => {
        // The three ways this went wrong before and the one way the obvious repair goes wrong: the
        // server's UTC day, the row's own date column compared to a comparand, and a day pasted in
        // from the browser.
        for (const filter of [NOTICE_WINDOW_OPEN, NOTICE_WINDOW_PASSED, NoticeWindowWithin(120)]) {
            expect(filter).not.toMatch(/GETUTCDATE|GETDATE|SYSDATETIME|AT TIME ZONE/i);
            expect(filter).not.toMatch(/\d{4}-\d{2}-\d{2}/);
            expect(filter).not.toContain('RenewalNoticeDeadline');
        }
    });

    it('open and passed partition the rows they used to, NULLs excluded from both', () => {
        // `DaysUntilNoticeDeadline` is NULL under exactly the conditions `RenewalNoticeDeadline` is,
        // and `>= 0` / `< 0` each drop a NULL — which is the `IS NOT NULL` these predicates used to
        // spell out. Complementary bounds on the same column is what makes that true; two predicates
        // on two columns would not be.
        expect(NOTICE_WINDOW_OPEN).toContain('>= 0');
        expect(NOTICE_WINDOW_PASSED).toContain('< 0');
        expect(NOTICE_WINDOW_OPEN.replace(' >= 0', '')).toBe(NOTICE_WINDOW_PASSED.replace(' < 0', ''));
    });

    it('refuses a window that is not a whole number of days', () => {
        // The value is interpolated into SQL text, so a non-integer is both a broken filter and the
        // only shape of injection an ExtraFilter is exposed to here.
        expect(() => NoticeWindowWithin(1.5)).toThrow(RangeError);
        expect(() => NoticeWindowWithin(-1)).toThrow(RangeError);
        expect(() => NoticeWindowWithin(Number.NaN)).toThrow(RangeError);
        expect(() => NoticeWindowWithin(Number.POSITIVE_INFINITY)).toThrow(RangeError);
    });
});

describe('BUSINESS_TODAY_SQL', () => {
    it('resolves the day from the same function the view joins', () => {
        expect(BUSINESS_TODAY_SQL).toContain('[__mj_BizAppsCommon].[fnBusinessToday]()');
        expect(BUSINESS_TODAY_SQL).toContain('[Today]');
        expect(BUSINESS_TODAY_SQL).not.toMatch(/GETUTCDATE|GETDATE/i);
    });

    it('is a scalar subquery, so it can stand where a date did', () => {
        expect(BUSINESS_TODAY_SQL.startsWith('(')).toBe(true);
        expect(BUSINESS_TODAY_SQL.endsWith(')')).toBe(true);
    });

    it('trips none of the ExtraFilter keyword denylist', () => {
        // MJ screens ExtraFilter with a denylist covering `insert / update / delete / exec / drop /
        // -- / union / xp_ / ; / waitfor` (DatabaseProviderBase.ValidateUserProvidedSQLClause). A
        // predicate that trips it surfaces as an unreadable grid, not as a message about the filter.
        expect(BUSINESS_TODAY_SQL).not.toMatch(
            /--|;|\bunion\b|\bexec\b|\bdrop\b|\bwaitfor\b|\binsert\b|\bupdate\b|\bdelete\b|xp_/i,
        );
    });
});

/**
 * THE CALL SITES, CHECKED AS SOURCE.
 *
 * Every one is either a `protected` getter on an `@Component` or an `async` method needing provider
 * metadata, so none can be invoked here — the same constraint `contract-dates-panel.test.ts` works
 * around. What can be proved without Angular is that the UTC clock is gone from all five and that
 * each reads the business day the view reads, which is exactly the defect: the view moved and these
 * did not.
 */
describe('every consumer of "today" in this package', () => {
    const FILES = [
        ['the Renewals page pills', '../../pages/contract-grid.page.ts'],
        ['the dashboard notice tile', '../../pages/contracts-dashboard.page.ts'],
        ['the left-nav renewals badge', '../../sections/contracts-sections.component.ts'],
        ['the overdue-task fragment', '../task-filters.ts'],
        ['the Overview countdown', '../../form-panels/contract-form.panels.ts'],
    ] as const;

    it.each(FILES)('%s no longer reads the server’s UTC day', async (_label, file) => {
        const source = await read(file);
        expect(source).not.toContain('GETUTCDATE');
    });

    it.each(FILES)('%s takes no calendar day from the browser either', async (_label, file) => {
        // The obvious repair, and the one that looks fixed while the engine is unloaded: reading the
        // day on the client and pasting it into SQL. Nothing in this package calls
        // `BusinessTimeZoneEngine.Instance.Config()`, so such a read falls open to UTC — the bug,
        // reintroduced silently. `DateAsText` and friends read a STORED day and never "today", which
        // is why `@mj-biz-apps/common-entities` is still imported elsewhere.
        const source = await read(file);
        expect(source).not.toContain('BusinessTimeZoneEngine');
        expect(source).not.toContain('TodayIn(');
    });

    it('states the notice window once, so the pill, the tile and the badge cannot drift apart', async () => {
        const pills = await read('../../pages/contract-grid.page.ts');
        const tile = await read('../../pages/contracts-dashboard.page.ts');
        const badge = await read('../../sections/contracts-sections.component.ts');
        expect(pills).toContain('Filter: NOTICE_WINDOW_OPEN,');
        expect(pills).toContain('Filter: NOTICE_WINDOW_PASSED,');
        expect(tile).toContain('NoticeWindowWithin(60)');
        expect(tile).toContain('NOTICE_WINDOW_PASSED');
        expect(badge).toContain('NoticeWindowWithin(120)');
        // And none of them may hand-write a comparison on the deadline instead. Only a COMPARISON:
        // the Renewals page legitimately SORTS on `RenewalNoticeDeadline`, nulls last, and always has.
        for (const source of [pills, tile, badge]) {
            expect(source).not.toMatch(/RenewalNoticeDeadline\s*(?:[<>]=?|BETWEEN)/i);
        }
    });

    it('resolves the overdue-task day in SQL, from the function the view joins', async () => {
        const tasks = await read('../task-filters.ts');
        expect(tasks).toContain('t.DueAt < ${BUSINESS_TODAY_SQL}');
    });

    it('takes the Overview countdown from the view rather than deriving a second one', async () => {
        // `DaysToEnd` was always read off the record; `DaysUntilNoticeDeadline` was recomputed from
        // the deadline and a UTC "today", so one card printed two different days. Four getters —
        // NoticeClock, NoticeTone, Health, NextMove — went through the local copy.
        const overview = await read('../../form-panels/contract-form.panels.ts');
        expect(overview).toContain('record?.DaysUntilNoticeDeadline ?? null');
        expect(overview.match(/noticeDays\(this\.Record\)/g) ?? []).toHaveLength(4);
        // The local re-derivation, by either of its shapes.
        expect(overview).not.toContain('daysUntil(');
        expect(overview).not.toMatch(/Date\.UTC\(/);
    });
});

/**
 * A source file with its COMMENTS REMOVED.
 *
 * This is finding 5 of the same review, one package over, and it would have bitten here for the same
 * reason. Every call site below now carries a comment explaining what it used to compare against —
 * `CAST(GETUTCDATE() AS date)`, `daysUntil(RenewalNoticeDeadline)` — because a fix whose reason is not
 * written down is reverted. Asserted against the raw text, those explanations fail the very absence
 * checks they exist to protect, on correct code, and the repair anybody reaches for is to delete the
 * assertion rather than the prose. `contract-state.test.ts` calls the SQL version of this `sqlCode`.
 *
 * `//` is stripped only where it is not preceded by a colon, so a `https://` inside a template or a
 * string survives; these files contain several.
 */
const code = (t: string) =>
    t
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/<!--[\s\S]*?-->/g, '')
        .replace(/(^|[^:])\/\/.*$/gm, '$1');

/** One file's CODE, read through a URL rather than a path so these tests need no `node:path`. */
async function read(relative: string): Promise<string> {
    const { readFile } = await import('node:fs/promises');
    return code(await readFile(new URL(relative, import.meta.url), 'utf8'));
}
