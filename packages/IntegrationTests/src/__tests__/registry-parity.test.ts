/**
 * THE ANTI-VACUITY FLOOR. Adapted from bizapps-orders.
 *
 * A suite that runs FEWER checks than it has looks exactly like a suite that passes. That is the
 * failure this file exists to make impossible, and it arrives by more routes than one:
 *
 *   - a bundle added to `checks/` but never imported by `index.ts` — its checks simply do not exist
 *     at runtime, and the total silently drops
 *   - a bundle renamed on one side of the `contracts-` prefix convention, so `GetBundle` returns
 *     nothing and the runner reports a bundle of zero
 *   - a check removed or commented out mid-refactor
 *   - a `.only` left in a file, silencing its siblings
 *
 * Every one of those is GREEN. None of them is caught by asserting that the checks which ran passed.
 *
 * So this asserts the shape of the registry itself against numbers written down here, and
 * `scripts/assert-check-count.mjs` asserts that a real RUN executed that many. Two gates, one
 * source of truth: change a bundle and this test fails first, which is what stops the expected
 * numbers from being quietly "corrected" to match a suite that shrank.
 *
 * WHEN YOU ADD A CHECK, update EXPECTED below. That edit is the point — it is a deliberate,
 * reviewable statement that the suite grew, rather than a number that follows whatever happened.
 */
import { describe, it, expect } from 'vitest';
import { IntegrationCheckRegistry } from '@memberjunction/testing-integration';
import '../index.js';

/**
 * Bundle id → the number of checks it must contain.
 *
 * Ids carry the `contracts-` prefix deliberately: the registry is a process-global `BaseSingleton`,
 * and an instance with orders dev-linked alongside us loads both apps' bundles into it. Orders owns
 * a bundle called `composition` too — without the prefix, `GetBundle('composition')` would hand back
 * both apps' checks as one bundle.
 */
const EXPECTED: Record<string, number> = {
    'contracts-composition': 16,
    'contracts-save-contract': 9,
    'contracts-billing': 15,
    'contracts-amendment': 8,
};

const TOTAL = Object.values(EXPECTED).reduce((a, b) => a + b, 0);

describe('integration registry parity', () => {
    it('registers exactly the bundles this app declares — no more, no fewer', () => {
        const registered = IntegrationCheckRegistry.Instance.GetBundleNames()
            .filter((n) => n.startsWith('contracts-'))
            .sort();
        expect(registered).toEqual(Object.keys(EXPECTED).sort());
    });

    for (const [bundle, count] of Object.entries(EXPECTED)) {
        it(`${bundle} contains ${count} checks`, () => {
            const checks = IntegrationCheckRegistry.Instance.GetBundle(bundle);
            expect(checks, `bundle '${bundle}' is not registered — is it imported in index.ts?`).toBeDefined();
            expect(checks!.length).toBe(count);
        });
    }

    it('every check id is unique and namespaced to its bundle', () => {
        // Two checks sharing an id means one of them can never be addressed individually, and
        // `mj test run <id>` would silently run the wrong one.
        const ids: string[] = [];
        for (const bundle of Object.keys(EXPECTED)) {
            for (const check of IntegrationCheckRegistry.Instance.GetBundle(bundle) ?? []) {
                ids.push(check.Id);
                expect(check.Id.startsWith(`${bundle}.`), `check '${check.Id}' is not namespaced to '${bundle}'`).toBe(true);
            }
        }
        expect(new Set(ids).size).toBe(ids.length);
    });

    it(`declares ${TOTAL} checks in total — the number scripts/assert-check-count.mjs enforces at run time`, () => {
        const actual = Object.keys(EXPECTED)
            .reduce((n, b) => n + (IntegrationCheckRegistry.Instance.GetBundle(b)?.length ?? 0), 0);
        expect(actual).toBe(TOTAL);
    });
});
