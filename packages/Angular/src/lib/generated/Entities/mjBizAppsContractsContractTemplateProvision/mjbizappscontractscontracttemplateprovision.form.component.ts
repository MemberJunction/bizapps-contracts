import { Component } from '@angular/core';
import { mjBizAppsContractsContractTemplateProvisionEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Template Provisions') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontracttemplateprovision-form',
    templateUrl: './mjbizappscontractscontracttemplateprovision.form.component.html'
})
export class mjBizAppsContractsContractTemplateProvisionFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTemplateProvisionEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'templateAssociation', sectionName: 'Template Association', isExpanded: true },
            { sectionKey: 'provisionDetails', sectionName: 'Provision Details', isExpanded: true },
            { sectionKey: 'provisionContent', sectionName: 'Provision Content', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTemplateModifications', sectionName: 'Contract Template Modifications', isExpanded: false }
        ]);
    }
}

