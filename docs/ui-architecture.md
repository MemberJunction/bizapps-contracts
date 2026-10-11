# UI Architecture — bind to the primitives, not to a service layer

> **The rule:** no data-access service layer. Angular code works directly with MJ's primitives:
> `BaseEntity` subclasses, `RunView`, `RunQuery`, and, for server work that is not a save of the
> record in hand, a Remote Operation. Services hold Angular-shaped, non-persistent state only.

## Why this is different from ordinary Angular advice

The classical Angular service layer exists to solve four problems. In a MemberJunction app, three of
them are already solved by stronger primitives, and wrapping those primitives makes each one worse.

**Data access.** `BaseEntity` is the data access layer, and it is network-transparent:
`ContractEntity` runs against GraphQL in the browser and SQL on the server, because the provider is
injected rather than assumed. A service that wraps it is a second, weaker abstraction over an
existing one.

**Typing.** Generated entity classes are typed from the schema: the compiler knows
`ContractTemplateEntity.Status` is `'Draft' | 'Published'` and `ContractEntity.RenewalNoticeDeadline`
is `Date | null`. A service that accepts and returns DTOs re-types the same data by hand, and every
field is a place the two can drift. v1 of this app had such a DTO (`ContractDraft`, below).

**Orchestration.** Server work that is not a save is a Remote Operation: a `BaseRemotableOperation`
subclass registered under a key, with typed input and output, run in-process on the server and over
GraphQL from the browser. A service method wrapping one adds a second, weaker signature for the same
call, and one more place for the input and output shapes to disagree.

**Shared state.** The one job that remains. For cached lookup data, MJ's `BaseEngine` covers it.

## What MJ 6.1 changed for this app

v1 could not compose a contract and its modifications in the browser: the collection did not exist
client-side, and the client provider cannot open a transaction. So v1 carried `ContractDraft`
(688 lines), `ChildCollection.ts`, a `Contracts.SaveContract` remote operation and the code that
turned the draft back into entities: machinery whose only job was to carry child rows over the
wire, translating the entity shape in both directions.

Related-record collections removed the reason. [`metadata/entity-relationships/`](../metadata/entity-relationships/)
declares `Modifications` on Contracts and `Provisions` on Contract Templates; CodeGen emits them onto
the generated classes (`mjBizAppsContractsContractEntity`, `mjBizAppsContractsContractTemplateEntity`).
Declare a collection there, not with `DeclareRelatedRecords` in a subclass. CodeGen reads the
declaration from the database, so `mj sync push` runs before `mj codegen`.

`contract.Modifications.Create()` works in either tier, and `contract.Save()` writes the header and
its modifications in one transaction. From the browser the graph travels as one `MJ.SaveEntityGraph`
call.

## The primitives, by job

| Job | Primitive | In this repo |
|---|---|---|
| Load, edit, validate and save a record and its children | `BaseEntity` subclass + collection | `ContractEntity`, `contract.Modifications` |
| Filtered read over an entity | `RunView` | `ScopedRunView(...)`, the worklist grids |
| Named, parameterised query | `RunQuery` | `Contracts Special Terms` (dashboard tile) |
| Server work that is not a save of the record in hand | Remote Operation | `Contracts.Supersede` |
| Cached lookup data used across components | `BaseEngine` | none yet |
| Per-user UI preference | `UserInfoEngine` settings | the hero panel's collapsed state |

## The patterns

**Read one record and its children**

In a form panel the host form has already loaded the record: `BaseFormPanel<ContractEntity>` exposes
it as `this.Record`. Elsewhere, construct through the provider and load explicitly; both collections
are declared `Load: 'explicit'` (`Reopen` in `packages/IntegrationTests/src/fixture.ts`):

```typescript
const contract = await provider.GetEntityObject<ContractEntity>(E_CONTRACT, user);
await contract.Load(contractID);
await contract.LoadRelatedRecords('Modifications');
```

**Read a list — through the provider, typed by what you select**

Pages and related sections list records with MJ's `mj-explorer-entity-data-grid` over
`RunViewParams` (`MJCContractGridPageBase`). The base view carries joined names and derived columns,
so a grid shows names, not IDs. Reads in code go through the provider the data came from
(`loadSupersedes` in `supersede.panel.ts`):

```typescript
const rv = ScopedRunView(this.FormComponent?.ProviderToUse);
const mine = await rv.RunView<{ ID: string; ContractNumber: string }>({
    EntityName: MJC_ENTITIES.Contract,
    Fields: ['ID', 'ContractNumber'],
    ExtraFilter: `SupersededByContractID = '${me}'`,
    ResultType: 'simple',
});
```

