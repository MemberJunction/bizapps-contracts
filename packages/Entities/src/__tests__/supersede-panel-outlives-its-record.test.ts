/**
 * Issue #28 item 23 — neither the outcome message nor the candidate list may outlive what it
 * describes.
 *
 * ONE SHAPE OF DEFECT, TWICE. Both halves come from state that belongs to the PANEL while the fact it
 * reports belongs to the RECORD or the SELECTION, and the panel outlives both: the form reuses the
 * same component instance when it navigates, and the combobox changes selection without any code
 * running. Nothing goes stale in a way the user can see is stale — the screen simply describes
 * something else.
 *
 * ASSERTED AGAINST THE SOURCE, deliberately. Rendering this panel needs Angular, a form host and a
 * metadata provider; what is being pinned is structural — a binding, a key's type, a reset — and each
 * is readable without any of that. The behavioural half of this operation is covered against a fake
 * provider in `supersede-add-and-release.test.ts`; this file covers the part that lives in the
 * template.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const root = (p: string) => fileURLToPath(new URL('../../../../' + p, import.meta.url));
const SUPERSEDE = readFileSync(root('packages/Angular/src/lib/form-panels/supersede.panel.ts'), 'utf8');

describe('item 19 — the chips say what to do, in the issue\u2019s words', () => {
    it('the read-only chip carries #203 item 19\u2019s copy exactly', () => {
        // Sentence case, and no trailing "this" — the row of the item-19 table that covers this panel.
        // It was missed by the rebase: the commit carrying it also carried supersede work that next
        // had already solved its own way, so the whole commit was dropped and this line came with it.
        expect(SUPERSEDE).toContain("'Finish editing to change'");
        expect(SUPERSEDE).toContain("'Save this contract first'");
        expect(SUPERSEDE).not.toContain('finish editing to change this');
    });
});

describe('item 23 — changing the selection drops the previous outcome', () => {
    it('the picker reports its change rather than only storing it', () => {
        // `[(ngModel)]` alone holds the value and runs nothing, which is why the banners survived a
        // new selection: "Linked — that contract is now superseded by this agreement." sat on screen
        // while the user picked a DIFFERENT contract and read as a description of it.
        expect(SUPERSEDE).toContain('(ngModelChange)="PickPredecessor($event)"');
        expect(SUPERSEDE).not.toContain('[(ngModel)]="PickedPredecessorID"');
    });

    it('and the handler clears both banners, not just the success one', () => {
        const fn = SUPERSEDE.slice(SUPERSEDE.indexOf('public PickPredecessor('));
        const body = fn.slice(0, fn.indexOf('\n    }'));
        expect(body).toContain("this.LinkOk = ''");
        expect(body).toContain("this.LinkError = ''");
    });
});

describe('item 23 — the candidate list is keyed on the record', () => {
    it('remembers WHICH contract it loaded for, not merely that it loaded', () => {
        // A boolean belongs to the panel. The form reuses the instance across navigation, so it
        // stayed true and the picker went on offering the previous contract's candidates — filtered
        // to the previous customer and the previous level, which is a wrong list, not a stale one.
        expect(SUPERSEDE).toContain('private loadedFor: string | null = null;');
        expect(SUPERSEDE).toContain('this.loadedFor !== id');
        expect(SUPERSEDE).not.toMatch(/private loaded = false;/);
    });

    it('a failed load re-arms the retry by clearing the key, not by setting a flag', () => {
        const fn = SUPERSEDE.slice(SUPERSEDE.indexOf('private async loadCandidates()'));
        expect(fn).toContain('this.loadedFor = null;');
        // Item 4's half: a later success must clear an earlier failure's banner.
        expect(fn).toContain("this.LoadError = '';");
    });
});
