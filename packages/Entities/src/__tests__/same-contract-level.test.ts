/**
 * The same-level supersession rule — the half that needs no database.
 *
 * A re-papering replaces an agreement with one at the SAME level of the tree: two top-level
 * agreements, or two documents under the same parent. Ruled by Marcelo 2026-08-20, replacing the
 * obvious-looking "root only" rule, which is wrong in both directions — it forbids a change order
 * superseding another change order under the same order form (real, and the alternative is deleting
 * history), while still permitting the genuinely meaningless case of a change order claiming to
 * replace the whole agreement it hangs off.
 *
 * These cases are written from the RULE, not from the implementation. Two of them are the ones a
 * plain nullable compare gets wrong, and both would fail silently: `null` vs `null` must be the SAME
 * level (a SQL `=` says no), and UUID casing must not matter (MJ returns either casing depending on
 * how the row was loaded, so a case-sensitive compare refuses a legitimate re-papering).
 */
import { describe, expect, it } from 'vitest';
import { IsSameContractLevel } from '../ContractEntity';

const PARENT_A = 'A1B2C3D4-0000-4000-8000-00000000000A';
const PARENT_B = 'B1B2C3D4-0000-4000-8000-00000000000B';

describe('IsSameContractLevel', () => {
    it('treats two top-level agreements as the same level', () => {
        expect(IsSameContractLevel(null, null)).toBe(true);
    });

    it('treats two siblings under one parent as the same level — a change order may supersede a change order', () => {
        expect(IsSameContractLevel(PARENT_A, PARENT_A)).toBe(true);
    });

    it('ignores UUID casing, because MJ returns either', () => {
        expect(IsSameContractLevel(PARENT_A.toLowerCase(), PARENT_A.toUpperCase())).toBe(true);
    });

    it('refuses a child superseding a top-level agreement', () => {
        expect(IsSameContractLevel(PARENT_A, null)).toBe(false);
    });

    it('refuses a top-level agreement superseding a child', () => {
        expect(IsSameContractLevel(null, PARENT_A)).toBe(false);
    });

    it('refuses two children of DIFFERENT parents', () => {
        expect(IsSameContractLevel(PARENT_A, PARENT_B)).toBe(false);
    });

    it('treats undefined as absent, so an unset field behaves like a top-level agreement', () => {
        expect(IsSameContractLevel(undefined, null)).toBe(true);
        expect(IsSameContractLevel(undefined, PARENT_A)).toBe(false);
    });
});
