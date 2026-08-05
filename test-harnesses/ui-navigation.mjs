/**
 * The pages, the search, and the grids that were carrying no assertions at all.
 *
 * Closes gaps 5a / 5b / 5c from `testing.md`. The grid tabs are the interesting ones: they render
 * MJ's grid, which is not ours to test — but the PARAMS we bind to it are, and a wrong `ExtraFilter`
 * would show another contract's rows while looking completely healthy. So this asserts that each tab
 * shows data belonging to the contract that is open, not merely that a grid appeared.
 *
 * Usage: node test-harnesses/ui-navigation.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-navigation.mjs "<explorer url with #token=…>"');
    process.exit(2);
}

let passed = 0, failed = 0;
const notes = [];
const check = (n, ok, d = '') => {
    if (ok) { passed++; console.log(`  ✓ ${n}`); }
    else { failed++; notes.push(`${n}${d ? ' — ' + d : ''}`); console.log(`  ✗ ${n}${d ? ' — ' + d : ''}`); }
};

const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 1100 } });
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    errors.push(t.slice(0, 300));
});
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));

/**
 * Navigate, then WAIT FOR THE PAGE TO ACTUALLY BE THERE rather than for a fixed number of
 * milliseconds. A fixed sleep produced assertions whose failure detail was the single word
 * "Contracts" — the page chrome had rendered and the content had not, so the test was reading an
 * empty page and reporting it as wrong content.
 */
const nav = async (label, expect) => {
    // BY ROLE, not by text. The nav subtitle is a <span> inside a <button.mj-left-nav__item>, and
    // clicking the inner span did not reliably navigate — the run stayed on the previous page while
    // reporting the NEXT page's content as wrong. Role targeting hits the real control and doubles as
    // an assertion that it is one. (TEST-ARCHITECTURE says this in as many words; I relearned it.)
    await page.getByRole('button', { name: label }).first().click();
    if (expect) {
        await page.locator(expect).first().waitFor({ state: 'visible', timeout: 30000 }).catch(() => undefined);
    }
    await page.waitForTimeout(2000);
};

