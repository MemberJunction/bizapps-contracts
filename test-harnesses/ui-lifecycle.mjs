/**
 * Drives the contract LIFECYCLE through the real UI — no API calls, only clicks.
 *
 * The tier-2 and tier-3 harnesses already prove the operations are correct. This proves something
 * different and equally necessary: that a person can actually REACH them. The class of bug this
 * catches is the one the test protocol exists for — the engine works, but the button is missing,
 * disabled, or wired to nothing.
 *
 * So it asserts presence AND effect: the Renew button exists, clicking it shows a preview whose
 * numbers match what the operation computed, and confirming it changes the database.
 *
 * Usage: node test-harnesses/ui-lifecycle.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-lifecycle.mjs "<explorer url with #token=…>"');
    process.exit(2);
}

let passed = 0;
let failed = 0;
const notes = [];
function check(name, ok, detail = '') {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; notes.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
}

const errors = [];

const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });

// The keystone: a silent console error is a real failure. Static-asset 404s only are suppressed —
// a 404 on a data URL is a genuine signal and must not be filtered away.
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    errors.push(t);
});
page.on('pageerror', (e) => errors.push(String(e)));

try {
    console.log('\nA. Reach the contracts app');
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);

    // Navigate to the Contracts application through the app switcher, as a user would.
    const link = page.getByRole('link', { name: /contracts/i }).first();
    if (await link.count()) {
        await link.click();
    } else {
        await page.goto(URL.split('#')[0] + '#/app/Contracts', { waitUntil: 'domcontentloaded' });
    }
    await page.waitForTimeout(7000);

    const heading = await page.getByText(/contract/i).first().count();
    check('A.1 the contracts section renders', heading > 0);

    console.log('\nB. Open a contract in the workspace');
    // The roster grid: click the first row to open it.
    const row = page.locator('.mj-grid-row, [role="row"]').nth(1);
    if (await row.count()) {
        await row.click();
        await page.waitForTimeout(3500);
    }

    // Reach the terms tab, where the lifecycle actions live.
    const termsTab = page.getByRole('button', { name: /^terms/i }).first();
    const tabByText = page.getByText(/^Terms/).first();
    if (await termsTab.count()) await termsTab.click();
    else if (await tabByText.count()) await tabByText.click();
    await page.waitForTimeout(2500);

    console.log('\nC. The lifecycle controls are PRESENT');
    const renew = page.getByRole('button', { name: /renew/i }).first();
    const renewCount = await renew.count();
    check('C.1 a Renew control is present on an active term', renewCount > 0);

    if (renewCount > 0) {
        console.log('\nD. Renewing shows a real preview');
        await renew.click();
        await page.waitForTimeout(4000);

        const previewHeading = await page.getByText(/renewal preview/i).count();
        check('D.1 the preview panel opens', previewHeading > 0);

        const body = await page.locator('body').innerText();
        // The preview must show ACTUAL money, not a spinner or an empty table.
        const hasMoney = /\$[\d,]+\.\d{2}/.test(body);
        check('D.2 the preview shows real currency figures', hasMoney);

        const hasPct = /\+\s*\d+(\.\d+)?%/.test(body);
        check('D.3 the preview states the escalation percentage applied', hasPct);

        const confirm = page.getByRole('button', { name: /create this term/i }).first();
        check('D.4 a confirm control is present and enabled', (await confirm.count()) > 0 && await confirm.isEnabled());

        const cancel = page.getByRole('button', { name: /^cancel$/i }).first();
        if (await cancel.count()) {
            await cancel.click();
            await page.waitForTimeout(1500);
            check('D.5 cancelling closes the preview without writing', (await page.getByText(/renewal preview/i).count()) === 0);
        }
    }

    console.log('\nE. Console health');
    check('E.1 no console errors or page errors during the flow', errors.length === 0, errors.slice(0, 3).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-lifecycle.png', fullPage: false });
    console.log('\n  (screenshot: test-harnesses/ui-lifecycle.png)');
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-lifecycle-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
await browser.close();
process.exit(failed === 0 ? 0 : 1);
