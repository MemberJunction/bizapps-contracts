/**
 * @fileoverview `Contracts.TerminateContract` — end an agreement and stop it from billing.
 *
 * TERMINATION IS NOT A STATUS FLIP. The status is the smallest part of it. What actually matters is
 * that every future `ContractBillingEvent` stops: a contract marked Terminated whose scheduled events
 * are still `Scheduled` will keep generating invoices, and it will do so quietly, because everything
 * downstream reads the schedule rather than the contract's status. That is the failure this operation
 * exists to prevent, and it is the reason termination cannot be a checkbox on a form.
 *
 * WHAT IS CANCELLED AND WHAT IS NOT. Events on or before the effective date are LEFT ALONE — they are
 * work already covered, and a customer still owes for the period they used. Only events after the
 * effective date are cancelled. Events already `Generated` or `Invoiced` are never touched by status:
 * money that has left the building is not un-billed by a state change here.
 *
 * ONE TRANSACTION, because a half-terminated contract — status changed, events still live — is
 * indistinguishable from a healthy one until somebody gets an invoice they should not have.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseRemotableOperation,
    type DatabaseProviderBase,
    type IMetadataProvider,
    type IRunViewProvider,
    Metadata,
    RunView,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type {
    mjBizAppsContractsContractEntity,
    mjBizAppsContractsContractTermEntity,
    mjBizAppsContractsContractBillingEventEntity,
    mjBizAppsContractsContractEventEntity,
} from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_BILLING_EVENT = 'MJ_BizApps_Contracts: Contract Billing Events';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';

export interface TerminateContractInput {
    ContractID: string;
    /** Why. Recorded on the lifecycle event — a termination with no stated reason is a future argument. */
    Reason: string;
    /** Defaults to today. Billing on or before this date stands; after it is cancelled. */
    EffectiveDate?: string;
    /** Compute and report, write nothing. */
    PreviewOnly?: boolean;
}

export interface TerminateContractOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    ContractID?: string;
    EffectiveDate?: string;
    /** Terms moved to Terminated. */
    TermsTerminated?: number;
    /** Future scheduled billing events cancelled. */
    BillingEventsCancelled?: number;
    /** Events left standing because they fall on or before the effective date, or already billed. */
    BillingEventsRetained?: number;
}

@RegisterClass(BaseRemotableOperation, 'Contracts.TerminateContract')
export class TerminateContractOperation extends BaseRemotableOperation<TerminateContractInput, TerminateContractOutput> {
    public OperationKey = 'Contracts.TerminateContract';