> **Choose `ResultType` by what you will do with the rows.** `'simple'`, the default, returns plain
> objects. In MJ 6.1.5 their dates and numbers arrive as `Date` and `number` on both tiers, but they
> are not entities: no `Save()`, no `Validate()`, no collections, and a column left out of `Fields` is
> absent whatever `T` says. `RunView<T>` does not check `T` against `ResultType`, so type a simple
> read by the fields it selects, as above, not by the entity class.
>
> Ask for `'entity_object'` when you will call entity methods or save: `loadLinkedFiles` in
> `executed-agreement.panel.ts` reads `MJ: Files` as entities because Mark and Unmark save the rows
> it read. For a count, use `'count_only'` (`modificationRowsExist` in `ContractEntityServer`) or
> `MaxRows: 1` with `TotalRowCount` (the dashboard tiles).

Never load children in a loop. For a set of contracts with their modifications, one `RunView` with
`ResultType: 'entity_object'` and `IncludeRelatedRecords: ['Modifications']` loads the collection for
every row in one more query. Nothing here uses it yet.

A shape `RunView` cannot return, such as a distinct count across customers, is a stored query:
`RunQuery` by `MJC_QUERIES.SpecialTerms` and `MJC_QUERY_CATEGORY`, with the SQL in
`metadata/queries/SQL/contracts-special-terms.sql`.

**Read derived values from the view; don't re-derive them**

`State`, `DaysToEnd`, `DaysUntilNoticeDeadline`, `RenewalNoticeDeadline`, `IsAwaitingDocument` and
`IsInCancellationWindow` are computed in the app's base view. Panels read them off the record
(`this.Record?.State`); worklist filters compare them (`NOTICE_WINDOW_OPEN` is
`DaysUntilNoticeDeadline >= 0`). A TypeScript copy of a view rule drifts from it: an earlier one
disagreed with the view on the termination boundary (see the header of `contract-state.ts`). The cost
is that a contract being edited shows its last-saved state.

**Compose and save — one call, one transaction**

```typescript
const mod = await contract.Modifications.Create();   // the collection stamps ContractID
mod.ContractTemplateProvisionID = provisionID;
mod.ModificationText = text;
const ok = await contract.Save();                    // header + modifications, one transaction
// ok === false: read contract.LatestResult?.CompleteMessage. Save() does not throw on a refusal.
```

This is `addMod` in `packages/IntegrationTests/src/checks/graph-save.checks.ts`, which also checks
that a refused modification writes no header. `Create()` does not mark the collection loaded, and
loading over staged rows throws, so on a saved contract load the collection before staging rows.

In the UI today, the Modifications section (`MJCContractModificationsPanel`) is a related-entity grid
on a saved contract. A modification is created and saved on its own generated form, with `ContractID`
supplied by the grid's `NewRecordValues`. `ContractTemplateModificationEntityServer.Save()` then sets
the parent's `HasModifications` through the contract entity, so Record Changes captures it. A panel
that stages modifications on the contract binds `contract.Modifications` and leaves the write to the
form's Save; it never saves child rows itself.

**Validate before the round trip — the shared subclass**

Rules decidable from the record and its staged children live on `ContractEntity` in
`packages/Entities`, which the browser and the server both load:

```typescript
public override Validate(): ValidationResult {
    const result = super.Validate();                  // generated rules, and each staged modification
    this.refuseReservedContractNumber(result);        // a hand-typed CTR-… is refused
    // HasModifications === false is refused while modification rows are staged
    this.refuseDuplicateStagedModifications(result);  // no query: the rows are in hand
    this.refuseEndBeforeEffective(result);            // CK_Contract_Dates, on the field
    return result;
}
```

`Save()` runs `Validate()` before it writes, so in the browser a refusal costs no network call, and
an error on a staged modification names its row (`Modifications[2].…`).

> **[MJ#4002](https://github.com/MemberJunction/MJ/issues/4002) (open, reported on 6.1.0 edge
> builds):** the browser has been seen resolving the generated class instead of `ContractEntity`,
> which leaves the shared rules and methods absent client-side; a `Validate()` override that does
> not run raises no error. The server resolves `ContractEntityServer`, which extends
> `ContractEntity`, so the rules still hold on save. Treat a browser check as a preflight, never as
> the only enforcement.

**Rules that need the database — the server subclass**

`ContractEntityServer` (`packages/CoreEntitiesServer`) holds what needs a lock or a read of another
record. `ValidateAsync()` carries the contract-type placement rules, the retired-type and
unusable-template checks, lineage cycles and the supersession guards. Its verdicts reach the UI
through the failed save's `LatestResult`, attributed to fields. `Save()` mints the contract number
through `spAssignNextContractNumber` and defaults an empty template. The shared class does not
override `Save()`: a shared class that persisted would have to work on a provider that cannot open a
transaction.

