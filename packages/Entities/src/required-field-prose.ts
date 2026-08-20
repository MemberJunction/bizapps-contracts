/**
 * @fileoverview Replacing MJ's flat "<field> cannot be null" with a sentence that says what to do.
 *
 * ADDS NO RULE — that distinction is the whole design, and getting it wrong here is a known trap
 * (R-2 of `plans/backend-requirements.md`, withdrawn because implementing it would have produced a
 * second copy of four working generated rules). Every field named by a prose map is already required
 * at the database, and MJ's `EntityField.Validate()` plus CodeGen's CHECK-derived validators already
 * refuse an empty one and already name the field. The rule is the metadata and the constraints;
 * restating it in TypeScript would give one fact two owners.
 *
 * What MJ cannot know is what the user should DO about it. Its message is
 * `` `${DisplayNameOrName} cannot be null` `` (`baseEntity.ts:320`) — correct, field-named, and mute on
 * the only question the person in front of the form is asking.
 *
 * WHY THIS IS ITS OWN MODULE. It started life inside `ContractTemplateModificationEntity`. Provisions
 * then needed exactly the same treatment (`ProvisionText` became required in V202608200800), which is
 * the second caller of somewhat-subtle logic that has to change together — the point at which
 * ORCHESTRATION.md's reuse test says bring it together rather than copy it. The prose maps stay with
 * their entities, because the sentences are domain knowledge; the mechanism lives here.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationErrorInfo, ValidationResult } from '@memberjunction/core';

/** Field name → the sentence that replaces MJ's flat one. */
export type RequiredFieldProse = Readonly<Record<string, string>>;

/**
 * Swap the flat nullability prose for something actionable, and collapse duplicates, in place.
 *
 * WHY REPLACE AND NOT APPEND. One mistake must produce one error. Appending would leave the flat
 * message beside the useful one, so a single empty field would mark itself twice.
 *
 * WHY COLLAPSE. A required field with a not-blank CHECK genuinely produces TWO absence errors on a
 * create, and both are correct: MJ's nullability check refuses the null, and CodeGen's generated
 * validator — derived from the CHECK — refuses null, empty AND whitespace, because the CHECK has to
 * cover all three. Two rungs of the ladder saying the same thing about the same field; the user needs
 * to be told once.
 *
 * WHY MATCH ON EMPTINESS RATHER THAN ON MJ'S WORDING. The obvious implementation greps the message
 * text, which couples this to a string in MJ core it does not own and cannot see change. Matching on
 * `Source` plus "the value really is absent" is stable across any rewording, and cannot capture the
 * wrong error: the only other check MJ runs on these fields is `MaxLength`, which by construction
 * fires only when a value is present.
 *
 * `result.Success` is deliberately not recomputed. Rewording cannot change a verdict, and collapsing
 * cannot either — dropping a duplicate leaves at least one error standing for the same field.
 */
export function ExplainMissingRequiredFields(entity: BaseEntity, result: ValidationResult, prose: RequiredFieldProse): void {
    const explained = new Set<string>();
    const kept: ValidationErrorInfo[] = [];

    for (const error of result.Errors) {
        const source = error.Source ?? '';
        const sentence = prose[source];
        if (!sentence || !fieldIsAbsent(entity, source)) {
            kept.push(error);
            continue;
        }
        if (explained.has(source)) continue;
        explained.add(source);
        error.Message = sentence;
        kept.push(error);
    }

    result.Errors = kept;
}

/**
 * Whether the named field is genuinely empty — the condition MJ's nullability check fires on, plus the
 * blank-string case, which is what the app's `…_TextNotBlank` CHECK constraints add.
 *
 * A field the entity does not have returns FALSE, not true. That direction matters: an unknown field
 * name means a prose map has drifted from the schema, and rewording an error for a field that does not
 * exist would hide the drift behind a friendly sentence.
 */
function fieldIsAbsent(entity: BaseEntity, fieldName: string): boolean {
    const field = entity.Fields.find((f) => f.EntityFieldInfo.Name === fieldName);
    if (!field) return false;
    const value: unknown = field.Value;
    return value === null || value === undefined || (typeof value === 'string' && value.trim().length === 0);
}
