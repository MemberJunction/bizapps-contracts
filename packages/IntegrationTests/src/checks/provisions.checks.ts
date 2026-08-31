/**
 * contracts-provisions — seed completeness, including text, and natural order.
 *
 * Sequence (the hand-maintained integer) is gone; ProvisionSortKey is the computed collation
 * that makes `1.9` sort before `1.10`. These checks read the published IT template the world
 * (or fixture) committed, and — when the real 2026-02-02 MSA is present — its 71 clauses too.
 */
import {
    Assert,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
} from '@memberjunction/testing-integration/registry';
import {
    E_PROVISION,
    E_TEMPLATE,
    FindId,
    FindRows,
    Quote,
    ResolveContractsFixture,
} from '../fixture.js';

type Ctx = IntegrationCheckContext;

interface ProvisionRow {
    ID: string;
    ProvisionNumber: string;
    Title: string;
    ProvisionText: string;
    ProvisionSortKey: string | null;
}

export const ProvisionsChecks: NamedCheck[] = [
    {
        Id: 'contracts-provisions.P1',
        Name: 'P1 — the published IT template has at least four provisions',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            const rows = await loadProvisions(ctx, f.TemplateID);
            Assert(rows.length >= 4, `P1 expected ≥4 provisions, found ${rows.length}`);
        },
    },
    {
        Id: 'contracts-provisions.P2',
        Name: 'P2 — every provision on that template carries non-blank text',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            const rows = await loadProvisions(ctx, f.TemplateID);
            const blank = rows.filter((r) => !(r.ProvisionText ?? '').trim());
            Assert(
                blank.length === 0,
                `P2 ${blank.length} provision(s) have no text: ${blank.map((r) => r.ProvisionNumber).join(', ')}`,
            );
        },
    },
    {
        Id: 'contracts-provisions.P3',
        Name: 'P3 — ProvisionSortKey orders 1.9 before 1.10',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            const rows = await loadProvisions(ctx, f.TemplateID);
            const n19 = rows.findIndex((r) => r.ProvisionNumber === '1.9');
            const n110 = rows.findIndex((r) => r.ProvisionNumber === '1.10');
            Assert(n19 >= 0 && n110 >= 0, `P3 missing 1.9 or 1.10 on template ${f.TemplateID}`);
            Assert(
                n19 < n110,
                `P3 1.9 (index ${n19}) should sort before 1.10 (index ${n110}) — ProvisionSortKey is not in natural order`,
            );
        },
    },
    {
        Id: 'contracts-provisions.P4',
        Name: 'P4 — ProvisionNumber is unique within the template',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const f = await ResolveContractsFixture(ctx);
            const rows = await loadProvisions(ctx, f.TemplateID);
            const seen = new Set<string>();
            const dupes: string[] = [];
            for (const row of rows) {
                const key = row.ProvisionNumber.trim().toLowerCase();
                if (seen.has(key)) dupes.push(row.ProvisionNumber);
                seen.add(key);
            }
            Assert(dupes.length === 0, `P4 duplicate provision numbers: ${dupes.join(', ')}`);
        },
    },
    {
        Id: 'contracts-provisions.P5',
        Name: 'P5 — when the 2026-02-02 MSA is present, it has ≥70 clauses with text',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            await ResolveContractsFixture(ctx);
            const msaID = await FindId(ctx, E_TEMPLATE, `VersionLabel = '${Quote('2026-02-02')}'`);
            if (!msaID) {
                // The MSA lives in demo-data/ and is optional. The IT template (P1–P4) is the floor.
                return;
            }
            const rows = await loadProvisions(ctx, msaID);
            Assert(rows.length >= 70, `P5 MSA has ${rows.length} provisions; the seed is 71`);
            const blank = rows.filter((r) => !(r.ProvisionText ?? '').trim());
            Assert(blank.length === 0, `P5 MSA has ${blank.length} provisions with no text`);
        },
    },
];

async function loadProvisions(ctx: Ctx, templateID: string): Promise<ProvisionRow[]> {
    return FindRows<ProvisionRow>(
        ctx,
        E_PROVISION,
        `ContractTemplateID = '${templateID}'`,
        ['ID', 'ProvisionNumber', 'Title', 'ProvisionText', 'ProvisionSortKey'],
        'ProvisionSortKey ASC, ProvisionNumber ASC',
    );
}

for (const check of ProvisionsChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-provisions', {
    Setup: async (ctx) => {
        await ResolveContractsFixture(ctx);
    },
    Teardown: async () => undefined,
});
