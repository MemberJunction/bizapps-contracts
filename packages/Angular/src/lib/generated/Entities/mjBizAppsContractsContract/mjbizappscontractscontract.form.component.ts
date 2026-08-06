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
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true },
            { sectionKey: 'mJBizAppsContractsContractEvents', sectionName: 'Contract Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTerms', sectionName: 'Contract Terms', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsSupersededByContractID', sectionName: 'Contracts (Superseded By Contract ID)', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractsParentContractID', sectionName: 'Contracts (Parent Contract ID)', isExpanded: false }
        ]);
    }
}

