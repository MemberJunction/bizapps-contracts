import { Component } from '@angular/core';
import { mjBizAppsContractsContractEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontract-form',
    templateUrl: './mjbizappscontractscontract.form.component.html'
})
export class mjBizAppsContractsContractFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'contractDetails', sectionName: 'Contract Details', isExpanded: true },
            { sectionKey: 'stakeholders', sectionName: 'Stakeholders', isExpanded: true },
            { sectionKey: 'provenance', sectionName: 'Provenance', isExpanded: true },
            { sectionKey: 'contractLifecycle', sectionName: 'Contract Lifecycle', isExpanded: true },
            { sectionKey: 'datesAndTerms', sectionName: 'Dates and Terms', isExpanded: true },
            { sectionKey: 'renewalTerms', sectionName: 'Renewal Terms', isExpanded: true },
            { sectionKey: 'notesAndMetadata', sectionName: 'Notes and Metadata', isExpanded: false },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTemplateModifications', sectionName: 'Modifications', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsSupersededByContractID', sectionName: 'Supersedes', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsParentContractID', sectionName: 'Lineage', isExpanded: false }
        ]);
    }
}

