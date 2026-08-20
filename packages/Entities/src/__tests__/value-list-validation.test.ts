/**
 * The value-list guard — the stopgap for MJ#3969.
 *
 * This exercises the REAL `ValidateValueLists`, not a restatement of it: the function reads only
 * `entity.Fields[].EntityFieldInfo` and `.Value`, so a duck-typed record is enough and no provider or
 * database is involved. That matters here more than usual — three of the six cases below are
 * EXCLUSIONS, and an exclusion is exactly the kind of rule a restatement would quietly get right in
 * the test and wrong in the code.
 *
 * The exclusions are the point. A guard that rejects too much is worse than the gap it fills:
 * validating `ListOrUserEntry` would reject the free text that mode exists to allow, and validating
 * against an unseeded value set would reject every value including the correct one.
 */
import { describe, expect, it } from 'vitest';
import { BaseEntity, ValidationResult } from '@memberjunction/core';
import { ValidateValueLists } from '../value-list-validation';

interface FakeFieldSpec {
    Name: string;
    Value: unknown;
    ValueListTypeEnum?: string;
    values?: string[];
    ReadOnly?: boolean;
    IsVirtual?: boolean;
    DisplayName?: string;
}

/** A record shaped as much of `BaseEntity` as the guard actually touches. */
function record(...specs: FakeFieldSpec[]): BaseEntity {
    return {
        Fields: specs.map((spec) => ({
            Value: spec.Value,
            EntityFieldInfo: {
                Name: spec.Name,
                DisplayNameOrName: spec.DisplayName ?? spec.Name,
                ValueListTypeEnum: spec.ValueListTypeEnum ?? 'List',
                EntityFieldValues: (spec.values ?? []).map((v) => ({ Value: v })),
                ReadOnly: spec.ReadOnly ?? false,
                IsVirtual: spec.IsVirtual ?? false,
            },
        })),
    } as unknown as BaseEntity;
}

function validate(entity: BaseEntity): ValidationResult {
    const result = new ValidationResult();
    result.Success = true;
    ValidateValueLists(entity, result);
    return result;
}

describe('ValidateValueLists', () => {
    it('refuses a value outside the list, on the field, naming what is allowed', () => {
        const result = validate(
            record({ Name: 'Status', DisplayName: 'Status', Value: 'Archived', values: ['Active', 'Inactive'] }),
        );

        expect(result.Success).toBe(false);
        expect(result.Errors).toHaveLength(1);
        expect(result.Errors[0].Source).toBe('Status');
        expect(result.Errors[0].Message).toContain('Active, Inactive');
        expect(result.Errors[0].Message).toContain('Archived');
    });

    it('accepts a value in the list', () => {
        const result = validate(record({ Name: 'Status', Value: 'Active', values: ['Active', 'Inactive'] }));

        expect(result.Success).toBe(true);
        expect(result.Errors).toHaveLength(0);
    });

    it('ignores ListOrUserEntry, whose whole purpose is to allow values outside the list', () => {
        const result = validate(
            record({ Name: 'Category', Value: 'Something bespoke', ValueListTypeEnum: 'ListOrUserEntry', values: ['A', 'B'] }),
        );

        expect(result.Success).toBe(true);
    });

    it('ignores a List field whose value set has not been seeded, rather than rejecting everything', () => {
        const result = validate(record({ Name: 'Status', Value: 'Active', values: [] }));

        expect(result.Success).toBe(true);
    });

    it('leaves null and empty to the nullability check, so one mistake is one error', () => {
        const result = validate(
            record(
                { Name: 'Status', Value: null, values: ['Active'] },
                { Name: 'ParentStatusRequirement', Value: undefined, values: ['Required', 'Prohibited'] },
                { Name: 'Other', Value: '', values: ['Active'] },
            ),
        );

        expect(result.Success).toBe(true);
        expect(result.Errors).toHaveLength(0);
    });

    it('skips read-only and virtual fields, which the caller cannot fix', () => {
        const result = validate(
            record(
                { Name: 'DerivedStatus', Value: 'Nonsense', values: ['Active'], ReadOnly: true },
                { Name: 'State', Value: 'Nonsense', values: ['Active'], IsVirtual: true },
            ),
        );

        expect(result.Success).toBe(true);
    });

    it('reports every offending field, not just the first', () => {
        const result = validate(
            record(
                { Name: 'Status', Value: 'Archived', values: ['Active', 'Inactive'] },
                { Name: 'ParentStatusRequirement', Value: 'Optional', values: ['Required', 'Prohibited'] },
            ),
        );

        expect(result.Errors.map((e) => e.Source)).toEqual(['Status', 'ParentStatusRequirement']);
    });
});
