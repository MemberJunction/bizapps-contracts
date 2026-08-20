/**
 * @fileoverview `ContractTemplateEntityServer` — deleting an agreement version.
 *
 * A template version is a HISTORICAL RECORD: a customer who signed in June 2026 stays bound to the
 * June 2026 version, so the version never goes away. Deleting one that contracts incorporate would
 * erase what those customers actually agreed to. Retiring is a `Status` change on the template's TYPE,
 * not a delete.
 *
 * Both dependencies are reported, not just the first: a template almost always has provisions AND
 * contracts, and being refused twice in a row for two different reasons is the worst version of this.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import {
    BaseEntity,
    type EntityDeleteOptions,
    ValidationErrorInfo,
    ValidationErrorType,
    ValidationResult,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractTemplateEntity, TEMPLATE_PUBLISHED } from '@mj-biz-apps/contracts-entities';
import { GuardedDelete, plural } from './delete-guard.js';

/* Extends the SHARED subclass so the one-way-publish rule and the value-list guard reach an API
 * caller too, not just a browser. Same reason `ContractEntityServer extends ContractEntity`. */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Templates')
export class ContractTemplateEntityServer extends ContractTemplateEntity {
    /**
     * PUBLISHING REQUIRES A READABLE VERSION.
     *
     * Publishing is the moment a version stops being editable and starts being referenceable, so it is
     * the right and only moment to insist the standard terms can actually be read. R-12's `IsUsable`
     * says whether they can: a `SourceURL`, or a file linked through `__mj.FileEntityRecordLink`.
     *
     * WHY THIS IS NOT `this.IsUsable`. That field is derived in the view and reflects what was LOADED,
     * so a save that sets `SourceURL` and `Status = 'Published'` together would be judged on the old
     * value and wrongly refused. The URL half is therefore read from the in-memory field and only the
     * file half costs a query — and only when the URL is absent and the record is actually being
     * published, so an ordinary save pays nothing.
     *
     * Server-side because the file half is a cross-entity read the browser has no business doing.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();

        const statusField = this.GetFieldByName('Status');
        const publishingNow =
            String(statusField?.Value ?? '') === TEMPLATE_PUBLISHED &&
            String(statusField?.OldValue ?? '') !== TEMPLATE_PUBLISHED;
        if (!publishingNow) return result;

        const hasUrl = String(this.SourceURL ?? '').trim().length > 0;
        if (hasUrl || (await this.hasLinkedDocument())) return result;

        result.Success = false;
        result.Errors.push(
            new ValidationErrorInfo(
                'Status',
                `"${this.Name ?? this.ID}" cannot be published: it records no source URL and has no attached ` +
                    `document, so nobody could read the terms it names. Publishing makes a version referenceable ` +
                    `and freezes it, so this is the moment it has to be readable. Add a URL or attach the ` +
                    `agreement document first.`,
                TEMPLATE_PUBLISHED,
                ValidationErrorType.Failure,
            ),
        );
        return result;
    }

    /** Whether a file is attached to this template — the other half of R-12's `IsUsable`. */
    private async hasLinkedDocument(): Promise<boolean> {
        const result = await this.RunViewProviderToUse.RunView(
            {
                EntityName: 'MJ: File Entity Record Links',
                ExtraFilter:
                    `EntityID = (SELECT ID FROM __mj.Entity WHERE Name = 'MJ_BizApps_Contracts: Contract Templates') ` +
                    `AND RecordID = '${this.ID}'`,
                ResultType: 'count_only',
            },
            this.ContextCurrentUser,
        );
        if (!result?.Success) {
            throw new Error(
                `Could not check whether a document is attached to this agreement version: ` +
                    `${result?.ErrorMessage ?? 'unknown error'}. Publishing was not attempted.`,
            );
        }
        return (result.TotalRowCount ?? 0) > 0;
    }

    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        return GuardedDelete(
            this,
            options,
            `Template "${this.Name ?? this.ID}" cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contracts',
                    Filter: `ContractTemplateID = '${this.ID}'`,
                    Describe: (n) =>
                        `${plural(n, 'contract')} ${n === 1 ? 'incorporates' : 'incorporate'} this version as ` +
                        `${n === 1 ? 'its' : 'their'} standard terms — deleting it would erase what those ` +
                        `customers agreed to. A signed version is a historical record; retire the template's type ` +
                        `instead of deleting the version.`,
                },
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Template Provisions',
                    Filter: `ContractTemplateID = '${this.ID}'`,
                    Describe: (n) => `It also still holds ${plural(n, 'provision')}.`,
                },
            ],
            (o) => super.Delete(o),
        );
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTemplateEntityServer(): void {
    void ContractTemplateEntityServer;
}
