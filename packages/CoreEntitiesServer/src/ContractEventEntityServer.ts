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

import { BaseEntity, type EntityDeleteOptions, type EntitySaveOptions } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractEventEntity } from '@mj-biz-apps/contracts-entities';

const EVENT_ENTITY = 'MJ_BizApps_Contracts: Contract Events';

@RegisterClass(BaseEntity, EVENT_ENTITY)
export class ContractEventEntityServer extends mjBizAppsContractsContractEventEntity {
    public override async Save(options?: EntitySaveOptions): Promise<boolean> {
        if (this.IsSaved) {
            // eslint-disable-next-line no-console
            console.error(
                `[Contracts] Refused to modify contract event ${this.ID} (${this.EventType}). The event log is ` +
                    `append-only: history that can be rewritten is not history. Record a NEW event instead.`,
            );
            return false;
        }
        return super.Save(options);
    }

    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
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
