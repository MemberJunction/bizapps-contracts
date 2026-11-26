# `@mj-biz-apps/contracts-ng`

Angular client bootstrap package for BizApps Contracts (`mj-app.json` `packages.client[].startupExport`: `LoadMjBizappsContractsClient`).

## What Lives Here

- **`src/lib/generated/`** — CodeGen entity forms (`@RegisterClass(BaseFormComponent, ...)`), retained intact and never replaced.
- **`src/lib/form-panels/`** — `@RegisterClassEx(BaseFormPanel, ...)` contributions layered onto generated entity forms (Hero, Overview, Agreement, Parties, Dates, Renewal terms, Notes, Provenance, Lifecycle, Modifications, Re-papering, Executed agreement, Lineage, plus Organization/Person Agreements panels and Contract Type Defaults panel).
- **`src/lib/sections/` & `src/lib/pages/`** — `BaseResourceComponent` Explorer sections (`Contracts`, `Templates`, `Configuration`) and dashboard/grid pages using `<mj-page-layout>` chrome and `NotifyLoadComplete()`.
- **`src/public-api.ts`** — Anti-tree-shake anchors inside `LoadMjBizappsContractsClient()` ensuring every generated form, section, and contributed panel remains registered in `MJGlobal.Instance.ClassFactory`.

## Optional MJ Doc Preview (`@memberjunction/ng-artifacts`)

Per [`docs/architecture/mj-docs-rubric.md`](../../docs/architecture/mj-docs-rubric.md) and [`.mj/specs/mj-docs-contract-draft-integration.md`](../../.mj/specs/mj-docs-contract-draft-integration.md):

- **Assembled Contract Draft Preview:** When `Contract.DocumentArtifactID` is set on a saved contract, an optional contributed `BaseFormPanel` renders the linked `MJ: Artifacts` draft/memo via `@memberjunction/ng-artifacts` (declared as a `^6.3.0-edge.1` peer + devDependency, never in `dependencies`).
- **Dual Form Registration Parity:** The generated `@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts')` host form remains active and registered; the preview panel augments it without replacing it.
- **Backward-Compatible & Resilient States:** Legacy/draft contracts where `DocumentArtifactID` is `null` display a clean unlinked state while keeping `Contract.Notes`, relational clause modifications, and Executed Agreement file attachment controls (`MJ: Files` `'Executed Agreement'`) fully usable. Zero-version or RLS-restricted artifacts degrade gracefully, and stale async loads are ignored on rapid contract switches.
- **UI Architecture & OpenApp v3 Standards:** No data-access service layer ([`docs/ui-architecture.md`](../../docs/ui-architecture.md)); bind directly to `BaseEntity`, `ContractsEngineBase`, and provider-scoped `RunView`/`RunViews` (`ResultType: 'simple'` for read-only lookups). Enforce `ChangeDetectionStrategy.OnPush`, modern `@if`/`@for`/`@switch` + `inject()`, `UserInfoEngine.Instance` (never `localStorage`), semantic `--mj-*` CSS design tokens (zero raw `#hex`/`rgb()`/`rgba()`/`hsl()` literals), and zero `window.print()`.

## Build & Test

```bash
pnpm --filter @mj-biz-apps/contracts-ng build
pnpm --filter @mj-biz-apps/contracts-ng test
```
