/**
 * The modification's required-field messages (R-6).
 *
 * This exercises the REAL `ExplainMissingRequiredFields` — the function reads only `entity.Fields[]`
 * and the errors already produced, so a duck-typed record is enough and no provider or database is
 * involved. Same technique, and the same reason, as `value-list-validation.test.ts`.
 *
 * WHAT IS ACTUALLY AT RISK HERE, and why it is worth a test for something that "only changes text":
 * this function mutates errors that MJ produced, in a loop over a shared array. The failure modes are
 * all silent — rewording an error that was not about absence, appending instead of replacing so one
 * empty field reports twice, flipping `Success`, or reordering `Errors` so the form marks a different
 * field. None of those would throw, and none would be visible in a passing build. The prose itself is
 * the least interesting thing below.
 *
 * Written from the intent (replace, exactly once, only for absent required fields, verdict untouched)
 * rather than from the implementation, so it stays a valid oracle if the function is rewritten.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';
import { ExplainMissingRequiredFields, MODIFICATION_REQUIRED_FIELD_PROSE } from '../ContractTemplateModificationEntity';

/** A record shaped as much of `BaseEntity` as the function actually touches. */
function record(fields: Record<string, unknown>): BaseEntity {
    return {
        Fields: Object.entries(fields).map(([Name, Value]) => ({
            Value,
            EntityFieldInfo: { Name, DisplayNameOrName: Name },
        })),
    } as unknown as BaseEntity;
}

/** The error MJ itself produces for a null field — `baseEntity.ts:320`, reproduced exactly. */
function nullError(source: string, displayName: string): ValidationErrorInfo {
    return new ValidationErrorInfo(source, `${displayName} cannot be null`, null, ValidationErrorType.Failure);
}

function resultWith(...errors: ValidationErrorInfo[]): ValidationResult {
    const result = new ValidationResult();
    result.Success = errors.length === 0;
    result.Errors = errors;
    return result;
}

describe('ExplainMissingRequiredFields', () => {
    it('replaces the flat message for a missing provision', () => {
        const entity = record({ ContractID: 'c1', ContractTemplateProvisionID: null, ModificationText: 'x' });
        const result = resultWith(nullError('ContractTemplateProvisionID', 'Contract Template Provision'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0].Message).toBe(MODIFICATION_REQUIRED_FIELD_PROSE.ContractTemplateProvisionID);
        expect(result.Errors[0].Message).not.toContain('cannot be null');
    });

    it('REPLACES rather than appends — one empty field produces exactly one error', () => {
        // The failure this pins: appending would leave MJ's message beside ours, so the form would
        // mark one field twice and show a banner of near-duplicates.
        const entity = record({ ContractID: 'c1', ContractTemplateProvisionID: null, ModificationText: 'x' });
        const result = resultWith(nullError('ContractTemplateProvisionID', 'Contract Template Provision'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors).toHaveLength(1);
    });

    it('rewords every missing required field, and leaves the order alone', () => {
        const entity = record({ ContractID: null, ContractTemplateProvisionID: null, ModificationText: null });
        const result = resultWith(
            nullError('ContractID', 'Contract'),
            nullError('ContractTemplateProvisionID', 'Contract Template Provision'),
            nullError('ModificationText', 'Modification Text'),
        );

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors.map((e) => e.Source)).toEqual([
            'ContractID',
            'ContractTemplateProvisionID',
            'ModificationText',
        ]);
        expect(result.Errors.map((e) => e.Message)).toEqual([
            MODIFICATION_REQUIRED_FIELD_PROSE.ContractID,
            MODIFICATION_REQUIRED_FIELD_PROSE.ContractTemplateProvisionID,
            MODIFICATION_REQUIRED_FIELD_PROSE.ModificationText,
        ]);
    });

    it('preserves Source, Value and Type — only the sentence changes', () => {
        // The form marks a field by Source and renders severity from Type. Rebuilding the error object
        // instead of mutating it is how those get lost, and nothing downstream would report it.
        const entity = record({ ModificationText: null });
        const original = nullError('ModificationText', 'Modification Text');
        const result = resultWith(original);

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0]).toBe(original);
        expect(result.Errors[0].Source).toBe('ModificationText');
        expect(result.Errors[0].Value).toBeNull();
        expect(result.Errors[0].Type).toBe(ValidationErrorType.Failure);
    });

    it('does not touch the verdict — rewording cannot make a save legal or illegal', () => {
        const entity = record({ ModificationText: null });
        const result = resultWith(nullError('ModificationText', 'Modification Text'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Success).toBe(false);
    });

    it('leaves an error on a field that is PRESENT alone', () => {
        // The MaxLength case. It fires only when a value exists, so rewording it as "you must record
        // what was agreed" would tell someone who wrote too much to write something.
        const entity = record({ ModificationText: 'a'.repeat(50) });
        const tooLong = new ValidationErrorInfo(
            'ModificationText',
            'Modification Text cannot be longer than 10 characters. Current value is 50 characters',
            'a'.repeat(50),
            ValidationErrorType.Failure,
        );
        const result = resultWith(tooLong);

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0].Message).toContain('cannot be longer than');
    });

    it('treats whitespace-only text as absent', () => {
        const entity = record({ ModificationText: '   ' });
        const result = resultWith(nullError('ModificationText', 'Modification Text'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0].Message).toBe(MODIFICATION_REQUIRED_FIELD_PROSE.ModificationText);
    });

    it('leaves errors on fields it knows nothing about', () => {
        const entity = record({ Notes: null });
        const result = resultWith(nullError('Notes', 'Notes'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0].Message).toBe('Notes cannot be null');
    });

    it('leaves the error alone when the field is absent from the record entirely', () => {
        // Drift guard: an entry naming a column the entity does not have means this map and the schema
        // have diverged. Rewording then would hide the drift behind a friendly sentence.
        const entity = record({ ContractID: 'c1' });
        const result = resultWith(nullError('ModificationText', 'Modification Text'));

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors[0].Message).toBe('Modification Text cannot be null');
    });


    it('COLLAPSES the two absence errors ModificationText really produces into one', () => {
        // Not hypothetical. On a create with no text, BOTH fire and both are correct:
        //   · MJ's nullability check           -> "Modification Text cannot be null"
        //   · CodeGen's ValidateModificationTextNotEmpty, derived from
        //     CK_ContractTemplateModification_TextNotBlank -> "... cannot be empty or consist only
        //     of whitespace" (it must cover null too, because the CHECK does).
        // Two rungs of the ladder saying one thing about one field. The user is told once.
        const entity = record({ ModificationText: null });
        const result = resultWith(
            nullError('ModificationText', 'Modification Text'),
            new ValidationErrorInfo(
                'ModificationText',
                'Modification text cannot be empty or consist only of whitespace.',
                null,
                ValidationErrorType.Failure,
            ),
        );

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors).toHaveLength(1);
        expect(result.Errors[0].Message).toBe(MODIFICATION_REQUIRED_FIELD_PROSE.ModificationText);
        expect(result.Errors[0].Source).toBe('ModificationText');
    });

    it('collapsing still leaves the result failing', () => {
        const entity = record({ ModificationText: null });
        const result = resultWith(
            nullError('ModificationText', 'Modification Text'),
            new ValidationErrorInfo('ModificationText', 'blank', null, ValidationErrorType.Failure),
        );

        ExplainMissingRequiredFields(entity, result);

        expect(result.Success).toBe(false);
        expect(result.Errors.length).toBeGreaterThan(0);
    });

    it('collapses per FIELD, not globally — two different empty fields still report twice', () => {
        const entity = record({ ContractID: null, ModificationText: null });
        const result = resultWith(
            nullError('ContractID', 'Contract'),
            nullError('ModificationText', 'Modification Text'),
            new ValidationErrorInfo('ModificationText', 'blank', null, ValidationErrorType.Failure),
        );

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors.map((e) => e.Source)).toEqual(['ContractID', 'ModificationText']);
    });

    it('never drops an error it did not reword', () => {
        // A second error on a PRESENT field, and an error on a field outside the map, both survive —
        // collapsing must not become a general-purpose error filter.
        const entity = record({ ModificationText: 'agreed', Notes: null });
        const a = new ValidationErrorInfo('ModificationText', 'too long', 'agreed', ValidationErrorType.Failure);
        const b = new ValidationErrorInfo('ModificationText', 'something else', 'agreed', ValidationErrorType.Failure);
        const c = nullError('Notes', 'Notes');
        const result = resultWith(a, b, c);

        ExplainMissingRequiredFields(entity, result);

        expect(result.Errors).toEqual([a, b, c]);
    });

    it('does nothing to a clean result', () => {
        const entity = record({ ContractID: 'c1', ContractTemplateProvisionID: 'p1', ModificationText: 'agreed' });
        const result = resultWith();

        ExplainMissingRequiredFields(entity, result);

        expect(result.Success).toBe(true);
        expect(result.Errors).toHaveLength(0);
    });
});

