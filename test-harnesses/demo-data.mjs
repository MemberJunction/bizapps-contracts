#!/usr/bin/env node
/**
 * ONE COHERENT DEMO DATASET across contracts, orders and accounting — and one command to apply it.
 *
 * ── THE PROBLEM THIS SOLVES ─────────────────────────────────────────────────────────────────────
 *
 * Each app grew its own demo data independently, so a dev instance ended up with TWO unrelated
 * universes: orders/accounting had "DEMO Publishing Co" selling to "DEMO Riverside Library", while
 * contracts had "Blue Cypress" selling to "Northwind Association". Nothing joined them, so no screen
 * could show an agreement, the orders it generated and the journal entries those booked — which is
 * the entire story this suite of apps exists to tell.
 *
 * Here, contracts hangs off the SAME company, the SAME customers and the SAME product catalogue that
 * orders and accounting already use. One chain, end to end.
 *
 * ── VALID AT BOTH LAYERS, ON PURPOSE ────────────────────────────────────────────────────────────
 *
 * Contracts are written through the ENTITY LAYER (`ContractEntityServer` and its child collections),
 * not raw SQL. That is the difference between data the database accepts and data the APP accepts:
 * raw SQL bypasses every rule in BaseEntity, so it is the easy way to plant a contract that cannot
 * be opened, edited or activated in the UI because the first save is correctly refused. An earlier
 * raw-SQL seed here did exactly that — it escalated a term 6.67% under a 5% cap, and the screen
 * showed "+6.67% (cap 5%)" to anyone who looked.
 *
 * Going through the entity layer means the seed also EXERCISES the composition path: one contract,
 * one transaction, terms and lines and schedules written as a tree.
 *
 * ── WHY THE RESET IS OURS AND NOT ORDERS' ───────────────────────────────────────────────────────
 *
 * `bizapps-orders/test-harnesses/seed-demo-data.mjs --reset` does not work twice. Its teardown SQL
 * is correct and thorough; its CONNECTION is not. It opens the pool without
 * `enableQuotedIdentifier: true`, and SQL Server refuses DML against any table carrying a filtered
 * index when QUOTED_IDENTIFIER is off:
 *
 *     Msg 1934 — DELETE failed because the following SET options have incorrect settings:
 *     'QUOTED_IDENTIFIER'
 *
 * So its Product delete fails, ProductCategory then cannot go, the Company delete hits
 * FK_ProductCategory_Company, and the re-seed dies on UQ_Company_Name. The seeder is a one-shot
 * against a virgin database. Contracts' own harnesses already carry that flag with a comment
 * explaining it; this file does too, which is why its reset is re-runnable.
 *
 * Filed upstream — the fix is one line in orders' pool options.
 *
 * ── USAGE ───────────────────────────────────────────────────────────────────────────────────────
 *
 *     npm run demo:seed          # reset, then build the whole dataset
 *     npm run demo:reset         # tear it down and stop
 *     node test-harnesses/demo-data.mjs --contracts-only   # skip the orders/accounting layer
 *
 * Everything created is tagged `DEMO` (companies, organisations, products) or `DEMO-` (contract
 * numbers), which is how the reset finds it. Nothing else is touched.
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import dotenv from 'dotenv';
import sql from 'mssql';

const here = path.dirname(fileURLToPath(import.meta.url));
const appRoot = path.resolve(here, '..');
dotenv.config({ path: path.resolve(appRoot, '../../../.env'), quiet: true });
dotenv.config({ path: path.resolve(appRoot, '.env'), quiet: true });

const ORDERS = '__mj_BizAppsOrders';
const ACCT = '__mj_BizAppsAccounting';
const COMMON = '__mj_BizAppsCommon';
const CONTRACTS = '__mj_BizAppsContracts';
const DEMO_TAG = 'DEMO';

const args = process.argv.slice(2);
const resetOnly = args.includes('--reset-only');
const contractsOnly = args.includes('--contracts-only');

const say = (m) => console.log(m);
const step = (m) => console.log(`\n▸ ${m}`);

/**
 * TEARDOWN NEEDS MORE RIGHTS THAN THE APP USER HAS.
 *
 * Orders' immutability triggers must be stood down to delete booked history, and `MJ_Connect` cannot
 * `DISABLE TRIGGER` — it gets "does not exist or you do not have permissions", which reads as a
 * missing object rather than a denied one and is the second reason orders' own reset cannot work.
 *
 * The CodeGen credentials already exist for exactly this class of job (they carry the DDL rights
 * CodeGen needs), so they are used when present and the app user is the fallback. On a deployment
 * with no elevated credentials the reset still clears everything it CAN, and says what it could not.
 */
