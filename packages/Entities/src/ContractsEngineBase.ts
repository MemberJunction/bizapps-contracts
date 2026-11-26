/**
 * @fileoverview `ContractsEngineBase` — shared `BaseEngine` caching bounded Contracts taxonomy and
 * agreement-template metadata across browser and server tiers.
 *
 * Follows the 5-Rule BizApps Performance & Caching Standard:
 *   1. Bounded reference/taxonomy caching via `BaseEnginePropertyConfig` (`AutoRefresh: true`),
 *      registered with `@RegisterForStartup()`.
 *   2. Multi-provider & impersonation safety: overrides `ProviderToUse` to follow the active
 *      provider passed to `Config()`, detects user/provider switches to evict cached state and
 *      force-refresh, gates each entity load on `CanRead`, and sets `CacheLocal: true` ONLY on
 *      non-RLS global lookup entities without cross-entity derived columns.
 *   3. Single batched load through `BaseEngine.Load()` (`RunViews`), plus O(1) lookup maps kept
 *      in sync across reloads and immediate `BaseEntity` mutations.
 *   4. Bounded container caching (`ConversationEngine`-style) for per-template provisions via
 *      `GetTemplateProvisions()` with LRU eviction, `BaseEntity` event invalidation, explicit
 *      `InvalidateTemplateProvisionsCache()`, and automatic clearing on user/provider switch.
 *      Unbounded transactional tables (`Contracts`, `Contract Orders`, `Contract Template
 *      Modifications`) are NEVER cached globally here.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import {
    BaseEngine,
    BaseEnginePropertyConfig,
    type BaseEntityEvent,
    type IMetadataProvider,
    Metadata,
    RegisterForStartup,
    RunView,
    type UserInfo,
} from '@memberjunction/core';
import { ContractTemplateEntity, TEMPLATE_PUBLISHED } from './ContractTemplateEntity';
import { ContractTemplateProvisionEntity } from './ContractTemplateProvisionEntity';
import { ContractTemplateTypeEntity, ContractTypeEntity } from './ContractTypeEntity';

/** Entity names managed by {@link ContractsEngineBase}. */
export const CONTRACTS_ENGINE_ENTITIES = {
    ContractTypes: 'MJ_BizApps_Contracts: Contract Types',
    ContractTemplateTypes: 'MJ_BizApps_Contracts: Contract Template Types',
    ContractTemplates: 'MJ_BizApps_Contracts: Contract Templates',
    ContractTemplateProvisions: 'MJ_BizApps_Contracts: Contract Template Provisions',
} as const;

const UUID_SHAPE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/** Maximum number of templates whose provision lists stay cached in memory at once. */
export const MAX_CACHED_TEMPLATE_PROVISIONS = 50;

/**
 * Shared metadata & taxonomy engine for BizApps Contracts.
 *
 * Caches the bounded lookup/registry tables:
 *   - `MJ_BizApps_Contracts: Contract Types` (`CacheLocal: true`)
 *   - `MJ_BizApps_Contracts: Contract Template Types` (`CacheLocal: true`)
 *   - `MJ_BizApps_Contracts: Contract Templates` (`CacheLocal: false` — `IsUsable` is view-derived
 *     from `SourceURL` OR `MJ: File Entity Record Links`, so local storage must not pin stale state)
 *
 * Also provides a bounded, LRU-evicted per-template container cache for
 * `MJ_BizApps_Contracts: Contract Template Provisions` (`GetTemplateProvisions`), avoiding global
 * bulk-loading of `ProvisionText` (`nvarchar(max)`).
 */
@RegisterForStartup()
export class ContractsEngineBase extends BaseEngine<ContractsEngineBase> {
    private _contractTypes: ContractTypeEntity[] = [];
    private _contractTemplateTypes: ContractTemplateTypeEntity[] = [];
    private _contractTemplates: ContractTemplateEntity[] = [];

    // Multi-provider & impersonation tracking (Rule 2)
    private _activeProvider: IMetadataProvider | null = null;
    private _loadedProvider: IMetadataProvider | null = null;
    private _loadedUserId: string | null = null;
    private _engineLoaded = false;

    // O(1) lookup indices with source-array snapshots so immediate BaseEngine mutations stay indexed
    private _contractTypesByID = new Map<string, ContractTypeEntity>();
    private _contractTypesByCode = new Map<string, ContractTypeEntity>();
    private _indexedTypesRef: ContractTypeEntity[] | null = null;
    private _indexedTypesLen = -1;

