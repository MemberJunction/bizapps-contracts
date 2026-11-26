# `@mj-biz-apps/contracts-entities`

Generated entity classes, shared `BaseEntity` subclasses, `ContractsEngineBase`, and pure domain helpers for the MemberJunction BizApps Contracts application (`__mj_BizAppsContracts`).

## What Lives Here

- **`src/generated/`** — CodeGen entity subclasses (`mjBizAppsContractsContractEntity`, `mjBizAppsContractsContractTemplateEntity`, `mjBizAppsContractsContractTemplateProvisionEntity`, `mjBizAppsContractsContractTemplateModificationEntity`, `mjBizAppsContractsContractTypeEntity`, `mjBizAppsContractsContractTemplateTypeEntity`, `mjBizAppsContractsContractOrderEntity`). Do not hand-edit generated files.
- **Shared `BaseEntity` Subclasses** (`ContractEntity`, `ContractTemplateEntity`, `ContractTemplateModificationEntity`, `ContractTemplateProvisionEntity`, `ContractTypeEntity`) — cross-field validation and helpers that run identically in the browser and on the server.
- **`ContractsEngineBase`** (`BaseEngine` / `BaseSingleton` + `@RegisterForStartup()`) — session-scoped caching for bounded taxonomy/registry tables (`Contract Types`, `Contract Template Types`, `Contract Templates`) and bounded per-template provisions cache (`GetTemplateProvisions`), with multi-provider/impersonation safety and `CanRead` permission gating.
- **Pure Domain Helpers** — `contract-state.ts`, `default-template.ts`, `renewal-defaults.ts`, `supersede-candidates.ts`, `source-record-candidates.ts`, `executed-agreement.ts`, `value-list-validation.ts`.

## `Contract.DocumentArtifactID` & MJ Docs Rubric

Per [`docs/architecture/mj-docs-rubric.md`](../../docs/architecture/mj-docs-rubric.md) and [`.mj/specs/mj-docs-contract-draft-integration.md`](../../.mj/specs/mj-docs-contract-draft-integration.md):

- **MJ Docs (`MJ: Artifacts`):** Versioned, rich long-form documents — **Assembled Contract Drafts**, **AI Contract Review Memos**, and **Executive Summaries** — are linked from `Contract` via optional nullable `Contract.DocumentArtifactID` (`UNIQUEIDENTIFIER NULL`, `FK -> [__mj].[Artifact]([ID])`), typed strictly as `string | null` on the generated entity class.
- **Strictly Relational Clauses & Quick Notes:** `ContractTemplateProvision`, `ContractTemplateModification`, and `Contract.Notes` stay strictly relational so clause-assembly rules, obligation reporting, and approval routing remain SQL-queryable.
- **No Global Artifact Caching:** `MJ: Artifacts` and `MJ: Artifact Versions` are unbounded transactional records and are **never** cached inside `ContractsEngineBase`.
- **Additive-Only Policy:** `Contract.DocumentArtifactID` obeys `PUBLISH_NO_BREAK_POLICY.md` (nullable FK, zero breaking drops/renames) and compiles cleanly against published `@memberjunction/*@6.3.0-edge.1` peer dependencies with zero `any`, zero lazy `unknown`, and zero `.Get()`/`.Set()` calls.

## Build & Test

```bash
pnpm --filter @mj-biz-apps/contracts-entities build
pnpm --filter @mj-biz-apps/contracts-entities test
```
