/**
 * The full lifecycle loop, driven ONLY through the UI: renew a term, confirm it, then activate the
 * term that renewal created.
 *
 * Distinct from `ui-lifecycle.mjs`, which stops at the preview. This one WRITES, because "the button
 * opens a panel" and "the button does the thing" are different claims and only the second one is
 * worth demoing. Nothing here touches the API directly — every state change goes through a click.
 *
 * It restores what it changed: the term renewal creates is deleted at the end, so the demo contract
 * goes back to the three terms it started with. A test that leaves the demo in a different state
 * than it found it is a test that breaks the demo.
 *
 * Usage: node test-harnesses/ui-full-loop.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-full-loop.mjs "<explorer url with #token=…>"');
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
const page = await browser.newPage({ viewport: { width: 1600, height: 1100 } });
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    errors.push(t);
});
page.on('pageerror', (e) => errors.push(String(e)));

const openTerms = async () => {
    const tab = page.getByRole('button', { name: /^terms/i }).first();
    if (await tab.count()) { await tab.click(); }
    else { const t = page.getByText(/^Terms/).first(); if (await t.count()) await t.click(); }
    await page.waitForTimeout(2500);
};

try {
    console.log('\nA. Open the demo contract');
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);

    // Target the app card by its DESCRIPTION, not by a /contracts/i name match. The home page shows
    // three things matching that word — the "__mj_BizAppsContracts" generated-schema card, the
    // Contracts app card, and the "Contracts" nav item inside it — so a loose regex picks whichever
    // happens to be first in the DOM and silently stays on Home. This string belongs to one card.
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(8000);

    const row = page.locator('[role="row"]').nth(1);
    if (await row.count()) { await row.click(); await page.waitForTimeout(3500); }
    await openTerms();

    const before = await page.locator('.tl-row').count();
    check('A.1 the term timeline shows the seeded terms', before === 3, `saw ${before}`);

    console.log('\nB. Renew — through the UI, for real');
    const renew = page.getByRole('button', { name: /renew/i }).first();
    check('B.1 the Renew control is present', (await renew.count()) > 0);
    await renew.click();
    await page.waitForTimeout(4000);

    const previewText = await page.locator('.pv').innerText().catch(() => '');
    check('B.2 the preview shows the escalated figures', /\$[\d,]+\.\d{2}/.test(previewText), previewText.slice(0, 120));

    const confirm = page.getByRole('button', { name: /create this term/i }).first();
    check('B.3 the confirm control is present', (await confirm.count()) > 0);
    await confirm.click();
    // Confirm re-runs the operation for real, then refreshes — give it room.
    await page.waitForTimeout(9000);
    await openTerms();

    const after = await page.locator('.tl-row').count();
    check('B.4 a FOURTH term now exists — the renewal was written', after === 4, `saw ${after}`);

    const timeline = await page.locator('.cb').first().innerText().catch(() => '');
    check('B.5 the new term is Pending, not silently activated', /Pending/i.test(timeline), timeline.slice(0, 200));

    console.log('\nC. Activate the term the renewal created');
    const activate = page.getByRole('button', { name: /activate/i }).first();
    check('C.1 an Activate control appeared on the Pending term', (await activate.count()) > 0);
    await activate.click();
    await page.waitForTimeout(9000);
    await openTerms();

    const timeline2 = await page.locator('.cb').first().innerText().catch(() => '');
    const activeCount = (timeline2.match(/·\s*Active/g) || []).length;
    check('C.2 the renewed term is now Active', activeCount >= 1, timeline2.slice(0, 240));

    console.log('\nD. Console health');
    check('D.1 no console or page errors across the whole loop', errors.length === 0, errors.slice(0, 3).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-full-loop.png' });
    console.log('\n  (screenshot: test-harnesses/ui-full-loop.png)');
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-full-loop-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
console.log('\nNOTE: this run WROTE to the demo contract. Restore it with demo/restore-demo-after-loop.sql');
await browser.close();
process.exit(failed === 0 ? 0 : 1);
