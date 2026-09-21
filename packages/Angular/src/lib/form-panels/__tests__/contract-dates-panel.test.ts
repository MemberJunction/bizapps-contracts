/**
 * The dates panel's two helpers are the whole boundary between `<input type="date">` and the four
 * DATE columns on Contract. `AsInput` re-parsed its argument and called `toISOString()` on the
 * result, which re-bases an offset-bearing stored string onto the following day; `SetDate`
 * hand-rolled the UTC-midnight literal and produced an `Invalid Date` for anything it could not
 * parse. Both now go through bizapps-common's calendar-day helpers, which are the one implementation
 * of the doctrine: a DATE is READ from UTC parts and WRITTEN as UTC midnight.
 *
 * The zone is pinned to America/Chicago — WEST of Greenwich, deliberately. The defect class these
 * tests exist for is a UTC-parts read replaced by a local-parts read, and east of Greenwich the two
 * agree for a UTC-midnight value, so an eastern pin (or CI's UTC) would leave this suite green
 * straight through the bug. The first test below fails loudly if the pin did not take.
 *
 * Subject is `contract-dates.ts`, not the panel: `MJCContractDatesPanel` is an `@Component` and
 * `new`-ing it outside an Angular host dies in `PlatformLocation`'s JIT fallback before any
 * assertion runs. The last describe holds the panel to its delegation instead — over a slice bounded
 * to that ONE class, because an unbounded slice polices whatever happens to be declared after it.
 */
process.env.TZ = 'America/Chicago';

import { describe, expect, it } from 'vitest';
import { DateAsInput, DateAsText, InputAsDate } from '../contract-dates';

describe('the pinned zone', () => {
    it('is west of Greenwich, so a local-parts read lands on the previous day', () => {
        // A guard, not a behaviour test. If TZ did not take, every assertion below would run on a
        // runtime where UTC parts and local parts agree, and would pass proving nothing.
        expect(Intl.DateTimeFormat().resolvedOptions().timeZone).toBe('America/Chicago');
        expect(new Date('2026-09-01T00:00:00.000Z').getDate()).toBe(31);
    });
});

describe('DateAsInput — reading a stored calendar day', () => {
    it('renders a stored UTC-midnight date as its own day, not the evening before', () => {
        // 1 Sep at UTC midnight is 31 Aug 19:00 in Chicago: the two readings genuinely disagree here.
        expect(DateAsInput(new Date('2026-09-01T00:00:00.000Z'))).toBe('2026-09-01');
    });
    it('renders a year-end stored date as its own day', () => {
        expect(DateAsInput(new Date('2026-12-31T00:00:00.000Z'))).toBe('2026-12-31');
    });
    it('takes an offset-bearing string as written rather than re-basing it', () => {
        // 2026-09-30T23:00:00-05:00 is 2026-10-01T04:00Z. The day that was stored is the 30th.
        expect(DateAsInput('2026-09-30T23:00:00-05:00')).toBe('2026-09-30');
    });
    it('takes a plain day string as written', () => {
        expect(DateAsInput('2026-09-01')).toBe('2026-09-01');
    });
    it('is empty for absent or unreadable values, and never throws', () => {
        expect(DateAsInput(null)).toBe('');
        expect(DateAsInput(undefined)).toBe('');
        expect(DateAsInput('')).toBe('');
        expect(DateAsInput('not-a-date')).toBe('');
        expect(DateAsInput(new Date('nonsense'))).toBe('');
    });
});

describe('InputAsDate — writing a picked calendar day', () => {
    it('writes UTC midnight of the picked day, the shape a DATE column round-trips as', () => {
        expect(InputAsDate('2026-12-31')?.toISOString()).toBe('2026-12-31T00:00:00.000Z');
    });
    it('writes UTC midnight for a day whose local midnight falls in the prior month', () => {
        expect(InputAsDate('2026-09-01')?.toISOString()).toBe('2026-09-01T00:00:00.000Z');
    });
    it('clears the field on an empty input', () => {
        expect(InputAsDate('')).toBeNull();
    });
    it('clears rather than throwing or storing an Invalid Date on an unreadable input', () => {
        expect(InputAsDate('not-a-date')).toBeNull();
    });
    it('round-trips a picked day back into the input unchanged', () => {
        expect(DateAsInput(InputAsDate('2026-09-01'))).toBe('2026-09-01');
    });
});

