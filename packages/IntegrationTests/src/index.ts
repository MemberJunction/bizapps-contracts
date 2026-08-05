/**
 * @mj-biz-apps/contracts-integration-tests — BizApps Contracts' integration-check content.
 *
 * PRIVATE, never published. Importing this module registers every check bundle on the shared
 * `IntegrationCheckRegistry` (from `@memberjunction/testing-integration`) as an import side effect —
 * that is the package's entire runtime job. The MJ testing CLI loads it via `mj.config.cjs`:
 *
 *     testing: { checkModules: ['@mj-biz-apps/contracts-integration-tests'] }
 *
 * …and `IntegrationTestDriver` then expands each `MJ: Tests` record's `Configuration.checks[].type`
 * into that bundle's ordered checks. The same registry backs `test-harnesses/integration.mjs`, so
 * there is no drift between "what `mj test` runs" and "what the standalone runner runs".
 *
 * WHY BUNDLE IDS ARE PREFIXED `contracts-`. The registry is a `BaseSingleton` keyed on check id and
 * is PROCESS-GLOBAL. An instance with both apps dev-linked loads orders' bundles and ours into the
 * same registry, and orders already owns a bundle called `composition` — so an unprefixed
 * `composition.CC1` would not collide on id, but `GetBundle('composition')` would return both apps'
 * checks as one bundle. Prefixing keeps every app's namespace its own.
 *
 * BUNDLES
 *   contracts-composition   CC1–CC14   the contract as one entity, one transaction, one tree
 *
 * @module @mj-biz-apps/contracts-integration-tests
 */

import './checks/composition.checks.js';

export { CompositionChecks } from './checks/composition.checks.js';
export * from './fixture.js';
