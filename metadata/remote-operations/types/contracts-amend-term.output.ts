/**
 * Output for `Contracts.AmendTerm`.
 *
 * The stub window is the whole point of the return value. Adding a product mid-term creates a line
 * whose EndDate is the TERM's end date, so the new product lands on the SAME renewal date as
 * everything else the customer already has — and `StubDays` is what the next billing event prorates.
 * A standalone subscription would instead run a year from the amendment date and hand the customer
 * a second renewal date to remember.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface AmendTermOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    ContractTermID?: string;
    AmendmentID?: string;
    AmendmentNumber?: number;
    /** The co-term stub that would be, or was, created. */
    LineID?: string;
    /** ISO date (YYYY-MM-DD) — the amendment date. */
    StubStart?: string;
    /** ISO date (YYYY-MM-DD) — the TERM's end date, which is the point. */
    StubEnd?: string;
    /** Days of the term the stub covers; what the proration is of. */
    StubDays?: number;
}
