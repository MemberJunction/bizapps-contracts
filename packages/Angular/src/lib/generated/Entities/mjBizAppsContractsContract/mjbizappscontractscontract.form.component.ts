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
            { sectionKey: 'partiesAndRelationships', sectionName: 'Parties and Relationships', isExpanded: true },
            { sectionKey: 'documentManagement', sectionName: 'Document Management', isExpanded: true },
            { sectionKey: 'provenanceAndLinking', sectionName: 'Provenance and Linking', isExpanded: true },
            { sectionKey: 'timelineAndTerms', sectionName: 'Timeline and Terms', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTemplateModifications', sectionName: 'Contract Template Modifications', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsSupersededByContractID', sectionName: 'Contracts (Superseded By Contract)', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsParentContractID', sectionName: 'Contracts (Parent Contract)', isExpanded: false }
        ]);
    }
}

