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
 *   node test-harnesses/integration.mjs contracts-composition    # one bundle
 *   node test-harnesses/integration.mjs contracts-composition.CC3  # a single check
 *
 * Exit: 0 pass · 1 check failure · 2 bootstrap failure
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';
import sql from 'mssql';

const here = path.dirname(fileURLToPath(import.meta.url));
// The instance's MJ worktree root — `here` is <mj>/packages/dev-apps/bizapps-contracts/test-harnesses,
// so the root env is four levels up. The app's own .env, if present, wins.
dotenv.config({ path: path.resolve(here, '..', '..', '..', '..', '.env'), quiet: true });
dotenv.config({ path: path.resolve(here, '..', '.env'), quiet: true });

/** Every bundle, in presentational order — each owns its own fixture. */
const ALL_BUNDLES = ['contracts-composition', 'contracts-save-contract'];

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

const { setupSQLServerClient, SQLServerProviderConfigData, UserCache } = await import(
    '@memberjunction/sqlserver-dataprovider'
);
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
await import('@memberjunction/server-bootstrap-lite');
await import('@mj-biz-apps/common-entities');
await import('@mj-biz-apps/orders-entities');
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
