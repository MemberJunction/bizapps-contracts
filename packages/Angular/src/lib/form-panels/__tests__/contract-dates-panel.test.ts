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
 * assertion runs. The last describe holds the panel to its delegation instead.
 */
process.env.TZ = 'America/Chicago';

import { describe, expect, it } from 'vitest';
import { DateAsInput, InputAsDate } from '../contract-dates';

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

describe('MJCContractDatesPanel', () => {
    it('delegates both helpers and keeps no calendar arithmetic of its own', async () => {
        // The panel cannot be constructed here, so the wiring is checked as source. `ngc` proves it
        // typechecks and that the template still binds AsInput/SetDate; this proves the bodies did
        // not quietly grow a second implementation of the rule.
        const source = await readPanelSource();
        const datesPanel = source.slice(source.indexOf('export class MJCContractDatesPanel'));
        expect(datesPanel).toContain('return DateAsInput(v);');
        expect(datesPanel).toContain('InputAsDate(value)');
        expect(datesPanel).not.toContain('toISOString');
        expect(datesPanel).not.toContain('new Date(');
    });
});

/** Read through a URL rather than a path so the test needs no `node:path`. */
async function readPanelSource(): Promise<string> {
    const { readFile } = await import('node:fs/promises');
    return readFile(new URL('../contract.panels.ts', import.meta.url), 'utf8');
}
