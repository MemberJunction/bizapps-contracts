/**
 * @fileoverview Custom ContractTerm form — a priority-2 override of the generated one.
 *
 * WHY THIS ONE MATTERS MOST. A term is where the money actually lives, and the generated form lists
 * twenty-one columns in schema order under a single "Details" panel. In that layout
 * `EscalationPercent` is unexplained on a generated form, so nothing tells the
 * reader that the second is a NEGOTIATED CEILING on the first — the single most disputed clause in a
 * B2B renewal, and the one the entity layer will refuse a save over. `BillingAnchorMonth` and
 * `BillingAnchorDay` sit apart from `BillingFrequency` they belong to. `RenewalOfTermID` looks like
 * an ordinary lookup rather than the link that makes the whole continuity chain navigable.
 *
 * So this contributes ORDER, GROUPING and EXPLANATION in the sequence a term is actually read:
 * which period is this → what was committed → when does it bill → what happens at renewal → how does
 * it end. Every panel that carries a rule the server enforces says so, because a refusal a person
 * could have avoided is a worse experience than a field with a sentence next to it.
 *
 * WHAT IT REUSES. Everything structural — `<mj-record-form-container>` for chrome and save/delete,
 * `<mj-collapsible-panel>` for sections and persisted expand state, `<mj-form-field>` for typed
 * editors, validation and edit-mode binding. No new form machinery, which is why it stays small.
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
import type { mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Terms', 2)
@Component({
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule, EntityViewerModule, LinkDirectivesModule],
    selector: 'mjc-contract-term-form',
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
            .hint.warn {
                color: var(--mj-status-warning-text, #b45309);
                background: var(--mj-status-warning-bg, #fffbeb);
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

            <!-- WHICH PERIOD IS THIS -->
            <mj-collapsible-panel SectionKey="period" SectionName="The period" Icon="fa-solid fa-calendar-range" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    <strong>Term number</strong> is derived, not typed — it is the term's position in this contract's
                    chain, assigned as the next available number when the row is created. Leave it alone unless you are
                    correcting a genuine mistake; the unique index on (contract, number) will refuse a duplicate.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ContractID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="TermNumber" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Status" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="StartDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EndDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHAT WAS COMMITTED -->
            <mj-collapsible-panel SectionKey="money" SectionName="What was committed" Icon="fa-solid fa-sack-dollar" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    <strong>Committed amount</strong> is what the customer agreed to spend over this period — it is not
                    the sum of the coverage lines and does not have to match them. A minimum commitment with usage
                    billing on top is the ordinary case where the two deliberately differ.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CommittedAmount" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="CurrencyID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="PaymentTermsTypeID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHEN DOES IT BILL -->
            <mj-collapsible-panel SectionKey="cadence" SectionName="Billing cadence" Icon="fa-solid fa-repeat" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    The cadence is what <strong>activation</strong> turns into an actual schedule: activating this term
                    creates a billing schedule and one event per occurrence between the start and end dates. Anchored on
                    the start date and stepped in whole months, so a term starting on the 31st bills on the 30th or 28th
                    in short months rather than skipping them. <strong>Milestone</strong> produces a schedule with no
                    dates — milestones are reached, not calculated.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="BillingFrequency" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="BillingAnchorMonth" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="BillingAnchorDay" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHAT HAPPENS AT RENEWAL -->
            <mj-collapsible-panel SectionKey="renewal" SectionName="Renewal &amp; escalation" Icon="fa-solid fa-rotate" [Form]="this" [FormContext]="formContext">
                <div class="hint warn">
                    <strong>Maximum escalation</strong> is a CEILING on the escalation, not a suggestion. A term whose
                    escalation exceeds its cap is <strong>refused on save</strong> — and when a renewal asks for more,
                    the ceiling is applied instead of the request rather than the renewal failing. Both are fractions:
                    0.05 is 5%. Raising the cap is a negotiation, not a correction.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EscalationPercent" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EscalationBasis" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="RenewalProbability" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <div class="hint">
                    <strong>Renewal of</strong> is the link that makes continuity navigable — it points at the term this
                    one replaced, and the workspace walks the chain to show a contract's history. It may only point at a
                    term on the SAME contract; anything else is refused, because walking a crossed chain would surface
                    another contract's terms as this one's past.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="RenewalOfTermID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- HOW DOES IT END -->
            <mj-collapsible-panel SectionKey="ending" SectionName="Ending early" Icon="fa-solid fa-ban" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    Set by <strong>terminating the contract</strong> rather than by hand — that operation also cancels
                    the billing events dated after it, which is the part that actually stops the money. Setting this date
                    alone records an intention and changes nothing about what will bill.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EarlyTerminationDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Notes" Type="textarea" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
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
export class MJCContractTermFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTermEntity;

    /**
     * The related-record keys are copied verbatim from the generated form so a user's existing
     * expand/collapse preferences survive the override — those are stored against the key.
     */
    override async ngOnInit(): Promise<void> {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'period', sectionName: 'The period', isExpanded: true },
            { sectionKey: 'money', sectionName: 'What was committed', isExpanded: true },
            { sectionKey: 'cadence', sectionName: 'Billing cadence', isExpanded: true },
            { sectionKey: 'renewal', sectionName: 'Renewal & escalation', isExpanded: false },
            { sectionKey: 'ending', sectionName: 'Ending early', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractLines', sectionName: 'Contract Lines', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractBillingSchedules', sectionName: 'Contract Billing Schedules', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractBillingEvents', sectionName: 'Contract Billing Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractCommitments', sectionName: 'Contract Commitments', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractAmendments', sectionName: 'Contract Amendments', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractEvents', sectionName: 'Contract Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTerms', sectionName: 'Contract Terms', isExpanded: false },
        ]);
    }
}
