/**
 * @fileoverview Custom ContractLine form — a priority-2 override of the generated one.
 *
 * A line is short — thirteen columns — so the generated form is not visually overwhelming. It is
 * still wrong in a way that costs people time, because three of those columns carry rules that are
 * invisible in a flat list and that the database will refuse a save over:
 *
 *   - `ContractedUnitPrice` is NULLABLE, and null does not mean zero or "unknown". It means
 *     RESOLVE FROM THE CATALOG as of the contract's priced-at date. Nothing in a flat field list
 *     conveys that, so the natural reading of an empty price box is "free", which is the opposite.
 *   - `SubscriptionTypeID` is REQUIRED on a subscription line and FORBIDDEN on every other kind —
 *     two CHECK constraints pulling in opposite directions on one field.
 *   - `SubscriptionID` is written by the system after materialization and is not a thing a person
 *     fills in; it also has to stay unique, because two lines owning one subscription is a
 *     duplicate-billing shape.
 *
 * So the grouping here is less about volume than about putting each rule next to the field it
 * governs, in the order a line is entered: what is covered → what it costs → how it materializes →
 * for how long.
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
import type { mjBizAppsContractsContractLineEntity } from '@mj-biz-apps/contracts-entities';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Lines', 2)
@Component({
    standalone: true,
    imports: [CommonModule, FormsModule, BaseFormsModule, EntityViewerModule, LinkDirectivesModule],
    selector: 'mjc-contract-line-form',
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

            <!-- WHAT IS COVERED -->
            <mj-collapsible-panel SectionKey="covered" SectionName="What is covered" Icon="fa-solid fa-layer-group" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    A term with <strong>no lines cannot be activated</strong> — an active term covering nothing bills
                    nothing, and nobody notices until a quarter closes light. The product comes from the orders catalog:
                    contracts commits to products, it does not own them.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ContractTermID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="DisplayOrder" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ProductID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="LineType" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Description" Type="textarea" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- WHAT IT COSTS -->
            <mj-collapsible-panel SectionKey="price" SectionName="Price" Icon="fa-solid fa-tag" [Form]="this" [FormContext]="formContext">
                <div class="hint warn">
                    <strong>Leaving the unit price empty is a decision, not an omission.</strong> Empty means
                    <em>resolve from the catalog</em> as of the contract's priced-at date — it does NOT mean zero. A
                    price entered here is locked onto the agreement and never re-read from the catalog again; renewals
                    escalate from it. Enter a price when the deal fixed one, leave it empty when the contract says
                    "at then-current list".
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="Quantity" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="ContractedUnitPrice" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="DiscountPct" Type="numerictextbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <div class="hint">
                    Discount is a <strong>fraction</strong> — 0.10 is ten percent — and a contract discount
                    <strong>overrides</strong> order-level discounting rather than stacking with it, so the value here
                    is the operative one.
                </div>
            </mj-collapsible-panel>

            <!-- HOW IT MATERIALIZES -->
            <mj-collapsible-panel SectionKey="subscription" SectionName="Subscription" Icon="fa-solid fa-arrows-rotate" [Form]="this" [FormContext]="formContext">
                <div class="hint warn">
                    <strong>Subscription type is required on a Subscription line and forbidden on every other kind.</strong>
                    Required because the orders subscription this line will create cannot exist without one, so a
                    subscription line without it saves happily and then fails at billing time on a live contract.
                    Forbidden elsewhere because a one-time fee does not have a subscription type. Both are enforced.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="SubscriptionTypeID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <div class="hint">
                    <strong>Subscription</strong> is written by the system when the line materializes, and is not
                    something to fill in by hand. It is unique across lines: two lines pointing at one subscription is
                    a duplicate-billing shape, so the second one is refused.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="SubscriptionID" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
            </mj-collapsible-panel>

            <!-- FOR HOW LONG -->
            <mj-collapsible-panel SectionKey="window" SectionName="Coverage window" Icon="fa-solid fa-calendar-day" [Form]="this" [FormContext]="formContext">
                <div class="hint">
                    Both empty is the normal case and means <strong>the whole term</strong>. Fill them in only for
                    coverage that genuinely starts late or ends early within the term — a mid-term add-on, or something
                    that lapses before the term does. Renewals deliberately do NOT carry these forward, since a window
                    inside the old term says nothing about the new one.
                </div>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="StartDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
                <mj-form-field [Record]="record" [ShowLabel]="true" FieldName="EndDate" Type="textbox" [EditMode]="EditMode" [FormContext]="formContext"></mj-form-field>
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
export class MJCContractLineFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractLineEntity;

    override async ngOnInit(): Promise<void> {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'covered', sectionName: 'What is covered', isExpanded: true },
            { sectionKey: 'price', sectionName: 'Price', isExpanded: true },
            { sectionKey: 'subscription', sectionName: 'Subscription', isExpanded: false },
            { sectionKey: 'window', sectionName: 'Coverage window', isExpanded: false },
        ]);
    }
}
