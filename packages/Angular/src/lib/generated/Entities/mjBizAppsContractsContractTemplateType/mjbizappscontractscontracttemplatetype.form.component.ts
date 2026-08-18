import { Component } from '@angular/core';
import { mjBizAppsContractsContractTemplateTypeEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Template Types') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontracttemplatetype-form',
    templateUrl: './mjbizappscontractscontracttemplatetype.form.component.html'
})
export class mjBizAppsContractsContractTemplateTypeFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTemplateTypeEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'templateConfiguration', sectionName: 'Template Configuration', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTemplates', sectionName: 'Contract Templates', isExpanded: false }
        ]);
    }
}

