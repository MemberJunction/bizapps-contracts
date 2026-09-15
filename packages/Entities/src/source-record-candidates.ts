/**
 * @fileoverview Which deals the Source-record picker may offer, and how it names them (golive #219).
 *
 * C-US1 says a finance user may associate a manually created contract with an existing deal by
 * looking it up. The link is the polymorphic pair `CreatingEntityID` / `CreatingRecordID`, which the
 * Provenance panel has rendered read-only since contracts#28 item 18 — for a reason that still
 * holds: hand-typing the two halves produced a corrupt pair (`CTR-000026` names
 * `MJ: Explorer Navigation Items` and a record id that is not a UUID). A picker that sets both halves
 * together is the way to satisfy the story WITHOUT reopening that defect, so the raw fields stay
 * read-only and this is what feeds the control above them.
 *
 * WHY THESE LIVE HERE AND NOT ON THE PANEL. Same reason `supersede-candidates.ts` exists: anything
 * declared inside an Angular component can only be asserted by standing up Angular's DI, so importing
 * it from a unit test fails with "the injectable 'PlatformLocation' needs to be compiled using the JIT
 * compiler". The panel owns the QUERY; these own the decisions inside it.
 *
 * ── WHY THIS FILE MENTIONS DEALS AND THE PACKAGE STILL DOES NOT DEPEND ON SALES ────────────────
 *
 * `bizapps-sales` depends on THIS app — it is sales' Close-Won seam that creates contracts — so a
 * dependency pointing back would invert the graph, which is the reason the column is polymorphic
 * rather than a `DealID` FK in the first place (the Contract entity's own description says so). The
 * strings below are therefore a SOFT, name-only read resolved from provider metadata at runtime: no
 * import, no manifest dependency, and an installation without sales simply finds no entity and shows
 * no picker.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/** One row of the picker, as the panel reads it off `vwDeals`. */
export interface DealOption {
    ID: string;
    DealNumber: string | null;
    Name: string;
    /** The customer's name, joined onto the deal's base view as `Account`. */
    Account: string | null;
}

/**
 * Escape a value on its way into an `ExtraFilter` string literal.
 *
 * Doubling the quote is the whole of it for a UUID, which is what the customer id is by construction.
 * The SEARCH text is different in kind — it is whatever a person typed — so it also needs the LIKE
 * metacharacters neutralised; see {@link DealSearchClause}.
 */
function quote(value: string): string {
    return value.replace(/'/g, "''");
}

/**
 * Neutralise a user's text for a `LIKE` pattern.
 *
 * `%` and `_` are wildcards and `[` opens a character class, so a customer named `A_B` typed verbatim
 * matches `AxB` too. T-SQL has no backslash escape by default; the portable form is to bracket each
 * metacharacter, which means what it says in every collation and needs no `ESCAPE` clause.
 */
function likeLiteral(value: string): string {
    return quote(value).replace(/[%_[]/g, (c) => `[${c}]`);
}

/**
 * The filter that decides WHICH deals the picker offers.
 *
 * Two modes, and the difference matters more than it looks:
 *
 *   · **NOTHING TYPED — the customer's own deals.** This is the seeded list, and it is the case the
 *     story is really about: a finance user papering a contract for Acme wants Acme's deals, not a
 *     page of whatever sorted first. Issue #219 asks the lookup to "ideally prefer deals for the
 *     contract's customer organization"; seeding it this way makes the common case zero-typing.
 *   · **TEXT TYPED — search the whole book, by deal or by customer.** Once a person types they are
 *     looking for something the seeded list did not contain, so staying scoped to one customer would
 *     silently answer a different question than the one asked. #219 states the search as "by name and
 *     customer", which is `Name`, `DealNumber` and the joined `Account`.
 *
 * AN ABSENT CUSTOMER WITH NO SEARCH TEXT OFFERS NOTHING, NOT EVERYTHING — the same direction, and the
 * same reasoning, as `SameCustomerClause`. `CustomerOrganizationID` is NOT NULL on Contract, so a
 * missing value never means "this contract has no customer"; it means the record could not be read.
 * Opening the picker to every deal in the database at exactly that moment is the failure worth
 * refusing, and a person who genuinely wants the whole book can type.
 *
 * The CUSTOMER LINK IS DIRECT, which is easy to disbelieve and is verified: sales' `SalesAccount`
 * shares its primary key with `__mj_BizAppsCommon.Organization` (`FK_SalesAccount_Organization` is on
 * `ID` itself), so a deal's `AccountID` IS an organization id and compares to the contract's
 * `CustomerOrganizationID` with no bridge table.
 */
export function DealSearchClause(customerOrganizationID: string | null | undefined, searchText?: string | null): string {
    const search = (searchText ?? '').trim();
    if (search) {
        const like = `%${likeLiteral(search)}%`;
        return `(Name LIKE '${like}' OR DealNumber LIKE '${like}' OR Account LIKE '${like}')`;
    }
    const customer = (customerOrganizationID ?? '').trim();
    if (!customer) return '1 = 0';
    return `AccountID = '${quote(customer)}'`;
}

/**
 * A clause matching ONE deal by id — the currently linked one.
 *
 * The seeded list is the customer's deals, and the deal a contract is already pointed at need not be
 * among them: Close Won writes the pair from sales, where the deal's account and the contract's
 * customer are two records a person maintains separately, and a re-pointed contract may name a deal
 * for a related entity entirely. Without this the picker renders BLANK beside a contract that plainly
 * has a source, which reads as "no deal" — the exact confusion #219 is about.
 *
 * ORed into the seeded filter rather than fetched separately so the list arrives in one read and the
 * selected option can never flicker in after the dropdown is already open.
 */
export function DealIDClause(dealID: string | null | undefined): string {
    const id = (dealID ?? '').trim();
    if (!id) return '1 = 0';
    return `ID = '${quote(id)}'`;
}

/**
 * The option label: `<DealNumber> — <Name> (<Account>)`.
 *
 * Every part earns its place. The NUMBER is what a person quotes in an email; the NAME is what they
 * recognise; the CUSTOMER disambiguates the renewals, which are frequently named identically across
 * accounts ("2026 Renewal" is not one deal). The customer is also the reason the parenthetical is
 * kept when searching widens past one account — without it the widened list is a column of
 * indistinguishable names.
 *
 * Each part is TRIMMED before its emptiness test, because blank strings are common on imported rows
 * and a label reading `— ( )` looks like broken software rather than a sparse record. A deal with no
 * number loses the prefix rather than rendering a dangling dash, and one with no name falls back to
 * the number so the option is never blank.
 */
export function DealOptionLabel(deal: DealOption): string {
    const number = (deal.DealNumber ?? '').trim();
    const name = (deal.Name ?? '').trim();
    const account = (deal.Account ?? '').trim();

    const head = number && name ? `${number} — ${name}` : name || number || 'Deal';
    return account ? `${head} (${account})` : head;
}
