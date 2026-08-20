/**
 * @fileoverview `ContractTemplateProvisionEntity` — the SHARED subclass, and like the modification's
 * it exists for one reason: the fields a provision cannot do without refuse in prose nobody can act on.
 *
 * IT ADDS NO RULE. `ContractTemplateID`, `ProvisionNumber`, `Title` and — as of V202608200800 —
 * `ProvisionText` are all required at the database, the last two of them via
 * `CK_ContractTemplateProvision_TextNotBlank` on top of `NOT NULL` (because `NOT NULL` accepts `''`;
 * see the migration). MJ and CodeGen already refuse an empty one and already name the field. Only the
 * sentence changes here.
 *
 * WHY `ProvisionText` MATTERS MORE THAN IT LOOKS. A provision is the STANDARD wording of a clause, and
 * a `ContractTemplateModification` is only meaningful read as a PAIR against it — a dispute needs the
 * comparison, not either half. A provision with no text is therefore worse than a modification with
 * no text: every modification pointing at it inherits the gap, and the contract still renders.
 *
 * SERVER RULES ARE NOT HERE. Provision immutability once a contract references the template (R-1) and
 * the delete guards (R-8) need cross-entity reads, so they live on
 * `ContractTemplateProvisionEntityServer`. What is here is what a browser can preflight.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTemplateProvisionEntity } from './generated/entity_subclasses';
import { ExplainMissingRequiredFields } from './required-field-prose';

/**
 * The prose each required field gets instead of "<Display Name> cannot be null".
 *
 * `ContractTemplateID` is included for the same reason `ContractID` is on the modification: a user
 * never sets it inside the template form — MJ stamps it from the parent before validating — so it can
 * only be empty on the standalone form or an API call, which is exactly where the flat message helps
 * least.
 *
 * `ProvisionSortKey` is deliberately ABSENT. It is a persisted computed column and read-only, so it
 * cannot be missing and cannot be set; naming it here would describe a failure that cannot happen.
 */
export const PROVISION_REQUIRED_FIELD_PROSE: Readonly<Record<string, string>> = {
    ContractTemplateID:
        'A provision is a clause OF an agreement version, so it cannot stand alone — choose the ' +
        'template this clause belongs to.',
    ProvisionNumber:
        'Give the clause its number as the document states it (for example 1.1, or 2.1A). The number is ' +
        'also what orders the provisions, so a clause without one sorts to the top until it has one.',
    Title:
        'Give the clause a heading, as the document states it. It is what the contract screens show ' +
        'when the full text is collapsed.',
    ProvisionText:
        'Record the standard wording of this clause. A provision with no text leaves every modification ' +
        'that negotiates it comparing against nothing, and the pair — standard beside negotiated — is ' +
        'what a dispute actually needs.',
};

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Provisions')
export class ContractTemplateProvisionEntity extends mjBizAppsContractsContractTemplateProvisionEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        ExplainMissingRequiredFields(this, result, PROVISION_REQUIRED_FIELD_PROSE);
        return result;
    }
}

/**
 * Anti-tree-shake anchor. Importing this module is what fires `@RegisterClass`; a production build can
 * drop an import whose class is never referenced, and a dropped registration would silently restore
 * MJ's flat messages with nothing failing.
 */
export function LoadContractTemplateProvisionEntity(): void {
    void ContractTemplateProvisionEntity;
}
