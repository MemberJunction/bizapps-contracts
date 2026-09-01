/**
 * Re-papering's copy and its two message bugs — the surviving parts of issue #28 items 19, 23 and 24.
 *
 * ⚠ TRIMMED ON 2026-09-01, when `origin/next` was merged taking its side of `contract.panels.ts`
 * wholesale and its DELETION of `record-files.panel.ts` (next moved Contracts onto MJ stock
 * attachments). That reverted item 19's hero, Dates, Renewal and Lineage copy, all of item 21, and
 * item 19's three Documents notes along with the file itself. Those assertions are gone rather than
 * left failing — they belong with the redo, written against whatever next's structure now is.
 *
 * What survives is everything in `supersede.panel.ts`, which merged cleanly: the two chips from item
 * 19, and both halves of item 23. Item 24 survives too, by coincidence rather than by our change —
 * next's rewrite of the file dropped the dead banner independently.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const strip = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/<!--[\s\S]*?-->/g, '');

const SUPERSEDE_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/supersede.panel.ts'), 'utf8');
const PANELS_RAW = readFileSync(root('packages/Angular/src/lib/form-panels/contract.panels.ts'), 'utf8');

/* Commentary removed: the panel quotes the copy it replaced, so a whole-file search would report the
 * explanation as the defect. Presence checks are unaffected; absence checks need this. */
const SUPERSEDE = strip(SUPERSEDE_RAW);

describe('item 19 — the re-papering chips', () => {
    it('read as sentences, not lowercase fragments', () => {
        expect(SUPERSEDE).toContain('Finish editing to change');
        expect(SUPERSEDE).toContain('Save this contract first');
        expect(SUPERSEDE).not.toContain('finish editing to change this');
    });

    it('and the empty picker still explains itself in the control (item 2)', () => {
        expect(SUPERSEDE).toContain("'No eligible contracts'");
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
        // A boolean belongs to the panel, and the panel outlives the record: the form reuses the
        // component instance across navigation, so a stale `true` left the PREVIOUS contract's
        // candidates on screen — filtered to the previous customer and level, a wrong list.
        expect(SUPERSEDE_RAW).toContain('private loadedFor: string | null = null;');
        expect(SUPERSEDE_RAW).toContain('this.loadedFor !== id');
        expect(SUPERSEDE_RAW).not.toMatch(/private loaded = false;/);
    });

    it('a later successful load clears an earlier failure (shipped with item 4)', () => {
        const fn = SUPERSEDE_RAW.slice(SUPERSEDE_RAW.indexOf('private async loadCandidates()'));
        expect(fn).toContain("this.LoadError = '';");
    });
});

describe('item 24 — the dead banner', () => {
    it('is absent from contract.panels.ts', () => {
        // Ours deleted it; next's rewrite of the file also dropped it. Either way it must not return.
        expect(PANELS_RAW).not.toContain('5 · Policy');
    });
});
