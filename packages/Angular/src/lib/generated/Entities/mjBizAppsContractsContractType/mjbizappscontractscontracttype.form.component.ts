import { Component } from '@angular/core';
import { mjBizAppsContractsContractTypeEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Types') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontracttype-form',
    templateUrl: './mjbizappscontractscontracttype.form.component.html'
})
export class mjBizAppsContractsContractTypeFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTypeEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'contractTypeDetails', sectionName: 'Contract Type Details', isExpanded: true },
            { sectionKey: 'configurationRules', sectionName: 'Configuration Rules', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContracts', sectionName: 'Contracts', isExpanded: false }
        ]);
    }
}

