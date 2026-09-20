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
const KIT = readFileSync(root('packages/Angular/src/lib/styles/contracts-kit.css'), 'utf8');

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

    it('and exactly once — no stat label is rendered twice', () => {
        /*
         * THIS CAUGHT NOTHING AND SHOULD HAVE. The header carried TWO identical Company blocks after
         * the rebase: `next` already had the stat from its own item-8 work, and re-applying this
         * branch's version inserted a second one next to it. Neither git nor CI could see it — the two
         * insertions were adjacent rather than overlapping, so there was no conflict, and CI runs
         * build-only, so duplicate markup compiles. `toContain` above passes on a duplicate too.
         *
         * Generalised rather than pinned to Company. A duplicated stat is what a rebase against a
         * branch solving the same issue produces, and the next one will not necessarily be this stat.
         */
        const labels = statLabels();
        expect(labels).toEqual([...new Set(labels)]);
    });

    it('and comes before the customer', () => {
        const labels = statLabels();
        const company = labels.indexOf('Company');
        const customer = labels.indexOf('Customer');
        expect(company).toBeGreaterThan(-1);
        expect(customer).toBeGreaterThan(company);
    });

    it('and wherever the DisplayName comes from, it is "Company"', () => {
        /*
         * THIS ASSERTION USED TO RUN THE OTHER WAY, and the flip is worth recording rather than
         * quietly making. It required the metadata file to hold NO `CompanyID` entry, on the finding
         * that CodeGen strips a trailing `ID` from a foreign key — so `CompanyID` already reads
         * "Company", the same rule that makes `CustomerOrganizationID` read "Customer Organization",
         * and measured on BizAppsDev a sync push reported no changes.
         *
         * That finding still holds; it was never the point. The issue asked for the DisplayName to be
         * "Company", and `next` ships it declared explicitly. Redundant with what CodeGen derives is
         * not the same as wrong, and a test that FAILS when someone states the intended value outright
         * is testing the mechanism rather than the outcome. So this pins the outcome: if the entry
         * exists it must say "Company", and if it does not, CodeGen's rule already produces it.
         */
        const meta = readFileSync(root('metadata/entity-fields/.entity-fields.json'), 'utf8');
        const entries: Array<{ primaryKey?: { ID?: string }; fields?: { DisplayName?: string } }> =
            JSON.parse(meta);
        const company = entries.filter((e) => e.primaryKey?.ID?.endsWith('Name=CompanyID'));
        expect(company.length).toBeLessThanOrEqual(1);
        for (const e of company) expect(e.fields?.DisplayName).toBe('Company');
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

describe('item 1 — the source record, as a chip on the shared Related row', () => {
    /*
     * WHY THESE ASSERTIONS MOVED RATHER THAN WENT AWAY (golive#225). They used to name this panel's
     * own resolver — `loadSource`, `SourceMissing`, the race guard — because the panel resolved the
     * source record itself. It no longer does: the resolving, and with it the two rules about when a
     * link must NOT be drawn, are `bizapps-related-chips`' and are pinned by `related-links.test.ts`
     * in `bizapps-common`. Item 1's guarantees still have to hold on THIS form, so they are re-aimed
     * at the half the panel kept — which relationship a contract offers, and that it is described
     * rather than resolved — plus the wiring that hands the other half over. Deleting them would
     * have left the delegation itself unpinned, which is the thing a future edit is most likely to
     * undo by quietly resolving the record here again.
     */

    /** The body of the getter that builds the chip descriptors. */
    const relatedLinks = (): string => {
        const fn = PANELS_RAW.slice(PANELS_RAW.indexOf('public get RelatedLinks()'));
        return fn.slice(0, fn.indexOf('\n    }'));
    };

    it('offers nothing at all when nothing created this contract', () => {
        // An EMPTY descriptor list is how the panel says "no relationship"; the shared row renders
        // nothing for it. That is what item 1 asked for in place of a stat reading "Entered
        // directly", which spent a slot announcing the absence of a fact.
        expect(relatedLinks()).toContain('if (!entityID || !recordID)');
        expect(relatedLinks()).toContain('this.relatedLinks = [];');
        expect(PANELS).not.toContain('Entered directly');
        expect(PANELS_RAW).not.toContain('get CreatingEntityName()');
    });

    it('leaves the label to the resolved entity, never a hardcoded "Deal"', () => {
        // `LabelPrefix` has the shared row compose the prefix with the entity's own singular name, so
        // a pair naming Orders reads "Source Order" with no edit here. A literal `Label` on this
        // descriptor would be exactly the hardcoding item 1 ruled out: the pair is polymorphic, and
        // sales being its only writer today is not a promise about tomorrow.
        expect(relatedLinks()).toContain("LabelPrefix: 'Source'");
        expect(relatedLinks()).not.toMatch(/\bLabel:/);
        expect(PANELS_RAW).not.toContain('this.SourceLabel');
    });

    it('looks the entity up by CreatingEntityID rather than assuming one', () => {
        // The one lookup that stays here, and the reason it does: the chip row addresses entities by
        // NAME and the provenance pair holds an entity ID.
        expect(relatedLinks()).toContain('e.ID === entityID');
        expect(relatedLinks()).toContain('EntityName: entity.Name');
    });

    it("routes navigation through the form's own path, as Customer and Contact do", () => {
        // The chip row emits instead of navigating, and the host wires it to `OnFormNavigate` — the
        // same path every field link in this file takes, and still not `NavigationService`.
        expect(PANELS).toMatch(/\(Navigate\)="FormComponent\.OnFormNavigate\(\$event\)"/);
        expect(PANELS).not.toContain('NavigationService');
    });

    it('hands the dead-link rules to the shared row rather than dropping them', () => {
        /*
         * Both hiding rules item 1 asked for are now the component's: no chip when the pair is null,
         * and no chip when the pair names a row that is not there — CTR-000026 carries a hand-typed
         * pair whose record id is not even a UUID, and the header used to offer an "Open" button that
         * navigated nowhere. Those are enforced in common; what has to be true here is that the row
         * is actually rendered and actually given what it needs to enforce them. A chip row bound
         * without a provider resolves against the ambient one, which in a multi-provider host reads
         * the wrong database — a wrong answer rather than an error.
         */
        expect(PANELS_RAW).toContain("from '@mj-biz-apps/common-ng'");
        expect(PANELS).toContain('<bizapps-related-chips');
        expect(PANELS).toMatch(/\[Links\]="RelatedLinks"/);
        expect(PANELS).toMatch(/\[Provider\]="FormComponent\.ProviderToUse"/);
    });

    it('and cannot re-implement them here by accident', () => {
        // The distinction the old code got wrong twice — a read that SUCCEEDS and matches nothing
        // versus a read that THREW — is only safe in one place. This panel reads no record for this
        // link at all now, so there is nothing here to get it wrong in a second way.
        expect(PANELS_RAW).not.toContain('loadSource');
        expect(PANELS_RAW).not.toContain('SourceMissing');
        expect(relatedLinks()).not.toContain('RunView');
    });

    it('cannot show the previous contract a chip belonging to the last one', () => {
        /*
         * The stale-answer hazard survived the refactor in a new shape. The old resolver raced a slow
         * read against form navigation; the getter instead CACHES, and a cache is stale for the same
         * reason. Two rules keep it honest: the key carries the record id as well as the pair, so
         * navigating to another contract is a different key — and an EMPTY entity catalog is never
         * cached as an answer, because it means metadata has not landed yet, not that this contract
         * has no source. The array reference is stable for a reason of its own: the chip row
         * re-resolves whenever `Links` is a new reference, so a getter building a fresh array each
         * change-detection pass would put it in a read loop.
         */
        expect(relatedLinks()).toContain('`${this.Record?.ID}:${entityID}:${recordID}`');
        expect(relatedLinks()).toContain('if (this.relatedFor === key) return this.relatedLinks;');
        expect(relatedLinks()).toContain('entities.length === 0');
    });
});

describe('item 21 — zero is a value, and auto-renew is a term', () => {
    it('day counts and percentages render 0 rather than an em dash', () => {
        for (const fnName of ['public Days(', 'public Percent(']) {
            const fn = PANELS_RAW.slice(PANELS_RAW.indexOf(fnName));
            expect(fn.slice(0, fn.indexOf('\n    }'))).toContain('v == null');
        }
        expect(PANELS).not.toContain('Record.RenewalNoticeDays ? Record.RenewalNoticeDays');
        expect(PANELS).not.toContain('Record.CancellationWindowDays ? Record.CancellationWindowDays');
    });

    it('the empty state includes AutoRenew, so it cannot contradict the screen', () => {
        const g = PANELS_RAW.slice(PANELS_RAW.indexOf('public get NoTermsRecorded()'));
        const body = g.slice(0, g.indexOf('\n    }'));
        for (const f of ['AutoRenew', 'RenewalNoticeDays == null', 'CancellationWindowDays == null',
                         'AnnualIncreasePercent == null']) {
            expect(body).toContain(f);
        }
    });
});

describe('item 5 — the panel half, now that the kit rule carries the width', () => {
    it('no inline width remains in the panels', () => {
        expect(PANELS_RAW).not.toContain('style="width:100%"');
    });

    it('because the kit rule provides it', () => {
        const start = KIT.indexOf('.mjc-field input,');
        expect(start).toBeGreaterThan(-1);
        expect(KIT.slice(start, KIT.indexOf('}', start))).toContain('width: 100%');
    });
});
