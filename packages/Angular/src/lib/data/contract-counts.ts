/**
 * @fileoverview Pure, provider-scoped count batching helper module.
 *
 * Batches contract filter-pill, section-badge, and dashboard-tile count queries into a single
 * `RunViews` call with `ResultType: 'count_only'` (instead of per-query `MaxRows: 1` loops that
 * ran N separate GraphQL requests and 2N SQL queries).
 *
 * @module @mj-biz-apps/contracts-ng
 */
import type { RunViewParams, RunViewResult } from '@memberjunction/core';
import { MJC_ENTITIES } from './entity-names';

export interface ContractCountRunner {
    RunViews?: (params: RunViewParams[]) => Promise<RunViewResult[]>;
    RunView: (params: RunViewParams) => Promise<RunViewResult>;
}

export interface ContractCountQuery {
    /** Caller-assigned key (e.g. pill Id, badge key, or tile metric key). */
    Key: string;
    /** SQL ExtraFilter expression for `MJ_BizApps_Contracts: Contracts`. */
    ExtraFilter: string;
    /** Human-readable label for failure reporting (optional). */
    Label?: string;
}

export interface ContractCountBatchResult {
    /** Map from `Key` to resolved row count (`null` when that count failed). */
    Counts: Record<string, number | null>;
    /** Labels (or Keys) of queries that failed (`!Success` or threw). */
    FailedLabels: string[];
}

/**
 * Builds `RunViewParams` with `ResultType: 'count_only'` for each query.
 */
export function BuildContractCountParams(queries: readonly ContractCountQuery[]): RunViewParams[] {
    return queries.map((q) => ({
        EntityName: MJC_ENTITIES.Contract,
        ExtraFilter: q.ExtraFilter,
        ResultType: 'count_only',
    }));
}

/**
 * Executes a batch of contract count queries using `RunViews` where available,
 * falling back to individual `RunView` calls.
 */
export async function RunContractCounts(
    rv: ContractCountRunner,
    queries: readonly ContractCountQuery[],
): Promise<ContractCountBatchResult> {
    if (queries.length === 0) {
        return { Counts: {}, FailedLabels: [] };
    }

    const Counts: Record<string, number | null> = {};
    const FailedLabels: string[] = [];
    const params = BuildContractCountParams(queries);

    if (typeof rv.RunViews === 'function') {
        try {
            const results = await rv.RunViews(params);
            for (let i = 0; i < queries.length; i++) {
                const q = queries[i];
                const r = results?.[i];
                if (r && r.Success !== false && typeof r.TotalRowCount === 'number') {
                    Counts[q.Key] = r.TotalRowCount;
                } else if (r && r.Success !== false && r.TotalRowCount == null) {
                    Counts[q.Key] = 0;
                } else {
                    Counts[q.Key] = null;
                    FailedLabels.push(q.Label ?? q.Key);
                }
            }
        } catch {
            for (const q of queries) {
                Counts[q.Key] = null;
                FailedLabels.push(q.Label ?? q.Key);
            }
        }
        return { Counts, FailedLabels };
    }

    // Fallback when typeof rv.RunViews !== 'function'
    const singleResults = await Promise.all(
        queries.map(async (q, i) => {
            try {
                return await rv.RunView(params[i]);
            } catch {
                return null;
            }
        }),
    );

    for (let i = 0; i < queries.length; i++) {
        const q = queries[i];
        const r = singleResults[i];
        if (r && r.Success !== false && typeof r.TotalRowCount === 'number') {
            Counts[q.Key] = r.TotalRowCount;
        } else if (r && r.Success !== false && r.TotalRowCount == null) {
            Counts[q.Key] = 0;
        } else {
            Counts[q.Key] = null;
            FailedLabels.push(q.Label ?? q.Key);
        }
    }

    return { Counts, FailedLabels };
}
