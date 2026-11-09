/**
 * Unit tests for agent context & client tools wiring on the Contracts dashboard and worklists (#154).
 */
import { describe, expect, it } from 'vitest';
import { BuildDashboardAgentContext, BuildGridAgentContext } from '../agent-context';

describe('BuildDashboardAgentContext (#154)', () => {
    it('shapes dashboard company filter, tiles, and grid filter into agent context', () => {
        const ctx = BuildDashboardAgentContext({
            SelectedCompanyIDs: ['11111111-0000-4000-8000-000000000001'],
            AvailableCompanies: [{ ID: '11111111-0000-4000-8000-000000000001', Name: 'Acme Holdings' }],
            Tiles: [
                {
                    Id: 'to-process',
                    Label: 'To process',
                    Count: 4,
                    Detail: '1 overdue',
                    Tone: 'warn',
                    GoTo: { PageId: 'list', Preset: 'has-open-task' },
                },
                {
                    Id: 'awaiting-document',
                    Label: 'Awaiting executed document',
                    Count: 2,
                    Detail: null,
                    Tone: 'none',
                    GoTo: { PageId: 'awaiting' },
                },
            ],
            CountError: null,
            GridExtraFilter: `(State IN ('Active','Executed')) AND (CompanyID IN ('11111111-0000-4000-8000-000000000001'))`,
        });

        expect(ctx).toEqual({
            Surface: 'contracts-dashboard',
            SelectedCompanyIDs: ['11111111-0000-4000-8000-000000000001'],
            AvailableCompanies: [{ ID: '11111111-0000-4000-8000-000000000001', Name: 'Acme Holdings' }],
            Tiles: [
                {
                    Id: 'to-process',
                    Label: 'To process',
                    Count: 4,
                    Detail: '1 overdue',
                    Tone: 'warn',
                    TargetPageId: 'list',
                    TargetPreset: 'has-open-task',
                },
                {
                    Id: 'awaiting-document',
                    Label: 'Awaiting executed document',
                    Count: 2,
                    Detail: null,
                    Tone: 'none',
                    TargetPageId: 'awaiting',
                    TargetPreset: null,
                },
            ],
            CountError: null,
            GridExtraFilter: `(State IN ('Active','Executed')) AND (CompanyID IN ('11111111-0000-4000-8000-000000000001'))`,
        });
    });
});

describe('BuildGridAgentContext (#154)', () => {
    it('resolves the active pill label and shapes grid state for the agent', () => {
        const ctx = BuildGridAgentContext({
            PageKey: 'contracts-renewals',
            ActivePillId: 'notice-open',
            PendingPresetId: null,
            SearchText: 'Northwind',
            PageFilter: `State IN ('Active','Executed')`,
            ExtraFilter: `(State IN ('Active','Executed')) AND (DaysUntilNoticeDeadline >= 0)`,
            OrderBy: 'CASE WHEN RenewalNoticeDeadline IS NULL THEN 1 ELSE 0 END, RenewalNoticeDeadline ASC',
            Pills: [
                { Id: 'next120', Label: 'Ends in 120 days', Filter: 'DaysToEnd BETWEEN 0 AND 120', Count: 8 },
                { Id: 'notice-open', Label: 'Notice window open', Filter: 'DaysUntilNoticeDeadline >= 0', Count: 3, Hint: 'We can still give notice in time' },
            ],
        });

        expect(ctx).toEqual({
            Surface: 'contracts-renewals',
            ActivePillId: 'notice-open',
            ActivePillLabel: 'Notice window open',
            PendingPresetId: null,
            SearchText: 'Northwind',
            PageFilter: `State IN ('Active','Executed')`,
            ExtraFilter: `(State IN ('Active','Executed')) AND (DaysUntilNoticeDeadline >= 0)`,
            OrderBy: 'CASE WHEN RenewalNoticeDeadline IS NULL THEN 1 ELSE 0 END, RenewalNoticeDeadline ASC',
            Pills: [
                { Id: 'next120', Label: 'Ends in 120 days', Count: 8, Hint: null },
                { Id: 'notice-open', Label: 'Notice window open', Count: 3, Hint: 'We can still give notice in time' },
            ],
        });
    });
});

describe('Dashboard and grid page SetAgentContext / SetAgentClientTools wiring (#154)', () => {
    it('wires SetAgentContext and SetAgentClientTools on contracts-dashboard.page.ts and contract-grid.page.ts', async () => {
        const { readFile } = await import('node:fs/promises');
        const dashboardSource = await readFile(new URL('../../pages/contracts-dashboard.page.ts', import.meta.url), 'utf8');
        const gridSource = await readFile(new URL('../../pages/contract-grid.page.ts', import.meta.url), 'utf8');

        expect(dashboardSource).toContain('this.navigation.SetAgentContext(');
        expect(dashboardSource).toContain('this.navigation.SetAgentClientTools(');
        expect(dashboardSource).toContain("Name: 'FilterDashboardByCompanies'");
        expect(dashboardSource).toContain("Name: 'ClearDashboardCompanyFilter'");
        expect(dashboardSource).toContain("Name: 'OpenDashboardWorklist'");
        expect(dashboardSource).toContain("Name: 'OpenContractRecord'");
        expect(dashboardSource).toContain("Name: 'RefreshContractsDashboard'");

        expect(gridSource).toContain('this.navigation.SetAgentContext(');
        expect(gridSource).toContain('this.navigation.SetAgentClientTools(');
        expect(gridSource).toContain("Name: 'SelectContractFilterPill'");
        expect(gridSource).toContain("Name: 'SearchContractsGrid'");
        expect(gridSource).toContain("Name: 'OpenContractRecord'");
        expect(gridSource).toContain("Name: 'RefreshContractsGridCounts'");
    });
});
