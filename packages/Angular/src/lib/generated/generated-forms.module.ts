/**********************************************************************************
* GENERATED FILE - This file is automatically managed by the MJ CodeGen tool, 
* 
* DO NOT MODIFY THIS FILE - any changes you make will be wiped out the next time the file is
* generated
* 
**********************************************************************************/
import { NgModule } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

// MemberJunction Imports
import { BaseFormsModule } from '@memberjunction/ng-base-forms';
import { EntityViewerModule } from '@memberjunction/ng-entity-viewer';
import { LinkDirectivesModule } from '@memberjunction/ng-link-directives';

// Import Generated Components
import { mjBizAppsContractsContractFormComponent } from "./Entities/mjBizAppsContractsContract/mjbizappscontractscontract.form.component";
import { mjBizAppsContractsContractTemplateFormComponent } from "./Entities/mjBizAppsContractsContractTemplate/mjbizappscontractscontracttemplate.form.component";
import { mjBizAppsContractsContractTemplateModificationFormComponent } from "./Entities/mjBizAppsContractsContractTemplateModification/mjbizappscontractscontracttemplatemodification.form.component";
import { mjBizAppsContractsContractTemplateProvisionFormComponent } from "./Entities/mjBizAppsContractsContractTemplateProvision/mjbizappscontractscontracttemplateprovision.form.component";
import { mjBizAppsContractsContractTemplateTypeFormComponent } from "./Entities/mjBizAppsContractsContractTemplateType/mjbizappscontractscontracttemplatetype.form.component";
import { mjBizAppsContractsContractTypeFormComponent } from "./Entities/mjBizAppsContractsContractType/mjbizappscontractscontracttype.form.component";
   

@NgModule({
declarations: [
    mjBizAppsContractsContractTemplateModificationFormComponent
],
imports: [
    CommonModule,
    FormsModule,
    BaseFormsModule,
    EntityViewerModule,
    LinkDirectivesModule
],
exports: [
]
})
export class GeneratedForms_SubModule_3 { }
    


@NgModule({
declarations: [
    mjBizAppsContractsContractTemplateProvisionFormComponent
],
imports: [
    CommonModule,
    FormsModule,
    BaseFormsModule,
    EntityViewerModule,
    LinkDirectivesModule
],
exports: [
]
})
export class GeneratedForms_SubModule_10 { }
    


@NgModule({
declarations: [
    mjBizAppsContractsContractFormComponent
],
imports: [
    CommonModule,
    FormsModule,
    BaseFormsModule,
    EntityViewerModule,
    LinkDirectivesModule
],
exports: [
]
})
export class GeneratedForms_SubModule_21 { }
    


@NgModule({
declarations: [
    mjBizAppsContractsContractTemplateFormComponent,
    mjBizAppsContractsContractTemplateTypeFormComponent
],
imports: [
    CommonModule,
    FormsModule,
    BaseFormsModule,
    EntityViewerModule,
    LinkDirectivesModule
],
exports: [
]
})
export class GeneratedForms_SubModule_27 { }
    


@NgModule({
declarations: [
    mjBizAppsContractsContractTypeFormComponent
],
imports: [
    CommonModule,
    FormsModule,
    BaseFormsModule,
    EntityViewerModule,
    LinkDirectivesModule
],
exports: [
]
})
export class GeneratedForms_SubModule_29 { }
    


@NgModule({
declarations: [
],
imports: [
    GeneratedForms_SubModule_3,
    GeneratedForms_SubModule_10,
    GeneratedForms_SubModule_21,
    GeneratedForms_SubModule_27,
    GeneratedForms_SubModule_29
]
})
export class GeneratedFormsModule { }
    
// Note: LoadXXXGeneratedForms() functions have been removed. Tree-shaking prevention
// is now handled by the pre-built class registration manifest system.
// See packages/CodeGenLib/CLASS_MANIFEST_GUIDE.md for details.
    