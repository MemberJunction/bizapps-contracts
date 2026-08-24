/**
 * @fileoverview `ContractTemplateEntity` — the publication lifecycle, and the one rule that makes it
 * mean anything.
 *
 * A template version is either a **Draft** (freely editable, not referenceable) or **Published**
 * (frozen, referenceable). The freeze itself is enforced by
 * `trg_ContractTemplateProvision_Immutability` against INSERT, UPDATE and DELETE on its provisions —
 * a trigger, because rewriting signed terms is the case where a bypass is silent corruption rather
 * than a bad edit in our own UI.
 *
 * WHAT LIVES HERE IS THE TRANSITION RULE, which the trigger cannot see: **publishing is one-way.**
 * Without it the freeze is decorative — anyone wanting to edit a published version would flip
 * `Status` back to Draft, edit, and flip it forward again, and every guarantee above evaporates. To
 * change published terms you publish a NEW VERSION, which is what `VersionLabel` and `IntroducedDate`
 * exist for.
 *
 * WHY NOT A CHECK CONSTRAINT: a CHECK sees one row's final state, not the transition. "Was Published,
 * is now Draft" is a comparison against `OldValue`, which only the entity layer has.
 *
 * WHY PROVISION-LEVEL DEACTIVATION WAS REJECTED (Marcelo, 2026-08-20), recorded so it is not
 * re-proposed: soft-deleting provisions would build a second, finer-grained versioning system beside
 * the one that already exists, and "what did this customer sign" would degrade from "template T" into
 * "the provisions of T that were active on date X" — a temporal query, which is exactly what
 * versioning avoids. The lifecycle belongs to the VERSION, not to the clause.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import { BaseEntity, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { mjBizAppsContractsContractTemplateEntity } from './generated/entity_subclasses';
import { ValidateValueLists } from './value-list-validation';

/** The published state — the string the `IN (...)` CHECK constrains `Status` to. */
export const TEMPLATE_PUBLISHED = 'Published';
/** The editable state, and the default for a new version. */
export const TEMPLATE_DRAFT = 'Draft';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Templates')
export class ContractTemplateEntity extends mjBizAppsContractsContractTemplateEntity {
    public override Validate(): ValidationResult {
        const result = super.Validate();
        // Status is an exhaustive value list with no generated validator — MJ never checks list
        // membership (MJ#3969), so the generic stopgap covers it like the other lookup columns.
        ValidateValueLists(this, result);
        this.refuseUnpublishing(result);
        return result;
    }

    /**
     * Publishing is one-way: `Published` never returns to `Draft`.
     *
     * Compared against `OldValue` rather than probing anything, so it costs nothing and works on a
     * record composed in the browser. Only fires on a SAVED record: a new version is legitimately
     * created as a Draft, and there is no previous state to have been published.
     */
    private refuseUnpublishing(result: ValidationResult): void {
        if (!this.IsSaved) return;
        const field = this.GetFieldByName('Status');
        if (!field) return;
        const was = String(field.OldValue ?? '');
        const now = String(field.Value ?? '');
        if (was !== TEMPLATE_PUBLISHED || now === TEMPLATE_PUBLISHED) return;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                `"${this.Name ?? this.ID}" is published and cannot be returned to draft. Contracts may already ` +
                    `incorporate its terms, and un-publishing would let those terms be edited underneath them. ` +
                    `Create a new version of this agreement instead — that is what versioning is for.`,
                now,
                ValidationErrorType.Failure,
            ),
        );
    }
}

/**
 * Anti-tree-shake anchor. Importing this module is what fires `@RegisterClass`; a dropped registration
 * would silently make publishing reversible, with nothing failing.
 */
export function LoadContractTemplateEntity(): void {
    void ContractTemplateEntity;
}