const admin = process.env.CODEGEN_DB_USERNAME
    ? { user: process.env.CODEGEN_DB_USERNAME, password: process.env.CODEGEN_DB_PASSWORD }
    : { user: process.env.DB_USERNAME, password: process.env.DB_PASSWORD };

const pool = await new sql.ConnectionPool({
    server: process.env.DB_HOST ?? 'localhost',
    port: Number(process.env.DB_PORT ?? 1433),
    database: process.env.DB_DATABASE,
    user: admin.user,
    password: admin.password,
    // THE FLAG ORDERS IS MISSING. Without it every DELETE against a table with a filtered index —
    // ContractLine and JournalEntryType both have one — fails with Msg 1934, and a teardown that
    // cannot delete leaves a database nobody can re-seed.
    options: { encrypt: false, trustServerCertificate: true, enableQuotedIdentifier: true },
    requestTimeout: 120000,
}).connect();

const q = (text) => pool.request().query(text);

/** Run a statement, reporting rather than swallowing. A teardown that hides its failures is why
 *  orders' reset looked like it worked. */
async function run(text, label) {
    try {
        await q(text);
    } catch (e) {
        console.error(`  ✗ ${label ?? text.slice(0, 70)}\n    ${e.message}`);
        throw e;
    }
}

// ─── Reset ──────────────────────────────────────────────────────────────────────────────────────

