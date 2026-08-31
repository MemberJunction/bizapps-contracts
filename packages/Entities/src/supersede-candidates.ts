/**
 * @fileoverview Which contracts the Supersedes picker may offer, and how it names them.
 *
 * contracts#28 item 4 states the rule as four conditions, all of which must hold. A candidate is a
 * contract that is:
 *
 *   1. the SAME CUSTOMER as this contract — {@link SameCustomerClause}
 *   2. at the SAME LEVEL — `IsSameContractLevel`, in `ContractEntity.ts`, where it already lived
 *   3. NOT already superseded — a plain `SupersededByContractID IS NULL`
 *   4. not this contract — a plain `ID <> …`
 *
 * WHY THESE LIVE HERE AND NOT ON THE PANEL. `supersede.panel.ts` is an Angular component, so anything
 * declared inside it can only be asserted by standing up Angular's DI — importing it from a unit test
 * fails with "the injectable 'PlatformLocation' needs to be compiled using the JIT compiler". Rules 3
 * and 4 have nothing to decide, but 1 and the label format both do, and both are stated as final in
 * the issue, which makes them worth pinning. Rule 2 was already here for the same reason.
 *
 * The panel still owns the QUERY. These own the decisions inside it.
 *
 * @module @mj-biz-apps/contracts-entities
 */

/**
 * The same-customer clause — rule 1 — or one that deliberately matches nothing.
 *
 * A re-papering replaces one customer's agreement with another agreement for THAT customer. Offering
 * another customer's contract is not merely untidy: linking it points one organisation's lineage at
 * another's, so the successor's terms read as governing a party that never signed them, and the
 * predecessor's customer loses the trail to whatever replaced their agreement.
 *
 * AN ABSENT CUSTOMER YIELDS NOTHING, NOT EVERYTHING, and the direction is the whole point.
 * `CustomerOrganizationID` is NOT NULL on Contract, so a missing value never means "this contract has
 * no customer" — it means the record could not be read. Widening to every contract at that moment
 * would offer the whole book precisely when the caller knows least, which is the failure rule 1
 * exists to prevent.
 */
export function SameCustomerClause(customerID: string | null | undefined): string {
    const id = (customerID ?? '').trim();
    if (!id) return '1 = 0';
    // The value reaches an `ExtraFilter` as a string. It is a UUID by construction, so this should
    // never fire — which is exactly why dropping it would go unnoticed.
    return `CustomerOrganizationID = '${id.replace(/'/g, "''")}'`;
}

/**
 * The option label: `<ContractNumber> — <Description>`, falling back to the contract type.
 *
 * Quoted as final in the issue. The description is what a person recognises — "Platform licence, 2026
 * renewal" — while the type is a category several contracts share, so a list labelled by type reads
 * as several copies of the same row.
 *
 * The description is TRIMMED before the emptiness test, because blank descriptions are common on
 * imported records and a label reading `CTR-0007 —   ` looks like missing data rather than an
 * uncategorised agreement. The second fallback to "Contract" exists so a row with neither can never
 * render a dangling dash.
 */
export function ContractOptionLabel(c: {
    ContractNumber: string;
    ContractType: string | null;
    Description: string | null;
}): string {
    const described = (c.Description ?? '').trim();
    return `${c.ContractNumber} — ${described || c.ContractType || 'Contract'}`;
}
