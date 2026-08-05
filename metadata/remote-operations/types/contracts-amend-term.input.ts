/**
 * Input for `Contracts.AmendTerm`.
 *
 * An amendment changes a term that is RUNNING; a renewal starts a new one. Conflating the two is the
 * single most common contract-model mistake — a customer who adds fifty seats in month four has not
 * started a new agreement, and forcing that through a renewal would restart their term, re-date
 * their renewal notice and re-baseline their escalation.
 *
 * THE CHANGE COMES IN ON THIS INPUT, not off the amendment row. `ContractAmendment` records THAT a
 * term changed, when, of what kind, and who approved it — it has no columns saying which line
 * changed or to what value. So `AddProduct` and `Coterm` are applied from what is supplied here, and
 * the other kinds are refused rather than guessed at.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface AmendTermInput {
    ContractTermID: string;
    /** `AddProduct` or `Coterm`. Other kinds are refused with the reason. */
    AmendmentType: string;
    /** What changed and why. Recorded on the amendment and on the lifecycle event. */
    Description: string;
    /** ISO date (YYYY-MM-DD). Defaults to today. The co-term stub starts here. */
    EffectiveDate?: string;
    /** The product being added mid-term. */
    ProductID?: string;
    Quantity?: number;
    ContractedUnitPrice?: number | null;
    /** Required when the added line is a Subscription — orders cannot materialise one without it. */
    SubscriptionTypeID?: string | null;
    LineType?: string;
    /** The approval task, where one was required. */
    ApprovalTaskID?: string | null;
    /** Compute and report, write nothing. */
    PreviewOnly?: boolean;
}
