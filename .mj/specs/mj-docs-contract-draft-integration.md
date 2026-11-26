# Specification: MJ Docs (`MJ: Artifacts`) Assembled Contract Draft Integration & Rubric

| Field | Value |
|---|---|
| **Spec ID** | `mj-docs-contract-draft-integration` |
| **Epic Task ID** | `35A59BC0-F153-43E1-BC27-4973C2F144A5` |
| **Approved FactoryPlan ID** | `FB65D359-1BA9-4F3E-8235-FBAA301C5E0B` (v2) |
| **Target Repository** | `MemberJunction/bizapps-contracts` (default branch: `next`) |
| **MJ Compatibility Target** | Published `@memberjunction/*@6.3.0-edge.1` (`>=6.3.0-edge.1 <7.0.0`) |
| **Architecture Rubric** | [`docs/architecture/mj-docs-rubric.md`](../../docs/architecture/mj-docs-rubric.md) |
| **Status** | Completed — All 3 Incremental Slices Implemented & Verified (Slice 1: Docs & Spec Sync ✓; Slice 2: Schema, PG Parity, CodeGen, Seed & Dual-DBMS Integration ✓; Slice 3: Angular `@memberjunction/ng-artifacts` Preview, `<mj-page-layout>` Drift Resolution, OpenApp v3 Parity & Playwright Verification ✓) |

---

## 1. Problem Statement & Goals

BizApps Contracts provides a clean relational tracking surface for customer agreements (`Contract`), standard agreement versions (`ContractTemplate`), atomic numbered clauses (`ContractTemplateProvision`), negotiated deviations (`ContractTemplateModification`), and executed signed PDFs (`MJ: Files` with category `Executed Agreement`).

As legal operations teams and AI agents assemble draft agreements, generate AI Contract Review Memos, and author Executive Summaries, the repository needs:

1. **An authoritative architecture rubric** separating **MJ Docs (`MJ: Artifacts`)**, **`MJ: Comments`**, **Quick Notes & Relational Clause Tables**, and **Executed Binary Attachments (`MJ: Files`)** so developers and agents never break SQL queryability or duplicate MJ's artifact engine.
2. **A strictly additive, dual-DBMS schema extension** linking `Contract` to an optional versioned MJ Doc via nullable `Contract.DocumentArtifactID` (`FK -> [__mj].[Artifact]([ID])`), obeying `PUBLISH_NO_BREAK_POLICY.md` and deterministic PostgreSQL parity (`split-bake v1`).
3. **An optional Angular MJ Doc preview surface** in `@mj-biz-apps/contracts-ng` powered by `@memberjunction/ng-artifacts` (compatible with published `@memberjunction/*@6.3.0-edge.1`), preserving Dual Form Registration Parity, OpenApp v3 readiness, and zero-regression backward compatibility for contracts where `DocumentArtifactID IS NULL`.

---

## 2. EARS Requirements

### 2.1 Documentation & Architecture Rubric (Slice 1)
- **REQ-DOC-1 (Ubiquitous):** THE SYSTEM SHALL codify the MJ Docs (`MJ: Artifacts`) vs. `MJ: Comments` vs. Quick Notes & Relational Columns rubric consistently across `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/architecture/mj-docs-rubric.md`, `.mj/specs/mj-docs-contract-draft-integration.md`, `packages/Entities/README.md`, and `packages/Angular/README.md`.
- **REQ-DOC-2 (Ubiquitous):** THE SYSTEM SHALL mandate that Assembled Contract Drafts, AI Contract Review Memos, and Executive Summaries reside in `MJ: Artifacts`, threaded review commentary resides in `MJ: Comments`, signed final PDFs reside in `MJ: Files` (`Executed Agreement` category), and `ContractTemplateProvision`, `ContractTemplateModification`, and `Contract.Notes` remain strictly relational.

