/**
 * @fileoverview Agreements on Common's Person form.
 *
 * `Contract.PrimaryContactPersonID` points at Common's People. Same registration pattern as
 * `organization.panels.ts` / orders' `person-orders.panel.ts`. Common is not modified.
 *
 * @module @mj-biz-apps/contracts-ng
 */
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RegisterClassEx } from '@memberjunction/global';
import { BaseFormPanel, BaseFormsModule } from '@memberjunction/ng-base-forms';
import type { AfterDataLoadEventArgs } from '@memberjunction/ng-entity-viewer';
import type { BaseEntity, RunViewParams } from '@memberjunction/core';
import { MJC_ENTITIES, MJC_FOREIGN_ENTITIES } from '../data/entity-names';

const SECTION_KEY = 'agreements';

@RegisterClassEx(BaseFormPanel, {
    key: 'form-panel:People:related:Contracts',
    priority: 10,
    metadata: {
        entity: MJC_FOREIGN_ENTITIES.Person,
        slot: 'after-related',
        sortKey: 68,
        relatedEntity: MJC_ENTITIES.Contract,
        relatedJoinField: 'PrimaryContactPersonID',
        contributionKey: SECTION_KEY,
        inclusion: 'Primary',
    },
})
@Component({
    selector: 'mjc-person-agreements-panel',
    standalone: true,
    imports: [CommonModule, BaseFormsModule],
    template: `
        <mj-collapsible-panel
            SectionKey="agreements"
            SectionName="Agreements"
            Icon="fa-solid fa-file-contract"
            Variant="related-entity"
            [Form]="FormComponent"
            [FormContext]="FormContext"
            [DefaultExpanded]="false">
            @if (Record.IsSaved) {
                <mj-explorer-entity-data-grid
                    [Params]="Params"
                    [NewRecordValues]="NewValues"
                    [AllowLoad]="FormComponent.IsSectionExpanded(SectionKey)"
                    [ShowToolbar]="true"
                    (Navigate)="FormComponent.OnFormNavigate($event)"
                    (AfterDataLoad)="OnDataLoad($event)">
                </mj-explorer-entity-data-grid>
            }
        </mj-collapsible-panel>
    `,
})
export class MJCPersonAgreementsPanel extends BaseFormPanel<BaseEntity> {
    public readonly ContractEntity = MJC_ENTITIES.Contract;
    public readonly SectionKey = SECTION_KEY;
    public get Params(): RunViewParams | null {
        const id = this.Record?.Get?.('ID');
        if (!id) return null;
        return {
            EntityName: MJC_ENTITIES.Contract,
            ExtraFilter: `PrimaryContactPersonID = '${String(id).replace(/'/g, "''")}'`,
        };
    }
    public get NewValues(): Record<string, unknown> {
        const id = this.Record?.Get?.('ID');
        return id ? { PrimaryContactPersonID: String(id) } : {};
    }
    public OnDataLoad(event: AfterDataLoadEventArgs): void {
        this.FormComponent.SetSectionRowCount(SECTION_KEY, event.totalRowCount);
    }
}
