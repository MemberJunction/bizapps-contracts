/**
 * @fileoverview `Contracts.ActivateTerm` — bring a term to life and give it a billing schedule.
 *
 * WHY A REMOTE OPERATION AND NOT AN ACTION. Orders settled this and we follow it: state changes that
 * WRITE are remote operations — the API the UI calls — while Actions are for agent/workflow-invocable
 * work that generally does not mutate. (Orders' own action category says so in as many words.) The
 * master plan §10.5 called these Actions; that is superseded here by the family convention.
 *
 * WHAT ACTIVATION MEANS. A `Pending` term is a promise; an `Active` term is a thing that bills. So
 * activation is not a status flip — it is the moment the term acquires the machinery that produces
 * money: a `ContractBillingSchedule` and the `ContractBillingEvent` rows its cadence implies. Doing
 * the flip without the schedule yields an Active term that silently bills nothing, which is the
 * failure nobody notices until a quarter closes light.
 *
 * ALL-OR-NONE. One transaction covers the status change, the schedule and every event. A partial
 * activation — status moved, events missing — is exactly the state that is hardest to detect and
 * worst to inherit.
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
    mjBizAppsContractsContractBillingScheduleEntity,
    mjBizAppsContractsContractBillingEventEntity,
    mjBizAppsContractsContractEventEntity,
} from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_SCHEDULE = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const E_EVENT = 'MJ_BizApps_Contracts: Contract Billing Events';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';

export interface ActivateTermInput {
    ContractTermID: string;
    /** Skip schedule creation when the caller has already built one deliberately. */
    SkipSchedule?: boolean;
}

export interface ActivateTermOutput {
    Success: boolean;
    Message?: string;
    ContractTermID?: string;
    BillingScheduleID?: string;
    /** Scheduled dates created, in order — the caller can show exactly what will bill and when. */
    ScheduledDates?: string[];
}

/** Months between occurrences. `Milestone` and `Custom` produce no cadence — a human places those. */
const CADENCE_MONTHS: Readonly<Record<string, number | null>> = {
    Monthly: 1,
    Quarterly: 3,
    SemiAnnual: 6,
    Annual: 12,
    Milestone: null,
    Custom: null,
};

@RegisterClass(BaseRemotableOperation, 'Contracts.ActivateTerm')
export class ActivateTermOperation extends BaseRemotableOperation<ActivateTermInput, ActivateTermOutput> {
    public OperationKey = 'Contracts.ActivateTerm';

