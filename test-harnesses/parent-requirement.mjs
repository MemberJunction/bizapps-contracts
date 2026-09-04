/**
 * Do `ContractType.MustBeChild` / `MustBeRoot` actually gate `ParentContractID`?
 *
 * This exercises the REAL path: it boots the MJ provider, imports the server package so
 * `ContractEntityServer` is the registered subclass, and attempts saves through `BaseEntity`. A SQL-level
 * check would prove nothing here — the rule lives in `ValidateAsync`, not in a constraint.
 *
 * WHAT IT REPLACED. The rule used to read the contract type's NAME and compare it to 'Change Order'. That
 * is not a rule, it is a coincidence: rename the lookup row and the check silently never fires again. The
 * columns carry the constraint now, and this file is the proof that reading them works — including the
 * MustBeRoot direction, which would otherwise be decoration.
 *
 * R-4 REPLACED THE THREE-STATE STRING with two booleans (`MustBeRoot` / `MustBeChild`, mutually exclusive
 * via `CK_ContractType_RootOrChild`). This harness was not updated with it and spent that time writing a
 * column that no longer existed, inside a `.catch(() => {})` that hid the error. It now uses the seeded
 * flags as they stand and mutates no vocabulary at all.
 *
 * Fixtures use a per-run token and are removed in a `finally`. Nothing else is altered, so there is
 * nothing to restore.
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
const CHANGE_ORDER = '33333333-0000-4000-8000-000000001004';   // MustBeChild
const PAYMENT_LINK = '33333333-0000-4000-8000-000000001003';   // unrestricted — the parent fixture
const STATEMENT_OF_WORK = '33333333-0000-4000-8000-000000001002'; // MustBeRoot

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
/**
 * Everything a failed save has to say.
 *
 * `LatestResult.Message` ALONE IS NOT IT, and reading only that is what made this harness's own
 * breakage unreadable: a validation refusal leaves `Message` null and puts the reason in `Errors[]`,
 * so the parent fixture failed for months reporting the single word "null". Both, always.
 */
const failureText = (entity) =>
    (String(entity.LatestResult?.Message ?? '') + ' ' +
        (entity.LatestResult?.Errors ?? []).map((e) => `${e.Source}: ${e.Message}`).join(' | ')).trim() ||
    '(no message)';

const refusedBecause = (entity, needle) => {
    const message = failureText(entity);
    return { ok: message.includes(needle), message };
};

/** A saved contract to point ParentContractID at. */
async function makeParent(seed) {
    const c = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    c.NewRecord();
    c.ContractTypeID = PAYMENT_LINK;
    c.CompanyID = seed.CompanyID;
    c.CustomerOrganizationID = seed.OrgID;
    c.ContractTemplateID = seed.TemplateID;
    c.Description = `${token} parent`;
    if (!(await c.Save())) throw new Error(`could not create the parent fixture: ${failureText(c)}`);
    created.push(c.ID);
    return c.ID;
}

