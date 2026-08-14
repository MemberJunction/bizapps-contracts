#!/usr/bin/env node
/**
 * Fail when FEWER integration checks RAN than the registry declares. Adapted from bizapps-orders.
 *
 * WHY A PASSING RUN IS NOT ENOUGH. `registry-parity.test.ts` proves the registry has 48 checks in
 * it. It cannot prove that a RUN executed them. Those come apart in ways that all look green:
 *
 *   - a bundle whose `Setup` throws is reported as one failure and its checks never execute
 *   - a bundle dropped from the runner's list simply vanishes from the output
 *   - a filter or a stray early return silences a file
 *   - the run dies partway and the summary still prints what it got to
 *
 * So the parity test guards the registry and this guards the run, both against the SAME number.
 * Neither can be quietly "corrected" to match a suite that shrank without the other one objecting.
 *
 * Usage:  node test-harnesses/integration.mjs 2>&1 | tee /tmp/integration.log
 *         node scripts/assert-check-count.mjs /tmp/integration.log
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const logPath = process.argv[2];

if (!logPath) {
    console.error('usage: node scripts/assert-check-count.mjs <integration-log>');
    process.exit(2);
}

/**
 * The expected total, parsed out of the parity test so there is exactly ONE source of truth.
 *
 * Reading it rather than restating it is the whole point: a second hardcoded number here could
 * drift into agreeing with a shrunken suite, which is the failure this file exists to prevent.
 */
function expectedTotal() {
    const src = readFileSync(join(root, 'packages/IntegrationTests/src/__tests__/registry-parity.test.ts'), 'utf8');
    const block = src.match(/const EXPECTED[^=]*=\s*\{([\s\S]*?)\};/);
    if (!block) {
        console.error('::error::Could not find the EXPECTED map in registry-parity.test.ts — has it been renamed?');
        process.exit(2);
    }
    const counts = [...block[1].matchAll(/'([^']+)'\s*:\s*(\d+)/g)].map(([, name, n]) => [name, Number(n)]);
    if (counts.length === 0) {
        console.error('::error::EXPECTED map parsed but contained no bundles.');
        process.exit(2);
    }
    return { total: counts.reduce((a, [, n]) => a + n, 0), counts };
}

const { total, counts } = expectedTotal();
const log = readFileSync(logPath, 'utf8');

// The runner's final line: "PASS — 48 passed, 0 failed" / "FAIL — 41 passed, 7 failed".
// Colour codes are stripped first: the runner colourises on a terminal, and an anchored match
// silently fails against the escapes rather than reporting a mismatch.
const clean = log.replace(/\[[0-9;]*m/g, '');
const m = clean.match(/(?:PASS|FAIL)\s+—\s+(\d+)\s+passed,\s+(\d+)\s+failed/);

if (!m) {
    console.error(`::error::No result line found in ${logPath}. The run did not reach its summary — treat this as a failure, not a missing log.`);
    process.exit(1);
}

const ran = Number(m[1]) + Number(m[2]);

if (ran < total) {
    console.error(`::error title=Integration suite ran short::${ran} checks ran; the registry declares ${total}. ` +
        `A green tally is not evidence when ${total - ran} checks never executed.`);
    console.error('Declared per bundle:');
    for (const [name, n] of counts) console.error(`  ${name}: ${n}`);
    process.exit(1);
}

if (ran > total) {
    console.error(`::error title=Integration suite ran long::${ran} checks ran but the registry declares ${total}. ` +
        'Update EXPECTED in registry-parity.test.ts — deliberately, as a statement that the suite grew.');
    process.exit(1);
}

console.log(`✓ ${ran} checks ran, matching the ${total} the registry declares.`);
