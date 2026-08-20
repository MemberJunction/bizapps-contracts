/**
 * @fileoverview A STOPGAP for [MJ#3969](https://github.com/MemberJunction/MJ/issues/3969) — MJ does
 * not validate value-list fields, so an `IN (…)` CHECK has no TypeScript counterpart at all.
 *
 * ## What is missing upstream
 *
 * When CodeGen meets `CHECK (Status IN ('Active','Inactive'))` it records the legal values as
 * metadata — `EntityField.ValueListType = 'List'` plus `__mj.EntityFieldValue` rows — rather than
 * emitting a generated `Validate()` method. That is the right call: the value list is also what the
 * UI needs to render a dropdown, and one representation beats two.
 *
 * But `BaseEntity` then never reads it. `EntityField.Validate()` checks nullability, `MaxLength`,
 * date parseability and numeric range, and stops. So this class of constraint is the one kind of
 * schema rule with **no representation in TypeScript at all**: neither the browser nor a server
 * subclass can preflight it, and an out-of-list value is refused only by SQL Server, as a raw
 * constraint violation with no field attached.
 *
 * ## Why the dropdown is not the answer
 *
 * It protects the *form* path, which is presumably why nobody noticed. Every other path is
 * unguarded — `mj sync push`, the GraphQL mutations, an Action, a subclass assigning the field in
 * code, a data load — and those are precisely the paths where a typo is least likely to pass a human
 * first.
 *
 * ## Why this is generic rather than three hand-written checks
 *
 * Three fields need it today (`ContractType.Status`, `ContractTemplateType.Status`,
 * `ContractTemplateType.Status`). Naming them here would mean a fourth value-list field added next
 * year is silently unguarded, and nothing would fail to say so. Driving off `ValueListTypeEnum`
 * instead means the guard covers whatever the schema declares, now and later, and needs no edit when
 * the schema changes — which is the same reason the rules it stands in for belong in MJ core.
 *
 * ## Deleting this
 *
 * When MJ#3969 lands, delete this file, drop the `ValidateValueLists(result)` call from every shared
 * subclass, and delete `value-list-validation.test.ts`. Nothing else references it. The upstream fix
 * produces the same errors from the same metadata, so the only observable change should be that the
 * message is worded by MJ rather than by us.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, EntityFieldValueListType, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';

/**
 * Reject any value-list field whose value is not in its list.
 *
 * Call it from a shared subclass's `Validate()` override, after `super.Validate()`.
 *
 * Three exclusions, each of which would otherwise turn this from a guard into a bug:
 *
 * 1. **`List` only — never `ListOrUserEntry`.** That second mode exists precisely to allow values
 *    outside the list; validating it would reject the very thing it was chosen to permit.
 * 2. **An empty value set validates nothing.** A field marked `List` whose `EntityFieldValue` rows
 *    have not been seeded would otherwise reject every value including the correct one, which is a
 *    far worse failure than the one this prevents.
 * 3. **Null and empty are left alone.** Whether the field may be empty is the nullability check's
 *    question, and it has already answered it by the time this runs. Answering it again would report
 *    one mistake as two errors.
 *
 * Read-only and virtual fields are skipped for the same reason `EntityField.Validate()` skips them:
 * the caller cannot set them, so refusing a save over one is a dead end with no fix available.
 *
 * The message lists the legal values rather than merely saying the value is invalid — a refusal that
 * does not say what would have been accepted sends the user back to guess.
 *
 * @param entity - The record being validated.
 * @param result - The accumulating result; errors are pushed onto it and `Success` cleared.
 */
export function ValidateValueLists(entity: BaseEntity, result: ValidationResult): void {
    for (const field of entity.Fields) {
        const info = field.EntityFieldInfo;
        if (info.ReadOnly || info.IsVirtual) continue;
        if (info.ValueListTypeEnum !== EntityFieldValueListType.List) continue;

        const allowed = info.EntityFieldValues;
        if (!allowed || allowed.length === 0) continue;

        const value = field.Value;
        if (value === null || value === undefined || value === '') continue;

        if (allowed.some((candidate) => candidate.Value === value)) continue;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                info.Name,
                `${info.DisplayNameOrName} must be one of: ${allowed.map((candidate) => candidate.Value).join(', ')}. ` +
                    `"${String(value)}" is not one of them.`,
                value,
                ValidationErrorType.Failure,
            ),
        );
    }
}
