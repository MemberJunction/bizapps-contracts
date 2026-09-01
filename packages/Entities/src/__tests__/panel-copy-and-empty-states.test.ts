/**
 * The form's copy, its empty states, and the two message bugs — issue #28 items 19, 21, 23 and 24.
 *
 * Item 19 replaces twelve pieces of developer-facing prose with copy the issue fixes VERBATIM, so
 * these are string tests and unapologetically so: the value delivered IS the exact wording, and a
 * test that checked "some text is present" would pass on a paraphrase, which is the thing being
 * removed. Where the issue says delete, the assertion is that the old sentence is gone.
 *
 * Items 21 and 23 are logic, and both are the same shape of bug — a check that conflates two
 * different states. `!Record.RenewalNoticeDays` conflates "zero" with "absent"; a `loaded` boolean
 * conflates "this record's list" with "some record's list". Both are pinned by structure rather than
 * by rendering, because neither needs a component to be true or false.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const PANELS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');
const SUPERSEDE_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/supersede.panel.ts'), 'utf8');
const FILES_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/record-files.panel.ts'), 'utf8');

/* Commentary removed: these panels quote the copy they replaced, so a whole-file search reports the
 * explanation as the defect. Presence checks are unaffected; absence checks need this. */
const PANELS = strip(PANELS_RAW);
const SUPERSEDE = strip(SUPERSEDE_RAW);
const FILES = strip(FILES_RAW);

describe('item 19 — the replacements, verbatim', () => {
    it.each([
        ['hero, contract number', PANELS, 'Contract number is assigned on save.'],
        ['dates, terminated', PANELS, 'Setting this marks the contract Terminated from this date.'],
        ['lineage, empty state', PANELS, 'No parent contract, change orders, or superseding contracts.'],
        ['documents, signing provider', FILES, 'Open in signing provider'],
        ['documents, no permission', FILES, "document(s) attached. You don't have permission to open them."],
        ['documents, no storage', FILES, 'No document storage is configured. Contact your administrator.'],
        ['re-papering, saved chip', SUPERSEDE, 'Finish editing to change'],
        ['re-papering, unsaved chip', SUPERSEDE, 'Save this contract first'],
    ])('%s', (_label, source, copy) => {
        expect(source).toContain(copy);
    });

    it.each([
        ['minted under a lock', PANELS, 'from a counter taken under a lock'],
        ['lifecycle is derived', PANELS, 'The lifecycle is <strong>derived</strong>'],
        ['executed may precede', PANELS, 'that is normal, not an anomaly'],
        ['orders holds the operational setting', PANELS, 'a mismatch is a finding, not a bug'],
        ['renewals watchlist', PANELS, 'renewals watchlist'],
        ['someone must act', PANELS, 'someone must act for this to continue'],
        ['standalone agreement', PANELS, 'A standalone agreement'],
        ['always-works fallback', FILES, 'the always-works fallback'],
        ['granted to finance, legal', FILES, 'finance, legal and sales leadership'],
        ['Azure AD app registration', FILES, 'Azure AD app registration'],
    ])('deleted: %s', (_label, source, copy) => {
        expect(source).not.toContain(copy);
    });

    it('renewal empty state is that sentence and nothing more', () => {
        // A substring check passes on the OLD copy, which began with the same sentence and then went
        // on about the renewals watchlist. The whole element is what changed, so assert the element.
        expect(PANELS).toContain('<div class="mjc-empty">No renewal terms recorded.</div>');
    });

    it('keeps the "as stated in the agreement" chip the issue says to leave', () => {
        expect(PANELS).toContain('as stated in the agreement');
    });
});

describe('item 21 — zero is a value, and auto-renew is a term', () => {
    it('day counts and percentages render 0 rather than an em dash', () => {
        const days = PANELS_RAW.slice(PANELS_RAW.indexOf('public Days('));
        expect(days.slice(0, days.indexOf('\n    }'))).toContain('v == null');
        const pct = PANELS_RAW.slice(PANELS_RAW.indexOf('public Percent('));
        expect(pct.slice(0, pct.indexOf('\n    }'))).toContain('v == null');
        // The falsy checks that hid a recorded zero must be gone from the template.
        expect(PANELS).not.toContain("Record.RenewalNoticeDays ? Record.RenewalNoticeDays");
        expect(PANELS).not.toContain("Record.CancellationWindowDays ? Record.CancellationWindowDays");
    });

    it('the empty state includes AutoRenew, so it cannot contradict the screen', () => {
        const g = PANELS_RAW.slice(PANELS_RAW.indexOf('public get NoTermsRecorded()'));
        const body = g.slice(0, g.indexOf('\n    }'));
        expect(body).toContain('AutoRenew');
        expect(body).toContain('RenewalNoticeDays == null');
        expect(body).toContain('CancellationWindowDays == null');
        expect(body).toContain('AnnualIncreasePercent == null');
    });
});

describe('item 23 — messages and lists do not outlive what they describe', () => {
    it('changing the selection clears the previous outcome', () => {
        expect(SUPERSEDE).toContain('(ngModelChange)="PickPredecessor($event)"');
        const fn = SUPERSEDE_RAW.slice(SUPERSEDE_RAW.indexOf('public PickPredecessor('));
        const body = fn.slice(0, fn.indexOf('\n    }'));
        expect(body).toContain("this.LinkOk = ''");
        expect(body).toContain("this.LinkError = ''");
    });

    it('the candidate list is keyed on the record, not a bare boolean', () => {
        expect(SUPERSEDE_RAW).toContain('private loadedFor: string | null = null;');
        expect(SUPERSEDE_RAW).toContain('this.loadedFor !== id');
        // A boolean would leave the previous contract's candidates on screen after navigation.
        expect(SUPERSEDE_RAW).not.toMatch(/private loaded = false;/);
    });

    it('a later successful load clears an earlier failure (done with item 4)', () => {
        const fn = SUPERSEDE_RAW.slice(SUPERSEDE_RAW.indexOf('private async loadCandidates()'));
        expect(fn).toContain("this.LoadError = '';");
    });
});

describe('item 24 — the dead banner', () => {
    it('is gone, and nothing replaced it', () => {
        expect(PANELS_RAW).not.toContain('5 · Policy');
        expect(PANELS_RAW.trimEnd().endsWith('}')).toBe(true);
    });
});