try {
    // A template, because three of the four seeded types set `TemplateRequired` and a contract of
    // such a type is refused without one. Looked up rather than hardcoded: the seeded Master
    // Agreement lives in demo-data, not metadata, so a database that never loaded the demo set has
    // none of it — a hardcoded id would fail there with a foreign-key error instead of this message.
    const seed = (await pool.request().query(`
        SELECT TOP 1 CAST(c.CompanyID AS VARCHAR(50)) AS CompanyID,
                     CAST(c.CustomerOrganizationID AS VARCHAR(50)) AS OrgID,
                     CAST(t.ID AS VARCHAR(50)) AS TemplateID
          FROM __mj_BizAppsContracts.Contract c
         CROSS JOIN (SELECT TOP 1 ID FROM __mj_BizAppsContracts.ContractTemplate
                      WHERE Status = 'Published' ORDER BY __mj_CreatedAt) t`)).recordset[0];
    if (!seed) throw new Error('no seed data: need at least one contract and one Published template');
    const parentID = await makeParent(seed);

    // 1. Required + no parent → refused.
    const a = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    a.NewRecord();
    a.ContractTypeID = CHANGE_ORDER;
    a.CompanyID = seed.CompanyID;
    a.CustomerOrganizationID = seed.OrgID;
    // Set even though Change Order does not require one: it keeps this case refused by the PARENT
    // rule alone. Were the seed's TemplateRequired to flip, an unset template would refuse the save
    // for a different reason and the needle below would report the drift rather than hide it.
    a.ContractTemplateID = seed.TemplateID;
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
    b.CompanyID = seed.CompanyID;
    b.CustomerOrganizationID = seed.OrgID;
    b.ContractTemplateID = seed.TemplateID;
    b.ParentContractID = parentID;
    b.Description = `${token} change order, with parent`;
    const savedB = await b.Save();
    if (savedB) created.push(b.ID);
    check("'Required' allows a change order that names its parent", savedB,
        `the save was refused: ${failureText(b)}`);

    // 3. MustBeRoot + parent → refused.
    //
    // NO LONGER FLIPS A LOOKUP ROW. This used to `UPDATE ContractType SET ParentStatusRequirement =
    // 'Prohibited'` and restore it in the `finally` — against a column R-4 deleted, replacing the
    // three-state string with `MustBeRoot`/`MustBeChild`. The UPDATE and its restore both threw
    // `Invalid column name`, both were swallowed by `.catch(() => {})`, and the case silently stopped
    // testing anything while the cleanup line still claimed it had put the row back.
    //
    // Statement of Work is seeded `MustBeRoot = true`, so the case needs no mutation at all. That is
    // the better test as well as the working one: nothing to restore means no path where a mid-run
    // failure leaves the vocabulary altered.
    const c2 = await provider.GetEntityObject('MJ_BizApps_Contracts: Contracts', user);
    c2.NewRecord();
    c2.ContractTypeID = STATEMENT_OF_WORK;
    c2.CompanyID = seed.CompanyID;
    c2.CustomerOrganizationID = seed.OrgID;
    c2.ContractTemplateID = seed.TemplateID;
    c2.ParentContractID = parentID;
    c2.Description = `${token} statement of work under a parent`;
    const savedC = await c2.Save();
    if (savedC) created.push(c2.ID);
    const whyC = refusedBecause(c2, 'stands on its own');
    check("'MustBeRoot' refuses a contract that names a parent, and says why", !savedC && whyC.ok,
        savedC ? 'the save SUCCEEDED, so the MustBeRoot branch is decoration'
               : `refused, but not by this rule — message was: ${whyC.message}`);
} catch (e) {
    failures++;
    console.log(`  ✖ harness error: ${String(e.message ?? e).split('\n')[0]}`);
} finally {
    // No lookup row to restore — see case 3. The fixtures are the only thing this harness creates.
    if (created.length) {
        // Children first: ParentContractID is an FK to the same table.
        const kids = await pool.request().query(
            `DELETE FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${token}%' AND ParentContractID IS NOT NULL`)
            .catch(() => ({ rowsAffected: [0] }));
        const roots = await pool.request().query(
            `DELETE FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${token}%'`)
            .catch(() => ({ rowsAffected: [0] }));
        // BOTH counts. Reporting only the second under-stated every run by the number of children
        // removed, which is the sort of quietly-wrong cleanup line that makes a real leak invisible.
        const removed = (kids.rowsAffected?.[0] ?? 0) + (roots.rowsAffected?.[0] ?? 0);
        console.log(`Cleanup: removed ${removed} fixture contract(s) of ${created.length} created.`);
    }
}

console.log(failures === 0 ? '\nPASS — all three cases behaved.' : `\nFAIL — ${failures} case(s) did not.`);
void pool.close().catch(() => undefined);
process.exit(failures ? 1 : 0);
