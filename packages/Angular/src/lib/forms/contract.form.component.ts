/**
 * @fileoverview Custom Contract form — an OVERRIDE of the generated one, not a replacement screen.
 *
 * HOW THE OVERRIDE WORKS. The generated form registers as
 * `@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts')` at the default priority 0.
 * This class registers for the SAME key at **priority 2**, so MJ's ClassFactory hands this one to
 * every caller instead — the roster's "New contract" button, a double-clicked grid row, a deep link.
 * Nothing else changes and no host wiring is touched: the generated form stays in the tree as the
 * fallback, and deleting this file restores it.
 *
 * WHY OVERRIDE AT ALL. The generated form is correct but shapeless: one "Details" panel listing
 * eighteen columns in schema order, so `PricedAt` — the field that LOCKS every price on the
 * agreement — sits between `AutoRenew` and `TerminationPolicy` with nothing to say it matters. A
 * contract is read and entered in a specific order (what is this → who is it with → when does it run
 * → what does it cost → what happens at renewal), and the form should follow that order.
 *
 * WHAT IT REUSES. Everything structural: `<mj-record-form-container>` (chrome, save/delete, history,
 * favourites), `<mj-collapsible-panel>` (sections + expand state), `<mj-form-field>` (typed editors,
 * validation, edit-mode binding, lookups). This file contributes ORDER, GROUPING and EXPLANATION —
 * not new form machinery, which is why it stays small.
 *
 * @module @mj-biz-apps/contracts-ng
 */

import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent, BaseFormsModule } from '@memberjunction/ng-base-forms';
import { EntityViewerModule } from '@memberjunction/ng-entity-viewer';
import { LinkDirectivesModule } from '@memberjunction/ng-link-directives';
import type { mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';

/** Priority 2 beats the generated form's 0 for the same key. */
@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts', 2)
@Component({
    standalone: true,
    // The same set GeneratedFormsModule imports — this form is built from MJ's own primitives
    // (record container, collapsible panels, typed form fields), so it needs the same providers.
    imports: [CommonModule, FormsModule, BaseFormsModule, EntityViewerModule, LinkDirectivesModule],
    selector: 'mjc-contract-form',
    styles: [
        `
            .hint {
                grid-column: 1 / -1;
                font-size: 12.5px;
                line-height: 1.5;
                color: var(--mj-status-info-text, #1d4ed8);
                background: var(--mj-status-info-bg, #eff6ff);
                border-radius: var(--mj-radius-md, 6px);
                padding: 10px 12px;
                margin: 0 0 12px;
            }
        `,
    ],
    template: `
        <mj-record-form-container
            [Record]="record"
            [FormComponent]="this"
            (Navigate)="OnFormNavigate($any($event))"
            (DeleteRequested)="OnDeleteRequested()"
            (FavoriteToggled)="OnFavoriteToggled()"
            (HistoryRequested)="OnHistoryRequested()"
            (ListManagementRequested)="OnListManagementRequested()"
        >
            <mj-form-panel-slot
                Entity="{{ record.EntityInfo.Name }}"
                Slot="before-fields"
                [Record]="record"
                [FormComponent]="this"
                [FormContext]="formContext"
            ></mj-form-panel-slot>

            <!-- WHAT IS THIS -->
            <mj-collapsible-panel SectionKey="agreement" SectionName="The agreement" Icon="fa-solid fa-file-signature" [Form]="this" [FormContext]="formContext">
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ContractNumber" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ContractTypeID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Status" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Description" Type="textarea" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ExternalReferenceID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ParentContractID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHO IS IT WITH -->
            <mj-collapsible-panel SectionKey="parties" SectionName="Parties" Icon="fa-solid fa-building" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    A contract has exactly one customer — an organization <strong>or</strong> a person, never both. The
                    database enforces it, so filling in both will refuse to save rather than silently pick one.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CompanyID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CustomerOrganizationID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CustomerPersonID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="PrimaryContactPersonID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="OwnerUserID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHEN DOES IT RUN, AND AT WHAT PRICES -->
            <mj-collapsible-panel SectionKey="dates" SectionName="Dates &amp; pricing" Icon="fa-solid fa-calendar-day" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    <strong>Priced as of</strong> is the moment prices are resolved from the catalog and
                    <strong>locked onto this agreement</strong>. Set it to the day the deal was struck — backdate it when
                    entering paper signed earlier. Everything after the first renewal escalates from the contract's own
                    price and never re-reads the catalog, so this date is the origin of every number on the agreement.
                    <br /><br />
                    Note that <strong>Executed</strong> may legitimately fall BEFORE <strong>Effective</strong> — signing
                    in December for a term starting January 1 is the ordinary case, not an error.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="PricedAt" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EffectiveDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ExecutedDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHAT HAPPENS AT THE END -->
            <mj-collapsible-panel SectionKey="renewal" SectionName="Renewal &amp; termination" Icon="fa-solid fa-rotate" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    The escalation cap and the renewal notice period live on each <strong>term</strong>, not here — they can
                    change between terms. This panel holds only what is true of the agreement as a whole.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="AutoRenew" Type="checkbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CancellationWindowDays" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="TerminationPolicy" Type="textarea" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="SupersededByContractID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <mj-form-panel-slot
                Entity="{{ record.EntityInfo.Name }}"
                Slot="after-fields"
                [Record]="record"
                [FormComponent]="this"
                [FormContext]="formContext"
            ></mj-form-panel-slot>
        </mj-record-form-container>
    `,
})
export class MJCContractFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractEntity;

    /**
     * Section keys must match the `SectionKey` on each panel — that is how expand state is tracked and
     * persisted. The related-record sections keep the generated form's keys so a user's existing
     * expand/collapse preferences survive the override.
     */
    override async ngOnInit(): Promise<void> {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'agreement', sectionName: 'The agreement', isExpanded: true },
            { sectionKey: 'parties', sectionName: 'Parties', isExpanded: true },
            { sectionKey: 'dates', sectionName: 'Dates & pricing', isExpanded: true },
            { sectionKey: 'renewal', sectionName: 'Renewal & termination', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTerms', sectionName: 'Contract Terms', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractEvents', sectionName: 'Contract Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsParentContractID', sectionName: 'Contracts (Parent Contract ID)', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsSupersededByContractID', sectionName: 'Contracts (Superseded By Contract ID)', isExpanded: false },
        ]);
    }
}
