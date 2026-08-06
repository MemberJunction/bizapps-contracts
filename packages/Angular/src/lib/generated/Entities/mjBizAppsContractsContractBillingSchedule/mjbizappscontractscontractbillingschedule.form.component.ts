import { Component } from '@angular/core';
import { mjBizAppsContractsContractBillingScheduleEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';
import {  } from "@memberjunction/ng-entity-viewer"

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Billing Schedules') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractbillingschedule-form',
    templateUrl: './mjbizappscontractscontractbillingschedule.form.component.html'
})
export class mjBizAppsContractsContractBillingScheduleFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractBillingScheduleEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true },
            { sectionKey: 'mJBizAppsContractsContractBillingEvents', sectionName: 'Contract Billing Events', isExpanded: false }
        ]);
    }
}

