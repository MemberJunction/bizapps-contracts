/**
 * @fileoverview `ContractTemplateEntityServer` — deleting an agreement version.
 *
 * A template version is a HISTORICAL RECORD: a customer who signed in June 2026 stays bound to the
 * June 2026 version, so the version never goes away. Deleting one that contracts incorporate would
 * erase what those customers actually agreed to. Retiring is a `Status` change on the template's TYPE,
 * not a delete.
 *
 * Both dependencies are reported, not just the first: a template almost always has provisions AND
 * contracts, and being refused twice in a row for two different reasons is the worst version of this.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity, type EntityDeleteOptions } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTemplateEntity } from '@mj-biz-apps/contracts-entities';
import { GuardedDelete, plural } from './delete-guard.js';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Templates')
export class ContractTemplateEntityServer extends mjBizAppsContractsContractTemplateEntity {
    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        return GuardedDelete(
            this,
            options,
            `Template "${this.Name ?? this.ID}" cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contracts',
                    Filter: `ContractTemplateID = '${this.ID}'`,
                    Describe: (n) =>
                        `${plural(n, 'contract')} ${n === 1 ? 'incorporates' : 'incorporate'} this version as ` +
                        `${n === 1 ? 'its' : 'their'} standard terms — deleting it would erase what those ` +
                        `customers agreed to. A signed version is a historical record; retire the template's type ` +
                        `instead of deleting the version.`,
                },
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Template Provisions',
                    Filter: `ContractTemplateID = '${this.ID}'`,
                    Describe: (n) => `It also still holds ${plural(n, 'provision')}.`,
                },
            ],
            (o) => super.Delete(o),
        );
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTemplateEntityServer(): void {
    void ContractTemplateEntityServer;
}
