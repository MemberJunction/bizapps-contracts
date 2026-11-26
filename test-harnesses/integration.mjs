/**
 * Standalone dispatcher for the contracts integration suite.
 *
 * Resolves bundles from the SAME `IntegrationCheckRegistry` that `mj test` uses, so there is no
 * drift between the two execution paths — this script is the fast inner loop (no metadata push, no
 * driver, a stack trace on failure), and `mj test suite --name "BizApps Contracts Integration"` is
 * the one that records results as `MJ: Test Runs`.
 *
 * Dual-DBMS: supports both SQL Server (`DB_PLATFORM=sqlserver`, default) and PostgreSQL
 * (`DB_PLATFORM=postgresql`).
 *
 * Usage:
 *   node test-harnesses/integration.mjs                          # every bundle
 *   node test-harnesses/integration.mjs contracts-graph-save     # one bundle
 *   node test-harnesses/integration.mjs contracts-mj-docs        # MJ Docs integration bundle
 *   node test-harnesses/integration.mjs contracts-graph-save.GS3 # a single check
 *
 * Exit: 0 pass · 1 check failure · 2 bootstrap failure
 */
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

loadEnvFrom(import.meta.url);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const REPO_ROOT = path.resolve(__dirname, '..');

/** Every bundle, in presentational order — each owns its own fixture. */
const ALL_BUNDLES = [
    'contracts-world',
    'contracts-mj-docs',
    'contracts-graph-save',
    'contracts-numbering',
    'contracts-provisions',
    'contracts-watchlist',
    'contracts-renewal-terms',
];

const args = process.argv.slice(2);
const only = args.filter((a) => !a.startsWith('-'));

const platform = (process.env.DB_PLATFORM ?? 'sqlserver').trim().toLowerCase();
const coreSchema = process.env.MJ_CORE_SCHEMA || '__mj';

let provider;
let pool;
let user;
let closeConnection;

if (platform === 'postgresql') {
    const pgProviderUrl = pathToFileURL(
        path.resolve(REPO_ROOT, '..', 'MJ', 'packages', 'PostgreSQLDataProvider', 'dist', 'index.js'),
    ).href;
    const mjCoreUrl = pathToFileURL(
        path.resolve(REPO_ROOT, '..', 'MJ', 'packages', 'MJCore', 'dist', 'index.js'),
    ).href;
    const { PostgreSQLDataProvider, PostgreSQLProviderConfigData } = await import(pgProviderUrl);
    const mjCoreFromWorkspace = await import(mjCoreUrl);
    const { Metadata, RunView } = await import('@memberjunction/core');
    const { UserCache } = await import('@memberjunction/generic-database-provider');

    const pgConfig = {
        Host: process.env.PG_HOST ?? process.env.DB_HOST ?? 'localhost',
        Port: Number(process.env.PG_PORT ?? process.env.DB_PORT ?? 5432),
        Database: process.env.PG_DATABASE ?? process.env.DB_DATABASE,
        User: process.env.PG_USERNAME ?? process.env.DB_USERNAME ?? 'mj_admin',
        Password: process.env.PG_PASSWORD ?? process.env.DB_PASSWORD ?? '',
        SSL: false,
        MJCoreSchemaName: coreSchema,
    };

    const pgProvider = new PostgreSQLDataProvider();
    const ok = await pgProvider.Config(new PostgreSQLProviderConfigData(pgConfig, coreSchema, 0, undefined, undefined, true));
    if (!ok) {
        console.error('BOOTSTRAP: PostgreSQLDataProvider.Config returned false');
        process.exit(2);
    }
    if (!pgProvider.Entities || pgProvider.Entities.length === 0) {
        await pgProvider.ReloadMetadata(true);
    }
    pool = pgProvider.DatabaseConnection;
    mjCoreFromWorkspace.SetProvider(pgProvider);
    Metadata.Provider = pgProvider;
    RunView.Provider = pgProvider;
    await UserCache.Instance.Refresh(pgProvider);
    provider = pgProvider;
    user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    closeConnection = async () => {
        await pgProvider.Dispose?.().catch(() => undefined);
    };
} else {
    const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD } = process.env;
    pool = await new sql.ConnectionPool({
        server: DB_HOST ?? 'localhost',
        port: Number(DB_PORT ?? 1433),
        database: DB_DATABASE,
        user: DB_USERNAME,
        password: DB_PASSWORD,
        options: { trustServerCertificate: true, encrypt: false },
        pool: { max: 10, min: 1 },
        requestTimeout: 60_000,
    }).connect();

    const { setupSQLServerClient, SQLServerProviderConfigData } = await import('@memberjunction/sqlserver-dataprovider');
    const { UserCache } = await import('@memberjunction/generic-database-provider');
    provider = await setupSQLServerClient(new SQLServerProviderConfigData(pool, coreSchema));
    await UserCache.Instance.Refresh(pool);
    user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    closeConnection = async () => {
        // NEVER await pool.close() — the MJ provider's pool can hang forever and the process never exits.
        void pool.close().catch(() => undefined);
    };
}

if (!user) {
    console.error('BOOTSTRAP: no context user in UserCache');
    process.exit(2);
}

// The entity subclasses under test register as a side effect of importing the server package.
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');

const { IntegrationCheckRegistry, IsCheckSkip } = await import('@memberjunction/testing-integration');
await import('@mj-biz-apps/contracts-integration-tests'); // side effect: registers the bundles

const registry = IntegrationCheckRegistry.Instance;

const baseContext = {
    User: user,
    Provider: provider,
    Pool: pool,
    Schema: coreSchema,
    Storage: undefined,
};

const requested = only.length ? only : ALL_BUNDLES;
let pass = 0;
let fail = 0;
let skipped = 0;
const failures = [];

console.log(`Running BizApps Contracts integration suite on platform=${platform}`);

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
                if (IsCheckSkip(e)) {
                    skipped++;
                    console.log(`  ○ ${check.Name}  SKIPPED: ${e.message}`);
                    continue;
                }
                fail++;
                const message = String(e?.message ?? e).split('\n')[0];
                failures.push({ Id: check.Id, message });
                console.log(`  ✖ ${check.Name}\n      ${message}`);
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
        if (lifecycle) await lifecycle.Teardown(ctx).catch((e) => console.warn(`  teardown warn: ${e.message}`));
    }
}

console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} (${platform}) — ${pass} passed, ${fail} failed, ${skipped} skipped`);
if (fail) failures.forEach((f) => console.log(`  · ${f.Id}: ${f.message}`));

void closeConnection();
process.exit(fail === 0 ? 0 : 1);
