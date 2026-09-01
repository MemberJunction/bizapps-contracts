/**
 * The hero's two parties and the form's copy — issue #28 items 8 and 19, re-applied.
 *
 * WHY THIS FILE IS A SECOND ATTEMPT. Both items shipped once, then `origin/next` rewrote
 * `contract.panels.ts` — a collapsible hero with its own stat grid, replacing the `mjc-hero__meta`
 * row these items were written against — and the merge took next's side. So the assertions are now
 * written against the stat grid, and the earlier file was deleted rather than adapted: a test that
 * still described the old markup would pass or fail for reasons unrelated to the guarantee.
 *
 * ITEM 8 IS TWO CHANGES AND ONLY ONE IS THE LABEL. "Selling" named no field a user could go looking
 * for — the column is `CompanyID` and every grid calls it Company. The ORDER matters too: our company
 * before the counterparty, which is how the agreement itself reads.
 *
 * ITEM 19'S DOCUMENTS ROWS ARE NOT HERE, and their absence is deliberate. The issue specifies three
 * replacements in `record-files.panel.ts`; next deleted that file in favour of MJ stock attachments
 * (3668a84), so there is nothing to assert. They need re-scoping against the new mechanism, not
 * quietly dropping — see the branch notes.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const PANELS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');

/* Commentary removed for absence checks: the panel quotes copy it replaced, so a whole-file search
 * reports the explanation as the defect. Presence checks are unaffected. */
const PANELS = PANELS_RAW.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

/** The hero stat labels, in render order. */
const statLabels = (): string[] =>
    [...PANELS.matchAll(/mjc-hero__stat-label">([^<]+)</g)].map((m) => m[1].trim());

describe('item 8 — the two parties, named and ordered', () => {
    it('the selling company is labelled Company', () => {
        expect(statLabels()).toContain('Company');
        expect(PANELS).not.toContain('>Selling<');
    });

    it('and comes before the customer', () => {
        const labels = statLabels();
        const company = labels.indexOf('Company');
        const customer = labels.indexOf('Customer');
        expect(company).toBeGreaterThan(-1);
        expect(customer).toBeGreaterThan(company);
    });

    it('needs no metadata entry — CodeGen already derives the DisplayName', () => {
        // CodeGen strips a trailing `ID` from a foreign key, so `CompanyID` already reads "Company";
        // `CustomerOrganizationID` reading "Customer Organization" is the same rule. Measured on
        // BizAppsDev: the column already held the target value and a sync push reported no changes.
        const meta = readFileSync(root('metadata/entity-fields/.entity-fields.json'), 'utf8');
        const entries: Array<{ primaryKey?: { ID?: string } }> = JSON.parse(meta);
        expect(entries.filter((e) => e.primaryKey?.ID?.endsWith('Name=CompanyID'))).toEqual([]);
    });
});

describe('item 19 — the replacements that still have a home', () => {
    it.each([
        ['hero, contract number', 'Contract number is assigned on save.'],
        ['dates, terminated', 'Setting this marks the contract Terminated from this date.'],
        ['renewal, empty state', '<div class="mjc-empty">No renewal terms recorded.</div>'],
        ['lineage, empty state', 'No parent contract, change orders, or superseding contracts.'],
    ])('%s', (_label, copy) => {
        expect(PANELS).toContain(copy);
    });

    it.each([
        ['minted under a lock', 'from a counter taken under a lock'],
        ['lifecycle is derived', 'The lifecycle is <strong>derived</strong>'],
        ['executed may precede', 'that is normal, not an anomaly'],
        ['terminated as a "fact"', 'a fact about what happened'],
        ['orders holds the operational setting', 'a mismatch is a finding, not a bug'],
        ['renewals watchlist', 'renewals watchlist'],
        ['someone must act', 'someone must act for this to continue'],
        ['standalone agreement', 'A standalone agreement'],
    ])('deleted: %s', (_label, copy) => {
        expect(PANELS).not.toContain(copy);
    });

    it('keeps the "as stated in the agreement" chip the issue says to leave', () => {
        expect(PANELS).toContain('as stated in the agreement');
    });
});
