/**
 * Unit tests for `ContractsEngineBase` — verifying the 5-Rule BizApps Performance & Caching Standard:
 *   - BaseSingleton identity and `@RegisterForStartup()` registration
 *   - Bounded taxonomy & template loading via `Config()` with `CacheLocal` discipline
 *   - Multi-provider & impersonation safety (`ProviderToUse` override, user/provider switch eviction)
 *   - `CanRead` permission gating before firing entity loads
 *   - O(1) lookup helpers (`GetContractTypeByID`, `GetContractTypeByCode`, `GetContractTemplateTypeByID`,
 *     `GetContractTemplateByID`, `GetCurrentUsableTemplate`)
 *   - Bounded LRU per-template provisions container cache + `BaseEntity` event invalidation
 *   - `ReadContractTypeByID` zero-RunView fast path when `ContractsEngineBase` is loaded
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import {
    type BaseEntityEvent,
    type EntityInfo,
    type IMetadataProvider,
    ProviderType,
    RunView,
    StartupManager,
    type UserInfo,
} from '@memberjunction/core';
import {
    CONTRACTS_ENGINE_ENTITIES,
    ContractsEngineBase,
    MAX_CACHED_TEMPLATE_PROVISIONS,
} from '../ContractsEngineBase';
import { ReadContractTypeByID } from '../contract-type-cache';
import type { ContractTemplateEntity } from '../ContractTemplateEntity';
import type { ContractTemplateProvisionEntity } from '../ContractTemplateProvisionEntity';
import type { ContractTemplateTypeEntity, ContractTypeEntity } from '../ContractTypeEntity';

const TYPE_ORDER_FORM_ID = '11111111-0000-4000-8000-000000000001';
const TYPE_CHANGE_ORDER_ID = '11111111-0000-4000-8000-000000000002';
const TMPL_TYPE_MSA_ID = '22222222-0000-4000-8000-000000000001';
const TMPL_TYPE_SOW_ID = '22222222-0000-4000-8000-000000000002';
const TMPL_V1_ID = '33333333-0000-4000-8000-000000000001';
const TMPL_V2_ID = '33333333-0000-4000-8000-000000000002';
const TMPL_DRAFT_ID = '33333333-0000-4000-8000-000000000003';
const TMPL_UNUSABLE_ID = '33333333-0000-4000-8000-000000000004';
const TMPL_SOW_ID = '33333333-0000-4000-8000-000000000005';

function makeUser(id: string): UserInfo {
    return { ID: id, Name: `User ${id}` } as unknown as UserInfo;
}

function makeContractType(overrides: Partial<ContractTypeEntity>): ContractTypeEntity {
    return {
        ID: TYPE_ORDER_FORM_ID,
        Name: 'Order Form',
        Code: 'ORDER_FORM',
        Status: 'Active',
        TemplateRequired: true,
        ContractTemplateTypeID: TMPL_TYPE_MSA_ID,
        DefaultAutoRenew: true,
        DefaultRenewalNoticeDays: 60,
        DefaultCancellationWindowDays: 30,
        DefaultAnnualIncreasePercent: 5,
        ...overrides,
    } as unknown as ContractTypeEntity;
}

function makeTemplateType(overrides: Partial<ContractTemplateTypeEntity>): ContractTemplateTypeEntity {
    return {
        ID: TMPL_TYPE_MSA_ID,
        Name: 'Master Agreement',
        Status: 'Active',
        ...overrides,
    } as unknown as ContractTemplateTypeEntity;
}

function makeTemplate(overrides: Partial<ContractTemplateEntity>): ContractTemplateEntity {
    return {
        ID: TMPL_V2_ID,
        Name: 'MSA v2',
        ContractTemplateTypeID: TMPL_TYPE_MSA_ID,
        Status: 'Published',
        IsUsable: true,
        IntroducedDate: new Date('2026-06-01T00:00:00Z'),
        __mj_CreatedAt: new Date('2026-06-01T00:00:00Z'),
        ...overrides,
    } as unknown as ContractTemplateEntity;
}

function makeProvision(id: string, templateID: string, num: string): ContractTemplateProvisionEntity {
    return {
        ID: id,
        ContractTemplateID: templateID,
        ProvisionNumber: num,
        Title: `Clause ${num}`,
        ProvisionText: `Standard text for ${num}`,
        ProvisionSortKey: num,
    } as unknown as ContractTemplateProvisionEntity;
}

interface MockProviderOptions {
    user?: UserInfo;
    deniedEntities?: string[];
    contractTypes?: ContractTypeEntity[];
    contractTemplateTypes?: ContractTemplateTypeEntity[];
    contractTemplates?: ContractTemplateEntity[];
    provisionsByTemplate?: Record<string, ContractTemplateProvisionEntity[]>;
}

function createMockProvider(options: MockProviderOptions = {}) {
    const user = options.user ?? makeUser('UUUUUUUU-0000-4000-8000-000000000001');
    const denied = new Set((options.deniedEntities ?? []).map((n) => n.toLowerCase()));

    const allEntityNames = [
        CONTRACTS_ENGINE_ENTITIES.ContractTypes,
        CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes,
        CONTRACTS_ENGINE_ENTITIES.ContractTemplates,
        CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions,
    ];

    const entities: EntityInfo[] = allEntityNames.map(
        (Name) =>
            ({
                ID: `ENT-${Name}`,
                Name,
                GetUserPermisions: (_u: UserInfo) => ({
                    CanRead: !denied.has(Name.toLowerCase()),
                    CanCreate: false,
                    CanUpdate: false,
                    CanDelete: false,
                }),
            }) as unknown as EntityInfo,
    );

    const runViewCalls: Array<{ EntityName: string; ExtraFilter?: string }> = [];

    const runView = vi.fn(async (params: { EntityName: string; ExtraFilter?: string }) => {
        runViewCalls.push({ EntityName: params.EntityName, ExtraFilter: params.ExtraFilter });
        switch (params.EntityName) {
            case CONTRACTS_ENGINE_ENTITIES.ContractTypes:
                return { Success: true, Results: options.contractTypes ?? [] };
            case CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes:
                return { Success: true, Results: options.contractTemplateTypes ?? [] };
            case CONTRACTS_ENGINE_ENTITIES.ContractTemplates:
                return { Success: true, Results: options.contractTemplates ?? [] };
            case CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions: {
                const m = /'([^']+)'/.exec(params.ExtraFilter ?? '');
                const tmplId = (m?.[1] ?? '').toLowerCase();
                return { Success: true, Results: options.provisionsByTemplate?.[tmplId] ?? [] };
            }
            default:
                return { Success: true, Results: [] };
        }
    });

    const runViews = vi.fn(async (paramsList: Array<{ EntityName: string; ExtraFilter?: string }>) => {
        const results = [];
        for (const p of paramsList) {
            results.push(await runView(p));
        }
        return results;
    });

    const provider = {
        ProviderType: ProviderType.Network,
        CurrentUser: user,
        Entities: entities,
        EntityByName: (name: string) => entities.find((e) => e.Name === name),
        RunView: runView,
        RunViews: runViews,
    } as unknown as IMetadataProvider;

    return { provider, user, runView, runViews, runViewCalls };
}

/**
 * Stubs `BaseEngine.Load` on `ContractsEngineBase` so unit tests exercise `ContractsEngineBase.Config()`,
 * `CanRead` gating, `CacheLocal` configuration, `ProviderToUse`, user/provider switches, and `AdditionalLoading()`
 * without requiring a full MJ database/local-cache runtime.
 */
