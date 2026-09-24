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
 * WHAT THIS ALSO PROVES, SINCE 2026-09-21. `NonRenewalOutcome` -- the ML training label added by
 * `V202609202354` -- re-states the SAME two date boundaries in a SECOND `CASE` a few lines below
 * `State`, by hand. Nothing held the two copies together: this file asserted `State` only, and
 * `contract-state.test.ts` checks the migration text for the `State` rule alone. So every fixture
 * below now asserts BOTH columns, which is what stops the label drifting away from a rule that has
 * already drifted from itself twice.
 *
 * THE TWO CASES DISAGREE ON PURPOSE, AND THE LAST FIXTURE IS THAT DISAGREEMENT. Their precedence is
 * INVERTED: `State` tests Terminated before Superseded, the label tests Superseded before Terminated.
 * A renewal normally terminates the old paper AND points it at the successor, so such a contract is
 * `Terminated` to a reader and `0` (renewed) to training -- both right, for different questions.
 * Anyone "aligning the two CASEs for consistency" flips every renewed-by-supersession contract from
 * 0 to 1, which teaches the model the OPPOSITE label on precisely the positive examples. That change
 * is invisible in every grid and every form; the last fixture below is the only thing that fails.
 *
 * FIXTURE DISCIPLINE. Rows are created under a per-run token, never touch the shared demo contracts,
 * and are deleted in a `finally` so a failure mid-run still cleans up. They are written with raw SQL
 * rather than through `BaseEntity` on purpose: this asks "given these field values, what does the view
 * say", so the save path would add number minting and audit rows — and audit rows would then block the
 * cleanup DELETE behind a foreign key.
 *
 * Date arithmetic is done IN SQL, against the same `[__mj_BizAppsCommon].[fnBusinessToday]()` the view
 * joins, so that "today" means the same thing to the fixture and to the view. Computing it in Node
 * would introduce the machine's timezone into a comparison the view does not make — which is the
 * exact class of bug that made a stored `date` render as the previous day in the UI.
 *
 * IT USED TO ANCHOR ON `CAST(GETUTCDATE() AS date)`, AND `V202609211200` BROKE THAT (#168). The view
 * now judges every boundary on `bt.Today` — the calendar day in the BUSINESS zone — while
 * `GETUTCDATE()` is the server's UTC day, which is already TOMORROW for the whole American evening.
 * A fixture placed at "UTC today" is therefore at `bt.Today + 1` all evening, so `terminated TODAY`
 * arrived as a future termination and read Active, `term ends TODAY` read Active-but-for-the-wrong-
 * reason, and `effective TODAY` read Executed: three or more fixtures failing every evening on a
 * correct view, which is how a harness stops being believed. Anchoring on the same function the view
 * anchors on makes the fixtures say what they mean at every hour.
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
    { label: 'terminated yesterday — the termination has taken effect', terminated: -1,   effective: -200, end: 200, superseded: false, expect: 'Terminated', outcome: 1 },
    { label: 'terminated TODAY — Terminated from this date, inclusive', terminated: 0,    effective: -200, end: 200, superseded: false, expect: 'Terminated', outcome: 1 },
    { label: 'terminated TOMORROW — notice served, not yet effective',  terminated: 1,    effective: -200, end: 200, superseded: false, expect: 'Active',     outcome: null },
    { label: 'superseded — the successor FK is the state',              terminated: null, effective: -200, end: 200, superseded: true,  expect: 'Superseded', outcome: 0 },
    { label: 'expired — the term ended yesterday',                      terminated: null, effective: -200, end: -1,  superseded: false, expect: 'Expired',    outcome: 1 },
    { label: 'term ends TODAY — still Active through the day',          terminated: null, effective: -200, end: 0,   superseded: false, expect: 'Active',     outcome: null },
    { label: 'effective TODAY — Active from today',                     terminated: null, effective: 0,    end: 200, superseded: false, expect: 'Active',     outcome: null },
    { label: 'executed, effective later — a WAIT, not a Draft (R-19)',  terminated: null, effective: 5,    end: 200, superseded: false, expect: 'Executed',   outcome: null },
    // The row the two CASEs read differently, and the reason the docstring says so out loud.
    // State stops at Terminated; the label stops at Superseded and calls it a renewal.
    { label: 'superseded AND terminated — the CASEs invert, on purpose', terminated: -1,  effective: -200, end: 200, superseded: true,  expect: 'Terminated', outcome: 0 },
];

