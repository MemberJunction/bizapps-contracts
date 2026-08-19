/**
 * Does the VIEW agree with the TYPESCRIPT about contract state?
 *
 * WHY THIS EXISTS. Contract state is derived twice — a T-SQL `CASE` in the layered base view
 * (`V202608182001`) and `DeriveContractState()` in `@mj-biz-apps/contracts-entities`. The unit test
 * guards them with `StateSQL()`, which asserts the migration still CONTAINS the text TypeScript
 * renders. That is a text comparison, and on 2026-08-19 it proved insufficient in the most direct way
 * possible: the TypeScript `Terminated` branch was changed from "any termination date" to
 * "terminated before today", the view was not, and all 77 unit tests stayed green while the two
 * implementations disagreed for every contract terminated today or later.
 *
 * Text cannot catch that. Only running both against the same facts can. MJ has no metadata mechanism
 * for "one rule, two runtimes" (no `EntityField` formula/expression support), so equivalence has to
 * be TESTED rather than declared — this script is that test.
 *
 * WHAT IT DOES. Reads every contract through `vwContracts` (the deployed view, not a copy of its
 * source) and through `DeriveContractState()`, and exits non-zero on any disagreement. It reads only;
 * it writes nothing and creates no fixtures, so it is safe to run against any instance.
 *
 * IT RUNS IN TWO PASSES. First over whatever contracts already exist, which catches regressions on
 * real data. Then over ITS OWN FIXTURES, because live data cannot be relied on to contain the
 * interesting cases — the nine rows in this instance cover Draft / Executed / Active / Expired and
 * NOT Terminated or Superseded, which is precisely the branch that broke. The fixture pass covers
 * every state plus the three-way termination boundary (yesterday / today / tomorrow).
 *
 * FIXTURE DISCIPLINE. It creates its own rows under a per-run token, never touches the shared demo
 * contracts, and deletes them in a `finally` so a failure mid-run still cleans up. Rows are written
 * with raw SQL rather than through BaseEntity ON PURPOSE: this compares a view expression against a
 * TypeScript function for given field values, so going through the save path would add the server
 * subclass's minting and audit rows to something that is purely a data-in / state-out comparison —
 * and audit rows would then block the cleanup DELETE behind an FK.
 *
 * Usage:  node test-harnesses/state-equivalence.mjs
 * Exit:   0 agree · 1 mismatch · 2 bootstrap failure
 */
import sql from 'mssql';
import { loadEnvFrom } from './load-env.mjs';

loadEnvFrom(import.meta.url);

const { DB_HOST, DB_PORT, DB_DATABASE, DB_USERNAME, DB_PASSWORD, MJ_CONTRACTS_SCHEMA } = process.env;
const schema = MJ_CONTRACTS_SCHEMA || '__mj_BizAppsContracts';

