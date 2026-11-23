/**
 * @fileoverview Unit tests for the contract-counts batching module and its caller wiring.
 */
import { readFile } from 'node:fs/promises';
import { describe, expect, it, vi } from 'vitest';
import type { RunViewParams, RunViewResult } from '@memberjunction/core';
import { MJC_ENTITIES } from '../entity-names';
import {
    BuildContractCountParams,
    RunContractCounts,
    type ContractCountQuery,
    type ContractCountRunner,
} from '../contract-counts';

describe('contract-counts helper module', () => {
    describe('BuildContractCountParams', () => {
        it('sets ResultType: count_only and EntityName: MJC_ENTITIES.Contract, never MaxRows: 1', () => {
            const queries: ContractCountQuery[] = [
                { Key: 'active', ExtraFilter: "State = 'Active'", Label: 'Active' },
                { Key: 'draft', ExtraFilter: "State = 'Draft'", Label: 'Draft' },
            ];
            const params = BuildContractCountParams(queries);

            expect(params).toHaveLength(2);
            for (let i = 0; i < queries.length; i++) {
                expect(params[i].EntityName).toBe(MJC_ENTITIES.Contract);
                expect(params[i].ExtraFilter).toBe(queries[i].ExtraFilter);
                expect(params[i].ResultType).toBe('count_only');
                expect(params[i].MaxRows).toBeUndefined();
            }
        });
    });

    describe('RunContractCounts', () => {
        it('returns empty counts and failed labels without calling runner when query list is empty', async () => {
            const runViews = vi.fn<(params: RunViewParams[]) => Promise<RunViewResult[]>>();
            const runView = vi.fn<(params: RunViewParams) => Promise<RunViewResult>>();
            const runner: ContractCountRunner = { RunViews: runViews, RunView: runView };

            const result = await RunContractCounts(runner, []);
            expect(result).toEqual({ Counts: {}, FailedLabels: [] });
            expect(runViews).not.toHaveBeenCalled();
            expect(runView).not.toHaveBeenCalled();
        });

        it('batches multiple queries into a single RunViews call and maps TotalRowCount by Key', async () => {
            const runViews = vi.fn<(params: RunViewParams[]) => Promise<RunViewResult[]>>().mockResolvedValue([
                { Success: true, TotalRowCount: 42, RowCount: 0, ExecutionTime: 10, ErrorMessage: '', Results: [] },
                { Success: true, TotalRowCount: 0, RowCount: 0, ExecutionTime: 12, ErrorMessage: '', Results: [] },
            ]);
            const runView = vi.fn<(params: RunViewParams) => Promise<RunViewResult>>();
            const runner: ContractCountRunner = { RunViews: runViews, RunView: runView };

            const queries: ContractCountQuery[] = [
                { Key: 'q1', ExtraFilter: 'Filter 1', Label: 'Query 1' },
                { Key: 'q2', ExtraFilter: 'Filter 2', Label: 'Query 2' },
            ];

            const result = await RunContractCounts(runner, queries);
            expect(runViews).toHaveBeenCalledTimes(1);
            expect(runView).not.toHaveBeenCalled();
            expect(result.Counts).toEqual({ q1: 42, q2: 0 });
            expect(result.FailedLabels).toEqual([]);
        });

        it('records null count and pushes FailedLabels when individual result has Success: false or missing TotalRowCount', async () => {
            const runViews = vi.fn<(params: RunViewParams[]) => Promise<RunViewResult[]>>().mockResolvedValue([
                { Success: true, TotalRowCount: 15, RowCount: 0, ExecutionTime: 10, ErrorMessage: '', Results: [] },
                { Success: false, TotalRowCount: 0, RowCount: 0, ExecutionTime: 12, ErrorMessage: 'Query failed', Results: [] },
            ]);
            const runView = vi.fn<(params: RunViewParams) => Promise<RunViewResult>>();
            const runner: ContractCountRunner = { RunViews: runViews, RunView: runView };

            const queries: ContractCountQuery[] = [
                { Key: 'ok', ExtraFilter: 'F1', Label: 'OK query' },
                { Key: 'bad', ExtraFilter: 'F2', Label: 'Bad query' },
            ];

            const result = await RunContractCounts(runner, queries);
            expect(runViews).toHaveBeenCalledTimes(1);
            expect(result.Counts).toEqual({ ok: 15, bad: null });
            expect(result.FailedLabels).toEqual(['Bad query']);
        });

        it('records null counts and FailedLabels for all queries when RunViews throws', async () => {
            const runViews = vi.fn<(params: RunViewParams[]) => Promise<RunViewResult[]>>().mockRejectedValue(new Error('Network error'));
            const runView = vi.fn<(params: RunViewParams) => Promise<RunViewResult>>();
            const runner: ContractCountRunner = { RunViews: runViews, RunView: runView };

            const queries: ContractCountQuery[] = [
                { Key: 'q1', ExtraFilter: 'F1', Label: 'First' },
                { Key: 'q2', ExtraFilter: 'F2' },
            ];

            const result = await RunContractCounts(runner, queries);
            expect(runViews).toHaveBeenCalledTimes(1);
            expect(result.Counts).toEqual({ q1: null, q2: null });
            expect(result.FailedLabels).toEqual(['First', 'q2']);
        });

        it('falls back to individual RunView calls when RunViews is undefined on the runner', async () => {
            const runView = vi.fn<(params: RunViewParams) => Promise<RunViewResult>>().mockImplementation(async (params) => {
                if (params.ExtraFilter === 'F1') {
                    return { Success: true, TotalRowCount: 7, RowCount: 0, ExecutionTime: 5, ErrorMessage: '', Results: [] };
                }
                throw new Error('RunView error');
            });
            const runner: ContractCountRunner = { RunView: runView };

            const queries: ContractCountQuery[] = [
                { Key: 'q1', ExtraFilter: 'F1', Label: 'First' },
                { Key: 'q2', ExtraFilter: 'F2', Label: 'Second' },
            ];

            const result = await RunContractCounts(runner, queries);
            expect(runView).toHaveBeenCalledTimes(2);
            expect(result.Counts).toEqual({ q1: 7, q2: null });
            expect(result.FailedLabels).toEqual(['Second']);
        });
    });

    describe('source wiring verification', () => {
        it('verifies contract-grid.page.ts delegates to RunContractCounts and does not use MaxRows: 1', async () => {
            const source = await readSourceFile('../../pages/contract-grid.page.ts');
            expect(source).toContain('RunContractCounts(');
            expect(source).not.toContain('MaxRows: 1');
            expect(source).toContain('void this.refreshCounts([openTaskPill]);');
        });

        it('verifies contracts-sections.component.ts delegates to RunContractCounts and does not use MaxRows: 1', async () => {
            const source = await readSourceFile('../../sections/contracts-sections.component.ts');
            expect(source).toContain('RunContractCounts(');
            expect(source).not.toContain('MaxRows: 1');
        });

        it('verifies contracts-dashboard.page.ts delegates to RunContractCounts and does not use MaxRows: 1', async () => {
            const source = await readSourceFile('../../pages/contracts-dashboard.page.ts');
            expect(source).toContain('RunContractCounts(');
            expect(source).not.toContain('MaxRows: 1');
        });
    });
});

async function readSourceFile(relativePath: string): Promise<string> {
    return readFile(new URL(relativePath, import.meta.url), 'utf8');
}
