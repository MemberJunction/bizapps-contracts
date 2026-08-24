/**
 * Does the server mint a contract number when none is supplied?
 *
 * ContractNumber is NULLABLE as of V202608211200 — MJ cannot express "NOT NULL, assigned by the server
 * on insert" (MJ#4001) and both workarounds broke creation (MJ#4000; and a read-only field is dropped
 * from the insert payload). So the DATABASE no longer holds "every contract has a number" and
 * ContractEntityServer.Save() does. That makes this test the only thing standing between a blank
 * contract number and production, which is why it exists.
 *
 * UNIQUENESS is still the database's: UQ_Contract_ContractNumber is a PLAIN unique index
 * (V202608211300), so every real number is unique and at most ONE un-numbered row can exist — which
 * only raw SQL bypassing the entity could ever create.
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';
loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD } = process.env;
const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost', port: Number(DB_PORT ?? 1433), database: DB_DATABASE,
    user: DB_USERNAME, password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false }, requestTimeout: 60_000,
}).connect();

const { setupSQLServerClient, SQLServerProviderConfigData } = await import('@memberjunction/sqlserver-dataprovider');
const { UserCache } = await import('@memberjunction/generic-database-provider');
await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
await UserCache.Instance.Refresh(pool);
const user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');
const { Metadata } = await import('@memberjunction/core');

const seed = (await pool.request().query(`
    -- A template is REQUIRED: the seeded Order Form / SOW / Payment Link types all carry
    -- TemplateRequired = 1, and ContractEntityServer refuses a contract of such a type without one.
    -- An earlier version of this harness omitted it and the save was correctly refused - the rule
    -- working, not the mint failing. Take a row that already satisfies its own type's rules.
    SELECT TOP 1 CAST(ContractTypeID AS VARCHAR(50)) t, CAST(CompanyID AS VARCHAR(50)) c,
                 CAST(CustomerOrganizationID AS VARCHAR(50)) o,
                 CAST(ContractTemplateID AS VARCHAR(50)) tmpl
      FROM __mj_BizAppsContracts.Contract
     WHERE ContractTemplateID IS NOT NULL AND ParentContractID IS NULL`)).recordset[0];

let failures = 0;
const cleanup = [];

// Case 1: no number supplied at all. Case 2: an explicit BLANK, which must be treated as absent.
for (const [label, value] of [['null (not set)', undefined], ['blank string', '   ']]) {
    const c = await new Metadata().GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    c.NewRecord();
    c.ContractTypeID = seed.t; c.CompanyID = seed.c; c.CustomerOrganizationID = seed.o;
    c.ContractTemplateID = seed.tmpl;
    c.AutoRenew = false; c.HasModifications = false;
    if (value !== undefined) c.ContractNumber = value;

    const ok = await c.Save();
    const minted = (c.ContractNumber ?? '').trim();
    const good = ok && /^CTR-\d+$/.test(minted);
    if (good) console.log(`  ✔ ${label} -> minted ${minted}`);
    else {
        failures++;
        console.log(`  ✖ ${label} -> Save()=${ok} number=${JSON.stringify(c.ContractNumber)}`);
        console.log(`      ${c.LatestResult?.Message ?? ''} ${(c.LatestResult?.Errors ?? []).map((e) => `${e.Source}: ${e.Message}`).join(' | ')}`);
    }
    if (ok) cleanup.push(c.ID);
}

for (const id of cleanup) await pool.request().query(`DELETE FROM __mj_BizAppsContracts.Contract WHERE ID='${id}'`);
await pool.close();
console.log(failures ? `\n✖ ${failures} failed` : '\n✔ all passed');
process.exit(failures ? 1 : 0);