### 2.2 Additive Schema, PostgreSQL Parity & CodeGen (Slice 2)
- **REQ-SCHEMA-1 (Ubiquitous):** THE SYSTEM SHALL add `[DocumentArtifactID] UNIQUEIDENTIFIER NULL` with foreign key `CONSTRAINT FK_Contract_DocumentArtifact FOREIGN KEY ([DocumentArtifactID]) REFERENCES [${mjSchema}].[Artifact]([ID])` and `sp_addextendedproperty` (`MS_Description`) to `[__mj_BizAppsContracts].[Contract]` via a 4-part additive T-SQL migration in strict compliance with `PUBLISH_NO_BREAK_POLICY.md`.
- **REQ-SCHEMA-2 (Unwanted Behavior):** IF a migration would drop, rename, narrow, or make non-nullable without default any published column, table, constraint, or stored-procedure parameter (including `Contract.Notes`, `ContractTemplateProvision`, or `ContractTemplateModification`), THEN THE SYSTEM SHALL reject that change as a `PUBLISH_NO_BREAK_POLICY.md` violation.
- **REQ-SCHEMA-3 (Ubiquitous):** THE SYSTEM SHALL generate the PostgreSQL counterpart in `migrations-pg/` strictly via workspace MJCLI `mj migrate convert --split --bake-codegen` (with line-1 `-- @mj-pg-provenance: split-bake v1` header; never freehand SQL or legacy regex `mj sql-convert`) and achieve 6-category SQL Server <-> PostgreSQL schema-delta equivalence (tables, columns, constraints, views, routines, indexes).
- **REQ-SCHEMA-4 (Event-Driven):** WHEN Skyway `mj migrate` and `mj sync push --dir metadata --ci` execute against a clean SQL Server or PostgreSQL database, THE SYSTEM SHALL produce a complete, runnable `__mj_BizAppsContracts` schema and entity metadata catalog with zero deploy-time `mj codegen`.
- **REQ-ENT-1 (Ubiquitous):** THE SYSTEM SHALL expose strongly-typed `DocumentArtifactID: string | null` on generated `mjBizAppsContractsContractEntity` / `ContractEntity` in `@mj-biz-apps/contracts-entities`, compiling cleanly against published `@memberjunction/*@6.3.0-edge.1` with zero `any`, zero lazy `unknown` casts, and zero `.Get()`/`.Set()` calls.

### 2.3 Angular Preview & OpenApp v3 Readiness (Slice 3)
- **REQ-UI-1 (Optional):** WHERE `Contract.DocumentArtifactID` is populated on a saved contract, THE SYSTEM SHALL render an embedded MJ Doc preview inside a contributed `@RegisterClassEx(BaseFormPanel, ...)` panel using `@memberjunction/ng-artifacts` without replacing the generated `@RegisterClass(BaseFormComponent, 'MJ_BizApps_Contracts: Contracts')` host form.
- **REQ-UI-2 (State-Driven):** WHILE `Contract.DocumentArtifactID` is `null` (including legacy and newly drafted contracts), THE SYSTEM SHALL render a clean empty/unlinked state in the optional preview panel and keep `Contract.Notes`, `ContractTemplateModification`, and `MJCContractExecutedAgreementPanel` workflows fully usable with zero console or page errors.
- **REQ-UI-3 (Unwanted Behavior):** IF `Contract.DocumentArtifactID` references an `Artifact` with zero accessible `ArtifactVersion` rows or an RLS-restricted record, THEN THE SYSTEM SHALL render a graceful non-fatal empty/restricted fallback state with zero uncaught exceptions.
- **REQ-UI-4 (Event-Driven):** WHEN the user switches rapidly between different `Contract` records, THE SYSTEM SHALL ignore or cancel stale async artifact load completions so previously selected contract drafts never overwrite the active contract preview under `ChangeDetectionStrategy.OnPush`.
- **REQ-UI-5 (Ubiquitous):** THE SYSTEM SHALL enforce OpenApp v3 UI hygiene across `@mj-biz-apps/contracts-ng`: Dual Form Registration Parity (`MJGlobal.Instance.ClassFactory.GetRegistration(BaseFormComponent, ...)`), `BaseResourceComponent` + `<mj-page-layout>` + `NotifyLoadComplete()` + `DefaultNavItems` parity, `ChangeDetectionStrategy.OnPush`, `UserInfoEngine.Instance` (zero `localStorage`), semantic `--mj-*` CSS design tokens (zero raw `#hex`/`rgb()`/`rgba()`/`hsl()` literals), zero `window.print()`, and `RunView` with `ResultType: 'simple'` and narrow `Fields`.

### 2.4 Verification & CI Gates (Slices 2 & 3)
- **REQ-VER-1 (Ubiquitous):** THE SYSTEM SHALL pass deterministic Vitest unit tests (`pnpm test`) with zero `.skip` regressions across `@mj-biz-apps/contracts-entities` and `@mj-biz-apps/contracts-ng`, including static token/registration/hygiene assertions.
- **REQ-VER-2 (Ubiquitous):** THE SYSTEM SHALL pass parallel SQL Server and PostgreSQL cross-stack integration tests (`packages/IntegrationTests` + `test-harnesses/integration.mjs` + `sf-workspace-db-broker.mjs rehearse-dual-db`) seeded with >= 20 realistic multi-entity domain records spanning organizations, people, roles, permissions, contract templates, provisions, modifications, and linked `MJ: Artifacts` drafts/memos.
- **REQ-VER-3 (Ubiquitous):** THE SYSTEM SHALL pass multi-view headless Chromium Playwright smoke verification asserting `pageErrors === 0`, `consoleErrors === 0`, loaded icon fonts, semantic `--mj-*` tokens, and zero raw Markdown leaks.

---

## 3. Critical User Journeys (CUJs)