    private _templateTypesByID = new Map<string, ContractTemplateTypeEntity>();
    private _indexedTemplateTypesRef: ContractTemplateTypeEntity[] | null = null;
    private _indexedTemplateTypesLen = -1;

    private _templatesByID = new Map<string, ContractTemplateEntity>();
    private _indexedTemplatesRef: ContractTemplateEntity[] | null = null;
    private _indexedTemplatesLen = -1;

    // Bounded per-template container cache for provisions (Rule 4 — LRU insertion-order Map)
    private _provisionsByTemplate = new Map<string, ContractTemplateProvisionEntity[]>();

    public constructor() {
        super();
    }

    public static get Instance(): ContractsEngineBase {
        return ContractsEngineBase.getInstance<ContractsEngineBase>();
    }

    /**
     * Always follow the active provider passed to `Config()`, falling back to `Metadata.Provider`.
     * Prevents `BaseEngine.SetProvider`'s first-wins latch from pinning an engine to a bootstrap
     * provider across impersonation or multi-provider host switches.
     */
    public override get ProviderToUse(): IMetadataProvider {
        return this._activeProvider ?? Metadata.Provider;
    }

    /**
     * True once `Config()` has loaded at least once on the current provider/user without being
     * invalidated.
     */
    public get IsLoaded(): boolean {
        return this._engineLoaded && this.Loaded;
    }

    /**
     * Returns true when `candidate` is the provider this engine is currently serving data for.
     * Used by `contract-type-cache.ts` and entity subclasses to avoid cross-provider leakage.
     */
    public MatchesProvider(candidate: unknown): boolean {
        if (!candidate || !this.IsLoaded) return false;
        const active = this._loadedProvider ?? this.ProviderToUse;
        return candidate === active || candidate === this.RunViewProviderToUse;
    }

    /**
     * Load (or refresh) the bounded Contracts taxonomy & template tables.
     *
     * Automatically detects user or provider switches (e.g., impersonation), clears derived maps
     * and per-template provision caches, and forces a fresh load. Each entity load is gated on
     * `CanRead` so restricted callers never trigger unauthorized `RunView` requests.
     */
    public async Config(
        forceRefresh: boolean = false,
        contextUser?: UserInfo,
        provider?: IMetadataProvider,
    ): Promise<void> {
        const effectiveProvider = provider ?? Metadata.Provider;
        const effectiveUser = contextUser ?? effectiveProvider?.CurrentUser;
        const incomingUserId = normalizeID(effectiveUser?.ID);

        const providerChanged =
            this._loadedProvider !== null &&
            effectiveProvider != null &&
            this._loadedProvider !== effectiveProvider;
        const userChanged =
            this._loadedUserId !== null &&
            incomingUserId !== this._loadedUserId;

        const mustRefresh = forceRefresh || providerChanged || userChanged || !this._engineLoaded;

        if (mustRefresh) {
            this.clearDerivedCaches();
        }

        this._activeProvider = provider ?? null;

        const configs: Partial<BaseEnginePropertyConfig>[] = [];
        const canReadTypes = this.canReadEntity(CONTRACTS_ENGINE_ENTITIES.ContractTypes, effectiveProvider, effectiveUser);
        const canReadTemplateTypes = this.canReadEntity(
            CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes,
            effectiveProvider,
            effectiveUser,
        );
        const canReadTemplates = this.canReadEntity(
            CONTRACTS_ENGINE_ENTITIES.ContractTemplates,
            effectiveProvider,
            effectiveUser,
        );

        if (canReadTypes) {
            configs.push({
                Type: 'entity',
                EntityName: CONTRACTS_ENGINE_ENTITIES.ContractTypes,
                PropertyName: '_contractTypes',
                OrderBy: 'Name ASC',
                AutoRefresh: true,
                CacheLocal: true,
            });
        } else {
            this._contractTypes = [];
        }

        if (canReadTemplateTypes) {
            configs.push({
                Type: 'entity',
                EntityName: CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes,
                PropertyName: '_contractTemplateTypes',
                OrderBy: 'Name ASC',
                AutoRefresh: true,
                CacheLocal: true,
            });
        } else {
            this._contractTemplateTypes = [];
        }

        if (canReadTemplates) {
            configs.push({
                Type: 'entity',
                EntityName: CONTRACTS_ENGINE_ENTITIES.ContractTemplates,
                PropertyName: '_contractTemplates',
                OrderBy: 'IntroducedDate DESC, __mj_CreatedAt DESC',
                AutoRefresh: true,
                // `vwContractTemplates.IsUsable` is derived from `SourceURL` OR `FileEntityRecordLink`,
                // so cross-session local storage could serve a stale `IsUsable` flag after file attachment.
                CacheLocal: false,
            });
        } else {
            this._contractTemplates = [];
        }

        if (configs.length === 0) {
            this._loadedProvider = effectiveProvider ?? null;
            this._loadedUserId = incomingUserId;
            this._engineLoaded = true;
            this.rebuildLookupMaps();
            return;
        }

        await this.Load(configs, effectiveProvider, mustRefresh, contextUser);
        this._loadedProvider = effectiveProvider ?? null;
        this._loadedUserId = incomingUserId;
        this._engineLoaded = this.Loaded;
        this.rebuildLookupMaps();
    }

