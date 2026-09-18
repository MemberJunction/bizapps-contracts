/**
 * Seeding the renewal fields from the Contract Type — the whole decision, which needs no database.
 *
 * Written from the ACCEPTANCE CRITERIA of golive #217 rather than from the implementation, one test
 * per criterion, plus the three cases that are easy to get backwards and silent when wrong:
 *
 *   · a deliberate `AutoRenew = No` is byte-identical to the untouched default, so only the explicit
 *     edit signal can protect it — the single failure this feature must not have;
 *   · `0` days and `0%` are values somebody negotiated, not absences;
 *   · a `bit` arriving as `'0'` from a stringifying transport must not read as `true`.
 */
import { describe, expect, it } from 'vitest';
import { ComputeRenewalSeed, RENEWAL_SEED_FIELDS, type ContractRenewalField } from '../renewal-defaults';

/** A new contract, before any type is chosen: AutoRenew No, the three numbers blank. */
const NEW_CONTRACT = {
    AutoRenew: false,
    RenewalNoticeDays: null,
    CancellationWindowDays: null,
    AnnualIncreasePercent: null,
} as const;

/** A type that states all four. */
const FULL_TYPE = {
    DefaultAutoRenew: true,
    DefaultRenewalNoticeDays: 60,
    DefaultCancellationWindowDays: 30,
    DefaultAnnualIncreasePercent: 3.5,
};

/** A type that states none of them — every column NULL, which is how every existing row starts. */
const SILENT_TYPE = {
    DefaultAutoRenew: null,
    DefaultRenewalNoticeDays: null,
    DefaultCancellationWindowDays: null,
    DefaultAnnualIncreasePercent: null,
};

/** The seed as it would leave the record: current values with the computed writes applied over them. */
function applied(current: Record<string, unknown>, seed: Record<string, unknown>) {
    return { ...current, ...seed };
}

