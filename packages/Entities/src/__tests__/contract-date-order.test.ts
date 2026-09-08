/**
 * R-12 — End Date may not fall before Effective Date, said in words before SQL says it in constraint text.
 *
 * WHY THIS EXISTS. `CK_Contract_Dates` has guarded the table since the baseline, so the data was never
 * at risk. What a user got was the raw violation: a constraint name, no field, no sentence. contracts#28
 * item 12 asks for the rule to be stated on the End Date field before a save is attempted, and
 * `ContractEntity.Validate()` runs in the browser AND on the server, so one rule covers both.
 *
 * WHAT IS ASSERTED, AND WHY IT IS ASSERTED THIS WAY. The table below is written from the CONSTRAINT —
 * `EndDate IS NULL OR EffectiveDate IS NULL OR EndDate >= EffectiveDate` — not from the function. That
 * direction matters: a test read off the implementation agrees with whatever the implementation does,
 * including whatever it does wrong. The failure that would matter most here is a validator STRICTER
 * than the database, which refuses rows SQL would accept; `equal dates` and the two `null` rows are the
 * cases that catch it.
 *
 * It asserts the real exported function rather than a local copy of the logic. `has-modifications-guard`
 * in this same folder restates its rule and says plainly that the restatement can drift — that was the
 * right trade there, because instantiating a BaseEntity needs a provider. It is not the trade here,
 * because `IsEndBeforeEffective` is pure and exported for exactly this reason.
 */
import { describe, expect, it } from 'vitest';
import { IsEndBeforeEffective } from '../ContractEntity.js';

const DAY = 86_400_000;
const JUN = new Date('2026-06-01T00:00:00Z');
const MAY = new Date(JUN.getTime() - 31 * DAY);

describe('IsEndBeforeEffective — the constraint, as a predicate', () => {
    it('refuses an end date before the effective date — the case the user hit', () => {
        // Andrew's repro exactly: Effective 1 Jun 2026, End 1 May 2026.
        expect(IsEndBeforeEffective(JUN, MAY)).toBe(true);
    });

    it('allows an end date after the effective date', () => {
        expect(IsEndBeforeEffective(MAY, JUN)).toBe(false);
    });

    it('ALLOWS equal dates — a one-day agreement is a real contract', () => {
        // The database accepts this (`>=`). A validator that refused it would reject rows SQL permits,
        // which is a worse defect than the raw error this replaces.
        expect(IsEndBeforeEffective(JUN, new Date(JUN.getTime()))).toBe(false);
    });

    it('allows one day apart in the good direction, and refuses one day apart in the bad one', () => {
        // The boundary either side of equal, so an off-by-one in the comparison cannot hide behind the
        // month-apart cases above.
        expect(IsEndBeforeEffective(JUN, new Date(JUN.getTime() + DAY))).toBe(false);
        expect(IsEndBeforeEffective(JUN, new Date(JUN.getTime() - DAY))).toBe(true);
    });

    describe('a half-filled form is not an error', () => {
        // Mirrors `EndDate IS NULL OR EffectiveDate IS NULL OR ...`. Every one of these is a state a
        // form passes through while someone is typing.
        const absent = [null, undefined, ''] as const;
        for (const missing of absent) {
            it(`allows a missing effective date (${JSON.stringify(missing)})`, () => {
                expect(IsEndBeforeEffective(missing, MAY)).toBe(false);
            });
            it(`allows a missing end date (${JSON.stringify(missing)})`, () => {
                expect(IsEndBeforeEffective(JUN, missing)).toBe(false);
            });
        }
        it('allows both missing', () => {
            expect(IsEndBeforeEffective(null, null)).toBe(false);
        });
    });

    describe('shapes other than Date, because a form binding supplies them', () => {
        it('compares ISO strings the same way it compares Dates', () => {
            // The field is typed `Date | null`; a date input hands over a string. Comparing a string to
            // a Date with `<` compares nonsense rather than throwing, so this is the shape most likely
            // to make the rule quietly stop working.
            expect(IsEndBeforeEffective('2026-06-01', '2026-05-01')).toBe(true);
            expect(IsEndBeforeEffective('2026-05-01', '2026-06-01')).toBe(false);
        });

        it('compares a mixed Date/string pair correctly in both directions', () => {
            expect(IsEndBeforeEffective(JUN, '2026-05-01')).toBe(true);
            expect(IsEndBeforeEffective('2026-05-01', JUN)).toBe(false);
        });

        it('treats an unreadable value as not-yet-known rather than as a violation', () => {
            // A half-typed date parses to Invalid Date. Reporting an error on it would put a message
            // under a field the user is still filling in.
            expect(IsEndBeforeEffective(JUN, 'not a date')).toBe(false);
            expect(IsEndBeforeEffective('not a date', MAY)).toBe(false);
            expect(IsEndBeforeEffective(new Date('nope'), MAY)).toBe(false);
        });
    });
});
