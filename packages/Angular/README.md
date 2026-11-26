# `@mj-biz-apps/contracts-ng`

Angular client bootstrap package for BizApps Contracts (`mj-app.json` `packages.client[].startupExport`: `LoadMjBizappsContractsClient`).

## What Lives Here

- **`src/lib/generated/`** — CodeGen entity forms (`@RegisterClass(BaseFormComponent, ...)`), retained intact and never replaced.
- **`src/lib/form-panels/`** — `@RegisterClassEx(BaseFormPanel, ...)` contributions layered onto generated entity forms (Hero, Overview, Agreement, Parties, Dates, Renewal terms, Notes, Provenance, Lifecycle, Modifications, Re-papering, Executed agreement, Assembled document MJ Doc preview via `MJCContractDocumentPreviewPanel` + `ContractDocumentPreviewComponent`, Lineage, plus Organization/Person Agreements panels and Contract Type Defaults panel).
- **`src/lib/sections/` & `src/lib/pages/`** — `BaseResourceComponent` Explorer sections (`Contracts`, `Templates`, `Configuration`) and dashboard/grid pages using `<mj-page-layout>` chrome, `ChangeDetectionStrategy.OnPush`, `UserInfoEngine.Instance` preference persistence, and `NotifyLoadComplete()`.
- **`src/public-api.ts`** — Anti-tree-shake anchors inside `LoadMjBizappsContractsClient()` ensuring every generated form (all 7 Contracts entities), section, and contributed panel remains registered in `MJGlobal.Instance.ClassFactory`.

## Optional MJ Doc Preview (`@memberjunction/ng-artifacts`)

Per [`docs/architecture/mj-docs-rubric.md`](../../docs/architecture/mj-docs-rubric.md) and [`.mj/specs/mj-docs-contract-draft-integration.md`](../../.mj/specs/mj-docs-contract-draft-integration.md):

- **Assembled Contract Draft Preview (`MJCContractDocumentPreviewPanel` / `ContractDocumentPreviewComponent`):** When `Contract.DocumentArtifactID` is set on a saved contract, the contributed `BaseFormPanel` (`slot: 'after-related'`, `contributionKey: 'documentPreview'`) loads `MJ: Artifacts` and `MJ: Artifact Versions` metadata in a single batched `ScopedRunView(provider).RunViews([...])` call (`ResultType: 'simple'`, skipping `Content` blobs) and renders the linked document inline via `@memberjunction/ng-artifacts@6.3.0-edge.1` (`ArtifactsModule` + `<mj-artifact-viewer-panel>` + `ArtifactIconService`). `@memberjunction/ng-artifacts` is declared as a `^6.3.0-edge.1` peerDependency + `6.3.0-edge.1` devDependency (never in `dependencies`).
- **Dual Form Registration Parity:** The generated `@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts')` host form (and all other generated entity forms) remain active and registered; the preview panel augments the Contract form without replacing it.
- **Backward-Compatible & Resilient States:**
  - `DocumentArtifactID === null` → clean unlinked empty state keeping `Contract.Notes`, relational clause modifications, and Executed Agreement file attachment controls (`MJ: Files` `'Executed Agreement'`) fully usable.
  - Zero accessible `ArtifactVersion` rows or RLS/permission-restricted artifacts → non-fatal graceful fallback (`no-versions` / `restricted`) with zero uncaught errors.
  - Rapid Contract record switching → monotonically increasing `loadSequence` token cancels/ignores stale async completions under `ChangeDetectionStrategy.OnPush`.
- **UI Architecture & OpenApp v3 Standards:** No data-access service layer ([`docs/ui-architecture.md`](../../docs/ui-architecture.md)); bind directly to `BaseEntity`, `ContractsEngineBase` (never caching unbounded artifacts), and provider-scoped `RunView`/`RunViews`. Enforced by `src/__tests__/ContractDocumentPreview.spec.ts` and `src/__tests__/ContractOpenAppParity.spec.ts`: `ChangeDetectionStrategy.OnPush`, modern `@if`/`@for`/`@switch` + `inject()`, `UserInfoEngine.Instance` (zero `localStorage`), semantic `--mj-*` CSS design tokens (zero raw `#hex`/`rgb()`/`rgba()`/`hsl()` literals), `Object.prototype.hasOwnProperty.call` null-prototype safety, and zero `window.print()`.

## Build & Test

```bash
pnpm --filter @mj-biz-apps/contracts-ng build
pnpm --filter @mj-biz-apps/contracts-ng test
```
