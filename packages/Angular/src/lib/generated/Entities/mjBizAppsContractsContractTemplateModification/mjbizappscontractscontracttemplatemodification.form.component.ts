import { Component } from '@angular/core';
import { mjBizAppsContractsContractTemplateModificationEntity } from '@mj-biz-apps/contracts-entities';
import { RegisterClass } from '@memberjunction/global';
import { BaseFormComponent } from '@memberjunction/ng-base-forms';

@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contract Template Modifications') // Tell MemberJunction about this class
@Component({
    standalone: false,
    selector: 'gen-mjbizappscontractscontracttemplatemodification-form',
    templateUrl: './mjbizappscontractscontracttemplatemodification.form.component.html'
})
export class mjBizAppsContractsContractTemplateModificationFormComponent extends BaseFormComponent {
    public record!: mjBizAppsContractsContractTemplateModificationEntity;

    override async ngOnInit() {
        await super.ngOnInit();
        this.initSections([
            { sectionKey: 'contractAssociation', sectionName: 'Contract Association', isExpanded: true },
            { sectionKey: 'modificationDetails', sectionName: 'Modification Details', isExpanded: true },
            { sectionKey: 'details', sectionName: 'Details', isExpanded: true },
            { sectionKey: 'systemMetadata', sectionName: 'System Metadata', isExpanded: false }
        ]);
    }
}