    protected async InternalExecute(
        input: TerminateContractInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<TerminateContractOutput> {
        const preview = input?.PreviewOnly === true;

        if (!input?.ContractID || !/^[0-9a-f-]{36}$/i.test(input.ContractID)) {
            return { Success: false, Preview: preview, Message: 'A valid ContractID is required.' };
        }
        if (!input.Reason || !input.Reason.trim()) {
            return { Success: false, Preview: preview, Message: 'A reason is required to terminate a contract.' };
        }

        const effective = input.EffectiveDate ? new Date(`${input.EffectiveDate.slice(0, 10)}T00:00:00.000Z`) : todayUTC();
        if (Number.isNaN(effective.getTime())) {
            return { Success: false, Preview: preview, Message: `EffectiveDate "${input.EffectiveDate}" is not a valid date.` };
        }

        const md = new Metadata();
        const contract = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
        if (!(await contract.Load(input.ContractID))) {
            return { Success: false, Preview: preview, Message: `Contract ${input.ContractID} was not found.` };
        }
        const status = contract.Status as unknown as string;
        if (status === 'Terminated') {
            return { Success: false, Preview: preview, Message: `${contract.ContractNumber} is already Terminated.` };
        }
        if (status === 'Superseded') {
            return {
                Success: false,
                Preview: preview,
                Message: `${contract.ContractNumber} was superseded by a replacement contract — terminate the successor instead.`,
            };
        }

        const rv = new RunView(provider as unknown as IRunViewProvider);

        // LIVE terms only. A `Completed` term already ran its full course — terminating it would be
        // both false (it was not cut short) and impossible (`Completed` is terminal, so the move is
        // refused and the whole transaction rolls back). Only a term that is still running, or has
        // not started yet, can be ended early.
        const terms = await rv.RunView<mjBizAppsContractsContractTermEntity>(
            {
                EntityName: E_TERM,
                ExtraFilter: `ContractID='${contract.ID}' AND Status IN ('Pending','PendingSignature','Active')`,
                ResultType: 'entity_object',
            },
            user,
        );
        if (!terms?.Success) {
            return { Success: false, Preview: preview, Message: `Could not read the contract's terms: ${terms?.ErrorMessage ?? 'unknown error'}` };
        }
        // Zero live terms is NOT an error: a contract whose term has run out but has not renewed is
        // exactly the "we are not renewing — close it" case. The contract still moves to Terminated;
        // there is simply no term or schedule work to do.
        const liveTerms = (terms.Results ?? []) as mjBizAppsContractsContractTermEntity[];

        // Scheduled events only. `Generated` / `Invoiced` are money already in flight and are not
        // rewritten by a status change here — reversing those is an accounting act, not a contract one.
        const events = liveTerms.length
            ? await rv.RunView<mjBizAppsContractsContractBillingEventEntity>(
                  {
                      EntityName: E_BILLING_EVENT,
                      ExtraFilter: `Status='Scheduled' AND ContractTermID IN (${liveTerms.map((t) => `'${t.ID}'`).join(',')})`,
                      ResultType: 'entity_object',
                  },
                  user,
              )
            : { Success: true, Results: [] as mjBizAppsContractsContractBillingEventEntity[], ErrorMessage: '' };
        if (!events?.Success) {
            return { Success: false, Preview: preview, Message: `Could not read the billing schedule: ${events?.ErrorMessage ?? 'unknown error'}` };
        }
        const scheduled = (events.Results ?? []) as mjBizAppsContractsContractBillingEventEntity[];
        const toCancel = scheduled.filter((e) => e.ScheduledDate && e.ScheduledDate.getTime() > effective.getTime());
        const retained = scheduled.length - toCancel.length;

        const summary =
            `${contract.ContractNumber} effective ${fmt(effective)}: ` +
            `${liveTerms.length} term(s) terminated, ${toCancel.length} future billing event(s) cancelled` +
            (retained ? `, ${retained} on-or-before the effective date left standing` : '');

        if (preview) {
            return {
                Success: true,
                Preview: true,
                Message: `Preview — ${summary}. Nothing was written.`,
                ContractID: contract.ID,
                EffectiveDate: fmt(effective),
                TermsTerminated: liveTerms.length,
                BillingEventsCancelled: toCancel.length,
                BillingEventsRetained: retained,
            };
        }

        const db = provider as unknown as DatabaseProviderBase;
        try {
            await db.BeginTransaction();

            // Events first: if anything below fails, we roll back anyway, but ordering this way means
            // the billing stop is the first thing established rather than the last.
            for (const e of toCancel) {
                e.Status = 'Cancelled';
                if (!(await e.Save())) {
                    await db.RollbackTransaction();
                    return { Success: false, Preview: false, Message: `Could not cancel a scheduled billing event: ${e.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                }
            }

            for (const t of liveTerms) {
                t.Status = 'Terminated';
                // The date the term actually stopped. `Contract` carries the POLICY
                // (TerminationPolicy / CancellationWindowDays); the term carries the EVENT, which is
                // why the effective date lands here and the reason lands on the lifecycle log.
                t.EarlyTerminationDate = effective;
                if (!(await t.Save())) {
                    await db.RollbackTransaction();
                    return { Success: false, Preview: false, Message: `Could not terminate term ${t.TermNumber}: ${t.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                }
            }

            contract.Status = 'Terminated';
            if (!(await contract.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Preview: false, Message: `Could not terminate the contract: ${contract.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            const log = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
            log.NewRecord();
            log.ContractID = contract.ID;
            log.EventType = 'Terminated';
            log.EventDate = new Date();
            log.PerformedByUserID = user.ID;
            log.Payload = JSON.stringify({
                reason: input.Reason.trim(),
                effectiveDate: fmt(effective),
                termsTerminated: liveTerms.length,
                billingEventsCancelled: toCancel.length,
                billingEventsRetained: retained,
            });
            if (!(await log.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Preview: false, Message: `Could not write the lifecycle event: ${log.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            await db.CommitTransaction();
            return {
                Success: true,
                Preview: false,
                Message: `Terminated — ${summary}.`,
                ContractID: contract.ID,
                EffectiveDate: fmt(effective),
                TermsTerminated: liveTerms.length,
                BillingEventsCancelled: toCancel.length,
                BillingEventsRetained: retained,
            };
        } catch (e) {
            await db.RollbackTransaction();
            return { Success: false, Preview: false, Message: `Termination failed and was rolled back: ${e instanceof Error ? e.message : String(e)}` };
        }
    }
}

function todayUTC(): Date {
    const now = new Date();
    return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
}

function fmt(d: Date): string {
    return d.toISOString().slice(0, 10);
}

/** Tree-shaking anchor. */
export function LoadTerminateContractOperation(): void {
    /* intentionally empty */
}
