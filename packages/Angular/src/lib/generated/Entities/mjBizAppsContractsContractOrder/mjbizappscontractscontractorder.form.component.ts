import { Component } from '@angular/core';
import { mjBizAppsContractsContractOrderEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Orders') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractorder-form',
    templateUrl: './mjbizappscontractscontractorder.form.component.html'
})
export class mjBizAppsContractsContractOrderFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractOrderEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