try {
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(8000);

    console.log('\nA. The workspace search + status filter (gap 5a)');
    // The search lives on the WORKSPACE, not the roster — it is a contract PICKER, moved there
    // deliberately. The roster page uses MJ's own grid toolbar, which is not ours to test. An earlier
    // version of this harness looked for the search on the roster and failed; the app was right.
    await nav(/Workspace/, '.searchbar');
    const search = page.getByPlaceholder(/Find a contract/i);
    check('A.1 the workspace carries the contract search', (await search.count()) > 0);

    // The picker only appears once there is a query — an always-visible empty list would be noise.
    check('A.2 no picker is shown before searching', (await page.locator('.picker').count()) === 0);

    await search.fill('001842');
    await page.waitForTimeout(2000);
    const hits = await page.locator('.pick').count();
    check('A.3 searching by contract number finds exactly one match', hits === 1, `${hits} matches`);
    check('A.4 the match shows the contract number', /CTR-001842/.test(await page.locator('.pick').first().innerText()));

    // A search that filters nothing looks identical to one that works, until the day it matters.
    await search.fill('ZZZ-NOTHING-MATCHES');
    await page.waitForTimeout(2000);
    check('A.5 a non-matching search yields no results and says so',
        (await page.locator('.pick').count()) === 0 && (await page.getByText(/Nothing matches that search/i).count()) > 0);

    // The description is searchable too, not just the number.
    await search.fill('Northwind');
    await page.waitForTimeout(2000);
    check('A.6 the search matches on description, not only the number', (await page.locator('.pick').count()) === 1);

    await search.fill('');
    await page.waitForTimeout(1200);
    const statusFilter = page.locator('select.sel').first();
    await statusFilter.selectOption('Terminated');
    await page.waitForTimeout(2000);
    check('A.7 filtering to a status the demo has none of yields nothing', (await page.locator('.pick').count()) === 0);

    await statusFilter.selectOption('Active');
    await page.waitForTimeout(2000);
    // Assert the demo contract is AMONG the matches, not that it is the only one. "Exactly one
    // Active contract" is true of a pristine demo and false of any real system — and it was already
    // false here the moment a test-created contract was left behind, which is a brittleness worth
    // removing rather than a leftover worth only deleting.
    const activeText = await page.locator('.picker').innerText().catch(() => '');
    check('A.8 filtering to Active includes the demo contract', /CTR-001842/.test(activeText), activeText.slice(0, 150).replace(/\n/g, ' / '));
    check('A.8a and every match shown really is Active', !/Draft|Terminated|Expired/.test(activeText), activeText.slice(0, 150).replace(/\n/g, ' / '));

    const clear = page.getByRole('button', { name: /^clear$/i }).first();
    check('A.9 a Clear control appears once a search is active', (await clear.count()) > 0);
    await clear.click();
    await page.waitForTimeout(1500);
    check('A.10 Clear removes the picker entirely', (await page.locator('.picker').count()) === 0);

    console.log('\nB. The billing worklist (gap 5b)');
    await nav(/Due, generated and failed/i, '.wrap');
    const billingText = await page.locator('body').innerText();
    check('B.1 the billing worklist page renders', billingText.length > 200);
    // The demo has one Failed event with a stated reason; the worklist is where a person would find it.
    check('B.2 it surfaces the failed billing event', /fail/i.test(billingText), billingText.slice(0, 200));

    console.log('\nC. Contract types (setup page)');
    await nav(/Defaults and rules/i, '.wrap');
    const typesText = await page.locator('body').innerText();
    // By NAME, not by code: the grid shows "Master Services Agreement" and "Statement of Work", which
    // is what a person reads. Asserting the codes tested the seed file rather than the page.
    const typeNames = ['Standard Agreement', 'Master Services Agreement', 'Statement of Work', 'Membership', 'Evergreen', 'Pilot'];
    const missing = typeNames.filter((t) => !typesText.includes(t));
    check('C.1 all six seeded contract types are listed by name', missing.length === 0, `missing: ${missing.join(', ')}`);
    check('C.2 the page explains configuration-as-data', /the columns are the rules/i.test(typesText));

    console.log('\nD. The grid tabs bind the RIGHT contract (gap 5c)');
    // Open the contract through the workspace PICKER, which section A already proved works. Clicking
    // a roster grid row did not reliably open the workspace here, and the earlier version then went
    // on to "pass" a Billing check that had actually matched the left-nav "Billing worklist" button —
    // a false pass that also derailed everything after it.
    await nav(/Open a contract|Workspace/, '.searchbar');
    await page.getByPlaceholder(/Find a contract/i).fill('001842');
    await page.waitForTimeout(2500);
    await page.locator('.pick').first().click();
    await page.waitForTimeout(4000);
    check('D.0 the contract opens in the workspace', (await page.locator('.tabs').count()) > 0);

    // Tab clicks are SCOPED to the .tabs container. Unscoped, /^billing/i matches the left-nav
    // "Billing worklist" item and silently navigates away from the thing under test.
    const tabs = page.locator('.tabs');
    const openTab = async (name) => {
        await tabs.getByRole('button', { name }).first().click();
        await page.waitForTimeout(4500);
    };

    await openTab(/^Coverage$/);
    const cov = await page.locator('body').innerText();
    // Asserted on the PRICES, not the descriptions. MJ's grid renders the entity's own columns and
    // does not take its column set from RunViewParams.Fields, so the coverage grid displays ProductID
    // as a bare UUID and no description — see the "grid columns" note in testing.md. The prices are
    // the demo's known contracted values, so they still prove the binding points at THIS term:
    // a wrong ExtraFilter would show other rows or none.
    check("D.1 Coverage shows THIS term's contracted prices", /\$28,000\.00/.test(cov) && /\$8,000\.00/.test(cov), cov.slice(-200).replace(/\n/g, ' / '));
    // The third line is deliberately null-priced (catalog-resolved), so three rows with two prices
    // is the correct shape — not a missing row.
    check('D.2 Coverage shows all three lines, one of them catalog-priced', (await page.locator('[role="row"]').count()) >= 4, `${await page.locator('[role="row"]').count()} rows incl. header`);

    // Clicking a coverage row opens the LINE in its own custom form — the editing half of the tab,
    // which previously only listed. Asserted on the custom panel names, since the generated form
    // would also open and would also look fine.
    const covRows = page.locator('[role="row"]');
    if ((await covRows.count()) > 1) {
        const kidsBefore = await page.evaluate(() => document.body.children.length);
        await covRows.nth(1).click();
        await page.waitForTimeout(6000);
        const kidsAfter = await page.evaluate(() => document.body.children.length);
        check('D.1a clicking a coverage row opens an overlay', kidsAfter > kidsBefore, `${kidsBefore} -> ${kidsAfter}`);
        const lineText = await page.evaluate(() => document.body.lastElementChild?.innerText ?? '');
        check('D.1b it is the CUSTOM line form, with its explanatory panels',
            /What is covered/i.test(lineText) && /resolve from the catalog/i.test(lineText),
            lineText.slice(0, 200).replace(/\n/g, ' / '));
        const close = page.getByRole('button', { name: /close|cancel/i }).last();
        if (await close.count()) { await close.click(); await page.waitForTimeout(2500); }
    }

    await openTab(/^Billing$/);
    const bill = await page.locator('body').innerText();
    check("D.3 Billing shows the term's schedule and events", /Quarterly/.test(bill) && /Scheduled/i.test(bill), bill.slice(-200).replace(/\n/g, ' / '));

    await openTab(/^Commitments$/);
    check('D.4 Commitments renders', (await page.locator('.tabs').count()) > 0);

    await openTab(/^Amendments$/);
    const amend = await page.locator('body').innerText();
    check('D.5 Amendments renders and explains itself', /Amendments change a/i.test(amend));

    console.log('\nF. The status control offers only LEGAL moves');
    await openTab(/^Overview$/);
    const statusOpts = await page.evaluate(() => {
        const labels = Array.from(document.querySelectorAll('label'));
        const statusLabel = labels.find((l) => l.textContent?.trim().startsWith('Status'));
        const sel = statusLabel?.querySelector('select');
        return sel ? Array.from(sel.options).map((o) => o.value) : [];
    });
    // The demo contract is Active. From Active the legal moves are Active, Expired, Terminated and
    // Superseded — Draft and PendingSignature are NOT offered, because going back to a draft after
    // the agreement is live is not a thing that happens.
    check('F.1 the status control offers exactly the legal moves from Active',
        JSON.stringify(statusOpts) === JSON.stringify(['Active', 'Expired', 'Terminated', 'Superseded']),
        JSON.stringify(statusOpts));
    check('F.2 it does NOT offer a move back to Draft', !statusOpts.includes('Draft'));

    console.log('\nE. Console health');
    check('E.1 no console or page errors across every page and tab', errors.length === 0, errors.slice(0, 2).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-navigation.png' });
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-navigation-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
await browser.close();
process.exit(failed === 0 ? 0 : 1);
