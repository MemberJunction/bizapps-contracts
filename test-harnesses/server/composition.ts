/**
 * @fileoverview Tier 2 — the contract as a COMPOSITION: one entity, one transaction, one tree.
 *
 * What this proves, and why each proof is shaped the way it is:
 *
 *  A. **A whole agreement writes in one `Save()`** — contract, terms, coverage, schedules and
 *     commitments — and the rows are really there. Verified by RAW SQL underneath the entity layer,
 *     because a caching or lying entity layer would happily report its own in-memory collections
 *     back and pass a test that asserted `contract.Terms.length`.
 *
 *  B. **A failure anywhere rolls back everything, including the contract number.** This is the whole
 *     point of the change: the UI used to save the contract, then the term, then each line as
 *     separate round trips, so a failure partway left a numbered contract with nothing under it.
 *     The sequence counter is checked before and after — an EXACT value — because allocation happens
 *     inside the transaction and a rollback must return the number.
 *
 *  C. **Lazy is lazy, and un-hydrated is not empty.** `Load()` leaves the tree unread; `LoadFull()`
 *     reads it; and the cross-child validators stay SILENT on a lazily loaded record rather than
 *     refusing it. That last one is the subtle bug this design was built to avoid, so it is asserted
 *     directly rather than assumed.
 *
 *  D. **The rules that now live in the new server subclasses** — coverage inside its term, a closed
 *     term refusing new coverage, an amendment against a live term only, a billing plan frozen once
 *     it has billed, a contract type whose default escalation fits under its own ceiling. Each is
 *     asserted as a REFUSAL with the reason, not as an absence of success.
 *
 * Run:  npx tsx test-harnesses/server/composition.ts
 * Exit: 0 pass · 1 test failure · 2 bootstrap failure
 */

import sql from 'mssql';
import dotenv from 'dotenv';
import path from 'path';
import { Metadata, RunView, type UserInfo } from '@memberjunction/core';
import { setupSQLServerClient, SQLServerProviderConfigData, UserCache } from '@memberjunction/sqlserver-dataprovider';
import '@memberjunction/server-bootstrap-lite';
import '@mj-biz-apps/common-entities';
import '@mj-biz-apps/orders-entities';
import '@mj-biz-apps/contracts-entities';
// Importing the server package is what registers the subclasses under test. Without it this harness
// would exercise the plain generated entities and pass while proving nothing.
import '@mj-biz-apps/contracts-core-entities-server';
import type {
    ContractEntityServer,
    ContractTermEntityServer,
    ContractTypeEntityServer,
    ContractAmendmentEntityServer,
} from '@mj-biz-apps/contracts-core-entities-server';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_TYPE = 'MJ_BizApps_Contracts: Contract Types';
const E_AMENDMENT = 'MJ_BizApps_Contracts: Contract Amendments';

/** Everything this run writes carries this tag, so teardown and leak-detection are exact. */
const TAG = 'tier2-composition';

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

const createdContracts: string[] = [];

