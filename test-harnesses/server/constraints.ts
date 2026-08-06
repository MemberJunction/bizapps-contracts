/**
 * @fileoverview Tier 2 — the invariants added to close the gaps the feature enumeration found.
 *
 * Every assertion here is a REFUSAL. That is the point: each of these states used to save happily,
 * and each one is a specific way the data could tell a lie —
 *
 *   X.5  a Subscription line with no type: saves, then fails at BILLING time on a live contract,
 *        because orders.Subscription.SubscriptionTypeID is NOT NULL.
 *   X.6  a Superseded contract with no successor: the exact state SupersededByContractID was added
 *        to eliminate, left optional.
 *   X.8  a renewal chain crossing contracts: walking it surfaces another contract's terms as this
 *        one's history.
 *   X.9  two lines owning one subscription: duplicate billing, from the side BillingMode does not
 *        cover.
 *   X.12 a Generated event with no GeneratedAt: "when did this bill get produced" optional in the
 *        one status where it must exist.
 *   X.14 an Approved amendment with no approval task: an approval with no record.
 *   X.15 a free-text event type, and an editable/deletable audit trail.
 *
 * A test that only proved the happy path would pass on all of the above. These prove the NO.
 *
 * Run:  npx tsx test-harnesses/server/constraints.ts
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
import '@mj-biz-apps/contracts-core-entities-server';
import type {
    mjBizAppsContractsContractBillingEventEntity,
    mjBizAppsContractsContractBillingScheduleEntity,
    mjBizAppsContractsContractEntity,
    mjBizAppsContractsContractTermEntity,
    mjBizAppsContractsContractLineEntity,
    mjBizAppsContractsContractEventEntity,
} from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_LINE = 'MJ_BizApps_Contracts: Contract Lines';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';
const E_SCHEDULE_ENT = 'MJ_BizApps_Contracts: Contract Billing Schedules';
const E_BILLING_EVT = 'MJ_BizApps_Contracts: Contract Billing Events';

const TAG = 'tier2-constraints';

let passed = 0, failed = 0;
const failures: string[] = [];
function check(name: string, ok: boolean, detail = ''): void {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; failures.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
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
        // enableQuotedIdentifier is REQUIRED, not cosmetic: ContractLine now carries a filtered
        // unique index (UQ_ContractLine_Subscription), and SQL Server refuses any DML against a table
        // with one when the session has QUOTED_IDENTIFIER off — which is tedious's default. Without
        // this the harness's own raw-SQL teardown dies while the code under test is perfectly fine.
        options: { encrypt: false, trustServerCertificate: true, enableQuotedIdentifier: true },
        requestTimeout: 60000,
    }).connect();

    await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
    await UserCache.Instance.Refresh(pool);
    const user: UserInfo | undefined =
        UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    if (!user) { console.error('BOOTSTRAP: no context user'); process.exit(2); }

    const md = new Metadata();
    const rv = new RunView();

    const [types, companies, orgs, products, subTypes] = await rv.RunViews(
        [
            { EntityName: 'MJ_BizApps_Contracts: Contract Types', Fields: ['ID', 'Code'], ResultType: 'simple' },
            { EntityName: 'MJ: Companies', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Common: Organizations', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Products', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Subscription Types', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
        ],
        user,
    );
    const typeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'Standard')?.ID;
    const companyID = (companies?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const orgID = (orgs?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const productID = (products?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const subTypeID = (subTypes?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    if (!typeID || !companyID || !orgID || !productID) {
        console.error(`BOOTSTRAP: missing fixtures — type=${!!typeID} company=${!!companyID} org=${!!orgID} product=${!!productID}`);
        process.exit(2);
    }

    const mkContract = async (label: string): Promise<mjBizAppsContractsContractEntity> => {
        const c = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
        c.NewRecord();
        c.ContractTypeID = typeID;
        c.CompanyID = companyID;
        c.CustomerOrganizationID = orgID;
        c.Status = 'Draft';
        c.Description = `${TAG}: ${label}`;
        if (!(await c.Save())) { console.error(`BOOTSTRAP: ${label} — ${c.LatestResult?.CompleteMessage}`); process.exit(2); }
        return c;
    };
    const mkTerm = async (contractID: string, year: number): Promise<mjBizAppsContractsContractTermEntity> => {
        const t = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        t.NewRecord();
        t.ContractID = contractID;
        t.StartDate = new Date(`${year}-01-01`);
        t.EndDate = new Date(`${year}-12-31`);
        t.Status = 'Pending';
        t.BillingFrequency = 'Annual';
        t.CommittedAmount = 0;
        if (!(await t.Save())) { console.error(`BOOTSTRAP: term ${year} — ${t.LatestResult?.CompleteMessage}`); process.exit(2); }
        return t;
    };

    const cA = await mkContract('contract A');
    const cB = await mkContract('contract B');
    const tA = await mkTerm(cA.ID, 2040);
    const tB = await mkTerm(cB.ID, 2040);

    console.log('\nX.5 — a Subscription line must carry the type the engine needs');

    const noType = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
    noType.NewRecord();
    noType.ContractTermID = tA.ID;
    noType.ProductID = productID;
    noType.LineType = 'Subscription';
    noType.Quantity = 1;
    noType.Description = `${TAG} subscription without a type`;
    const noTypeSaved = await noType.Save();
    check('X.5 a Subscription line with no SubscriptionTypeID is REFUSED at write time', noTypeSaved === false, noTypeSaved ? 'it saved' : '');

    if (subTypeID) {
        const withType = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
        withType.NewRecord();
        withType.ContractTermID = tA.ID;
        withType.ProductID = productID;
        withType.LineType = 'Subscription';
        withType.SubscriptionTypeID = subTypeID;
        withType.Quantity = 1;
        withType.Description = `${TAG} subscription with a type`;
        check('X.5a the same line WITH a type is accepted', await withType.Save(), withType.LatestResult?.CompleteMessage ?? '');
    } else {
        console.log('  – X.5a skipped: no orders SubscriptionType seeded to point at');
    }

    // A non-subscription line still needs no type — the rule must not have become "always required".
    const oneTime = await md.GetEntityObject<mjBizAppsContractsContractLineEntity>(E_LINE, user);
    oneTime.NewRecord();
    oneTime.ContractTermID = tA.ID;
    oneTime.ProductID = productID;
    oneTime.LineType = 'OneTime';
    oneTime.Quantity = 1;
    oneTime.ContractedUnitPrice = 500;
    oneTime.Description = `${TAG} one-time`;
    check('X.5b a OneTime line still needs no subscription type', await oneTime.Save(), oneTime.LatestResult?.CompleteMessage ?? '');

    console.log('\nX.6 — Superseded must name its successor');

    // Bring A live first. `Draft -> Superseded` is not a legal MOVE (a draft was never live, so
    // nothing replaced it) — the first version of this test tried it and read the transition
    // refusal as a CHECK refusal. Two invariants, one `false`: worth separating deliberately.
    cA.Status = 'Active';
    if (!(await cA.Save())) { console.error(`SETUP: could not activate A — ${cA.LatestResult?.CompleteMessage}`); process.exit(2); }

    cA.Status = 'Superseded';
    const supersededNoSuccessor = await cA.Save();
    check('X.6 Superseded with no SupersededByContractID is REFUSED', supersededNoSuccessor === false, supersededNoSuccessor ? 'it saved' : '');
    await cA.Load(cA.ID);

    cA.Status = 'Superseded';
    cA.SupersededByContractID = cB.ID;
    check('X.6a Superseded WITH a named successor is accepted', await cA.Save(), cA.LatestResult?.CompleteMessage ?? '');
    await cA.Load(cA.ID);

    console.log('\nX.8 — a renewal chain cannot cross contracts');

    const crossing = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
    crossing.NewRecord();
    crossing.ContractID = cB.ID;
    crossing.RenewalOfTermID = tA.ID; // tA belongs to contract A
    crossing.StartDate = new Date('2041-01-01');
    crossing.EndDate = new Date('2041-12-31');
    crossing.Status = 'Pending';
    crossing.BillingFrequency = 'Annual';
    const crossingSaved = await crossing.Save();
    check('X.8 a term renewing a term on ANOTHER contract is REFUSED', crossingSaved === false, crossingSaved ? 'it saved' : '');
    const crossMsg = crossing.LatestResult?.CompleteMessage ?? '';
    check('X.8b the refusal explains that a chain cannot cross contracts',
        /cannot cross contracts/i.test(crossMsg), `got "${crossMsg}"`);

    const sameContract = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
    sameContract.NewRecord();
    sameContract.ContractID = cB.ID;
    sameContract.RenewalOfTermID = tB.ID; // tB belongs to contract B — correct
    sameContract.StartDate = new Date('2041-01-01');
    sameContract.EndDate = new Date('2041-12-31');
    sameContract.Status = 'Pending';
    sameContract.BillingFrequency = 'Annual';
    sameContract.CommittedAmount = 0;
    check('X.8a a renewal within the SAME contract is accepted', await sameContract.Save(), sameContract.LatestResult?.CompleteMessage ?? '');

    console.log('\nX.15 — the event log is a closed vocabulary AND actually immutable');

    const badType = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
    badType.NewRecord();
    badType.ContractID = cB.ID;
    badType.EventType = 'asdf';
    badType.EventDate = new Date();
    const badTypeSaved = await badType.Save();
    check('X.15 a free-text EventType is REFUSED', badTypeSaved === false, badTypeSaved ? 'it saved' : '');

    const goodEvent = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
    goodEvent.NewRecord();
    goodEvent.ContractID = cB.ID;
    goodEvent.EventType = 'ContractCreated';
    goodEvent.EventDate = new Date();
    goodEvent.Payload = JSON.stringify({ tag: TAG });
    const goodSaved = await goodEvent.Save();
    check('X.15a a vocabulary EventType is accepted', goodSaved, goodEvent.LatestResult?.CompleteMessage ?? '');

    if (goodSaved) {
        goodEvent.Payload = JSON.stringify({ tag: TAG, tampered: true });
        const edited = await goodEvent.Save();
        check('X.15b EDITING a recorded event is REFUSED', edited === false, edited ? 'it saved' : '');
        const editMsg = goodEvent.LatestResult?.CompleteMessage ?? '';
        check('X.15b1 the refusal explains the log is append-only', /append-only/i.test(editMsg), `got "${editMsg}"`);

        const deleted = await goodEvent.Delete();
        check('X.15c DELETING a recorded event is REFUSED', deleted === false, deleted ? 'it deleted' : '');

        // And prove the refusal was real, not just a false return.
        const still = await rv.RunView<{ ID: string; Payload: string }>(
            { EntityName: E_LOG, Fields: ['ID', 'Payload'], ExtraFilter: `ID='${goodEvent.ID}'`, ResultType: 'simple', BypassCache: true },
            user,
        );
        check('X.15d the event is still present and UNCHANGED in the database',
            still.Results?.length === 1 && !still.Results[0].Payload.includes('tampered'),
            JSON.stringify(still.Results?.[0]));
    }

    console.log('\nX.9 / X.12 / X.14 — enforced by the database, checked with raw SQL');
    // These are CHECK/index constraints. Asserting them through raw SQL proves the CONSTRAINT exists
    // rather than that some entity-layer guard happens to agree — a bypass proof, per the doctrine.
    const req = pool.request();
    const constraintExists = async (name: string): Promise<boolean> => {
        const r = await req.query(
            `SELECT COUNT(*) AS n FROM sys.check_constraints WHERE name = '${name}'
             UNION ALL SELECT COUNT(*) FROM sys.indexes WHERE name = '${name}'`,
        );
        return (r.recordset as { n: number }[]).some((row) => row.n > 0);
    };
    check('X.9 UQ_ContractLine_Subscription exists (one subscription, one line)', await constraintExists('UQ_ContractLine_Subscription'));
    check('X.12 CK_ContractBillingEvent_GeneratedHasTimestamp exists', await constraintExists('CK_ContractBillingEvent_GeneratedHasTimestamp'));
    check('X.14 CK_ContractAmendment_ApprovedHasTask exists', await constraintExists('CK_ContractAmendment_ApprovedHasTask'));
    check('X.5c CK_ContractLine_SubscriptionNeedsType exists', await constraintExists('CK_ContractLine_SubscriptionNeedsType'));
    check('X.6b CK_Contract_SupersededHasSuccessor exists', await constraintExists('CK_Contract_SupersededHasSuccessor'));
    check('X.15e CK_ContractEvent_EventType exists', await constraintExists('CK_ContractEvent_EventType'));
    check('X.2a CK_ContractType_MaxEscalationPercent exists', await constraintExists('CK_ContractType_MaxEscalationPercent'));
    check('X.2b CK_ContractType_RenewalNoticeDays exists', await constraintExists('CK_ContractType_RenewalNoticeDays'));
    // Moved from ContractTerm to Contract on 2026-08-05 — asserted at its new home so the move
    // cannot silently lose its bound.
    check('X.2d CK_Contract_RenewalNoticeDays exists (the field\'s new home)', await constraintExists('CK_Contract_RenewalNoticeDays'));
    // Removed the same day, along with ContractTerm.MaxEscalationPercent itself. Asserting the
    // ABSENCE keeps a later re-add from quietly restoring a second, divergent ceiling beside the
    // type's — which is the exact duplication the removal was for.
    check('X.2e CK_ContractTerm_MaxEscalationPercent is GONE (the ceiling lives on the type)',
        !(await constraintExists('CK_ContractTerm_MaxEscalationPercent')));
    check('X.2f CK_ContractTerm_RenewalNoticeDays is GONE (moved up to the contract)',
        !(await constraintExists('CK_ContractTerm_RenewalNoticeDays')));

    // The bound has to actually BITE, not merely exist. This matters more than the usual existence
    // check because the type's ceiling is now the ONLY ceiling — every term's escalation is judged
    // against it — so a negative here would be the single value the whole rule rests on.
    const negativeDefault = await req.query(`
        BEGIN TRY
            UPDATE __mj_BizAppsContracts.ContractType SET DefaultMaxEscalationPercent = -0.05 WHERE Code = 'Standard';
            SELECT 0 AS refused;
        END TRY
        BEGIN CATCH
            SELECT 1 AS refused;
        END CATCH`);
    check('X.2c a NEGATIVE default escalation is actually refused, not just constrained on paper',
        (negativeDefault.recordset as { refused: number }[])[0]?.refused === 1);

    console.log('\nX.7 / X.11 — the pricing moment, and an event matching its schedule');

    // X.7 IS A RAW-SQL BYPASS PROOF, and it has to be. Going through the entity layer cannot reach
    // the bad state at all: `ContractEntityServer.Save()` defaults `PricedAt` when it is null, so
    // setting it to null and saving simply re-fills it — the first version of this test asserted a
    // refusal and got a successful save for exactly that reason.
    //
    // That is the app behaving correctly, and it is also why the CHECK matters: the constraint is a
    // backstop for the paths that DO NOT go through the entity layer — a migration, a fixture, a
    // support script. Proving it therefore means going underneath the entity layer deliberately.
    // Each statement is its own request with the error caught in JAVASCRIPT rather than in a T-SQL
    // TRY/CATCH. A constraint violation inside a multi-statement batch did not behave predictably
    // here — the error escaped the batch — and "did this specific UPDATE fail?" is a question the
    // driver answers unambiguously one statement at a time.
    const attempt = async (sql: string): Promise<boolean> => {
        try {
            await pool.request().query(sql);
            return false; // it succeeded, i.e. NOT refused
        } catch {
            return true; // refused
        }
    };

    const probeDesc = `${TAG}: pricing moment`;
    await pool.request().query(`
        INSERT INTO __mj_BizAppsContracts.Contract
            (ContractNumber, ContractTypeID, CompanyID, CustomerOrganizationID, Status, Description, PricedAt)
        VALUES (CONCAT('${TAG}-', LEFT(CAST(NEWID() AS NVARCHAR(36)), 8)), '${typeID}', '${companyID}', '${orgID}',
                'Active', '${probeDesc}', GETDATE());`);

    check('X.7a the DATABASE refuses a null PricedAt on an Active contract',
        await attempt(`UPDATE __mj_BizAppsContracts.Contract SET PricedAt = NULL WHERE Description = '${probeDesc}'`));

    // The path the NARROW constraint missed entirely: leave Active, then null it.
    await pool.request().query(`UPDATE __mj_BizAppsContracts.Contract SET Status = 'Terminated' WHERE Description = '${probeDesc}'`);
    check('X.7b and on a TERMINATED one — the path the narrow constraint missed',
        await attempt(`UPDATE __mj_BizAppsContracts.Contract SET PricedAt = NULL WHERE Description = '${probeDesc}'`));

    // Draft stays exempt, because a contract being typed has not been priced yet.
    await pool.request().query(`UPDATE __mj_BizAppsContracts.Contract SET Status = 'Draft' WHERE Description = '${probeDesc}'`);
    check('X.7c a DRAFT may still have no pricing moment — the exemption is deliberate',
        (await attempt(`UPDATE __mj_BizAppsContracts.Contract SET PricedAt = NULL WHERE Description = '${probeDesc}'`)) === false);

    await pool.request().query(`DELETE FROM __mj_BizAppsContracts.Contract WHERE Description = '${probeDesc}'`);

    // X.11: an event may not name a schedule belonging to another term. Built with two live terms on
    // contract B so both a matching and a crossed pairing are available.
    const evTermA = await mkTerm(cB.ID, 2050);
    const evTermB = await mkTerm(cB.ID, 2051);
    const mkSchedule = async (termID: string) => {
        const sc = await md.GetEntityObject<mjBizAppsContractsContractBillingScheduleEntity>(E_SCHEDULE_ENT, user);
        sc.NewRecord();
        sc.ContractTermID = termID;
        sc.ScheduleType = 'Cadence';
        sc.Frequency = 'Annual';
        sc.AnchorDate = new Date('2050-01-01');
        sc.IsActive = true;
        await sc.Save();
        return sc;
    };
    const schedA = await mkSchedule(evTermA.ID);

    const matched = await md.GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVT, user);
    matched.NewRecord();
    matched.ContractBillingScheduleID = schedA.ID;
    matched.ContractTermID = evTermA.ID;
    matched.ScheduledDate = new Date('2050-01-01');
    matched.Status = 'Scheduled';
    check('X.11a an event whose schedule belongs to its OWN term saves', await matched.Save(), matched.LatestResult?.CompleteMessage ?? '');

    const crossed = await md.GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVT, user);
    crossed.NewRecord();
    crossed.ContractBillingScheduleID = schedA.ID; // term A's schedule…
    crossed.ContractTermID = evTermB.ID;           // …on term B's event
    crossed.ScheduledDate = new Date('2051-01-01');
    crossed.Status = 'Scheduled';
    const crossedSaved = await crossed.Save();
    check('X.11b an event naming ANOTHER term\'s schedule is REFUSED', crossedSaved === false, crossedSaved ? 'it saved' : '');
    check('X.11c and the refusal explains why the crossing matters',
        /different term/i.test(crossed.LatestResult?.CompleteMessage ?? ''), crossed.LatestResult?.CompleteMessage ?? '');

    console.log('\nENGINE — contract-type defaults on a NEW contract');

    // The renewal-notice period MOVED from ContractTerm to Contract on 2026-08-05, and the defaulting
    // moved with it. Written notice before a renewal price change is a provision of the AGREEMENT,
    // not of a period, so it is negotiated once. The Standard type prescribes 30 days; a contract
    // created without one should get that, and a contract that STATES one must keep it, because that
    // is what was negotiated. Exact values, from the seeded metadata.
    //
    // The escalation ceiling made the opposite move — off the term and onto the TYPE, with no
    // per-contract copy at all — so it is no longer defaulted anywhere and is tested where it is now
    // enforced, in invariants.ts section D.
    const inherit = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    inherit.NewRecord();
    inherit.ContractTypeID = typeID!;
    inherit.CompanyID = companyID!;
    inherit.CustomerOrganizationID = orgID!;
    inherit.Status = 'Draft';
    inherit.Description = `${TAG}: inherits its notice period`;
    const inheritSaved = await inherit.Save();
    check('E.1 a new contract inherits its type\'s renewal-notice period', inheritSaved && inherit.RenewalNoticeDays === 30,
        `saved=${inheritSaved} notice=${inherit.RenewalNoticeDays} · ${inherit.LatestResult?.CompleteMessage ?? ''}`);

    const explicit = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    explicit.NewRecord();
    explicit.ContractTypeID = typeID!;
    explicit.CompanyID = companyID!;
    explicit.CustomerOrganizationID = orgID!;
    explicit.Status = 'Draft';
    explicit.Description = `${TAG}: states its own notice period`;
    explicit.RenewalNoticeDays = 120;
    const explicitSaved = await explicit.Save();
    check('E.2 a contract that STATES its own notice period keeps it — the default never overwrites',
        explicitSaved && explicit.RenewalNoticeDays === 120, `notice=${explicit.RenewalNoticeDays}`);

    // The negative case, and the one that would be WRONG: an existing contract must never acquire a
    // notice period it was not negotiated with. Retrofitting one would change an agreement.
    explicit.RenewalNoticeDays = null;
    const clearedSaved = await explicit.Save();
    await explicit.Load(explicit.ID);
    check('E.3 clearing an EXISTING contract\'s notice period leaves it cleared — no retrofit on update',
        clearedSaved && (explicit.RenewalNoticeDays === null || explicit.RenewalNoticeDays === undefined),
        `got ${explicit.RenewalNoticeDays}`);

    console.log('\nTeardown');
    // Raw SQL, deepest-first: the entity layer now REFUSES to delete events, which is the point of
    // X.15 — so the harness cannot use it to clean up after itself.
    const cleanup = pool.request();
    await cleanup.query(`
        DECLARE @ids TABLE (ID UNIQUEIDENTIFIER);
        INSERT INTO @ids SELECT ID FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${TAG}%';
        DECLARE @terms TABLE (ID UNIQUEIDENTIFIER);
        INSERT INTO @terms SELECT t.ID FROM __mj_BizAppsContracts.ContractTerm t JOIN @ids i ON i.ID = t.ContractID;
        DELETE be FROM __mj_BizAppsContracts.ContractBillingEvent be JOIN @terms t ON t.ID = be.ContractTermID;
        DELETE bs FROM __mj_BizAppsContracts.ContractBillingSchedule bs JOIN @terms t ON t.ID = bs.ContractTermID;
        DELETE l FROM __mj_BizAppsContracts.ContractLine l JOIN @terms t ON t.ID = l.ContractTermID;
        DELETE e FROM __mj_BizAppsContracts.ContractEvent e JOIN @ids i ON i.ID = e.ContractID;
        -- Status AND the successor must be cleared together: CK_Contract_SupersededHasSuccessor
        -- forbids a Superseded contract without one, so nulling the FK alone is refused. The
        -- constraint even constrains the cleanup, which is a good sign it is real.
        UPDATE __mj_BizAppsContracts.Contract SET SupersededByContractID = NULL, Status = 'Draft' WHERE ID IN (SELECT ID FROM @ids);
        DELETE ct FROM __mj_BizAppsContracts.ContractTerm ct JOIN @terms t ON t.ID = ct.ID;
        DELETE c FROM __mj_BizAppsContracts.Contract c JOIN @ids i ON i.ID = c.ID;`);
    const leftover = await pool.request().query(
        `SELECT COUNT(*) AS n FROM __mj_BizAppsContracts.Contract WHERE Description LIKE '${TAG}%'`);
    check('teardown left nothing behind', (leftover.recordset as { n: number }[])[0].n === 0);

    console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
    if (failed) failures.forEach((f) => console.log(`  · ${f}`));
    void pool.close().catch(() => undefined);
    process.exit(failed === 0 ? 0 : 1);
}

void main().catch((e) => {
    console.error('HARNESS ERROR:', e instanceof Error ? (e.stack ?? e.message) : String(e));
    process.exit(2);
});
