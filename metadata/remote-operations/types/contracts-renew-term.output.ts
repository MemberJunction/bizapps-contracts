/**
 * Output for `Contracts.RenewTerm`.
 *
 * `EscalationWasClamped` is surfaced rather than hidden: when a requested increase exceeds the
 * negotiated ceiling the operation applies the ceiling instead of failing, and the caller must be
 * able to say so out loud rather than silently showing a smaller number than was asked for.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface RenewedLine {
    Description: string;
    PreviousUnitPrice: number | null;
    NewUnitPrice: number | null;
}

export interface RenewTermOutput {
    Success: boolean;
    Message?: string;
    Preview: boolean;
    /** Undefined on a preview — nothing was created. */
    NewContractTermID?: string;
    NewTermNumber?: number;
    /** ISO date (YYYY-MM-DD). */
    StartDate?: string;
    /** ISO date (YYYY-MM-DD). */
    EndDate?: string;
    /** The percentage actually applied, after clamping. A fraction: 0.05 = 5%. */
    AppliedEscalationPercent?: number;
    /** True when the requested escalation was reduced to the term's negotiated ceiling. */
    EscalationWasClamped?: boolean;
    Lines?: RenewedLine[];
}
