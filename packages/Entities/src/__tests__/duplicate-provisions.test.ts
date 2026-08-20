/**
 * R-10's staged-rows rule — the half that needs no database.
 *
 * `UQ_ContractTemplateModification_Contract_Provision` is the floor and it refuses a duplicate as a
 * raw unique-index violation naming no field. Two cheaper layers sit above it: the editor's picker
 * hides provisions already modified (so the normal path never reaches the error), and this counts
 * duplicates among the rows staged in one graph save — with no query, because they are right there.
 *
 * The three cases that are easy to get wrong are all here, and each would be a silent failure:
 * UUID casing (miss a duplicate while appearing to check), blank IDs (refuse a save the user is still
 * composing), and repeat counting (report one problem twice).
 */
import { describe, expect, it } from 'vitest';
import { FindDuplicateProvisionIDs } from '../ContractEntity';

const A = 'A1B2C3D4-0000-4000-8000-000000000001';
const B = 'B1B2C3D4-0000-4000-8000-000000000002';

describe('FindDuplicateProvisionIDs', () => {
    it('finds nothing in a clean set', () => {
        expect(FindDuplicateProvisionIDs([A, B])).toEqual([]);
    });

    it('finds nothing in an empty set', () => {
        expect(FindDuplicateProvisionIDs([])).toEqual([]);
    });

    it('finds a straightforward duplicate', () => {
        expect(FindDuplicateProvisionIDs([A, B, A])).toEqual([A.toLowerCase()]);
    });

    it('treats DIFFERENT CASING as the same provision', () => {
        // The silent failure: MJ hands UUIDs back in either casing depending on the load path, so a
        // case-sensitive check would let the duplicate through and the raw index error would arrive.
        expect(FindDuplicateProvisionIDs([A, A.toLowerCase()])).toEqual([A.toLowerCase()]);
    });

    it('reports a triplicate ONCE — three copies is one problem', () => {
        expect(FindDuplicateProvisionIDs([A, A, A])).toEqual([A.toLowerCase()]);
    });

    it('reports each duplicated provision separately', () => {
        expect(FindDuplicateProvisionIDs([A, A, B, B])).toEqual([A.toLowerCase(), B.toLowerCase()]);
    });

    it('does NOT group rows with no provision chosen yet', () => {
        // Two freshly-added rows are an incomplete edit, not the same provision twice. Grouping them
        // would refuse a save while the user is still filling the form in.
        expect(FindDuplicateProvisionIDs([null, undefined, '', '   '])).toEqual([]);
    });

    it('ignores blanks while still catching a real duplicate beside them', () => {
        expect(FindDuplicateProvisionIDs([null, A, '', A])).toEqual([A.toLowerCase()]);
    });
});
