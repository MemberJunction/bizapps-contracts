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

import {
    BaseEntity,
    RunView,
    type IMetadataProvider,
    ValidationErrorInfo,
    ValidationResult,
    type EntitySaveOptions,
    type IRunViewProvider,
} from '@memberjunction/core';
import { RegisterClass, UUIDsEqual } from '@memberjunction/global';
import { ContractsEngine, LoadContractsEngine } from './ContractsEngine.js';
import { mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';

const TERM_ENTITY = 'MJ_BizApps_Contracts: Contract Terms';
const CONTRACT_ENTITY = 'MJ_BizApps_Contracts: Contracts';

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
    /**
     * OPT IN TO ASYNC VALIDATION. `BaseEntity.DefaultSkipAsyncValidation` is `true`, so `ValidateAsync`
     * is skipped unless an entity asks for it — and a rule placed there without this override simply
     * never runs. That is exactly what happened when the renewal-chain check moved out of `Save()`:
     * cross-contract renewals started saving again, silently, until a test caught it.
     *
     * The cost is one extra read per term save, which is the correct price for a rule that prevents
     * one contract's history from showing another contract's terms.
     */
    public override get DefaultSkipAsyncValidation(): boolean {
        return false;
    }

    /** Synchronous rules — everything decidable from this row alone. */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        this.checkEscalationCap(result);
        return result;
    }

    /**
     * Cross-record rules go here, not in `Validate()`: the renewal-chain check must READ the row it
     * points at, and `Validate()` is synchronous. `Save()` runs both and merges the errors.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();
        await this.checkRenewalChainIntegrity(result);
        return result;
    }

    public override async Save(options?: EntitySaveOptions): Promise<boolean> {

        // TERM NUMBERING IS DERIVED, NOT TYPED. A term's number is its position in the contract's
        // chain; asking a caller to supply it invites the duplicate that the unique index on
        // (ContractID, TermNumber) then rejects at the worst possible moment.
        if (!this.IsSaved && (this.TermNumber === null || this.TermNumber === undefined || this.TermNumber <= 0)) {
            this.TermNumber = await this.nextTermNumber();
        }

        if (!this.IsSaved) {
            await this.applyContractTypeDefaults();
        }

        return super.Save(options);
    }

    /**
     * The cap rule. Both are fractions (0.05 = 5%), and a null cap means "uncapped" — deliberately
     * permitted, because plenty of real agreements have no ceiling and pretending otherwise would
     * make them unrecordable.
     */
    private checkEscalationCap(result: ValidationResult): void {
        const pct = this.EscalationPercent;
        const cap = this.MaxEscalationPercent;
        if (pct === null || pct === undefined || cap === null || cap === undefined) return;
        if (pct <= cap) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'EscalationPercent',
                `An escalation of ${(pct * 100).toFixed(2)}% exceeds this term's negotiated cap of ` +
                    `${(cap * 100).toFixed(2)}%. Either lower the escalation or raise the cap — the cap is what ` +
                    `the contract says, so changing it is a negotiation, not a correction.`,
                pct,
            ),
        );
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
    private async checkRenewalChainIntegrity(result: ValidationResult): Promise<void> {
        if (!this.RenewalOfTermID || !this.ContractID) return;

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
        if (!parent) return;

        if (UUIDsEqual(parent.ContractID, this.ContractID)) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'RenewalOfTermID',
                `This term is recorded as renewing term ${parent.TermNumber} of a DIFFERENT contract. ` +
                    `A renewal chain cannot cross contracts — walking it would surface another contract's ` +
                    `terms as this one's history.`,
                this.RenewalOfTermID,
            ),
        );
    }

    private checkStatusTransition(result: ValidationResult): void {
        if (!this.IsSaved) return;
        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return;
        if ((LEGAL_MOVES[previous] ?? []).includes(next)) return;

        const allowed = (LEGAL_MOVES[previous] ?? []).filter((s) => s !== previous);
        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                `A term cannot move from ${previous} to ${next}. ` +
                    (allowed.length ? `Legal moves are: ${allowed.join(', ')}.` : `${previous} is a terminal state.`),
                next,
            ),
        );
    }

    /**
     * Fill a NEW term's unset ceiling and notice period from its contract type.
     *
     * This is what "configuration as data" means in practice: `ContractType` carries
     * `DefaultMaxEscalationPercent` and `DefaultRenewalNoticeDays` precisely so the engine READS them
     * rather than branching on a type's name, and a term created without them should get what its
     * type prescribes instead of silently having no ceiling at all — which is the uncapped
     * "then-current list price" case the cap exists to prevent.
     *
     * NEW RECORDS ONLY, and only fields the caller left unset. Both halves matter:
     *
     *  - On an EXISTING term, retrofitting a default would CHANGE AN AGREEMENT. A term that was
     *    negotiated without a ceiling has no ceiling; that is a fact about the contract, not a gap.
     *  - A RENEWAL is unaffected by construction: `RenewTerm` copies the prior term's values forward,
     *    so it always supplies them and this never fires. A renewal inherits from the agreement it
     *    continues, never from the type — the type's defaults describe how a NEW term starts.
     */
    private async applyContractTypeDefaults(): Promise<void> {
        const needsCap = this.MaxEscalationPercent === null || this.MaxEscalationPercent === undefined;
        const needsNotice = this.RenewalNoticeDays === null || this.RenewalNoticeDays === undefined;
        if ((!needsCap && !needsNotice) || !this.ContractID) return;

        const provider = this.ProviderToUse as unknown as IMetadataProvider;
        await LoadContractsEngine(provider, this.ContextCurrentUser);

        // The term knows its contract, not its type, so the type has to be resolved through it. One
        // read for the contract; the type itself comes from the cache.
        const rv = new RunView(provider as unknown as IRunViewProvider);
        const res = await rv.RunView<{ ContractTypeID: string }>(
            {
                EntityName: CONTRACT_ENTITY,
                Fields: ['ContractTypeID'],
                ExtraFilter: `ID='${this.ContractID}'`,
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        // A failed read must not silently skip the defaults — a term quietly created without its
        // ceiling is exactly the outcome this method exists to prevent.
        if (!res?.Success) {
            throw new Error(`Could not read the contract's type to apply its defaults: ${res?.ErrorMessage ?? 'unknown error'}`);
        }
        const contractTypeID = res.Results?.[0]?.ContractTypeID;
        if (!contractTypeID) return;

        const engine = ContractsEngine.Instance;
        if (needsCap) this.MaxEscalationPercent = engine.DefaultMaxEscalationFor(contractTypeID);
        if (needsNotice) this.RenewalNoticeDays = engine.DefaultRenewalNoticeDaysFor(contractTypeID);
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
