/**
 * The audit trail renders as a readable timeline, with real detail from the event payloads.
 *
 * Worth its own check because the History tab is where the invariant work becomes visible: the log
 * is append-only and its vocabulary is closed, and the tab should SAY so next to entries a person
 * can actually read. A grid of raw EventType strings and JSON blobs would technically display the
 * same data and communicate none of it.
 */
import { chromium } from 'playwright';
const URL = process.argv[2];
let passed = 0, failed = 0; const notes = [];
const check = (n, ok, d='') => { if (ok) { passed++; console.log(`  ✓ ${n}`); } else { failed++; notes.push(`${n}${d?' — '+d:''}`); console.log(`  ✗ ${n}${d?' — '+d:''}`); } };
const errors = [];
const b = await chromium.launch({ headless: true, channel: 'chrome' });
const p = await b.newPage({ viewport: { width: 1600, height: 1100 } });
p.on('console', m => { if (m.type()==='error' && !/favicon|\.ico|\.map/i.test(m.text())) errors.push(m.text()); });
p.on('pageerror', e => errors.push(String(e)));
try {
    await p.goto(URL, { waitUntil: 'domcontentloaded' });
    await p.waitForTimeout(9000);
    await p.getByText(/The agreement envelope/i).first().click();
    await p.waitForTimeout(8000);
    await p.locator('[role="row"]').nth(1).click();
    await p.waitForTimeout(3500);
    await p.getByRole('button', { name: /^history/i }).first().click();
    await p.waitForTimeout(3000);

    const tl = await p.locator('.ev').count();
    check('A.1 the audit timeline renders entries', tl > 0, `${tl} entries`);
    const text = await p.locator('.cb').first().innerText().catch(() => '');
    check('A.2 event types read as sentences, not enum strings', /Term activated|Term renewed|Contract executed/i.test(text), text.slice(0, 200));
    check('A.3 raw enum strings are NOT shown', !/TermActivated|ContractExecuted/.test(text), text.slice(0, 200));
    check('A.4 the immutability guarantee is stated on the tab', (await p.getByText(/append-only and enforced/i).count()) > 0);
    check('A.5 no console errors', errors.length === 0, errors.slice(0,2).join(' | '));
    await p.screenshot({ path: 'test-harnesses/ui-history.png' });
} catch (e) { failed++; notes.push('HARNESS: '+e.message); console.log('  ✗ HARNESS: '+e.message); }
console.log(`\n${failed===0?'PASS':'FAIL'} — ${passed} passed, ${failed} failed`);
notes.forEach(n => console.log('  · '+n));
await b.close();
process.exit(failed===0?0:1);