    protected override async AdditionalLoading(_contextUser?: UserInfo): Promise<void> {
        this.rebuildLookupMaps();
    }

    /**
     * Listen for `Contract Template Provisions` save/delete events so the bounded per-template
     * container cache stays fresh, and re-index lookup maps after taxonomy entity mutations.
     */
    protected override async HandleIndividualBaseEntityEvent(event: BaseEntityEvent): Promise<boolean> {
        const entityName = (event.baseEntity?.EntityInfo?.Name ?? event.entityName ?? '').trim().toLowerCase();
        if (entityName === CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions.toLowerCase()) {
            const provision = event.baseEntity as ContractTemplateProvisionEntity | undefined;
            const templateID = provision?.ContractTemplateID;
            if (templateID) {
                this.InvalidateTemplateProvisionsCache(templateID);
            } else {
                this.InvalidateTemplateProvisionsCache();
            }
        }

        const handled = await super.HandleIndividualBaseEntityEvent(event);

        if (
            entityName === CONTRACTS_ENGINE_ENTITIES.ContractTypes.toLowerCase() ||
            entityName === CONTRACTS_ENGINE_ENTITIES.ContractTemplateTypes.toLowerCase() ||
            entityName === CONTRACTS_ENGINE_ENTITIES.ContractTemplates.toLowerCase()
        ) {
            this.rebuildLookupMaps();
        }
        return handled;
    }

    /**
     * Evict all cached taxonomy arrays, lookup maps, and bounded per-template provisions caches.
     * The next `Config()` call will perform a fresh load.
     */
    public InvalidateCache(): void {
        this._contractTypes = [];
        this._contractTemplateTypes = [];
        this._contractTemplates = [];
        this._loadedProvider = null;
        this._loadedUserId = null;
        this._engineLoaded = false;
        this.clearDerivedCaches();
    }

    /* ── Taxonomy Getters ─────────────────────────────────────────────────── */

    /** All cached Contract Types (sorted by `Name ASC`). */
    public get ContractTypes(): ContractTypeEntity[] {
        return this._contractTypes;
    }

    /** Only `Active` Contract Types (sorted by `Name ASC`). */
    public get ActiveContractTypes(): ContractTypeEntity[] {
        return this._contractTypes.filter((t) => t.Status === 'Active');
    }

    /** All cached Contract Template Types (sorted by `Name ASC`). */
    public get ContractTemplateTypes(): ContractTemplateTypeEntity[] {
        return this._contractTemplateTypes;
    }

    /** Only `Active` Contract Template Types (sorted by `Name ASC`). */
    public get ActiveContractTemplateTypes(): ContractTemplateTypeEntity[] {
        return this._contractTemplateTypes.filter((t) => t.Status === 'Active');
    }

    /** All cached Contract Templates (sorted by `IntroducedDate DESC, __mj_CreatedAt DESC`). */
    public get ContractTemplates(): ContractTemplateEntity[] {
        return this._contractTemplates;
    }

    /** Only `Published` Contract Templates. */
    public get PublishedContractTemplates(): ContractTemplateEntity[] {
        return this._contractTemplates.filter((t) => t.Status === TEMPLATE_PUBLISHED);
    }

    /* ── O(1) Lookup Helpers ──────────────────────────────────────────────── */

    /** O(1) case-insensitive UUID lookup for a Contract Type. */
    public GetContractTypeByID(id: string | null | undefined): ContractTypeEntity | undefined {
        const key = normalizeID(id);
        if (!key) return undefined;
        this.ensureTypesIndexed();
        return this._contractTypesByID.get(key);
    }

    /** O(1) case-insensitive Code lookup for a Contract Type (e.g. `'ORDER_FORM'`). */
    public GetContractTypeByCode(code: string | null | undefined): ContractTypeEntity | undefined {
        const key = (code ?? '').trim().toUpperCase();
        if (!key) return undefined;
        this.ensureTypesIndexed();
        return this._contractTypesByCode.get(key);
    }

