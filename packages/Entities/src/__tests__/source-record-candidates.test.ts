/**
 * The Source-record picker's two pure decisions (golive #219).
 *
 * C-US1 asks that finance be able to attach a manually created contract to an existing deal. The two
 * halves that need no database are WHICH deals are offered and WHAT each option says, and both are
 * stated in the issue rather than inferred from the code, which makes them an oracle:
 *
 *   · "search deals by name and customer, and ideally prefer deals for the contract's customer
 *     organization"
 *   · the raw ids stay visible and read-only, so the label is the only thing a person reads when
 *     choosing — it has to identify a deal on its own
 *
 * Written from the RULE, not from the implementation.
 */
import { describe, expect, it } from 'vitest';
import { DealIDClause, DealOptionLabel, DealSearchClause } from '../source-record-candidates';

const CUSTOMER = 'C1B2C3D4-0000-4000-8000-00000000000C';

describe('DealSearchClause — what the picker offers', () => {
    describe('nothing typed: the CONTRACT CUSTOMER’s own deals', () => {
        it("scopes the seeded list to the contract's customer", () => {
            expect(DealSearchClause(CUSTOMER)).toBe(`AccountID = '${CUSTOMER}'`);
        });

        it('compares the organization id DIRECTLY to AccountID, with no bridge', () => {
            /*
             * Verified against sales' schema rather than assumed: `FK_SalesAccount_Organization` is on
             * SalesAccount.ID itself, so a sales account SHARES its primary key with the common
             * Organization it represents. That is what makes the one-column compare correct; if it
             * were an ordinary FK column this clause would silently match nothing.
             */
            expect(DealSearchClause(CUSTOMER)).not.toMatch(/Organization|JOIN|IN \(/i);
        });

        describe('an ABSENT customer offers nothing, not everything', () => {
            /*
             * Same direction, and the same reasoning, as `SameCustomerClause`. `CustomerOrganizationID`
             * is NOT NULL on Contract, so a blank value never means "no customer" — it means the record
             * could not be read. Widening to every deal in the database at that moment is the failure
             * worth refusing; a person who really wants the whole book can type.
             */
            for (const absent of [null, undefined, '', '   ']) {
                it(`yields a clause matching nothing for ${JSON.stringify(absent)}`, () => {
                    expect(DealSearchClause(absent)).toBe('1 = 0');
                });
            }
        });

        it('escapes a quote rather than letting it close the literal', () => {
            expect(DealSearchClause("a'b")).toBe(`AccountID = 'a''b'`);
        });
    });

    describe('text typed: name, number and CUSTOMER, across every account', () => {
        it('searches all three fields the issue names', () => {
            const clause = DealSearchClause(CUSTOMER, 'renewal');
            expect(clause).toContain(`Name LIKE '%renewal%'`);
            expect(clause).toContain(`DealNumber LIKE '%renewal%'`);
            expect(clause).toContain(`Account LIKE '%renewal%'`);
        });

        it('is parenthesised, so an OR never escapes into the caller’s AND', () => {
            // The panel composes this with other predicates. Unbracketed ORs are how a filter that
            // reads correctly returns the whole table.
            expect(DealSearchClause(CUSTOMER, 'renewal').startsWith('(')).toBe(true);
            expect(DealSearchClause(CUSTOMER, 'renewal').endsWith(')')).toBe(true);
        });

        it('DROPS the customer scope once a person types', () => {
            /*
             * Deliberate, and the opposite of what "prefer the customer's deals" reads like at first.
             * Typing means the seeded list did not contain what was wanted; staying scoped would answer
             * a different question than the one asked and show an empty dropdown as if no such deal
             * existed.
             */
            expect(DealSearchClause(CUSTOMER, 'renewal')).not.toContain('AccountID');
        });

        it('searches even when the customer could not be read', () => {
            // The empty-customer refusal is about the SEEDED list. An explicit search is a person
            // asking for something by name, and has nothing to do with which customer they are on.
            expect(DealSearchClause(null, 'acme')).toContain(`Name LIKE '%acme%'`);
        });

        it('treats whitespace-only typing as nothing typed', () => {
            expect(DealSearchClause(CUSTOMER, '   ')).toBe(`AccountID = '${CUSTOMER}'`);
        });

        it('neutralises LIKE wildcards in what the user typed', () => {
            /*
             * `%`, `_` and `[` are pattern syntax, so a customer named `A_B` typed verbatim also matches
             * `AxB`, and a lone `%` matches every deal — a search box that silently ignores what was
             * typed. T-SQL has no default backslash escape; bracketing is the portable form.
             */
            const clause = DealSearchClause(null, '100%_[x]');
            expect(clause).toContain(`Name LIKE '%100[%][_][[]x]%'`);
        });

        it('escapes a quote in the search text', () => {
            expect(DealSearchClause(null, "O'Brien")).toContain(`Name LIKE '%O''Brien%'`);
        });
    });
});

describe('DealIDClause — keeping the CURRENT deal in the list', () => {
    it('matches the one deal by id', () => {
        expect(DealIDClause('D0000001-0000-4000-8000-00000000000D')).toBe(
            `ID = 'D0000001-0000-4000-8000-00000000000D'`,
        );
    });

    describe('no current deal matches nothing, so the OR adds nothing', () => {
        // The panel ORs this into the seeded filter unconditionally. A clause that widened when there
        // was nothing to keep would turn the customer-scoped list into the whole book.
        for (const absent of [null, undefined, '', '  ']) {
            it(`yields a clause matching nothing for ${JSON.stringify(absent)}`, () => {
                expect(DealIDClause(absent)).toBe('1 = 0');
            });
        }
    });

    it('escapes a quote rather than letting it close the literal', () => {
        expect(DealIDClause("a'b")).toBe(`ID = 'a''b'`);
    });
});

describe('DealOptionLabel — what an option says', () => {
    const base = { ID: 'D1', DealNumber: 'DEAL-0042', Name: '2026 Renewal', Account: 'Acme Corp' };

    it('names the deal by number, name and customer', () => {
        expect(DealOptionLabel(base)).toBe('DEAL-0042 — 2026 Renewal (Acme Corp)');
    });

    it('keeps the customer, which is what disambiguates identically named renewals', () => {
        // "2026 Renewal" is not one deal. Once a search widens past a single account, the
        // parenthetical is the only thing separating the rows.
        const other = DealOptionLabel({ ...base, ID: 'D2', DealNumber: 'DEAL-0043', Account: 'Globex' });
        expect(other).not.toBe(DealOptionLabel(base));
    });

    it('drops the dash rather than dangling it when there is no number', () => {
        expect(DealOptionLabel({ ...base, DealNumber: null })).toBe('2026 Renewal (Acme Corp)');
    });

    it('falls back to the number when the deal has no name', () => {
        expect(DealOptionLabel({ ...base, Name: '' })).toBe('DEAL-0042 (Acme Corp)');
    });

    it('omits the parenthetical rather than rendering an empty one', () => {
        expect(DealOptionLabel({ ...base, Account: '   ' })).toBe('DEAL-0042 — 2026 Renewal');
    });

    it('never renders a blank option', () => {
        expect(DealOptionLabel({ ID: 'D9', DealNumber: null, Name: '', Account: null })).toBe('Deal');
    });
});
