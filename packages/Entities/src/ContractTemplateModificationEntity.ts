/**
 * @fileoverview `ContractTemplateModificationEntity` — the SHARED subclass, and it exists for exactly
 * one reason: the three fields a modification cannot do without refuse in prose nobody can act on.
 *
 * IT ADDS NO RULE. That distinction is the whole design, and getting it wrong here is a known trap
 * (R-2 of `plans/backend-requirements.md`, withdrawn because implementing it would have produced a
 * second copy of four working generated rules). `ContractID`, `ContractTemplateProvisionID` and — as
 * of V202608192340 — `ModificationText` are all NOT NULL in the database, so MJ's own
 * `EntityField.Validate()` already refuses an empty one and already names the field. The rule is the
 * metadata; restating it in TypeScript would give one fact two owners and let them drift the next
 * time a column's nullability changes.
 *
 * What MJ cannot know is what the user should DO about it. Its message is
 * `` `${DisplayNameOrName} cannot be null` `` (`baseEntity.ts:320`) — correct, field-named, and mute
 * on the only question the person in front of the form is asking. "Contract Template Provision
 * cannot be null" does not tell anyone to pick a clause. So this class REPLACES those three messages
 * and adds none.
 *
 * The mechanism — replace rather than append, collapse the duplicate absence errors, match on
 * emptiness rather than on MJ's wording — lives in `required-field-prose.ts`, shared with provisions.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTemplateModificationEntity } from './generated/entity_subclasses';
import { ExplainMissingRequiredFields } from './required-field-prose';

/**
 * The prose each required field gets instead of "<Display Name> cannot be null".
 *
 * Each one says what to do, not what is wrong. `ContractID` is the odd member and is included
 * deliberately: a user never sets it — MJ stamps it from the parent before validating
 * (`relatedRecordCollection.ts`, `stampParentKey()` ahead of the child's `Validate()`), so inside the
 * modification editor it cannot be empty. It can only be empty on the standalone form or an API
 * call, which is precisely where "Contract cannot be null" is least useful, because the caller has to
 * be told that a modification is meaningless without the contract it belongs to.
 */
export const MODIFICATION_REQUIRED_FIELD_PROSE: Readonly<Record<string, string>> = {
    ContractID:
        'A modification records what one specific contract negotiated, so it cannot exist on its own — ' +
        'choose the contract this deviation belongs to.',
    ContractTemplateProvisionID:
        'Choose the standard provision this modification changes. The negotiated wording is only ' +
        'meaningful beside the clause it replaces.',
    ModificationText:
        'Record what this contract says instead of the standard clause. A modification that does not ' +
        'say what was agreed asserts that the paper differs without saying how, which is the one ' +
        'state this record cannot usefully be in.',
};

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Modifications')
export class ContractTemplateModificationEntity extends mjBizAppsContractsContractTemplateModificationEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        ExplainMissingRequiredFields(this, result, MODIFICATION_REQUIRED_FIELD_PROSE);
        return result;
    }
}

/**
 * Anti-tree-shake anchor. Importing this module is what fires `@RegisterClass`; a production build can
 * drop an import whose class is never referenced, and a dropped registration would silently restore
 * MJ's flat messages with nothing failing — the same reason `LoadContractEntity` exists.
 */
export function LoadContractTemplateModificationEntity(): void {
    void ContractTemplateModificationEntity;
}