/** NULL is a real answer here — "not concluded yet" — so it prints as itself rather than as blank. */
const fmt = (v) => (v === null ? 'NULL' : String(v));

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

    // The fixtures and the view must anchor on the SAME day. Without this the INSERT below fails with
    // "invalid object name", which reads as a harness bug rather than as a database missing
    // bizapps-common's business-time-zone migration — the same message V202609211200 guards against.
    const fn = await pool.request()
        .query(`SELECT OBJECT_ID('[__mj_BizAppsCommon].[fnBusinessToday]', 'IF') AS ObjectID`);
    if (!fn.recordset[0]?.ObjectID) {
        console.error(
            'BOOTSTRAP: [__mj_BizAppsCommon].[fnBusinessToday]() is absent. Apply bizapps-common\'s ' +
            'business-time-zone migration to this database first — vwContracts joins it (V202609211200).',
        );
        process.exit(2);
    }

    // Reported once, because a fixture that disagrees is read very differently depending on which day
    // the view thinks it is: a run in the American evening has bt.Today one behind the UTC day.
    const bt = await pool.request().query(`
        SELECT CONVERT(varchar(10), b.[Today], 23) AS BusinessToday, b.SqlZone AS Zone,
               CONVERT(varchar(10), CAST(GETUTCDATE() AS date), 23) AS UtcToday
          FROM [__mj_BizAppsCommon].[fnBusinessToday]() b`);
    const { BusinessToday, Zone, UtcToday } = bt.recordset[0] ?? {};
    console.log(
        `Business day: ${BusinessToday} (${Zone})${BusinessToday === UtcToday ? '' : ` — the UTC day is ${UtcToday}`}`,
    );

    for (const [i, f] of FIXTURES.entries()) {
        // ExecutedDate is always set and in the past so 'Executed' is reachable; CK_Contract_Dates
        // only requires EndDate >= EffectiveDate.
        const r = await pool.request()
            .input('num', `${token}-${i}`).input('type', TypeID).input('co', CompanyID).input('org', OrgID)
            .query(`
            DECLARE @id uniqueidentifier = NEWID();
            -- The BUSINESS day, read from the function the view itself joins (#168). Read ONCE into a
            -- variable so every column of a fixture is placed relative to the same day even if the
            -- run straddles midnight in the business zone.
            DECLARE @today date = (SELECT TOP 1 b.[Today] FROM [__mj_BizAppsCommon].[fnBusinessToday]() b);
            INSERT INTO [${schema}].[Contract]
                (ID, ContractNumber, ContractTypeID, CompanyID, CustomerOrganizationID,
                 AutoRenew, HasModifications, ExecutedDate, EffectiveDate, EndDate, TerminatedDate,
                 SupersededByContractID)
            VALUES
                (@id, @num, @type, @co, @org, 0, 0,
                 DATEADD(day, -300, @today),
                 DATEADD(day, ${f.effective}, @today),
                 DATEADD(day, ${f.end}, @today),
                 ${f.terminated === null ? 'NULL' : `DATEADD(day, ${f.terminated}, @today)`},
                 ${f.superseded ? `(SELECT TOP 1 ID FROM [${schema}].[Contract] WHERE ContractNumber <> @num)` : 'NULL'});
            SELECT v.[State] AS SqlState, v.[NonRenewalOutcome] AS SqlOutcome
              FROM [${schema}].[vwContracts] v WHERE v.ID = @id;`);

        const row = r.recordset[0];
        const actualState = row?.SqlState;
        // `??` and never `||`: the label's 0 means RENEWED, and `||` would read it as absent.
        const actualOutcome = row?.SqlOutcome ?? null;
        const stateOk = actualState === f.expect;
        const outcomeOk = actualOutcome === f.outcome;

        if (stateOk && outcomeOk) {
            console.log(`  ✔ ${f.label} → ${actualState} / ${fmt(actualOutcome)}`);
        } else {
            if (!stateOk) {
                failures++;
                console.log(`  ✖ ${f.label}\n      State: expected ${f.expect}, the view returned ${actualState}`);
            }
            if (!outcomeOk) {
                failures++;
                console.log(`  ✖ ${f.label}\n      NonRenewalOutcome: expected ${fmt(f.outcome)}, the view returned ${fmt(actualOutcome)}`);
            }
        }
    }
} finally {
    const cleanup = await pool.request()
        .query(`DELETE FROM [${schema}].[Contract] WHERE ContractNumber LIKE '${token}-%'`);
    console.log(`Fixture cleanup: removed ${cleanup.rowsAffected[0]} row(s).`);
}

const assertions = FIXTURES.length * 2;
console.log(failures === 0
    ? `\nPASS — State and NonRenewalOutcome both matched on all ${FIXTURES.length} fixtures (${assertions} assertions).`
    : `\nFAIL — ${failures} of ${assertions} assertions disagreed, across ${FIXTURES.length} fixtures.`);

void pool.close().catch(() => undefined);
process.exit(failures ? 1 : 0);
