import { Component } from '@angular/core';
import { mjBizAppsContractsContractCommitmentEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Commitments') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractcommitment-form',
    templateUrl: './mjbizappscontractscontractcommitment.form.component.html'
})
export class mjBizAppsContractsContractCommitmentFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractCommitmentEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