One rule can span both tiers. `ContractEntity.Validate()` refuses `HasModifications = false` only when
staged rows prove modifications exist. On a saved contract whose collection was never loaded, an
empty collection means unknown, and `ContractEntityServer.ValidateAsync()` settles it with a count.

- A server subclass extends the shared subclass, not the generated class, so the server runs the
  shared rules too.
- It registers later, so the ClassFactory resolves it on the server while the browser keeps the
  shared class. `LoadMjBizappsContractsEntitiesServer()` anchors every server registration;
  `class-registration.test.ts` and `server-class-registration.test.ts` assert which class wins.
- Decisions both tiers need are free functions in `@mj-biz-apps/contracts-entities`, so a unit test
  reaches them without Angular. `default-template.ts` (`MayWriteDefaultTemplate`,
  `CurrentTemplateFilter`, `CurrentTemplateOrderBy`) serves `MJCContractAgreementPanel` and
  `ResolveServerDefaultTemplate` alike.
- The UI decides what to offer; the server decides what is allowed. `SameCustomerClause` filters the
  re-papering picker; `refuseCrossCustomerSupersession` refuses the save. If they disagree, the
  server wins.

**Server work that is not a save — the operation**

Re-papering writes the predecessor's `SupersededByContractID` from the successor's form: a write to a
record other than the one on screen. It runs as `Contracts.Supersede` (`SupersedeOperation` in
`packages/CoreEntitiesServer/src/SupersedeOperation.ts`). The panel, `MJCContractSupersedePanel`:

```typescript
const provider = (this.FormComponent?.ProviderToUse ?? Metadata.Provider) as unknown as IRemoteOperationProvider;
// input and output types are declared inline here, matching SupersedeInput / SupersedeOutput
const result = await provider.RouteOperation(SUPERSEDE_OP, { SuccessorID: this.Record.ID, ...what });
if (!result?.Success) throw new Error(result?.ErrorMessage || 'The server did not complete the request.');
this.Supersedes = result.Output?.Supersedes ?? [];   // the server's list, not a cached one
```

The operation loads both contracts through its `provider` and `user`, then lets the entity do the
work:

```typescript
predecessor.Supersede(successor);        // ContractEntity owns the rule
if (!(await predecessor.Save())) {       // ContractEntityServer.ValidateAsync() runs here
    return { Supersedes: …, Released: released, Refused: predecessor.LatestResult?.Message ?? … };
}
```

- An operation is justified only when the work is not a save of the record in hand: it writes other
  records, or the UI needs a server verdict before a save.
- It calls entity methods and `Save()`. It never restates a rule.
- It returns the state the UI renders, so the panel shows the server's answer.
- MJ prefers the typed `Execute()` on an operation class over the string-keyed `RouteOperation`.
  This app has no `MJ: Remote Operations` row, so CodeGen emits no typed class into
  `packages/Entities/src/generated/remote_operations.ts`, and `SupersedeOperation` lives in the
  server-only package, which client code must not import. Until a typed class exists, the key stays
  in one constant (`SUPERSEDE_OP`) and the panel's input and output types must match
  `SupersedeInput` and `SupersedeOutput`.
- No hand-written GraphQL resolvers (`packages/Server` holds generated ones only) and no Actions for
  code-to-code calls. Actions are for agents and workflows; `packages/Actions` has none.

**Lookups and per-user state**

This app has no engine of its own. Lookups are read where needed through a scoped `RunView`
(`typeRequiresTemplate` in `MJCContractAgreementPanel`, `loadRenewalDefaults` in `ContractEntity`).
When several components need the same lookup set, add a `BaseEngine` subclass, not an Angular
service. Per-user UI preferences go through `UserInfoEngine` settings: `MJCContractHeroPanel` keeps
its collapsed state with `GetSetting` and `SetSettingDebounced`.

## Provider scoping

Every read goes through the provider the data came from (`packages/Angular/src/lib/data/provider.ts`).
A bare `new RunView()` binds to the global provider; in a host with more than one, it reads the wrong
database and returns a wrong answer, not an error.

| Where | Provider |
|---|---|
| Form panels | `this.FormComponent?.ProviderToUse` |
| Pages and sections | `this.ProviderToUse` where the class has one (`BaseDashboard`), else `ScopedRunView()`, which falls back to `Metadata.Provider` |
| Entity subclasses | `this.RunViewProviderToUse`, with `this.ContextCurrentUser` |
| Operations | the `provider` and `user` passed to `InternalExecute` |

