/**
 * @fileoverview `Contracts.SweepRenewalTerms` — the daily copy of every linked contract's renewal terms
 * to its orders' subscriptions (issue #77).
 *
 * Calls the sweep, reports tallies as outputs, never throws at the caller. A subscription that refused
 * the terms makes the run fail, so the job log shows it rather than a green night.
 *
 * @module @mj-biz-apps/contracts-server
 */
import { BaseAction } from '@memberjunction/actions';
import type { ActionParam, ActionResultSimple, RunActionParams } from '@memberjunction/actions-base';
import { Metadata, RunView } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { SweepContractRenewalTerms, type RenewalTermsSweepOutcome } from '@mj-biz-apps/contracts-core-entities-server';

function setOutput(params: RunActionParams, name: string, value: unknown): void {
    const existing = params.Params?.find((p) => p.Name?.toLowerCase() === name.toLowerCase());
    if (existing) {
        existing.Value = value;
        return;
    }
    params.Params = params.Params ?? [];
    params.Params.push({ Name: name, Value: value, Type: 'Output' } as ActionParam);
}

function describe(sweep: RenewalTermsSweepOutcome): string {
    const tallies =
        `Checked ${sweep.Contracts} linked contract(s): ${sweep.Updated} subscription(s) updated, ` +
        `${sweep.Unchanged} already current, ${sweep.Failed.length} not updated.`;
    return sweep.Failed.length
        ? `${tallies} ${sweep.Failed.map((f) => `${f.ContractNumber} / ${f.SubscriptionNumber}: ${f.Message}`).join(' | ')}`
        : tallies;
}

@RegisterClass(BaseAction, 'Contracts.SweepRenewalTerms')
export class SweepRenewalTermsAction extends BaseAction {
    protected async InternalRunAction(params: RunActionParams): Promise<ActionResultSimple> {
        try {
            const sweep = await SweepContractRenewalTerms(RunView.FromMetadataProvider(Metadata.Provider), params.ContextUser);
            setOutput(params, 'Contracts', sweep.Contracts);
            setOutput(params, 'Updated', sweep.Updated);
            setOutput(params, 'Unchanged', sweep.Unchanged);
            setOutput(params, 'Failed', JSON.stringify(sweep.Failed));
            return {
                Success: sweep.Failed.length === 0,
                ResultCode: sweep.Failed.length === 0 ? 'SUCCESS' : 'PARTIAL',
                Message: describe(sweep),
            };
        } catch (error) {
            return {
                Success: false,
                ResultCode: 'ERROR',
                Message: `The renewal terms sweep failed: ${error instanceof Error ? error.message : String(error)}`,
            };
        }
    }
}

/** Anti-tree-shaking anchor — `@RegisterClass` is a side effect of import. */
export function LoadSweepRenewalTermsAction(): void {
    void SweepRenewalTermsAction;
}
