import { Component } from '@angular/core';
import { mjBizAppsContractsContractBillingEventEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Billing Events') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractbillingevent-form',
    templateUrl: './mjbizappscontractscontractbillingevent.form.component.html'
})
export class mjBizAppsContractsContractBillingEventFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractBillingEventEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

