/**
 * @fileoverview Server-side `ContractCommitment` — minimums, prepaid balances and draws.
 *
 * WHAT A COMMITMENT IS FOR. The master plan says this app owns "consumed versus committed"; the
 * commitment row is where that lives. `CommittedAmount` is what the customer promised to spend,
 * `ConsumedAmount` is what they have, and `TrueUpPolicy` says what happens to the difference at
 * period end. The billing engine reads all three to compute a shortfall.
 *
 * WHAT IS DELIBERATELY NOT ENFORCED HERE, AND WHY THAT IS NOT AN OVERSIGHT:
 *
 *  - **Which `TrueUpPolicy` values are legal for which `CommitmentType`.** `Forfeit` on a `Prepaid`
 *    balance and `Rollover` on a `Minimum` are the two combinations that look wrong, but "look
 *    wrong" is not a rule — this is open question **X.13**, waiting on Andrew, and it changes what
 *    the billing engine computes. Guessing it here would bake an unreviewed commercial policy into
 *    the one path every write takes, and a wrong guess silently under- or over-bills. It stays open.
 *
 *  - **`ConsumedAmount` capped at `CommittedAmount`.** Over-consumption against a minimum is a real
 *    state that must be recordable and reportable, not an error. The schema comment says so
 *    explicitly and the CHECK deliberately bounds only the floor.
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
import { mjBizAppsContractsContractCommitmentEntity } from '@mj-biz-apps/contracts-entities';

const COMMITMENT_ENTITY = 'MJ_BizApps_Contracts: Contract Commitments';
const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';

/**
 * Which commitment status may follow which.
 *
 * All three exits from `Open` are terminal: a commitment that has been trued up, forfeited or closed
 * has had its money decided. Re-opening it would let the same shortfall bill twice.
 */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Open: ['Open', 'Closed', 'TruedUp', 'Forfeited'],
    Closed: ['Closed'],
    TruedUp: ['TruedUp'],
    Forfeited: ['Forfeited'],
};

@RegisterClass(BaseEntity, COMMITMENT_ENTITY)
export class ContractCommitmentEntityServer extends mjBizAppsContractsContractCommitmentEntity {
    /** The period-within-term rule reads the term row. */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        this.checkAmounts(result);
        return result;
    }

    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkPeriodWithinTerm(result);
        return result;
    }

    /**
     * A settled commitment stays settled. Without this, `TruedUp -> Open` saves happily and the same
     * shortfall can be billed a second time — the exact duplicate-billing shape the billing event's
     * Failed-with-a-reason design exists to avoid.
     */
    private checkStatusTransition(result: ValidationResult): void {
        if (!this.IsSaved) return;

        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return;
        if ((LEGAL_MOVES[previous] ?? []).includes(next)) return;

        const others = (LEGAL_MOVES[previous] ?? []).filter((s) => s !== previous);
        this.fail(
            result,
            'Status',
            `A commitment cannot move from ${previous} to ${next}. ` +
                (others.length
                    ? `Legal moves are: ${others.join(', ')}.`
                    : `${previous} is settled — its money has been decided, and reopening it would let the ` +
                      'same shortfall bill twice.'),
            next,
        );
    }

    /** The readable half of `CK_ContractCommitment_CommittedAmount` / `_ConsumedAmount`. */
    private checkAmounts(result: ValidationResult): void {
        if (typeof this.CommittedAmount === 'number' && this.CommittedAmount < 0) {
            this.fail(
                result,
                'CommittedAmount',
                'A commitment cannot be negative — a promise to spend less than nothing is not a thing the ' +
                    'billing engine can compute a shortfall against.',
                this.CommittedAmount,
            );
        }
        if (typeof this.ConsumedAmount === 'number' && this.ConsumedAmount < 0) {
            this.fail(
                result,
                'ConsumedAmount',
                'Consumption cannot be negative. To reverse consumption, record the reversal that caused ' +
                    'it rather than driving this total below zero.',
                this.ConsumedAmount,
            );
        }
    }

    /**
     * A commitment period outside its term measures consumption over a window the agreement does not
     * cover, so the shortfall it produces bills for time the customer never contracted.
     *
     * Null bounds mean "the whole term", which is the common case and always valid.
     */
    private async checkPeriodWithinTerm(result: ValidationResult): Promise<void> {
        const periodStart = ContractCommitmentEntityServer.asDate(this.PeriodStart);
        const periodEnd = ContractCommitmentEntityServer.asDate(this.PeriodEnd);
        if ((!periodStart && !periodEnd) || !this.ContractTermID) return;

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
            throw new Error(`Could not read this commitment's term: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const term = res.Results?.[0];
        if (!term) return;

        const termStart = ContractCommitmentEntityServer.asDate(term.StartDate);
        const termEnd = ContractCommitmentEntityServer.asDate(term.EndDate);
        if (!termStart || !termEnd) return;

        if (periodStart && periodStart.getTime() < termStart.getTime()) {
            this.fail(
                result,
                'PeriodStart',
                `The commitment period starts ${ContractCommitmentEntityServer.iso(periodStart)}, before ` +
                    `term ${term.TermNumber} begins (${ContractCommitmentEntityServer.iso(termStart)}). ` +
                    'Consumption would be measured over time the agreement does not cover.',
                this.PeriodStart,
            );
        }

        if (periodEnd && periodEnd.getTime() > termEnd.getTime()) {
            this.fail(
                result,
                'PeriodEnd',
                `The commitment period ends ${ContractCommitmentEntityServer.iso(periodEnd)}, after term ` +
                    `${term.TermNumber} ends (${ContractCommitmentEntityServer.iso(termEnd)}). A shortfall ` +
                    'computed over that window would bill for time the customer never contracted.',
                this.PeriodEnd,
            );
        }
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
export function LoadContractCommitmentEntityServer(): void {
    /* intentionally empty */
}
