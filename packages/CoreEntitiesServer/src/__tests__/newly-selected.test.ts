/**
 * `IsNewlySelected` — the predicate R-5 turns on, and the one place this app deliberately does NOT
 * copy `bizapps-accounting`.
 *
 * R-5's rule is about the EDIT, not the row: choosing a retired contract type is refused, while a
 * contract that already references one keeps saving forever. Everything therefore rests on what
 * "newly selected" means, and there are exactly three cases — two of which are easy to get backwards:
 *
 *   NEW record, key set          -> new selection.   (a create IS the newest selection there is)
 *   SAVED record, key changed    -> new selection.
 *   SAVED record, key unchanged  -> NOT a new selection, whatever the referenced row now says.
 *
 * `GLAccountEntityServer`'s identity lock returns early when `OldValue` is null — right for asking
 * "did an existing value change", wrong here, because it would skip every create. Copying that shape
 * would have produced a rule that passes review, passes a build, and never fires on the case the
 * Configuration page actually promises ("a retired type stops being offered for new contracts").
 *
 * Exercises the real function against a duck-typed record — it reads only `IsSaved` and
 * `GetFieldByName`, so no provider and no database. Same technique as `value-list-validation.test.ts`.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity } from '@memberjunction/core';
import { IsNewlySelected } from '../ContractEntityServer.js';

/** As much of `BaseEntity` as the predicate touches. */
function record(isSaved: boolean, fields: Record<string, { OldValue: unknown; Value: unknown }>): BaseEntity {
    return {
        IsSaved: isSaved,
        GetFieldByName: (name: string) => fields[name],
    } as unknown as BaseEntity;
}

const UPPER = 'A1B2C3D4-0000-4000-8000-000000000001';
const lower = UPPER.toLowerCase();

describe('IsNewlySelected', () => {
    it('a NEW record naming the type is a new selection — the case accounting\'s shape would skip', () => {
        expect(IsNewlySelected(record(false, { ContractTypeID: { OldValue: null, Value: UPPER } }), 'ContractTypeID')).toBe(true);
    });

    it('a new record is a new selection even with nothing to compare against', () => {
        // No field entry at all: an unsaved record has no old values to read.
        expect(IsNewlySelected(record(false, {}), 'ContractTypeID')).toBe(true);
    });

    it('a SAVED record whose key changed is a new selection', () => {
        const r = record(true, { ContractTypeID: { OldValue: 'old-id', Value: 'new-id' } });
        expect(IsNewlySelected(r, 'ContractTypeID')).toBe(true);
    });

    it('a SAVED record whose key did not change is NOT a new selection', () => {
        // THE non-regression that matters: this is every save of every existing contract. If this
        // returned true, retiring a lookup row would break saves on the contracts already using it.
        const r = record(true, { ContractTypeID: { OldValue: UPPER, Value: UPPER } });
        expect(IsNewlySelected(r, 'ContractTypeID')).toBe(false);
    });

    it('UUID CASING is not a change', () => {
        // MJ hands UUIDs back in either casing depending on how the record was loaded. A `!==` here
        // would report a change on a record nobody touched, refusing a perfectly legal save.
        const r = record(true, { ContractTypeID: { OldValue: UPPER, Value: lower } });
        expect(IsNewlySelected(r, 'ContractTypeID')).toBe(false);
    });

    it('clearing an optional key counts as a change', () => {
        // Clearing ContractTemplateID is a real edit. R-5 then finds no value and does not fire, but
        // the predicate must not lie about what happened.
        const r = record(true, { ContractTemplateID: { OldValue: UPPER, Value: null } });
        expect(IsNewlySelected(r, 'ContractTemplateID')).toBe(true);
    });

    it('setting a key that was empty counts as a change', () => {
        const r = record(true, { ContractTemplateID: { OldValue: null, Value: UPPER } });
        expect(IsNewlySelected(r, 'ContractTemplateID')).toBe(true);
    });

    it('null and undefined and empty string are the same absence', () => {
        expect(IsNewlySelected(record(true, { X: { OldValue: null, Value: undefined } }), 'X')).toBe(false);
        expect(IsNewlySelected(record(true, { X: { OldValue: undefined, Value: '' } }), 'X')).toBe(false);
    });

    it('a field the entity does not have is not a new selection', () => {
        // Fail closed rather than refusing a save over a field name that has drifted.
        expect(IsNewlySelected(record(true, {}), 'NoSuchField')).toBe(false);
    });
});