describe('picking a type on a new contract', () => {
    it('fills all four fields from that type (AC 2)', () => {
        const seed = ComputeRenewalSeed({
            defaults: FULL_TYPE,
            current: NEW_CONTRACT,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(seed).toEqual({
            AutoRenew: true,
            RenewalNoticeDays: 60,
            CancellationWindowDays: 30,
            AnnualIncreasePercent: 3.5,
        });
    });

    it('leaves a type with no defaults reading exactly as today — No and blank (AC 5)', () => {
        const seed = ComputeRenewalSeed({
            defaults: SILENT_TYPE,
            current: NEW_CONTRACT,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(seed).toEqual({});
    });

    it('writes nothing when re-seeded from the same type — no phantom dirty flag', () => {
        const current = applied(NEW_CONTRACT, {
            AutoRenew: true,
            RenewalNoticeDays: 60,
            CancellationWindowDays: 30,
            AnnualIncreasePercent: 3.5,
        });
        expect(ComputeRenewalSeed({ defaults: FULL_TYPE, current, pristine: NEW_CONTRACT, userEdited: [] })).toEqual({});
    });
});

describe('changing the type before saving (AC 3)', () => {
    it('replaces the values the previous type seeded', () => {
        const afterFirstType = applied(NEW_CONTRACT, {
            AutoRenew: true,
            RenewalNoticeDays: 60,
            CancellationWindowDays: 30,
            AnnualIncreasePercent: 3.5,
        });
        const seed = ComputeRenewalSeed({
            defaults: { ...SILENT_TYPE, DefaultRenewalNoticeDays: 90, DefaultAutoRenew: false },
            current: afterFirstType,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(applied(afterFirstType, seed)).toEqual({
            AutoRenew: false,
            RenewalNoticeDays: 90,
            // The new type says nothing about these two, so the DEPARTING type's numbers leave with
            // it rather than staying on a contract that never claimed them.
            CancellationWindowDays: null,
            AnnualIncreasePercent: null,
        });
    });

    it('does not clobber a value the user already edited', () => {
        const edited = applied(NEW_CONTRACT, { RenewalNoticeDays: 45 });
        const seed = ComputeRenewalSeed({
            defaults: FULL_TYPE,
            current: edited,
            pristine: NEW_CONTRACT,
            userEdited: ['RenewalNoticeDays'],
        });
        expect(seed.RenewalNoticeDays).toBeUndefined();
        expect(applied(edited, seed).RenewalNoticeDays).toBe(45);
        // The fields the user did NOT touch still follow the type.
        expect(seed.CancellationWindowDays).toBe(30);
    });

    it('protects a deliberate AutoRenew = No, which looks identical to the untouched default', () => {
        const seed = ComputeRenewalSeed({
            defaults: FULL_TYPE, // says Yes
            current: NEW_CONTRACT, // holds No — indistinguishable from never-touched
            pristine: NEW_CONTRACT,
            userEdited: ['AutoRenew'],
        });
        expect(seed.AutoRenew).toBeUndefined();
    });

    it('restores the pristine values when the type is cleared altogether', () => {
        const seeded = applied(NEW_CONTRACT, { AutoRenew: true, RenewalNoticeDays: 60 });
        const seed = ComputeRenewalSeed({ defaults: null, current: seeded, pristine: NEW_CONTRACT, userEdited: [] });
        expect(applied(seeded, seed)).toEqual(NEW_CONTRACT);
    });
});

describe('values that are easy to lose', () => {
    it('seeds zero days and zero percent, which are negotiated terms rather than blanks', () => {
        const seed = ComputeRenewalSeed({
            defaults: { ...SILENT_TYPE, DefaultRenewalNoticeDays: 0, DefaultAnnualIncreasePercent: 0 },
            current: NEW_CONTRACT,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(seed.RenewalNoticeDays).toBe(0);
        expect(seed.AnnualIncreasePercent).toBe(0);
    });

    it("reads a bit arriving as '0' as No, not as a non-empty string", () => {
        const current = applied(NEW_CONTRACT, { AutoRenew: true });
        const seed = ComputeRenewalSeed({
            defaults: { ...SILENT_TYPE, DefaultAutoRenew: '0' },
            current,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(seed.AutoRenew).toBe(false);
    });

    it('accepts the numeric forms a driver may return for a bit', () => {
        for (const yes of [1, true, '1', 'true']) {
            const seed = ComputeRenewalSeed({
                defaults: { ...SILENT_TYPE, DefaultAutoRenew: yes },
                current: NEW_CONTRACT,
                pristine: NEW_CONTRACT,
                userEdited: [],
            });
            expect(seed.AutoRenew, `${String(yes)} should read as Yes`).toBe(true);
        }
    });

    it('does not re-write a value that only differs by the string/number the form produced', () => {
        const current = applied(NEW_CONTRACT, { RenewalNoticeDays: '60' });
        const seed = ComputeRenewalSeed({
            defaults: { ...SILENT_TYPE, DefaultRenewalNoticeDays: 60 },
            current,
            pristine: NEW_CONTRACT,
            userEdited: [],
        });
        expect(seed.RenewalNoticeDays).toBeUndefined();
    });
});

describe('the field map', () => {
    it('pairs every Default* column with the Contract column it seeds', () => {
        // The RunView field list and the writes both come from this map, so a rename that updates one
        // and not the other cannot happen — but a missing PAIR can, and it would seed three fields
        // while looking like it seeds four.
        expect(RENEWAL_SEED_FIELDS.map((f) => [f.TypeField, f.ContractField])).toEqual([
            ['DefaultAutoRenew', 'AutoRenew'],
            ['DefaultRenewalNoticeDays', 'RenewalNoticeDays'],
            ['DefaultCancellationWindowDays', 'CancellationWindowDays'],
            ['DefaultAnnualIncreasePercent', 'AnnualIncreasePercent'],
        ]);
    });

    it('names each contract column exactly once', () => {
        const names = RENEWAL_SEED_FIELDS.map((f) => f.ContractField as ContractRenewalField);
        expect(new Set(names).size).toBe(names.length);
    });
});
