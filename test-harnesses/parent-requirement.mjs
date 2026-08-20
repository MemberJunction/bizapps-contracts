/**
 * Does `ContractType.ParentStatusRequirement` actually gate `ParentContractID`?
 *
 * This exercises the REAL path: it boots the MJ provider, imports the server package so
 * `ContractEntityServer` is the registered subclass, and attempts saves through `BaseEntity`. A SQL-level
 * check would prove nothing here — the rule lives in `ValidateAsync`, not in a constraint.
 *
 * WHAT IT REPLACED. The rule used to read the contract type's NAME and compare it to 'Change Order'. That
 * is not a rule, it is a coincidence: rename the lookup row and the check silently never fires again. The
 * column carries the constraint now, and this file is the proof that reading it works — including the
 * 'Prohibited' direction, which is new and would otherwise be decoration.
 *
 * Fixtures use a per-run token and are removed in a `finally`; the temporary flip of a type's requirement
 * is restored in the same block, so a mid-run failure cannot leave a lookup row altered.
 *
 * ⚠ OBSERVED, NOT SUPPRESSED: bootstrap prints `TypeError: provider.QuoteSchemaAndView is not a
 * function` before the first case. It comes from inside MJ during provider/UserCache setup, is caught
 * and logged by MJ rather than thrown, and demonstrably does not affect this test — a context user is
 * found, saves succeed, and each refusal is matched against the rule's own message text rather than
 * merely "did the save fail". It is recorded here instead of ignored because a stray provider error
 * is exactly the kind of thing that later turns out to explain a real failure.
 *
 * Usage:  npm run test:parent-rule
 * Exit:   0 all cases behaved · 1 a case did not · 2 bootstrap failure
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD } = process.env;
const CHANGE_ORDER = '33333333-0000-4000-8000-000000001004';
const PAYMENT_LINK = '33333333-0000-4000-8000-000000001003';

const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost', port: Number(DB_PORT ?? 1433), database: DB_DATABASE,
    user: DB_USERNAME, password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false }, requestTimeout: 60_000,
}).connect().catch((e) => { console.error(`BOOTSTRAP: ${e.message}`); process.exit(2); });

// UserCache moved to @memberjunction/generic-database-provider. It used to be re-exported from
// @memberjunction/sqlserver-dataprovider, and importing it from there now yields `undefined` — so
// `UserCache.Instance` throws "Cannot read properties of undefined (reading 'Instance')", which names
// no package and reads like a broken provider. This is the same failure signature `mjdev app migrate`
// and `mjdev app capture` produce on this instance (plans/WORKAROUNDS.md W-2), so it is very likely
// the same moved export inside the mjdev-bundled engine.
const { setupSQLServerClient, SQLServerProviderConfigData } = await import('@memberjunction/sqlserver-dataprovider');
const { UserCache } = await import('@memberjunction/generic-database-provider');
const provider = await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
await UserCache.Instance.Refresh(pool);
const user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
if (!user) { console.error('BOOTSTRAP: no context user'); process.exit(2); }

// NOT importing @memberjunction/server-bootstrap-lite: it preloads MJ CORE class registrations, and
// nothing here touches a core entity subclass. The two imports below are what matter — they are what
// registers ContractEntity and ContractEntityServer, and without them the save would exercise the
// plain generated class and pass while proving nothing.
await import('@mj-biz-apps/contracts-entities');
await import('@mj-biz-apps/contracts-core-entities-server');

const token = `ZZPARENT-${process.pid}`;
const created = [];
let failures = 0;

const check = (label, ok, detail) => {
    if (ok) console.log(`  ✔ ${label}`);
    else { failures++; console.log(`  ✖ ${label}\n      ${detail}`); }
};

/**
 * A refusal only counts if it is OUR refusal.
 *
 * "The save returned false" is not evidence the rule fired — a provider fault, a constraint, or a
 * missing FK would all produce the same false, and the test would go green while proving nothing. So
 * the message has to name the field and say the thing this rule says.
 */
