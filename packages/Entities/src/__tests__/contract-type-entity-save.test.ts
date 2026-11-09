/**
 * `ContractTypeEntity.Save()` / `.Delete()` against MJ's real `BaseEntity` and `EntityField`, with a
 * fake provider standing in for the database.
 *
 *   · #149: "No" (`false`) and "no default" (`null`) on `DefaultAutoRenew` must both reach the
 *     provider. MJ's `EntityField.Dirty` compares `bit` fields as booleans, so `false` <-> `null`
 *     reads as clean and, without the override, `Save()` returns `true` having written nothing.
 *   · #150: a save or delete evicts that type's row from the shared cache. A delete must evict the
 *     deleted ID, not the fresh one `BaseEntity.Delete()` assigns through `NewRecord()`.
 */
import { describe, expect, it, vi } from 'vitest';
import { type BaseEntity, EntityInfo, UserInfo } from '@memberjunction/core';
import { ContractTypeEntity } from '../ContractTypeEntity';
import { ReadContractTypeByID } from '../contract-type-cache';

const ENTITY_ID = 'E0000000-0000-4000-8000-000000000001';
const ROLE_ID = 'R0000000-0000-4000-8000-000000000001';
const TYPE_ID = '33333333-0000-4000-8000-000000001001';

function contractTypeEntityInfo(): EntityInfo {
    const field = (Name: string, Type: string, Sequence: number, extra: Record<string, unknown> = {}) => ({
        ID: `F${Sequence}`,
        EntityID: ENTITY_ID,
        Name,
        Type,
        Sequence,
        AllowsNull: false,
        AllowUpdateAPI: true,
        ...extra,
    });
    return new EntityInfo({
        ID: ENTITY_ID,
        Name: 'MJ_BizApps_Contracts: Contract Types',
        SchemaName: '__mj_BizAppsContracts',
        BaseTable: 'ContractType',
        BaseView: 'vwContractTypes',
        AllowCreateAPI: true,
        AllowUpdateAPI: true,
        AllowDeleteAPI: true,
        EntityFields: [
            field('ID', 'uniqueidentifier', 1, { IsPrimaryKey: true, AllowUpdateAPI: false }),
            field('Name', 'nvarchar', 2, { Length: 200 }),
            field('DefaultAutoRenew', 'bit', 3, { AllowsNull: true }),
        ],
        EntityPermissions: [
            { ID: 'P1', EntityID: ENTITY_ID, RoleID: ROLE_ID, CanCreate: true, CanRead: true, CanUpdate: true, CanDelete: true },
        ],
    });
}

function loadedType(defaultAutoRenew: boolean | null) {
    const writes: Record<string, unknown>[] = [];
    const reads: string[] = [];
    const user = new UserInfo(null as never, { ID: 'U1', Name: 'Test', UserRoles: [{ UserID: 'U1', RoleID: ROLE_ID }] });
    const provider = {
        CurrentUser: user,
        Save: vi.fn(async (entity: BaseEntity, _user?: unknown, _options?: unknown) => {
            writes.push(entity.GetAll());
            return entity.GetAll();
        }),
        Delete: vi.fn(async () => true),
        RunView: vi.fn(async (params: { ExtraFilter: string }) => {
            reads.push(params.ExtraFilter);
            return { Success: true, Results: [{ ID: TYPE_ID, Name: 'Order Form', DefaultAutoRenew: defaultAutoRenew }] };
        }),
    };
    const entity = new ContractTypeEntity(contractTypeEntityInfo(), provider as never);
    entity.ContextCurrentUser = user;
    entity.LoadFromData({ ID: TYPE_ID, Name: 'Order Form', DefaultAutoRenew: defaultAutoRenew });
    return { entity, provider, writes, reads };
}

describe('ContractTypeEntity.Save — DefaultAutoRenew null vs false (#149)', () => {
    it('writes "no default" over "No" although MJ reports the field clean', async () => {
        const { entity, writes } = loadedType(false);
        entity.DefaultAutoRenew = null;
        expect(entity.GetFieldByName('DefaultAutoRenew')?.Dirty).toBe(false);

        await expect(entity.Save()).resolves.toBe(true);
        expect(writes).toHaveLength(1);
        expect(writes[0].DefaultAutoRenew).toBeNull();
    });

    it('writes "No" over "no default"', async () => {
        const { entity, writes } = loadedType(null);
        entity.DefaultAutoRenew = false;

        await expect(entity.Save()).resolves.toBe(true);
        expect(writes).toHaveLength(1);
        expect(writes[0].DefaultAutoRenew).toBe(false);
    });

    it('keeps the caller\'s other save options when it forces the write', async () => {
        const { entity, provider } = loadedType(false);
        entity.DefaultAutoRenew = null;

        await entity.Save({ IgnoreDirtyState: false, SkipEntityActions: true } as never);
        const options = provider.Save.mock.calls[0][2] as { IgnoreDirtyState: boolean; SkipEntityActions?: boolean };
        expect(options.IgnoreDirtyState).toBe(true);
        expect(options.SkipEntityActions).toBe(true);
    });

    it('still skips the provider when nothing changed', async () => {
        for (const value of [true, false, null]) {
            const { entity, writes } = loadedType(value);
            await expect(entity.Save()).resolves.toBe(true);
            expect(writes).toHaveLength(0);
        }
    });
});

describe('ContractTypeEntity cache invalidation (#150)', () => {
    it('evicts the type\'s cached row after a save', async () => {
        const { entity, provider, reads } = loadedType(true);
        await ReadContractTypeByID(provider, TYPE_ID);
        entity.Name = 'Order Form (renamed)';
        await expect(entity.Save()).resolves.toBe(true);

        await ReadContractTypeByID(provider, TYPE_ID);
        expect(reads).toHaveLength(2);
    });

    it('evicts the deleted ID, not the one NewRecord() assigns afterwards', async () => {
        const { entity, provider, reads } = loadedType(true);
        await ReadContractTypeByID(provider, TYPE_ID);
        await expect(entity.Delete()).resolves.toBe(true);
        expect(entity.ID).not.toBe(TYPE_ID);

        await ReadContractTypeByID(provider, TYPE_ID);
        expect(reads).toHaveLength(2);
    });
});
