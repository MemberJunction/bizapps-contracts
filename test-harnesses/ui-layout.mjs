/**
 * TIER 5 — LAYOUT. Every page, in every section, at several viewport sizes.
 *
 * WHY THIS EXISTS. A page whose layout depends on the WINDOW HEIGHT is a bug you cannot see in a
 * test that only ever renders one size, and it is exactly the bug this file was written for: the
 * app dropped its page content straight into `mj-left-nav-content`, whose ::ng-deep rule forces
 * every direct child to display:flex + flex-direction:column + height:100% + overflow:hidden. Block
 * flow became a fixed-height flex column that CLIPPED instead of scrolling, so what a page looked
 * like was a function of how tall the window happened to be. The fix is MJ's own chrome pattern —
 * left-nav-content, then mj-page-body-interior (named in that rule's :not() list, so it keeps
 * display:block + flex:1 1 auto + overflow-y:auto), then the content.
 *
 * The four assertions per page are the ones that would have caught it:
 *   - the interior scroller is actually present
 *   - it fills to the BOTTOM of the pane (gap 0), so height is used rather than guessed
 *   - overflow scrolls rather than clips
 *   - content is a SINGLE column spanning the pane — a second x value means something wrapped or
 *     floated into a column of its own, which is what a "smooshed on the right" page really is
 * and then, across sizes, that each page sits at the same x at every viewport. That last one is the
 * actual contract: layout must not be viewport-dependent.
 *
 * It also covers the workspace search, which is the other thing a single-state test misses: the
 * results list was hidden whenever a contract was open, so typing did nothing.
 *
 * Usage: node test-harnesses/ui-layout.mjs "<explorer url with #token=…>"
 * READ-ONLY — it opens and searches, it never saves.
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
const SIZES = [[1700,1200],[1551,869],[1280,720]];
const RAILS = {
  Contracts: ['Dashboard', 'All contracts', 'Workspace', 'Renewals due', 'Amendments'],
  Billing: ['Billing worklist', 'Schedules', 'Commitments'],
  Setup: ['Contract types'],
};
let pass = 0, fail = 0;
const check = (n, ok, d='') => { if (ok) { pass++; } else { fail++; console.log(`  FAIL ${n} — ${d}`); } };

const b = await chromium.launch({ headless: true, channel: 'chrome' });
const seen = {};
for (const [w,h] of SIZES) {
  const p = await b.newPage({ viewport: { width: w, height: h } });
  await p.goto(URL, { waitUntil: 'domcontentloaded' });
  await p.waitForTimeout(9000);
  await p.getByText(/The agreement envelope/i).first().click();
  await p.waitForTimeout(7000);
  for (const [section, items] of Object.entries(RAILS)) {
    await p.getByRole('link', { name: new RegExp(`^${section}$`) }).first().click();
    await p.waitForTimeout(2200);
    for (const item of items) {
      await p.locator('mj-left-nav').getByRole('button', { name: new RegExp(item, 'i') }).first().click();
      await p.waitForTimeout(1600);
      const m = await p.locator('mj-left-nav-content').first().evaluate((n) => {
        const interior = n.querySelector('mj-page-body-interior');
        const wrap = n.querySelector('.wrap');
        const pane = n.getBoundingClientRect();
        const kids = [...(wrap?.children ?? [])].map((c) => Math.round(c.getBoundingClientRect().x));
        const kw = [...(wrap?.children ?? [])].map((c) => Math.round(c.getBoundingClientRect().width));
        return {
          hasInterior: !!interior,
          bottomGap: interior ? Math.round(pane.bottom - interior.getBoundingClientRect().bottom) : null,
          clipped: interior ? (interior.scrollHeight > interior.clientHeight && getComputedStyle(interior).overflowY !== 'auto') : false,
          xs: [...new Set(kids)], ws: [...new Set(kw)],
          paneW: Math.round(pane.width),
        };
      });
      // EXACTLY ONE creation control per page, and it lives in the header.
      //
      // Counted OUTSIDE mj-workspace-card deliberately: the card's document strip has its own "+"
      // new-tab affordance, which is chrome that comes with the card rather than a page-level
      // button, so excluding it keeps this assertion about the thing it is actually policing —
      // a second "New X" a few hundred pixels from the first one, where the reader has to work out
      // whether the two differ.
      const news = await p.evaluate(() => {
        const all = [...document.querySelectorAll('button, a[role=button]')];
        return all
          .filter((b) => !b.closest('mj-workspace-card'))
          .map((b) => (b.textContent || '').trim())
          .filter((t) => /^New\s/i.test(t));
      });
      check(`${section}/${item} @${w} has exactly one "New …" control`, news.length === 1, news.join(' | ') || 'none');

      const key = `${section}/${item}`;
      check(`${key} @${w} uses the interior scroller`, m.hasInterior);
      check(`${key} @${w} fills to the bottom`, m.bottomGap === 0, `gap ${m.bottomGap}px`);
      check(`${key} @${w} never clips`, !m.clipped);
      check(`${key} @${w} content is single-column`, m.xs.length <= 1, `x values ${m.xs.join(',')}`);
      check(`${key} @${w} content spans the pane`, m.ws.every((x) => x > m.paneW - 80), `widths ${m.ws.join(',')} pane ${m.paneW}`);
      (seen[key] ??= []).push(m.xs[0]);
    }
  }
  await p.close();
}
for (const [k, xs] of Object.entries(seen)) {
  check(`${k} sits at the same x at every viewport`, new Set(xs).size === 1, xs.join(','));
}

// The search, with a record open.
const p = await b.newPage({ viewport: { width: 1551, height: 869 } });
await p.goto(URL, { waitUntil: 'domcontentloaded' });
await p.waitForTimeout(9000);
await p.getByText(/The agreement envelope/i).first().click();
await p.waitForTimeout(7000);
await p.getByRole('link', { name: /^Contracts$/ }).first().click();
await p.waitForTimeout(2200);
await p.locator('mj-left-nav').getByRole('button', { name: /workspace/i }).first().click();
await p.waitForTimeout(2000);
await p.locator('.pick').first().click();
await p.waitForTimeout(3000);
check('a record opens into the workspace card', await p.locator('mj-workspace-card').count() > 0);
await p.locator('.searchbox input').first().fill('CTR-002004');
await p.waitForTimeout(1200);
const picks = await p.locator('.pick').allInnerTexts();
check('search returns results while a contract is open', picks.length >= 1, `${picks.length} results`);
check('and it is the one searched for', picks.join(' ').includes('CTR-002004'), picks.join(' | ').slice(0,120));
await p.locator('.pick').first().click();
await p.waitForTimeout(3000);
const tabs = await p.locator('mj-workspace-card [role="tab"], mj-workspace-card .ws-tab').count();
check('opening a hit adds a second document tab', tabs >= 2, `${tabs} tabs`);
await p.close();
await b.close();
console.log(`\n${fail === 0 ? 'PASS' : 'FAIL'} — ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
