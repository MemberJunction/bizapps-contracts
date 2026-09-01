/**
 * Edit controls match the read-mode value box — the surviving half of issue #28 item 5.
 *
 * ⚠ TRIMMED ON 2026-09-01, when `origin/next` was merged taking its side of `contract.panels.ts`
 * wholesale. `next` rewrote the hero and the surrounding panels, so item 5's PANEL half (removing the
 * inline `style="width:100%"`) and all of item 6 (the "Renewal notice (days)" label and the two
 * direction hints) were reverted with that file. The assertions covering them are gone rather than
 * left failing; they belong with the redo, against next's structure.
 *
 * What survives is the kit rule, and it survives because `contracts-kit.css` merged cleanly. That is
 * the load-bearing half: without it a native `<input type="date">` inherits none of the app's
 * typography and edit mode visibly jumps.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const KIT = readFileSync(root('packages/Angular/src/lib/styles/contracts-kit.css'), 'utf8');

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
