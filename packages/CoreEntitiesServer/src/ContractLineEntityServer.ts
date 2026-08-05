/**
 * @fileoverview Server-side `ContractLine` — coverage rules a CHECK constraint cannot hold.
 *
 * WHY THIS CLASS EXISTS AT ALL. Until now `ContractLine` had EIGHT CHECK constraints and no server
 * subclass, which meant two different things were true at once: the row could not be written
 * invalid, and nobody writing one could be told why. A CHECK reports itself as
 * `CK_ContractLine_SubscriptionNeedsType` — a symbol, in a database error, arriving at a UI that can
 * only render it verbatim. So the rules are mirrored here as sentences, and the CHECK stays exactly
 * where it is as the un-bypassable floor beneath them. The mirror is not a replacement: a rule that
 * lives ONLY in TypeScript is a rule that direct SQL walks straight past.
 *
 * AND THE RULES A CHECK GENUINELY CANNOT HOLD, which is the real reason for the file:
 *  - **A line must sit inside its term.** Coverage running past the term's end date bills for a
 *    period the agreement does not cover. The dates being compared live on two different rows, so no
 *    CHECK can see both.
 *  - **A finished term does not gain coverage.** Adding a line to a `Completed` or `Terminated` term
 *    silently changes what a closed period was entitled to — and the billing engine, which reads
 *    lines to assemble a draft, would then bill it.
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
import { mjBizAppsContractsContractLineEntity } from '@mj-biz-apps/contracts-entities';

const LINE_ENTITY = 'MJ_BizApps_Contracts: Contract Lines';
const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';

/** Term statuses that no longer accept new or altered coverage. */
const CLOSED_TERM_STATUSES: readonly string[] = ['Completed', 'Terminated'];

