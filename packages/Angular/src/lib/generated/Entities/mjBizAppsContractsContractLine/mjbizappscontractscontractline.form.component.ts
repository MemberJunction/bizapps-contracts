import { Component } from '@angular/core';
import { mjBizAppsContractsContractLineEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Lines') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractline-form',
    templateUrl: './mjbizappscontractscontractline.form.component.html'
})
export class mjBizAppsContractsContractLineFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractLineEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

