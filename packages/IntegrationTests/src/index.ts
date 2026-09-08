/**
 * @mj-biz-apps/contracts-integration-tests — BizApps Contracts' integration-check content.
 *
 * PRIVATE, never published. Importing this module registers every check bundle on the shared
 * `IntegrationCheckRegistry` (from `@memberjunction/testing-integration`) as an import side effect —
 * that is the package's entire runtime job. The MJ testing CLI loads it via `mj.config.cjs`:
 *
 *     testing: { checkModules: ['@mj-biz-apps/contracts-integration-tests'] }
 *
 * BUNDLES
 *   contracts-world        CW1        commit CTR-WORLD (template, customers, a portfolio of every State)
 *   contracts-graph-save   GS1–GS11   header + modifications atomicity, flag invariant, type rules — D-15
 *   contracts-numbering    N1–N5      ContractNumber CTR sequence, uniqueness, reserved namespace
 *   contracts-provisions   P1–P5      seed completeness incl. text, natural order via ProvisionSortKey
 *   contracts-watchlist    W1–W8      derived column VALUES (awaiting document, days to end, notice, state)
 *
 * WHY BUNDLE IDS ARE PREFIXED `contracts-`. The registry is a `BaseSingleton` keyed on check id and
 * is PROCESS-GLOBAL. An instance with both apps dev-linked loads orders' bundles and ours into the
 * same registry; prefixing keeps every app's namespace its own.
 *
 * `contracts-world` COMMITS. Everything else rolls its transaction back. Run world first when you
 * want Explorer to show rows; the other bundles are safe to re-run.
 *
 * ⚠️ `RUN_MUTATION_TESTS=1` is required under `mj test` (every check is RequiresMutation). The
 * standalone runner (`test-harnesses/integration.mjs`) does not apply that gate.
 *
 * @module @mj-biz-apps/contracts-integration-tests
 */

// `mj test` loads ONLY the modules named in `testing.checkModules`. Without these imports the
// ClassFactory never sees ContractEntityServer: every save would run against the generated
// entity and the suite would silently measure nothing.
import {
    LoadContractEntity,
    LoadContractTemplateEntity,
    LoadContractTemplateModificationEntity,
    LoadContractTemplateProvisionEntity,
    LoadContractTypeEntities,
} from '@mj-biz-apps/contracts-entities';
import { LoadMjBizappsContractsEntitiesServer } from '@mj-biz-apps/contracts-core-entities-server';
import './checks/world.checks.js';
import './checks/graph-save.checks.js';
import './checks/numbering.checks.js';
import './checks/provisions.checks.js';
import './checks/watchlist.checks.js';

LoadContractEntity();
LoadContractTemplateEntity();
LoadContractTemplateModificationEntity();
LoadContractTemplateProvisionEntity();
LoadContractTypeEntities();
LoadMjBizappsContractsEntitiesServer();

export { ContractsWorldChecks } from './checks/world.checks.js';
export { GraphSaveChecks } from './checks/graph-save.checks.js';
export { NumberingChecks } from './checks/numbering.checks.js';
export { ProvisionsChecks } from './checks/provisions.checks.js';
export { WatchlistChecks } from './checks/watchlist.checks.js';
export * from './fixture.js';
export * from './world/world.js';
export * from './world/load-world.js';
