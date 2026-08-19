/**
 * @fileoverview `ContractEntityServer` — the rules that CANNOT run in a browser.
 *
 * Registered later than the shared `ContractEntity`, so MJ's ClassFactory resolves this one on the
 * server while the browser keeps the shared class (plan §6.3). Everything a client should be able to
 * preflight lives on the shared class instead; what is here needs a lock or a cross-entity read.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity, LogError, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractEntity } from '@mj-biz-apps/contracts-entities';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')
export class ContractEntityServer extends ContractEntity {
    /**
     * Mint `ContractNumber` on first save, then persist.
     *
     * WHY THE NUMBER IS MINTED HERE and not defaulted in SQL. It comes from a singleton counter that
     * has to be taken under a lock inside the save's own transaction, so a rollback releases the
     * number instead of burning it. A column default cannot do that, and a client cannot be trusted
     * with it.
     *
     * Contracts needs no `SkipRelatedCollections` dance, unlike orders: nothing here prepares child
     * rows before the graph executor runs, so the plain save carries `Modifications` with it.
     */
    public override async Save(): Promise<boolean> {
        try {
            if (!this.IsSaved && !this.ContractNumber) {
                this.ContractNumber = await this.assignContractNumber();
            }
            return await super.Save();
        } catch (err) {
            LogError(`ContractEntityServer.Save failed for contract ${this.ContractNumber ?? this.ID}: ${err}`);
            throw err;
        }
    }

    /**
     * Server-authoritative rules that need to read another entity.
     *
     * A CHANGE ORDER MUST NAME WHAT IT CHANGES. The rule needs the ContractType row to know whether
     * this contract IS a change order, which is a join the browser has no business doing — so the
     * shared class cannot carry it (ERD §7.1). Without the rule a change order with no parent is a
     * contract that claims to amend something and names nothing, and the derived `IsChangeOrder`
     * reads false on it, so it silently disappears from every lineage view.
     *
     * Deliberately keyed on the type NAME here, which is the one place that is correct: the check has
     * to ask "is this the change-order type", and the type table carries no boolean for it —
     * `RequiresExecutedDocument` is the only rule column, and it says something else entirely.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();

        if (this.ContractTypeID && !this.ParentContractID && (await this.isChangeOrderType())) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'ParentContractID',
                    `Contract ${this.ContractNumber ?? ''} is a Change Order, so it must name the contract it ` +
                        `changes. A change order with no parent amends nothing and would not appear in the ` +
                        `original agreement's lineage.`,
                    this.ParentContractID,
                    ValidationErrorType.Failure,
                ),
            );
        }

        return result;
    }

    /** Whether this contract's type is the Change Order type. One scalar read, no entity load. */
    private async isChangeOrderType(): Promise<boolean> {
        const provider = this.ProviderToUse as unknown as { ExecuteSQL: (sql: string, params?: unknown[]) => Promise<unknown> };
        const rows = (await provider.ExecuteSQL(
            `SELECT [Name] FROM __mj_BizAppsContracts.ContractType WHERE ID = @p0`,
            [this.ContractTypeID],
        )) as Array<{ Name: string }>;
        return rows?.[0]?.Name === 'Change Order';
    }

    /**
     * Take the next value from the `ContractSequence` singleton and format it `CTR-000001`.
     *
     * `UPDLOCK, HOLDLOCK` inside the CALLER'S transaction, so concurrent creates serialize on the
     * counter row rather than colliding on the unique index — and a create that rolls back releases
     * its number rather than leaving a gap.
     *
     * `OUTPUT … INTO` rather than a bare `OUTPUT`: CodeGen puts an `__mj_UpdatedAt` trigger on every
     * table, and SQL Server forbids a bare OUTPUT clause on a table that has triggers. Copied
     * verbatim from orders' `nextSequence`, including that constraint, because it is the same
     * problem and getting it subtly different across two apps would be worse than duplicating it.
     */
    private async assignContractNumber(): Promise<string> {
        const provider = this.ProviderToUse as unknown as { ExecuteSQL: (sql: string, params?: unknown[]) => Promise<unknown> };
        const rows = (await provider.ExecuteSQL(
            `DECLARE @seq TABLE (Seq INT);
             UPDATE __mj_BizAppsContracts.ContractSequence WITH (UPDLOCK, HOLDLOCK)
             SET NextSequenceNumber = NextSequenceNumber + 1
             OUTPUT deleted.NextSequenceNumber INTO @seq(Seq)
             WHERE ID = 1;
             SELECT Seq FROM @seq;`,
        )) as Array<{ Seq: number }>;

        const seq = rows?.[0]?.Seq;
        if (!seq) {
            throw new Error(
                `Could not obtain the next contract number — the ContractSequence singleton row (ID=1) is ` +
                    `missing. It is seeded by the baseline migration.`,
            );
        }
        return `CTR-${String(seq).padStart(6, '0')}`;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractEntityServer(): void {
    void ContractEntityServer;
}
