# AGENTS.md — BizApps Contracts Agent Guide

This file provides repository-specific instructions for coding agents working in **`MemberJunction/bizapps-contracts`**.
It complements [`CLAUDE.md`](CLAUDE.md) and the topic guides under [`docs/claude/`](docs/claude/README.md).

## Critical Non-Negotiable Rules

1. **Zero `any` / lazy `unknown`:** Never use `any`, `as any`, `<any>`, or `unknown` as a lazy shortcut. Derive entity field types from generated entity classes (`Entity['Field']`).
2. **Zero `.Get()` / `.Set()` on generated fields:** Always use strongly-typed properties on generated or shared entity subclasses.
3. **`BaseSingleton` for all singletons:** Always extend `BaseSingleton<T>` (or `BaseEngine<T>`, which extends `BaseSingleton<T>`) — never `private static _instance`.
4. **Static imports only:** Default to static `import` at top of file. Never use dynamic `await import(...)` unless narrowly justified (Angular lazy routes, optional peer deps, measured bundle-size deferral, or unbreakable circular dep).
5. **No cross-package re-exports:** Each package exports only what it defines. Consumers import types from their owning package.
6. **Modern Angular syntax:** Use `@if` / `@for` / `@switch` and `inject()` in Angular components. Persist user preferences via `UserInfoEngine.Instance` (never `localStorage`/`sessionStorage`).
7. **No data-access service layer:** [`docs/ui-architecture.md`](docs/ui-architecture.md) is binding. Bind directly to `BaseEntity` subclasses, `ContractsEngineBase`, `RunView`/`RunViews`, `RunQuery`, and Remote Operations.
8. **Incremental migrations only:** [`docs/database-migrations.md`](docs/database-migrations.md) is binding. Never edit the baseline or already-released migrations; metadata belongs in `metadata/*.json`, never ad-hoc migration SQL.
9. **Safe git & CI compliance:** Never commit directly to `next` or `main`. Stage files explicitly (`git add <file>`). Never squash-merge PRs (use standard merge commits). Never modify protected CI scripts unless explicitly requested. Add a `.changeset/*.md` file when changing published packages.
10. **Run build & unit tests:** Always run `pnpm run build:packages` and `pnpm run test` (and update/add tests for any changed behavior) before finishing.

## 5-Rule BizApps Performance & Caching Standard

Full doctrine & examples live in [`docs/claude/04-performance.md`](docs/claude/04-performance.md).

### 1. `BaseEngine` (`BaseSingleton` + `@RegisterForStartup()`) for Bounded Reference/Taxonomy Metadata
- Cache small, bounded reference/taxonomy tables once per session via `BaseEnginePropertyConfig` (`AutoRefresh: true`), never via per-component `RunView` calls.
- **`ContractsEngineBase`** (`packages/Entities/src/ContractsEngineBase.ts`) caches:
  - `MJ_BizApps_Contracts: Contract Types` (`CacheLocal: true`, O(1) lookup by ID/Code)
  - `MJ_BizApps_Contracts: Contract Template Types` (`CacheLocal: true`, O(1) lookup by ID)
  - `MJ_BizApps_Contracts: Contract Templates` (`CacheLocal: false`, O(1) lookup by ID + `GetCurrentUsableTemplate()`)
- Always warm at entry points with `await ContractsEngineBase.Instance.Config(false, contextUser, provider)`.
- Use `engine.ObserveProperty<E>(...)` or `engine.DataChange$` for reactive Angular updates.

### 2. Multi-Provider, Impersonation & RLS `CacheLocal` Safety
- Override `ProviderToUse` to return `this._activeProvider ?? Metadata.Provider` (storing `_activeProvider = provider ?? null` in `Config()`) so the engine never permanently latches to its bootstrap provider.
- Auto-detect user ID or provider switches in `Config()` to clear derived maps/container caches and force-refresh; expose `InvalidateCache()`.
- Set `CacheLocal: false` on any RLS-filtered entity or view with cross-entity derived columns (e.g., `Contract Templates`, whose `IsUsable` depends on `MJ: File Entity Record Links`). Set `CacheLocal: true` **only** on shared non-RLS global lookup tables.
- Gate every entity load on `provider.EntityByName(name)?.GetUserPermisions(effectiveUser)?.CanRead` before invoking `Load()`.

### 3. Mandatory `rv.RunViews([...])` Single-Request Batching
- Collapse `Promise.all([new RunView().RunView(...), ...])` and independent sequential `await rv.RunView(...)` calls into a single **`RunView.FromMetadataProvider(provider).RunViews([...])`** (or `ScopedRunView(provider).RunViews([...])`) call.
- Use `ResultType: 'simple'` + narrow `Fields: [...]` whenever entity mutation is not needed (skipping `nvarchar(max)` columns such as `ModificationText` and `ProvisionText`).
- Use `ResultType: 'count_only'` (reading `TotalRowCount`) whenever only a count is needed — never `MaxRows: 1` or `Fields: ['ID']` + `.length`.
- Reference implementations in this repo: `RunContractCounts`, `DescribeDeleteBlockers`, `SweepContractRenewalTerms`, `MJCContractSupersedePanel.load()`, `MJCContractExecutedAgreementPanel.load()`, `MJCContractLineagePanel.load()`, and `ContractEntityServer.ValidateAsync()` (`selectedTemplate()` / `supersededTarget()`).

