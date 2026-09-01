/**
 * Edit mode looks like read mode, and the two day-counts say which way the notice runs —
 * issue #28 items 5 and 6.
 *
 * WHY THE INPUTS ARE BARE IN THE FIRST PLACE, since that is the thing a reader will want to "fix".
 * The Dates panel exists because the generated datetime picker renders a TIME component for a `date`
 * column — a contract does not start at 7pm — so these are native `<input type="date">`. A native
 * control inherits none of the app's chrome, which is what made edit mode visibly jump. The remedy is
 * kit CSS, NOT swapping back to the generated control; a test that only checked "looks styled" would
 * be satisfied by the very change that reintroduces the bug, so this pins both halves.
 *
 * Source-level guards: reads files, no database, no MJ imports.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const PANEL_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');

/**
 * The panel with its COMMENTARY REMOVED — `/* *\/` docblocks and `<!-- -->` template comments.
 *
 * Every assertion below that says "this string is absent" has to run against this rather than the
 * raw file. The comments in these panels explain the very copy they replaced, verbatim and in
 * quotes, so a whole-file search cannot tell a rendered label from a note about one — it reports the
 * explanation as the defect. Assertions that a string is PRESENT are unaffected either way.
 */
const PANEL = PANEL_RAW.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');
const KIT = readFileSync(root('packages/Angular/src/lib/styles/contracts-kit.css'), 'utf8');
const META = readFileSync(root('metadata/entity-fields/.entity-fields.json'), 'utf8');

/**
 * The `.mjc-field input, .mjc-field select` rule body.
 *
 * A FUNCTION, not a module-scope constant. Resolved eagerly with an `expect` inside, a missing rule
 * throws while the module loads and vitest reports "no tests" for the whole file — which says the
 * suite is broken rather than which guarantee was lost. Lazy, each test fails on its own terms.
 */
const inputRule = (): string => {
    const start = KIT.indexOf('.mjc-field input,');
    if (start < 0) return '';
    return KIT.slice(start, KIT.indexOf('}', start));
};

describe('item 5 — edit controls match the read-mode value box', () => {
    it('the kit styles the inputs, mirroring .mjc-val', () => {
        expect(inputRule()).not.toBe('');
        for (const decl of [
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

    it('carries the width, so no inline style has to', () => {
        expect(inputRule()).toContain('width: 100%');
        expect(PANEL).not.toContain('style="width:100%"');
    });

    it('the dates stay date-only — not the generated datetime picker', () => {
        // The panel exists BECAUSE the generated control shows a time component for a `date` column.
        expect(PANEL.match(/<input type="date"/g) ?? []).toHaveLength(4);
        expect(PANEL).not.toContain('type="datetime-local"');
    });

    it('tokens only — no hardcoded colour reaches the rule', () => {
        expect(inputRule()).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
        expect(inputRule()).not.toMatch(/\brgba?\(/);
    });
});

describe('item 6 — the two day-counts say which direction they run', () => {
    it('the label is the plain one', () => {
        expect(PANEL).toContain('<label>Renewal notice (days)</label>');
        expect(PANEL).not.toContain('Renewal notice we owe (days)');
    });

    it('each field states its direction, verbatim', () => {
        expect(PANEL).toContain('Written notice we must give the customer before a renewal price change.');
        expect(PANEL).toContain('Notice the customer must give us to cancel.');
    });

    it('the deadline hint survives — it is a different fact from the direction', () => {
        expect(PANEL).toContain("deadline: {{ NoticeDeadline | date: 'd MMM y' }}");
    });

    it('the DisplayName is set, because CodeGen does not bracket a unit', () => {
        /*
         * Contrast with `CompanyID` (item 8), where an entry was NOT added: CodeGen strips a trailing
         * `ID` from an FK and already produced "Company". It does not parenthesise a unit, so it
         * derives "Renewal Notice Days" here — verified against the database before this was added.
         * A grid heading that reads differently from the form is a real cost on a field that is one
         * of a confusable pair.
         */
        const entries: Array<{ fields?: Record<string, unknown>; primaryKey?: { ID?: string } }> = JSON.parse(META);
        const row = entries.find((e) => e.primaryKey?.ID?.endsWith('Name=RenewalNoticeDays'));
        expect(row?.fields?.DisplayName).toBe('Renewal Notice (Days)');
    });
});
