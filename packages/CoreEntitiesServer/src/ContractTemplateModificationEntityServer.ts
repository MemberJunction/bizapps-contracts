/**
 * @fileoverview `ContractTemplateModificationEntityServer` — the two rules a modification needs that
 * only the server can enforce.
 *
 * Both exist because a modification can be saved on its OWN, not just as part of its contract's
 * graph: the row has a custom form reachable from the editor's Open action (D-22), and admins can
 * reach the generated form directly. Rules that only ran on the parent's save would be bypassed by
 * either path.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import {
    BaseEntity,
    type DatabaseProviderBase,
    LogError,
    Metadata,
    ValidationErrorInfo,
    ValidationErrorType,
    ValidationResult,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractEntity, ContractTemplateModificationEntity } from '@mj-biz-apps/contracts-entities';

/** Guards an ID before it is interpolated into the ancestor walk. */
const UUID_SHAPE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/*
 * EXTENDS THE SHARED SUBCLASS, not the generated one. It used to extend the generated class directly,
 * which meant the server was the one tier that did NOT get the shared class's rules: a modification
 * saved through GraphQL or the standalone form skipped them, so the useful required-field prose would
 * have reached a browser and not an API caller. The same reason `ContractEntityServer extends
 * ContractEntity` rather than the generated class.
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Modifications')
export class ContractTemplateModificationEntityServer extends ContractTemplateModificationEntity {
    /**
     * THE PROVISION MUST BELONG TO A TEMPLATE AT OR ABOVE THIS CONTRACT IN THE TREE (R-4).
     *
     * This rule is why the modification row carries no `ContractTemplateID` of its own (ERD R-16). An
     * earlier design stored the template beside the provision, which meant the row could say it
     * modified template B's clause on a contract that incorporates template A — a stored copy of a
     * derivable fact, free to disagree with it. Removing the column made the disagreement impossible
     * to *express*; this check makes the remaining relationship impossible to *violate*.
     *
     * ⚠ THIS COMPARED AGAINST THE CONTRACT'S OWN SINGLE `ContractTemplateID` UNTIL R-4, and that was
     * too narrow — it made the change-order mechanism unusable. A change order carries no template of
     * its own (its type has `TemplateRequired = false`) but is the CHILD of a contract that does, and a
     * modification recorded ON the change order is where the negotiated wording physically lives. Under
     * the old rule every such modification was refused, because the change order's own
     * `ContractTemplateID` is null and the provision's template matched nothing. Ruled by Marcelo
     * 2026-08-20: *"a modification may point at any template at or above it in the tree."*
     *
     * So the comparison is now against the ANCESTOR SET — every template reachable at or above this
     * modification's contract by walking `ParentContractID`. One recursive walk, one row per level, and
     * chains are 1–3 deep; the same shape R-3 uses, bounded the same way for the same reason (an
     * already-corrupt ring must terminate rather than spin).
     *
     * It needs joins the browser has no business doing, so it cannot live on the shared class. The UI
     * never offers an out-of-tree provision anyway — the picker filters by the contract's template
     * (§6.6) — so in normal use this never fires. It is the backstop for the standalone form, an API
     * caller, and a contract whose template was changed after modifications were recorded against the
     * old one.
     *
     * A contract whose whole ancestry carries NO template is exempt rather than rejected: an SOW
     * legitimately has none (Amith, 2026-08-18), and refusing to record what an SOW negotiated because
     * there is no versioned template to check against would block real work to satisfy a rule about a
     * document that does not exist.
     */
    public override async ValidateAsync(): Promise<ValidationResult> {
        const result = await super.ValidateAsync();

        if (this.ContractID && this.ContractTemplateProvisionID) {
            const mismatch = await this.provisionOutsideContractTemplate();
            if (mismatch) {
                result.Success = false;
                result.Errors.push(
                    new ValidationErrorInfo(
                        'ContractTemplateProvisionID',
                        `That provision belongs to "${mismatch.ProvisionTemplate}", but this contract and its ` +
                            `parents reference "${mismatch.ContractTemplate}". A modification can only deviate from a ` +
                            `provision of an agreement version this contract actually sits under.`,
                        this.ContractTemplateProvisionID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }

        if (this.ContractID && this.ContractTemplateProvisionID && (await this.duplicateAlreadySaved())) {
            result.Success = false;
            result.Errors.push(
                new ValidationErrorInfo(
                    'ContractTemplateProvisionID',
                    `This contract already records a modification for that provision. A contract states ONE ` +
                        `negotiated wording per standard clause — edit the existing modification rather than ` +
                        `adding a second one.`,
                    this.ContractTemplateProvisionID,
                    ValidationErrorType.Failure,
                ),
            );
        }

        return result;
    }

    /**
     * R-10 — is there ALREADY a saved modification of this provision on this contract?
     *
     * The half the browser cannot answer. `ContractEntity.Validate()` catches duplicates among the rows
     * staged in one graph save with no query; this catches a row colliding with one already in the
     * table, which is the standalone-form and API path — and the path where the user has no sibling
     * rows on screen to notice the collision themselves.
     *
     * `ID <> '<this>'` matters and is easy to forget: without it, every ordinary re-save of an existing
     * modification would find ITSELF and refuse. On a create `this.ID` is a generated UUID that matches
     * no row, so the exclusion is harmless there.
     *
     * `UQ_ContractTemplateModification_Contract_Provision` remains the floor. This exists for the
     * message, which is the reason accounting gives for its own duplicated uniqueness checks.
     */
    private async duplicateAlreadySaved(): Promise<boolean> {
        const result = await this.RunViewProviderToUse.RunView(
            {
                EntityName: 'MJ_BizApps_Contracts: Contract Template Modifications',
                ExtraFilter:
                    `ContractID = '${this.ContractID}' ` +
                    `AND ContractTemplateProvisionID = '${this.ContractTemplateProvisionID}' ` +
                    `AND ID <> '${this.ID}'`,
                ResultType: 'count_only',
            },
            this.ContextCurrentUser,
        );
        if (!result?.Success) {
            // Must not read as "no duplicate" — that would wave through the collision this guards, and
            // the raw unique-index error would arrive instead of the sentence.
            throw new Error(
                `Could not check for an existing modification of this provision: ` +
                    `${result?.ErrorMessage ?? 'unknown error'}.`,
            );
        }
        return (result.TotalRowCount ?? 0) > 0;
    }

    /**
     * Force the parent contract's `HasModifications` true after a standalone save.
     *
     * The shared `ContractEntity.Validate()` refuses to CLEAR the flag while rows exist, which covers
     * the graph path. It cannot cover this one: saving a modification directly never runs the
     * contract's validation at all, so a row could be added to a contract still marked unmodified —
     * and that contract then reads as "standard agreement, no need to open the PDF" while carrying a
     * recorded deviation. That is the single most misleading state this app could produce.
     *
     * Done AFTER the save, and only when the save succeeded: the flag should follow the row's
     * existence, not anticipate it. Skipped when the parent already has it set, so the ordinary graph
     * path costs nothing. A failure to update the parent is logged and does NOT fail the save — the
     * modification is the user's work and is correctly stored; the flag is a derived warning, and
     * losing the save to fix a warning would be the wrong trade. The next contract save reconciles it.
     */
    public override async Save(): Promise<boolean> {
        const saved = await super.Save();
        if (saved) {
            try {
                await this.forceParentFlag();
            } catch (err) {
                LogError(
                    `Modification ${this.ID} saved, but could not set HasModifications on contract ` +
                        `${this.ContractID}: ${err}`,
                );
            }
        }
        return saved;
    }

    /**
     * Set the parent's flag — THROUGH THE ENTITY, not a raw `UPDATE`.
     *
     * The first version of this did `UPDATE … SET HasModifications = 1`, which worked and was wrong.
     * Rule 4 of this schema is "audit is MJ's": `TrackRecordChanges` is on, and *who marked this
     * contract as modified, and when* is exactly the question someone asks during a dispute over what
     * was agreed. A raw `UPDATE` bypasses `MJ: Record Changes` entirely, so that flip would have been
     * the one state transition in the app with no audit trail — on the field whose whole purpose is to
     * warn a reader that the paper differs from the standard. It also skips cache invalidation, so a
     * long-lived client could keep showing the old value. Caught on review of PR #9.
     *
     * Loading a whole entity to set one bit is more expensive than one statement. That is the right
     * trade here and only here: this runs when a modification is saved OUTSIDE its contract's graph,
     * which is the uncommon path, and it no-ops when the flag is already true — so the ordinary graph
     * save never reaches it.
     */
    private async forceParentFlag(): Promise<void> {
        const md = new Metadata();
        // Typed as the SHARED class, but the ClassFactory hands back ContractEntityServer here — it is
        // registered later, so it wins on the server. That is deliberate: the flag flip should run the
        // contract's own server rules, not bypass them.
        const contract = await md.GetEntityObject<ContractEntity>('MJ_BizApps_Contracts: Contracts', this.ContextCurrentUser);
        if (!(await contract.Load(this.ContractID))) {
            throw new Error(`contract ${this.ContractID} could not be loaded`);
        }
        // Already true is the common case — leave it alone rather than writing a Record Change that
        // says nothing happened.
        if (contract.HasModifications === true) return;
        contract.HasModifications = true;
        if (!(await contract.Save())) {
            throw new Error(contract.LatestResult?.Message ?? 'save returned false');
        }
    }

    /**
     * The provision's template name and the contract's tree, when the provision sits outside it.
     * Returns null when it is inside the tree, or when the tree carries no template at all.
     *
     * Returns NAMES rather than a boolean so the message can say which is which — "that provision
     * belongs to the 2024 agreement; this contract and its parents reference the 2026 one" is
     * actionable, where "invalid provision" sends the user back to a picker with no idea what to pick.
     *
     * ONE STATEMENT, not two reads and a comparison in TypeScript. The walk has to happen in SQL
     * (a recursive ancestor set is not something `RunView` can express), and once the query is there
     * anyway, resolving the provision's template in the same statement costs nothing extra. This is a
     * deliberate reversal of the note the previous implementation carried, which preferred two
     * metadata-mediated `RunView`s over one join; that trade made sense when the rule was a
     * single-row equality check and does not survive the rule becoming a tree walk.
     */
    private async provisionOutsideContractTemplate(): Promise<{ ProvisionTemplate: string; ContractTemplate: string } | null> {
        if (!UUID_SHAPE.test(this.ContractID) || !UUID_SHAPE.test(this.ContractTemplateProvisionID)) {
            throw new Error(
                `Refusing to check the provision's template: '${this.ContractID}' or ` +
                    `'${this.ContractTemplateProvisionID}' is not a UUID.`,
            );
        }
        const rows = await this.db.ExecuteSQL<{
            ProvisionTemplateID: string;
            ProvisionTemplate: string;
            AncestorTemplates: string | null;
            InTree: number;
        }>(
            `WITH ancestry AS (
                 SELECT [ID], [ParentContractID], [ContractTemplateID], 1 AS Depth
                   FROM __mj_BizAppsContracts.[Contract]
                  WHERE [ID] = '${this.ContractID}'
                 UNION ALL
                 SELECT c.[ID], c.[ParentContractID], c.[ContractTemplateID], a.Depth + 1
                   FROM __mj_BizAppsContracts.[Contract] c
                   JOIN ancestry a ON c.[ID] = a.[ParentContractID]
                  WHERE a.Depth < 50
             ),
             tmpl AS (
                 SELECT DISTINCT t.[ID], t.[Name]
                   FROM ancestry a
                   JOIN __mj_BizAppsContracts.[ContractTemplate] t ON t.[ID] = a.[ContractTemplateID]
             )
             SELECT
                 CAST(pt.[ID] AS NVARCHAR(36))                                   AS ProvisionTemplateID,
                 pt.[Name]                                                       AS ProvisionTemplate,
                 (SELECT STRING_AGG(x.[Name], N', ') FROM tmpl x)                AS AncestorTemplates,
                 CASE WHEN EXISTS (SELECT 1 FROM tmpl x WHERE x.[ID] = pt.[ID])
                      THEN 1 ELSE 0 END                                          AS InTree
               FROM __mj_BizAppsContracts.[ContractTemplateProvision] p
               JOIN __mj_BizAppsContracts.[ContractTemplate] pt ON pt.[ID] = p.[ContractTemplateID]
              WHERE p.[ID] = '${this.ContractTemplateProvisionID}';`,
            undefined,
            { isMutation: false, description: 'R-4 provision-in-ancestor-templates check' },
            this.ContextCurrentUser,
        );

        const row = rows?.[0];
        // No provision row, or it is inside the tree: nothing to say.
        if (!row || row.InTree === 1) return null;
        // The whole ancestry carries no template — the SOW case, exempt by ruling.
        if (!row.AncestorTemplates) return null;
        return { ProvisionTemplate: row.ProvisionTemplate, ContractTemplate: row.AncestorTemplates };
    }

    /** Narrowing cast to the concrete provider, which is what a server-side subclass always has. */
    private get db(): DatabaseProviderBase {
        return this.ProviderToUse as unknown as DatabaseProviderBase;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTemplateModificationEntityServer(): void {
    void ContractTemplateModificationEntityServer;
}
