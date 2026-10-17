/**
 * The contract-number call must reach each database in that database's own language.
 *
 * One T-SQL batch used to go to every provider, so on PostgreSQL every new contract's save failed at
 * numbering (#88). The fix is a `PlatformSQL` the provider resolves by `PlatformKey`; this pins both
 * forms and runs them through MJ's real `ResolveSQL` against a duck-typed provider — it reads only
 * `PlatformKey`, so no database.
 */
import { describe, expect, it } from 'vitest';
import { ProviderBase } from '@memberjunction/core';
import { ASSIGN_CONTRACT_NUMBER_SQL } from '../ContractEntityServer.js';

function resolveFor(platform: 'sqlserver' | 'postgresql'): string {
    return ProviderBase.prototype.ResolveSQL.call({ PlatformKey: platform } as unknown as ProviderBase, ASSIGN_CONTRACT_NUMBER_SQL);
}

describe('contract-number SQL — one form per database', () => {
    it('SQL Server reads the procedure OUTPUT through a T-SQL batch', () => {
        const sql = resolveFor('sqlserver');
        expect(sql).toContain('EXEC __mj_BizAppsContracts.spAssignNextContractNumber @ContractNumber = @contractNumber OUTPUT');
        expect(sql).toContain('AS ContractNumber');
    });

    it('PostgreSQL calls the function from a SELECT, with no T-SQL in it', () => {
        const sql = resolveFor('postgresql');
        expect(sql).toBe(`SELECT __mj_BizAppsContracts."spAssignNextContractNumber"() AS "ContractNumber";`);
        expect(sql).not.toMatch(/DECLARE|EXEC|@/);
    });

    it('the PostgreSQL alias is quoted, so the row key keeps the case the caller reads', () => {
        expect(resolveFor('postgresql')).toContain('AS "ContractNumber"');
    });
});
