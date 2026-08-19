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
 * FORM PANELS — the record-scoped Documents panel (plan §6.5). Entity-agnostic base carried forward
 * from v1; its subclasses are re-registered against the v2 entities. The v1 subclasses named
 * Contract Terms and Contract Amendments, entities that no longer exist.
 * ========================================================================== */
import { ContractFilesPanel, ContractTemplateFilesPanel } from './lib/form-panels/record-files.panel';
export { RecordFilesPanelBase, ContractFilesPanel, ContractTemplateFilesPanel } from './lib/form-panels/record-files.panel';

export function LoadMjBizappsContractsClient(): void {
    // Importing the modules above is what registers everything; the references below are
    // anti-tree-shake anchors. Without a live use, a production build can drop the import and the
    // registrations never fire — a silent failure with no error, so one anchor per registration.
    void GeneratedFormsModule;
    void ContractFilesPanel;
    void ContractTemplateFilesPanel;
}