### 4. `ConversationEngine`-Style Bounded Container Caching (No Arbitrary Filtered List Caches)
- **Never** globally cache unbounded transactional tables (`Contracts`, `Contract Orders`, `Contract Template Modifications`) or arbitrary `ExtraFilter` search queries in singletons.
- Cache bounded per-container bundles ONLY with an explicit LRU/size cap, `BaseEntity` event invalidation, explicit `Invalidate*()` methods, and user/provider-switch eviction — see `ContractsEngineBase.GetTemplateProvisions(templateID)` (`MAX_CACHED_TEMPLATE_PROVISIONS = 50`).

### 5. RLS-Safe Two-Step Entity Reads
- Never write raw SQL subqueries against RLS-filtered `vw*` base views inside `ExtraFilter`.
- Read the RLS-scoped entity first via a provider-scoped `RunView` (respecting `CanRead` permissions), then pass the resulting `ID IN (...)` into the dependent `RunView`. Never bypass RLS or read privileged entities unchecked.

## MJ Docs (`MJ: Artifacts`) vs. `MJ: Comments` vs. Quick Notes Rubric

Full rubric, entity boundary matrix, and Mermaid dataflow live in [`docs/architecture/mj-docs-rubric.md`](docs/architecture/mj-docs-rubric.md); formal EARS requirements and CUJs live in [`.mj/specs/mj-docs-contract-draft-integration.md`](.mj/specs/mj-docs-contract-draft-integration.md).

- **MJ Docs (`MJ: Artifacts`):** Store versioned, rich long-form documents — **Assembled Contract Drafts**, **AI Contract Review Memos**, and **Executive Summaries** — linked via optional nullable `Contract.DocumentArtifactID` (`UNIQUEIDENTIFIER NULL`, `FK -> [__mj].[Artifact]([ID])`) and rendered optionally via `@memberjunction/ng-artifacts`. Do **not** conflate with signed executed PDFs (`MJ: Files` + `'Executed Agreement'` category).
- **`MJ: Comments`:** Use for threaded human/agent discussion, review feedback, and negotiation commentary anchored to entities.
- **Quick Notes & Relational Columns:** Keep atomic `ContractTemplateProvision` and `ContractTemplateModification` clause rows and `Contract.Notes` strictly relational so clause-assembly rules, obligation reporting, and approval routing stay SQL-queryable. Never globally cache unbounded `MJ: Artifacts` / `MJ: Artifact Versions` rows in `ContractsEngineBase`.
- **`PUBLISH_NO_BREAK_POLICY.md` & `@memberjunction/*@6.3.0-edge.1` Guardrails:** Schema changes are strictly additive (nullable FK, zero breaking column drops/renames/narrowings). Declare `@memberjunction/ng-artifacts` as a `^6.3.0-edge.1` peer + devDependency (never in `dependencies`), preserve Dual Form Registration Parity (`BaseFormComponent` + contributed `BaseFormPanel`), use `ChangeDetectionStrategy.OnPush`, semantic `--mj-*` tokens (zero raw `#hex`/`rgb()`/`rgba()`/`hsl()`), `UserInfoEngine.Instance`, and zero `window.print()`.
- **Deterministic PostgreSQL Parity:** Generate every `migrations-pg/*.pg.sql` counterpart strictly via `mj migrate convert --split --bake-codegen` (with line-1 `-- @mj-pg-provenance: split-bake v1` header; never freehand SQL or legacy `mj sql-convert`) and verify 6-category SQL Server <-> PostgreSQL schema-delta equivalence with zero deploy-time `mj codegen`.

## Key Packages

- `packages/Entities` (`@mj-biz-apps/contracts-entities`, [`README.md`](packages/Entities/README.md)): Generated entities (including optional `Contract.DocumentArtifactID`), shared `BaseEntity` subclasses, `ContractsEngineBase`, `contract-type-cache`, pure domain helpers (`default-template`, `renewal-defaults`, `contract-state`, `supersede-candidates`, `source-record-candidates`).
- `packages/CoreEntitiesServer` (`@mj-biz-apps/contracts-core-entities-server`): Server-only `BaseEntity` subclasses, `SupersedeOperation`, `delete-guard`, `renewal-terms`.
- `packages/Angular` (`@mj-biz-apps/contracts-ng`, [`README.md`](packages/Angular/README.md)): Client bootstrap, generated forms, `BaseFormPanel` contributions (including optional `@memberjunction/ng-artifacts` contract draft preview), Explorer sections and dashboard/grid pages.
- `packages/Server` (`@mj-biz-apps/contracts-server`): Generated GraphQL resolvers + `SweepRenewalTermsAction`.
- `packages/IntegrationTests` ([`README.md`](packages/IntegrationTests/README.md)): Live-DB integration test bundles.