async function main(): Promise<void> {
    dotenv.config({ path: path.resolve(process.cwd(), '../../../.env'), quiet: true });
    dotenv.config({ path: path.resolve(process.cwd(), '.env'), quiet: true });

    const pool = await new sql.ConnectionPool({
        server: process.env.DB_HOST ?? 'localhost',
        port: Number(process.env.DB_PORT ?? 1433),
        user: process.env.DB_USERNAME,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_DATABASE,
        options: { encrypt: false, trustServerCertificate: true },
        requestTimeout: 60000,
    }).connect();

    await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
    await UserCache.Instance.Refresh(pool);
    const user: UserInfo | undefined =
        UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    if (!user) {
        console.error('BOOTSTRAP: no context user');
        process.exit(2);
    }

    const md = new Metadata();
    const rv = new RunView();

    // Fixtures are READ, never created — this harness must not invent companies or products.
    const [types, companies, orgs, products, subTypes] = await rv.RunViews(
        [
            { EntityName: E_TYPE, Fields: ['ID', 'Code'], ResultType: 'simple' },
            { EntityName: 'MJ: Companies', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Common: Organizations', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Products', Fields: ['ID'], MaxRows: 2, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Subscription Types', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
        ],
        user,
    );
    const typeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'Standard')?.ID;
    const companyID = (companies?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const orgID = (orgs?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const productIDs = (products?.Results as { ID: string }[] | undefined)?.map((p) => p.ID) ?? [];
    const subTypeID = (subTypes?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    if (!typeID || !companyID || !orgID || productIDs.length < 2 || !subTypeID) {
        console.error(
            `BOOTSTRAP: missing fixtures — type=${!!typeID} company=${!!companyID} org=${!!orgID} ` +
                `products=${productIDs.length} subscriptionType=${!!subTypeID}`,
        );
        console.error('Seed the demo data first: demo/seed-demo-contract.sql');
        process.exit(2);
    }

    /** Raw-SQL count, UNDERNEATH the entity layer — an entity cache cannot fake this. */
    async function rawCount(table: string, where: string): Promise<number> {
        const result = await pool.request().query(`SELECT COUNT(*) AS N FROM __mj_BizAppsContracts.${table} WHERE ${where}`);
        return Number(result.recordset[0]?.N ?? -1);
    }

    async function sequenceValue(): Promise<number> {
        const result = await pool.request().query('SELECT NextSequenceNumber AS N FROM __mj_BizAppsContracts.ContractSequence');
        return Number(result.recordset[0]?.N ?? -1);
    }

    /** A contract header with the fixtures filled in — every test starts from this shape. */
    async function newContract(description: string): Promise<ContractEntityServer> {
        const c = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
        c.NewRecord();
        c.ContractTypeID = typeID!;
        c.CompanyID = companyID!;
        c.CustomerOrganizationID = orgID!;
        c.Status = 'Draft';
        c.Description = `${TAG}: ${description}`;
        c.MarkTermsAuthoritative();
        return c;
    }

    /* ═══════════════════════════════════════════════════════════════════════════════════════════
     * A. The whole agreement, in ONE Save()
     * ═══════════════════════════════════════════════════════════════════════════════════════════ */
    console.log('\nA. One Save() writes contract + terms + coverage + schedules + commitments');

    const whole = await newContract('whole tree');

    const term1 = await whole.CreateTerm(user);
    term1.StartDate = new Date('2030-01-01');
    term1.EndDate = new Date('2030-12-31');
    term1.Status = 'Pending';
    term1.BillingFrequency = 'Quarterly';
    term1.CommittedAmount = 120000;

    const t1line1 = await term1.CreateLine(user);
    t1line1.ProductID = productIDs[0];
    t1line1.LineType = 'Subscription';
    t1line1.SubscriptionTypeID = subTypeID;
    t1line1.Quantity = 10;
    t1line1.ContractedUnitPrice = 1000;

    const t1line2 = await term1.CreateLine(user);
    t1line2.ProductID = productIDs[1];
    t1line2.LineType = 'OneTime';
    t1line2.Quantity = 1;
    t1line2.ContractedUnitPrice = 5000;

    const t1schedule = await term1.CreateSchedule(user);
    t1schedule.ScheduleType = 'Cadence';
    t1schedule.Frequency = 'Quarterly';
    t1schedule.AnchorDate = new Date('2030-01-01');

    const t1commitment = await term1.CreateCommitment(user);
    t1commitment.CommitmentType = 'Minimum';
    t1commitment.CommittedAmount = 120000;
    t1commitment.ConsumedAmount = 0;
    t1commitment.TrueUpPolicy = 'BillShortfall';
    t1commitment.Status = 'Open';

    const term2 = await whole.CreateTerm(user);
    term2.StartDate = new Date('2031-01-01');
    term2.EndDate = new Date('2031-12-31');
    term2.Status = 'Pending';
    term2.BillingFrequency = 'Annual';

    const t2line = await term2.CreateLine(user);
    t2line.ProductID = productIDs[0];
    t2line.LineType = 'Subscription';
    t2line.SubscriptionTypeID = subTypeID;
    t2line.Quantity = 12;
    t2line.ContractedUnitPrice = 1100;

    let wholeSaved = false;
    let wholeError = '';
    try {
        wholeSaved = await whole.Save();
    } catch (e) {
        wholeError = e instanceof Error ? e.message : String(e);
    }
    if (wholeSaved) createdContracts.push(whole.ID);

    check('A.1 a contract with 2 terms, 3 lines, 1 schedule and 1 commitment saves in one call', wholeSaved, wholeError);
    check('A.2 the contract got its number', /^CTR-\d{6}$/.test(whole.ContractNumber ?? ''), `got "${whole.ContractNumber}"`);
    check('A.3 [raw SQL] exactly 2 term rows exist', (await rawCount('ContractTerm', `ContractID='${whole.ID}'`)) === 2);
    check(
        'A.4 [raw SQL] exactly 3 coverage rows exist across those terms',
        (await rawCount('ContractLine', `ContractTermID IN ('${term1.ID}','${term2.ID}')`)) === 3,
    );
    check('A.5 [raw SQL] exactly 1 billing schedule exists', (await rawCount('ContractBillingSchedule', `ContractTermID='${term1.ID}'`)) === 1);
    check('A.6 [raw SQL] exactly 1 commitment exists', (await rawCount('ContractCommitment', `ContractTermID='${term1.ID}'`)) === 1);
    check('A.7 term numbers were DERIVED as 1 and 2, not collided on 1', term1.TermNumber === 1 && term2.TermNumber === 2,
        `got ${term1.TermNumber} and ${term2.TermNumber}`);
    check('A.8 coverage was sequenced positionally within its term', t1line1.DisplayOrder === 1 && t1line2.DisplayOrder === 2,
        `got ${t1line1.DisplayOrder} and ${t1line2.DisplayOrder}`);

    /* ═══════════════════════════════════════════════════════════════════════════════════════════
     * B. All-or-none — a grandchild failure takes the whole tree, and the number, with it
     * ═══════════════════════════════════════════════════════════════════════════════════════════ */
    console.log('\nB. A failure in ONE line rolls back the contract, its terms, and the sequence');

    const sequenceBefore = await sequenceValue();

    const doomed = await newContract('rollback proof');
    const doomedTerm = await doomed.CreateTerm(user);
    doomedTerm.StartDate = new Date('2030-01-01');
    doomedTerm.EndDate = new Date('2030-12-31');
    doomedTerm.Status = 'Pending';
    doomedTerm.BillingFrequency = 'Annual';

    const goodLine = await doomedTerm.CreateLine(user);
    goodLine.ProductID = productIDs[0];
    goodLine.LineType = 'OneTime';
    goodLine.Quantity = 1;
    goodLine.ContractedUnitPrice = 100;

    // A Subscription line with no SubscriptionTypeID. Refused by ContractLineEntityServer.Validate,
    // which is the failure we want: it happens at the DEEPEST level of the tree, after the header
    // and the term and one good line have already been written inside the transaction.
    const badLine = await doomedTerm.CreateLine(user);
    badLine.ProductID = productIDs[1];
    badLine.LineType = 'Subscription';
    badLine.Quantity = 1;

    let doomedSaved = false;
    let doomedThrew = false;
    try {
        doomedSaved = await doomed.Save();
    } catch {
        doomedThrew = true;
    }

    check('B.1 the save did not succeed', doomedSaved === false, doomedSaved ? 'it returned true' : '');
    check('B.2 the failure surfaced as an exception rather than a silent false', doomedThrew);
    check(
        'B.3 [raw SQL] NO contract row survived — not even the header that saved first',
        (await rawCount('Contract', `Description='${TAG}: rollback proof'`)) === 0,
    );
    check(
        'B.4 [raw SQL] no orphan term survived either',
        (await rawCount('ContractTerm', `ID='${doomedTerm.ID}'`)) === 0,
    );
    check(
        'B.5 [raw SQL] the good line that HAD saved was rolled back too',
        (await rawCount('ContractLine', `ID='${goodLine.ID}'`)) === 0,
    );
    const sequenceAfter = await sequenceValue();
    check(
        'B.6 the contract number was RETURNED to the sequence, not stranded',
        sequenceAfter === sequenceBefore,
        `${sequenceBefore} -> ${sequenceAfter}`,
    );

    /* ═══════════════════════════════════════════════════════════════════════════════════════════
     * C. Lazy hydration, and the un-hydrated-is-not-empty rule
     * ═══════════════════════════════════════════════════════════════════════════════════════════ */
    console.log('\nC. Lazy loading, and the gate that stops it becoming a false refusal');

    const shallow = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
    await shallow.Load(whole.ID);
    check('C.1 Load() leaves the terms unread — the roster case', shallow.Terms.length === 0 && !shallow.TermsAreLoaded,
        `${shallow.Terms.length} terms, loaded=${shallow.TermsAreLoaded}`);

    const deep = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
    await deep.Load(whole.ID);
    await deep.LoadFull(user);
    check('C.2 LoadFull() reads both terms', deep.Terms.length === 2 && deep.TermsAreLoaded, `${deep.Terms.length} terms`);
    const deepT1 = deep.Terms.find((t) => t.TermNumber === 1);
    const deepT2 = deep.Terms.find((t) => t.TermNumber === 2);
    check('C.3 each term got ITS OWN coverage, not the other term\'s', deepT1?.Lines.length === 2 && deepT2?.Lines.length === 1,
        `term1=${deepT1?.Lines.length} term2=${deepT2?.Lines.length}`);
    check('C.4 the schedule and commitment landed on term 1 only',
        deepT1?.Schedules.length === 1 && deepT1?.Commitments.length === 1 && deepT2?.Schedules.length === 0 && deepT2?.Commitments.length === 0,
        `t1 sched=${deepT1?.Schedules.length} commit=${deepT1?.Commitments.length}; t2 sched=${deepT2?.Schedules.length} commit=${deepT2?.Commitments.length}`);
    check('C.5 the exact contracted price round-tripped', deepT1?.Lines.find((l) => l.LineType === 'OneTime')?.ContractedUnitPrice === 5000,
        `got ${deepT1?.Lines.find((l) => l.LineType === 'OneTime')?.ContractedUnitPrice}`);

    // THE SUBTLE ONE. A lazily loaded ACTIVE contract must still be editable: its empty Terms
    // collection means "not asked for", and a validator that read it as "has no terms" would refuse
    // every edit to every live contract in the system.
    const activeContract = await newContract('active with a term');
    const activeTerm = await activeContract.CreateTerm(user);
    activeTerm.StartDate = new Date('2030-01-01');
    activeTerm.EndDate = new Date('2030-12-31');
    activeTerm.Status = 'Pending';
    activeTerm.BillingFrequency = 'Annual';
    const activeLine = await activeTerm.CreateLine(user);
    activeLine.ProductID = productIDs[0];
    activeLine.LineType = 'OneTime';
    activeLine.Quantity = 1;
    activeLine.ContractedUnitPrice = 999;
    if (await activeContract.Save()) createdContracts.push(activeContract.ID);
    activeContract.Status = 'Active';
    const activatedWithTerms = await activeContract.Save();
    check('C.6 an Active contract WITH a term saves', activatedWithTerms, activeContract.LatestResult?.CompleteMessage ?? '');

    const lazyActive = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
    await lazyActive.Load(activeContract.ID);
    lazyActive.Description = `${TAG}: active with a term (edited lazily)`;
    const lazyEditSaved = await lazyActive.Save();
    check(
        'C.7 editing a lazily loaded ACTIVE contract is NOT refused for "having no terms"',
        lazyEditSaved,
        lazyActive.LatestResult?.CompleteMessage ?? '',
    );

    // And the complement — the rule really does fire when the collection IS authoritative.
    const emptyActive = await newContract('active with no term');
    emptyActive.Status = 'Active';
    const emptyActiveSaved = await emptyActive.Save().catch(() => false);
    if (emptyActiveSaved) createdContracts.push(emptyActive.ID);
    check('C.8 but an in-memory Active contract with NO term is refused', emptyActiveSaved === false,
        emptyActiveSaved ? 'it saved' : '');

    /* ═══════════════════════════════════════════════════════════════════════════════════════════
     * D. The rules the new server subclasses added
     * ═══════════════════════════════════════════════════════════════════════════════════════════ */
    console.log('\nD. Rules that now live in BaseEntity rather than only in a CHECK');

    const host = await newContract('subclass rules');
    const hostTerm = await host.CreateTerm(user);
    hostTerm.StartDate = new Date('2030-06-01');
    hostTerm.EndDate = new Date('2030-12-31');
    hostTerm.Status = 'Pending';
    hostTerm.BillingFrequency = 'Monthly';
    const hostLine = await hostTerm.CreateLine(user);
    hostLine.ProductID = productIDs[0];
    hostLine.LineType = 'OneTime';
    hostLine.Quantity = 1;
    hostLine.ContractedUnitPrice = 10;
    if (await host.Save()) createdContracts.push(host.ID);

    // D.1 — coverage reaching past the end of its term.
    const overrun = await hostTerm.CreateLine(user);
    overrun.ProductID = productIDs[1];
    overrun.LineType = 'OneTime';
    overrun.Quantity = 1;
    overrun.StartDate = new Date('2030-06-01');
    overrun.EndDate = new Date('2031-06-01');
    const overrunSaved = await overrun.Save();
    check('D.1 coverage running past its term\'s end is refused', overrunSaved === false, overrunSaved ? 'it saved' : '');
    check('D.1b and the refusal names the end date rather than a constraint symbol',
        (overrun.LatestResult?.CompleteMessage ?? '').includes('past the end of term'),
        overrun.LatestResult?.CompleteMessage ?? '');
    hostTerm.RemoveLine(overrun);

    // D.2 — coverage starting before its term begins.
    const early = await hostTerm.CreateLine(user);
    early.ProductID = productIDs[1];
    early.LineType = 'OneTime';
    early.Quantity = 1;
    early.StartDate = new Date('2030-01-01');
    const earlySaved = await early.Save();
    check('D.2 coverage starting before its term begins is refused', earlySaved === false, earlySaved ? 'it saved' : '');
    hostTerm.RemoveLine(early);

    // D.3 — a Subscription line with no subscription type, said readably.
    const typeless = await hostTerm.CreateLine(user);
    typeless.ProductID = productIDs[1];
    typeless.LineType = 'Subscription';
    typeless.Quantity = 1;
    const typelessSaved = await typeless.Save();
    check('D.3 a Subscription line with no subscription type is refused', typelessSaved === false, typelessSaved ? 'it saved' : '');
    check('D.3b with a sentence, not "CK_ContractLine_SubscriptionNeedsType"',
        (typeless.LatestResult?.CompleteMessage ?? '').includes('WHICH KIND of subscription'),
        typeless.LatestResult?.CompleteMessage ?? '');
    hostTerm.RemoveLine(typeless);

    // D.4 — a closed term does not gain coverage.
    const closedTerm = await md.GetEntityObject<ContractTermEntityServer>(E_TERM, user);
    await closedTerm.Load(hostTerm.ID);
    closedTerm.Status = 'Active';
    await closedTerm.LoadChildren(user);
    const activatedTerm = await closedTerm.Save();
    check('D.4a an Active term WITH coverage saves', activatedTerm, closedTerm.LatestResult?.CompleteMessage ?? '');
    closedTerm.Status = 'Completed';
    const completedTerm = await closedTerm.Save();
    check('D.4b the term completes', completedTerm, closedTerm.LatestResult?.CompleteMessage ?? '');

    const lateCoverage = await closedTerm.CreateLine(user);
    lateCoverage.ProductID = productIDs[1];
    lateCoverage.LineType = 'OneTime';
    lateCoverage.Quantity = 1;
    const lateCoverageSaved = await lateCoverage.Save();
    check('D.4c coverage added to a Completed term is refused', lateCoverageSaved === false, lateCoverageSaved ? 'it saved' : '');
    closedTerm.RemoveLine(lateCoverage);

    // D.5 — an Active term with no coverage at all.
    const bareContract = await newContract('bare active term');
    const bareTerm = await bareContract.CreateTerm(user);
    bareTerm.StartDate = new Date('2030-01-01');
    bareTerm.EndDate = new Date('2030-12-31');
    bareTerm.Status = 'Active';
    bareTerm.BillingFrequency = 'Annual';
    const bareSaved = await bareContract.Save().catch(() => false);
    if (bareSaved) createdContracts.push(bareContract.ID);
    check('D.5 an Active term with NO coverage is refused', bareSaved === false, bareSaved ? 'it saved' : '');

    // D.6 — an amendment may only target a term that is running.
    const amendment = await md.GetEntityObject<ContractAmendmentEntityServer>(E_AMENDMENT, user);
    amendment.NewRecord();
    amendment.ContractTermID = closedTerm.ID; // Completed
    amendment.EffectiveDate = new Date('2030-07-01');
    amendment.AmendmentType = 'ChangeQuantity';
    amendment.Status = 'Draft';
    amendment.Description = `${TAG}: amendment on a completed term`;
    const amendmentSaved = await amendment.Save();
    check('D.6 an amendment against a Completed term is refused', amendmentSaved === false, amendmentSaved ? 'it saved' : '');
    check('D.6b and it says to renew instead of amend',
        (amendment.LatestResult?.CompleteMessage ?? '').includes('renew into a new term'),
        amendment.LatestResult?.CompleteMessage ?? '');

    // D.7 — a contract type whose default escalation exceeds its own default ceiling.
    const badType = await md.GetEntityObject<ContractTypeEntityServer>(E_TYPE, user);
    badType.NewRecord();
    badType.Code = `${TAG}-badtype-${Date.now().toString().slice(-6)}`;
    badType.Name = `${TAG} bad type`;
    badType.RenewalMode = 'Deal';
    badType.DefaultEscalationPercent = 0.06;
    badType.DefaultMaxEscalationPercent = 0.05;
    const badTypeSaved = await badType.Save();
    check('D.7 a type prescribing 6% escalation under a 5% ceiling is refused', badTypeSaved === false, badTypeSaved ? 'it saved' : '');
    check('D.7b and the refusal explains it would be reported against the TERM otherwise',
        (badType.LatestResult?.CompleteMessage ?? '').includes('not where it can be fixed'),
        badType.LatestResult?.CompleteMessage ?? '');

    /* ═══════════════════════════════════════════════════════════════════════════════════════════
     * E. Teardown — the tree deletes bottom-up through the same collections
     * ═══════════════════════════════════════════════════════════════════════════════════════════ */
    console.log('\nE. Teardown');

    for (const id of createdContracts) {
        const c = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
        if (!(await c.Load(id))) continue;
        await c.LoadFull(user);
        for (const term of [...c.Terms]) c.RemoveTerm(term);
        try {
            await c.Save();
        } catch (e) {
            console.log(`    (term teardown for ${id}: ${e instanceof Error ? e.message : String(e)})`);
        }
        await c.Delete();
    }

    const leftoverContracts = await rawCount('Contract', `Description LIKE '${TAG}%'`);
    check('E.1 no contract rows left behind', leftoverContracts === 0, `${leftoverContracts} remain`);
    const leftoverTypes = await rawCount('ContractType', `Name LIKE '${TAG}%'`);
    check('E.2 no contract-type rows left behind', leftoverTypes === 0, `${leftoverTypes} remain`);

    console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
    if (failed) failures.forEach((f) => console.log(`  · ${f}`));

    // NEVER await pool.close() — the MJ provider's pool can hang forever and the process never exits.
    void pool.close().catch(() => undefined);
    process.exit(failed === 0 ? 0 : 1);
}

void main().catch((e) => {
    console.error('HARNESS ERROR:', e instanceof Error ? (e.stack ?? e.message) : String(e));
    process.exit(2);
});
