/**
 * Drives the golden path THROUGH THE UI ONLY — no direct DB writes, no API calls.
 * create -> see it in the list -> open it in the workspace.
 * Uses system Chrome (channel:'chrome') per the harness convention.
 */
import { chromium } from 'playwright';
import fs from 'fs';

const URL = fs.readFileSync('/tmp/mjurl.txt', 'utf8').trim();
const NUM = process.env.CTR || 'CTR-UI-0001';
const shot = (p, n) => p.screenshot({ path: `/tmp/golden-${n}.png`, fullPage: false }).catch(() => {});
const log = (...a) => console.log('[golden]', ...a);

const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
page.on('console', (m) => { if (m.type() === 'error' && !/favicon|sourcemap|\.ico/i.test(m.text())) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));

try {
    log('opening explorer…');
    await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 90000 });
    await page.waitForTimeout(12000);
    await shot(page, '01-loaded');

    // Reach the Contracts app
    const contractsNav = page.getByText('Contracts', { exact: true }).first();
    if (await contractsNav.count()) { await contractsNav.click({ timeout: 15000 }).catch(() => {}); }
    await page.waitForTimeout(6000);
    await shot(page, '02-contracts');
    log('title:', await page.title());

    // Go to the create page via the rail
    const newNav = page.getByText('New contract', { exact: false }).first();
    await newNav.click({ timeout: 20000 });
    await page.waitForTimeout(3000);
    await shot(page, '03-create');

    // Fill the form — labels are our own, so target by proximity to the label text
    const setInput = async (labelText, value) => {
        const lbl = page.locator('label.fld', { hasText: labelText }).first();
        const el = lbl.locator('input.in, select.sel, textarea.ta').first();
        const tag = await el.evaluate((n) => n.tagName.toLowerCase());
        if (tag === 'select') await el.selectOption({ index: 1 });
        else await el.fill(String(value));
        return tag;
    };

    await setInput('Contract number', NUM);
    await setInput('Contract type', '');
    await setInput('Selling company', '');
    await setInput('Customer organization', '');
    await setInput('Effective', '2027-01-01');
    await setInput('Executed', '2026-12-15');
    await setInput('Priced as of', '2026-12-10');
    await setInput('Description', 'Created through the UI by the golden-path drive.');
    await setInput('Cancellation window (days)', '45');
    await setInput('External reference', 'UI-DRIVE-1');
    await shot(page, '04-filled');

    // The optional first term
    const termToggle = page.locator('input[type=checkbox]').first();
    if (await termToggle.count()) {
        await termToggle.check().catch(() => {});
        await page.waitForTimeout(500);
        await setInput('Start date', '2027-01-01');
        await setInput('End date', '2027-12-31');
        await setInput('Committed amount', '250000');
        await shot(page, '05-term');
    }

    // Create
    const createBtn = page.getByRole('button', { name: /Create contract/i }).first();
    log('create enabled:', await createBtn.isEnabled());
    await createBtn.click({ timeout: 20000 });
    await page.waitForTimeout(8000);
    await shot(page, '06-after-create');

    const bodyText = await page.locator('body').innerText();
    log('workspace shows number:', bodyText.includes(NUM));

    // Back to the list and confirm it is there
    const listNav = page.locator('mj-left-nav').getByText('Contracts', { exact: true }).first();
    if (await listNav.count()) { await listNav.click().catch(() => {}); await page.waitForTimeout(5000); }
    await shot(page, '07-list');
    const listText = await page.locator('body').innerText();
    log('list shows number:', listText.includes(NUM));

    console.log('CONSOLE_ERRORS=' + errors.length);
    errors.slice(0, 5).forEach((e) => console.log('  err:', e.slice(0, 160)));
} catch (e) {
    console.log('DRIVE_ERROR:', String(e).slice(0, 400));
    await shot(page, '99-failure');
} finally {
    await browser.close();
}
