/**
 * @fileoverview Server-side `ContractBillingSchedule` — the plan that decides when bills happen.
 *
 * THE RULE WORTH THE FILE: **a schedule that has already produced bills is frozen.**
 *
 * Changing a live schedule's type or frequency is not an edit, it is a retroactive re-plan. A term
 * billed quarterly for three quarters, switched to Monthly, now has a cadence whose history does not
 * match its rule — and every downstream answer to "why did the customer get this bill on this date"
 * is wrong from that moment on, including the ones already sent. `ContractBillingEvent` exists
 * precisely to answer that question; silently invalidating it is worse than refusing the edit.
 *
 * No CHECK can express this: it compares this row against the existence of rows in another table.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    RunView,
    ValidationErrorInfo,
    ValidationResult,
    type IRunViewProvider,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractBillingScheduleEntity } from '@mj-biz-apps/contracts-entities';

const SCHEDULE_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const EVENT_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Events';
const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';

/** The fields a schedule with billing history may no longer change. */
const FROZEN_FIELDS: readonly string[] = ['ScheduleType', 'Frequency', 'AnchorDate'];

@RegisterClass(BaseEntity, SCHEDULE_ENTITY)
export class ContractBillingScheduleEntityServer extends mjBizAppsContractsContractBillingScheduleEntity {
    /** Both cross-row rules below are reads; without this opt-in they would never run. */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkCadenceHasFrequency(result);
        return result;
    }

    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkNotFrozenByHistory(result);
        await this.checkAnchorWithinTerm(result);
        return result;
    }

    /**
     * `CK_ContractBillingSchedule_CadenceNeedsFrequency`, said readably. A cadence with no frequency
     * has nothing to iterate — the scheduled job would find it, be unable to compute a next date,
     * and produce nothing, forever, with no error anywhere.
     */
    private checkCadenceHasFrequency(result: ValidationResult): void {
        if (this.ScheduleType !== 'Cadence' || this.Frequency) return;
        this.fail(
            result,
            'Frequency',
            'A Cadence schedule needs a frequency — it is the thing the schedule iterates. Without one ' +
                'the billing job can never compute a next date, so the term would simply never bill and ' +
                'nothing would report an error.',
            this.Frequency,
        );
    }

    /**
     * Freeze the plan once it has produced bills.
     *
     * Only fires when a frozen field ACTUALLY changed — `IsActive` and `Notes` stay editable, because
     * stopping a schedule going forward is a legitimate operational act that rewrites nothing.
     */
    private async checkNotFrozenByHistory(result: ValidationResult): Promise<void> {
        if (!this.IsSaved) return;

        const changed = FROZEN_FIELDS.filter((name) => {
            const field = this.Fields.find((f) => f.Name === name);
            return field ? field.Dirty : false;
        });
        if (changed.length === 0) return;

        const generated = await this.countGeneratedEvents();
        if (generated === 0) return;

        this.fail(
            result,
            changed[0],
            `This schedule has already produced ${generated} bill${generated === 1 ? '' : 's'}, so its ` +
                `${changed.join(' and ')} can no longer change — the bills already sent were generated under ` +
                'the current plan, and changing it now would make the billing history unexplainable. To bill ' +
                'differently from here, deactivate this schedule and add a new one.',
            null,
        );
    }

    /** How many bills this schedule has actually generated. */
    private async countGeneratedEvents(): Promise<number> {
        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ID: string }>(
            {
                EntityName: EVENT_ENTITY,
                Fields: ['ID'],
                ExtraFilter: `ContractBillingScheduleID='${this.ID}' AND Status='Generated'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not check this schedule's billing history: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        return res.Results?.length ?? 0;
    }

    /**
     * An anchor outside the term dates produces a first billing date the term does not cover.
     * A null anchor means "anchor on the term's start", which is what the schedule builder does.
     */
    private async checkAnchorWithinTerm(result: ValidationResult): Promise<void> {
        const anchor = ContractBillingScheduleEntityServer.asDate(this.AnchorDate);
        if (!anchor || !this.ContractTermID) return;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ StartDate: Date | string; EndDate: Date | string; TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['StartDate', 'EndDate', 'TermNumber'],
                ExtraFilter: `ID='${this.ContractTermID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not read this schedule's term: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const term = res.Results?.[0];
        if (!term) return;

        const start = ContractBillingScheduleEntityServer.asDate(term.StartDate);
        const end = ContractBillingScheduleEntityServer.asDate(term.EndDate);
        if (!start || !end) return;
        if (anchor.getTime() >= start.getTime() && anchor.getTime() <= end.getTime()) return;

        this.fail(
            result,
            'AnchorDate',
            `The billing anchor ${ContractBillingScheduleEntityServer.iso(anchor)} falls outside term ` +
                `${term.TermNumber} (${ContractBillingScheduleEntityServer.iso(start)} to ` +
                `${ContractBillingScheduleEntityServer.iso(end)}). The cadence would compute its first ` +
                'billing date in a period the term does not cover.',
            this.AnchorDate,
        );
    }

    private fail(result: ValidationResult, field: string, message: string, value: unknown): void {
        result.Success = false;
        result.Errors.push(new ValidationErrorInfo(field, message, value));
    }

    private static asDate(value: Date | string | null | undefined): Date | null {
        if (!value) return null;
        const d = value instanceof Date ? value : new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    private static iso(d: Date): string {
        return d.toISOString().slice(0, 10);
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractBillingScheduleEntityServer(): void {
    /* intentionally empty */
}
