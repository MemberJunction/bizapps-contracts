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
 * WHY REPLACE AND NOT APPEND. One mistake must produce one error. Appending would leave the flat
 * message beside the useful one, so a single empty field would mark itself twice and the form would
 * show a banner of duplicates — the same reasoning that makes `ValidateValueLists` leave null alone
 * and defer to the nullability rung.
 *
 * WHY MATCH ON EMPTINESS RATHER THAN ON MJ'S WORDING. The obvious implementation greps the message
 * text, which couples this file to a string in MJ core that it does not own and cannot see change.
 * Matching on `Source` plus "the value really is absent" is stable across any rewording, and it
 * cannot capture the wrong error: the only other check MJ runs on these fields is `MaxLength`, which
 * by construction fires only when a value is present.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationErrorInfo, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTemplateModificationEntity } from './generated/entity_subclasses';

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

/**
 * Swap MJ's flat nullability prose for something actionable, in place.
 *
 * A FREE FUNCTION over the entity, not a private method, and for the reason `ValidateValueLists` is
 * one: it reads only `entity.Fields[].Value` and the errors already in hand, so a duck-typed record
 * is enough to test the REAL code. A private method would need a provider to instantiate, which would
 * push a pure-logic rule into the tier that costs a database — and the alternative, a restatement of
 * the logic in the test, is exactly how an exclusion gets tested right and implemented wrong.
 *
 * It REWORDS in place and COLLAPSES duplicates. The surviving `ValidationErrorInfo` objects are
 * mutated rather than rebuilt, so `Source`, `Value` and `Type` are untouched and relative order is
 * preserved — the form marks the same field in the same place, and only the sentence changes. The
 * array itself is rebuilt only to DROP the second and later absence errors for one field (see the
 * comment at the collapse), never to reorder or replace what stays.
 *
 * `result.Success` is deliberately not recomputed. Rewording cannot change a verdict, and collapsing
 * cannot either — dropping a duplicate leaves at least one error standing for the same field, so a
 * failing result still fails. A function about how a refusal READS has no business deciding whether a
 * save proceeds.
 */
export function ExplainMissingRequiredFields(entity: BaseEntity, result: ValidationResult): void {
    const explained = new Set<string>();
    const kept: ValidationErrorInfo[] = [];

    for (const error of result.Errors) {
        const source = error.Source ?? '';
        const prose = MODIFICATION_REQUIRED_FIELD_PROSE[source];
        if (!prose || !fieldIsAbsent(entity, source)) {
            kept.push(error);
            continue;
        }
        // COLLAPSE. `ModificationText` genuinely produces TWO absence errors on a create, and both
        // are correct: MJ's nullability check refuses the null, and CodeGen's generated
        // `ValidateModificationTextNotEmpty` -- derived from CK_ContractTemplateModification_TextNotBlank
        // -- refuses null, empty AND whitespace, because the CHECK has to cover all three. Neither is
        // wrong and neither should be removed at its source; they are two rungs of the ladder saying
        // the same thing about the same field, and the user needs to be told once.
        if (explained.has(source)) continue;
        explained.add(source);
        error.Message = prose;
        kept.push(error);
    }

    result.Errors = kept;
}

/**
 * Whether the named field is genuinely empty — the condition MJ's nullability check fires on, plus the
 * blank-string case.
 *
 * A whitespace-only `ModificationText` passes MJ's null check and passes the database's NOT NULL, so
 * it is not what produced the error being reworded; it is accepted here anyway because it is the same
 * user mistake, and if a future rule rejects blank text this predicate is already right.
 *
 * A field the entity does not have returns FALSE, not true. That direction matters: an unknown field
 * name means this map has drifted from the schema, and rewording an error for a field that does not
 * exist would hide the drift behind a friendly sentence.
 */
function fieldIsAbsent(entity: BaseEntity, fieldName: string): boolean {
    const field = entity.Fields.find((f) => f.EntityFieldInfo.Name === fieldName);
    if (!field) return false;
    const value: unknown = field.Value;
    return value === null || value === undefined || (typeof value === 'string' && value.trim().length === 0);
}

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Modifications')
export class ContractTemplateModificationEntity extends mjBizAppsContractsContractTemplateModificationEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        ExplainMissingRequiredFields(this, result);
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