function spyEngineLoad(engine: ContractsEngineBase) {
    const loadCalls: Array<{
        configs: Array<{
            EntityName?: string;
            PropertyName?: string;
            AutoRefresh?: boolean;
            CacheLocal?: boolean;
        }>;
        provider: IMetadataProvider;
        forceRefresh: boolean;
        contextUser?: UserInfo;
    }> = [];

    const spy = vi
        .spyOn(engine as unknown as { Load: (...args: unknown[]) => Promise<void> }, 'Load')
        .mockImplementation(async (...rawArgs: unknown[]) => {
            const [configs, provider, forceRefresh, contextUser] = rawArgs as [
                Array<{
                    EntityName?: string;
                    PropertyName?: string;
                    AutoRefresh?: boolean;
                    CacheLocal?: boolean;
                }>,
                IMetadataProvider,
                boolean,
                UserInfo | undefined,
            ];
            loadCalls.push({ configs, provider, forceRefresh, contextUser });

            const rv = RunView.FromMetadataProvider(provider);
            for (const cfg of configs) {
                if (!cfg.EntityName || !cfg.PropertyName) continue;
                const res = await rv.RunView({ EntityName: cfg.EntityName }, contextUser);
                (engine as unknown as Record<string, unknown>)[cfg.PropertyName] = res.Results ?? [];
            }
            (engine as unknown as { _loaded: boolean })._loaded = true;
            await (engine as unknown as { AdditionalLoading: (u?: UserInfo) => Promise<void> }).AdditionalLoading(
                contextUser,
            );
        });

    return { spy, loadCalls };
}

