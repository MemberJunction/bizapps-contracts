# 3 · Entities & data access

## Creating entity objects — always via Metadata

Never `new EntityClass()` — it bypasses MJ's class factory (and any registered
subclass overrides). Always:

```typescript
const md = new Metadata();
const person = await md.GetEntityObject<PersonEntity>('Person', contextUser);
```

- Use the generic parameter for full typing (`GetEntityObject<T>`, `RunView<T>`, `Load<T>`).
- **Server-side code always passes `contextUser`** (to `GetEntityObject` AND
  `RunView`) — the server serves many users; omitting it breaks isolation and
  auditing. Client-side Angular code may omit it (context is ambient).

## Loading collections — RunView

```typescript
const rv = new RunView();
const result = await rv.RunView<PersonEntity>({
    EntityName: 'Person',
    ExtraFilter: `LastName='Smith'`,
    OrderBy: 'FirstName ASC',
    ResultType: 'entity_object'
}, contextUser);
if (result.Success) { const people = result.Results ?? []; }
else { LogError(result.ErrorMessage); }
```

- **RunView does NOT throw** — check `result.Success` / `result.ErrorMessage`.
  A try/catch around it catches nothing.
- Batch independent queries with **`RunViews` (plural)** — one round trip, not
  N. Never call RunView inside a loop; load once, aggregate client-side.
- Prefer the view's denormalized fields (`run.Model`) over a second lookup by
  ID (`run.ModelID` → query).

## Save / Delete — booleans, not exceptions

`Save()`/`Delete()` return `true`/`false`; they do **not** throw on logical
failures (validation, permissions, FK violations). Always check the return
value and read errors from `entity.LatestResult?.CompleteMessage` (not
`.Message` — `CompleteMessage` combines everything).

## The spread-operator trap

BaseEntity fields are getters — the spread operator skips them.
`{ ...entity }` silently produces an object with **no** field values. Use
`{ ...entity.GetAll() }`.

## Looking up entity definitions

Use `md.EntityByName(name)` (case-insensitive, trimmed, O(1)) — never
`md.Entities.find(e => e.Name === …)` (case-sensitive scan that silently
misses). Guard the `undefined` return. Iterate `md.Entities` only when you
genuinely need all of them.

## Entity naming — the "MJ: " prefix

Newer MJ core entities are named with an `MJ: ` prefix
(`'MJ: AI Agent Runs'`, not `'AI Agent Runs'`); older ones aren't. Verify
names in the generated `entity_subclasses.ts` (the `@RegisterClass` JSDoc
shows each entity's exact name). Your own app's entities get YOUR schema
prefix (this template: `Sample App: `) via `SchemaInfo.EntityNamePrefix` +
`mj.config.cjs` `NameRulesBySchema` — that's what prevents cross-app
collisions.

## Provider awareness (multi-provider code paths)

`new Metadata()` resolves to the process-global provider. Inside a class that
owns a provider (`ProviderBase`, `BaseEngine`, `BaseEntity`) use `this` /
`this.ProviderToUse`; in helpers accept an optional
`provider?: IMetadataProvider` and fall back to the global explicitly. Global
is fine in single-provider apps, CLI scripts, and bootstrap code.