    protected async InternalExecute(
        input: ActivateTermInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<ActivateTermOutput> {
        if (!input?.ContractTermID) {
            return { Success: false, Message: 'ContractTermID is required.' };
        }
        if (!/^[0-9a-f-]{36}$/i.test(input.ContractTermID)) {
            return { Success: false, Message: 'ContractTermID is not a valid identifier.' };
        }

        const md = new Metadata();
        const term = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        if (!(await term.Load(input.ContractTermID))) {
            return { Success: false, Message: `Contract term ${input.ContractTermID} was not found.` };
        }

        const current = term.Status as unknown as string;
        if (current === 'Active') {
            return { Success: false, Message: `Term ${term.TermNumber} is already Active.` };
        }
        if (current === 'Completed' || current === 'Terminated') {
            return { Success: false, Message: `Term ${term.TermNumber} is ${current} and cannot be activated.` };
        }

        // Refuse a term that cannot bill, BEFORE opening a transaction. An Active term with no
        // coverage is the same silent nothing as an Active term with no schedule.
        const rv = new RunView(provider as unknown as IRunViewProvider);
        const lines = await rv.RunView<{ ID: string }>(
            { EntityName: 'MJ_BizApps_Contracts: Contract Lines', Fields: ['ID'], ExtraFilter: `ContractTermID='${term.ID}'`, ResultType: 'simple' },
            user,
        );
        if (!lines?.Success) {
            return { Success: false, Message: `Could not read the term's coverage: ${lines?.ErrorMessage ?? 'unknown error'}` };
        }
        if ((lines.Results?.length ?? 0) === 0) {
            return { Success: false, Message: `Term ${term.TermNumber} covers nothing — add at least one contract line before activating it.` };
        }

        const db = provider as unknown as DatabaseProviderBase;
        const dates: string[] = [];
        let scheduleID: string | undefined;

        try {
            await db.BeginTransaction();

            term.Status = 'Active';
            if (!(await term.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Message: `Could not activate the term: ${term.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            if (!input.SkipSchedule) {
                const frequency = (term.BillingFrequency as unknown as string) ?? 'Annual';
                const months = CADENCE_MONTHS[frequency] ?? null;

                const schedule = await md.GetEntityObject<mjBizAppsContractsContractBillingScheduleEntity>(E_SCHEDULE, user);
                schedule.NewRecord();
                schedule.ContractTermID = term.ID;
                schedule.ScheduleType = months === null ? 'Milestone' : 'Cadence';
                schedule.Frequency = frequency as typeof schedule.Frequency;
                // THE ANCHOR THE TERM NEGOTIATED, when it names one.
                //
                // `BillingAnchorMonth` / `BillingAnchorDay` existed on the term, were copied forward
                // by RenewTerm, and were read by NOTHING — the schedule always anchored on the start
                // date. So a contract that says "bills on the 1st of the quarter" was recorded
                // faithfully and then billed on whatever day it happened to start. Two dead columns
                // and a silently ignored provision.
                schedule.AnchorDate = anchorFor(term);
                schedule.IsActive = true;
                if (!(await schedule.Save())) {
                    await db.RollbackTransaction();
                    return { Success: false, Message: `Could not create the billing schedule: ${schedule.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                }
                scheduleID = schedule.ID;

                // A milestone schedule gets no dates: milestones are reached, not calculated. Creating
                // guesses here would put dates in front of a human that nobody agreed to.
                for (const when of months === null ? [] : occurrences(anchorFor(term), term.StartDate, term.EndDate, months)) {
                    const ev = await md.GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_EVENT, user);
                    ev.NewRecord();
                    ev.ContractBillingScheduleID = schedule.ID;
                    ev.ContractTermID = term.ID;
                    ev.ScheduledDate = when;
                    ev.Status = 'Scheduled';
                    if (!(await ev.Save())) {
                        await db.RollbackTransaction();
                        return { Success: false, Message: `Could not create a billing event: ${ev.LatestResult?.CompleteMessage ?? 'unknown error'}` };
                    }
                    dates.push(when.toISOString().slice(0, 10));
                }
            }

            // A CONTRACT WHOSE TERM IS LIVE IS A LIVE CONTRACT. Without this the roster shows "Draft"
            // for an agreement that is actively billing — the same class of lie as a Terminated
            // contract whose schedule still runs, and just as invisible. Only Draft and
            // PendingSignature are promoted: Expired, Terminated and Superseded are deliberate states
            // that activating a term must not quietly undo.
            const contract = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
            if (await contract.Load(term.ContractID)) {
                const status = contract.Status as unknown as string;
                if (status === 'Draft' || status === 'PendingSignature') {
                    contract.Status = 'Active';
                    if (!(await contract.Save())) {
                        await db.RollbackTransaction();
                        return {
                            Success: false,
                            Message: `Could not bring the contract live: ${contract.LatestResult?.CompleteMessage ?? 'unknown error'}`,
                        };
                    }
                }
            }

            const log = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
            log.NewRecord();
            log.ContractID = term.ContractID;
            log.ContractTermID = term.ID;
            log.EventType = 'TermActivated';
            log.EventDate = new Date();
            log.PerformedByUserID = user.ID;
            log.Payload = JSON.stringify({ termNumber: term.TermNumber, scheduleID, occurrences: dates.length });
            if (!(await log.Save())) {
                await db.RollbackTransaction();
                return { Success: false, Message: `Could not write the lifecycle event: ${log.LatestResult?.CompleteMessage ?? 'unknown error'}` };
            }

            await db.CommitTransaction();
            return {
                Success: true,
                Message: `Term ${term.TermNumber} is Active with ${dates.length} scheduled billing event(s).`,
                ContractTermID: term.ID,
                BillingScheduleID: scheduleID,
                ScheduledDates: dates,
            };
        } catch (e) {
            await db.RollbackTransaction();
            return { Success: false, Message: `Activation failed and was rolled back: ${e instanceof Error ? e.message : String(e)}` };
        }
    }
}

/**
 * The date the cadence is anchored on: what the TERM negotiated, or its start date.
 *
 * `BillingAnchorDay` alone means "this day of every period, starting in the term's first month" —
 * the common case, e.g. bills on the 1st. `BillingAnchorMonth` as well pins the first occurrence to
 * a specific month, which is how an annual term that always bills in January is expressed however
 * mid-year it was signed.
 *
 * NEVER BEFORE THE TERM STARTS. An anchor that resolves earlier than the start date is pulled
 * forward by whole cadence steps until it is inside the term — otherwise a January anchor on a term
 * starting in March would schedule its first bill for a period the agreement does not cover.
 */
function anchorFor(term: mjBizAppsContractsContractTermEntity): Date {
    const start = term.StartDate;
    const day = term.BillingAnchorDay;
    const month = term.BillingAnchorMonth;
    if (!day && !month) return start;

    const year = start.getUTCFullYear();
    const targetMonth = month ? month - 1 : start.getUTCMonth();
    const lastOfMonth = new Date(Date.UTC(year, targetMonth + 1, 0)).getUTCDate();
    const targetDay = Math.min(day ?? start.getUTCDate(), lastOfMonth);

    const anchor = new Date(Date.UTC(year, targetMonth, targetDay));
    if (anchor.getTime() >= start.getTime()) return anchor;

    // Before the term began: step forward a year for a month-pinned anchor, a month otherwise.
    const stepped = new Date(anchor);
    if (month) stepped.setUTCFullYear(stepped.getUTCFullYear() + 1);
    else stepped.setUTCMonth(stepped.getUTCMonth() + 1);
    const steppedLast = new Date(Date.UTC(stepped.getUTCFullYear(), stepped.getUTCMonth() + 1, 0)).getUTCDate();
    stepped.setUTCDate(Math.min(day ?? start.getUTCDate(), steppedLast));
    return stepped;
}

/**
 * Every occurrence from `anchor` up to and including any that falls on or before `end`.
 *
 * Stepped in whole months from the anchor, so a schedule anchored on the 31st bills on the 30th/28th
 * where the month is short rather than skipping to the next month — `setMonth` rolling over is the
 * classic way a quarterly schedule quietly loses a quarter.
 *
 * `start` is carried separately from `anchor` because they differ once a term names its own anchor:
 * nothing may be scheduled before the term begins, even when the anchor computation lands there.
 */
function occurrences(anchor: Date, start: Date, end: Date, months: number): Date[] {
    const out: Date[] = [];
    const anchorDay = anchor.getUTCDate();
    for (let i = 0; ; i++) {
        const d = new Date(Date.UTC(anchor.getUTCFullYear(), anchor.getUTCMonth() + i * months, 1));
        const lastOfMonth = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
        d.setUTCDate(Math.min(anchorDay, lastOfMonth));
        if (d.getTime() > end.getTime()) break;
        if (d.getTime() >= start.getTime()) out.push(d);
        if (out.length > 400) break; // guard against a pathological range
    }
    return out;
}

/** Tree-shaking anchor. */
export function LoadActivateTermOperation(): void {
    /* intentionally empty */
}
