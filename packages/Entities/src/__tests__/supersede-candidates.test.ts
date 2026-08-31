/**
 * The Supersedes picker's two stated rules — the halves that need no database.
 *
 * contracts#28 item 4 fixes a dropdown that showed nothing and explained nothing. Its "final rule"
 * lists four conditions; rules 2 to 4 were already applied, rule 1 (same customer) was not, and the
 * option label was wrong. This file pins the two decisions that are pure:
 *
 *   · what the same-customer clause does when the customer is ABSENT
 *   · what the option label says, and what it falls back to
 *
 * Written from the RULE rather than from the implementation. Both are quoted as final in the issue,
 * which makes them an oracle rather than a description of the code.
 *
 * Rule 2 is `IsSameContractLevel`, pinned next door in `same-contract-level.test.ts`. Rules 3 and 4
 * are plain SQL predicates with nothing to decide.
 */
import { describe, expect, it } from 'vitest';
import { ContractOptionLabel, SameCustomerClause } from '../supersede-candidates';

const CUSTOMER = 'C1B2C3D4-0000-4000-8000-00000000000C';

describe('SameCustomerClause — rule 1', () => {
    it("scopes the picker to the contract's own customer", () => {
        expect(SameCustomerClause(CUSTOMER)).toBe(`CustomerOrganizationID = '${CUSTOMER}'`);
    });

    describe('an ABSENT customer offers nothing, not everything', () => {
        /**
         * The direction is the whole point, and it is what a refactor flips by accident.
         * `CustomerOrganizationID` is NOT NULL on Contract, so a missing value never means "this
         * contract has no customer" — it means the record could not be read. Widening to every
         * contract at that moment would offer another customer's agreements precisely when the caller
         * knows least, which is the failure rule 1 exists to prevent.
         */
        for (const absent of [null, undefined, '', '   ']) {
            it(`yields a clause matching nothing for ${JSON.stringify(absent)}`, () => {
                expect(SameCustomerClause(absent)).toBe('1 = 0');
            });
        }
    });

    it('escapes a quote rather than letting it close the literal', () => {
        // The value reaches an ExtraFilter as a string. It is a UUID by construction, so this should
        // never fire — which is exactly why dropping the escape would go unnoticed.
        expect(SameCustomerClause("a'b")).toBe(`CustomerOrganizationID = 'a''b'`);
    });
});

describe('ContractOptionLabel — the option label', () => {
    const base = { ContractNumber: 'CTR-0007', ContractType: 'Order Form', Description: null as string | null };

    it('uses the DESCRIPTION when there is one', () => {
        expect(ContractOptionLabel({ ...base, Description: 'Platform licence, 2026 renewal' })).toBe(
            'CTR-0007 — Platform licence, 2026 renewal',
        );
    });

    it('falls back to the CONTRACT TYPE when the description is empty', () => {
        expect(ContractOptionLabel({ ...base, Description: null })).toBe('CTR-0007 — Order Form');
    });

    it('treats a whitespace-only description as empty', () => {
        // Blank descriptions are common on imported records, and "CTR-0007 —   " reads as missing
        // data rather than as an uncategorised agreement.
        expect(ContractOptionLabel({ ...base, Description: '   ' })).toBe('CTR-0007 — Order Form');
    });

    it('falls back again when the type is missing too, rather than rendering a dangling dash', () => {
        expect(ContractOptionLabel({ ContractNumber: 'CTR-0007', ContractType: null, Description: null })).toBe(
            'CTR-0007 — Contract',
        );
    });

    it('does NOT fall back merely because the description is short', () => {
        // Only emptiness triggers the fallback. A one-character description is still what someone typed.
        expect(ContractOptionLabel({ ...base, Description: 'A' })).toBe('CTR-0007 — A');
    });

    it('trims surrounding whitespace off a real description', () => {
        expect(ContractOptionLabel({ ...base, Description: '  Renewal  ' })).toBe('CTR-0007 — Renewal');
    });
});
