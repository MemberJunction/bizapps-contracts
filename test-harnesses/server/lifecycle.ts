/**
 * @fileoverview Tier 2 — the contract LIFECYCLE, driven through the real remote operations.
 *
 * The sibling harness (`invariants.ts`) proves the rules a single `Save()` must uphold. This one
 * proves the three multi-write operations that move a contract through its life: activation,
 * renewal, termination. They are where the interesting failures live, because each writes several
 * tables and a partial write leaves a state that looks healthy and bills wrongly.
 *
 * WHAT IT ASSERTS, AND WHY THAT MATTERS. Exact values, always — the count of billing events a
 * quarterly year produces (4, not "some"), the escalated price to the cent (1030.00, not "higher"),
 * the clamped percentage when a renewal exceeds its negotiated ceiling. And after termination it
 * re-reads the billing schedule from the database to confirm the FUTURE events are Cancelled while
 * the ones on or before the effective date still stand — the single most consequential behavior
 * here, and the one no status check would catch.
 *
 * The operations are invoked via `ExecuteServer`, which is the same path MJAPI takes when the UI
 * calls them. No shortcuts around the class factory, no reimplementation of the logic under test.
 *
 * Run:  npx tsx test-harnesses/server/lifecycle.ts
 * Exit: 0 pass · 1 test failure · 2 bootstrap failure
 */

import sql from 'mssql';
import dotenv from 'dotenv';
import path from 'path';
import { Metadata, RunView, type IMetadataProvider, type UserInfo } from '@memberjunction/core';
import { setupSQLServerClient, SQLServerProviderConfigData, UserCache } from '@memberjunction/sqlserver-dataprovider';
import '@memberjunction/server-bootstrap-lite';
import '@mj-biz-apps/common-entities';
import '@mj-biz-apps/orders-entities';
import '@mj-biz-apps/contracts-entities';
import {
    ActivateTermOperation,
    RenewTermOperation,
    TerminateContractOperation,
} from '@mj-biz-apps/contracts-core-entities-server';
import type {
    mjBizAppsContractsContractEntity,
    mjBizAppsContractsContractTermEntity,
    mjBizAppsContractsContractLineEntity,
} from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINE = 'MJ_BizApps_Contracts: Contract Lines';
const E_BILLING_EVENT = 'MJ_BizApps_Contracts: Contract Billing Events';
const E_SCHEDULE = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';

const TAG = 'tier2-lifecycle';

let passed = 0;
let failed = 0;
const failures: string[] = [];

