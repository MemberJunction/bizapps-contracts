/**
 * @mj-biz-apps/contracts-ng — the CLIENT BOOTSTRAP package.
 *
 * This is the package named in mj-app.json under packages.client with role "bootstrap". When the app
 * is installed (or dev-linked), MJExplorer's auto-generated open-app-bootstrap.generated.ts gains a
 * static `import '@mj-biz-apps/contracts-ng';` — ESBuild bundles it and module evaluation fires the
 * @RegisterClass decorators that make our components discoverable.
 *
 * WHAT LIVES HERE
 *   src/lib/generated/    — CodeGen Angular output (one form per entity; do not edit)
 *   src/lib/form-panels/  — BaseFormPanel contributions (plan §6.4) — our UX, layered onto the
 *                           GENERATED forms rather than replacing them
 *   src/lib/custom/       — the few bespoke components (the modification editor, §6.4 / D-22)
 *   src/lib/pages/        — BaseResourceComponent surfaces the nav points at (list, watchlist, …)
 *
 * THE V2 SHAPE, AND WHY IT IS SMALLER THAN V1'S. v1 replaced the generated Contract form with a
 * custom one at priority 2 and hand-rolled a workspace/tab shell around it. v2 keeps every generated
 * form registered and contributes panels into its slots — orders' current direction, adopted
 * wholesale (plan §6.4). A full form replacement is a last resort; contracts expects to need none.
 */

/* ============================================================================
 * GENERATED FORMS. The side-effect imports fire the @RegisterClass decorators; the re-exports are
 * what MJExplorer's class-registration manifest imports BY NAME. Without these exports the Explorer
 * bundle fails to compile with TS2305 'has no exported member'.
 * ========================================================================== */
import '@mj-biz-apps/contracts-entities';
import './lib/generated/generated-forms.module';
import { GeneratedFormsModule } from './lib/generated/generated-forms.module';
export { GeneratedFormsModule } from './lib/generated/generated-forms.module';
export { mjBizAppsContractsContractFormComponent } from './lib/generated/Entities/mjBizAppsContractsContract/mjbizappscontractscontract.form.component';
export { mjBizAppsContractsContractSequenceFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractSequence/mjbizappscontractscontractsequence.form.component';
export { mjBizAppsContractsContractTemplateFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractTemplate/mjbizappscontractscontracttemplate.form.component';
export { mjBizAppsContractsContractTemplateModificationFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractTemplateModification/mjbizappscontractscontracttemplatemodification.form.component';
export { mjBizAppsContractsContractTemplateProvisionFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractTemplateProvision/mjbizappscontractscontracttemplateprovision.form.component';
export { mjBizAppsContractsContractTemplateTypeFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractTemplateType/mjbizappscontractscontracttemplatetype.form.component';
export { mjBizAppsContractsContractTypeFormComponent } from './lib/generated/Entities/mjBizAppsContractsContractType/mjbizappscontractscontracttype.form.component';

/* ============================================================================
 * EXPLORER SECTIONS — the three top-level tabs. Each @RegisterClass key must match a DriverClass in
 * metadata/applications/.contracts-application.json; that pairing is the entire wiring, and both
 * halves are required — metadata without a class renders a dead tab, a class without metadata never
 * appears.
 * ========================================================================== */
import {
    ContractsConfigurationSectionResource,
    ContractsSectionResource,
    ContractsTemplatesSectionResource,
} from './lib/sections/contracts-sections.component';
export {
    MJCSectionBaseComponent,
    ContractsSectionResource,
    ContractsTemplatesSectionResource,
    ContractsConfigurationSectionResource,
} from './lib/sections/contracts-sections.component';
export { MJCSectionShellComponent } from './lib/sections/section-shell.component';
export * from './lib/sections/section-nav.model';
export * from './lib/data/entity-names';

/* ============================================================================
 * FORM PANELS — the app's UX, contributed onto the GENERATED forms (plan §6.4) rather than replacing
 * them. Every one of these mounts itself: the slot host discovers registrations, so nothing here is
 * referenced by a template. That is exactly why the anchors at the bottom are load-bearing.
 * ========================================================================== */
import { ContractFilesPanel, ContractTemplateFilesPanel } from './lib/form-panels/record-files.panel';
import {
    MJCContractHeroPanel,
    MJCContractLineagePanel,
    MJCContractModificationsPanel,
    MJCContractRenewalPanel,
} from './lib/form-panels/contract.panels';
import { MJCTemplateProvisionsPanel } from './lib/form-panels/template.panels';
import { MJCOrganizationAgreementsPanel } from './lib/form-panels/organization.panels';
import { MJCModificationFormComponent } from './lib/custom/modification.form.component';

export { RecordFilesPanelBase, ContractFilesPanel, ContractTemplateFilesPanel } from './lib/form-panels/record-files.panel';
export {
    MJCContractHeroPanel,
    MJCContractRenewalPanel,
    MJCContractModificationsPanel,
    MJCContractLineagePanel,
} from './lib/form-panels/contract.panels';
export { MJCTemplateProvisionsPanel } from './lib/form-panels/template.panels';
export { MJCOrganizationAgreementsPanel } from './lib/form-panels/organization.panels';

/* ============================================================================
 * THE ONE SHARED CUSTOM COMPONENT (D-22) — the modification editor, rendered inline by the contract's
 * panel AND as the body of the modification's own form. One implementation, two hosts, because MJ
 * cannot embed a child entity's form inside a parent's.
 * ========================================================================== */
export { MJCModificationEditorComponent } from './lib/custom/modification-editor.component';
export { MJCModificationFormComponent } from './lib/custom/modification.form.component';

/* Pages are exported so another app (or a dashboard) can host one directly; the sections resolve them
 * internally, so nothing here depends on these being exported. */
export * from './lib/pages/contract-grid.page';
export { MJCModificationsPageComponent } from './lib/pages/modifications.page';
export { MJCContractsDashboardPageComponent } from './lib/pages/contracts-dashboard.page';
export { MJCAgreementVersionsPageComponent, MJCAllProvisionsPageComponent } from './lib/pages/templates.page';
export {
    MJCContractTypesPageComponent,
    MJCTemplateTypesPageComponent,
    MJCNumberingPageComponent,
} from './lib/pages/configuration.page';

export function LoadMjBizappsContractsClient(): void {
    // Importing the modules above is what registers everything; the references below are
    // ANTI-TREE-SHAKE ANCHORS. Without a live use, a production build can drop an import whose class is
    // never referenced — and a dropped registration is a nav tab that mounts nothing, or a panel that
    // silently never appears, with no error either way. One anchor per registration, every time.
    void GeneratedFormsModule;

    // Sections — each is a nav tab.
    void ContractsSectionResource;
    void ContractsTemplatesSectionResource;
    void ContractsConfigurationSectionResource;

    // Panels — none of these is referenced by any template, so they exist only because of this.
    void ContractFilesPanel;
    void ContractTemplateFilesPanel;
    void MJCContractHeroPanel;
    void MJCContractRenewalPanel;
    void MJCContractModificationsPanel;
    void MJCContractLineagePanel;
    void MJCTemplateProvisionsPanel;
    void MJCOrganizationAgreementsPanel;

    // The one custom form replacement (priority 2).
    void MJCModificationFormComponent;
}