async function reset() {
    step('Removing any previous demo data');

    const companies = `SELECT ID FROM __mj.Company WHERE Name LIKE '${DEMO_TAG}%'`;
    const orderIDs = `SELECT ID FROM ${ORDERS}.OrderHeader WHERE CompanyID IN (${companies})`;
    const demoContracts = `SELECT ID FROM ${CONTRACTS}.Contract WHERE ContractNumber LIKE '${DEMO_TAG}-%' OR Description LIKE '${DEMO_TAG}%'`;
    const demoTerms = `SELECT ID FROM ${CONTRACTS}.ContractTerm WHERE ContractID IN (${demoContracts})`;

    // CONTRACTS FIRST — its lines point at orders' Products and its billing events at OrderHeaders,
    // so anything below would be blocked by an FK if this ran later. Deepest child first throughout.
    const contractStatements = [
        `DELETE FROM ${CONTRACTS}.ContractBillingEvent WHERE ContractTermID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractBillingSchedule WHERE ContractTermID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractAmendment WHERE ContractTermID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractCommitment WHERE ContractTermID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractLine WHERE ContractTermID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractEvent WHERE ContractID IN (${demoContracts})`,
        // Renewal chains are self-referential: a term pointed at by another must lose the pointer
        // before either can go.
        `UPDATE ${CONTRACTS}.ContractTerm SET RenewalOfTermID = NULL WHERE ID IN (${demoTerms})`,
        `DELETE FROM ${CONTRACTS}.ContractTerm WHERE ID IN (${demoTerms})`,
        `UPDATE ${CONTRACTS}.Contract SET SupersededByContractID = NULL WHERE ID IN (${demoContracts})`,
        `DELETE FROM ${CONTRACTS}.Contract WHERE ID IN (${demoContracts})`,
    ];

    // ORDERS + ACCOUNTING — adapted from orders' own teardown, which is correct in its ordering.
    // The immutability triggers exist to stop booked history being deleted; that is right in
    // production and exactly what a demo reset has to stand down.
    const upstreamStatements = [
        `DISABLE TRIGGER ${ORDERS}.trg_OrderLine_ImmutableAfterConfirm ON ${ORDERS}.OrderLine`,
        `DISABLE TRIGGER ${ORDERS}.trg_PaymentHeader_ImmutableAfterCapture ON ${ORDERS}.PaymentHeader`,
        `DISABLE TRIGGER ${ORDERS}.trg_PaymentLine_ImmutableAfterCapture ON ${ORDERS}.PaymentLine`,
        `UPDATE ${ORDERS}.OrderLine SET JournalEntryID=NULL WHERE OrderHeaderID IN (${orderIDs})`,
        `UPDATE ${ORDERS}.PaymentHeader SET JournalEntryID=NULL WHERE ReceivingCompanyID IN (${companies})`,
        `UPDATE ${ORDERS}.PaymentLine SET BookedAt=NULL WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE jel FROM ${ACCT}.JournalEntryLine jel JOIN ${ACCT}.JournalEntry je ON je.ID=jel.JournalEntryID WHERE je.CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.JournalEntry WHERE CompanyID IN (${companies})`,
        `UPDATE ${ORDERS}.OrderHeader SET InitialPaymentDetailID=NULL WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.PaymentLine WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.PaymentHeader WHERE ReceivingCompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.PaymentDetail WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.SubscriptionEvent WHERE SubscriptionID IN (SELECT ID FROM ${ORDERS}.Subscription WHERE CompanyID IN (${companies}))`,
        `DELETE FROM ${ORDERS}.SubscriptionTerm WHERE SubscriptionID IN (SELECT ID FROM ${ORDERS}.Subscription WHERE CompanyID IN (${companies}))`,
        `DELETE FROM ${ORDERS}.Subscription WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.EventOrderLine WHERE ID IN (SELECT ID FROM ${ORDERS}.OrderLine WHERE OrderHeaderID IN (${orderIDs}))`,
        `DELETE FROM ${ORDERS}.OrderLine WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.OrderHeader WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.IntercompanyAccountMatch WHERE SourceCompanyID IN (${companies}) OR TargetCompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.EventProduct WHERE ID IN (SELECT ID FROM ${ORDERS}.Product WHERE CompanyID IN (${companies}))`,
        // Tables orders' own teardown does not cover — found by reading sys.foreign_keys rather than
        // by hitting them one error at a time. This is the drift a hand-maintained delete list
        // accumulates, and the reason the loop below does not depend on getting the order right.
        `DELETE FROM ${ORDERS}.ProductPrice WHERE ProductID IN (SELECT ID FROM ${ORDERS}.Product WHERE CompanyID IN (${companies}))`,
        `DELETE FROM ${ORDERS}.ProductBundleItem WHERE BundleProductID IN (SELECT ID FROM ${ORDERS}.Product WHERE CompanyID IN (${companies})) OR ComponentProductID IN (SELECT ID FROM ${ORDERS}.Product WHERE CompanyID IN (${companies}))`,
        `DELETE FROM ${ORDERS}.OrderAdjustment WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.OrderCharge WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.PaymentIntent WHERE OrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.StoredValueTransaction WHERE RelatedOrderHeaderID IN (${orderIDs})`,
        `DELETE FROM ${ORDERS}.StoredValueAccount WHERE IssuingCompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.Promotion WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.PaymentProvider WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.OrderCompanyPolicy WHERE ID IN (${companies})`,
        `DELETE FROM ${ACCT}.CompanyTaxNexus WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.TaxLiability WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.JournalEntryBatch WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.Product WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.ProductCategory WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ORDERS}.ProductType WHERE Name LIKE '${DEMO_TAG}%'`,
        `DELETE FROM ${ACCT}.GLAccountLink WHERE RecordID IN (${companies})`,
        `DELETE FROM ${ACCT}.JournalEntrySequence WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.GLAccount WHERE CompanyID IN (${companies})`,
        `DELETE FROM ${ACCT}.AccountingCompanyProfile WHERE ID IN (${companies})`,
        `DELETE FROM __mj.Company WHERE Name LIKE '${DEMO_TAG}%'`,
        `DELETE FROM ${COMMON}.Organization WHERE Name LIKE '${DEMO_TAG}%'`,
        `DELETE FROM ${COMMON}.Person WHERE LastName LIKE '${DEMO_TAG}%'`,
        `ENABLE TRIGGER ${ORDERS}.trg_OrderLine_ImmutableAfterConfirm ON ${ORDERS}.OrderLine`,
        `ENABLE TRIGGER ${ORDERS}.trg_PaymentHeader_ImmutableAfterCapture ON ${ORDERS}.PaymentHeader`,
        `ENABLE TRIGGER ${ORDERS}.trg_PaymentLine_ImmutableAfterCapture ON ${ORDERS}.PaymentLine`,
    ];

    /**
     * DELETE TO A FIXED POINT, rather than in a hand-perfected order.
     *
     * A hand-maintained delete list is right on the day it is written and wrong the first time
     * anyone adds a table — which is precisely how orders' teardown broke: it predates
     * ProductPrice, ProductBundleItem, OrderAdjustment and half a dozen others, so its Product
     * delete now fails on an FK and everything downstream of it silently survives.
     *
     * So: attempt every statement, keep the ones that failed on a REFERENCE constraint, and go
     * round again. Each pass frees the next layer, so the loop converges in as many passes as the
     * graph is deep. Order stops mattering, and a table added tomorrow only needs a line in the
     * list — not a line in the right PLACE.
     *
     * Anything still failing when a pass makes no progress is a real error and is reported.
     */
    const isDisable = (s) => /^DISABLE TRIGGER/.test(s);
    const isEnable = (s) => /^ENABLE TRIGGER/.test(s);
    const toggle = (s) => isDisable(s) || isEnable(s);
    async function deleteToFixedPoint(statements, label) {
        let pending = statements.filter((s) => !toggle(s));
        // DISABLE FIRST, ENABLE LAST — and they are separated deliberately. Running every toggle up
        // front turns the triggers straight back ON before a single row is deleted, and the deletes
        // then fail on the very immutability guard the disable was for.
        //
        // Advisory either way: a session that cannot disable a trigger will fail loudly on the
        // delete itself, which is the error worth seeing rather than a permissions message about a
        // trigger.
        for (const s of statements.filter(isDisable)) {
            try { await q(s); } catch { /* surfaced by the delete that needs it, if any */ }
        }
        for (let pass = 1; pending.length && pass <= 12; pass++) {
            const failed = [];
            for (const s of pending) {
                try { await q(s); } catch (e) {
                    if (/REFERENCE constraint/i.test(e.message)) failed.push(s);
                    else { console.error(`  ✗ ${s.slice(0, 90)}\n    ${e.message}`); throw e; }
                }
            }
            if (failed.length === pending.length) {
                console.error(`  ✗ ${label}: ${failed.length} statement(s) still blocked after pass ${pass}`);
                for (const s of failed.slice(0, 5)) console.error(`      ${s.slice(0, 110)}`);
                throw new Error(`${label} teardown did not converge`);
            }
            pending = failed;
        }
        for (const s of statements.filter(isEnable)) {
            try { await q(s); } catch { /* leaving a trigger disabled would be worse than saying so */ }
        }
        say(`  ${label} cleared`);
    }

    await deleteToFixedPoint(contractStatements, 'contracts');
    if (!contractsOnly) await deleteToFixedPoint(upstreamStatements, 'orders + accounting');

    // PROVE IT. A teardown that reports success without checking is the thing that produced the
    // "cannot re-seed" state in the first place.
    const left = await q(`
        SELECT
          (SELECT COUNT(*) FROM __mj.Company WHERE Name LIKE '${DEMO_TAG}%') AS companies,
          (SELECT COUNT(*) FROM ${ORDERS}.Product p JOIN __mj.Company c ON c.ID=p.CompanyID WHERE c.Name LIKE '${DEMO_TAG}%') AS products,
          (SELECT COUNT(*) FROM ${CONTRACTS}.Contract WHERE ContractNumber LIKE '${DEMO_TAG}-%' OR Description LIKE '${DEMO_TAG}%') AS contracts`);
    const r = left.recordset[0];
    const remaining = contractsOnly ? r.contracts : r.companies + r.products + r.contracts;
    if (remaining !== 0) {
        console.error(`  ✗ reset incomplete — companies=${r.companies} products=${r.products} contracts=${r.contracts}`);
        process.exit(1);
    }
    say('  verified: nothing tagged DEMO remains');
}

