import { Component } from '@angular/core';
import { mjBizAppsContractsContractEventEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Events') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractevent-form',
    templateUrl: './mjbizappscontractscontractevent.form.component.html'
})
export class mjBizAppsContractsContractEventFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractEventEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