@RegisterClass(BaseEntity, LINE_ENTITY)
export class ContractLineEntityServer extends mjBizAppsContractsContractLineEntity {
    /**
     * Both rules below read the TERM this line hangs off, so async validation has to actually run.
     * `BaseEntity` skips it unless an entity opts in — and a rule placed in `ValidateAsync` without
     * this override is dead code that looks live, which is precisely how the term's renewal-chain
     * check was silently disabled once already.
     */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    /** Same-row rules — the readable half of what the CHECK constraints enforce. */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkSubscriptionShape(result);
        this.checkOwnDates(result);
        return result;
    }

    /** Rules that must read the parent term. */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkAgainstTerm(result);
        return result;
    }

    /**
     * The subscription trio, said in English.
     *
     * `CK_ContractLine_SubscriptionNeedsType` is the one that matters: orders'
     * `Subscription.SubscriptionTypeID` is NOT NULL, so a subscription line without a type cannot be
     * materialised — and before the CHECK existed that failure landed at BILLING time, as a Failed
     * event on a live contract, rather than at write time on a draft.
     */
    private checkSubscriptionShape(result: ValidationResult): void {
        const isSubscription = this.LineType === 'Subscription';

        if (isSubscription && !this.SubscriptionTypeID) {
            this.fail(
                result,
                'SubscriptionTypeID',
                'A Subscription line must say WHICH KIND of subscription it will create. Without it the ' +
                    'billing engine cannot materialise the subscription, and the failure would surface as a ' +
                    'failed bill on a live contract rather than here on the draft.',
                this.SubscriptionTypeID,
            );
        }

        if (!isSubscription && this.SubscriptionTypeID) {
            this.fail(
                result,
                'SubscriptionTypeID',
                `A subscription type belongs only on a Subscription line; this line is ${this.LineType}. ` +
                    'Either change the line type or clear the subscription type.',
                this.SubscriptionTypeID,
            );
        }

        if (!isSubscription && this.SubscriptionID) {
            this.fail(
                result,
                'SubscriptionID',
                `Only a Subscription line can point at a subscription; this line is ${this.LineType}.`,
                this.SubscriptionID,
            );
        }
    }

    /** The line's own window, before it is compared with anything. */
    private checkOwnDates(result: ValidationResult): void {
        const start = ContractLineEntityServer.asDate(this.StartDate);
        const end = ContractLineEntityServer.asDate(this.EndDate);
        if (!start || !end || end.getTime() >= start.getTime()) return;

        this.fail(
            result,
            'EndDate',
            `Coverage cannot end (${ContractLineEntityServer.iso(end)}) before it starts ` +
                `(${ContractLineEntityServer.iso(start)}).`,
            this.EndDate,
        );
    }

    /**
     * The two cross-row rules.
     *
     * ONE READ serves both — the term's status and its dates arrive together, and a second query for
     * the same row would double the cost of every line save in a contract that may hold dozens.
     */
    private async checkAgainstTerm(result: ValidationResult): Promise<void> {
        if (!this.ContractTermID) return;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ Status: string; StartDate: Date | string; EndDate: Date | string; TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['Status', 'StartDate', 'EndDate', 'TermNumber'],
                ExtraFilter: `ID='${this.ContractTermID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // RunView signals failure through Success and never throws. Treating a failed read as "no
        // term" would skip both rules silently, which is the shape of bug this file exists to remove.
        if (!res?.Success) {
            throw new Error(`Could not read this line's term to validate it: ${res?.ErrorMessage ?? 'unknown error'}`);
        }

        const term = res.Results?.[0];
        // A missing term is the FK's to reject; duplicating it here would produce two different
        // messages for one condition.
        if (!term) return;

        this.checkTermAcceptsCoverage(result, term.Status, term.TermNumber);
        this.checkWithinTerm(result, term.StartDate, term.EndDate, term.TermNumber);
    }

    /**
     * A closed term's coverage is a historical fact. Changing it rewrites what a finished period
     * entitled the customer to — and because the billing engine assembles drafts from lines, a line
     * added to a terminated term is a line that can still produce a bill.
     */
    private checkTermAcceptsCoverage(result: ValidationResult, termStatus: string, termNumber: number): void {
        if (!CLOSED_TERM_STATUSES.includes(termStatus)) return;

        this.fail(
            result,
            'ContractTermID',
            `Term ${termNumber} is ${termStatus}, so its coverage is settled and cannot change. ` +
                'Coverage for a period that has ended is a record of what was agreed; to change what the ' +
                'customer gets NOW, amend the live term or renew into a new one.',
            this.ContractTermID,
        );
    }

    /**
     * Coverage outside the term bills for a period the agreement does not cover.
     *
     * A null date on the line means "for the whole term", which is the common case and always valid.
     * Only a stated date can fall outside.
     */
    private checkWithinTerm(
        result: ValidationResult,
        termStartRaw: Date | string,
        termEndRaw: Date | string,
        termNumber: number,
    ): void {
        const termStart = ContractLineEntityServer.asDate(termStartRaw);
        const termEnd = ContractLineEntityServer.asDate(termEndRaw);
        if (!termStart || !termEnd) return;

        const start = ContractLineEntityServer.asDate(this.StartDate);
        const end = ContractLineEntityServer.asDate(this.EndDate);

        if (start && start.getTime() < termStart.getTime()) {
            this.fail(
                result,
                'StartDate',
                `Coverage starts ${ContractLineEntityServer.iso(start)}, before term ${termNumber} begins ` +
                    `(${ContractLineEntityServer.iso(termStart)}). A line cannot entitle the customer to ` +
                    'something before the term that grants it has started.',
                this.StartDate,
            );
        }

        if (end && end.getTime() > termEnd.getTime()) {
            this.fail(
                result,
                'EndDate',
                `Coverage runs to ${ContractLineEntityServer.iso(end)}, past the end of term ${termNumber} ` +
                    `(${ContractLineEntityServer.iso(termEnd)}). Billing would generate for a period the ` +
                    'agreement does not cover — renew the term instead of extending the line past it.',
                this.EndDate,
            );
        }
    }

    private fail(result: ValidationResult, field: string, message: string, value: unknown): void {
        result.Success = false;
        result.Errors.push(new ValidationErrorInfo(field, message, value));
    }

    /** A DATE column can arrive as a `Date` or as an ISO string depending on the read path. */
    private static asDate(value: Date | string | null | undefined): Date | null {
        if (!value) return null;
        const d = value instanceof Date ? value : new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    /** UTC date-part only — repo convention is UTC everywhere, never a local-time getter. */
    private static iso(d: Date): string {
        return d.toISOString().slice(0, 10);
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractLineEntityServer(): void {
    /* intentionally empty */
}