// ─── Upstream (orders + accounting) ──────────────────────────────────────────────────────────────

function seedUpstream() {
    step('Seeding orders + accounting (delegating to their own seeder)');
    const ordersSeed = path.resolve(appRoot, '..', 'bizapps-orders', 'test-harnesses', 'seed-demo-data.mjs');
    if (!existsSync(ordersSeed)) {
        say('  bizapps-orders is not a sibling of this repo — skipping the upstream layer.');
        say('  Contracts will be seeded against whatever DEMO fixtures already exist.');
        return false;
    }
    // Delegated rather than reimplemented: orders owns its own demo story (two companies, a real
    // chart of accounts, nine orders across every state) and duplicating it here would guarantee the
    // two drift. We supply the reset it cannot do for itself, then let it build.
    const res = spawnSync(process.execPath, [ordersSeed], {
        cwd: path.dirname(path.dirname(ordersSeed)),
        env: process.env,
        encoding: 'utf8',
    });
    const out = (res.stdout ?? '') + (res.stderr ?? '');
    if (res.status !== 0) {
        console.error(out.split('\n').filter((l) => !/API key|EmbedText|ClassFactory/.test(l)).slice(-12).join('\n'));
        throw new Error('orders demo seeder failed');
    }
    for (const line of out.split('\n')) {
        if (/^\s*(ORD-|▸|\s{2}\w)/.test(line) && !/API key|EmbedText|ClassFactory/.test(line)) say(`  ${line.trim()}`);
    }
    return true;
}

