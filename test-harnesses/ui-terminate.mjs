/**
 * Terminating a contract through the UI — the one documented click path never driven in a browser.
 *
 * WHY THIS EXISTS. Termination was proven at tier 2 (the operation, its transaction, the exact
 * cancelled/retained split) and its controls were never clicked. Then `docs/WORKFLOW-WALKTHROUGH.md`
 * told a reviewer to follow that path during a live session. Publishing a click path I had not walked
 * is the gap this closes: if the reason field is not reachable, or the preview does not render, or
 * confirm does nothing, the first person to find out should not be Andrew in front of Marcelo.
 *
 * It WRITES — termination is not previewable all the way to proof — so it restores afterwards.
 * `demo/restore-demo-after-loop.sql` now un-cancels the billing events too, which it did not before:
 * un-terminating without that leaves the demo looking healthy while its schedule is dead, which is
 * the half-restored state that is worse than no restore at all.
 *
 * Usage: node test-harnesses/ui-terminate.mjs "<explorer-url-with-token>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-terminate.mjs "<explorer url with #token=…>"');
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
const page = await browser.newPage({ viewport: { width: 1600, height: 1200 } });
page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const t = m.text();
    if (/favicon|\.ico|\.map|apple-touch-icon/i.test(t)) return;
    errors.push(t.slice(0, 300));
});
page.on('pageerror', (e) => errors.push(String(e).slice(0, 300)));

try {
    console.log('\nA. Reach the termination controls, exactly as the walkthrough says');
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(8000);
    await page.locator('[role="row"]').nth(1).click();
    await page.waitForTimeout(4000);

    // The walkthrough says: workspace → Overview → "Renewal & termination".
    const reason = page.getByPlaceholder(/Why is this ending/i);
    check('A.1 the Overview tab carries a termination reason field', (await reason.count()) > 0);
    check('A.2 a Terminate control is present', (await page.getByRole('button', { name: /terminate/i }).count()) > 0);

    const terminate = page.getByRole('button', { name: /terminate/i }).first();
    check('A.3 it is DISABLED until a reason is given — the reason is required, not advisory',
        !(await terminate.isEnabled()));

    console.log('\nB. The preview reports the split before anything is written');
    await reason.fill('Walkthrough verification — customer consolidation');
    // Effective mid-term, so there is both a retained and a cancelled side to report.
    const effective = page.locator('input[type="date"]').last();
    if (await effective.count()) await effective.fill('2026-08-15');
    await page.waitForTimeout(1200);

    check('B.1 the control enables once a reason is present', await terminate.isEnabled());
    await terminate.click();
    await page.waitForTimeout(5000);

    const pv = await page.locator('.pv').last().innerText().catch(() => '');
    check('B.2 a preview appears', pv.length > 20, pv.slice(0, 150).replace(/\n/g, ' / '));
    check('B.3 it states how many terms end', /term\(s\) will be terminated/i.test(pv), pv.slice(0, 200).replace(/\n/g, ' / '));
    check('B.4 and how many FUTURE billing events are cancelled', /future billing event\(s\) will be cancelled/i.test(pv),
        pv.slice(0, 200).replace(/\n/g, ' / '));

    // The demo's active term bills quarterly through 2026, so an August cut has events on both sides.
    check('B.5 it also says what STAYS — periods already covered are still owed',
        /stay/i.test(pv) || /still owed/i.test(pv), pv.slice(0, 250).replace(/\n/g, ' / '));

    const stillActive = await page.locator('body').innerText();
    check('B.6 THE PREVIEW WROTE NOTHING — the contract still reads ACTIVE', /ACTIVE/.test(stillActive));

    console.log('\nC. Confirming actually terminates it');
    const confirm = page.getByRole('button', { name: /terminate this contract/i }).first();
    check('C.1 a confirm control is present', (await confirm.count()) > 0);
    await confirm.click();
    await page.waitForTimeout(9000);

    const after = await page.locator('body').innerText();
    check('C.2 the contract now reads TERMINATED', /TERMINATED/i.test(after), after.slice(0, 200).replace(/\n/g, ' / '));

    console.log('\nD. The history records it, in readable form');
    const hist = page.getByRole('button', { name: /^history/i }).first();
    if (await hist.count()) { await hist.click(); await page.waitForTimeout(4000); }
    const histText = await page.locator('.cb').first().innerText().catch(() => '');
    check('D.1 a termination entry appears on the timeline', /Contract terminated/i.test(histText),
        histText.slice(0, 200).replace(/\n/g, ' / '));
    check('D.2 and it carries the REASON that was typed', /customer consolidation/i.test(histText),
        histText.slice(0, 250).replace(/\n/g, ' / '));

    console.log('\nE. Console health');
    check('E.1 no console or page errors across the whole path', errors.length === 0, errors.slice(0, 2).join(' | '));

    await page.screenshot({ path: 'test-harnesses/ui-terminate.png' });
} catch (e) {
    failed++;
    notes.push(`HARNESS: ${e.message}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e.message}`);
    try { await page.screenshot({ path: 'test-harnesses/ui-terminate-failure.png' }); } catch { /* ignore */ }
}

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach((n) => console.log(`  · ${n}`));
console.log('\nNOTE: this run TERMINATED the demo contract. Restore it with demo/restore-demo-after-loop.sql');
await browser.close();
process.exit(failed === 0 ? 0 : 1);
