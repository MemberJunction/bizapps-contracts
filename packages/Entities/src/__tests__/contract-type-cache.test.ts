/**
 * Shared per-provider cache for `ContractType` rows (#150).
 *
 * Verifies that when `ContractTypeID` changes on an unsaved contract, both
 * `ContractEntity.SeedRenewalDefaultsFromType()` and `MJCContractAgreementPanel` (via
 * `ContractEntity.ReadSelectedContractType()`) share a single `RunView` call per `(provider, typeID)`
 * — including when both fire concurrently on the same tick — and that `InvalidateContractTypeCache`
 * evicts stale entries after a save or delete. Eviction from `ContractTypeEntity.Save` / `.Delete`
 * themselves is covered in `contract-type-entity-save.test.ts`.
 */
import { describe, expect, it, vi } from 'vitest';
import type { IRunViewProvider } from '@memberjunction/core';
import {
    CONTRACT_TYPE_CACHE_TTL_MS,
    InvalidateContractTypeCache,
    ReadContractTypeByID,
    type ContractTypeCachedRow,
} from '../contract-type-cache';

const ORDER_FORM_ID = '33333333-0000-4000-8000-000000001001';
const SOW_ID = '33333333-0000-4000-8000-000000001002';
const MASTER_AGREEMENT_TYPE_ID = '33333333-0000-4000-8000-000000002001';

const ORDER_FORM_ROW: ContractTypeCachedRow = {
    ID: ORDER_FORM_ID,
    Name: 'Order Form',
    TemplateRequired: true,
    ContractTemplateTypeID: MASTER_AGREEMENT_TYPE_ID,
    Status: 'Active',
    DefaultAutoRenew: true,
    DefaultRenewalNoticeDays: 60,
    DefaultCancellationWindowDays: 30,
    DefaultAnnualIncreasePercent: 5,
};

function createMockProvider(impl?: (filter: string) => Promise<{ Success: boolean; Results?: ContractTypeCachedRow[]; ErrorMessage?: string }>) {
    const runView = vi.fn(async (params: { ExtraFilter: string }) => {
        if (impl) return impl(params.ExtraFilter);
        return { Success: true, Results: [ORDER_FORM_ROW] };
    });
    return {
        provider: { RunView: runView } as unknown as IRunViewProvider,
        runView,
    };
}

describe('ReadContractTypeByID (#150)', () => {
    it('coalesces concurrent reads for the same (provider, typeID) into a single RunView call', async () => {
        const { provider, runView } = createMockProvider();

        const [first, second] = await Promise.all([
            ReadContractTypeByID(provider, ORDER_FORM_ID.toLowerCase()),
            ReadContractTypeByID(provider, ORDER_FORM_ID.toUpperCase()),
        ]);

        expect(runView).toHaveBeenCalledTimes(1);
        expect(first).toEqual(ORDER_FORM_ROW);
        expect(second).toEqual(ORDER_FORM_ROW);
    });

    it('requests both template-defaulting and renewal-defaulting columns in one projection', async () => {
        const { provider, runView } = createMockProvider();
        await ReadContractTypeByID(provider, ORDER_FORM_ID);

        const callArg = runView.mock.calls[0][0] as unknown as { Fields: string[] };
        expect(callArg.Fields).toEqual(
            expect.arrayContaining([
                'ID',
                'Name',
                'TemplateRequired',
                'ContractTemplateTypeID',
                'DefaultAutoRenew',
                'DefaultRenewalNoticeDays',
                'DefaultCancellationWindowDays',
                'DefaultAnnualIncreasePercent',
                'Status',
            ]),
        );
    });

    it('re-queries after InvalidateContractTypeCache is called for that typeID or provider', async () => {
        const { provider, runView } = createMockProvider();

        await ReadContractTypeByID(provider, ORDER_FORM_ID);
        expect(runView).toHaveBeenCalledTimes(1);

        InvalidateContractTypeCache(provider, ORDER_FORM_ID);
        await ReadContractTypeByID(provider, ORDER_FORM_ID);
        expect(runView).toHaveBeenCalledTimes(2);
    });

    it('evicts failed reads so a subsequent call retries instead of returning a poisoned promise', async () => {
        let attempts = 0;
        const { provider, runView } = createMockProvider(async () => {
            attempts += 1;
            if (attempts === 1) {
                return { Success: false, ErrorMessage: 'temporary failure' };
            }
            return { Success: true, Results: [ORDER_FORM_ROW] };
        });

        await expect(ReadContractTypeByID(provider, ORDER_FORM_ID)).rejects.toThrow('temporary failure');
        const recovered = await ReadContractTypeByID(provider, ORDER_FORM_ID);
        expect(recovered).toEqual(ORDER_FORM_ROW);
        expect(runView).toHaveBeenCalledTimes(2);
    });

    it('returns null without querying when typeID is blank or not a UUID', async () => {
        const { provider, runView } = createMockProvider();
        expect(await ReadContractTypeByID(provider, '')).toBeNull();
        expect(await ReadContractTypeByID(provider, null)).toBeNull();
        expect(await ReadContractTypeByID(provider, 'not-a-uuid')).toBeNull();
        expect(runView).not.toHaveBeenCalled();
    });

    it('isolates caches per provider instance', async () => {
        const a = createMockProvider();
        const b = createMockProvider();

        await ReadContractTypeByID(a.provider, SOW_ID);
        await ReadContractTypeByID(b.provider, SOW_ID);

        expect(a.runView).toHaveBeenCalledTimes(1);
        expect(b.runView).toHaveBeenCalledTimes(1);
    });

    it('serves a repeat read from cache inside the TTL and re-reads once it expires', async () => {
        vi.useFakeTimers();
        try {
            let noticeDays = 60;
            const { provider, runView } = createMockProvider(async () => ({
                Success: true,
                Results: [{ ...ORDER_FORM_ROW, DefaultRenewalNoticeDays: noticeDays }],
            }));

            expect((await ReadContractTypeByID(provider, ORDER_FORM_ID))?.DefaultRenewalNoticeDays).toBe(60);
            noticeDays = 90; // another session edits the type; this one never hears about it

            vi.advanceTimersByTime(CONTRACT_TYPE_CACHE_TTL_MS - 1);
            expect((await ReadContractTypeByID(provider, ORDER_FORM_ID))?.DefaultRenewalNoticeDays).toBe(60);
            expect(runView).toHaveBeenCalledTimes(1);

            vi.advanceTimersByTime(1);
            expect((await ReadContractTypeByID(provider, ORDER_FORM_ID))?.DefaultRenewalNoticeDays).toBe(90);
            expect(runView).toHaveBeenCalledTimes(2);
        } finally {
            vi.useRealTimers();
        }
    });
});