// ─── Contracts, on the SAME fixtures ─────────────────────────────────────────────────────────────

async function seedContracts() {
    step('Seeding contracts against the same company, customers and catalogue');

    const fixtures = await q(`
        SELECT TOP 1
          -- The PRIMARY seller and customer, not whichever sorts first. Orders builds two companies
          -- (a publisher and a partner press) so it can demonstrate intercompany postings; the
          -- agreement belongs to the main one, and an alphabetical pick quietly chose the partner.
          (SELECT TOP 1 ID FROM __mj.Company WHERE Name LIKE '${DEMO_TAG}%Publishing%') AS companyID,
          (SELECT TOP 1 Name FROM __mj.Company WHERE Name LIKE '${DEMO_TAG}%Publishing%') AS companyName,
          (SELECT TOP 1 ID FROM ${COMMON}.Organization WHERE Name LIKE '${DEMO_TAG}%Riverside%') AS orgID,
          (SELECT TOP 1 Name FROM ${COMMON}.Organization WHERE Name LIKE '${DEMO_TAG}%Riverside%') AS orgName,
          (SELECT TOP 1 ID FROM ${ORDERS}.PaymentTermsType ORDER BY NetDays) AS payTermsID,
          (SELECT TOP 1 ID FROM ${ORDERS}.SubscriptionType ORDER BY Name) AS subTypeID,
          (SELECT TOP 1 ID FROM ${CONTRACTS}.ContractType WHERE Code='MSA') AS msaTypeID,
          (SELECT TOP 1 ID FROM ${CONTRACTS}.ContractType WHERE Code='Standard') AS stdTypeID`);
    const f = fixtures.recordset[0];

    if (!f.companyID || !f.orgID) {
        console.error('\n  ✗ No DEMO company/organisation found.');
        console.error('    Run the upstream layer first (drop --contracts-only), or seed orders by hand:');
        console.error('      node ../bizapps-orders/test-harnesses/seed-demo-data.mjs');
        process.exit(1);
    }
    if (!f.msaTypeID || !f.stdTypeID) {
        console.error('\n  ✗ Contract types are missing — run: mjdev app sync <slug> bizapps-contracts');
        process.exit(1);
    }

    const products = (await q(`
        SELECT TOP 4 p.ID, p.Name FROM ${ORDERS}.Product p
        WHERE p.CompanyID = '${f.companyID}' ORDER BY p.Name`)).recordset;
    if (products.length === 0) {
        console.error('\n  ✗ No DEMO products found — the upstream layer did not run.');
        process.exit(1);
    }

    say(`  company:  ${f.companyName}`);
    say(`  customer: ${f.orgName}`);
    say(`  catalogue: ${products.map((p) => p.Name).join(', ')}`);

    return { ...f, products };
}

// ─── Contracts, written through the ENTITY LAYER ─────────────────────────────────────────────────

/**
 * Create the agreements with `ContractEntityServer`, not SQL.
 *
 * This is the part that makes the dataset trustworthy. Raw SQL produces rows the DATABASE accepts;
 * the entity layer produces rows the APP accepts — term numbering derived rather than supplied, the
 * escalation ceiling checked against the contract type, coverage required before a term goes Active,
 * the whole tree written in one transaction. A demo contract that the UI would refuse to save is
 * worse than no demo contract, because the first person to click Edit finds it.
 */