function check(name: string, condition: boolean, detail = ''): void {
    if (condition) {
        passed++;
        console.log(`  ✓ ${name}`);
    } else {
        failed++;
        failures.push(`${name}${detail ? ' — ' + detail : ''}`);
        console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`);
    }
}

async function main(): Promise<void> {
    dotenv.config({ path: path.resolve(process.cwd(), '../../../.env'), quiet: true });
    dotenv.config({ path: path.resolve(process.cwd(), '.env'), quiet: true });

    const pool = await new sql.ConnectionPool({
        server: process.env.DB_HOST ?? 'localhost',
        port: Number(process.env.DB_PORT ?? 1433),
        user: process.env.DB_USERNAME,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_DATABASE,
        // Required for DML against ContractLine, which now carries a filtered unique index.
        options: { encrypt: false, trustServerCertificate: true, enableQuotedIdentifier: true },
        requestTimeout: 60000,
    }).connect();

    const provider = (await setupSQLServerClient(
        new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'),
    )) as unknown as IMetadataProvider;
    await UserCache.Instance.Refresh(pool);
    const user: UserInfo | undefined =
        UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    if (!user) {
        console.error('BOOTSTRAP: no context user');
        process.exit(2);
    }

    const md = new Metadata();
    const rv = new RunView();
    const ctx = { provider, user, emitProgress: () => undefined };

    // Fixtures are READ, never created. A test harness that invents companies or products pollutes
    // the shared demo data every run; the seed owns those (demo/seed-demo-contract.sql).
    const [types, companies, orgs, products] = await rv.RunViews(
        [
            { EntityName: 'MJ_BizApps_Contracts: Contract Types', Fields: ['ID', 'Code'], ResultType: 'simple' },
            { EntityName: 'MJ: Companies', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Common: Organizations', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Products', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
        ],
        user,
    );
    const typeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'Standard')?.ID;
    const companyID = (companies?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const orgID = (orgs?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const productID = (products?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    if (!typeID || !companyID || !orgID || !productID) {
        console.error(
            `BOOTSTRAP: missing fixtures — type=${!!typeID} company=${!!companyID} org=${!!orgID} product=${!!productID}`,
        );
        console.error('Seed the demo data first: demo/seed-demo-contract.sql');
        process.exit(2);
    }

    // ---- Fixture: one contract, one quarterly year-long term, two lines. --------------------------

    const contract = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    contract.NewRecord();
    contract.ContractTypeID = typeID;
    contract.CompanyID = companyID;
    contract.CustomerOrganizationID = orgID;
    // BORN DRAFT, ACTIVATED BELOW once it has a term. A contract cannot be Active with no term
    // (ContractEntityServer.checkActiveHasATerm, added 2026-08-05) — the header records who agreed
    // and on what paper, the TERM records the dates, the money and the coverage. This fixture used
    // to create it Active and add the term afterwards, which was the only possible order before the
    // entity could compose a tree; it is now both possible and correct to assemble first.
    contract.Status = 'Draft';
    contract.Description = `${TAG}: lifecycle subject`;
    contract.EffectiveDate = new Date('2027-01-01');
    if (!(await contract.Save())) {
        console.error(`BOOTSTRAP: could not create the contract — ${contract.LatestResult?.CompleteMessage}`);
        process.exit(2);
    }

    const term = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
    term.NewRecord();
    term.ContractID = contract.ID;
    term.StartDate = new Date('2027-01-01');
    term.EndDate = new Date('2027-12-31');
    term.Status = 'Pending';
    term.BillingFrequency = 'Quarterly';
    // 3% sits under the Standard type's 5% ceiling — as of 2026-08-05 the cap lives on the TYPE, so
    // there is no per-term ceiling to set here any more.
    term.EscalationPercent = 0.03;
    term.CommittedAmount = 4000;
    if (!(await term.Save())) {
        console.error(`BOOTSTRAP: could not create the term — ${term.LatestResult?.CompleteMessage}`);
        process.exit(2);
    }

    const mkLine = async (order: number, desc: string, price: number): Promise<void> => {
        const l = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
        l.NewRecord();
        l.ContractTermID = term.ID;
        l.ProductID = productID;
        l.DisplayOrder = order;
        l.Description = desc;
        l.LineType = 'OneTime';
        l.Quantity = 1;
        l.ContractedUnitPrice = price;
        if (!(await l.Save())) {
            console.error(`BOOTSTRAP: could not create line ${order} — ${l.LatestResult?.CompleteMessage}`);
            process.exit(2);
        }
    };
    await mkLine(1, `${TAG} platform fee`, 1000);
    await mkLine(2, `${TAG} support`, 250.5);

    // Now it has a term with coverage, so it can legitimately go live.
    contract.Status = 'Active';
    if (!(await contract.Save())) {
        console.error(`BOOTSTRAP: could not activate the contract — ${contract.LatestResult?.CompleteMessage}`);
        process.exit(2);
    }

    // ---- A. Activation ---------------------------------------------------------------------------

    console.log('\nA. ActivateTerm — status, schedule and the events it implies');

    const activate = new ActivateTermOperation();
    const a1 = await activate.ExecuteServer({ ContractTermID: term.ID }, ctx);
    check('A.1 activation succeeds', a1.Success === true && a1.Output?.Success === true, a1.Output?.Message ?? a1.ErrorMessage ?? '');

    // A quarterly term spanning exactly one year bills 4 times. Not "several" — four.
    check(
        'A.2 a quarterly year produces exactly 4 billing events',
        a1.Output?.ScheduledDates?.length === 4,
        `got ${a1.Output?.ScheduledDates?.length}: ${JSON.stringify(a1.Output?.ScheduledDates)}`,
    );
    check(
        'A.3 the events fall on the term anchor, quarterly',
        JSON.stringify(a1.Output?.ScheduledDates) === JSON.stringify(['2027-01-01', '2027-04-01', '2027-07-01', '2027-10-01']),
        JSON.stringify(a1.Output?.ScheduledDates),
    );

    await term.Load(term.ID);
    check('A.4 the term is Active in the database', (term.Status as unknown as string) === 'Active', `db says ${term.Status}`);

    const schedules = await rv.RunView<{ ID: string; ScheduleType: string; Frequency: string }>(
        { EntityName: E_SCHEDULE, Fields: ['ID', 'ScheduleType', 'Frequency'], ExtraFilter: `ContractTermID='${term.ID}'`, ResultType: 'simple', BypassCache: true },
        user,
    );
    check('A.5 exactly one billing schedule was created', schedules.Results?.length === 1, `got ${schedules.Results?.length}`);
    check(
        'A.6 the schedule is a Quarterly Cadence',
        schedules.Results?.[0]?.ScheduleType === 'Cadence' && schedules.Results?.[0]?.Frequency === 'Quarterly',
        `${schedules.Results?.[0]?.ScheduleType}/${schedules.Results?.[0]?.Frequency}`,
    );

    const a2 = await activate.ExecuteServer({ ContractTermID: term.ID }, ctx);
    check('A.7 activating an already-Active term is REFUSED (no duplicate schedule)', a2.Output?.Success === false, a2.Output?.Message ?? '');

    // ---- B. Renewal ------------------------------------------------------------------------------

    console.log('\nB. RenewTerm — preview, escalation, and the clamp');

    const renew = new RenewTermOperation();

    const preview = await renew.ExecuteServer({ ContractTermID: term.ID, PreviewOnly: true }, ctx);
    check('B.1 a preview succeeds', preview.Output?.Success === true, preview.Output?.Message ?? '');
    check('B.2 the preview dates the next term to the day after this one ends', preview.Output?.StartDate === '2028-01-01', `got ${preview.Output?.StartDate}`);
    check('B.3 the preview keeps the same term length', preview.Output?.EndDate === '2028-12-31', `got ${preview.Output?.EndDate}`);
    check(
        'B.4 the preview escalates 1000.00 by 3% to exactly 1030.00',
        preview.Output?.Lines?.find((l) => l.Description.includes('platform'))?.NewUnitPrice === 1030,
        JSON.stringify(preview.Output?.Lines),
    );
    check(
        'B.5 the preview rounds 250.50 + 3% to the cent (258.02, not 258.015)',
        preview.Output?.Lines?.find((l) => l.Description.includes('support'))?.NewUnitPrice === 258.02,
        JSON.stringify(preview.Output?.Lines),
    );

    const afterPreview = await rv.RunView<{ ID: string }>(
        { EntityName: E_TERM, Fields: ['ID'], ExtraFilter: `RenewalOfTermID='${term.ID}'`, ResultType: 'simple', BypassCache: true },
        user,
    );
    check('B.6 THE PREVIEW WROTE NOTHING — no renewal term exists', afterPreview.Results?.length === 0, `${afterPreview.Results?.length} rows`);

    // The negotiated ceiling is 5%; ask for 8% and the operation must apply 5%, not 8% and not fail.
    const clamped = await renew.ExecuteServer({ ContractTermID: term.ID, PreviewOnly: true, EscalationPercentOverride: 0.08 }, ctx);
    check('B.7 an over-cap escalation is CLAMPED, not rejected', clamped.Output?.Success === true && clamped.Output?.EscalationWasClamped === true, clamped.Output?.Message ?? '');
    check('B.8 the clamp applies exactly the 5% ceiling', clamped.Output?.AppliedEscalationPercent === 0.05, `got ${clamped.Output?.AppliedEscalationPercent}`);
    check(
        'B.9 the clamped price is 1050.00, not 1080.00',
        clamped.Output?.Lines?.find((l) => l.Description.includes('platform'))?.NewUnitPrice === 1050,
        JSON.stringify(clamped.Output?.Lines),
    );

    const committed = await renew.ExecuteServer({ ContractTermID: term.ID }, ctx);
    check('B.10 the real renewal succeeds', committed.Output?.Success === true, committed.Output?.Message ?? '');
    const newTermID = committed.Output?.NewContractTermID;
    check('B.11 the new term numbers itself 2', committed.Output?.NewTermNumber === 2, `got ${committed.Output?.NewTermNumber}`);

    if (newTermID) {
        const newLines = await rv.RunView<{ Description: string; ContractedUnitPrice: number }>(
            { EntityName: E_LINE, Fields: ['Description', 'ContractedUnitPrice'], ExtraFilter: `ContractTermID='${newTermID}'`, ResultType: 'simple', BypassCache: true },
            user,
        );
        check('B.12 both lines were carried forward', newLines.Results?.length === 2, `got ${newLines.Results?.length}`);
        check(
            'B.13 the carried line price is the escalated 1030.00 in the DATABASE',
            Number(newLines.Results?.find((l) => l.Description.includes('platform'))?.ContractedUnitPrice) === 1030,
            JSON.stringify(newLines.Results),
        );

        const newTerm = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        await newTerm.Load(newTermID);
        check('B.14 the renewal starts Pending, not Active (activation stays a deliberate step)', (newTerm.Status as unknown as string) === 'Pending', `got ${newTerm.Status}`);
        check('B.15 the renewal points back at its predecessor', newTerm.RenewalOfTermID === term.ID);
        check('B.16 the committed amount escalated too — 4000 -> 4120.00', Number(newTerm.CommittedAmount) === 4120, `got ${newTerm.CommittedAmount}`);
    }

    await term.Load(term.ID);
    check('B.17 the renewed term is Completed, not deleted (the chain is the history)', (term.Status as unknown as string) === 'Completed', `got ${term.Status}`);

    const twice = await renew.ExecuteServer({ ContractTermID: term.ID }, ctx);
    check('B.18 renewing the same term twice is REFUSED (no double-billing successor)', twice.Output?.Success === false, twice.Output?.Message ?? '');

    // ---- C. Termination --------------------------------------------------------------------------

    console.log('\nC. TerminateContract — what stops billing, and what does not');

    // Activate the renewal so there is a live schedule to terminate against.
    const a3 = await activate.ExecuteServer({ ContractTermID: newTermID ?? '' }, ctx);
    check('C.1 the renewal activates and gets its own 4 events', a3.Output?.ScheduledDates?.length === 4, JSON.stringify(a3.Output?.ScheduledDates));

    const terminate = new TerminateContractOperation();

    const noReason = await terminate.ExecuteServer({ ContractID: contract.ID, Reason: '   ' }, ctx);
    check('C.2 termination without a reason is REFUSED', noReason.Output?.Success === false, noReason.Output?.Message ?? '');

    // Effective mid-year 2028: the Jan and Apr events stand, Jul and Oct are cancelled.
    const tPreview = await terminate.ExecuteServer(
        { ContractID: contract.ID, Reason: 'tier2: customer consolidation', EffectiveDate: '2028-06-30', PreviewOnly: true },
        ctx,
    );
    check('C.3 the termination preview succeeds', tPreview.Output?.Success === true, tPreview.Output?.Message ?? '');
    check('C.4 the preview cancels exactly the 2 events AFTER the effective date', tPreview.Output?.BillingEventsCancelled === 2, `got ${tPreview.Output?.BillingEventsCancelled}`);
    check('C.5 the preview RETAINS the 2 events on or before it', tPreview.Output?.BillingEventsRetained === 2, `got ${tPreview.Output?.BillingEventsRetained}`);

    await contract.Load(contract.ID);
    check('C.6 THE PREVIEW WROTE NOTHING — the contract is still Active', (contract.Status as unknown as string) === 'Active', `got ${contract.Status}`);

    const tReal = await terminate.ExecuteServer(
        { ContractID: contract.ID, Reason: 'tier2: customer consolidation', EffectiveDate: '2028-06-30' },
        ctx,
    );
    check('C.7 the real termination succeeds', tReal.Output?.Success === true, tReal.Output?.Message ?? '');

    await contract.Load(contract.ID);
    check('C.8 the contract is Terminated', (contract.Status as unknown as string) === 'Terminated', `got ${contract.Status}`);

    // THE ASSERTION THAT MATTERS. Read the schedule back and confirm the split is real in the DB.
    const finalEvents = await rv.RunView<{ ScheduledDate: string; Status: string }>(
        {
            EntityName: E_BILLING_EVENT,
            Fields: ['ScheduledDate', 'Status'],
            ExtraFilter: `ContractTermID='${newTermID}'`,
            OrderBy: 'ScheduledDate',
            ResultType: 'simple',
            BypassCache: true,
        },
        user,
    );
    // Format through Date, not String(): a `date` column comes back as a Date object, and
    // String(date).slice(0,10) yields "Fri Dec 31" — which would silently pass a sloppier assertion.
    const rows = (finalEvents.Results ?? []).map((e) => `${new Date(e.ScheduledDate).toISOString().slice(0, 10)}=${e.Status}`);
    check(
        'C.9 past events still Scheduled, future events Cancelled — exactly',
        JSON.stringify(rows) === JSON.stringify(['2028-01-01=Scheduled', '2028-04-01=Scheduled', '2028-07-01=Cancelled', '2028-10-01=Cancelled']),
        JSON.stringify(rows),
    );

    const finalTerm = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
    if (newTermID) await finalTerm.Load(newTermID);
    check('C.10 the term records the early-termination date', fmt(finalTerm.EarlyTerminationDate) === '2028-06-30', `got ${String(finalTerm.EarlyTerminationDate)}`);

    const logs = await rv.RunView<{ EventType: string; Payload: string }>(
        { EntityName: E_LOG, Fields: ['EventType', 'Payload'], ExtraFilter: `ContractID='${contract.ID}'`, ResultType: 'simple', BypassCache: true },
        user,
    );
    const kinds = (logs.Results ?? []).map((l) => l.EventType).sort();
    check(
        'C.11 every transition left a lifecycle event (2 activations, 1 renewal, 1 termination)',
        JSON.stringify(kinds) === JSON.stringify(['ContractTerminated', 'TermActivated', 'TermActivated', 'TermRenewed']),
        JSON.stringify(kinds),
    );
    check(
        'C.12 the termination reason is recorded on the event',
        (logs.Results ?? []).some((l) => l.EventType === 'ContractTerminated' && l.Payload?.includes('customer consolidation')),
    );

    // ---- CD. Schedule arithmetic — the edge cases the comments CLAIM ------------------------------
    //
    // ActivateTerm's `occurrences()` says it clamps to the month's last day rather than rolling over,
    // because setMonth() rolling over is the classic way a monthly schedule silently loses a month.
    // That claim was written in a comment and never tested. A comment is not evidence.

    console.log('\nCD. Schedule arithmetic at the month boundaries');

    const mkFixture = async (start: string, end: string, freq: string): Promise<string> => {
        const c = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
        c.NewRecord();
        c.ContractTypeID = typeID;
        c.CompanyID = companyID;
        c.CustomerOrganizationID = orgID;
        // Draft until it has a term — see the note on the main fixture above.
        c.Status = 'Draft';
        c.Description = `${TAG}: schedule ${start} ${freq}`;
        if (!(await c.Save())) throw new Error(`mkFixture contract: ${c.LatestResult?.CompleteMessage}`);
        const t = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        t.NewRecord();
        t.ContractID = c.ID;
        t.StartDate = new Date(start);
        t.EndDate = new Date(end);
        t.Status = 'Pending';
        t.BillingFrequency = freq as typeof t.BillingFrequency;
        t.CommittedAmount = 0;
        await t.Save();
        const l = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
        l.NewRecord();
        l.ContractTermID = t.ID;
        l.ProductID = productID;
        l.DisplayOrder = 1;
        l.LineType = 'OneTime';
        l.Quantity = 1;
        l.ContractedUnitPrice = 100;
        l.Description = `${TAG} schedule line`;
        if (!(await l.Save())) throw new Error(`mkFixture line: ${l.LatestResult?.CompleteMessage}`);
        c.Status = 'Active';
        if (!(await c.Save())) throw new Error(`mkFixture activate: ${c.LatestResult?.CompleteMessage}`);
        return t.ID;
    };

    // A term starting Jan 31, billed monthly. Rolling over would put February's event in MARCH and
    // produce eleven events for a twelve-month term — the loss is silent and compounding.
    const jan31 = await mkFixture('2029-01-31', '2029-12-31', 'Monthly');
    const r1 = await activate.ExecuteServer({ ContractTermID: jan31 }, ctx);
    const d1 = r1.Output?.ScheduledDates ?? [];
    check('CD.1 a monthly year from Jan 31 produces 12 events, not 11', d1.length === 12, `${d1.length}: ${JSON.stringify(d1)}`);
    check('CD.2 February clamps to the 28th rather than rolling into March', d1[1] === '2029-02-28', `got ${d1[1]}`);
    check('CD.3 April clamps to the 30th', d1[3] === '2029-04-30', `got ${d1[3]}`);
    check('CD.4 a long month returns to the 31st — the clamp does not stick', d1[4] === '2029-05-31', `got ${d1[4]}`);

    // 2028 is a leap year: February has 29 days, and the clamp must use the real month length.
    const leap = await mkFixture('2028-01-31', '2028-03-31', 'Monthly');
    const r2 = await activate.ExecuteServer({ ContractTermID: leap }, ctx);
    const d2 = r2.Output?.ScheduledDates ?? [];
    check('CD.5 a leap February clamps to the 29th, not the 28th', d2[1] === '2028-02-29', JSON.stringify(d2));

    // A term shorter than one cadence still bills once — at the start. Zero events would mean an
    // Active term that never bills, which is the failure ActivateTerm exists to prevent.
    const short = await mkFixture('2029-01-01', '2029-02-15', 'Quarterly');
    const r3 = await activate.ExecuteServer({ ContractTermID: short }, ctx);
    check('CD.6 a term shorter than its cadence still bills once, at the start',
        JSON.stringify(r3.Output?.ScheduledDates) === JSON.stringify(['2029-01-01']),
        JSON.stringify(r3.Output?.ScheduledDates));

    // Milestone billing has no cadence: milestones are reached, not calculated. A schedule is still
    // created (so a human can place events on it) but inventing dates nobody agreed to would be worse
    // than none.
    const milestone = await mkFixture('2029-01-01', '2029-12-31', 'Milestone');
    const r4 = await activate.ExecuteServer({ ContractTermID: milestone }, ctx);
    check('CD.7 a Milestone term gets a schedule but ZERO invented dates',
        r4.Output?.Success === true && (r4.Output?.ScheduledDates?.length ?? -1) === 0 && !!r4.Output?.BillingScheduleID,
        JSON.stringify(r4.Output));

    // ---- D. Teardown -----------------------------------------------------------------------------

    console.log('\nD. Teardown');
    // Sweep by TAG, not by this run's ID: a harness that crashed mid-way leaves rows behind, and the
    // next run must clean them up rather than accumulate them and then fail its own leftover check.
    const mine = await rv.RunView<{ ID: string }>(
        { EntityName: E_CONTRACT, Fields: ['ID'], ExtraFilter: `Description LIKE '${TAG}%'`, ResultType: 'simple', BypassCache: true },
        user,
    );
    for (const row of mine.Results ?? []) {
        await teardown(md, rv, user, row.ID, pool);
    }
    const leftover = await rv.RunView<{ ID: string }>(
        { EntityName: E_CONTRACT, Fields: ['ID'], ExtraFilter: `Description LIKE '${TAG}%'`, ResultType: 'simple', BypassCache: true },
        user,
    );
    check('D.1 teardown left nothing behind', (leftover.Results?.length ?? -1) === 0, `${leftover.Results?.length} rows remain`);

    console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
    if (failed) failures.forEach((f) => console.log(`  · ${f}`));

    void pool.close().catch(() => undefined);
    process.exit(failed === 0 ? 0 : 1);
}

/**
 * FK-aware cleanup, in RAW SQL rather than through the entity layer.
 *
 * Two reasons, both learned here. First, ContractEventEntityServer now REFUSES Delete outright —
 * that refusal is a feature (an audit trail a caller can erase is not an audit trail), so the
 * harness has to clean up beneath the guard it is testing. Second, entity-layer teardown proved
 * unreliable at this scale: a delete would fail with "Error executing SQL" while the same delete in
 * raw SQL and the generated sproc called directly both succeeded, so the cause was somewhere in the
 * read-then-delete round trip rather than in the data. Deterministic set-based deletes have no such
 * failure mode, and cleanup is not the thing under test.
 */
async function teardown(_md: Metadata, _rv: RunView, _user: UserInfo, contractID: string, pool: sql.ConnectionPool): Promise<void> {
    await pool.request().query(`
        DECLARE @c UNIQUEIDENTIFIER = '${contractID}';
        DECLARE @terms TABLE (ID UNIQUEIDENTIFIER);
        INSERT INTO @terms SELECT ID FROM __mj_BizAppsContracts.ContractTerm WHERE ContractID = @c;

        DELETE be FROM __mj_BizAppsContracts.ContractBillingEvent be JOIN @terms t ON t.ID = be.ContractTermID;
        DELETE bs FROM __mj_BizAppsContracts.ContractBillingSchedule bs JOIN @terms t ON t.ID = bs.ContractTermID;
        DELETE cl FROM __mj_BizAppsContracts.ContractLine cl JOIN @terms t ON t.ID = cl.ContractTermID;
        DELETE FROM __mj_BizAppsContracts.ContractEvent WHERE ContractID = @c;
        -- Renewals reference their predecessor, so the chain unwinds newest-first.
        DELETE FROM __mj_BizAppsContracts.ContractTerm WHERE ContractID = @c AND RenewalOfTermID IS NOT NULL;
        DELETE FROM __mj_BizAppsContracts.ContractTerm WHERE ContractID = @c;
        DELETE FROM __mj_BizAppsContracts.Contract WHERE ID = @c;`);
}

function fmt(d: Date | null): string {
    return d ? new Date(d).toISOString().slice(0, 10) : '(null)';
}

void main().catch((e) => {
    console.error('HARNESS ERROR:', e instanceof Error ? (e.stack ?? e.message) : String(e));
    process.exit(2);
});
