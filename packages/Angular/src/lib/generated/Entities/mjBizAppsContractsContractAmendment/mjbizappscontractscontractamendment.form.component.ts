import { Component } from '@angular/core';
import { mjBizAppsContractsContractAmendmentEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Amendments') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractamendment-form',
    templateUrl: './mjbizappscontractscontractamendment.form.component.html'
})
export class mjBizAppsContractsContractAmendmentFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractAmendmentEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