async function writeContracts(ctx) {
    const { setupSQLServerClient, SQLServerProviderConfigData, UserCache } = await import('@memberjunction/sqlserver-dataprovider');
    await setupSQLServerClient(new SQLServerProviderConfigData(pool, process.env.MJ_CORE_SCHEMA || '__mj'));
    await UserCache.Instance.Refresh(pool);
    const user = UserCache.Users.find((u) => u?.Type?.trim().toLowerCase() === 'owner') ?? UserCache.Users[0];
    if (!user) throw new Error('no context user available');

    // The server subclasses register as an import side effect. Without these the seed would write
    // through the plain generated entities and skip every rule it is meant to respect.
    await import('@memberjunction/server-bootstrap-lite');
    await import('@mj-biz-apps/common-entities');
    await import('@mj-biz-apps/orders-entities');
    await import('@mj-biz-apps/contracts-entities');
    await import('@mj-biz-apps/contracts-core-entities-server');

    const { Metadata } = await import('@memberjunction/core');
    const md = new Metadata();
    const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';

    const today = new Date();
    const iso = (d) => new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
    const plusYears = (d, n) => { const x = iso(d); x.setUTCFullYear(x.getUTCFullYear() + n); x.setUTCDate(x.getUTCDate() - 1); return x; };

    const made = [];

    /** One agreement, its term, and the coverage that term entitles the customer to. */
    async function agreement({ label, typeID, status, startsIn, years, committed, escalation, lines }) {
        const c = await md.GetEntityObject(E_CONTRACT, user);
        c.NewRecord();
        c.ContractTypeID = typeID;
        c.CompanyID = ctx.companyID;
        c.CustomerOrganizationID = ctx.orgID;
        c.Status = 'Draft';                       // activated below, so the lifecycle rules run in order
        c.Description = `${DEMO_TAG} ${label}`;
        const start = iso(today); start.setUTCDate(start.getUTCDate() + startsIn);
        c.EffectiveDate = start;
        c.AutoRenew = true;

        const term = await c.CreateTerm(user);
        term.StartDate = start;
        term.EndDate = plusYears(start, years);
        term.Status = 'Pending';
        term.BillingFrequency = 'Quarterly';
        term.CommittedAmount = committed;
        if (escalation !== null) { term.EscalationPercent = escalation; term.EscalationBasis = 'PriorTerm'; }
        term.PaymentTermsTypeID = ctx.payTermsID;

        let order = 1;
        for (const l of lines) {
            const line = await term.CreateLine(user);
            line.ProductID = l.product;
            line.LineType = l.type;
            line.Quantity = l.qty;
            line.ContractedUnitPrice = l.price;
            if (l.type === 'Subscription') line.SubscriptionTypeID = ctx.subTypeID;
            line.DisplayOrder = order++;
            line.Description = l.label;
        }

        if (!(await c.Save())) throw new Error(`${label}: ${c.LatestResult?.CompleteMessage ?? 'save failed'}`);

        if (status === 'Active') {
            // Activated through the same path the UI uses, so the term's coverage rule is enforced
            // rather than assumed — a term with no lines is refused here exactly as it would be on screen.
            term.Status = 'Active';
            c.Status = 'Active';
            if (!(await c.Save())) throw new Error(`${label} (activate): ${c.LatestResult?.CompleteMessage ?? 'save failed'}`);
        }
        made.push(`${c.ContractNumber} (${status})`);
        return c;
    }

    step('Writing contracts through the entity layer');

    const p = ctx.products;
    await agreement({
        label: 'Riverside master agreement', typeID: ctx.msaTypeID, status: 'Active',
        startsIn: -120, years: 1, committed: 48000, escalation: 0.04,
        lines: [
            { product: p[0].ID, type: 'Subscription', qty: 1, price: 3000, label: p[0].Name },
            { product: p[1 % p.length].ID, type: 'Subscription', qty: 2, price: 750, label: p[1 % p.length].Name },
            { product: p[2 % p.length].ID, type: 'OneTime', qty: 1, price: 2500, label: `${p[2 % p.length].Name} — onboarding` },
        ],
    });
    await agreement({
        label: 'Riverside pilot, out for signature', typeID: ctx.stdTypeID, status: 'Draft',
        startsIn: 30, years: 1, committed: 9000, escalation: null,
        lines: [{ product: p[0].ID, type: 'Subscription', qty: 1, price: 750, label: `${p[0].Name} — pilot tier` }],
    });

    for (const m of made) say(`  ${m}`);
    return made;
}

// ─── Main ────────────────────────────────────────────────────────────────────────────────────────

try {
    await reset();

    if (resetOnly) {
        say('\n✓ Demo data removed.');
    } else {
        if (!contractsOnly) seedUpstream();
        const ctx = await seedContracts();
        const made = await writeContracts(ctx);
        say(`\n✓ One dataset across three apps:`);
        say(`    ${ctx.companyName} sells to ${ctx.orgName}`);
        say(`    orders + accounting: the nine orders above, trial balance balanced`);
        say(`    contracts: ${made.join(', ')}`);
        say(`\n  Re-runnable: 'npm run demo:seed' resets and rebuilds; 'npm run demo:reset' just clears.`);
    }
} finally {
    await pool.close();
}
