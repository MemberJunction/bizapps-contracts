/**
 * Input for `Contracts.RenewTerm`.
 *
 * `PreviewOnly` is the important one: renewal is where a human wants to see the escalated numbers
 * before agreeing to them, and the preview runs the identical computation rather than a second copy
 * of the rules that would eventually disagree with the real thing.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface RenewTermInput {
    /** The term being renewed — becomes the new term's RenewalOfTermID. */
    ContractTermID: string;
    /** Compute and return, write nothing. */
    PreviewOnly?: boolean;
    /** Override the term's own escalation for this renewal. Still clamped to the negotiated cap. */
    EscalationPercentOverride?: number;
    /** Length of the new term. Defaults to the length of the term being renewed. */
    TermMonths?: number;
}
