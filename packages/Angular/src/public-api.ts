/**
 * @mj-biz-apps/contracts-ng — the CLIENT BOOTSTRAP package.
 *
 * This is the package named in mj-app.json under packages.client with role
 * "bootstrap". When the app is installed (or dev-linked), MJExplorer's
 * auto-generated open-app-bootstrap.generated.ts gains a static
 * `import '@mj-biz-apps/contracts-ng';` — ESBuild bundles it and module evaluation
 * fires the @RegisterClass decorators that make your components discoverable.
 *
 * WHAT LIVES HERE
 *   src/lib/generated/ — CodeGen Angular output (entity forms; do not edit)
 *   src/lib/           — your hand-written components (dashboards, tabs, ...)
 *
 * AFTER YOUR FIRST CODEGEN RUN (the pattern every shipped app uses): import
 * the entity package + the generated forms module so their @RegisterClass
 * decorators fire, and RE-EXPORT the generated module/components so the
 * host's class-registration manifest can import them by name:
 *
 *   import '@mj-biz-apps/contracts-entities';
 *   import './lib/generated/generated-forms.module';
 *   import { GeneratedFormsModule } from './lib/generated/generated-forms.module';
 *   export { GeneratedFormsModule } from './lib/generated/generated-forms.module';
 *   export { <YourEntity>FormComponent } from './lib/generated/Entities/<YourEntity>/<yourentity>.form.component';
 *
 * HAND-WRITTEN COMPONENT EXAMPLE — a resource component that renders as a tab
 * in MJ Explorer (its DriverClass must match a DefaultNavItems entry in your
 * application metadata — see docs/template-docs/metadata.md):
 *
 *   import { Component } from '@angular/core';
 *   import { RegisterClass } from '@memberjunction/global';
 *   import { BaseResourceComponent, ResourceData } from '@memberjunction/ng-shared';
 *
 *   @RegisterClass(BaseResourceComponent, 'MjBizappsContractsDashboard')
 *   @Component({
 *     selector: 'sample-app-dashboard',
 *     template: '<div><h2>BizApps Contracts</h2></div>',
 *     standalone: false
 *   })
 *   export class MjBizappsContractsDashboardComponent extends BaseResourceComponent {
 *     async GetResourceDisplayName(data: ResourceData): Promise<string> { return 'Sample App'; }
 *     async GetResourceIconClass(data: ResourceData): Promise<string> { return 'fa-solid fa-cube'; }
 *   }
 *
 * NOTE: package.json already carries the peer deps the generated forms will
 * import (@angular/forms, ng-base-forms, ng-entity-viewer, ng-link-directives)
 * so your first codegen run builds without dependency surgery.
 *
 * TODO(template): rename the function to Load<YourApp>Client and keep it in
 * sync with mj-app.json "startupExport".
 */

/* ============================================================================
 * GENERATED FORMS — wired after the first CodeGen run, exactly as the header
 * above prescribes. The side-effect imports fire the @RegisterClass decorators;
 * the re-exports are what MJExplorer's class-registration manifest imports BY
 * NAME. Without these exports the Explorer bundle fails to compile with
 * TS2305 'has no exported member', which is precisely what happened.
 * ========================================================================== */
import '@mj-biz-apps/contracts-entities';
import './lib/generated/generated-forms.module';
import { GeneratedFormsModule } from './lib/generated/generated-forms.module';
import { MJCContractsSectionComponent } from './lib/sections/contracts-section.component';
import { MJCContractFormComponent } from './lib/forms/contract.form.component';
export { GeneratedFormsModule } from './lib/generated/generated-forms.module';
export { mjBizAppsContractsContractAmendmentFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractAmendment/mjbizappscontractscontractamendment.form.component';
export { mjBizAppsContractsContractBillingEventFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractBillingEvent/mjbizappscontractscontractbillingevent.form.component';
export { mjBizAppsContractsContractBillingScheduleFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractBillingSchedule/mjbizappscontractscontractbillingschedule.form.component';
export { mjBizAppsContractsContractCommitmentFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractCommitment/mjbizappscontractscontractcommitment.form.component';
export { mjBizAppsContractsContractEventFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractEvent/mjbizappscontractscontractevent.form.component';
export { mjBizAppsContractsContractFormComponent } from './lib/generated/Entities/mjBizAppsContractsContract/mjbizappscontractscontract.form.component';
export { mjBizAppsContractsContractLineFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractLine/mjbizappscontractscontractline.form.component';
export { mjBizAppsContractsContractSequenceFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractSequence/mjbizappscontractscontractsequence.form.component';
export { mjBizAppsContractsContractTermFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractTerm/mjbizappscontractscontractterm.form.component';
export { mjBizAppsContractsContractTypeFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractType/mjbizappscontractscontracttype.form.component';


/* The Explorer tab. Its @RegisterClass key must match the DriverClass in
 * metadata/applications/.contracts-application.json — that pairing is the entire wiring. */
export { MJCContractsSectionComponent } from './lib/sections/contracts-section.component';
/* Custom Contract form — overrides the generated one at priority 2. */
export { MJCContractFormComponent } from './lib/forms/contract.form.component';

export function LoadMjBizappsContractsClient(): void {
    // Importing this module is what registers everything above. The reference
    // below is an anti-tree-shake anchor: without a live use, a production build
    // can drop the module import and the registrations never fire.
    void GeneratedFormsModule;
    void MJCContractsSectionComponent;
    void MJCContractFormComponent;
}
