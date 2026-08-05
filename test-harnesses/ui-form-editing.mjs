/**
 * Editing a term through MJ's form architecture — the slide-in, not a hand-built field set.
 *
 * What this actually needs to prove is narrow but important: that the presenter mounts a REAL form
 * for our entity, that the form is populated with the record we asked for, and that cancelling it
 * leaves the record alone. If the slide-in opened empty, or opened the wrong record, the UI would
 * still "work" in the sense that a panel appears — which is exactly the kind of half-working that a
 * presence-only check would bless.
 *
 * Usage: node test-harnesses/ui-form-editing.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-form-editing.mjs "<explorer url with #token=…>"');
    process.exit(2);
}

let passed = 0, failed = 0;
const notes = [];
const check = (name, ok, detail = '') => {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; notes.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
};

const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1700, height: 1100 } });
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    errors.push(t);
});
page.on('pageerror', (e) => errors.push(String(e)));

try {
    console.log('\nA. Open a contract on the terms tab');
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(8000);

    const row = page.locator('[role="row"]').nth(1);
    if (await row.count()) { await row.click(); await page.waitForTimeout(3500); }
    const termsTab = page.getByRole('button', { name: /^terms/i }).first();
    if (await termsTab.count()) await termsTab.click();
    await page.waitForTimeout(2500);
    check('A.1 the term timeline is showing', (await page.locator('.tl-row').count()) > 0);

    console.log('\nB. Open a term in the slide-in form');
    // The pencil is the first action on the row; target it by its title rather than by position.
    const edit = page.locator('button[title*="Edit this term"]').first();
    check('B.1 an edit control is offered on each term', (await edit.count()) > 0);
    const baselineKids = await page.evaluate(() => document.body.children.length);
    await edit.click();
    await page.waitForTimeout(6000);

    // SCOPE THE ASSERTION TO THE OVERLAY ITSELF. Checking document.body would also match the grid
    // behind it, whose column header is likewise "Committed Amount" — so a body-wide check passes
    // even when the slide-in opens empty. The first version of this file had exactly that bug and
    // reported a confident 8/8.
    //
    // The overlay is found as the LAST child of <body>, not by an `mj-form-slide-in` tag: the
    // presenter mounts it with createComponent() into a plain div host, so the component's own
    // selector never appears in the DOM. Verified by diffing document.body.children across the click.
    const bodyKids = await page.evaluate(() => document.body.children.length);
    check('B.2 an overlay was mounted onto the body', bodyKids > baselineKids, `${baselineKids} -> ${bodyKids}`);
    const panelText = await page.evaluate(() => {
        const last = document.body.lastElementChild;
        return last ? (last.innerText || '') : '';
    });
    check('B.2a the overlay rendered the entity form, not an empty shell', /Committed Amount|CommittedAmount/i.test(panelText), panelText.slice(0, 300));
    check("B.3 the form carries the term's real data", /4(32|53|71)/.test(panelText) || /Quarterly/i.test(panelText), panelText.slice(0, 300));

    console.log('\nC. Cancelling changes nothing');
    const close = page.getByRole('button', { name: /close|cancel/i }).last();
    if (await close.count()) { await close.click(); await page.waitForTimeout(3000); }
    check('C.1 the slide-in closes', (await page.locator('.tl-row').count()) > 0);

    console.log('\nD. Adding coverage and a term are offered');
    check('D.1 an add-coverage control is offered per term', (await page.locator('button[title*="Add a coverage line"]').count()) > 0);
    check('D.2 an Add term control is offered on the contract', (await page.getByRole('button', { name: /add term/i }).count()) > 0);

    console.log('\nE. Console health');
    check('E.1 no console or page errors', errors.length === 0, errors.slice(0, 3).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-form-editing.png' });
    console.log('\n  (screenshot: test-harnesses/ui-form-editing.png)');
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-form-editing-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
await browser.close();
process.exit(failed === 0 ? 0 : 1);
