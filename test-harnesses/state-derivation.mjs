/**
 * Does the VIEW derive the contract lifecycle correctly?
 *
 * WHY THIS IS THE ONLY SEMANTIC TEST OF THE RULE. `State` is derived in exactly one place — the `CASE`
 * in `V202608182001` — because the rule is time-dependent (`Expired` and `Active` turn over at
 * midnight with no write to trigger them), so it has to be evaluated at READ time. There is no
 * TypeScript copy to compare against, on purpose: the previous design rendered the rule in both
 * languages from one module, the two drifted anyway on the termination boundary, and the guard missed
 * it because it compared the renderings as TEXT.
 *
 * So the oracle here is not another implementation — it is the `expect` column below, written from what
 * a person says the answer should be. `contract-state.test.ts` covers the same rule DB-free by checking
 * the migration text against a hand-written statement of it; this file is what proves the SQL actually
 * EVALUATES that way, which no amount of text matching can.
 *
 * FIXTURE DISCIPLINE. Rows are created under a per-run token, never touch the shared demo contracts,
 * and are deleted in a `finally` so a failure mid-run still cleans up. They are written with raw SQL
 * rather than through `BaseEntity` on purpose: this asks "given these field values, what does the view
 * say", so the save path would add number minting and audit rows — and audit rows would then block the
 * cleanup DELETE behind a foreign key.
 *
 * Date arithmetic is done in SQL against `GETUTCDATE()` so that "today" means the same thing to the
 * fixture and to the view. Computing it in Node would introduce the machine's timezone into a
 * comparison the view makes in UTC — which is the exact class of bug that made a stored `date` render
 * as the previous day in the UI.
 *
 * Usage:  npm run test:state
 * Exit:   0 all fixtures correct · 1 a fixture disagrees · 2 bootstrap failure
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD, MJ_CONTRACTS_SCHEMA } = process.env;
const schema = MJ_CONTRACTS_SCHEMA || '__mj_BizAppsContracts';

if (!DB_DATABASE) {
    console.error('BOOTSTRAP: no DB_DATABASE — the instance .env was not found (see load-env.mjs)');
    process.exit(2);
}

const pool = await new sql.ConnectionPool({
    server: DB_HOST ?? 'localhost',
    port: Number(DB_PORT ?? 1433),
    database: DB_DATABASE,
    user: DB_USERNAME,
    password: DB_PASSWORD,
    options: { trustServerCertificate: true, encrypt: false },
}).connect().catch((e) => {
    console.error(`BOOTSTRAP: cannot connect (${e.message})`);
    process.exit(2);
});

/**
 * Day offsets from today, and the state the view must return.
 *
 * The three termination rows are the reason this file exists. The rule was wrong in BOTH directions at
 * different times — first `TerminatedDate IS NOT NULL` (so a termination scheduled for next year made a
 * live contract read Terminated), then briefly an unreachable branch asserting the opposite — and
 * nothing caught either, because nothing tested the boundary.
 *
 * MOVED AGAIN 2026-08-30, and this one is a DECISION rather than a third oscillation. `terminated TODAY`
 * expected Active, on the reading that a contract is in force through the end of its last day. Andrew
 * settled it the other way in contracts#28 item 13: terminated means terminated FROM that date, which is
 * also what the Dates tab has always told the user it means. `V202608300100` moves the view from `<` to
 * `<=` to match, and this fixture is what proves the view actually moved.
 *
 * The neighbours did NOT move, and the difference is the point: `term ends TODAY` stays Active, because
 * an END date is the last day the agreement covers, while a TERMINATED date is the day it stops. Two
 * date columns, two meanings, and making them symmetric would expire every contract a day early.
 */