Entity names come from `MJC_ENTITIES` and `MJC_FOREIGN_ENTITIES` in `data/entity-names.ts`, never
string literals in a component: a mistyped name compiles and fails at runtime as an empty grid.

## Where UI code goes

Everything is under `packages/Angular/src/lib/`:

- `generated/` — CodeGen forms, one per entity. Never edited, and none is replaced: a replacement
  loses FK search, section grouping and validation display.
- `form-panels/` — the app's UX, contributed into the generated forms as `BaseFormPanel` subclasses
  registered with `@RegisterClassEx(BaseFormPanel, { key, metadata: { entity, slot, sortKey, contributionKey, … } })`.
  A panel can mount on another app's form: `MJCOrganizationAgreementsPanel` lists a customer's
  contracts on `MJ_BizApps_Common: Organizations`. `ContractFormPolicy` sets the contract form's
  layout.
- `pages/` — what the sections mount: the contract grids (`MJCContractGridPageBase` and its three
  pages), the dashboard (`MJCContractsDashboardPageComponent`, a `BaseDashboard`), and the
  modification, template and configuration pages.
- `sections/` — the three Explorer sections, `BaseResourceComponent` subclasses registered under the
  `DriverClass` names in `metadata/applications/`.
- `data/` — free functions and constants, with no state and no DI: `provider.ts`, `entity-names.ts`,
  `task-filters.ts` (one open-task filter shared by a dashboard tile and a grid pill) and
  `business-day.ts` (notice-window filters on view columns).

Panel rules:

- `contributionKey` equals the panel's `SectionKey` and differs from `replacesSectionKey`. Otherwise
  the section folds into Details or disappears (header of `contract.panels.ts`).
- The form reuses one panel instance across records. Key per-record state to the record ID
  (`loadedFor` in `supersede.panel.ts`), not to a boolean.
- Panels navigate through the host form (`FormComponent.OnFormNavigate`); pages own
  `NavigationService`.
- `LoadMjBizappsContractsClient()` in `public-api.ts` references every registered class. A panel that
  no template references survives a production build only because of that anchor.

## What a service IS still for

Angular-shaped, non-persistent state. A helper class, injected for lifetime and DI, holding nothing
that belongs in a table:

- wizard step, selection, expand/collapse, filter-panel state
- router coordination and navigation intent
- cross-component UI coordination that has no entity behind it

This app declares no services of its own. Pages and `MJCFkNavigateDirective` inject MJ's
`NavigationService`; panel state such as the picked predecessor lives on the panel.

If a method on a service loads, saves, validates or maps entity data, it is in the wrong place.

## The test to apply in review

> Could a non-Angular host — a script, a server job, another app — do this same work with the same
> objects?

If yes, it belongs on the entity, its shared or server subclass, or an operation. This repo's
example: a new contract's template default first lived only in the Agreement panel, so a contract
created anywhere else (Closed Won in the sales app, an import, a script) reached the server with no
template and was refused. The default now also runs in `ContractEntityServer.Save()`
(`ResolveServerDefaultTemplate`), on the same decisions from `default-template.ts`. The giveaway for
logic in the wrong layer is usually a DTO that mirrors an entity, or a rule that exists only in a
component.

## See also

- [`ERD.md`](ERD.md) — the as-built schema the entity classes are generated from
- [`database-migrations.md`](database-migrations.md) — schema changes, and what `metadata/` may hold
- [`metadata/entity-relationships/`](../metadata/entity-relationships/) — where `Modifications` and `Provisions` are declared (metadata, not TypeScript)
- [`claude/03-entities-and-data.md`](claude/03-entities-and-data.md) — `GetEntityObject`, `RunView`, `Save()` results, provider awareness
- [`claude/04-performance.md`](claude/04-performance.md) — `entity_object` vs `simple`, batching, `BaseEngine`
- [`claude/06-angular.md`](claude/06-angular.md) — component conventions and design tokens
- MJ 6.1: [related-record collections](https://github.com/MemberJunction/MJ/blob/lts/6.1/packages/MJCore/docs/related-record-collections.md),
  [Remote Operations](https://github.com/MemberJunction/MJ/blob/lts/6.1/guides/REMOTE_OPERATIONS_GUIDE.md),
  [UI layering](https://github.com/MemberJunction/MJ/blob/lts/6.1/guides/UI_LAYERING_GUIDE.md),
  [forms architecture](https://github.com/MemberJunction/MJ/blob/lts/6.1/guides/FORMS_ARCHITECTURE_GUIDE.md)
