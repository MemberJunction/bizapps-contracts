/**
 * The contract-number call must reach each database in that database's own language.
 *
 * One T-SQL batch used to go to every provider, so on PostgreSQL every new contract's save failed at
 * numbering (#88). The fix is a `PlatformSQL` the provider resolves by `PlatformKey`; this pins both
 * forms and runs them through MJ's real `ResolveSQL` against a duck-typed provider — it reads only
 * `PlatformKey`, so no database.
 */
import { describe, expect, it, vi } from 'vitest';
import {
    DocumentNumberingEngine,
    InMemoryDocumentSequenceStore,
    ProviderBase,
} from '@memberjunction/core';
import {
    CONTRACT_DOCUMENT_NUMBER_POLICY,
    CONTRACT_NUMBER_SEQUENCE_KEY,
} from '@mj-biz-apps/contracts-entities';
import {
    ASSIGN_CONTRACT_NUMBER_SQL,
    ContractStoredProcSequenceStore,
} from '../ContractEntityServer.js';

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

    it('allocates and formats CTR-###### via ContractStoredProcSequenceStore and DocumentNumberingEngine', async () => {
        const executeSQL = vi.fn().mockResolvedValue([{ ContractNumber: 'CTR-000042' }]);
        const provider = {
            PlatformKey: 'sqlserver',
            ResolveSQL: (platformSql: typeof ASSIGN_CONTRACT_NUMBER_SQL) =>
                ProviderBase.prototype.ResolveSQL.call({ PlatformKey: 'sqlserver' } as never, platformSql),
            ExecuteSQL: executeSQL,
        } as never;

        const store = new ContractStoredProcSequenceStore(new InMemoryDocumentSequenceStore());
        const seq = await store.AllocateNext({
            sequenceKey: CONTRACT_NUMBER_SEQUENCE_KEY,
            scopeKey: '__GLOBAL__',
            startAt: 1,
            incrementBy: 1,
            provider,
            contextUser: undefined,
        });
        expect(seq).toBe(42);
        expect(executeSQL).toHaveBeenCalledOnce();

        const formatted = DocumentNumberingEngine.Instance.FormatPattern(
            CONTRACT_DOCUMENT_NUMBER_POLICY,
            seq,
            { EntityInfo: { Name: 'MJ_BizApps_Contracts: Contracts' } } as never,
            undefined,
            new Date('2026-08-21T00:00:00Z'),
            2026,
        );
        expect(formatted).toBe('CTR-000042');
    });

    it('delegates non-contract sequence keys to the fallback IDocumentSequenceStore and throws when the sproc returns empty', async () => {
        const fallback = new InMemoryDocumentSequenceStore();
        const store = new ContractStoredProcSequenceStore(fallback);
        const emptyProvider = {
            PlatformKey: 'sqlserver',
            ResolveSQL: () => 'SELECT NULL;',
            ExecuteSQL: vi.fn().mockResolvedValue([]),
        } as never;

        const otherSeq = await store.AllocateNext({
            sequenceKey: 'Other.Entity.Number',
            scopeKey: '__GLOBAL__',
            startAt: 10,
            incrementBy: 1,
            provider: emptyProvider,
            contextUser: undefined,
        });
        expect(otherSeq).toBe(10);

        await expect(
            store.AllocateNext({
                sequenceKey: CONTRACT_NUMBER_SEQUENCE_KEY,
                scopeKey: '__GLOBAL__',
                startAt: 1,
                incrementBy: 1,
                provider: emptyProvider,
                contextUser: undefined,
            }),
        ).rejects.toThrow(/spAssignNextContractNumber returned nothing/);
    });
});
