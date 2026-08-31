/**
 * Standalone dispatcher for the contracts integration suite.
 *
 * Resolves bundles from the SAME `IntegrationCheckRegistry` that `mj test` uses, so there is no
 * drift between the two execution paths — this script is the fast inner loop (no metadata push, no
 * driver, a stack trace on failure), and `mj test suite --name "BizApps Contracts Integration"` is
 * the one that records results as `MJ: Test Runs`.
 *
 * Usage:
 *   node test-harnesses/integration.mjs                          # every bundle
 *   node test-harnesses/integration.mjs contracts-graph-save     # one bundle
 *   node test-harnesses/integration.mjs contracts-graph-save.GS3 # a single check
 *
 * Exit: 0 pass · 1 check failure · 2 bootstrap failure
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

// Finds the instance .env by walking UP rather than counting directories. The fixed four-level path
// this used to hard-code was correct only for the pre-6.x nested layout; under the parent-workspace
// topology it resolved to ~/MJDev and silently loaded nothing, so DB_PORT stayed undefined and the
// script died with "Failed to connect to localhost:1433". See load-env.mjs.
loadEnvFrom(import.meta.url);

/** Every bundle, in presentational order — each owns its own fixture. */
// The v2 bundles (plan item 13), plus contracts-world which COMMITS a portfolio so Explorer
// has rows. v1's contracts-composition / -save-contract / -billing / -amendment tested the draft
// payload, the billing engine and term amendment — all deleted by the rebuild.
const ALL_BUNDLES = [
    'contracts-world',
    'contracts-graph-save',
    'contracts-numbering',
    'contracts-provisions',
    'contracts-watchlist',
];

const args = process.argv.slice(2);
const only = args.filter((a) => !a.startsWith('-'));

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD } = process.env;
const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost',
    port: Number(DB_PORT ?? 1433),
    database: DB_DATABASE,
    user: DB_USERNAME,
    password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false },
    pool: { max: 10, min: 1 },
    // `mssql` defaults requestTimeout to 15s. A contract tree save writes the header, its terms and
    // every term's coverage inside one transaction, each with its own async validation reads. On a
    // laptop running SQL Server in Docker that occasionally crosses 15s, and the timeout surfaces
    // as a save failure in a DIFFERENT check on every run — which reads exactly like an intermittent
    // engine defect. 60s reflects what the write actually costs here and still fails loudly on
    // anything genuinely hung.
    requestTimeout: 60_000,
}).connect();

// UserCache moved to @memberjunction/generic-database-provider. It used to be re-exported from
// @memberjunction/sqlserver-dataprovider, and importing it from there now yields `undefined` — so
// `UserCache.Instance` throws "Cannot read properties of undefined (reading 'Instance')", which names
// no package and reads like a broken provider. This is the same failure signature `mjdev app migrate`
// and `mjdev app capture` produce on this instance (plans/WORKAROUNDS.md W-2), so it is very likely
// the same moved export inside the mjdev-bundled engine.
const { setupSQLServerClient, SQLServerProviderConfigData } = await import('@memberjunction/sqlserver-dataprovider');
const { UserCache } = await import('@memberjunction/generic-database-provider');
const provider = await setupSQLServerClient(
    new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'),
);
await UserCache.Instance.Refresh(pool);
const user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
if (!user) {
    console.error('BOOTSTRAP: no context user in UserCache');
    process.exit(2);
}

// The entity subclasses under test register as a side effect of importing the server package.
// Without this the checks would exercise the plain generated entities and pass while proving
// nothing — every invariant in this suite lives in a subclass.
// NOT importing @memberjunction/server-bootstrap-lite, @mj-biz-apps/common-entities or
// @mj-biz-apps/orders-entities: none is a declared dependency of this repo, so under pnpm's strict
// node_modules all three are unresolvable and the FIRST of them killed this script at bootstrap with
// ERR_MODULE_NOT_FOUND — before it ever reached the registry, which is what made the harness look
// unwired. bootstrap-lite only preloads MJ CORE class registrations and nothing here touches a core
// subclass; the other two belong to sibling apps. Same reasoning as parent-requirement.mjs.
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');

const { IntegrationCheckRegistry } = await import('@memberjunction/testing-integration');
await import('@mj-biz-apps/contracts-integration-tests'); // side effect: registers the bundles

const registry = IntegrationCheckRegistry.Instance;

/**
 * `Storage` is only read by MJ's own cache bundles, so leaving it undefined is honest — ours never
 * touch it, and fabricating an instrumented cache would mean claiming to own the process for no
 * benefit.
 */
const baseContext = {
    User: user,
    Provider: provider,
    Pool: pool,
    Schema: process.env.MJ_CORE_SCHEMA || '__mj',
    Storage: undefined,
};

const requested = only.length ? only : ALL_BUNDLES;
let pass = 0;
let fail = 0;
const failures = [];

for (const request of requested) {
    const [bundle, localId] = request.includes('.') ? [request.split('.')[0], request] : [request, null];
    const checks = registry.GetBundle(bundle).filter((c) => !localId || c.Id === localId);
    if (checks.length === 0) {
        console.error(`\n✖ no checks matched '${request}' — known bundles: ${registry.GetBundleNames().join(', ')}`);
        fail++;
        continue;
    }

    console.log(`\n=== ${bundle} (${checks.length} check${checks.length === 1 ? '' : 's'}) ===`);
    const ctx = { ...baseContext };
    const lifecycle = registry.GetLifecycle(bundle);

    try {
        if (lifecycle) await lifecycle.Setup(ctx);

        for (const check of checks) {
            const started = Date.now();
            try {
                await check.Fn(ctx);
                pass++;
                console.log(`  ✔ ${check.Name}  (${Date.now() - started}ms)`);
            } catch (e) {
                fail++;
                const message = String(e?.message ?? e).split('\n')[0];
                failures.push({ Id: check.Id, message });
                console.log(`  ✖ ${check.Name}\n      ${message}`);
                // mssql buries the useful text ('Invalid column name X') in a nested originalError,
                // so surface it rather than making the reader open a debugger for it.
                const nested = e?.originalError?.message ?? e?.precedingErrors?.[0]?.message;
                if (nested && nested !== message) console.log(`      ↳ ${nested}`);
            }
        }
    } catch (e) {
        fail++;
        const message = String(e?.message ?? e).split('\n')[0];
        failures.push({ Id: `${bundle} (setup)`, message });
        console.log(`  ✖ ${bundle} SETUP FAILED\n      ${message}`);
        const nested = e?.originalError?.message;
        if (nested && nested !== message) console.log(`      ↳ ${nested}`);
    } finally {
        // Best-effort — a check failure must still tear down.
        if (lifecycle) await lifecycle.Teardown(ctx).catch((e) => console.warn(`  teardown warn: ${e.message}`));
    }
}

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${pass} passed, ${fail} failed`);
if (fail) failures.forEach((f) => console.log(`  · ${f.Id}: ${f.message}`));

// NEVER await pool.close() — the MJ provider's pool can hang forever and the process never exits.
void pool.close().catch(() => undefined);
process.exit(fail === 0 ? 0 : 1);