let DeriveContractState;
try {
    ({ DeriveContractState } = await import('@mj-biz-apps/contracts-entities'));
} catch (e) {
    console.error(`BOOTSTRAP: cannot import @mj-biz-apps/contracts-entities — build it first (${e.message})`);
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

// Dates come back as `varchar` on purpose: the column type is `date`, and letting the driver hand
// back a Date object would render midnight UTC — which is exactly the ambiguity `asDate()` exists to
// remove. Passing the calendar date as text means both sides compare the same calendar day.
const { recordset } = await pool.request().query(`
    SELECT c.ContractNumber,
           CONVERT(varchar(10), c.TerminatedDate, 23)   AS TerminatedDate,
           CONVERT(varchar(10), c.EffectiveDate, 23)    AS EffectiveDate,
           CONVERT(varchar(10), c.ExecutedDate, 23)     AS ExecutedDate,
           CONVERT(varchar(10), c.EndDate, 23)          AS EndDate,
           CAST(c.SupersededByContractID AS varchar(50)) AS SupersededByContractID,
           v.[State]                                     AS SqlState
      FROM [${schema}].[Contract] c
      JOIN [${schema}].[vwContracts] v ON v.ID = c.ID
     ORDER BY c.ContractNumber`);

const mismatches = [];
const seen = new Set();
for (const row of recordset) {
    const ts = DeriveContractState({
        TerminatedDate: row.TerminatedDate,
        EffectiveDate: row.EffectiveDate,
        ExecutedDate: row.ExecutedDate,
        EndDate: row.EndDate,
        SupersededByContractID: row.SupersededByContractID,
    });
    seen.add(row.SqlState);
    if (ts !== row.SqlState) mismatches.push({ Contract: row.ContractNumber, SQL: row.SqlState, TS: ts });
}

console.log(`Pass 1 — existing data: compared ${recordset.length} contract(s). ` +
    `States present: ${[...seen].sort().join(', ') || 'none'}`);

// ── Pass 2: our own fixtures, so the branches live data misses are still covered ────────────────
// `date` arithmetic is done in SQL against GETUTCDATE() so "today" means the same thing to the view
// and to the fixtures. The token makes every row of this run identifiable for cleanup even if the
// process is killed between insert and delete.
const token = `ZZTEST-${process.pid}-${Date.now().toString(36).toUpperCase()}`;
const FIXTURES = [
    { label: 'terminated yesterday',            terminated: -1,   effective: -200, end: 200, superseded: false, expect: 'Terminated' },
    { label: 'terminated today',                terminated: 0,    effective: -200, end: 200, superseded: false, expect: 'Active' },
    { label: 'terminated tomorrow',             terminated: 1,    effective: -200, end: 200, superseded: false, expect: 'Active' },
    { label: 'superseded',                      terminated: null, effective: -200, end: 200, superseded: true,  expect: 'Superseded' },
    { label: 'expired — term ended yesterday',  terminated: null, effective: -200, end: -1,  superseded: false, expect: 'Expired' },
    { label: 'term ends today — still Active',  terminated: null, effective: -200, end: 0,   superseded: false, expect: 'Active' },
    { label: 'effective today — Active',        terminated: null, effective: 0,    end: 200, superseded: false, expect: 'Active' },
    { label: 'executed, not yet effective',     terminated: null, effective: 5,    end: 200, superseded: false, expect: 'Executed' },
];

let fixtureFailures = 0;
try {
    const ids = await pool.request().query(`
        SELECT TOP 1
            (SELECT TOP 1 ID FROM [${schema}].[ContractType])              AS TypeID,
            (SELECT TOP 1 CompanyID FROM [${schema}].[Contract])           AS CompanyID,
            (SELECT TOP 1 CustomerOrganizationID FROM [${schema}].[Contract]) AS OrgID`);
    const { TypeID, CompanyID, OrgID } = ids.recordset[0] ?? {};
    if (!TypeID || !CompanyID || !OrgID) {
        console.log('SKIP pass 2 — no existing type/company/organisation to borrow FK values from.');
    } else {
        for (const [i, f] of FIXTURES.entries()) {
            // ExecutedDate is always set and always in the past so 'Executed' is reachable; the
            // CK_Contract_Dates constraint only requires EndDate >= EffectiveDate.
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
                SELECT CONVERT(varchar(10), c.TerminatedDate, 23) AS TerminatedDate,
                       CONVERT(varchar(10), c.EffectiveDate, 23)  AS EffectiveDate,
                       CONVERT(varchar(10), c.ExecutedDate, 23)   AS ExecutedDate,
                       CONVERT(varchar(10), c.EndDate, 23)        AS EndDate,
                       CAST(c.SupersededByContractID AS varchar(50)) AS SupersededByContractID,
                       v.[State] AS SqlState
                  FROM [${schema}].[Contract] c
                  JOIN [${schema}].[vwContracts] v ON v.ID = c.ID
                 WHERE c.ID = @id;`);
            const row = r.recordset[0];
            const ts = DeriveContractState({
                TerminatedDate: row.TerminatedDate, EffectiveDate: row.EffectiveDate,
                ExecutedDate: row.ExecutedDate, EndDate: row.EndDate,
                SupersededByContractID: row.SupersededByContractID,
            });
            // Three-way check: the view, the function, AND what a person says the answer is. Two
            // implementations agreeing on the WRONG answer is the failure this catches — text
            // comparison of the two never could.
            const agree = ts === row.SqlState;
            const correct = row.SqlState === f.expect;
            if (!agree || !correct) {
                fixtureFailures++;
                console.log(`  ✖ ${f.label}: expected ${f.expect}, view says ${row.SqlState}, TypeScript says ${ts}`);
            } else {
                console.log(`  ✔ ${f.label} → ${row.SqlState}`);
            }
        }
    }
} finally {
    const cleanup = await pool.request()
        .query(`DELETE FROM [${schema}].[Contract] WHERE ContractNumber LIKE '${token}-%'`);
    console.log(`Fixture cleanup: removed ${cleanup.rowsAffected[0]} row(s).`);
}

const failed = mismatches.length + fixtureFailures;
if (mismatches.length) {
    console.log(`\nPass 1 FAILED — the view and DeriveContractState() disagree on ${mismatches.length} row(s):`);
    for (const m of mismatches) console.log(`  · ${m.Contract}: view says ${m.SQL}, TypeScript says ${m.TS}`);
}
console.log(failed === 0
    ? `\nPASS — view and TypeScript agree, and both match the expected state on all ${FIXTURES.length} boundary fixtures.`
    : `\nFAIL — ${failed} problem(s) above.`);

void pool.close().catch(() => undefined);
process.exit(failed ? 1 : 0);
