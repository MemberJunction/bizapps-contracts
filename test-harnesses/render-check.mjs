/**
 * Ad-hoc RENDER CHECK — does the app actually appear and show data?
 *
 * NOT part of the app's test suite. Playwright is out of scope for v2 (ruled 2026-08-19): the tiered
 * suite belongs to MJ's integration testing framework, and item 13's bundles are where behaviour gets
 * asserted. This script exists for one narrower reason — it catches a class of defect that nothing
 * else in this repo can, which it proved twice in one session:
 *
 *   1. `super.ngOnDestroy?.()` — valid TypeScript, type-checks, builds clean, and produces a bundle
 *      esbuild cannot PARSE. One unparseable chunk killed every @RegisterClass in the package, so
 *      Explorer rendered no contracts nav tab at all.
 *   2. The list grid rendered ZERO ROWS while its toolbar reported "7 rows" — `mj-explorer-entity-data-grid`
 *      is `height: 100%` outside a related panel, and the page gave it no definite height. Every text
 *      assertion in this very script PASSED while that was broken, because the row text was in the DOM.
 *      Only the screenshot showed it.
 *
 * That second one is the honest limitation of this script: **text assertions cannot see layout.** It
 * writes screenshots to /tmp/mjj-*.png and they are worth looking at, not just collecting.
 *
 * Usage — needs MJAPI + MJExplorer running and a magic-link URL:
 *   mjdev explorer-url contracts-mj6 | grep -oE 'http://localhost:[0-9]+/#token=\S+' > /tmp/mjcurl.txt
 *   node test-harnesses/render-check.mjs
 *
 * Drives SYSTEM Chrome (`channel: 'chrome'`) so no Playwright browser download is needed.
 */
import { chromium } from '/Users/marcelotorres/MJDev/instances/contracts-mj6/node_modules/.pnpm/playwright@1.58.1/node_modules/playwright/index.mjs';
import fs from 'fs';
const URL = fs.readFileSync('/tmp/mjcurl.txt', 'utf8').trim();
const shot = (p, n) => p.screenshot({ path: `/tmp/mjj-${n}.png`, fullPage: false }).catch(() => {});
const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1680, height: 1050 } });
page.on('console', (m) => { if (m.type() === 'error' && !/favicon|sourcemap|\.ico|net::ERR/i.test(m.text())) errors.push(m.text()); });
page.on('pageerror', (e) => errors.push('PAGEERROR: ' + String(e)));
const txt = async () => (await page.locator('body').innerText().catch(() => '')) || '';
const step = (n, ok, extra='') => console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${n}${extra ? ' — ' + extra : ''}`);

try {
  await page.goto(URL, { waitUntil: 'domcontentloaded', timeout: 120000 });
  await page.waitForTimeout(22000);
  await page.getByText('Contracts', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(10000);
  await shot(page, '01-dashboard');
  let t = await txt();
  // Dashboard counts should now be non-zero.
  const nonZero = /In force without paper\s*[1-9]|Notice window closing \(60 days\)\s*[1-9]|Ends within 120 days\s*[1-9]|Modified agreements\s*[1-9]/.test(t.replace(/\n/g,' '));
  step('dashboard shows non-zero counts', nonZero, nonZero ? '' : t.replace(/\n/g,' ').slice(0,200));

  // All contracts
  await page.getByText('All contracts', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '02-list');
  t = await txt();
  const nums = (t.match(/CTR-9000\d\d/g) || []);
  step('list shows contract rows', nums.length >= 3, `${new Set(nums).size} distinct numbers`);
  const names = ['Northwind Association','Cascadia Health Society','Meridian Credit Union'].filter(n=>t.includes(n));
  step('grid shows NAMES not UUIDs (D-23)', names.length >= 2, names.join(', '));
  const states = ['Active','Executed','Expired','Draft'].filter(s=>t.includes(s));
  step('derived State column renders', states.length >= 3, states.join(', '));

  // Renewals worklist
  await page.getByText('Renewals & expiry', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '03-renewals');
  t = await txt();
  step('renewals page renders its pills', /Notice window|Ends in 120 days|Auto-renewing/.test(t));

  // Awaiting documents
  await page.getByText('Awaiting documents', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '04-awaiting');
  t = await txt();
  step('awaiting-documents page renders', /awaiting|Payment Links never appear/i.test(t));
  step('Payment Link is EXCLUDED from awaiting', !t.includes('CTR-900005'), t.includes('CTR-900005') ? 'CTR-900005 wrongly listed' : 'correctly absent');

  // Modifications
  await page.getByText('Modifications', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '05-modifications');
  t = await txt();
  step('modifications page renders rows', /Liability is capped|Most-modified|deviation/i.test(t));

  // Templates section
  await page.getByText('Templates', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '06-templates');
  t = await txt();
  step('templates section renders', /Agreement versions|Master Agreement|published version/i.test(t));
  await page.getByText('All provisions', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '07-provisions');
  t = await txt();
  step('all-provisions page renders clauses', /Limitation of Liability|Definitions|numbered clause/i.test(t));

  // Configuration
  await page.getByText('Configuration', { exact: true }).first().click({ timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(9000);
  await shot(page, '08-configuration');
  t = await txt();
  step('configuration renders contract types', /Requires Executed Document|Order Form|Payment Link/i.test(t));
} catch (e) {
  console.log('THREW:', String(e).slice(0, 300));
} finally {
  console.log(`\n  console errors: ${errors.length}`);
  errors.slice(0, 8).forEach((e) => console.log('    ', e.slice(0, 200)));
  await browser.close();
}
