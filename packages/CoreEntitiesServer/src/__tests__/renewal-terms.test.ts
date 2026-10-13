/**
 * Copying a contract's renewal terms to the subscriptions it governs (issue #77).
 *
 * A fake provider stands in for the database: what matters is which subscriptions are found through
 * the contract's linked orders and what each one is saved with, and both are observable without SQL.
 */
import { describe, expect, it } from 'vitest';
import {
    ApplyContractRenewalTerms,
    type ContractRenewalTerms,
    E_CONTRACT_ORDER,
    E_ORDER_LINE,
    E_SUBSCRIPTION,
    type RenewalTermsProvider,
} from '../renewal-terms.js';

type SubRow = {
    ID: string;
    SubscriptionNumber: string;
    OrderLineID: string;
    RenewalIncreasePercent: number | null;
    CarryDiscountOnRenewal: boolean;
    Refuse?: string;
};

function makeWorld(opts: {
    links: Array<{ ContractID: string; OrderID: string }>;
    lines: Array<{ ID: string; OrderHeaderID: string }>;
    subs: SubRow[];
}) {
    const saves: Array<{ SubscriptionNumber: string; RenewalIncreasePercent: number | null; CarryDiscountOnRenewal: boolean }> = [];

    const subEntity = (row: SubRow) => {
        const original = { ...row };
        return {
            get SubscriptionNumber() { return row.SubscriptionNumber; },
            get RenewalIncreasePercent() { return row.RenewalIncreasePercent; },
            set RenewalIncreasePercent(v: number | null) { row.RenewalIncreasePercent = v; },
            get CarryDiscountOnRenewal() { return row.CarryDiscountOnRenewal; },
            set CarryDiscountOnRenewal(v: boolean) { row.CarryDiscountOnRenewal = v; },
            get Dirty() {
                return row.RenewalIncreasePercent !== original.RenewalIncreasePercent ||
                    row.CarryDiscountOnRenewal !== original.CarryDiscountOnRenewal;
            },
            LatestResult: { CompleteMessage: row.Refuse ?? '' },
            async Save() {
                if (row.Refuse) return false;
                saves.push({
                    SubscriptionNumber: row.SubscriptionNumber,
                    RenewalIncreasePercent: row.RenewalIncreasePercent,
                    CarryDiscountOnRenewal: row.CarryDiscountOnRenewal,
                });
                return true;
            },
        };
    };

    const inList = (filter: string, column: string): string[] => {
        const m = new RegExp(`${column}(?:=| IN \\()([^)]*)`).exec(filter);
        return (m?.[1] ?? '').split(',').map((v) => v.replace(/'/g, '').trim()).filter(Boolean);
    };

    const provider = {
        async RunView(params: { EntityName: string; ExtraFilter: string }) {
            switch (params.EntityName) {
                case E_CONTRACT_ORDER: {
                    const ids = inList(params.ExtraFilter, 'ContractID');
                    return { Success: true, Results: opts.links.filter((l) => ids.includes(l.ContractID)) };
                }
                case E_ORDER_LINE: {
                    const ids = inList(params.ExtraFilter, 'OrderHeaderID');
                    return { Success: true, Results: opts.lines.filter((l) => ids.includes(l.OrderHeaderID)) };
                }
                case E_SUBSCRIPTION: {
                    const ids = inList(params.ExtraFilter, 'OrderLineID');
                    return { Success: true, Results: opts.subs.filter((s) => ids.includes(s.OrderLineID)).map(subEntity) };
                }
                default:
                    return { Success: false, ErrorMessage: `unexpected entity ${params.EntityName}`, Results: [] };
            }
        },
    } as unknown as RenewalTermsProvider;

    return { provider, saves };
}

const TERMS = (over: Partial<ContractRenewalTerms> = {}): ContractRenewalTerms => ({
    ContractID: 'C-1',
    ContractNumber: 'CTR-0001',
    AnnualIncreasePercent: 6,
    CarryDiscountOnRenewal: false,
    ...over,
});

/** Contract C-1 governs order O-1 (two lines, two subscriptions); order O-2 belongs to nobody. */
const WORLD = (subs: Partial<SubRow>[] = []) =>
    makeWorld({
        links: [{ ContractID: 'C-1', OrderID: 'O-1' }],
        lines: [
            { ID: 'L-1', OrderHeaderID: 'O-1' },
            { ID: 'L-2', OrderHeaderID: 'O-1' },
            { ID: 'L-3', OrderHeaderID: 'O-2' },
        ],
        subs: [
            { ID: 'S-1', SubscriptionNumber: 'SUB-1', OrderLineID: 'L-1', RenewalIncreasePercent: null, CarryDiscountOnRenewal: false, ...subs[0] },
            { ID: 'S-2', SubscriptionNumber: 'SUB-2', OrderLineID: 'L-2', RenewalIncreasePercent: null, CarryDiscountOnRenewal: false, ...subs[1] },
            { ID: 'S-3', SubscriptionNumber: 'SUB-3', OrderLineID: 'L-3', RenewalIncreasePercent: null, CarryDiscountOnRenewal: false, ...subs[2] },
        ],
    });

describe('ApplyContractRenewalTerms', () => {
    it('writes the increase to every subscription of a linked order, and to no other', async () => {
        const { provider, saves } = WORLD();
        const outcome = await ApplyContractRenewalTerms(provider, TERMS(), undefined);
        expect(outcome.Updated.sort()).toEqual(['SUB-1', 'SUB-2']);
        expect(saves.map((s) => s.RenewalIncreasePercent)).toEqual([6, 6]);
        expect(saves.some((s) => s.SubscriptionNumber === 'SUB-3')).toBe(false);
    });

    it('leaves a hand-set increase alone when the contract states none', async () => {
        const { provider, saves } = WORLD([{ RenewalIncreasePercent: 4 }]);
        const outcome = await ApplyContractRenewalTerms(provider, TERMS({ AnnualIncreasePercent: null }), undefined);
        expect(saves).toEqual([]);
        expect(outcome.Unchanged).toBe(2);
    });

    it('overwrites a hand-set increase when the contract states one', async () => {
        const { provider, saves } = WORLD([{ RenewalIncreasePercent: 4 }]);
        await ApplyContractRenewalTerms(provider, TERMS({ AnnualIncreasePercent: 5 }), undefined);
        expect(saves.find((s) => s.SubscriptionNumber === 'SUB-1')?.RenewalIncreasePercent).toBe(5);
    });

    it('always copies the carry-discount flag, in both directions', async () => {
        const on = WORLD();
        await ApplyContractRenewalTerms(on.provider, TERMS({ AnnualIncreasePercent: null, CarryDiscountOnRenewal: true }), undefined);
        expect(on.saves.map((s) => s.CarryDiscountOnRenewal)).toEqual([true, true]);

        const off = WORLD([{ CarryDiscountOnRenewal: true }]);
        await ApplyContractRenewalTerms(off.provider, TERMS({ AnnualIncreasePercent: null, CarryDiscountOnRenewal: false }), undefined);
        expect(off.saves).toEqual([{ SubscriptionNumber: 'SUB-1', RenewalIncreasePercent: null, CarryDiscountOnRenewal: false }]);
    });

    it('saves nothing when every subscription already carries the terms', async () => {
        const { provider, saves } = WORLD([{ RenewalIncreasePercent: 6 }, { RenewalIncreasePercent: 6 }]);
        const outcome = await ApplyContractRenewalTerms(provider, TERMS(), undefined);
        expect(saves).toEqual([]);
        expect(outcome).toEqual({ Updated: [], Unchanged: 2, Failed: [] });
    });

    it('reports an increase above what a subscription accepts instead of saving it', async () => {
        const { provider, saves } = WORLD();
        const outcome = await ApplyContractRenewalTerms(provider, TERMS({ AnnualIncreasePercent: 150 }), undefined);
        expect(saves).toEqual([]);
        expect(outcome.Failed.map((f) => f.SubscriptionNumber).sort()).toEqual(['SUB-1', 'SUB-2']);
        expect(outcome.Failed[0].Message).toContain('150%');
    });

    it('reports a subscription that refuses the save and still updates the others', async () => {
        const { provider, saves } = WORLD([{ Refuse: 'subscription is canceled' }]);
        const outcome = await ApplyContractRenewalTerms(provider, TERMS(), undefined);
        expect(outcome.Failed).toEqual([{ SubscriptionNumber: 'SUB-1', Message: 'subscription is canceled' }]);
        expect(saves.map((s) => s.SubscriptionNumber)).toEqual(['SUB-2']);
    });

    it('does nothing for a contract with no linked orders', async () => {
        const { provider, saves } = WORLD();
        const outcome = await ApplyContractRenewalTerms(provider, TERMS({ ContractID: 'C-9' }), undefined);
        expect(saves).toEqual([]);
        expect(outcome).toEqual({ Updated: [], Unchanged: 0, Failed: [] });
    });

    it('throws when a lookup fails, rather than reporting nothing to copy', async () => {
        const provider = { async RunView() { return { Success: false, ErrorMessage: 'boom', Results: [] }; } } as unknown as RenewalTermsProvider;
        await expect(ApplyContractRenewalTerms(provider, TERMS(), undefined)).rejects.toThrow(/boom/);
    });
});