describe('ContractsEngineBase', () => {
    beforeEach(() => {
        vi.restoreAllMocks();
        const engine = ContractsEngineBase.Instance;
        engine.InvalidateCache();
        (engine as unknown as { _loaded: boolean })._loaded = false;
    });

    it('is a BaseSingleton registered with StartupManager via @RegisterForStartup()', () => {
        const a = ContractsEngineBase.Instance;
        const b = ContractsEngineBase.Instance;
        expect(a).toBe(b);

        const registrations = StartupManager.Instance.GetRegistrations();
        const match = registrations.find((r) => r.constructor === (ContractsEngineBase as unknown));
        expect(match).toBeDefined();
    });

    it('loads bounded taxonomy & template tables with proper CacheLocal settings and builds O(1) lookups', async () => {
        const engine = ContractsEngineBase.Instance;
        const { loadCalls } = spyEngineLoad(engine);

        const orderForm = makeContractType({});
        const changeOrder = makeContractType({
            ID: TYPE_CHANGE_ORDER_ID,
            Name: 'Change Order',
            Code: 'CHANGE_ORDER',
            Status: 'Inactive',
            TemplateRequired: false,
            ContractTemplateTypeID: null,
        });
        const msaType = makeTemplateType({});
        const sowType = makeTemplateType({ ID: TMPL_TYPE_SOW_ID, Name: 'SOW', Status: 'Inactive' });
        const tmplV1 = makeTemplate({
            ID: TMPL_V1_ID,
            Name: 'MSA v1',
            IntroducedDate: new Date('2025-01-01T00:00:00Z'),
            __mj_CreatedAt: new Date('2025-01-01T00:00:00Z'),
        });
        const tmplV2 = makeTemplate({
            ID: TMPL_V2_ID,
            Name: 'MSA v2',
            IntroducedDate: new Date('2026-06-01T00:00:00Z'),
            __mj_CreatedAt: new Date('2026-06-01T00:00:00Z'),
        });
        const tmplDraft = makeTemplate({
            ID: TMPL_DRAFT_ID,
            Name: 'MSA v3 Draft',
            Status: 'Draft',
            IntroducedDate: new Date('2026-12-01T00:00:00Z'),
        });
        const tmplUnusable = makeTemplate({
            ID: TMPL_UNUSABLE_ID,
            Name: 'MSA v4 Unusable',
            IsUsable: false,
            IntroducedDate: new Date('2026-12-15T00:00:00Z'),
        });
        const tmplSow = makeTemplate({
            ID: TMPL_SOW_ID,
            Name: 'SOW v1',
            ContractTemplateTypeID: TMPL_TYPE_SOW_ID,
            IntroducedDate: new Date('2026-09-01T00:00:00Z'),
        });

        const { provider, user } = createMockProvider({
            contractTypes: [orderForm, changeOrder],
            contractTemplateTypes: [msaType, sowType],
            contractTemplates: [tmplV1, tmplDraft, tmplUnusable, tmplV2, tmplSow],
        });

        await engine.Config(false, user, provider);

        expect(loadCalls).toHaveLength(1);
        const configs = loadCalls[0].configs;
        expect(configs).toHaveLength(3);

        const typeCfg = configs.find((c) => c.EntityName === CONTRACTS_ENGINE_ENTITIES.ContractTypes);
        const tmplTypeCfg = configs.find((c) => c.EntityName === CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes);
        const tmplCfg = configs.find((c) => c.EntityName === CONTRACTS_ENGINE_ENTITIES.ContractTemplates);
        expect(typeCfg?.AutoRefresh).toBe(true);
        expect(typeCfg?.CacheLocal).toBe(true);
        expect(tmplTypeCfg?.AutoRefresh).toBe(true);
        expect(tmplTypeCfg?.CacheLocal).toBe(true);
        expect(tmplCfg?.AutoRefresh).toBe(true);
        // Contract Templates carries view-derived IsUsable (depends on FileEntityRecordLink)
        expect(tmplCfg?.CacheLocal).toBe(false);

        expect(engine.IsLoaded).toBe(true);
        expect(engine.ProviderToUse).toBe(provider);
        expect(engine.ActiveContractTypes).toEqual([orderForm]);
        expect(engine.ActiveContractTemplateTypes).toEqual([msaType]);
        expect(engine.PublishedContractTemplates.map((t) => t.ID)).toEqual([
            TMPL_V1_ID,
            TMPL_UNUSABLE_ID,
            TMPL_V2_ID,
            TMPL_SOW_ID,
        ]);

        // O(1) case-insensitive lookups
        expect(engine.GetContractTypeByID(TYPE_ORDER_FORM_ID.toUpperCase())).toBe(orderForm);
        expect(engine.GetContractTypeByCode('order_form')).toBe(orderForm);
        expect(engine.GetContractTemplateTypeByID(TMPL_TYPE_MSA_ID.toUpperCase())).toBe(msaType);
        expect(engine.GetContractTemplateByID(TMPL_V2_ID.toUpperCase())).toBe(tmplV2);

        // Current usable template resolution (scoped and unscoped)
        expect(engine.GetCurrentUsableTemplate(TMPL_TYPE_MSA_ID)?.ID).toBe(TMPL_V2_ID);
        expect(engine.GetCurrentUsableTemplate(TMPL_TYPE_SOW_ID)?.ID).toBe(TMPL_SOW_ID);
        expect(engine.GetCurrentUsableTemplate(null)?.ID).toBe(TMPL_SOW_ID); // newest usable across all types
    });

    it('gates entity loads on CanRead and skips unauthorized entities without firing RunView', async () => {
        const engine = ContractsEngineBase.Instance;
        const { loadCalls } = spyEngineLoad(engine);

        const orderForm = makeContractType({});
        const { provider, user } = createMockProvider({
            deniedEntities: [CONTRACTS_ENGINE_ENTITIES.ContractTemplates],
            contractTypes: [orderForm],
            contractTemplates: [makeTemplate({})],
        });

        await engine.Config(false, user, provider);

        expect(loadCalls).toHaveLength(1);
        const loadedEntities = loadCalls[0].configs.map((c) => c.EntityName);
        expect(loadedEntities).toContain(CONTRACTS_ENGINE_ENTITIES.ContractTypes);
        expect(loadedEntities).toContain(CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes);
        expect(loadedEntities).not.toContain(CONTRACTS_ENGINE_ENTITIES.ContractTemplates);
        expect(engine.ContractTemplates).toEqual([]);
        expect(engine.GetContractTypeByID(TYPE_ORDER_FORM_ID)).toBe(orderForm);
    });

    it('skips Load completely when user cannot read any Contracts taxonomy entities', async () => {
        const engine = ContractsEngineBase.Instance;
        const { loadCalls } = spyEngineLoad(engine);

        const { provider, user } = createMockProvider({
            deniedEntities: [
                CONTRACTS_ENGINE_ENTITIES.ContractTypes,
                CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes,
                CONTRACTS_ENGINE_ENTITIES.ContractTemplates,
            ],
        });

        await engine.Config(false, user, provider);
        expect(loadCalls).toHaveLength(0);
        expect(engine.ContractTypes).toEqual([]);
        expect(engine.ContractTemplateTypes).toEqual([]);
        expect(engine.ContractTemplates).toEqual([]);
    });

    it('follows active ProviderToUse and force-refreshes + evicts caches on user or provider switch', async () => {
        const engine = ContractsEngineBase.Instance;
        const { loadCalls } = spyEngineLoad(engine);

        const userA = makeUser('AAAAAAAA-0000-4000-8000-000000000001');
        const userB = makeUser('BBBBBBBB-0000-4000-8000-000000000002');
        const provA = createMockProvider({
            user: userA,
            contractTypes: [makeContractType({ Name: 'Type From A' })],
            provisionsByTemplate: {
                [TMPL_V1_ID]: [makeProvision('P1', TMPL_V1_ID, '1.1')],
            },
        });
        const provB = createMockProvider({
            user: userB,
            contractTypes: [makeContractType({ Name: 'Type From B' })],
            provisionsByTemplate: {
                [TMPL_V1_ID]: [makeProvision('P2', TMPL_V1_ID, '1.2')],
            },
        });

        await engine.Config(false, userA, provA.provider);
        expect(engine.ProviderToUse).toBe(provA.provider);
        expect(engine.GetContractTypeByID(TYPE_ORDER_FORM_ID)?.Name).toBe('Type From A');

        // Populate bounded provisions cache under userA/provA
        const provsA = await engine.GetTemplateProvisions(TMPL_V1_ID, false, userA);
        expect(provsA.map((p) => p.ID)).toEqual(['P1']);

        // Impersonation / provider switch to userB/provB must update ProviderToUse, force refresh, and evict provisions cache
        await engine.Config(false, userB, provB.provider);
        expect(engine.ProviderToUse).toBe(provB.provider);
        expect(loadCalls[1].forceRefresh).toBe(true);
        expect(engine.GetContractTypeByID(TYPE_ORDER_FORM_ID)?.Name).toBe('Type From B');

        const provsB = await engine.GetTemplateProvisions(TMPL_V1_ID, false, userB);
        expect(provsB.map((p) => p.ID)).toEqual(['P2']);
    });

    it('caches per-template provisions with bounded LRU cap and invalidates on BaseEntity events or explicit call', async () => {
        const engine = ContractsEngineBase.Instance;
        spyEngineLoad(engine);

        const provisionsMap: Record<string, ContractTemplateProvisionEntity[]> = {};
        const templateIDs: string[] = [];
        for (let i = 0; i <= MAX_CACHED_TEMPLATE_PROVISIONS; i++) {
            const hex = i.toString(16).padStart(12, '0');
            const id = `44444444-0000-4000-8000-${hex}`;
            templateIDs.push(id);
            provisionsMap[id] = [makeProvision(`P-${i}`, id, '1.0')];
        }

        const { provider, user, runViewCalls } = createMockProvider({
            provisionsByTemplate: provisionsMap,
        });
        await engine.Config(false, user, provider);
        runViewCalls.length = 0;

        // First read hits RunView; second read hits bounded container cache
        await engine.GetTemplateProvisions(templateIDs[0], false, user);
        await engine.GetTemplateProvisions(templateIDs[0], false, user);
        expect(runViewCalls).toHaveLength(1);

        // Simulated BaseEntity save event on Contract Template Provisions evicts that template's cache
        await (
            engine as unknown as { HandleIndividualBaseEntityEvent: (e: BaseEntityEvent) => Promise<boolean> }
        ).HandleIndividualBaseEntityEvent({
            type: 'save',
            baseEntity: {
                EntityInfo: { Name: CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions },
                ContractTemplateID: templateIDs[0],
            },
        } as unknown as BaseEntityEvent);

        await engine.GetTemplateProvisions(templateIDs[0], false, user);
        expect(runViewCalls).toHaveLength(2);

        // Fill beyond MAX_CACHED_TEMPLATE_PROVISIONS to verify LRU eviction of oldest entry
        for (let i = 1; i <= MAX_CACHED_TEMPLATE_PROVISIONS; i++) {
            await engine.GetTemplateProvisions(templateIDs[i], false, user);
        }
        const callsBeforeEvictedReread = runViewCalls.length;
        // templateIDs[0] was oldest and should have been evicted
        await engine.GetTemplateProvisions(templateIDs[0], false, user);
        expect(runViewCalls.length).toBe(callsBeforeEvictedReread + 1);
    });

    it('backs ReadContractTypeByID with zero RunView calls once loaded on the matching provider', async () => {
        const engine = ContractsEngineBase.Instance;
        spyEngineLoad(engine);

        const orderForm = makeContractType({});
        const { provider, user, runViewCalls } = createMockProvider({
            contractTypes: [orderForm],
        });

        await engine.Config(false, user, provider);
        runViewCalls.length = 0;

        const row = await ReadContractTypeByID(
            provider as unknown as Parameters<typeof ReadContractTypeByID>[0],
            TYPE_ORDER_FORM_ID,
            user,
        );
        expect(runViewCalls).toHaveLength(0);
        expect(row).toMatchObject({
            ID: TYPE_ORDER_FORM_ID,
            Name: 'Order Form',
            TemplateRequired: true,
            ContractTemplateTypeID: TMPL_TYPE_MSA_ID,
            DefaultAutoRenew: true,
            DefaultRenewalNoticeDays: 60,
        });
    });

    it('InvalidateCache resets loaded state and clears all arrays and lookup maps', async () => {
        const engine = ContractsEngineBase.Instance;
        spyEngineLoad(engine);

        const { provider, user } = createMockProvider({
            contractTypes: [makeContractType({})],
            contractTemplateTypes: [makeTemplateType({})],
            contractTemplates: [makeTemplate({})],
        });

        await engine.Config(false, user, provider);
        expect(engine.IsLoaded).toBe(true);
        expect(engine.ContractTypes).toHaveLength(1);

        engine.InvalidateCache();
        expect(engine.IsLoaded).toBe(false);
        expect(engine.ContractTypes).toEqual([]);
        expect(engine.GetContractTypeByID(TYPE_ORDER_FORM_ID)).toBeUndefined();
        expect(engine.GetContractTemplateByID(TMPL_V2_ID)).toBeUndefined();
    });
});
