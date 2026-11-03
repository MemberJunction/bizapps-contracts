/**
 * @fileoverview Shared per-provider cache for `ContractType` rows (#150).
 *
 * When a user picks or changes `ContractTypeID` on an unsaved contract form, two independent
 * consumers react on the same tick:
 *
 *   1. `ContractEntity.SeedRenewalDefaultsFromType()` (triggered by `MJCContractRenewalPanel`)
 *      reads the four `Default*` columns on `ContractType`.
 *   2. `MJCContractAgreementPanel` reads `TemplateRequired` and `ContractTemplateTypeID` on the
 *      same `ContractType` row to default or withdraw `ContractTemplateID`.
 *
 * Previously each consumer issued its own `RunView` against `MJ_BizApps_Contracts: Contract Types`
 * for the same `ID`. This module coalesces both into a single `RunView` per `(provider, typeID)`
 * — including concurrent in-flight calls on the same tick — and caches resolved rows in a
 * `WeakMap` keyed by the `IRunViewProvider` so provider-scoping is preserved and tests with
 * per-test mock providers stay isolated.
 *
 * @module @mj-biz-apps/contracts-entities
 */
import type { IRunViewProvider, UserInfo } from '@memberjunction/core';
import { RENEWAL_SEED_FIELDS, type ContractTypeRenewalDefaults } from './renewal-defaults';

const UUID_SHAPE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

/**
 * The projection of `MJ_BizApps_Contracts: Contract Types` shared by renewal-default seeding
 * and template defaulting.
 */
export interface ContractTypeCachedRow extends ContractTypeRenewalDefaults {
    ID: string;
    Name: string;
    TemplateRequired: boolean;
    ContractTemplateTypeID: string | null;
    Status: string | null;
}

const CONTRACT_TYPE_CACHE_FIELDS: string[] = [
    'ID',
    'Name',
    'TemplateRequired',
    'ContractTemplateTypeID',
    'Status',
    ...RENEWAL_SEED_FIELDS.map((f) => f.TypeField),
];

/**
 * Any provider or `RunView` instance exposing `RunView(...)`.
 */
export type ContractTypeCacheProvider = Pick<IRunViewProvider, 'RunView'>;

/**
 * Per-provider cache mapping lowercase `ContractType.ID` -> in-flight or resolved row promise.
 * Keyed by `ContractTypeCacheProvider` in a `WeakMap` so nothing leaks across requests or test stubs.
 */
const providerCache = new WeakMap<object, Map<string, Promise<ContractTypeCachedRow | null>>>();

function cacheFor(provider: ContractTypeCacheProvider): Map<string, Promise<ContractTypeCachedRow | null>> {
    const key = provider as unknown as object;
    let map = providerCache.get(key);
    if (!map) {
        map = new Map<string, Promise<ContractTypeCachedRow | null>>();
        providerCache.set(key, map);
    }
    return map;
}

/**
 * Read a `ContractType` row by ID, coalescing concurrent and repeated reads on the same provider.
 *
 *   - Returns `null` without querying if `typeID` is empty or not a valid UUID.
 *   - Throws if `RunView` reports `Success: false` (and evicts the failed entry so a later retry
 *     is not poisoned).
 *   - Evicts when no row matches `typeID`, so a missing ID is not permanently cached.
 */
export async function ReadContractTypeByID(
    provider: ContractTypeCacheProvider | null | undefined,
    typeID: string | null | undefined,
    contextUser?: UserInfo,
): Promise<ContractTypeCachedRow | null> {
    if (!provider) return null;
    const id = String(typeID ?? '').trim();
    if (!UUID_SHAPE.test(id)) return null;

    const normalizedKey = id.toLowerCase();
    const map = cacheFor(provider);
    const existing = map.get(normalizedKey);
    if (existing) return existing;

    const pending = (async (): Promise<ContractTypeCachedRow | null> => {
        try {
            const result = await provider.RunView<ContractTypeCachedRow>(
                {
                    EntityName: 'MJ_BizApps_Contracts: Contract Types',
                    ExtraFilter: `ID = '${id}'`,
                    Fields: CONTRACT_TYPE_CACHE_FIELDS,
                    ResultType: 'simple',
                },
                contextUser,
            );
            if (!result?.Success) {
                map.delete(normalizedKey);
                throw new Error(result?.ErrorMessage || `Could not read ContractType ${id}.`);
            }
            const row = result.Results?.[0] ?? null;
            if (!row) {
                map.delete(normalizedKey);
            }
            return row;
        } catch (err) {
            map.delete(normalizedKey);
            throw err;
        }
    })();

    map.set(normalizedKey, pending);
    return pending;
}

/**
 * Evict cached `ContractType` row(s) for a provider (or a specific `typeID` on that provider)
 * when a `ContractType` record is saved or deleted in the same session.
 */
export function InvalidateContractTypeCache(
    provider: ContractTypeCacheProvider | null | undefined,
    typeID?: string | null,
): void {
    if (!provider) return;
    const map = providerCache.get(provider as unknown as object);
    if (!map) return;
    if (typeID) {
        map.delete(typeID.trim().toLowerCase());
    } else {
        map.clear();
    }
}
