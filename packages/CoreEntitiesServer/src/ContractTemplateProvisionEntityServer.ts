/**
 * @fileoverview `ContractTemplateProvisionEntityServer` — a signed clause is a historical record.
 *
 * Two rules, both about the same fact: once a contract incorporates a template, that template's
 * provisions are what somebody agreed to.
 *
 *   **R-1** the TERMS (`ProvisionNumber`, `Title`, `ProvisionText`) cannot change, and the provision
 *           cannot be deleted, while any contract references its template.
 *   **R-8** and independently of R-1, a provision cannot be deleted while modifications cite it.
 *
 * ## The trigger is the floor; this class exists for the sentence
 *
 * `trg_ContractTemplateProvision_Immutability` (V202608200100) enforces R-1 against ANY writer — raw
 * SQL, a future service, another app, a data load — because rewriting signed terms is the case where a
 * bypass is silent corruption rather than a bad edit in our own UI. What a trigger cannot do is
 * explain itself: it reaches the user as a raw SQL error naming no field.
 *
 * **That is not a nicety here, it is a correctness requirement for R-8.** R-8's whole point is that a
 * refused delete reads as a sentence instead of a constraint. If this class checked only the
 * modification dependency and let the trigger catch the template-referenced case, then deleting an
 * unmodified provision of a referenced template would sail past the guard and die in the database —
 * producing exactly the raw error R-8 was written to eliminate. So the code half must cover **both**
 * conditions the trigger covers, or the guard has a hole shaped like the trigger.
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
import { ContractTemplateProvisionEntity, TEMPLATE_PUBLISHED } from '@mj-biz-apps/contracts-entities';
import { GuardedDelete, RefuseDelete, plural } from './delete-guard.js';

/**
 * The columns that ARE the terms. `Description` and `Sequence` are deliberately absent: ordering a
 * document and annotating it internally are not changing what it says, so they stay editable on a
 * referenced template. This list must stay in step with the trigger's comparison — the trigger is the
 * floor and a divergence would mean the code permits an edit the database then refuses raw.
 */
const FROZEN_TERM_FIELDS: ReadonlyArray<{ Name: string; Label: string }> = [
    { Name: 'ProvisionNumber', Label: 'the clause number' },
    { Name: 'Title', Label: 'the clause title' },
    { Name: 'ProvisionText', Label: 'the standard wording' },
];