describe('DateAsText — rendering a stored calendar day read-only', () => {
    /*
     * The assertions are on the DAY NUMBER rather than on a formatted string, because the locale is
     * the viewer's and a literal expectation would pin this suite to whichever locale the test
     * runtime happens to have. The DAY is the whole defect: in Chicago a local-zone render of
     * 31 December at UTC midnight reads 30 December, so the pair of assertions below distinguishes
     * the fix from the bug in any locale.
     */
    it('renders the stored day, not the evening before it, in the viewer\u2019s zone', () => {
        const text = DateAsText(new Date('2026-12-31T00:00:00.000Z'));
        expect(text).toMatch(/\b31\b/);
        expect(text).not.toMatch(/\b30\b/);
        expect(text).toContain('2026');
    });

    it('does not slide a month boundary backwards', () => {
        // 1 Sep at UTC midnight is 31 Aug 19:00 in Chicago — a different day, month AND (elsewhere)
        // year. `| date: 'd MMM y'` rendered this as 31 Aug.
        const text = DateAsText(new Date('2026-09-01T00:00:00.000Z'));
        expect(text).toMatch(/\b1\b/);
        expect(text).not.toMatch(/\b31\b/);
        expect(text).not.toMatch(/Aug/i);
    });

    it('takes an offset-bearing string as written rather than re-basing it', () => {
        // 2026-09-30T23:00:00-05:00 is 2026-10-01T04:00Z. The day that was stored is the 30th.
        const text = DateAsText('2026-09-30T23:00:00-05:00');
        expect(text).toMatch(/\b30\b/);
        expect(text).not.toMatch(/\b1\b/);
    });

    it('agrees with the edit-mode input for the same value — the whole point', () => {
        // The bug was one screen showing two days for one column: the `<input type="date">` read UTC
        // parts and the read-only `<div>` beside it did not.
        for (const value of ['2026-12-31', '2026-09-01', '2026-09-30T23:00:00-05:00']) {
            const day = DateAsInput(value);
            expect(DateAsText(value)).toContain(String(Number(day.slice(8, 10))));
        }
    });

    it('is an em dash for absent or unreadable values, and never throws', () => {
        expect(DateAsText(null)).toBe('\u2014');
        expect(DateAsText(undefined)).toBe('\u2014');
        expect(DateAsText('')).toBe('\u2014');
        expect(DateAsText('not-a-date')).toBe('\u2014');
        expect(DateAsText(new Date('nonsense'))).toBe('\u2014');
    });
});

describe('MJCContractDatesPanel', () => {
    it('delegates all three helpers and keeps no calendar arithmetic of its own', async () => {
        // The panel cannot be constructed here, so the wiring is checked as source. `ngc` proves it
        // typechecks and that the template still binds AsInput/SetDate/DateText; this proves the
        // bodies did not quietly grow a second implementation of the rule.
        const datesPanel = await readPanelClass('MJCContractDatesPanel');
        expect(datesPanel).toContain('return DateAsInput(v);');
        expect(datesPanel).toContain('InputAsDate(value)');
        expect(datesPanel).toContain('public DateText = DateAsText;');
        expect(datesPanel).not.toContain('toISOString');
        expect(datesPanel).not.toContain('new Date(');
    });

    it('renders every read-only date through the shared helper, never the local-zone date pipe', async () => {
        // bc-aidp-next-golive#168: `| date` formats in the VIEWER'S zone, so a `DATE` column at UTC
        // midnight rendered as the PREVIOUS day — the same panel showed 31 Dec in the input and
        // 30 Dec in the read-only div. All four columns, so a fifth field cannot be added the old way
        // and pass.
        const panel = await readPanelSource();
        const template = panel.slice(panel.indexOf("selector: 'mjc-contract-dates-panel'"), panel.indexOf('export class MJCContractDatesPanel'));
        for (const field of ['ExecutedDate', 'EffectiveDate', 'EndDate', 'TerminatedDate']) {
            expect(template).toContain(`{{ DateText(Record.${field}) }}`);
        }
        expect(template).not.toContain('| date');
    });

    it('leaves no local-zone date pipe anywhere in the file', async () => {
        // The hero's three stats and the renewal panel's deadline hint had the same defect, so the
        // guard is the whole file rather than the one panel. `| date` on a DATE column is never right
        // here; on a DATETIMEOFFSET it would be, and this file holds none.
        expect(await readPanelSource()).not.toContain('| date');
    });
});

/**
 * ONE panel class's body, bounded at the NEXT `export class` (or EOF).
 *
 * The bound is the whole point and it was missing: `slice(indexOf('export class MJCContractDatesPanel'))`
 * runs to end-of-file, so the absence checks above were also policing `MJCContractLineagePanel`,
 * which follows it in the same file and has nothing to do with the calendar-day rule. A perfectly
 * correct `new Date(` in the lineage panel would have failed a test about the dates panel, and the
 * repair anybody reaches for first is to delete the assertion.
 */
async function readPanelClass(name: string): Promise<string> {
    const source = await readPanelSource();
    const start = source.indexOf(`export class ${name}`);
    expect(start).toBeGreaterThan(-1);
    const next = source.indexOf('\nexport class ', start + 1);
    const body = next === -1 ? source.slice(start) : source.slice(start, next);
    // A slice that swallowed the rest of the file would still satisfy every assertion above, so the
    // bound is asserted rather than assumed.
    expect(body).not.toContain('export class MJCContractLineagePanel');
    return body;
}

/** Read through a URL rather than a path so the test needs no `node:path`. */
async function readPanelSource(): Promise<string> {
    const { readFile } = await import('node:fs/promises');
    return readFile(new URL('../contract.panels.ts', import.meta.url), 'utf8');
}
