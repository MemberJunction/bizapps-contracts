/**
 * Unit tests for `DescribeDeleteBlockers` batching in `delete-guard.ts`.
 *
 * Verifies that multi-dependency delete checks (e.g. `ContractEntityServer.Delete()` checking
 * 4 dependencies) batch all `count_only` queries into a single `RunViews` call instead of
 * issuing N sequential `RunView` round-trips, while preserving fail-closed error behavior and
 * falling back cleanly when a minimal provider stub lacks `RunViews`.
 */
import { describe, expect, it, vi } from 'vitest';
import type { BaseEntity, RunViewParams, RunViewResult } from '@memberjunction/core';
import { DescribeDeleteBlockers, type DeleteDependency } from '../delete-guard.js';

const DEPS: DeleteDependency[] = [
    {
        EntityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
        Filter: "ContractID = 'C-1'",
        Describe: (n) => `${n} modification(s)`,
    },
    {
        EntityName: 'MJ_BizApps_Contracts: Contract Orders',
        Filter: "ContractID = 'C-1'",
        Describe: (n) => `${n} order(s)`,
    },
    {
        EntityName: 'MJ_BizApps_Contracts: Contracts',
        Filter: "ParentContractID = 'C-1'",
        Describe: (n) => `${n} child(ren)`,
    },
];

describe('DescribeDeleteBlockers batching', () => {
    it('batches multiple dependency counts into a single RunViews call with ResultType: count_only', async () => {
        const runViews = vi.fn(
            async (params: RunViewParams[]): Promise<RunViewResult[]> =>
                params.map((_, i) => ({
                    Success: true,
                    TotalRowCount: i === 0 ? 2 : i === 2 ? 1 : 0,
                    RowCount: 0,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                    Results: [],
                })),
        );
        const runView = vi.fn();
        const entity = {
            ContextCurrentUser: { ID: 'U1' },
            RunViewProviderToUse: { RunViews: runViews, RunView: runView },
        } as unknown as BaseEntity;

        const message = await DescribeDeleteBlockers(entity, DEPS);

        expect(runViews).toHaveBeenCalledTimes(1);
        expect(runView).not.toHaveBeenCalled();
        const batchParams = runViews.mock.calls[0][0];
        expect(batchParams).toHaveLength(3);
        expect(batchParams.every((p) => p.ResultType === 'count_only')).toBe(true);
        expect(message).toBe('2 modification(s) 1 child(ren)');
    });

    it('returns null when every batched count is zero', async () => {
        const runViews = vi.fn(
            async (params: RunViewParams[]): Promise<RunViewResult[]> =>
                params.map(() => ({
                    Success: true,
                    TotalRowCount: 0,
                    RowCount: 0,
                    ExecutionTime: 1,
                    ErrorMessage: '',
                    Results: [],
                })),
        );
        const entity = {
            RunViewProviderToUse: { RunViews: runViews, RunView: vi.fn() },
        } as unknown as BaseEntity;

        await expect(DescribeDeleteBlockers(entity, DEPS)).resolves.toBeNull();
        expect(runViews).toHaveBeenCalledTimes(1);
    });

    it('throws (fails closed) when any batched dependency count fails', async () => {
        const runViews = vi.fn(async (): Promise<RunViewResult[]> => [
            { Success: true, TotalRowCount: 0, RowCount: 0, ExecutionTime: 1, ErrorMessage: '', Results: [] },
            { Success: false, TotalRowCount: 0, RowCount: 0, ExecutionTime: 1, ErrorMessage: 'db down', Results: [] },
            { Success: true, TotalRowCount: 0, RowCount: 0, ExecutionTime: 1, ErrorMessage: '', Results: [] },
        ]);
        const entity = {
            RunViewProviderToUse: { RunViews: runViews, RunView: vi.fn() },
        } as unknown as BaseEntity;

        await expect(DescribeDeleteBlockers(entity, DEPS)).rejects.toThrow(/db down/);
    });

    it('falls back to RunView when provider stub does not expose RunViews', async () => {
        const runView = vi.fn(async (): Promise<RunViewResult> => ({
            Success: true,
            TotalRowCount: 1,
            RowCount: 0,
            ExecutionTime: 1,
            ErrorMessage: '',
            Results: [],
        }));
        const entity = {
            RunViewProviderToUse: { RunView: runView },
        } as unknown as BaseEntity;

        const message = await DescribeDeleteBlockers(entity, DEPS.slice(0, 2));
        expect(runView).toHaveBeenCalledTimes(2);
        expect(message).toBe('1 modification(s) 1 order(s)');
    });
});
