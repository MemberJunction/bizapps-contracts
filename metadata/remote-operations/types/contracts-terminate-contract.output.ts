/**
 * Output for `Contracts.TerminateContract`.
 *
 * The cancelled/retained split is the whole point of the return value. A contract marked Terminated
 * whose scheduled events still stand will keep invoicing, quietly, because everything downstream
 * reads the schedule rather than the contract's status — so the caller is told exactly how many
 * future events were stopped and how many already-covered ones were deliberately left alone.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface TerminateContractOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    ContractID?: string;
    /** ISO date (YYYY-MM-DD). */
    EffectiveDate?: string;
    /** Terms moved to Terminated. Zero is legitimate — a contract whose term already completed. */
    TermsTerminated?: number;
    /** Future scheduled billing events cancelled. */
    BillingEventsCancelled?: number;
    /** Events left standing: on or before the effective date, i.e. periods already covered. */
    BillingEventsRetained?: number;
}
