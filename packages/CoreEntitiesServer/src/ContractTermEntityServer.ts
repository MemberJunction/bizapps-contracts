/**
 * @fileoverview Server-side `ContractTerm` — term numbering, the escalation cap, and legal moves.
 *
 * THE ESCALATION CAP IS THE INTERESTING ONE. `MaxEscalationPercent` is a ceiling on
 * `EscalationPercent`, and that rule **cannot be a CHECK constraint** here: CodeGen derives a
 * generated validation method name from the constraint expression, and a constraint naming two
 * columns makes it emit a call to a method it never defines — a build break in generated code that
 * orders already hit and documented. So the rule lives where it can be expressed safely: in `Save()`,
 * on the one path every write takes.
 *
 * That is not a workaround. An uncapped "then-current list price" increase is the single most
 * disputed clause in a B2B renewal; a contract that records a 5% ceiling and then escalates 8%
 * is a contract we would lose an argument about.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import { BaseEntity, RunView, type EntitySaveOptions, type IRunViewProvider } from '@memberjunction/core';
import { RegisterClass, UUIDsEqual } from '@memberjunction/global';
import { mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';

const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';

/** Which term status may follow which. Terminal states have only themselves. */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Pending: ['Pending', 'PendingSignature', 'Active', 'Terminated'],
    PendingSignature: ['PendingSignature', 'Pending', 'Active', 'Terminated'],
    Active: ['Active', 'Completed', 'Terminated'],
    Completed: ['Completed'],
    Terminated: ['Terminated'],
};

@RegisterClass(BaseEntity, TERM_ENTITY)
export class ContractTermEntityServer extends mjBizAppsContractsContractTermEntity {
    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        if (!this.passesStatusTransition()) return false;
        if (!this.passesEscalationCap()) return false;
        if (!(await this.passesRenewalChainIntegrity())) return false;

        // TERM NUMBERING IS DERIVED, NOT TYPED. A term's number is its position in the contract's
        // chain; asking a caller to supply it invites the duplicate that the unique index on
        // (ContractID, TermNumber) then rejects at the worst possible moment.
        if (!this.IsSaved && (this.TermNumber === null || this.TermNumber === undefined || this.TermNumber <= 0)) {
            this.TermNumber = await this.nextTermNumber();
        }

        return super.Save(options);
    }

    /**
     * The cap rule. Both are fractions (0.05 = 5%), and a null cap means "uncapped" — deliberately
     * permitted, because plenty of real agreements have no ceiling and pretending otherwise would
     * make them unrecordable.
     */
    private passesEscalationCap(): boolean {
        const pct = this.EscalationPercent;
        const cap = this.MaxEscalationPercent;
        if (pct === null || pct === undefined || cap === null || cap === undefined) return true;
        if (pct <= cap) return true;

        // eslint-disable-next-line no-console
        console.error(
            `[Contracts] Refused term ${this.TermNumber ?? '(new)'}: escalation ${(pct * 100).toFixed(2)}% ` +
                `exceeds its cap of ${(cap * 100).toFixed(2)}%. Raise MaxEscalationPercent or lower EscalationPercent.`,
        );
        return false;
    }

    /**
     * A term may only renew a term on the SAME contract.
     *
     * The FK blocks only self-reference, so `A.Term1` could be recorded as the renewal of `B.Term3`
     * and it saved. The renewal chain is this app's continuity model and the workspace's term history
     * walks it — a cross-contract link makes that walk surface **another customer's terms** inside
     * this contract's history. That is a data-leak shape, not just an inconsistency.
     *
     * This cannot be a CHECK constraint: the rule compares a column on this row to a column on the
     * row it points at, and a CHECK cannot see another row.
     */
    private async passesRenewalChainIntegrity(): Promise<boolean> {
        if (!this.RenewalOfTermID || !this.ContractID) return true;

        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ContractID: string; TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['ContractID', 'TermNumber'],
                ExtraFilter: `ID='${this.RenewalOfTermID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!res?.Success) {
            throw new Error(`Could not verify the renewal chain: ${res?.ErrorMessage ?? 'unknown error'}`);
        }

        const parent = res.Results?.[0];
        // A missing predecessor is left to the FK to reject — that is its job, and duplicating the
        // error here would produce two different messages for one condition.
        if (!parent) return true;

        if (UUIDsEqual(parent.ContractID, this.ContractID)) return true;

        // eslint-disable-next-line no-console
        console.error(
            `[Contracts] Refused term: RenewalOfTermID points at term ${parent.TermNumber} on a DIFFERENT ` +
                `contract. A renewal chain cannot cross contracts — walking it would surface another ` +
                `contract's terms as this one's history.`,
        );
        return false;
    }

    private passesStatusTransition(): boolean {
        if (!this.IsSaved) return true;
        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return true;
        if ((LEGAL_MOVES[previous] ?? []).includes(next)) return true;

        const allowed = (LEGAL_MOVES[previous] ?? []).filter((s) => s !== previous);
        // eslint-disable-next-line no-console
        console.error(
            `[Contracts] Refused term status move ${previous} -> ${next}. ` +
                (allowed.length ? `Legal moves: ${allowed.join(', ')}.` : `${previous} is terminal.`),
        );
        return false;
    }

    /** max(TermNumber) + 1 for this contract, via RunView on this entity's own provider. */
    private async nextTermNumber(): Promise<number> {
        if (!this.ContractID) return 1;
        // The entity's OWN provider, cast to the RunView surface — never a global Metadata.
        const rv = new RunView(this.ProviderToUse as unknown as IRunViewProvider);
        const res = await rv.RunView<{ TermNumber: number }>(
            {
                EntityName: TERM_ENTITY,
                Fields: ['TermNumber'],
                ExtraFilter: `ContractID='${this.ContractID}'`,
                OrderBy: 'TermNumber DESC',
                MaxRows: 1,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // RunView reports failure via Success and never throws; a failed read must not silently
        // hand back 1 and collide with an existing term.
        if (!res?.Success) {
            throw new Error(`Could not determine the next term number: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const highest = res.Results?.[0]?.TermNumber ?? 0;
        return Number(highest) + 1;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractTermEntityServer(): void {
    /* intentionally empty */
}
