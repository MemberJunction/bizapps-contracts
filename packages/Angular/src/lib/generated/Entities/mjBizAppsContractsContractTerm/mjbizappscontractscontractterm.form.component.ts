import { Component } from '@angular/core';
import { mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Terms') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractterm-form',
    templateUrl: './mjbizappscontractscontractterm.form.component.html'
})
export class mjBizAppsContractsContractTermFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTermEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true },
            { sectionKey: 'mJBizAppsContractsContractBillingSchedules', sectionName: 'Contract Billing Schedules', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractLines', sectionName: 'Contract Lines', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractCommitments', sectionName: 'Contract Commitments', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractEvents', sectionName: 'Contract Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractBillingEvents', sectionName: 'Contract Billing Events', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractTerms', sectionName: 'Contract Terms', isExpanded: false },
            { sectionKey: 'mJBizAppsContractsContractAmendments', sectionName: 'Contract Amendments', isExpanded: false }
        ]);
    }
}