/*
 * EXTENDS THE SHARED SUBCLASS, not the generated one — so an API caller gets the required-field prose
 * too, not just a browser. Same reason `ContractEntityServer extends ContractEntity`.
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Provisions')
export class ContractTemplateProvisionEntityServer extends ContractTemplateProvisionEntity {
    /**
     * R-1 — refuse an edit to the terms of a provision whose template is referenced.
     *
     * Gated on `IsSaved` (a provision being created cannot have been agreed to yet) and on a field
     * actually being dirty, so the ordinary save of an unreferenced or cosmetically-edited provision
     * pays **nothing** — no probe at all. The reference count runs only when a frozen field really
     * changed, which is the shape that makes belt-and-braces affordable.
     *
     * Compares `OldValue` to `Value` in memory rather than probing the database, for the same reason
     * `GLAccountEntityServer` does: the entity already knows what it loaded. One error per changed
     * field, each naming that field, so the form marks the offending input rather than showing a banner.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();

        // CREATE on a published version. The trigger is the floor here too, but it cannot explain
        // itself on this path at all: MJ calls the generated sproc as `INSERT ... EXEC`, inside which
        // SQL Server forbids a trigger from issuing ROLLBACK, so the refusal arrived as
        // "Cannot use the ROLLBACK statement within an INSERT-EXEC statement" — a message about the
        // mechanism, naming neither the rule nor the field. This is the sentence a user should get.
        if (!this.IsSaved) {
            if (this.ContractTemplateID && (await this.templateIsPublished())) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ContractTemplateID',
                        `This agreement version is published, so a clause cannot be added to it — that would ` +
                            `silently grow the terms of every contract already referencing it. Publish a new ` +
                            `version instead.`,
                        this.ContractTemplateID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
            return result;
        }

        const changed = FROZEN_TERM_FIELDS.filter((f) => this.fieldChanged(f.Name));
        if (changed.length === 0) return result;

        // Only now is a read worth doing.
        if (!(await this.templateIsPublished())) return result;

        for (const field of changed) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    field.Name,
                    `This agreement version is published, so ${field.Label} cannot change — editing it would ` +
                        `rewrite what any customer who signed against it agreed to. Publish a new version instead; ` +
                        `a published version is a historical record. (The description is still editable.)`,
                    this.Get(field.Name),
                    ValidationErrorType.Failure,
                ),
            );
        }

        return result;
    }

    /**
     * Both delete conditions — R-8's modifications, and R-1's referenced template.
     *
     * Reported together rather than first-wins, so someone is not refused twice for two reasons.
     */
    public override async Delete(options?: EntityDeleteOptions): Promise<boolean> {
        // The published check first, and separately from the dependency list, because it is not a
        // dependency — nothing points at this row, the VERSION is simply closed. Pre-empting the
        // trigger here is what turns its raw SQL error into a sentence (the whole point of R-8).
        if (await this.templateIsPublished()) {
            return RefuseDelete(
                this,
                `Provision ${this.ProvisionNumber ?? ''} cannot be deleted: this agreement version is published, ` +
                    `and removing a clause from an agreement someone signed is the same act as rewriting it. ` +
                    `Publish a new version instead.`,
            );
        }
        return GuardedDelete(
            this,
            options,
            `Provision ${this.ProvisionNumber ?? ''} cannot be deleted.`,
            [
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
                    Filter: `ContractTemplateProvisionID = '${this.ID}'`,
                    Describe: (n) =>
                        `${plural(n, 'contract')} negotiated different wording for this clause, and the negotiated ` +
                        `text is only meaningful beside the standard text it replaces.`,
                },
            ],
            (o) => super.Delete(o),
        );
    }

    /**
     * Whether a field's value differs from what was loaded.
     *
     * Trimmed string comparison: `ProvisionText` is free text, and MJ round-trips trailing whitespace
     * inconsistently enough that treating `"x "` as an edit to `"x"` would refuse a save nobody meant
     * to make. The trigger uses exact comparison, so the code is very slightly more permissive than the
     * floor — which is the correct direction for the pair: the code never permits something the trigger
     * would reject on a DIFFERENT value, it only declines to complain about a whitespace-only diff that
     * the trigger would also see. If that ever diverges materially the trigger still holds the line.
     */
    private fieldChanged(fieldName: string): boolean {
        const field = this.GetFieldByName(fieldName);
        if (!field) return false;
        const before = field.OldValue;
        const after = field.Value;
        if (before === after) return false;
        return String(before ?? '').trim() !== String(after ?? '').trim();
    }

    /**
     * Whether this provision's template is PUBLISHED.
     *
     * ⚠ THIS USED TO ASK "do any contracts reference the template", and that gate was wrong in BOTH
     * directions (V202608200900). Too strict: a provision added after a contract referenced the
     * template was never part of what anyone signed, yet became immediately unremovable — and the live
     * data had referenced templates still being authored, which the rule stranded with no way to
     * finish. Too loose: it said nothing about INSERT, so a clause could be ADDED to a signed version.
     * Publication is now an explicit act and the gate reads it directly.
     */
    private async templateIsPublished(): Promise<boolean> {
        const result = await this.RunViewProviderToUse.RunView<{ Status: string }>(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Templates',
                ExtraFilter: `ID = '${this.ContractTemplateID}'`,
                Fields: ['Status'],
                ResultType: 'simple',
            },
            this.ContextCurrentUser,
        );
        if (!result?.Success) {
            // Must not read as "draft" — that would wave through the very edit this guards.
            throw new Error(
                `Could not read the publication status of this provision's agreement version: ` +
                    `${result?.ErrorMessage ?? 'unknown error'}. The save was not attempted.`,
            );
        }
        return result.Results?.[0]?.Status === TEMPLATE_PUBLISHED;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTemplateProvisionEntityServer(): void {
    void ContractTemplateProvisionEntityServer;
}
