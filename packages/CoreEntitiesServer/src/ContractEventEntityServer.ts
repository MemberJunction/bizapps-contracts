/**
 * @fileoverview Server-side `ContractEvent` — makes the audit trail actually immutable.
 *
 * THE TABLE'S OWN COMMENT SAID "never edited, never deleted". That was documentation, not a
 * mechanism: CodeGen generates full CRUD for every entity, so `spUpdateContractEvent` and
 * `spDeleteContractEvent` exist and work. A test that edited an event and then deleted it succeeded.
 *
 * An audit trail whose immutability is a comment is not an audit trail — it is a table that happens
 * to contain history until someone changes it. That matters more here than usual because the
 * termination reason lives in this log rather than on the contract row: if these rows are editable,
 * the recorded reason a contract ended is editable too.
 *
 * So: an existing row cannot be saved, and no row can be deleted. Insert is the only legal write.
 * The migration handles the other half of the same finding — `EventType` is now a CHECK-enforced
 * closed vocabulary rather than the schema's one free-text value column.
 *
 * WHY NOT DATABASE TRIGGERS. An INSTEAD OF trigger would block CodeGen's own sprocs and make the
 * generated CRUD fail in ways that read as MJ bugs. The entity layer is the path every write in this
 * app takes, and it can explain itself.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseEntity,
    ValidationErrorInfo,
    ValidationResult,
    type EntityDeleteOptions,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractEventEntity } from '@mj-biz-apps/contracts-entities';

const EVENT_ENTITY = 'MJ_BizApps_Contracts: Contract Events';

@RegisterClass(BaseEntity, EVENT_ENTITY)
export class ContractEventEntityServer extends mjBizAppsContractsContractEventEntity {
    /**
     * Refusal as a VALIDATION error rather than a bare `false`, so the caller is told why. `Save()`
     * merges these into `LatestResult`; a guard that only logged to the console left the UI showing
     * "Save failed: unknown error", which is a refusal nobody can act on.
     */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        if (this.IsSaved) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'ID',
                    `Contract events cannot be modified. The log is append-only — history that can be ` +
                        `rewritten is not history. Record a new event instead.`,
                    this.ID,
                ),
            );
        }
        return result;
    }

    /**
     * Delete has no validation hook, so this stays a logged refusal — but it is unconditional, which
     * makes it self-explanatory in a way the conditional Save guard was not.
     */
    public override async Delete(_options?: EntityDeleteOptions): Promise<boolean> {
        // eslint-disable-next-line no-console
        console.error(
            `[Contracts] Refused to delete contract event ${this.ID} (${this.EventType}). Events are never ` +
                `removed — a contract's history includes the parts someone would rather forget.`,
        );
        return false;
    }
}

/** Tree-shaking anchor. */
export function LoadContractEventEntityServer(): void {
    /* intentionally empty */
}