const FIXTURES = [
    { label: 'terminated yesterday — the termination has taken effect', terminated: -1, effective: -200, end: 200, superseded: false, expect: 'Terminated' },
    { label: 'terminated TODAY — Terminated from this date, inclusive',  terminated: 0,  effective: -200, end: 200, superseded: false, expect: 'Terminated' },
    { label: 'terminated TOMORROW — notice served, not yet effective',  terminated: 1,  effective: -200, end: 200, superseded: false, expect: 'Active' },
    { label: 'superseded — the successor FK is the state',              terminated: null, effective: -200, end: 200, superseded: true,  expect: 'Superseded' },
    { label: 'expired — the term ended yesterday',                      terminated: null, effective: -200, end: -1,  superseded: false, expect: 'Expired' },
    { label: 'term ends TODAY — still Active through the day',          terminated: null, effective: -200, end: 0,   superseded: false, expect: 'Active' },
    { label: 'effective TODAY — Active from today',                     terminated: null, effective: 0,    end: 200, superseded: false, expect: 'Active' },
    { label: 'executed, effective later — a WAIT, not a Draft (R-19)',  terminated: null, effective: 5,    end: 200, superseded: false, expect: 'Executed' },
];

const token = `ZZTEST-${process.pid}-${Date.now().toString(36).toUpperCase()}`;
let failures = 0;

try {
    const ids = await pool.request().query(`
        SELECT TOP 1
            (SELECT TOP 1 ID FROM [${schema}].[ContractType])                 AS TypeID,
            (SELECT TOP 1 CompanyID FROM [${schema}].[Contract])              AS CompanyID,
            (SELECT TOP 1 CustomerOrganizationID FROM [${schema}].[Contract]) AS OrgID`);
    const { TypeID, CompanyID, OrgID } = ids.recordset[0] ?? {};
    if (!TypeID || !CompanyID || !OrgID) {
        console.error('BOOTSTRAP: no existing type/company/organisation to borrow FK values from.');
        process.exit(2);
    }

    for (const [i, f] of FIXTURES.entries()) {
        // ExecutedDate is always set and in the past so 'Executed' is reachable; CK_Contract_Dates
        // only requires EndDate >= EffectiveDate.
        const r = await pool.request()
            .input('num', `${token}-${i}`).input('type', TypeID).input('co', CompanyID).input('org', OrgID)
            .query(`
            DECLARE @id uniqueidentifier = NEWID();
            INSERT INTO [${schema}].[Contract]
                (ID, ContractNumber, ContractTypeID, CompanyID, CustomerOrganizationID,
                 AutoRenew, HasModifications, ExecutedDate, EffectiveDate, EndDate, TerminatedDate,
                 SupersededByContractID)
            VALUES
                (@id, @num, @type, @co, @org, 0, 0,
                 DATEADD(day, -300, CAST(GETUTCDATE() AS date)),
                 DATEADD(day, ${f.effective}, CAST(GETUTCDATE() AS date)),
                 DATEADD(day, ${f.end}, CAST(GETUTCDATE() AS date)),
                 ${f.terminated === null ? 'NULL' : `DATEADD(day, ${f.terminated}, CAST(GETUTCDATE() AS date))`},
                 ${f.superseded ? `(SELECT TOP 1 ID FROM [${schema}].[Contract] WHERE ContractNumber <> @num)` : 'NULL'});
            SELECT v.[State] AS SqlState FROM [${schema}].[vwContracts] v WHERE v.ID = @id;`);

        const actual = r.recordset[0]?.SqlState;
        if (actual === f.expect) {
            console.log(`  ✔ ${f.label} → ${actual}`);
        } else {
            failures++;
            console.log(`  ✖ ${f.label}\n      expected ${f.expect}, the view returned ${actual}`);
        }
    }
} finally {
    const cleanup = await pool.request()
        .query(`DELETE FROM [${schema}].[Contract] WHERE ContractNumber LIKE '${token}-%'`);
    console.log(`Fixture cleanup: removed ${cleanup.rowsAffected[0]} row(s).`);
}

console.log(failures === 0
    ? `\nPASS — the view returned the expected state for all ${FIXTURES.length} fixtures.`
    : `\nFAIL — ${failures} of ${FIXTURES.length} fixtures disagreed with the expected state.`);

void pool.close().catch(() => undefined);
process.exit(failures ? 1 : 0);
