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
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true },
            { sectionKey: 'mJBizAppsContractsContracts', sectionName: 'Contracts', isExpanded: false }
        ]);
    }
}

