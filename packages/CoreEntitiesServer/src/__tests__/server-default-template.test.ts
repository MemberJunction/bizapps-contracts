/**
 * `ResolveServerDefaultTemplate` — the server-side template default a contract created outside the
 * Agreement panel relies on (golive #269).
 *
 * The case that broke: Closed Won in sales creates an Order Form with no template, and Order Form
 * carries `TemplateRequired = 1`, so every automated contract was refused on save. The panel's #218
 * default never runs on that path.
 *
 * Exercises the real function with stubbed reads, so each case also asserts WHICH reads ran — a
 * saved contract, or one whose field is already filled, must not pay for either query.
 */
import { describe, expect, it, vi } from 'vitest';
import { ResolveServerDefaultTemplate } from '../ContractEntityServer.js';

const TYPE = 'A1B2C3D4-0000-4000-8000-000000000001';
const CURRENT = 'A1B2C3D4-0000-4000-8000-0000000000AA';
const PICKED = 'A1B2C3D4-0000-4000-8000-0000000000BB';

function reads(templateRequired: boolean, current: string | null = CURRENT) {
    return {
        required: vi.fn(async () => templateRequired),
        current: vi.fn(async () => current),
    };
}

describe('ResolveServerDefaultTemplate', () => {
    it('a NEW contract of a type that requires a template gets the current one — the Closed Won case', async () => {
        const r = reads(true);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: TYPE, currentTemplateID: null },
            r.required,
            r.current,
        );
        expect(id).toBe(CURRENT);
    });

    it('treats a blank template as empty', async () => {
        const r = reads(true);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: TYPE, currentTemplateID: '  ' },
            r.required,
            r.current,
        );
        expect(id).toBe(CURRENT);
    });

    it('never replaces a template the caller supplied', async () => {
        const r = reads(true);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: TYPE, currentTemplateID: PICKED },
            r.required,
            r.current,
        );
        expect(id).toBeNull();
        expect(r.required).not.toHaveBeenCalled();
        expect(r.current).not.toHaveBeenCalled();
    });

    it('never touches a SAVED contract, and reads nothing to decide that', async () => {
        const r = reads(true);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: true, contractTypeID: TYPE, currentTemplateID: null },
            r.required,
            r.current,
        );
        expect(id).toBeNull();
        expect(r.required).not.toHaveBeenCalled();
        expect(r.current).not.toHaveBeenCalled();
    });

    it('does not default onto a type that needs no template (Change Order)', async () => {
        const r = reads(false);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: TYPE, currentTemplateID: null },
            r.required,
            r.current,
        );
        expect(id).toBeNull();
        expect(r.current).not.toHaveBeenCalled();
    });

    it('does nothing for a contract with no type', async () => {
        const r = reads(true);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: null, currentTemplateID: null },
            r.required,
            r.current,
        );
        expect(id).toBeNull();
        expect(r.required).not.toHaveBeenCalled();
    });

    it('returns null when no Published usable template exists, leaving validation to refuse the save', async () => {
        const r = reads(true, null);
        const id = await ResolveServerDefaultTemplate(
            { isSaved: false, contractTypeID: TYPE, currentTemplateID: null },
            r.required,
            r.current,
        );
        expect(id).toBeNull();
    });
});
