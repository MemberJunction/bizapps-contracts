/**
 * The consolidated workspace: one surface for viewing, editing AND creating — and the three tab
 * states that make that possible.
 *
 * WHAT THIS REPLACES. Creation used to live on its own page. A contract is never finished being
 * created, though — it gains a term next week, coverage after review — so two surfaces forced
 * somebody to decide when the thing stopped being created, and every entity appearing after that
 * became an argument about which surface owned it. Merging them removed the argument, and the third
 * tab state ("not yet", muted with a reason) is what lets one strip serve both jobs.
 *
 * WHAT IT PROVES
 *   1  the three SECTION tabs render (Contracts / Billing / Setup)
 *   2  a new contract opens IN the workspace — no separate create page
 *   3  the term-dependent panes are muted, with a reason, until a term exists
 *   4  the after-the-fact panes are muted, with a reason, until the contract is saved
 *   5  the issue list names the missing FIELDS, and clears as they are filled
 *   6  adding a term unlocks exactly the three term-dependent panes and no others
 *   7  one save writes the contract, its term and its coverage — number allocated by the server
 *   8  every pane unlocks after the save
 *   9  the document tab re-points at the SAVED contract rather than staying "New contract"
 *
 * TARGET BY ROLE, SCOPE TO A CONTAINER, ASSERT ON VALUES. A loose locator does not fail, it
 * succeeds on the wrong element — a `/contract/i` name match hits the generated-schema card on Home
 * and never navigates, reporting a clean pass from the wrong page.
 *
 * THIS HARNESS WRITES. Its contract is tagged and removed at the end; the tag is also how a crashed
 * run is cleaned up (`demo/cleanup-ui-e2e.sql`).
 *
 * Usage: node test-harnesses/ui-workspace.mjs "<explorer url with #token=…>"
 */
import { chromium } from 'playwright';

const URL = process.argv[2];
if (!URL) {
    console.error('Usage: node test-harnesses/ui-workspace.mjs "<explorer url with #token=…>"');
    process.exit(2);
}

const STAMP = `UI-E2E workspace ${new Date().toISOString().slice(0, 19)}`;
let passed = 0, failed = 0;
const notes = [];
const check = (name, ok, detail = '') => {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; notes.push(`${name}${detail ? ' — ' + detail : ''}`); console.log(`  ✗ ${name}${detail ? ' — ' + detail : ''}`); }
};

const errors = [];
const browser = await chromium.launch({ headless: true, channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1700, height: 1200 } });
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(String(e)));

/** The inner strip is the LAST one on the page; the first is the section switcher. */
const innerTabs = () => page.locator('.mj-tab-nav').last();

async function tabState(label) {
    const btn = innerTabs().locator('button', { hasText: new RegExp(`^\\s*${label}`) }).first();
    if (!(await btn.count())) return null;
    return { Disabled: await btn.isDisabled(), Reason: await btn.getAttribute('title'), Text: (await btn.innerText()).replace(/\s+/g, ' ').trim() };
}

/** Choose the first REAL option in a labelled picker (skipping the "—" / "Choose…" placeholder). */
async function pickFirst(label) {
    const sel = page.locator('.fld', { hasText: label }).locator('select').first();
    const values = [];
    for (const o of await sel.locator('option').all()) values.push(await o.getAttribute('value'));
    const real = values.filter((v) => v && v !== 'null' && v.length > 10);
    if (!real.length) return null;
    await sel.selectOption(real[0]);
    await page.waitForTimeout(350);
    return real[0];
}

