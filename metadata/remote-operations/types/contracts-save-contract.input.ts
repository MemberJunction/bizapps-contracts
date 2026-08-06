/**
 * Input for `Contracts.SaveContract`.
 *
 * ONE PAYLOAD FOR THE WHOLE AGREEMENT — contract, terms, coverage, billing plans and commitments.
 * A browser cannot compose that through `BaseEntity`: the class it holds is the generated entity,
 * and the child collections live on the server subclass. So the client builds a `ContractDraft`,
 * calls `ToInput()`, and the server rehydrates it into the real tree and saves it once.
 *
 * REMOVALS ARE NAMED, never inferred from absence. A client that loaded a contract lazily holds
 * only some of its terms; inferring deletion from what is missing would silently delete the rest.
 *
 * NO import statements — definitions are emitted verbatim.
 */
export interface SaveContractInput {
    Contract: {
        /** Null on a new contract. Set to update an existing one. */
        ID?: string | null;
        /** Never honoured on a NEW contract — allocated from the sequence inside the transaction. */
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
}
