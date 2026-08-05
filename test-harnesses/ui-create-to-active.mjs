/**
 * The golden path, from nothing: create a contract WITH coverage, then activate its term — all
 * through the UI.
 *
 * This is the flow that was broken until coverage entry existed. `Contracts.ActivateTerm` refuses a
 * term with no lines, so a contract created without them could never be activated and never renewed:
 * everything a person created in the app was a dead end. The point of this harness is that the dead
 * end stays gone — it fails the moment creation stops producing an activatable term.
 *
 * Usage: node test-harnesses/ui-create-to-active.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-create-to-active.mjs "<explorer url with #token=…>"');
    process.exit(2);
}

const STAMP = `UI-E2E ${new Date().toISOString().slice(0, 19)}`;
let passed = 0, failed = 0;
const notes = [];
const check = (name, ok, detail = '') => {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; notes.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
};

const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    // Truncated: a GraphQL error body runs to thousands of lines and buries the run's own output.
    errors.push(t.slice(0, 300));
});
page.on('pageerror', (e) => errors.push(String(e)));

/** Pick the first real option in a select (index 0 is usually the "choose…" placeholder). */
const pickFirst = async (sel) => {
    const values = await sel.locator('option').evaluateAll((os) => os.map((o) => o.value).filter(Boolean));
    if (values.length) await sel.selectOption(values[0]);
    return values[0];
};

try {
    console.log('\nA. Open the create page');
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(8000);

    await page.getByText(/New contract/i).first().click();
    await page.waitForTimeout(3000);
    check('A.1 the create page opens', (await page.getByText(/Fast entry|first term/i).count()) > 0);

    console.log('\nB. Fill the contract');
    const selects = page.locator('select.sel');
    // Contract type, company and customer organization are the required references.
    const n = await selects.count();
    for (let i = 0; i < Math.min(n, 4); i++) {
        const s = selects.nth(i);
        const val = await s.inputValue().catch(() => '');
        if (!val) await pickFirst(s);
    }
    // Target fields by PLACEHOLDER, not by position. `input.in` first is the contract NUMBER, so
    // filling "first" put the stamp in the wrong column and the description stayed null — a bug in
    // the harness that looked exactly like a bug in the app.
    await page.getByPlaceholder('CTR-001900').fill(`UI-E2E ${Date.now()}`);
    await page.getByPlaceholder('What this agreement covers').fill(STAMP);
    await page.waitForTimeout(500);

    console.log('\nC. Turn on the first term and add coverage');
    const termToggle = page.locator('input[type="checkbox"]').first();
    await termToggle.check();
    await page.waitForTimeout(1500);

    const warnBefore = await page.getByText(/cannot be activated/i).count();
    check('C.1 the app WARNS that an uncovered term cannot be activated', warnBefore > 0);

    await page.getByRole('button', { name: /add line/i }).first().click();
    await page.waitForTimeout(1200);

    // The product select is the one carrying the "Choose a product…" placeholder.
    const productSel = page.locator('select.sel').filter({ hasText: 'Choose a product' }).first();
    check('C.2 a coverage row with a product picker appeared', (await productSel.count()) > 0);
    const chosen = await pickFirst(productSel);
    check('C.3 a product can be selected', !!chosen);

    // A Subscription line REQUIRES a subscription type — CK_ContractLine_SubscriptionNeedsType — and
    // the page now says so BEFORE the save rather than letting the write fail with a raw
    // CREATE_ENTITY_ERROR. Pick one, the way a person would.
    const subTypeSel = page.locator('select.sel').filter({ hasText: 'Required' }).first();
    check('C.3a a subscription line demands its subscription type', (await subTypeSel.count()) > 0);
    await pickFirst(subTypeSel);
    await page.waitForTimeout(600);

    const priceInput = page.locator('input.nm').nth(1); // qty, price, disc
    await priceInput.fill('1200');
    await page.waitForTimeout(800);

    const warnAfter = await page.getByText(/cannot be activated/i).count();
    check('C.4 the warning clears once the term is covered', warnAfter === 0);

    // A SECOND line, deliberately left with no price. Null price means "resolve from the catalog",
    // NOT zero — so it must be excluded from the coverage total and the page must SAY how many it
    // excluded. Counting it as free would show a total that is confidently wrong, which is worse
    // than an incomplete one that admits what it left out. The walkthrough tells a reviewer this is
    // how it behaves, so it needs an assertion behind it.
    await page.getByRole('button', { name: /add line/i }).first().click();
    await page.waitForTimeout(1200);
    const secondType = page.locator('select.sel').filter({ hasText: 'Subscription' }).last();
    if (await secondType.count()) await secondType.selectOption('OneTime');
    // .last(), not .first(): EVERY product select contains the "Choose a product…" option, so the
    // filter matches both rows and .first() silently re-picked row 1 — leaving row 2 productless, so
    // the catalog-priced count stayed 0 and the note correctly did not render. The app was right.
    const secondProduct = page.locator('select.sel').filter({ hasText: 'Choose a product' }).last();
    if (await secondProduct.count()) await pickFirst(secondProduct);
    await page.waitForTimeout(1000);

    const covText = await page.locator('.cov').innerText().catch(() => '');
    check('C.5 the catalog-priced line is EXCLUDED from the total, and the page says so',
        /priced from the catalog, so not counted here/i.test(covText), covText.slice(-220).replace(/\n/g, ' / '));
    check('C.6 the total still shows the PRICED coverage rather than going blank',
        /\$1,200\.00/.test(covText), covText.slice(-220).replace(/\n/g, ' / '));

    console.log('\nD. Create it');
    await page.getByRole('button', { name: /create contract|^create$/i }).first().click();
    await page.waitForTimeout(9000);

    const body = await page.locator('body').innerText();
    check('D.1 creation did not report a failure', !/coverage failed|first term failed/i.test(body), body.match(/.{0,90}failed.{0,90}/i)?.[0] ?? '');

    console.log('\nE. Activate the term on the contract just created');
    // NO navigation step. Create() already loads the new contract into the workspace and switches to
    // it — landing you on the thing you just made is the correct behaviour, and an earlier version of
    // this harness invented a trip back to the roster that the app does not require. It then failed
    // on a search box that was not on the page it was actually looking at.
    const onNew = await page.getByText(/UI-E2E/).first().count();
    check('E.1 the app lands on the contract that was just created', onNew > 0);

    const termsTab = page.getByRole('button', { name: /^terms/i }).first();
    if (await termsTab.count()) await termsTab.click();
    await page.waitForTimeout(2500);

    const activate = page.getByRole('button', { name: /activate/i }).first();
    check('E.2 an Activate control is offered on the new term', (await activate.count()) > 0);
    await activate.click();
    await page.waitForTimeout(9000);

    const timeline = await page.locator('.cb').first().innerText().catch(() => '');
    check('E.3 THE NEW CONTRACT ACTIVATES — the dead end is gone', /Active/i.test(timeline), timeline.slice(0, 200));

    console.log('\nF. Console health');
    check('F.1 no console or page errors across the whole path', errors.length === 0, errors.slice(0, 3).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-create-to-active.png' });
    console.log('\n  (screenshot: test-harnesses/ui-create-to-active.png)');
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-create-to-active-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
console.log(`\nNOTE: this run created a contract described "${STAMP}". Clean up with demo/cleanup-ui-e2e.sql`);
await browser.close();
process.exit(failed === 0 ? 0 : 1);
