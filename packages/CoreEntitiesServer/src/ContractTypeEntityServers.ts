/**
 * @fileoverview The two lookup types' delete guards — and the usability trap they close.
 *
 * The Configuration page tells people to retire a type by setting `Status = 'Inactive'`, and the grid
 * then offers Delete anyway with no explanation of why it fails. So the refusal here does more than
 * name the blocker: it says what to do instead, because the user has already been told the right
 * answer somewhere they are not currently looking.
 *
 * This is the pair R-5 completes. R-5 stops a retired type being newly SELECTED; these stop it being
 * DELETED. Between them, "retire" is a coherent operation: existing records keep working, new ones
 * cannot choose it, and nobody has to delete anything.
 *
 * TWO CLASSES IN ONE FILE, matching `ContractTypeEntity.ts` on the shared side: they are the same rule
 * on the two lookup tables, and splitting them would put four lines in each of two files.
 *
 * BOTH EXTEND THE SHARED CLASS, NOT THE GENERATED ONE, and that is load-bearing rather than tidy.
 * `@RegisterClass` resolves last-registered-wins. The shared `ContractTypeEntity` registers for the
 * same key, so if both extended the generated class they would be SIBLINGS: the winner would not
 * inherit the loser, it would replace it, and `ContractTypeEntity.Validate` -- the whole reason that
 * class exists, running `ValidateValueLists` for a CHECK constraint `BaseEntity` cannot see
 * (MJ#3969) -- would simply not run on the server. It did not, until this commit. MJAPI had been
 * printing the collision at every boot.
 *
 * Nothing failed loudly, which is why it lasted: the database still refuses a bad `Status`, at the
 * very end, as a constraint violation naming no field -- exactly the round trip the shared subclass
 * was written to prevent. `server-extends-shared.test.ts` now asserts the chain for all six entities
 * rather than for the two that were wrong.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity, type EntityDeleteOptions } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractTemplateTypeEntity, ContractTypeEntity } from '@mj-biz-apps/contracts-entities';
import { GuardedDelete, plural } from './delete-guard.js';

/** How to retire instead of deleting — the same advice in both messages, written once. */
const RETIRE_INSTEAD = `Retiring is what you want: set Status to Inactive, which stops it being offered for new records and leaves the existing ones working.`;

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Types')
export class ContractTypeEntityServer extends ContractTypeEntity {
    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        return GuardedDelete(
            this,
            options,
            `Contract type "${this.Name ?? this.ID}" cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contracts',
                    Filter: `ContractTypeID = '${this.ID}'`,
                    Describe: (n) => `${plural(n, 'contract')} ${n === 1 ? 'is' : 'are'} of this type. ${RETIRE_INSTEAD}`,
                },
            ],
            (o) => super.Delete(o),
        );
    }
}

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Types')
export class ContractTemplateTypeEntityServer extends ContractTemplateTypeEntity {
    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        return GuardedDelete(
            this,
            options,
            `Template type "${this.Name ?? this.ID}" cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Templates',
                    Filter: `ContractTemplateTypeID = '${this.ID}'`,
                    Describe: (n) => `${plural(n, 'template')} ${n === 1 ? 'is' : 'are'} of this type. ${RETIRE_INSTEAD}`,
                },
            ],
            (o) => super.Delete(o),
        );
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTypeEntityServers(): void {
    void ContractTypeEntityServer;
    void ContractTemplateTypeEntityServer;
}
