/**
 * The three rule-check queries must reach each database in that database's own language.
 *
 * Each used to be one T-SQL string sent to every provider, so on PostgreSQL the saves that ran them
 * failed (#99). Each is now a `PlatformSQL` the provider resolves by `PlatformKey`; this runs both
 * forms through MJ's real `ResolveSQL` against a duck-typed provider — it reads only `PlatformKey`,
 * so no database.
 */
import { describe, expect, it } from 'vitest';
import { ProviderBase, type PlatformSQL } from '@memberjunction/core';
import { lineageProbeSQL, modificationsAgainstTemplateSQL } from '../ContractEntityServer.js';
import { provisionTemplateCheckSQL } from '../ContractTemplateModificationEntityServer.js';

const A = '11111111-1111-1111-1111-111111111111';
const B = '22222222-2222-2222-2222-222222222222';

function resolveFor(platform: 'sqlserver' | 'postgresql', sql: PlatformSQL): string {
    return ProviderBase.prototype.ResolveSQL.call({ PlatformKey: platform } as unknown as ProviderBase, sql);
}

const cases: { name: string; sql: PlatformSQL; aliases: string[] }[] = [
    { name: 'R-3 parent cycle probe', sql: lineageProbeSQL('ParentContractID', A, B), aliases: ['Chain', 'Depth'] },
    { name: 'R-3 successor cycle probe', sql: lineageProbeSQL('SupersededByContractID', A, B), aliases: ['Chain', 'Depth'] },
    { name: 'R-4 modifications count', sql: modificationsAgainstTemplateSQL(A, B), aliases: ['Hits'] },
    {
        name: 'template ancestry check',
        sql: provisionTemplateCheckSQL(A, B),
        aliases: ['ProvisionTemplateID', 'ProvisionTemplate', 'AncestorTemplates', 'InTree'],
    },
];

describe.each(cases)('$name — one form per database', ({ sql, aliases }) => {
    it('SQL Server keeps the T-SQL form', () => {
        const resolved = resolveFor('sqlserver', sql);
        expect(resolved).toContain('__mj_BizAppsContracts.[');
        expect(resolved).not.toContain('"');
    });

    it('PostgreSQL gets no T-SQL', () => {
        const resolved = resolveFor('postgresql', sql);
        expect(resolved).not.toMatch(/\[|\]|\bTOP\b|NVARCHAR|N'/);
        expect(resolved).toContain('__mj_BizAppsContracts."');
    });

    it('PostgreSQL quotes every alias the caller reads, so none folds to lowercase', () => {
        const resolved = resolveFor('postgresql', sql);
        for (const alias of aliases) expect(resolved).toContain(`AS "${alias}"`);
    });

    it('both forms carry the IDs they were given', () => {
        for (const platform of ['sqlserver', 'postgresql'] as const) {
            const resolved = resolveFor(platform, sql);
            expect(resolved).toContain(`'${A}'`);
            expect(resolved).toContain(`'${B}'`);
        }
    });
});

describe('recursive walks', () => {
    it('PostgreSQL declares the CTE RECURSIVE; SQL Server does not need to', () => {
        for (const sql of [lineageProbeSQL('ParentContractID', A, B), provisionTemplateCheckSQL(A, B)]) {
            expect(resolveFor('postgresql', sql)).toMatch(/^WITH RECURSIVE /);
            expect(resolveFor('sqlserver', sql)).toMatch(/^WITH (lineage|ancestry) AS/);
        }
    });

    it('the cycle probe walks the column it was asked to walk', () => {
        const resolved = resolveFor('postgresql', lineageProbeSQL('SupersededByContractID', A, B));
        expect(resolved).toContain('JOIN lineage l ON c."ID" = l."SupersededByContractID"');
        expect(resolved).not.toContain('ParentContractID');
    });
});