const refusedBecause = (entity, needle) => {
    const message = String(entity.LatestResult?.Message ?? '') +
        ' ' + (entity.LatestResult?.Errors ?? []).map((e) => `${e.Source}: ${e.Message}`).join(' | ');
    return { ok: message.includes(needle), message: message.trim() || '(no message)' };
};

/** A saved contract to point ParentContractID at. */
async function makeParent(seedIds) {
    const c = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    c.NewRecord();
    c.ContractTypeID = PAYMENT_LINK;
    c.CompanyID = seedIds.CompanyID;
    c.CustomerOrganizationID = seedIds.OrgID;
    c.Description = `${token} parent`;
    if (!(await c.Save())) throw new Error(`could not create the parent fixture: ${c.LatestResult?.Message}`);
    created.push(c.ID);
    return c.ID;
}

try {
    const ids = (await pool.request().query(`
        SELECT TOP 1 CompanyID, CustomerOrganizationID AS OrgID FROM __mj_BizAppsContracts.Contract`)).recordset[0];
    const parentID = await makeParent(ids);

    // 1. Required + no parent → refused.
    const a = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    a.NewRecord();
    a.ContractTypeID = CHANGE_ORDER;
    a.CompanyID = ids.CompanyID;
    a.CustomerOrganizationID = ids.OrgID;
    a.Description = `${token} change order, no parent`;
    const savedA = await a.Save();
    if (savedA) created.push(a.ID);
    const whyA = refusedBecause(a, 'must name the');
    check("'Required' refuses a change order with no parent, and says why", !savedA && whyA.ok,
        savedA ? 'the save SUCCEEDED, so the rule did not fire'
               : `refused, but not by this rule — message was: ${whyA.message}`);

    // 2. Required + parent → allowed.
    const b = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    b.NewRecord();
    b.ContractTypeID = CHANGE_ORDER;
    b.CompanyID = ids.CompanyID;
    b.CustomerOrganizationID = ids.OrgID;
    b.ParentContractID = parentID;
    b.Description = `${token} change order, with parent`;
    const savedB = await b.Save();
    if (savedB) created.push(b.ID);
    check("'Required' allows a change order that names its parent", savedB,
        `the save was refused: ${b.LatestResult?.Message}`);

    // 3. Prohibited + parent → refused. Flip a type, then restore it in the finally.
    await pool.request().query(
        `UPDATE __mj_BizAppsContracts.ContractType SET ParentStatusRequirement = 'Prohibited' WHERE ID = '${PAYMENT_LINK}'`);
    const c2 = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    c2.NewRecord();
    c2.ContractTypeID = PAYMENT_LINK;
    c2.CompanyID = ids.CompanyID;
    c2.CustomerOrganizationID = ids.OrgID;
    c2.ParentContractID = parentID;
    c2.Description = `${token} payment link under a parent`;
    const savedC = await c2.Save();
    if (savedC) created.push(c2.ID);
    const whyC = refusedBecause(c2, 'stands on its own');
    check("'Prohibited' refuses a contract that names a parent, and says why", !savedC && whyC.ok,
        savedC ? 'the save SUCCEEDED, so the Prohibited branch is decoration'
               : `refused, but not by this rule — message was: ${whyC.message}`);
} catch (e) {
    failures++;
    console.log(`  ✖ harness error: ${String(e.message ?? e).split('\n')[0]}`);
} finally {
    await pool.request().query(
        `UPDATE __mj_BizAppsContracts.ContractType SET ParentStatusRequirement = NULL WHERE ID = '${PAYMENT_LINK}'`).catch(() => {});
    if (created.length) {
        // Children first: ParentContractID is an FK to the same table.
        await pool.request().query(
            `DELETE FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${token}%' AND ParentContractID IS NOT NULL`).catch(() => {});
        const r = await pool.request().query(
            `DELETE FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${token}%'`).catch(() => ({ rowsAffected: [0] }));
        console.log(`Cleanup: removed ${r.rowsAffected?.[0] ?? 0} fixture contract(s), restored Payment Link to NULL.`);
    }
}

console.log(failures === 0 ? '\nPASS — all three cases behaved.' : `\nFAIL — ${failures} case(s) did not.`);
void pool.close().catch(() => undefined);
process.exit(failures ? 1 : 0);