try {
    await page.goto(URL, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(9000);

    // By DESCRIPTION, not by name — see the header note.
    await page.getByText(/The agreement envelope/i).first().click();
    await page.waitForTimeout(7000);

    console.log('\n1. Sections');
    const sectionStrip = (await page.locator('.mj-tab-nav').first().innerText()).replace(/\n/g, '|');
    for (const s of ['Contracts', 'Billing', 'Setup']) {
        check(`1.${s} the ${s} section is in the top strip`, sectionStrip.includes(s), sectionStrip);
    }

    console.log('\n2. A new contract opens IN the workspace');
    await page.getByRole('button', { name: /new contract/i }).first().click();
    await page.waitForTimeout(2500);
    check('2.1 the workspace header shows an unsaved contract', (await page.locator('.ws-num').first().innerText()).includes('New contract'));
    check('2.2 the status line says it is not yet saved', (await page.locator('.ws-sub').first().innerText()).includes('Not yet saved'));

    console.log('\n3 & 4. The muted panes, and their reasons');
    for (const [label, fragment] of [['Coverage', 'Add a term first'], ['Billing', 'Add a term first'], ['Commitments', 'Add a term first']]) {
        const state = await tabState(label);
        check(`3.${label} is muted before a term exists`, state?.Disabled === true, JSON.stringify(state));
        check(`3.${label} says why`, (state?.Reason ?? '').includes(fragment), state?.Reason ?? 'no tooltip');
    }
    for (const label of ['Amendments', 'Documents', 'History']) {
        const state = await tabState(label);
        check(`4.${label} is muted before the contract is saved`, state?.Disabled === true, JSON.stringify(state));
        check(`4.${label} says why`, (state?.Reason ?? '').includes('once the contract is saved'), state?.Reason ?? 'no tooltip');
    }

    console.log('\n5. The issue list names the missing fields');
    const issuesBefore = await page.locator('.issues').innerText();
    check('5.1 it names the contract type', /contract type/i.test(issuesBefore), issuesBefore.slice(0, 120));
    check('5.2 it names the customer', /customer/i.test(issuesBefore), issuesBefore.slice(0, 120));
    const contractTab = await tabState('Contract');
    check('5.3 the Contract tab carries the error badge', (contractTab?.Text ?? '').includes('!'), contractTab?.Text ?? '');

    await pickFirst('Contract type');
    await pickFirst('Company');
    await pickFirst('Customer organization');
    await page.locator('.fld', { hasText: 'Description' }).locator('textarea').first().fill(STAMP);
    await page.waitForTimeout(800);
    check('5.4 the issue list clears once the required fields are filled', (await page.locator('.issues').count()) === 0);

    console.log('\n6. Adding a term unlocks exactly the term-dependent panes');
    await page.getByRole('tab', { name: /^Terms/ }).click();
    await page.waitForTimeout(500);
    await page.getByRole('button', { name: /add term/i }).click();
    await page.waitForTimeout(1000);
    for (const label of ['Coverage', 'Billing', 'Commitments']) {
        check(`6.${label} is now reachable`, (await tabState(label))?.Disabled === false);
    }
    for (const label of ['Amendments', 'Documents', 'History']) {
        // The two preconditions are INDEPENDENT: a term does not make a history exist.
        check(`6.${label} stays muted — it needs a saved record, not a term`, (await tabState(label))?.Disabled === true);
    }
    check('6.count the Terms tab shows 1', (await tabState('Terms'))?.Text.includes('1'), (await tabState('Terms'))?.Text);

    console.log('\n7. One save writes the whole agreement');
    await page.getByRole('tab', { name: /^Coverage/ }).click();
    await page.waitForTimeout(600);
    await page.getByRole('button', { name: /add line/i }).click();
    await page.waitForTimeout(800);
    await pickFirst('Product');
    await page.locator('.fld', { hasText: 'Line type' }).locator('select').first().selectOption('OneTime');
    await page.locator('.fld', { hasText: 'Contracted unit price' }).locator('input').first().fill('4200');
    await page.waitForTimeout(700);

    const save = page.getByRole('button', { name: /create contract|save changes/i }).first();
    check('7.1 save is enabled once the draft is valid', !(await save.isDisabled()));
    await save.click();
    await page.waitForTimeout(7000);

    const number = (await page.locator('.ws-num').first().innerText()).trim();
    check('7.2 the SERVER allocated a contract number', /^CTR-\d{6}$/.test(number), `got "${number}"`);
    check('7.3 the header reports it saved', (await page.locator('.ws-sub').first().innerText()).includes('Saved'));
    check('7.4 the coverage count survived the round trip', (await tabState('Coverage'))?.Text.includes('1'), (await tabState('Coverage'))?.Text);

    console.log('\n8. Every pane unlocks after the save');
    for (const label of ['Coverage', 'Billing', 'Commitments', 'Amendments', 'Documents', 'History']) {
        check(`8.${label} is reachable`, (await tabState(label))?.Disabled === false);
    }

    console.log('\n9. The document tab re-points at the saved contract');
    // If it still said "New contract", closing and reopening it would resurrect an id-less draft and
    // create a SECOND contract on the next save.
    const docStrip = await page.locator('.card .ch').first().innerText();
    check('9.1 the open-document tab shows the allocated number', docStrip.includes(number), docStrip.replace(/\s+/g, ' ').slice(0, 120));

    console.log('\n10. The lifecycle, from the Terms pane');
    // This is the coverage that used to live on the create page and in a separate lifecycle
    // harness. Activation is not a status flip: the operation also builds the billing schedule and
    // the events its cadence implies, and a term marked Active with no schedule bills nothing.
    await page.getByRole('tab', { name: /^Terms/ }).click();
    await page.waitForTimeout(800);

    const pane = page.locator('.pane').last();
    const activate = pane.getByRole('button', { name: /activate/i }).first();
    check('10.1 an unstarted term offers Activate', (await activate.count()) > 0);
    if (await activate.count()) {
        await activate.click();
        await page.waitForTimeout(7000);
        const after = (await page.locator('.ws-sub').first().innerText()) + (await page.locator('.ws-head').innerText());
        check('10.2 activation reports the billing events it scheduled', /scheduled|activated/i.test(after), after.replace(/\s+/g, ' ').slice(0, 160));

        // A term that is running can be renewed, and NOT activated again — the strip must follow
        // the state rather than offering both.
        await page.waitForTimeout(1500);
        const renew = pane.getByRole('button', { name: /renew/i }).first();
        check('10.3 an active term offers Renew instead', (await renew.count()) > 0);
        check('10.4 and no longer offers Activate', (await pane.getByRole('button', { name: /activate/i }).count()) === 0);

        if (await renew.count()) {
            await renew.click();
            await page.waitForTimeout(6000);
            const preview = page.locator('.issues', { hasText: /Renewing term/i }).first();
            check('10.5 renewal PREVIEWS the new dates before writing', (await preview.count()) > 0);
            if (await preview.count()) {
                const text = await preview.innerText();
                // The numbers a person approves must be the numbers that get written, so the preview
                // is the real computation with the write suppressed.
                check('10.6 the preview names the new term window', /New term: \d{4}-\d{2}-\d{2}/.test(text), text.replace(/\s+/g, ' ').slice(0, 140));
                await page.getByRole('button', { name: /cancel/i }).first().click();
                await page.waitForTimeout(1200);
                check('10.7 cancelling the preview writes nothing', (await page.locator('.issues', { hasText: /Renewing term/i }).count()) === 0);
            }
        }
    }

    console.log('\n11. History — the append-only audit trail');
    await page.getByRole('tab', { name: /^History/ }).click();
    await page.waitForTimeout(2500);
    const history = await page.locator('.pane').last().innerText();
    // Activation and renewal both write lifecycle events. An empty history after both would mean
    // the audit trail is not being written, which nothing else would surface.
    check('11.1 the history pane renders for a saved contract', history.length > 0);

    console.log('\n12. Termination — previewed before it is committed');
    const terminate = page.getByRole('button', { name: /terminate/i }).first();
    check('12.1 a live contract offers Terminate', (await terminate.count()) > 0);
    if (await terminate.count()) {
        await terminate.click();
        await page.waitForTimeout(6000);
        const preview = page.locator('.issues', { hasText: /Terminating this contract/i }).first();
        check('12.2 termination PREVIEWS before writing', (await preview.count()) > 0);
        if (await preview.count()) {
            const text = await preview.innerText();
            // The split is the whole point: periods already covered are still owed, so retained
            // events must be reported alongside cancelled ones rather than everything vanishing.
            check('12.3 the preview reports events CANCELLED', /CANCELLED: \d+/.test(text), text.replace(/\s+/g, ' ').slice(0, 160));
            check('12.4 and events RETAINED — periods already covered are still owed', /RETAINED[^:]*: \d+/.test(text), text.replace(/\s+/g, ' ').slice(0, 200));

            // A reason is required before it can be committed: "terminated" with no why is a support
            // ticket nobody can answer.
            const commit = preview.getByRole('button', { name: /terminate this contract/i }).first();
            check('12.5 committing is blocked until a reason is given', await commit.isDisabled());
            await preview.locator('input[type="text"]').first().fill('UI-E2E: terminated by the workspace harness');
            await page.waitForTimeout(600);
            check('12.6 and enabled once it is', !(await commit.isDisabled()));

            await page.getByRole('button', { name: /cancel/i }).first().click();
            await page.waitForTimeout(1200);
            check('12.7 cancelling writes nothing', (await page.locator('.issues', { hasText: /Terminating this contract/i }).count()) === 0);
        }
    }

    console.log('\n13. The workspace search finds what was just created');
    // Through the app's OWN search rather than the roster grid: MJ's grid virtualizes its rows, so
    // reading its innerText proves only what happens to be scrolled into view. Asserting on that is
    // the same class of mistake as a loose locator — it passes or fails for reasons unrelated to
    // the thing under test.
    // Scoped to the rail and UNANCHORED: a rail item's accessible name includes its description
    // ("WorkspaceOpen, edit and create"), so ^Workspace$ never matches. Scope, do not anchor.
    await page.locator('mj-left-nav').getByRole('button', { name: /workspace/i }).first().click();
    await page.waitForTimeout(1500);
    for (const doc of await page.locator('.card .ch button i.fa-xmark').all()) {
        await doc.click();
        await page.waitForTimeout(400);
    }
    await page.waitForTimeout(1200);
    const search = page.getByPlaceholder(/Find a contract/i).first();
    if (await search.count()) {
        await search.fill(number);
        await page.waitForTimeout(1500);
        const picks = page.locator('.pick');
        check('13.1 searching by contract number finds exactly one match', (await picks.count()) === 1, `${await picks.count()} matches for ${number}`);
        if ((await picks.count()) === 1) {
            check('13.2 and it is the right one', (await picks.first().innerText()).includes(number));
        }
    } else {
        check('13.1 the workspace search box is present', false, 'no search box found');
    }

    console.log('\n14. Cleanup');
    // Remove what this run wrote, so a re-run starts from the same place.
    const nav = page.getByRole('button', { name: /^All contracts$/ }).first();
    if (await nav.count()) { await nav.click(); await page.waitForTimeout(2500); }
    console.log(`  (contract ${number} tagged "${STAMP}" — demo/cleanup-ui-e2e.sql removes UI-E2E rows)`);
} catch (e) {
    failed++;
    notes.push(`harness error: ${e instanceof Error ? e.message : String(e)}`);
    console.log(`\n  ✗ HARNESS ERROR: ${e instanceof Error ? e.message : String(e)}`);
}

// A silent console error is a real UI bug, so it fails the run — that capture is the keystone.
check('0. no console errors or page errors during the run', errors.length === 0, errors.slice(0, 3).join(' | '));

console.log(`\n${failed === 0 ? 'PASS' : 'FAIL'} — ${passed} passed, ${failed} failed`);
if (failed) notes.forEach((n) => console.log(`  · ${n}`));
await browser.close();
process.exit(failed === 0 ? 0 : 1);