> **Mapping Note:** `CUJ-1`..`CUJ-4` map 1:1 to `FactoryPlan.Contract.criticalUserJourneys[0..3]` (linking `productBrief.opportunityTree[0].linkedCujIds = ["CUJ-1"]` to `CUJ-1` below) and incorporate `DefaultNavItems` entry and RLS/zero-version fallback coverage per the architecture review.

### `CUJ-1` — Legal Operations Manager: Linked Assembled Contract Draft Preview
- **Persona:** Legal Operations Manager
- **Steps:**
  1. Navigate via Explorer `DefaultNavItems` into the Contracts section and open an existing `Contract` record with an assembled contract draft linked via `DocumentArtifactID`.
  2. Inspect relational `ContractTemplateProvision` and `ContractTemplateModification` rows alongside `Contract.Notes`.
  3. Preview the linked Assembled Contract Draft via the embedded `@memberjunction/ng-artifacts` MJ Doc preview panel without leaving the Contract workspace.
  4. Verify graceful empty/permission-restricted rendering if a linked `DocumentArtifactID` has zero accessible `ArtifactVersion` rows under RLS.
- **Expected Outcome:** Both queryable relational clause/approval metadata and the rich versioned MJ Doc draft render seamlessly with zero console or page errors.

### `CUJ-2` — Contract Administrator: Backward-Compatible Unlinked / Legacy Contract
- **Persona:** Contract Administrator
- **Steps:**
  1. Navigate via Explorer `DefaultNavItems` into the Contracts section and open a newly drafted or legacy `Contract` record where `DocumentArtifactID` is `null`.
  2. Verify `Contract.Notes`, clause modification controls, and Executed Agreement file attachment controls remain fully usable.
  3. Verify the optional MJ Doc preview panel displays a clean empty/unlinked state.
- **Expected Outcome:** Backward-compatible experience for legacy and in-progress contracts with zero runtime errors or broken form registrations.

### `CUJ-3` — Platform DevOps Engineer: Dual-DBMS Additive Migration & CI Verification
- **Persona:** Platform DevOps Engineer
- **Steps:**
  1. Execute `sf-workspace-db-broker.mjs rehearse-dual-db` against both SQL Server and PostgreSQL using Skyway `mj migrate` and `mj sync push --dir metadata --ci` (zero deploy-time `mj codegen`).
  2. Run `pnpm build`, `pnpm test`, and `test-harnesses/integration.mjs`.
- **Expected Outcome:** 6-category SQL Server <-> PostgreSQL schema-delta equivalence passes with zero deploy-time codegen and 100% green unit and dual-DBMS integration suites.

### `CUJ-4` — Business Stakeholder & Platform Operator: End-to-End Governed Workflow
- **Persona:** Business Stakeholder & Platform Operator
- **Steps:**
  1. Navigate via `DefaultNavItems` into the Contracts workspace and execute the end-to-end Assembled Contract Draft workflow (relational clause authoring + optional `DocumentArtifactID` linking + preview inspection).
  2. Provide domain inputs and observe structured, validated feedback from shared/server entity validation and UI panels.
  3. Verify persisted state, `TrackRecordChanges` audit trail, and clear error/empty handling across both database engines.
- **Expected Outcome:** End-to-end journey for MJ Docs Assembled Contract Draft Integration succeeds with passing unit, dual-DBMS integration, and Playwright verification.

---

## 4. Non-Goals & Out of Scope

- Migrating relational `ContractTemplateProvision`, `ContractTemplateModification`, or `Contract.Notes` data into `MJ: Artifacts` blobs.
- Modifying upstream `@memberjunction/*@6.3.0-edge.1` packages (`packages/MJCore/**`, `packages/MJServer/**`, `packages/MJCLI/**`) or adding bespoke TypeGraphQL resolvers to `@memberjunction/server`.
- Any breaking schema changes, column drops/renames, type narrowings, or required non-defaulted columns violating `PUBLISH_NO_BREAK_POLICY.md`.
- Touching `**/auth/**` or `**/security/**` paths.
- Implementing client-side `window.print()` PDF export mechanisms (or introducing out-of-scope server-side PDF actions not required by the MVP preview cutline).
- Bypassing strict TypeScript safety (`any`, lazy `unknown`, `.Get()`/`.Set()`) or shipping undocumented behavior.

---

## 5. Alternatives Considered

