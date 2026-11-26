# 4 · Performance & Caching — 5-Rule BizApps Standard

Every data read and cache in `bizapps-contracts` follows the **5-Rule BizApps Performance & Caching Standard**.

## Rule 1 · `BaseEngine` (`BaseSingleton` + `@RegisterForStartup()`) for Bounded Reference/Taxonomy Metadata

Small, bounded lookup and registry tables MUST be cached once per session in a `BaseEngine` subclass (`BaseEnginePropertyConfig` with `AutoRefresh: true`), never re-queried via `RunView` on every form open or widget mount.

- In this repo, **`ContractsEngineBase`** (`packages/Entities/src/ContractsEngineBase.ts`) extends `BaseEngine<ContractsEngineBase>` (`BaseSingleton` + `@RegisterForStartup()`) and caches:
  - `MJ_BizApps_Contracts: Contract Types` (`CacheLocal: true`, O(1) lookup by ID and Code)
  - `MJ_BizApps_Contracts: Contract Template Types` (`CacheLocal: true`, O(1) lookup by ID)
  - `MJ_BizApps_Contracts: Contract Templates` (`CacheLocal: false`, O(1) lookup by ID + `GetCurrentUsableTemplate()`)
- Always warm/ensure the engine at entry points with:
  ```typescript
  await ContractsEngineBase.Instance.Config(false, contextUser, provider);
  const contractType = ContractsEngineBase.Instance.GetContractTypeByID(id);
  ```
- Subscribe to `engine.ObserveProperty<E>('_contractTypes')` or `engine.DataChange$` instead of writing manual "reload after mutation" loops in Angular.
- Do **not** bulk-cache entities with large `nvarchar(max)` payload columns (like `ContractTemplateProvision.ProvisionText`) or unbounded transactional tables (`Contracts`, `Contract Orders`, `Contract Template Modifications`).

## Rule 2 · Multi-Provider, Impersonation & RLS `CacheLocal` Safety

A `BaseEngine` singleton can serve multiple providers or impersonated users across its lifetime.

- **Active `ProviderToUse` override:** Never let `BaseEngine.SetProvider`'s first-wins latch permanently pin an engine to its bootstrap provider. Store `_activeProvider = provider ?? null` in `Config()` and override:
  ```typescript
  public override get ProviderToUse(): IMetadataProvider {
      return this._activeProvider ?? Metadata.Provider;
  }
  ```
- **User & provider switch eviction:** Detect `userId` or `provider` changes in `Config()`, clear derived maps and any per-container caches, and force-refresh. Expose `InvalidateCache()` for explicit eviction.
- **`CacheLocal` discipline:** Set `CacheLocal: true` **only** on shared, non-RLS global lookup tables with no cross-entity derived columns (`Contract Types`, `Contract Template Types`). Set `CacheLocal: false` on any RLS-filtered entity or view with cross-entity virtual columns (`Contract Templates`, whose `IsUsable` depends on `MJ: File Entity Record Links`).
- **`CanRead` permission gating:** Check `provider.EntityByName(entityName)?.GetUserPermisions(effectiveUser)?.CanRead` before adding an entity config to `Load()`. Never fire an unauthorized `RunView` for a restricted caller.

## Rule 3 · Mandatory `rv.RunViews([...])` Single-Request Batching

Collapse `Promise.all([new RunView().RunView(...), ...])` and sequential independent `await rv.RunView(...)` calls into a single **`rv.RunViews([...])`** batch call (`RunView.FromMetadataProvider(provider)` / `ScopedRunView(provider)`).

| Use | When | Notes |
|---|---|---|
| `ResultType: 'entity_object'` | You will **mutate and save** the records | Full `BaseEntity` instances; `Fields` is ignored |
| `ResultType: 'simple'` + `Fields: [...]` | Read/display only | Plain objects, much faster; always pass narrow `Fields` to skip `nvarchar(max)` / JSON columns |
| `ResultType: 'count_only'` | You only need a row count | Zero row payload; read `TotalRowCount` (never `MaxRows: 1` or `Fields: ['ID']` + `.length`) |

