import { Component } from '@angular/core';
import { mjBizAppsContractsContractSequenceEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Sequences') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontractsequence-form',
    templateUrl: './mjbizappscontractscontractsequence.form.component.html'
})
export class mjBizAppsContractsContractSequenceFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractSequenceEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true }
        ]);
    }
}