| Alternative | Why Rejected |
|---|---|
| Store entire contracts (including clause provisions and modifications) inside `MJ: Artifacts` JSON/Markdown payloads and deprecate relational clause tables. | Breaks SQL queryability for clause-assembly rules, obligation reporting, renewal-risk derived views, and approval routing workflows, and violates `PUBLISH_NO_BREAK_POLICY.md`. |
| Store assembled contract drafts in a new `NVARCHAR(MAX)` column on `[__mj_BizAppsContracts].[Contract]` instead of referencing `[__mj].[Artifact]`. | Duplicates `MJ: Artifacts` versioning, preview, sharing, and AI artifact lifecycle capabilities already provided by `@memberjunction/ng-artifacts`. |
| Hand-write PostgreSQL migration SQL directly or use legacy regex `mj sql-convert`. | Violates the deterministic PG parity mandate (`mj migrate convert --split --bake-codegen` + `-- @mj-pg-provenance: split-bake v1`) and risks schema drift across SQL Server and PostgreSQL. |

---

## 6. Acceptance Criteria, Slices & Required Artifacts

| AC ID | Slice | Statement | Verified By |
|---|---|---|---|
| **AC-1** | Slice 1 | `CLAUDE.md`, `AGENTS.md`, `README.md`, `docs/architecture/mj-docs-rubric.md`, and `.mj/specs/**` clearly codify the MJ Docs (`MJ: Artifacts`) vs. `MJ: Comments` vs. Quick Notes architecture rubric (Assembled Contract Drafts, AI Contract Review Memos, and Executive Summaries in `MJ: Artifacts`; atomic `ContractTemplateProvision`, `ContractTemplateModification`, and `Contract.Notes` strictly relational) alongside package README updates. | `ART-6` (`DocUpdate`) |
| **AC-2** | Slice 2 | Additive 4-part T-SQL migration adds nullable `[DocumentArtifactID] UNIQUEIDENTIFIER NULL FK -> [__mj].[Artifact]([ID])` on `[__mj_BizAppsContracts].[Contract]` in strict compliance with `PUBLISH_NO_BREAK_POLICY.md`, accompanied by a deterministic PostgreSQL `.pg.sql` counterpart generated via `mj migrate convert --split --bake-codegen` (with line-1 `-- @mj-pg-provenance: split-bake v1` header), passing 6-category SQL Server <-> PostgreSQL schema-delta equivalence and clean Skyway `mj migrate` + `mj sync push --dir metadata --ci` with zero deploy-time `mj codegen`. | `ART-4` (`MigrationDryRun`) |
| **AC-3** | Slices 2–3 | All packages build cleanly via `pnpm build` against published `@memberjunction/*@6.3.0-edge.1` with zero TypeScript `any`/`unknown` occurrences and zero legacy `.Get()`/`.Set()` calls, and `.github/workflows/` enforces build, unit tests, static gates, and PG parity checks on PRs targeting `next`. | `ART-1` (`BuildLog`) |
| **AC-4** | Slices 2–3 | Deterministic unit tests across `packages/Entities` and `packages/Angular` pass 100% via `pnpm test` with zero `.skip` regressions, verifying `Contract.DocumentArtifactID` typing, optional `@memberjunction/ng-artifacts` preview rendering and null/RLS/stale-load handling, Dual Form Registration Parity via `MJGlobal.Instance.ClassFactory.GetRegistration(BaseFormComponent, ...)`, zero raw `#hex`/`rgb()`/`rgba()`/`hsl()` literals, zero `window.print()`, and `OnPush`/`UserInfoEngine` hygiene. | `ART-2` (`TestRun`) |
| **AC-5** | Slice 2 | Real-world multi-entity domain seed fixtures (>= 20 realistic domain records across organizations, people, roles, permissions, contract templates, provisions, modifications, and linked `MJ: Artifacts` drafts/memos) pass parallel SQL Server and PostgreSQL cross-stack integration tests in `packages/IntegrationTests` via `test-harnesses/integration.mjs` and `sf-workspace-db-broker.mjs rehearse-dual-db`. | `ART-3` (`IntegrationSuiteRun`), `ART-8` (`SeedDensityReport`) |
| **AC-6** | Slice 3 | OpenApp v3 readiness checks pass with active Dual Form Registration Parity, `BaseResourceComponent` + `<mj-page-layout>` + `NotifyLoadComplete()` + `DefaultNavItems` parity, and multi-view headless Chromium `PlaywrightScreenshot` verification (`pageErrors === 0`, `consoleErrors === 0`, loaded icon fonts, semantic `--mj-*` tokens, zero raw Markdown leaks). | `ART-5` (`PlaywrightScreenshot`), `ART-7` (`OpenAppReadinessReport`) |

---

## 7. Adoption Metrics

| Metric ID | Name | Baseline | Target Threshold | Telemetry Signal |
|---|---|---|---|---|
| **MET-1** | Primary CUJ Completion Rate | Unverified / manual process before feature delivery | >= 95% automated CUJ verification pass & user task completion | Integration & Playwright CUJ check results + application activity records |
| **MET-2** | Post-Ship Regression Defect Rate | 0 governed unit/world tests for MJ Docs integration prior to change | 0 P0/P1 regressions within 14 days post-merge | Continuous monitor heartbeat + production incident triage count |