Examples in this repo:
- **Dashboard & grid badge counts:** `RunContractCounts` batches all filter-pill and dashboard-tile counts into one `rv.RunViews([...])` call with `ResultType: 'count_only'`.
- **Form panels:** `MJCContractSupersedePanel.load()` batches `Supersedes` + eligible `Candidates` into one `rv.RunViews(...)`; `MJCContractExecutedAgreementPanel.load()` batches `MJ: File Categories` + `MJ: File Entity Record Links` into one `rv.RunViews(...)`; `MJCContractLineagePanel.load()` uses `ResultType: 'count_only'`.
- **Server guards & batch jobs:** `DescribeDeleteBlockers()` batches all FK dependency counts in one `RunViews` call; `SweepContractRenewalTerms()` batches `Contracts` + `Order Lines` in one `RunViews` call and loads `Subscriptions` once instead of a `3*N` per-contract loop; `ContractEntityServer.ValidateAsync()` memoizes `selectedTemplate()` and `supersededTarget()` so each referenced row is read at most once per validation pass.
- **Narrow projections:** `MJCModificationsPageComponent.loadTally()` passes `Fields: ['ContractTemplateProvisionID', 'ContractTemplateProvision']` so `ModificationText` (`nvarchar(max)`) is never downloaded.

## Rule 4 · `ConversationEngine`-Style Bounded Container Caching (No Arbitrary Filtered List Caches)

- **Never** cache unbounded transactional tables (`Contracts`, `Contract Orders`, `Contract Template Modifications`) globally in a singleton, and **never** cache arbitrary `ExtraFilter` search/list results in global singletons.
- **Bounded container caches are allowed** only for a single bounded parent container with:
  1. An explicit size cap / LRU eviction (e.g., `ContractsEngineBase.GetTemplateProvisions(templateID)` caps cached templates at `MAX_CACHED_TEMPLATE_PROVISIONS = 50`).
  2. Automatic invalidation on `BaseEntity` save/delete events (`HandleIndividualBaseEntityEvent`).
  3. Explicit invalidation (`InvalidateTemplateProvisionsCache(templateID?)`).
  4. Automatic eviction on user/provider switch and `InvalidateCache()`.

## Rule 5 · RLS-Safe Two-Step Entity Reads

- **Never** write raw SQL subqueries against RLS-filtered base views (`vw*`) inside another entity's `ExtraFilter` (MJ applies row filters to the entity being read, not to ad-hoc subqueries).
- When joining across RLS-scoped entities in application code, read the RLS-scoped entity first through a provider-scoped `RunView` (with `contextUser`), then pass the authorized IDs (`ID IN (...)`) into the second `RunView` (respecting `CanRead` permissions at every step).
- Never bypass RLS or read privileged entities unchecked; keep server-side enforcement intact.

---

## Deep pagination — keyset, not offset

Background jobs iterating a whole entity use `RunViewParams.AfterKey` (keyset/seek — O(log N) per page at any depth), not `StartRow` (each page re-scans everything skipped). Single-column-PK entities only; UI grids can stay on `StartRow`.

```typescript
let last: CompositeKey | undefined;
while (true) {
  const r = await rv.RunView({ EntityName: 'X', AfterKey: last, MaxRows: 500, ResultType: 'entity_object' }, user);
  if (!r.Success || r.Results.length === 0) break;
  /* process */
  if (r.Results.length < 500) break;
  last = CompositeKey.FromID(r.Results[r.Results.length - 1].ID);
}
```

## Server-side caching (know it exists)

MJAPI trusts its local cache completely (`BaseEntity` events invalidate it); small unfiltered results are auto-cached. Per-query escape hatch when you need true DB state after out-of-band SQL: `BypassCache: true`. Also: before bulk-loading an entity a loaded engine may already hold, ask `BaseEngineRegistry.Instance.TryGetCachedRecords<T>(name, { unfilteredOnly: true })` — read the returned array, never mutate it. Full doctrine lives in MJ's `guides/CACHING_AND_PUBSUB_GUIDE.md`.