    /** O(1) case-insensitive UUID lookup for a Contract Template Type. */
    public GetContractTemplateTypeByID(id: string | null | undefined): ContractTemplateTypeEntity | undefined {
        const key = normalizeID(id);
        if (!key) return undefined;
        this.ensureTemplateTypesIndexed();
        return this._templateTypesByID.get(key);
    }

    /** O(1) case-insensitive UUID lookup for a Contract Template. */
    public GetContractTemplateByID(id: string | null | undefined): ContractTemplateEntity | undefined {
        const key = normalizeID(id);
        if (!key) return undefined;
        this.ensureTemplatesIndexed();
        return this._templatesByID.get(key);
    }

    /**
     * Resolve the newest `Published`, `IsUsable === true` template, optionally scoped to a
     * `ContractTemplateTypeID`. Mirrors `BuildCurrentTemplateFilter` and `CurrentTemplateOrderBy`
     * (`IntroducedDate DESC` with nulls last, then `__mj_CreatedAt DESC`).
     */
    public GetCurrentUsableTemplate(contractTemplateTypeID?: string | null): ContractTemplateEntity | undefined {
        const scopedTypeID = normalizeID(contractTemplateTypeID);
        const eligible = this._contractTemplates.filter((t) => {
            if (t.Status !== TEMPLATE_PUBLISHED || t.IsUsable !== true) return false;
            if (scopedTypeID && normalizeID(t.ContractTemplateTypeID) !== scopedTypeID) return false;
            return true;
        });

        if (eligible.length === 0) return undefined;

        eligible.sort((a, b) => {
            const introDiff = compareDescNullableDate(a.IntroducedDate, b.IntroducedDate);
            if (introDiff !== 0) return introDiff;
            return compareDescNullableDate(a.__mj_CreatedAt, b.__mj_CreatedAt);
        });
        return eligible[0];
    }

    /* ── Bounded Container Cache: Per-Template Provisions (Rule 4) ────────── */

    /**
     * Load and cache the bounded list of provisions belonging to a single `ContractTemplateID`,
     * ordered by `ProvisionSortKey ASC`.
     *
     * Cached in an LRU-bounded map (`MAX_CACHED_TEMPLATE_PROVISIONS`), automatically invalidated
     * on `Contract Template Provisions` save/delete events and cleared on user/provider switch.
     */
    public async GetTemplateProvisions(
        templateID: string | null | undefined,
        forceRefresh: boolean = false,
        contextUser?: UserInfo,
    ): Promise<ContractTemplateProvisionEntity[]> {
        const trimmed = String(templateID ?? '').trim();
        if (!UUID_SHAPE.test(trimmed)) return [];
        const key = trimmed.toLowerCase();

        if (!forceRefresh && this._provisionsByTemplate.has(key)) {
            const cached = this._provisionsByTemplate.get(key)!;
            // Refresh LRU recency
            this._provisionsByTemplate.delete(key);
            this._provisionsByTemplate.set(key, cached);
            return cached;
        }

        const provider = this.ProviderToUse;
        const effectiveUser = contextUser ?? provider?.CurrentUser;
        if (!this.canReadEntity(CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions, provider, effectiveUser)) {
            return [];
        }

        const rv = RunView.FromMetadataProvider(provider);
        const result = await rv.RunView<ContractTemplateProvisionEntity>(
            {
                EntityName: CONTRACTS_ENGINE_ENTITIES.ContractTemplateProvisions,
                ExtraFilter: `ContractTemplateID = '${trimmed}'`,
                OrderBy: 'ProvisionSortKey ASC',
                ResultType: 'entity_object',
            },
            contextUser,
        );
        if (!result?.Success) {
            throw new Error(
                result?.ErrorMessage || `Could not load provisions for contract template ${trimmed}.`,
            );
        }

        const rows = result.Results ?? [];
        this.setCachedTemplateProvisions(key, rows);
        return rows;
    }

    /**
     * Evict cached provisions for one `templateID`, or for all cached templates when omitted.
     */
    public InvalidateTemplateProvisionsCache(templateID?: string | null): void {
        const key = normalizeID(templateID);
        if (key) {
            this._provisionsByTemplate.delete(key);
        } else {
            this._provisionsByTemplate.clear();
        }
    }

    /* ── Internal Helpers ─────────────────────────────────────────────────── */

