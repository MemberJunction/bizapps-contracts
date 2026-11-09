/**
 * Unit tests for `ResolveFixtureCompany` and `DestroyFixture` (#144).
 */
import { describe, expect, it, vi } from 'vitest';
import type { IMetadataProvider, UserInfo } from '@memberjunction/core';
import type { IntegrationCheckContext } from '@memberjunction/testing-integration/registry';
import {
    DestroyFixture,
    E_COMPANY,
    E_CONTRACT,
    FIXTURE_COMPANY_NAME,
    ResolveFixtureCompany,
    type ContractsFixture,
} from '../fixture.js';

interface FakeCompanyRecord {
    ID: string;
    Name: string;
    NewRecord: ReturnType<typeof vi.fn>;
    Load: ReturnType<typeof vi.fn>;
    Save: ReturnType<typeof vi.fn>;
    Delete: ReturnType<typeof vi.fn>;
}

function makeFakeContext(opts: {
    existingCompanyID?: string | null;
    dependentContractID?: string | null;
    createdCompanyID?: string;
}): {
    ctx: IntegrationCheckContext;
    companyEntity: FakeCompanyRecord;
    runViewSpy: ReturnType<typeof vi.fn>;
} {
    const companyEntity: FakeCompanyRecord = {
        ID: '',
        Name: '',
        NewRecord: vi.fn(() => {
            companyEntity.ID = '';
            companyEntity.Name = '';
        }),
        Load: vi.fn(async (id: string) => {
            companyEntity.ID = id;
            return true;
        }),
        Save: vi.fn(async () => {
            companyEntity.ID = opts.createdCompanyID ?? '99999999-0000-4000-8000-000000000144';
            return true;
        }),
        Delete: vi.fn(async () => true),
    };

    const runViewSpy = vi.fn(async (params: { EntityName: string }) => {
        if (params.EntityName === E_COMPANY) {
            return {
                Success: true,
                Results: opts.existingCompanyID ? [{ ID: opts.existingCompanyID }] : [],
            };
        }
        if (params.EntityName === E_CONTRACT) {
            return {
                Success: true,
                Results: opts.dependentContractID ? [{ ID: opts.dependentContractID }] : [],
            };
        }
        return { Success: true, Results: [] };
    });

    const provider = {
        RunView: runViewSpy,
        RunViews: vi.fn(),
        GetEntityObject: vi.fn(async () => companyEntity),
    } as unknown as IMetadataProvider;

    const ctx: IntegrationCheckContext = {
        Provider: provider,
        User: { ID: 'user-1' } as unknown as UserInfo,
        Schema: '__mj',
    };

    return { ctx, companyEntity, runViewSpy };
}

describe('ResolveFixtureCompany & DestroyFixture (#144)', () => {
    it('reuses an existing MJ: Companies row when one is present', async () => {
        const { ctx, companyEntity } = makeFakeContext({
            existingCompanyID: '11111111-0000-4000-8000-000000000001',
        });

        const resolved = await ResolveFixtureCompany(ctx);
        expect(resolved).toEqual({
            id: '11111111-0000-4000-8000-000000000001',
            createdCompanyID: null,
        });
        expect(companyEntity.Save).not.toHaveBeenCalled();
    });

    it('creates a fixture-owned MJ: Companies row when none exists and deletes it in DestroyFixture', async () => {
        const { ctx, companyEntity } = makeFakeContext({
            existingCompanyID: null,
            dependentContractID: null,
            createdCompanyID: '99999999-0000-4000-8000-000000000144',
        });

        const resolved = await ResolveFixtureCompany(ctx);
        expect(companyEntity.NewRecord).toHaveBeenCalledOnce();
        expect(companyEntity.Name).toBe(FIXTURE_COMPANY_NAME);
        expect(companyEntity.Save).toHaveBeenCalledOnce();
        expect(resolved).toEqual({
            id: '99999999-0000-4000-8000-000000000144',
            createdCompanyID: '99999999-0000-4000-8000-000000000144',
        });

        await DestroyFixture(ctx, {
            CompanyID: resolved.id,
            CreatedCompanyID: resolved.createdCompanyID,
        } as ContractsFixture);

        expect(companyEntity.Load).toHaveBeenCalledWith('99999999-0000-4000-8000-000000000144');
        expect(companyEntity.Delete).toHaveBeenCalledOnce();
    });

    it('preserves the fixture company if committed contracts still reference it', async () => {
        const { ctx, companyEntity } = makeFakeContext({
            existingCompanyID: null,
            dependentContractID: 'contract-still-using-company',
        });

        await DestroyFixture(ctx, {
            CompanyID: '99999999-0000-4000-8000-000000000144',
            CreatedCompanyID: '99999999-0000-4000-8000-000000000144',
        } as ContractsFixture);

        expect(companyEntity.Delete).not.toHaveBeenCalled();
    });
});
