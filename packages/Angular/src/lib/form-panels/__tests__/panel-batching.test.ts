/**
 * Source-wiring guards verifying the 5-Rule BizApps Performance & Caching Standard across Angular
 * form panels and pages:
 *   - `MJCContractSupersedePanel.load()` batches Supersedes + Candidates in one `RunViews` call
 *   - `MJCContractExecutedAgreementPanel.load()` batches FileCategory + FileEntityRecordLink in one `RunViews` call
 *   - `MJCContractLineagePanel.load()` uses `ResultType: 'count_only'` (not fetching every child ID)
 *   - `MJCContractAgreementPanel` warms and reads from `ContractsEngineBase`
 *   - `MJCModificationsPageComponent.loadTally()` narrows `Fields` to skip `ModificationText` (`nvarchar(max)`)
 *   - Zero dynamic `await import(` calls across form panels
 */
import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';

const readPanel = (rel: string) => readFile(new URL(rel, import.meta.url), 'utf8');

describe('Angular performance & batching wiring', () => {
    it('supersede.panel.ts batches initial load via RunViews and uses static imports only', async () => {
        const src = await readPanel('../supersede.panel.ts');
        expect(src).toContain('await rv.RunViews([');
        expect(src).not.toMatch(/await import\(/);
    });

    it('executed-agreement.panel.ts batches FileCategory + FileEntityRecordLink via RunViews', async () => {
        const src = await readPanel('../executed-agreement.panel.ts');
        expect(src).toContain('await rv.RunViews([');
        expect(src).not.toMatch(/await import\(/);
    });

    it('contract.panels.ts uses count_only for child badge count and static imports only', async () => {
        const src = await readPanel('../contract.panels.ts');
        expect(src).toContain("ResultType: 'count_only'");
        expect(src).not.toMatch(/await import\(/);
    });

    it('contract-form.panels.ts reads Contract Types and Current Usable Template from ContractsEngineBase with static imports only', async () => {
        const src = await readPanel('../contract-form.panels.ts');
        expect(src).toContain('ContractsEngineBase.Instance.Config(');
        expect(src).toContain('ContractsEngineBase.Instance.GetContractTypeByID(');
        expect(src).toContain('ContractsEngineBase.Instance.GetCurrentUsableTemplate(');
        expect(src).not.toMatch(/await import\(/);
    });

    it('modifications.page.ts narrows Fields in loadTally() to avoid downloading ModificationText', async () => {
        const src = await readPanel('../../pages/modifications.page.ts');
        expect(src).toContain("Fields: ['ContractTemplateProvisionID', 'ContractTemplateProvision']");
    });
});
