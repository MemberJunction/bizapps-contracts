import { Component } from '@angular/core';
import { mjBizAppsContractsContractTemplateEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Templates') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontracttemplate-form',
    templateUrl: './mjbizappscontractscontracttemplate.form.component.html'
})
export class mjBizAppsContractsContractTemplateFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTemplateEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'templateDetails', sectionName: 'Template Details', isExpanded: true },
            { sectionKey: 'publishingInformation', sectionName: 'Publishing Information', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContracts', sectionName: 'Contracts', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTemplateProvisions', sectionName: 'Contract Template Provisions', isExpanded: false }
        ]);
    }
}