    private setCachedTemplateProvisions(key: string, rows: ContractTemplateProvisionEntity[]): void {
        if (this._provisionsByTemplate.has(key)) {
            this._provisionsByTemplate.delete(key);
        } else if (this._provisionsByTemplate.size >= MAX_CACHED_TEMPLATE_PROVISIONS) {
            const oldestKey = this._provisionsByTemplate.keys().next().value;
            if (oldestKey !== undefined) {
                this._provisionsByTemplate.delete(oldestKey);
            }
        }
        this._provisionsByTemplate.set(key, rows);
    }

    private clearDerivedCaches(): void {
        this._contractTypesByID.clear();
        this._contractTypesByCode.clear();
        this._indexedTypesRef = null;
        this._indexedTypesLen = -1;

        this._templateTypesByID.clear();
        this._indexedTemplateTypesRef = null;
        this._indexedTemplateTypesLen = -1;

        this._templatesByID.clear();
        this._indexedTemplatesRef = null;
        this._indexedTemplatesLen = -1;

        this._provisionsByTemplate.clear();
    }

    private rebuildLookupMaps(): void {
        this._contractTypesByID.clear();
        this._contractTypesByCode.clear();
        for (const t of this._contractTypes) {
            const id = normalizeID(t.ID);
            if (id) this._contractTypesByID.set(id, t);
            const code = (t.Code ?? '').trim().toUpperCase();
            if (code) this._contractTypesByCode.set(code, t);
        }
        this._indexedTypesRef = this._contractTypes;
        this._indexedTypesLen = this._contractTypes.length;

        this._templateTypesByID.clear();
        for (const tt of this._contractTemplateTypes) {
            const id = normalizeID(tt.ID);
            if (id) this._templateTypesByID.set(id, tt);
        }
        this._indexedTemplateTypesRef = this._contractTemplateTypes;
        this._indexedTemplateTypesLen = this._contractTemplateTypes.length;

        this._templatesByID.clear();
        for (const tmpl of this._contractTemplates) {
            const id = normalizeID(tmpl.ID);
            if (id) this._templatesByID.set(id, tmpl);
        }
        this._indexedTemplatesRef = this._contractTemplates;
        this._indexedTemplatesLen = this._contractTemplates.length;
    }

    private ensureTypesIndexed(): void {
        if (this._indexedTypesRef !== this._contractTypes || this._indexedTypesLen !== this._contractTypes.length) {
            this.rebuildLookupMaps();
        }
    }

    private ensureTemplateTypesIndexed(): void {
        if (
            this._indexedTemplateTypesRef !== this._contractTemplateTypes ||
            this._indexedTemplateTypesLen !== this._contractTemplateTypes.length
        ) {
            this.rebuildLookupMaps();
        }
    }

    private ensureTemplatesIndexed(): void {
        if (
            this._indexedTemplatesRef !== this._contractTemplates ||
            this._indexedTemplatesLen !== this._contractTemplates.length
        ) {
            this.rebuildLookupMaps();
        }
    }

    private canReadEntity(
        entityName: string,
        provider: IMetadataProvider | null | undefined,
        user: UserInfo | undefined,
    ): boolean {
        if (!provider) return true;
        const entityInfo =
            typeof provider.EntityByName === 'function'
                ? provider.EntityByName(entityName)
                : provider.Entities?.find((e) => e.Name === entityName);
        if (!entityInfo) {
            // If metadata catalog isn't populated (e.g. lightweight test provider), allow load attempt
            return !provider.Entities || provider.Entities.length === 0;
        }
        if (!user) return true;
        if (typeof entityInfo.GetUserPermisions !== 'function') return true;
        return entityInfo.GetUserPermisions(user)?.CanRead === true;
    }
}

function normalizeID(value: string | null | undefined): string | null {
    const trimmed = String(value ?? '').trim();
    return trimmed ? trimmed.toLowerCase() : null;
}

function toTimestamp(value: Date | string | null | undefined): number | null {
    if (value == null) return null;
    const ms = value instanceof Date ? value.getTime() : new Date(value).getTime();
    return Number.isFinite(ms) ? ms : null;
}

/** Descending comparator with nulls sorted LAST (matching T-SQL `ORDER BY col DESC`). */
function compareDescNullableDate(a: Date | string | null | undefined, b: Date | string | null | undefined): number {
    const ta = toTimestamp(a);
    const tb = toTimestamp(b);
    if (ta === tb) return 0;
    if (ta === null) return 1;
    if (tb === null) return -1;
    return tb - ta;
}

/**
 * Anti-tree-shake anchor. Importing this module registers `ContractsEngineBase` via
 * `@RegisterForStartup()`; referencing it from bootstrap prevents production bundlers from
 * dropping the registration.
 */
export function LoadContractsEngine(): void {
    void ContractsEngineBase;
}
