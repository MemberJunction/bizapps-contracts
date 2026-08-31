/**
 * Does re-papering actually work on the REAL path?
 *
 * The UI reports that linking a predecessor does nothing. This isolates whether the failure is in the
 * entity/server layer or in the browser: it boots the real provider, registers ContractEntity and
 * ContractEntityServer, and drives exactly what the panel drives — Supersede() on a loaded
 * predecessor, then Save() — reporting the entity's OWN message on failure rather than "it returned
 * false", which would be true of a provider fault and prove nothing.
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';
loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD } = process.env;
const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost', port: Number(DB_PORT ?? 1433), database: DB_DATABASE,
    user: DB_USERNAME, password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false }, requestTimeout: 60_000,
}).connect().catch((e) => { console.error(`BOOTSTRAP: ${e.message}`); process.exit(2); });

const { setupSQLServerClient, SQLServerProviderConfigData } = await import('@memberjunction/sqlserver-dataprovider');
const { UserCache } = await import('@memberjunction/generic-database-provider');
const provider = await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
await UserCache.Instance.Refresh(pool);
const user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');

const E = 'MJ_BizApps_Contracts: Contracts';
const why = (e) => String(e.LatestResult?.Message ?? '') + ' ' +
    (e.LatestResult?.Errors ?? []).map((x) => `${x.Source}: ${x.Message}`).join(' | ');

// Two root contracts, neither already superseded, FOR THE SAME CUSTOMER.
//
// The same-customer clause is not incidental to the fixture — `refuseCrossCustomerSupersession`
// (issue #28 item 4) refuses a re-papering across customers, so a `TOP 2 ... ORDER BY
// ContractNumber` pick reads whichever two contracts sort first and is refused on a rule this
// harness is not testing. The harness exercises `Supersede()` reaching the server subclass and
// persisting; it needs a pair the eligibility rules actually permit.
const rows = (await pool.request().query(`
    SELECT TOP 2 CAST(c.ID AS VARCHAR(50)) AS ID, c.ContractNumber
      FROM __mj_BizAppsContracts.Contract c
      JOIN (
            SELECT TOP 1 CustomerOrganizationID
              FROM __mj_BizAppsContracts.Contract
             WHERE ParentContractID IS NULL AND SupersededByContractID IS NULL
             GROUP BY CustomerOrganizationID
            HAVING COUNT(*) >= 2
             ORDER BY CustomerOrganizationID
           ) pick ON pick.CustomerOrganizationID = c.CustomerOrganizationID
     WHERE c.ParentContractID IS NULL AND c.SupersededByContractID IS NULL
     ORDER BY c.ContractNumber`)).recordset;
if (rows.length < 2) {
    console.error('need two eligible root contracts for the SAME customer');
    process.exit(2);
}
const [predRow, succRow] = rows;
console.log(`predecessor ${predRow.ContractNumber}  ->  successor ${succRow.ContractNumber}\n`);

const md = new (await import('@memberjunction/core')).Metadata();
const successor = await md.GetEntityObject(E, user);
const predecessor = await md.GetEntityObject(E, user);
console.log(`successor class:   ${successor.constructor.name}`);
console.log(`predecessor class: ${predecessor.constructor.name}`);
if (!(await successor.Load(succRow.ID)))  { console.error('could not load successor'); process.exit(2); }
if (!(await predecessor.Load(predRow.ID))) { console.error('could not load predecessor'); process.exit(2); }

console.log(`\nSupersede() present: ${typeof predecessor.Supersede}`);
try { predecessor.Supersede(successor); }
catch (e) { console.log(`✖ Supersede() THREW: ${e.message}`); process.exit(1); }
console.log(`after Supersede(): SupersededByContractID = ${predecessor.SupersededByContractID}`);
console.log(`Dirty = ${predecessor.Dirty}`);

const ok = await predecessor.Save();
console.log(`\nSave() -> ${ok}`);
if (!ok) console.log(`   reason: ${why(predecessor).trim() || '(no message)'}`);

const after = (await pool.request().query(`
    SELECT ISNULL(CAST(SupersededByContractID AS VARCHAR(50)),'(null)') AS S
      FROM __mj_BizAppsContracts.Contract WHERE ID = '${predRow.ID}'`)).recordset[0].S;
console.log(`DB now says SupersededByContractID = ${after}`);
console.log(after.toLowerCase() === succRow.ID.toLowerCase() ? '\n✔ PERSISTED' : '\n✖ NOT PERSISTED');

// leave the data as we found it
await pool.request().query(`UPDATE __mj_BizAppsContracts.Contract SET SupersededByContractID = NULL WHERE ID = '${predRow.ID}'`);
console.log('(cleaned up)');
await pool.close();