/**
 * The UI-side predicate for R-6, restated here as the CONTRACT it must satisfy.
 *
 * `IsTextMissing` in the modification editor decides whether a row's textarea gets a required marker.
 * It lives in an Angular component, so it is not importable here without pulling in the whole Angular
 * package — but the property that matters is agreement with the DATABASE, and that is testable as a
 * statement about thresholds:
 *
 *   the CHECK is `LEN(LTRIM(RTRIM(ModificationText))) > 0`
 *   the marker must appear for exactly the values that CHECK rejects — no more, no fewer
 *
 * Too strict and the UI flags text the database would accept (a minimum length nobody was told about).
 * Too loose and the marker is absent on a row that will fail at save, which is the gap this closed.
 */
describe('the UI required-marker threshold matches the database CHECK', () => {
    /** What `IsTextMissing` does: `!String(value ?? '').trim()`. */
    const markerShows = (value: unknown) => !String(value ?? '').trim();

    /** What the CHECK does: reject null, and reject when the trimmed length is 0. */
    const databaseRejects = (value: unknown) =>
        value === null || value === undefined || String(value).trim().length === 0;

    const CASES: unknown[] = [null, undefined, '', ' ', '   ', '\t', '\n', 'x', ' x ', 'a full clause', '0'];

    for (const value of CASES) {
        it(`agrees on ${JSON.stringify(value)}`, () => {
            expect(markerShows(value)).toBe(databaseRejects(value));
        });
    }

    it('one character is enough — there is no minimum length', () => {
        // An arbitrary minimum would be a rule the user cannot discover and we cannot justify.
        expect(markerShows('x')).toBe(false);
        expect(databaseRejects('x')).toBe(false);
    });

    it("'0' is text, not emptiness", () => {
        // The falsy-string trap: `!'0'` is false in JS, but a naive `Number()`-based or truthiness
        // check elsewhere could treat it as absent. A clause numbered or worded "0" is real text.
        expect(markerShows('0')).toBe(false);
    });
});
