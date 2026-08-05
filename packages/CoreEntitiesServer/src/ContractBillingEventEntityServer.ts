/**
 * @fileoverview Server-side `ContractBillingEvent` — keeps an event and its schedule on the same term.
 *
 * THE GAP (X.11). A billing event carries BOTH `ContractTermID` and `ContractBillingScheduleID`, and
 * nothing required the schedule to belong to that term. `Term A`'s event could point at `Term B`'s
 * schedule and it saved cleanly.
 *
 * WHY THAT IS WORSE THAN IT SOUNDS. The two columns are read by different things. The scheduled-job
 * driver selects by `Status` + `ScheduledDate` and bills against the EVENT'S term. Termination
 * cancels future events by looking them up through their TERM. The workspace's Billing tab lists a
 * schedule's events through the SCHEDULE. So a crossed row bills one term while being cancelled with
 * another — which is not a display bug, it is an invoice sent for an agreement that was terminated.
 *
 * WHY IT IS NOT A CHECK CONSTRAINT. The rule compares a column on this row to a column on the row it
 * points at, and a CHECK cannot see another row. Same shape and same reasoning as the renewal-chain
 * rule in `ContractTermEntityServer` — and, as there, it lives in `ValidateAsync()` with
 * `DefaultSkipAsyncValidation` overridden to `false`, because a rule placed there without the
 * override never runs at all.
 *
 * A COMPOSITE FK (`ContractBillingScheduleID`, `ContractTermID`) referencing a matching unique key on
 * the schedule would enforce this in SQL. That is the better long-term shape and it is a schema
 * change worth proposing rather than making unilaterally — the entity guard closes the hole now and
 * the composite key can replace it later without changing any caller.
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
import { RegisterClass, UUIDsEqual } from '@memberjunction/global';
import { mjBizAppsContractsContractBillingEventEntity } from '@mj-biz-apps/contracts-entities';

const BILLING_EVENT_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Events';
const SCHEDULE_ENTITY = 'MJ_BizApps_Contracts: Contract Billing Schedules';

@RegisterClass(BaseEntity, BILLING_EVENT_ENTITY)
export class ContractBillingEventEntityServer extends mjBizAppsContractsContractBillingEventEntity {
    /**
     * Opt in to async validation — `BaseEntity` skips it by default, so the rule below would be dead
     * code without this. One extra read per billing-event save, which is the correct price for not
     * billing a terminated agreement.
     */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkScheduleBelongsToTerm(result);
        return result;
    }

    private async checkScheduleBelongsToTerm(result: ValidationResult): Promise<void> {
        if (!this.ContractBillingScheduleID || !this.ContractTermID) return;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ContractTermID: string }>(
            {
                EntityName: SCHEDULE_ENTITY,
                Fields: ['ContractTermID'],
                ExtraFilter: `ID='${this.ContractBillingScheduleID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not verify the billing schedule's term: ${res?.ErrorMessage ?? 'unknown error'}`);
        }

        const schedule = res.Results?.[0];
        // A missing schedule is the FK's to reject; duplicating it here would give one condition two
        // different messages.
        if (!schedule) return;

        if (UUIDsEqual(schedule.ContractTermID, this.ContractTermID)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'ContractBillingScheduleID',
                `This billing event names a schedule belonging to a DIFFERENT term. The two are read by ` +
                    `different things — the scheduled job bills against the event's term, termination cancels ` +
                    `through it, and the Billing tab lists through the schedule — so a crossed row bills one ` +
                    `agreement while being cancelled with another.`,
                this.ContractBillingScheduleID,
            ),
        );
    }
}

/** Tree-shaking anchor. */
export function LoadContractBillingEventEntityServer(): void {
    /* intentionally empty */
}
