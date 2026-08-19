/**
 * @fileoverview The modification's OWN form — D-22's second host for one component.
 *
 * Marcelo ruled that a modification deserves a form and not only an inline panel: it carries real content
 * (a clause of negotiated language) and a person editing that language wants the whole width, not a row
 * inside a list.
 *
 * MJ has no way to embed a child entity's form inside a parent form, so rather than choose between the
 * two we render ONE component — `mjc-modification-editor` — in both places. Here it runs in
 * `SingleRowMode` with the contract fixed; inline on the contract form it runs as a list. Two hosts, one
 * implementation, so the standard-clause-beside-negotiated-language layout cannot drift between them.
 *
 * THIS IS THE ONE FULL FORM REPLACEMENT IN THE APP, and it is registered at PRIORITY 2 — the same
 * mechanism that made v1's contract form a hazard. It is defensible here for the reason it was not there:
 * v1 replaced the CONTRACT form, the app's central surface, and bound columns that were later dropped.
 * This replaces the form of a join-shaped row whose two fields are exactly what the editor renders, and
 * it adds no field binding of its own — the editor owns that.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component, ViewEncapsulation } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type {
    ContractEntity,
    mjBizAppsContractsContractTemplateModificationEntity,
} from '@mj-biz-apps/contracts-entities';
import { MJC_ENTITIES } from '../data/entity-names';
import { MJCModificationEditorComponent } from './modification-editor.component';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Template Modifications', 2)
@Component({
    selector: 'mjc-modification-form',
    standalone: true,
    encapsulation: ViewEncapsulation.None,
    imports: [CommonModule, BaseFormsModule, MJCModificationEditorComponent],
    template: `
        <div class="mjc-page">
            @if (Contract) {
                <div class="mjc-card">
                    <h3 class="mjc-card__title">
                        Modification to {{ Contract.ContractNumber }}
                    </h3>
                    <p class="mjc-page__intro">
                        The contract is fixed here — a modification cannot be moved to a different
                        agreement, because it is a statement about <em>this</em> contract's paper. Open the
                        contract to record another one.
                    </p>
                </div>

                <mjc-modification-editor
                    [Record]="Contract"
                    [EditMode]="EditMode"
                    [SingleRowMode]="true"
                    [OnlyModificationID]="ModificationID"
                    [Provider]="ProviderToUse" />
            } @else if (LoadError) {
                <p class="mjc-empty">{{ LoadError }}</p>
            } @else {
                <p class="mjc-empty">Loading the contract this modification belongs to…</p>
            }
        </div>
    `,
})
export class MJCModificationFormComponent extends BaseFormComponent {
    /**
     * `BaseFormComponent` declares `record` abstract, so every form must name its entity type — that is
     * how the base gets typed access to the row it is editing. Same declaration the generated form
     * makes; this class replaces that form, so it inherits the obligation.
     */
    public record!: mjBizAppsContractsContractTemplateModificationEntity;

    public Contract: ContractEntity | null = null;
    public LoadError: string | null = null;
    public ModificationID: string | null = null;
    private loadStarted = false;

    /**
     * Load the PARENT contract, then let the editor work through its collection.
     *
     * Why not edit the modification record directly, when that is what this form is for? Because the
     * invariants live on the contract: `HasModifications` must stay true while rows exist, and the
     * provision must belong to the contract's template. Editing through the collection means both rules
     * are enforced by the same code that enforces them inline, and the save is one graph. Editing the row
     * standalone would work and would route around the parent's `Validate()` — the server subclass exists
     * precisely because that path is reachable, and using it here voluntarily would be perverse.
     */
    public override async ngAfterViewInit(): Promise<void> {
        // Plain call — see the note in contracts-sections.component.ts: `super.x?.()` produces a
        // bundle esbuild cannot parse, and BaseFormComponent declares ngAfterViewInit concretely.
        super.ngAfterViewInit();
        if (this.loadStarted) return;
        this.loadStarted = true;

        const contractID = this.record?.ContractID;
        this.ModificationID = this.record?.ID ?? null;
        if (!contractID) {
            this.LoadError = 'This modification names no contract, which should not be possible — ContractID is NOT NULL.';
            return;
        }

        try {
            // D-25: construct through the FORM's provider, so the parent contract is loaded from the
            // same place this modification was.
            const contract = await this.ProviderToUse.GetEntityObject<ContractEntity>(MJC_ENTITIES.Contract);
            if (await contract.Load(contractID)) {
                // Load the collection so the editor finds this row in it rather than fetching again.
                await contract.Modifications.Load();
                this.Contract = contract;
            } else {
                this.LoadError = `Could not load contract ${contractID}.`;
            }
        } catch (err) {
            this.LoadError = `Could not load the parent contract: ${String(err)}`;
        }
    }
}
