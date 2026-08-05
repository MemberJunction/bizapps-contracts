/**
 * @fileoverview Server-side `Contract` — the invariants that must hold no matter who writes the row.
 *
 * WHY HERE AND NOT IN A HELPER. `Save()` is the one path every write goes through: the UI, an Action,
 * a fixture, a workflow, an agent. A rule enforced anywhere else is a rule that holds right up until
 * somebody saves the entity directly — which is precisely how a "validated" record ends up invalid.
 *
 * WHAT THE DATABASE CANNOT DO, AND SO LIVES HERE:
 *  - **Legal status MOVES.** `CK_Contract_Status` enforces the legal SET and knows nothing about
 *    transitions, so `Terminated -> Active` and `Superseded -> Draft` both save happily today. A
 *    terminated contract coming back to life keeps its billing schedule and starts invoicing again.
 *  - **Sequence allocation.** `ContractNumber` is unique and human-facing; allocating it needs a
 *    read-modify-write against `ContractSequence` that must not interleave.
 *  - **The pricing lock.** `PricedAt` is the as-of date every price on the agreement resolves from
 *    (master plan §12). A contract saved without one has no defined pricing moment at all.
 *
 * PROVIDER DISCIPLINE: everything goes through `this.ProviderToUse` — the entity's own provider —
 * never `new Metadata()` or a global. A second provider splits the metadata and the class factory,
 * and the failure is silent.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import { BaseEntity, ValidationErrorInfo, ValidationResult, type EntitySaveOptions } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type { DatabaseProviderBase } from '@memberjunction/core';
import { mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';

const CONTRACT_ENTITY = 'MJ_BizApps_Contracts: Contracts';

/**
 * Which status may follow which. Absent from the map means "no move out of here" — a terminal state.
 *
 * `Superseded` is terminal on purpose: a contract that was replaced does not come back. The successor
 * is a different row, named by `SupersededByContractID`.
 */
const LEGAL_MOVES: Readonly<Record<string, readonly string[]>> = {
    Draft: ['Draft', 'PendingSignature', 'Active', 'Terminated'],
    PendingSignature: ['PendingSignature', 'Draft', 'Active', 'Terminated'],
    Active: ['Active', 'Expired', 'Terminated', 'Superseded'],
    Expired: ['Expired', 'Superseded', 'Terminated'],
    Terminated: ['Terminated'],
    Superseded: ['Superseded'],
};

@RegisterClass(BaseEntity, CONTRACT_ENTITY)
export class ContractEntityServer extends mjBizAppsContractsContractEntity {
    /**
     * VALIDATION, NOT A SAVE GUARD. These rules used to live in `Save()` as an early `return false`
     * plus a `console.error`, which refused correctly and told the user nothing: the UI showed
     * "Save failed: unknown error" because no error had been recorded anywhere it could read.
     *
     * `Save()` calls `Validate()` and puts its errors on `LatestResult`, so putting the rules here
     * means every caller — the form, an operation, an agent — gets the actual reason.
     */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.checkStatusTransition(result);
        return result;
    }

    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        // The pricing moment. Defaulted rather than demanded: a contract created today is priced
        // today, and someone entering older paper overrides it. What must not happen is a contract
        // with no as-of date, because then "the catalog price" has no defined meaning (§12).
        if (!this.PricedAt) {
            this.PricedAt = new Date();
        }

        const needsNumber = !this.ContractNumber || !this.ContractNumber.trim();
        if (!needsNumber) {
            return super.Save(options);
        }

        // ALLOCATION IS TRANSACTIONAL, and the number lands on `this` so it is persisted by the same
        // super.Save() as everything else — allocating outside the transaction would hand out a
        // number that a failed save then strands, and `ContractNumber` is uniquely indexed.
        const provider = this.ProviderToUse as unknown as DatabaseProviderBase;
        try {
            await provider.BeginTransaction();
            this.ContractNumber = await this.allocateContractNumber(provider);
            const saved = await super.Save(options);
            if (!saved) {
                await provider.RollbackTransaction();
                return false;
            }
            await provider.CommitTransaction();
            return true;
        } catch (e) {
            await provider.RollbackTransaction();
            throw e;
        }
    }

    /**
     * A save is legal when the status is unchanged, or when the move is in {@link LEGAL_MOVES}.
     * A brand-new record may start in any state the CHECK allows — the map governs MOVES, not births.
     */
    private checkStatusTransition(result: ValidationResult): void {
        if (!this.IsSaved) return;

        const field = this.Fields.find((f) => f.Name === 'Status');
        const previous = field?.OldValue as string | undefined;
        const next = this.Status as unknown as string;
        if (!previous || previous === next) return;

        const allowed = LEGAL_MOVES[previous] ?? [];
        if (allowed.includes(next)) return;

        // The message names the legal alternatives, because "that is not allowed" leaves the person
        // to guess what is. A terminal state says so outright rather than listing nothing.
        const others = allowed.filter((s) => s !== previous);
        const detail = others.length
            ? `Legal moves from ${previous} are: ${others.join(', ')}.`
            : `${previous} is a terminal state — nothing follows it.`;
        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo('Status', `A contract cannot move from ${previous} to ${next}. ${detail}`, next),
        );
    }

    /**
     * `CTR-{seq}` from the singleton `ContractSequence` row. Read-modify-write inside the caller's
     * transaction, so two concurrent creates cannot take the same number.
     */
    private async allocateContractNumber(provider: DatabaseProviderBase): Promise<string> {
        // OUTPUT ... INTO, not a bare OUTPUT: CodeGen puts an __mj_UpdatedAt trigger on every table,
        // and SQL Server refuses a bare OUTPUT clause on a table that has enabled triggers.
        const rows = await provider.ExecuteSQL(
            `DECLARE @allocated TABLE (Allocated INT);
             UPDATE __mj_BizAppsContracts.ContractSequence
                SET NextSequenceNumber = NextSequenceNumber + 1
             OUTPUT deleted.NextSequenceNumber INTO @allocated(Allocated);
             SELECT Allocated FROM @allocated;`,
        );
        const allocated = Array.isArray(rows) && rows.length ? Number((rows[0] as { Allocated: number }).Allocated) : NaN;
        if (!Number.isFinite(allocated)) {
            throw new Error('ContractSequence produced no number — is the singleton row missing?');
        }
        return `CTR-${String(allocated).padStart(6, '0')}`;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadContractEntityServer(): void {
    /* intentionally empty */
}
