/**
 * Output for `Contracts.SaveContract`.
 *
 * On success the WHOLE saved agreement comes back, re-read from the database, so the client sees
 * what the server DERIVED rather than its own guesses: the allocated contract number, each term's
 * derived number, the defaulted pricing date, and any defaults a contract type supplied.
 *
 * On failure `Issues` carries FIELD-LEVEL reasons in the same shape the client's own validator
 * produces, so one renderer displays both. A save that fails with only a joined string forces the
 * UI to either parse it or show a paragraph where a field marker belongs.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface SaveContractOutput {
    Success: boolean;
    Message?: string;
    Contract?: {
        ID?: string | null;
        ContractNumber?: string | null;
        ContractTypeID: string;
        CompanyID: string;
        CustomerOrganizationID?: string | null;
        CustomerPersonID?: string | null;
        PrimaryContactPersonID?: string | null;
        OwnerUserID?: string | null;
        ParentContractID?: string | null;
        Status: string;
        Description?: string | null;
        EffectiveDate?: string | null;
        ExecutedDate?: string | null;
        PricedAt?: string | null;
        AutoRenew?: boolean;
        CancellationWindowDays?: number | null;
        TerminationPolicy?: string | null;
        ExternalReferenceID?: string | null;
        Terms: {
            ID?: string | null;
            StartDate: string;
            EndDate: string;
            Status: string;
            BillingFrequency: string;
            CommittedAmount?: number | null;
            EscalationPercent?: number | null;
            EscalationBasis?: string | null;
            MaxEscalationPercent?: number | null;
            RenewalNoticeDays?: number | null;
            RenewalProbability?: number | null;
            PaymentTermsTypeID?: string | null;
            CurrencyID?: string | null;
            EarlyTerminationDate?: string | null;
            ExecutedDate?: string | null;
            Notes?: string | null;
            Lines: {
                ID?: string | null;
                ProductID: string;
                LineType: string;
                Quantity: number;
                ContractedUnitPrice?: number | null;
                DiscountPct?: number | null;
                StartDate?: string | null;
                EndDate?: string | null;
                SubscriptionTypeID?: string | null;
                Description?: string | null;
            }[];
            Schedules: {
                ID?: string | null;
                ScheduleType: string;
                Frequency?: string | null;
                AnchorDate?: string | null;
                IsActive?: boolean;
                Notes?: string | null;
            }[];
            Commitments: {
                ID?: string | null;
                CommitmentType: string;
                CommittedAmount: number;
                ConsumedAmount?: number;
                PeriodStart?: string | null;
                PeriodEnd?: string | null;
                TrueUpPolicy?: string;
                Status?: string;
            }[];
        }[];
        RemovedTermIDs: string[];
        RemovedLineIDs: string[];
        RemovedScheduleIDs: string[];
        RemovedCommitmentIDs: string[];
    };
    /** Field-level reasons on failure. Section maps to a workspace pane. */
    Issues?: { Section: string; Field?: string; Message: string }[];
}
