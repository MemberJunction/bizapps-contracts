/**
 * @fileoverview Server-side `ContractAmendment` — a mid-term change to a LIVE term.
 *
 * THE DISTINCTION THIS CLASS DEFENDS. An amendment changes a term that is running; a renewal starts
 * a new one. The schema comment calls conflating the two "the single most common contract-model
 * mistake", and until now nothing stopped it: an amendment could be written against a `Pending` term
 * that had not started, or a `Completed` one that had finished, and the row saved. Both are really
 * renewals wearing the wrong hat, and both produce a change history that says a settled period was
 * altered after the fact.
 *
 * A CHECK cannot enforce it — the status being tested lives on the term, one row over.
 *
 * NUMBERING IS DERIVED, not typed, for the same reason `ContractTerm.TermNumber` is: asking a caller
 * to supply a number that a unique index then rejects (`UQ_ContractAmendment_Term_Number`) turns an
 * ordering detail into a user-facing collision.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    RunView,
    ValidationErrorInfo,
    ValidationResult,
    type EntitySaveOptions,
    type IRunViewProvider,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractAmendmentEntity } from '@mj-biz-apps/contracts-entities';

const AMENDMENT_ENTITY = 'MJ_BizApps_Contracts: Contract Amendments';
const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';

/**
 * Which amendment status may follow which.
 *
 * `Applied` is terminal because an applied amendment has already changed the term — the change
 * cannot be un-made by editing the paperwork that recorded it. `Rejected` is terminal for the same
 * reason a rejection is a decision: revisiting it means raising a new amendment, which is what the
 * numbering is for.
 */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Draft: ['Draft', 'PendingApproval', 'Cancelled'],
    PendingApproval: ['PendingApproval', 'Approved', 'Rejected', 'Cancelled'],
    Approved: ['Approved', 'Applied', 'Cancelled'],
    Rejected: ['Rejected'],
    Applied: ['Applied'],
    Cancelled: ['Cancelled'],
};

/** Term statuses an amendment may target. An amendment changes what is RUNNING. */
const AMENDABLE_TERM_STATUSES: readonly string[] = ['Active'];

@RegisterClass(BaseEntity, AMENDMENT_ENTITY)
export class ContractAmendmentEntityServer extends mjBizAppsContractsContractAmendmentEntity {
    /** The amendable-term rule reads the term row, so async validation must actually run. */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        this.checkApprovalIsTraceable(result);
        return result;
    }

    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkTermIsAmendable(result);
        return result;
    }

    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        if (!this.IsSaved && (this.AmendmentNumber === null || this.AmendmentNumber === undefined || this.AmendmentNumber <= 0)) {
            this.AmendmentNumber = await this.nextAmendmentNumber();
        }
        return super.Save(options);
    }

    /**
     * `CK_ContractAmendment_ApprovedHasTask`, said readably.
     *
     * An amendment marked Approved with no task is an approval nobody can be held to — which is
     * exactly what routing non-standard terms through an approval task exists to prevent. Rejected
     * counts too: a rejection is equally a decision somebody made.
     */
    private checkApprovalIsTraceable(result: ValidationResult): void {
        const status = this.Status as unknown as string;
        if (status !== 'Approved' && status !== 'Rejected') return;
        if (this.ApprovalTaskID) return;

        this.fail(
            result,
            'ApprovalTaskID',
            `An amendment marked ${status} must name the approval task that decided it. Without one there ` +
                'is no record of who decided, or on what basis — and a discount or waiver granted with no ' +
                'traceable approval is the thing the approval route exists to prevent.',
            this.ApprovalTaskID,
        );
    }

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
            `An amendment cannot move from ${previous} to ${next}. ` +
                (others.length
                    ? `Legal moves are: ${others.join(', ')}.`
                    : `${previous} is terminal — to revisit it, raise a new amendment.`),
            next,
        );
    }

    /**
     * An amendment changes a LIVE term.
     *
     * Against a `Pending` term the change belongs in the term itself, which has not started and can
     * simply be edited. Against a `Completed` or `Terminated` one it rewrites a settled period. Both
     * are really renewals — a new term — and saying so is more useful than letting the row save.
     *
     * Only checked on a NEW amendment, or when the term it points at changes: an amendment raised
     * legitimately against a live term must remain editable through its approval route even after
     * that term completes, or an approval landing a day late would be unrecordable.
     */
    private async checkTermIsAmendable(result: ValidationResult): Promise<void> {
        if (!this.ContractTermID) return;

        const termField = this.Fields.find((f) => f.Name === 'ContractTermID');
        const termChanged = termField ? termField.Dirty : false;
        if (this.IsSaved && !termChanged) return;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ Status: string; TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['Status', 'TermNumber'],
                ExtraFilter: `ID='${this.ContractTermID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not read the term this amendment targets: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const term = res.Results?.[0];
        if (!term) return;
        if (AMENDABLE_TERM_STATUSES.includes(term.Status)) return;

        const advice =
            term.Status === 'Pending' || term.Status === 'PendingSignature'
                ? 'That term has not started yet, so change the term itself rather than amending it.'
                : 'That term has ended, so amending it would rewrite a settled period — renew into a new term instead.';

        this.fail(
            result,
            'ContractTermID',
            `An amendment changes a term that is RUNNING, and term ${term.TermNumber} is ${term.Status}. ${advice}`,
            this.ContractTermID,
        );
    }

    /** max(AmendmentNumber) + 1 for this term. */
    private async nextAmendmentNumber(): Promise<number> {
        if (!this.ContractTermID) return 1;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ AmendmentNumber: number }>(
            {
                EntityName: AMENDMENT_ENTITY,
                Fields: ['AmendmentNumber'],
                ExtraFilter: `ContractTermID='${this.ContractTermID}'`,
                OrderBy: 'AmendmentNumber DESC',
                MaxRows: 1,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // A failed read must not hand back 1 and collide on UQ_ContractAmendment_Term_Number.
        if (!res?.Success) {
            throw new Error(`Could not determine the next amendment number: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        return Number(res.Results?.[0]?.AmendmentNumber ?? 0) + 1;
    }

    private fail(result: ValidationResult, field: string, message: string, value: unknown): void {
        result.Success = false;
        result.Errors.push(new ValidationErrorInfo(field, message, value));
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractAmendmentEntityServer(): void {
    /* intentionally empty */
}
