/**
 * Input for `Contracts.TerminateContract`.
 *
 * `Reason` is required, not optional: a termination with no stated reason is a future argument, and
 * the reason is what the lifecycle event records.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface TerminateContractInput {
    ContractID: string;
    /** Why. Recorded on the lifecycle event. */
    Reason: string;
    /** ISO date (YYYY-MM-DD). Defaults to today. Billing on or before it stands; after it is cancelled. */
    EffectiveDate?: string;
    /** Compute and report, write nothing. */
    PreviewOnly?: boolean;
}
