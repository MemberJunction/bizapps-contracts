/**
 * Output for `Contracts.ActivateTerm`.
 *
 * `ScheduledDates` is returned so the caller can show exactly what will bill and when, rather than
 * reporting "activated" and leaving a human to go looking for the schedule to confirm it exists.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface ActivateTermOutput {
    Success: boolean;
    Message?: string;
    ContractTermID?: string;
    BillingScheduleID?: string;
    /** ISO dates (YYYY-MM-DD) of every billing event created, in order. */
    ScheduledDates?: string[];
}
