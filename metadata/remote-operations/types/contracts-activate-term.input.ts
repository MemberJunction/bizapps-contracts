/**
 * Input for `Contracts.ActivateTerm`.
 *
 * Activation is the moment a term stops being a promise and starts being a thing that bills, so the
 * only input beyond the term itself is the escape hatch for a schedule somebody built by hand.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface ActivateTermInput {
    ContractTermID: string;
    /** Skip schedule creation when the caller has already built one deliberately. */
    SkipSchedule?: boolean;
}
