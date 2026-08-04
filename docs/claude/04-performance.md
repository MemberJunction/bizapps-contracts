# 4 · Performance

## `entity_object` vs `simple` (the biggest easy win)

| Use | When | Notes |
|---|---|---|
| `ResultType: 'entity_object'` | You will **mutate and save** the records | Full BaseEntity instances. The `Fields` param is **ignored** (all fields load — by design, entities must be whole) |
| `ResultType: 'simple'` + `Fields: [...]` | Read/display only | Plain objects, much faster; `Fields` narrows the query — use it to skip large text/JSON columns |

Anti-pattern: loading `entity_object` just to `.map(r => r.ID)`.

## Batch everything

- `RunViews` (plural) for multiple independent queries — a dashboard should
  load in 2–3 calls, not 30.
- Never query per-item in a loop; load the range once, bucket client-side.

## Deep pagination — keyset, not offset

Background jobs iterating a whole entity use `RunViewParams.AfterKey`
(keyset/seek — O(log N) per page at any depth), not `StartRow` (each page
re-scans everything skipped). Single-column-PK entities only; UI grids can
stay on `StartRow`.

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

## Reactive caches — `BaseEngine` + `ObserveProperty`

Before building a "reload after mutation" loop in Angular, check whether a
`BaseEngine` subclass already caches the entity — subscribe to
`engine.ObserveProperty<E>('propName')` (auto-re-emits on save/delete/remote
invalidation) instead of polling. Small entity sets (dozens of rows) that you
own are worth a new engine: declare `Configs` entries and invalidation comes
free. Lazy-load with `await MyEngine.Instance.Config(false, user, provider)`
at every entry point. Don't bulk-cache entities with huge columns — use
targeted `RunView` filters for those.

## Server-side caching (know it exists)

MJAPI trusts its local cache completely (BaseEntity events invalidate it);
small unfiltered results are auto-cached. Per-query escape hatch when you need
true DB state after out-of-band SQL: `BypassCache: true`. Also: before
bulk-loading an entity a loaded engine may already hold, ask
`BaseEngineRegistry.Instance.TryGetCachedRecords<T>(name, { unfilteredOnly: true })`
— read the returned array, never mutate it. Full doctrine lives in MJ's
`guides/CACHING_AND_PUBSUB_GUIDE.md`.
