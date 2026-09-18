/**
 * `ContractEntity.SeedRenewalDefaultsFromType()` — the half that reads and writes (golive #217).
 *
 * The DECISION is proven in `renewal-defaults.test.ts`. What is left here is the behaviour around it,
 * and all of it is behaviour a restatement would not catch:
 *
 *   · saved records are never seeded — the guard that keeps this feature away from contracts whose
 *     values somebody entered from paper;
 *   · the pristine snapshot is taken ONCE, before the first write, so a second type change restores
 *     the record's own starting values rather than the first type's defaults;
 *   · an unreadable or unselected type restores rather than throws.
 *
 * Called through `Function.prototype.call` on a minimal stub rather than a real `BaseEntity`, which
 * would need a metadata provider and a database — the same reason `has-modifications-guard.test.ts`
 * does not instantiate one. Unlike that file this is not a restatement: the code under test is the
 * real method, reached through the prototype.
 */
import { describe, expect, it } from 'vitest';
import { ContractEntity } from '../ContractEntity';
import type { ContractRenewalField } from '../renewal-defaults';

const TYPE_A = 'A1B2C3D4-0000-4000-8000-00000000000A';
const TYPE_B = 'B1B2C3D4-0000-4000-8000-00000000000B';

type Row = Record<string, unknown>;

/**
 * A stand-in for the entity: a real `ContractEntity` PROTOTYPE with the handful of members the method
 * touches defined as own properties. Built with `Object.create` + `defineProperty` rather than a
 * literal, so the private helpers (`currentRenewalValues`, `loadRenewalDefaults`) are the real ones,
 * and so `IsSaved` — a getter-only accessor on `BaseEntity` — can be shadowed at all.
 */
function stub(options: { isSaved?: boolean; typeID?: string | null; rows?: Record<string, Row> } = {}) {
    const values: Row = {
        AutoRenew: false,
        RenewalNoticeDays: null,
        CancellationWindowDays: null,
        AnnualIncreasePercent: null,
    };
    const reads: string[] = [];
    const members = {
        IsSaved: options.isSaved ?? false,
        ContractTypeID: options.typeID ?? null,
        ContextCurrentUser: undefined,
        renewalFieldsUserEdited: new Set<ContractRenewalField>(),
        renewalFieldsPristine: null,
        Get: (f: string) => values[f],
        Set: (f: string, v: unknown) => {
            values[f] = v;
        },
        RunViewProviderToUse: {
            RunView: async (params: { ExtraFilter: string }) => {
                reads.push(params.ExtraFilter);
                const id = /'([^']+)'/.exec(params.ExtraFilter)?.[1] ?? '';
                const row = options.rows?.[id.toUpperCase()];
                return { Success: true, Results: row ? [row] : [] };
            },
        },
        values,
        reads,
    };

    const self = Object.create(ContractEntity.prototype) as typeof members;
    for (const [key, value] of Object.entries(members)) {
        Object.defineProperty(self, key, { value, writable: true, enumerable: true, configurable: true });
    }
    return self;
}

const seed = (self: ReturnType<typeof stub>) =>
    (self as unknown as ContractEntity).SeedRenewalDefaultsFromType();

const TYPES = {
    [TYPE_A]: { DefaultAutoRenew: true, DefaultRenewalNoticeDays: 60, DefaultCancellationWindowDays: 30 },
    [TYPE_B]: { DefaultRenewalNoticeDays: 90 },
};

describe('seeding from the selected type', () => {
    it('writes the type\'s defaults onto a new contract', async () => {
        const self = stub({ typeID: TYPE_A, rows: TYPES });
        await expect(seed(self)).resolves.toBe(true);
        expect(self.values).toEqual({
            AutoRenew: true,
            RenewalNoticeDays: 60,
            CancellationWindowDays: 30,
            AnnualIncreasePercent: null,
        });
    });

    it('never touches a saved contract, and does not even read the type row', async () => {
        const self = stub({ isSaved: true, typeID: TYPE_A, rows: TYPES });
        await expect(seed(self)).resolves.toBe(false);
        expect(self.values.RenewalNoticeDays).toBeNull();
        expect(self.reads).toEqual([]);
    });

    it('restores the record\'s own starting values when the second type says nothing', async () => {
        const self = stub({ typeID: TYPE_A, rows: TYPES });
        await seed(self);

        self.ContractTypeID = TYPE_B;
        await seed(self);

        // Type B states a notice period and nothing else, so A's Yes and A's cancellation window go
        // with A — the pristine snapshot is what they revert to, not B's silence layered over A.
        expect(self.values).toEqual({
            AutoRenew: false,
            RenewalNoticeDays: 90,
            CancellationWindowDays: null,
            AnnualIncreasePercent: null,
        });
    });

    it('keeps a field the user edited, across a type change', async () => {
        const self = stub({ typeID: TYPE_A, rows: TYPES });
        (self as unknown as ContractEntity).MarkRenewalFieldEdited('RenewalNoticeDays');
        self.values.RenewalNoticeDays = 45;

        await seed(self);
        self.ContractTypeID = TYPE_B;
        await seed(self);

        expect(self.values.RenewalNoticeDays).toBe(45);
    });

    it('reads nothing and writes nothing when no type is selected yet', async () => {
        const self = stub({ typeID: null, rows: TYPES });
        await expect(seed(self)).resolves.toBe(false);
        expect(self.reads).toEqual([]);
    });

    it('refuses to interpolate an ID that is not a UUID', async () => {
        const self = stub({ typeID: "' OR 1=1 --", rows: TYPES });
        await expect(seed(self)).resolves.toBe(false);
        expect(self.reads).toEqual([]);
    });

    it('leaves the fields alone when the type row cannot be found', async () => {
        const self = stub({ typeID: TYPE_A, rows: TYPES });
        await seed(self);

        self.ContractTypeID = 'C1B2C3D4-0000-4000-8000-00000000000C'; // no such row
        await seed(self);
        expect(self.values).toEqual({
            AutoRenew: false,
            RenewalNoticeDays: null,
            CancellationWindowDays: null,
            AnnualIncreasePercent: null,
        });
    });
});
