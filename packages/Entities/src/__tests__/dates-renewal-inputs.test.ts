/**
 * Edit controls match the read-mode value box, and the two notice fields state their direction —
 * issue #28 items 5 and 6.
 *
 * TRIMMED AND THEN RESTORED, which is worth recording because the gap was real. When `origin/next`
 * was merged taking its side of `contract.panels.ts`, both items were reverted with that file and
 * these assertions were deleted rather than left failing. The re-apply that followed covered items
 * 1, 8, 19, 21 and item 5's panel half — and MISSED item 6 entirely, leaving only its `DisplayName`
 * metadata. Nothing failed, because the tests that would have caught it had been deleted alongside
 * the code. Caught in review of PR #36, not here.
 *
 * The lesson is in the shape of this file rather than a comment: deleting a test with the code it
 * covered removes the thing that would notice the code never came back. Where a revert is expected
 * to be re-applied, the assertions are the checklist.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const KIT = readFileSync(root('packages/Angular/src/lib/styles/contracts-kit.css'), 'utf8');
const PANELS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');

/* Commentary removed for absence checks: the panel quotes the label it replaced, in order to explain
 * why the direction moved into a hint, so a whole-file search reports the explanation as the defect. */
const PANELS = PANELS_RAW.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

/** The `.mjc-field input, .mjc-field select` rule body. Lazy, so a missing rule fails one test. */
const inputRule = (): string => {
    const start = KIT.indexOf('.mjc-field input,');
    if (start < 0) return '';
    return KIT.slice(start, KIT.indexOf('}', start));
};

describe('item 5 — the kit styles bare form controls like the value box', () => {
    it('the rule exists and mirrors .mjc-val', () => {
        expect(inputRule()).not.toBe('');
        for (const decl of [
            'width: 100%',
            'padding: 6px 9px',
            'border: 1px solid var(--mj-border-default)',
            'border-radius: var(--mj-radius-sm)',
            'background: var(--mj-bg-surface)',
            'min-height: 31px',
        ]) {
            expect(inputRule()).toContain(decl);
        }
    });

    it('sets font: inherit — a form control does not inherit it by default', () => {
        // Without this the value box and the input disagree even when every other property matches,
        // because browsers fall back to a UA font for form controls.
        expect(inputRule()).toContain('font: inherit');
    });

    it('tokens only — no hardcoded colour reaches the rule', () => {
        expect(inputRule()).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
        expect(inputRule()).not.toMatch(/\brgba?\(/);
    });
});

describe('item 5 — the panel half', () => {
    it('no inline width remains; the kit rule carries it', () => {
        expect(PANELS_RAW).not.toContain('style="width:100%"');
    });

    it('the dates stay date-only — not the generated datetime picker', () => {
        // The Dates panel exists BECAUSE the generated control shows a time component for a `date`
        // column. A styling fix that reintroduced it would defeat the purpose of the panel.
        // Against the comment-stripped source: `AsInput`'s docblock names the tag too, and counting
        // the raw file reports five for four fields.
        expect(PANELS.match(/<input type="date"/g) ?? []).toHaveLength(4);
        expect(PANELS).not.toContain('type="datetime-local"');
    });
});

describe('item 6 — the two day-counts say which direction they run', () => {
    it('the label is the plain one', () => {
        expect(PANELS).toContain('<label>Renewal notice (days)</label>');
        expect(PANELS).not.toContain('Renewal notice we owe (days)');
    });

    it('each field states its direction, verbatim', () => {
        expect(PANELS).toContain('Written notice we must give the customer before a renewal price change.');
        expect(PANELS).toContain('Notice the customer must give us to cancel.');
    });

    it('the deadline hint survives — it is a different fact from the direction', () => {
        expect(PANELS).toContain("deadline: {{ NoticeDeadline | date: 'd MMM y' }}");
    });

    it('the DisplayName is set, because CodeGen does not bracket a unit', () => {
        /*
         * Contrast with `CompanyID` (item 8), where no entry was added: CodeGen strips a trailing
         * `ID` from an FK and already produced "Company". It does not parenthesise a unit, so it
         * derives "Renewal Notice Days" here — verified against the database before it was added.
         */
        const meta = readFileSync(root('metadata/entity-fields/.entity-fields.json'), 'utf8');
        const entries: Array<{ fields?: Record<string, unknown>; primaryKey?: { ID?: string } }> = JSON.parse(meta);
        const row = entries.find((e) => e.primaryKey?.ID?.endsWith('Name=RenewalNoticeDays'));
        expect(row?.fields?.DisplayName).toBe('Renewal Notice (Days)');
    });
});
