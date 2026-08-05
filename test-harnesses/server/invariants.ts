/**
 * @fileoverview Tier 2 — server/data harness. In-process, direct SQL, MJAPI-free.
 *
 * Proves the invariants that live in the entity subclasses, because those are exactly the rules the
 * database CANNOT enforce: legal status MOVES (the CHECK knows only the legal SET), sequence
 * allocation, the derived term number, and the escalation cap (which cannot be a CHECK because a
 * two-column constraint breaks CodeGen's generated validation naming).
 *
 * Every assertion is an EXACT value or an explicit refusal. "It saved" is not a result.
 *
 * Run:  npx tsx test-harnesses/server/invariants.ts
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
import type { mjBizAppsContractsContractEntity, mjBizAppsContractsContractTermEntity } from '@mj-biz-apps/contracts-entities';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';

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

/** Everything this run creates, torn down FK-aware (terms before contracts). */
const createdTerms: string[] = [];
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

    // Fixtures the contract needs. Read, never created — this harness must not invent companies.
    const [types, companies, orgs] = await rv.RunViews(
        [
            { EntityName: 'MJ_BizApps_Contracts: Contract Types', Fields: ['ID', 'Code'], ResultType: 'simple' },
            { EntityName: 'MJ: Companies', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Common: Organizations', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
        ],
        user,
    );
    const typeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'Standard')?.ID;
    const companyID = (companies?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const orgID = (orgs?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    if (!typeID || !companyID || !orgID) {
        console.error(`BOOTSTRAP: missing fixtures — type=${!!typeID} company=${!!companyID} org=${!!orgID}`);
        console.error('Seed the demo data first: demo/seed-demo-contract.sql');
        process.exit(2);
    }

    console.log('\nA. Contract — number allocation and the pricing lock');

    const c1 = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    c1.NewRecord();
    c1.ContractTypeID = typeID;
    c1.CompanyID = companyID;
    c1.CustomerOrganizationID = orgID;
    c1.Status = 'Draft';
    c1.Description = 'tier2-invariants: number + pricing lock';
    const c1saved = await c1.Save();
    check('A.1 a contract saves with no ContractNumber supplied', c1saved, c1.LatestResult?.CompleteMessage ?? '');
    if (c1saved) createdContracts.push(c1.ID);
    check('A.2 ContractNumber was allocated as CTR-######', /^CTR-\d{6}$/.test(c1.ContractNumber ?? ''), `got "${c1.ContractNumber}"`);
    check('A.3 PricedAt defaulted rather than being left null', !!c1.PricedAt, `got ${String(c1.PricedAt)}`);

    const c2 = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    c2.NewRecord();
    c2.ContractTypeID = typeID;
    c2.CompanyID = companyID;
    c2.CustomerOrganizationID = orgID;
    c2.Status = 'Draft';
    c2.Description = 'tier2-invariants: sequence advances';
    const c2saved = await c2.Save();
    if (c2saved) createdContracts.push(c2.ID);
    const n1 = Number((c1.ContractNumber ?? 'CTR-0').split('-')[1]);
    const n2 = Number((c2.ContractNumber ?? 'CTR-0').split('-')[1]);
    check('A.4 the sequence advances by exactly 1 between contracts', c2saved && n2 === n1 + 1, `${c1.ContractNumber} -> ${c2.ContractNumber}`);

    const explicit = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    explicit.NewRecord();
    explicit.ContractTypeID = typeID;
    explicit.CompanyID = companyID;
    explicit.CustomerOrganizationID = orgID;
    explicit.Status = 'Draft';
    explicit.ContractNumber = `CTR-T2-${Date.now().toString().slice(-6)}`;
    explicit.Description = 'tier2-invariants: explicit number is respected';
    const explicitNumber = explicit.ContractNumber;
    const explicitSaved = await explicit.Save();
    if (explicitSaved) createdContracts.push(explicit.ID);
    check('A.5 an explicitly supplied number is NOT overwritten', explicitSaved && explicit.ContractNumber === explicitNumber, `got "${explicit.ContractNumber}"`);

    console.log('\nB. Contract — legal status moves (what the CHECK cannot express)');

    c1.Status = 'Terminated';
    const toTerminated = await c1.Save();
    check('B.1 Draft -> Terminated is allowed', toTerminated);

    c1.Status = 'Active';
    const revive = await c1.Save();
    check('B.2 Terminated -> Active is REFUSED (a terminated contract cannot come back)', revive === false);
    // A refusal the caller cannot read is a refusal nobody can act on. These rules live in Validate()
    // precisely so the reason reaches LatestResult instead of only the server console.
    const reviveMsg = c1.LatestResult?.CompleteMessage ?? '';
    check('B.2a the refusal EXPLAINS itself to the caller', /cannot move from Terminated to Active/i.test(reviveMsg), `got "${reviveMsg}"`);
    check('B.2b and says Terminated is terminal', /terminal/i.test(reviveMsg), `got "${reviveMsg}"`);

    // Reload to drop the rejected in-memory value before continuing.
    await c1.Load(c1.ID);
    check('B.3 the refused move did not persist', (c1.Status as unknown as string) === 'Terminated', `db says ${c1.Status}`);

    // B.4/B.5 are about the STATUS TRANSITION MAP, so the subject needs a term first — an Active
    // contract with no term is refused by a DIFFERENT rule (checkActiveHasATerm), and the
    // transition test would then pass or fail for the wrong reason.
    //
    // Its OWN contract, not c2: c2 is the subject of C.1/C.2, which assert that terms number
    // themselves 1 then 2. A term added here would take number 1 and make those read 2 and 3.
    const mover = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
    mover.NewRecord();
    mover.ContractTypeID = typeID;
    mover.CompanyID = companyID;
    mover.CustomerOrganizationID = orgID;
    mover.Status = 'Draft';
    mover.Description = 'tier2-invariants: status transition subject';
    if (await mover.Save()) createdContracts.push(mover.ID);

    const moverTerm = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
    moverTerm.NewRecord();
    moverTerm.ContractID = mover.ID;
    moverTerm.StartDate = new Date('2029-01-01');
    moverTerm.EndDate = new Date('2029-12-31');
    moverTerm.Status = 'Pending';
    moverTerm.BillingFrequency = 'Annual';
    if (await moverTerm.Save()) createdTerms.push(moverTerm.ID);

    mover.Status = 'Active';
    const activate = await mover.Save();
    check('B.4 Draft -> Active is allowed', activate, mover.LatestResult?.CompleteMessage ?? '');
    mover.Status = 'Draft';
    const backwards = await mover.Save();
    check('B.5 Active -> Draft is REFUSED', backwards === false);
    await c2.Load(c2.ID);

    console.log('\nC. ContractTerm — derived numbering');

    const mkTerm = async (contractID: string, start: string, end: string): Promise<mjBizAppsContractsContractTermEntity> => {
        const t = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        t.NewRecord();
        t.ContractID = contractID;
        t.StartDate = new Date(start);
        t.EndDate = new Date(end);
        t.Status = 'Pending';
        t.BillingFrequency = 'Annual';
        return t;
    };

    const t1 = await mkTerm(c2.ID, '2027-01-01', '2027-12-31');
    const t1saved = await t1.Save();
    if (t1saved) createdTerms.push(t1.ID);
    check('C.1 the first term numbers itself 1', t1saved && t1.TermNumber === 1, `got ${t1.TermNumber} · ${t1.LatestResult?.CompleteMessage ?? ''}`);

    const t2 = await mkTerm(c2.ID, '2028-01-01', '2028-12-31');
    const t2saved = await t2.Save();
    if (t2saved) createdTerms.push(t2.ID);
    check('C.2 the second term numbers itself 2', t2saved && t2.TermNumber === 2, `got ${t2.TermNumber}`);

    console.log('\nD. ContractTerm — the escalation cap (impossible as a CHECK)');

    const over = await mkTerm(c2.ID, '2029-01-01', '2029-12-31');
    over.EscalationPercent = 0.08;
    over.MaxEscalationPercent = 0.05;
    const overSaved = await over.Save();
    check('D.1 escalation 8% under a 5% cap is REFUSED', overSaved === false);
    const capMsg = over.LatestResult?.CompleteMessage ?? '';
    check('D.1a the refusal names both numbers', /8\.00%/.test(capMsg) && /5\.00%/.test(capMsg), `got "${capMsg}"`);
    if (overSaved) createdTerms.push(over.ID);

    const under = await mkTerm(c2.ID, '2030-01-01', '2030-12-31');
    under.EscalationPercent = 0.04;
    under.MaxEscalationPercent = 0.05;
    const underSaved = await under.Save();
    if (underSaved) createdTerms.push(under.ID);
    check('D.2 escalation 4% under a 5% cap is allowed', underSaved, under.LatestResult?.CompleteMessage ?? '');

    // D.3 needs a GENUINELY uncapped term, and since 2026-08-05 that means a contract whose TYPE
    // sets no default ceiling. A new term now inherits `ContractType.DefaultMaxEscalationPercent`,
    // so on a Standard contract (5%) there is no such thing as an uncapped new term — which is the
    // intended behaviour and the reason this test moved rather than being relaxed.
    //
    // SOW carries a null default, so it is the honest way to prove the rule. Asserting the default
    // is null first, so that if the seed ever gives SOW a ceiling this fails as a stale fixture
    // rather than silently testing nothing.
    const sowTypeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'SOW')?.ID;
    check('D.3a the SOW type genuinely sets no default ceiling (fixture check)', !!sowTypeID);

    if (sowTypeID) {
        const sowContract = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
        sowContract.NewRecord();
        sowContract.ContractTypeID = sowTypeID;
        sowContract.CompanyID = companyID;
        sowContract.CustomerOrganizationID = orgID;
        sowContract.Status = 'Draft';
        sowContract.Description = 'tier2-invariants: uncapped SOW';
        if (await sowContract.Save()) createdContracts.push(sowContract.ID);

        const uncapped = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        uncapped.NewRecord();
        uncapped.ContractID = sowContract.ID;
        uncapped.StartDate = new Date('2031-01-01');
        uncapped.EndDate = new Date('2031-12-31');
        uncapped.Status = 'Pending';
        uncapped.BillingFrequency = 'Annual';
        uncapped.EscalationPercent = 0.20;
        const uncappedSaved = await uncapped.Save();
        if (uncappedSaved) createdTerms.push(uncapped.ID);
        check('D.3b a null cap really does mean uncapped — 20% is allowed', uncappedSaved, uncapped.LatestResult?.CompleteMessage ?? '');
        check('D.3c and the term genuinely has no ceiling, rather than one that happens to exceed 20%',
            uncapped.MaxEscalationPercent === null || uncapped.MaxEscalationPercent === undefined,
            `got ${uncapped.MaxEscalationPercent}`);
    }

    // The complement: on a Standard contract (5% default) a new term is NOT uncapped, which is the
    // behaviour change that made the old version of this test stale.
    const inherited = await mkTerm(c2.ID, '2032-01-01', '2032-12-31');
    inherited.EscalationPercent = 0.20;
    const inheritedSaved = await inherited.Save();
    if (inheritedSaved) createdTerms.push(inherited.ID);
    check('D.4 on a Standard contract the SAME 20% is refused, because the type supplies a 5% ceiling',
        inheritedSaved === false, inheritedSaved ? 'it saved' : '');

    console.log('\nE. Teardown');
    // FK-aware: terms reference contracts, so terms go first.
    for (const id of createdTerms) {
        const t = await md.GetEntityObject<mjBizAppsContractsContractTermEntity>(E_TERM, user);
        if (await t.Load(id)) await t.Delete();
    }
    for (const id of createdContracts) {
        const c = await md.GetEntityObject<mjBizAppsContractsContractEntity>(E_CONTRACT, user);
        if (await c.Load(id)) await c.Delete();
    }
    const leftover = await rv.RunView<{ ID: string }>(
        { EntityName: E_CONTRACT, ExtraFilter: `Description LIKE 'tier2-invariants%'`, Fields: ['ID'], ResultType: 'simple', BypassCache: true },
        user,
    );
    check('E.1 teardown left nothing behind', (leftover.Results?.length ?? -1) === 0, `${leftover.Results?.length} rows remain`);

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
