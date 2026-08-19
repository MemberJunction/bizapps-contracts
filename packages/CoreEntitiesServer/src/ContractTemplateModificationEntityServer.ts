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
import { BaseEntity, LogError, Metadata, ValidationErrorInfo, ValidationErrorType, ValidationResult } from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import { ContractEntity, mjBizAppsContractsContractTemplateModificationEntity } from '@mj-biz-apps/contracts-entities';

@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Modifications')
export class ContractTemplateModificationEntityServer extends mjBizAppsContractsContractTemplateModificationEntity {
    /**
     * THE PROVISION MUST BELONG TO THE TEMPLATE THIS CONTRACT INCORPORATES.
     *
     * This rule is why the modification row carries no `ContractTemplateID` of its own (ERD R-16). An
     * earlier design stored the template beside the provision, which meant the row could say it
     * modified template B's clause on a contract that incorporates template A — a stored copy of a
     * derivable fact, free to disagree with it. Removing the column made the disagreement impossible
     * to *express*; this check makes the remaining relationship impossible to *violate*.
     *
     * It needs two joins (provision → its template, and this modification → its contract → that
     * contract's template), so it cannot live on the shared class. The UI never offers an
     * out-of-template provision in the first place — the picker filters the cached provision set by
     * the contract's ContractTemplateID (§6.6) — so in normal use this never fires. It is the
     * backstop for the standalone form, an API caller, and a contract whose template was changed
     * after modifications were recorded against the old one.
     *
     * A contract with NO template is exempt rather than rejected: an SOW legitimately has none
     * (Amith, 2026-08-18), and refusing to record what an SOW negotiated because there is no
     * versioned template to check against would block real work to satisfy a rule about a document
     * that does not exist.
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
                        `That provision belongs to "${mismatch.ProvisionTemplate}", but this contract incorporates ` +
                            `"${mismatch.ContractTemplate}". A modification can only deviate from a provision of the ` +
                            `agreement version the contract actually references.`,
                        this.ContractTemplateProvisionID,
                        ValidationErrorType.Failure,
                    ),
                );
            }
        }

        return result;
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
     * The two template names when they disagree, or null when they match (or cannot be compared).
     *
     * Returns the NAMES rather than a boolean so the error message can say which is which — "that
     * provision belongs to the 2024 agreement, this contract references the 2026 one" is actionable;
     * "invalid provision" sends the user back to a picker with no idea what to pick.
     */
    private async provisionOutsideContractTemplate(): Promise<{ ProvisionTemplate: string; ContractTemplate: string } | null> {
        const provider = this.ProviderToUse as unknown as { ExecuteSQL: (sql: string, params?: unknown[]) => Promise<unknown> };
        const rows = (await provider.ExecuteSQL(
            `SELECT pt.[Name] AS ProvisionTemplate, ctt.[Name] AS ContractTemplate
               FROM __mj_BizAppsContracts.ContractTemplateProvision p
               JOIN __mj_BizAppsContracts.ContractTemplate pt ON pt.ID = p.ContractTemplateID
               JOIN __mj_BizAppsContracts.Contract c ON c.ID = @p1
               JOIN __mj_BizAppsContracts.ContractTemplate ctt ON ctt.ID = c.ContractTemplateID
              WHERE p.ID = @p0
                AND c.ContractTemplateID IS NOT NULL
                AND p.ContractTemplateID <> c.ContractTemplateID;`,
            [this.ContractTemplateProvisionID, this.ContractID],
        )) as Array<{ ProvisionTemplate: string; ContractTemplate: string }>;
        return rows?.[0] ?? null;
    }
}

/** Anti-tree-shake anchor — see the note in index.ts. */
export function LoadContractTemplateModificationEntityServer(): void {
    void ContractTemplateModificationEntityServer;
}
