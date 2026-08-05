import { BaseEntity, EntitySaveOptions, EntityDeleteOptions, CompositeKey, ValidationResult, ValidationErrorInfo, ValidationErrorType, Metadata, ProviderType, DatabaseProviderBase } from "@memberjunction/core";
import { RegisterClass } from "@memberjunction/global";
import { z } from "zod";

export const loadModule = () => {
  // no-op, only used to ensure this file is a valid module and to allow easy loading
}

     
 
/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Amendments
 */
export const mjBizAppsContractsContractAmendmentSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractTermID: z.string().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    AmendmentNumber: z.number().describe(`
        * * Field Name: AmendmentNumber
        * * Display Name: Amendment Number
        * * SQL Data Type: int`),
    EffectiveDate: z.date().describe(`
        * * Field Name: EffectiveDate
        * * Display Name: Effective Date
        * * SQL Data Type: date`),
    AmendmentType: z.union([z.literal('AddProduct'), z.literal('ChangePrice'), z.literal('ChangeQuantity'), z.literal('Coterm'), z.literal('Other'), z.literal('PartialTerminate')]).describe(`
        * * Field Name: AmendmentType
        * * Display Name: Amendment Type
        * * SQL Data Type: nvarchar(30)
    * * Value List Type: List
    * * Possible Values 
    *   * AddProduct
    *   * ChangePrice
    *   * ChangeQuantity
    *   * Coterm
    *   * Other
    *   * PartialTerminate`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    Status: z.union([z.literal('Applied'), z.literal('Approved'), z.literal('Cancelled'), z.literal('Draft'), z.literal('PendingApproval'), z.literal('Rejected')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Draft
    * * Value List Type: List
    * * Possible Values 
    *   * Applied
    *   * Approved
    *   * Cancelled
    *   * Draft
    *   * PendingApproval
    *   * Rejected`),
    ApprovalTaskID: z.string().nullable().describe(`
        * * Field Name: ApprovalTaskID
        * * Display Name: Approval Task ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
        * * Description: The bizapps-tasks Task gating this amendment. Raised for non-standard terms, discounts beyond a rep's SalesAuthority, and early-termination waivers; TaskType OnComplete/OnReject hooks call back into contracts to advance or reject.`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    ApprovalTask: z.string().nullable().describe(`
        * * Field Name: ApprovalTask
        * * Display Name: Approval Task
        * * SQL Data Type: nvarchar(255)`),
});

export type mjBizAppsContractsContractAmendmentEntityType = z.infer<typeof mjBizAppsContractsContractAmendmentSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Billing Events
 */
export const mjBizAppsContractsContractBillingEventSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractBillingScheduleID: z.string().nullable().describe(`
        * * Field Name: ContractBillingScheduleID
        * * Display Name: Contract Billing Schedule ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Billing Schedules (vwContractBillingSchedules.ID)`),
    ContractTermID: z.string().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    ScheduledDate: z.date().describe(`
        * * Field Name: ScheduledDate
        * * Display Name: Scheduled Date
        * * SQL Data Type: date`),
    Status: z.union([z.literal('Failed'), z.literal('Generated'), z.literal('Scheduled'), z.literal('Skipped')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Scheduled
    * * Value List Type: List
    * * Possible Values 
    *   * Failed
    *   * Generated
    *   * Scheduled
    *   * Skipped`),
    OrderID: z.string().nullable().describe(`
        * * Field Name: OrderID
        * * Display Name: Order ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Orders: Order Headers (vwOrderHeaders.ID)
        * * Description: The ONE consolidated order this event produced, via Orders.CreateOrderInState. A legal downward reference: contracts sits above orders. Status=Generated requires it, which is what makes the status transition a real idempotency guard.`),
    ComputedAmount: z.number().nullable().describe(`
        * * Field Name: ComputedAmount
        * * Display Name: Computed Amount
        * * SQL Data Type: decimal(19, 4)
        * * Description: A STAMP of the total Orders.PreviewOrder returned — never a figure computed in this app. Contracts decides WHAT to bill and never what it costs.`),
    GeneratedAt: z.date().nullable().describe(`
        * * Field Name: GeneratedAt
        * * Display Name: Generated At
        * * SQL Data Type: datetimeoffset`),
    FailureReason: z.string().nullable().describe(`
        * * Field Name: FailureReason
        * * Display Name: Failure Reason
        * * SQL Data Type: nvarchar(MAX)`),
    Notes: z.string().nullable().describe(`
        * * Field Name: Notes
        * * Display Name: Notes
        * * SQL Data Type: nvarchar(MAX)`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
});

export type mjBizAppsContractsContractBillingEventEntityType = z.infer<typeof mjBizAppsContractsContractBillingEventSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Billing Schedules
 */
export const mjBizAppsContractsContractBillingScheduleSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractTermID: z.string().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    ScheduleType: z.union([z.literal('Cadence'), z.literal('Custom'), z.literal('Milestone')]).describe(`
        * * Field Name: ScheduleType
        * * Display Name: Schedule Type
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Cadence
    *   * Custom
    *   * Milestone`),
    Frequency: z.union([z.literal('Annual'), z.literal('Custom'), z.literal('Milestone'), z.literal('Monthly'), z.literal('Quarterly'), z.literal('SemiAnnual')]).nullable().describe(`
        * * Field Name: Frequency
        * * Display Name: Frequency
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual`),
    AnchorDate: z.date().nullable().describe(`
        * * Field Name: AnchorDate
        * * Display Name: Anchor Date
        * * SQL Data Type: date`),
    IsActive: z.boolean().describe(`
        * * Field Name: IsActive
        * * Display Name: Is Active
        * * SQL Data Type: bit
        * * Default Value: 1`),
    Notes: z.string().nullable().describe(`
        * * Field Name: Notes
        * * Display Name: Notes
        * * SQL Data Type: nvarchar(MAX)`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
});

export type mjBizAppsContractsContractBillingScheduleEntityType = z.infer<typeof mjBizAppsContractsContractBillingScheduleSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Commitments
 */
export const mjBizAppsContractsContractCommitmentSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractTermID: z.string().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    CommitmentType: z.union([z.literal('Draw'), z.literal('Minimum'), z.literal('Prepaid')]).describe(`
        * * Field Name: CommitmentType
        * * Display Name: Commitment Type
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Draw
    *   * Minimum
    *   * Prepaid`),
    CommittedAmount: z.number().describe(`
        * * Field Name: CommittedAmount
        * * Display Name: Committed Amount
        * * SQL Data Type: decimal(19, 4)`),
    ConsumedAmount: z.number().describe(`
        * * Field Name: ConsumedAmount
        * * Display Name: Consumed Amount
        * * SQL Data Type: decimal(19, 4)
        * * Default Value: 0`),
    PeriodStart: z.date().nullable().describe(`
        * * Field Name: PeriodStart
        * * Display Name: Period Start
        * * SQL Data Type: date`),
    PeriodEnd: z.date().nullable().describe(`
        * * Field Name: PeriodEnd
        * * Display Name: Period End
        * * SQL Data Type: date`),
    TrueUpPolicy: z.union([z.literal('BillShortfall'), z.literal('Forfeit'), z.literal('Rollover')]).describe(`
        * * Field Name: TrueUpPolicy
        * * Display Name: True Up Policy
        * * SQL Data Type: nvarchar(20)
        * * Default Value: BillShortfall
    * * Value List Type: List
    * * Possible Values 
    *   * BillShortfall
    *   * Forfeit
    *   * Rollover
        * * Description: What happens to an unconsumed minimum at period end: BillShortfall adds the gap to the next bill, Forfeit drops it, Rollover carries it forward.`),
    Status: z.union([z.literal('Closed'), z.literal('Forfeited'), z.literal('Open'), z.literal('TruedUp')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Open
    * * Value List Type: List
    * * Possible Values 
    *   * Closed
    *   * Forfeited
    *   * Open
    *   * TruedUp`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
});

export type mjBizAppsContractsContractCommitmentEntityType = z.infer<typeof mjBizAppsContractsContractCommitmentSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Events
 */
export const mjBizAppsContractsContractEventSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractID: z.string().describe(`
        * * Field Name: ContractID
        * * Display Name: Contract ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)`),
    ContractTermID: z.string().nullable().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    EventType: z.string().describe(`
        * * Field Name: EventType
        * * Display Name: Event Type
        * * SQL Data Type: nvarchar(50)`),
    EventDate: z.date().describe(`
        * * Field Name: EventDate
        * * Display Name: Event Date
        * * SQL Data Type: datetimeoffset
        * * Default Value: sysdatetimeoffset()`),
    Payload: z.string().nullable().describe(`
        * * Field Name: Payload
        * * Display Name: Payload
        * * SQL Data Type: nvarchar(MAX)`),
    PerformedByUserID: z.string().nullable().describe(`
        * * Field Name: PerformedByUserID
        * * Display Name: Performed By User ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Users (vwUsers.ID)`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    PerformedByUser: z.string().nullable().describe(`
        * * Field Name: PerformedByUser
        * * Display Name: Performed By User
        * * SQL Data Type: nvarchar(100)`),
});

export type mjBizAppsContractsContractEventEntityType = z.infer<typeof mjBizAppsContractsContractEventSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Lines
 */
export const mjBizAppsContractsContractLineSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractTermID: z.string().describe(`
        * * Field Name: ContractTermID
        * * Display Name: Contract Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)`),
    ProductID: z.string().describe(`
        * * Field Name: ProductID
        * * Display Name: Product ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Orders: Products (vwProducts.ID)`),
    LineType: z.union([z.literal('Milestone'), z.literal('Minimum'), z.literal('OneTime'), z.literal('Subscription'), z.literal('Usage')]).describe(`
        * * Field Name: LineType
        * * Display Name: Line Type
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Milestone
    *   * Minimum
    *   * OneTime
    *   * Subscription
    *   * Usage
        * * Description: Subscription | OneTime | Milestone | Usage | Minimum. Usage is present in the value list although usage metering is out of v1, so the schema need not change when metering arrives.`),
    Quantity: z.number().describe(`
        * * Field Name: Quantity
        * * Display Name: Quantity
        * * SQL Data Type: decimal(18, 4)
        * * Default Value: 1`),
    ContractedUnitPrice: z.number().nullable().describe(`
        * * Field Name: ContractedUnitPrice
        * * Display Name: Contracted Unit Price
        * * SQL Data Type: decimal(19, 4)
        * * Description: The negotiated per-unit price. NULL means RESOLVE NORMALLY — the line is covered by the agreement but priced from the catalog. A non-null value is what ContractPriceResolver returns into orders' pricing walk; escalation is applied by the resolver at billing time, not stored here.`),
    DiscountPct: z.number().nullable().describe(`
        * * Field Name: DiscountPct
        * * Display Name: Discount Pct
        * * SQL Data Type: decimal(7, 4)`),
    StartDate: z.date().nullable().describe(`
        * * Field Name: StartDate
        * * Display Name: Start Date
        * * SQL Data Type: date`),
    EndDate: z.date().nullable().describe(`
        * * Field Name: EndDate
        * * Display Name: End Date
        * * SQL Data Type: date
        * * Description: Co-term stubs live here: a line added mid-term starts at the amendment date and ends at the TERM's end date, so the stub prorates on the next billing event. This is the capability standalone subscriptions structurally cannot provide, and the reason the contract owns the calendar.`),
    SubscriptionID: z.string().nullable().describe(`
        * * Field Name: SubscriptionID
        * * Display Name: Subscription ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Orders: Subscriptions (vwSubscriptions.ID)
        * * Description: The materialized orders Subscription for a LineType=Subscription line. This linkage lives HERE and points up the graph: orders never learns the word "contract", only that the subscription's BillingMode is External so SpawnRenewals skips it.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    DisplayOrder: z.number().describe(`
        * * Field Name: DisplayOrder
        * * Display Name: Display Order
        * * SQL Data Type: int
        * * Default Value: 0`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    Product: z.string().describe(`
        * * Field Name: Product
        * * Display Name: Product
        * * SQL Data Type: nvarchar(200)`),
});

export type mjBizAppsContractsContractLineEntityType = z.infer<typeof mjBizAppsContractsContractLineSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Sequences
 */
export const mjBizAppsContractsContractSequenceSchema = z.object({
    ID: z.number().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: int
        * * Default Value: 1`),
    NextSequenceNumber: z.number().describe(`
        * * Field Name: NextSequenceNumber
        * * Display Name: Next Sequence Number
        * * SQL Data Type: int
        * * Default Value: 1`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
});

export type mjBizAppsContractsContractSequenceEntityType = z.infer<typeof mjBizAppsContractsContractSequenceSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Terms
 */
export const mjBizAppsContractsContractTermSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractID: z.string().describe(`
        * * Field Name: ContractID
        * * Display Name: Contract ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)`),
    TermNumber: z.number().describe(`
        * * Field Name: TermNumber
        * * Display Name: Term Number
        * * SQL Data Type: int`),
    StartDate: z.date().describe(`
        * * Field Name: StartDate
        * * Display Name: Start Date
        * * SQL Data Type: date`),
    EndDate: z.date().describe(`
        * * Field Name: EndDate
        * * Display Name: End Date
        * * SQL Data Type: date`),
    Status: z.union([z.literal('Active'), z.literal('Completed'), z.literal('Pending'), z.literal('PendingSignature'), z.literal('Terminated')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Pending
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Completed
    *   * Pending
    *   * PendingSignature
    *   * Terminated`),
    RenewalOfTermID: z.string().nullable().describe(`
        * * Field Name: RenewalOfTermID
        * * Display Name: Renewal Of Term ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
        * * Description: Self-FK chaining back to the term this one renewed, making the renewal history navigable without a separate lineage table.`),
    CommittedAmount: z.number().nullable().describe(`
        * * Field Name: CommittedAmount
        * * Display Name: Committed Amount
        * * SQL Data Type: decimal(19, 4)`),
    EscalationPercent: z.number().nullable().describe(`
        * * Field Name: EscalationPercent
        * * Display Name: Escalation Percent
        * * SQL Data Type: decimal(7, 4)
        * * Description: The rate increase applied at renewal, per EscalationBasis. Applied BY THE RESOLVER at billing time from the term rules — never baked into stored line prices, which then go stale.`),
    EscalationBasis: z.union([z.literal('Index'), z.literal('ListPrice'), z.literal('PriorTerm')]).nullable().describe(`
        * * Field Name: EscalationBasis
        * * Display Name: Escalation Basis
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Index
    *   * ListPrice
    *   * PriorTerm`),
    MaxEscalationPercent: z.number().nullable().describe(`
        * * Field Name: MaxEscalationPercent
        * * Display Name: Max Escalation Percent
        * * SQL Data Type: decimal(7, 4)`),
    RenewalNoticeDays: z.number().nullable().describe(`
        * * Field Name: RenewalNoticeDays
        * * Display Name: Renewal Notice Days
        * * SQL Data Type: int`),
    BillingFrequency: z.union([z.literal('Annual'), z.literal('Custom'), z.literal('Milestone'), z.literal('Monthly'), z.literal('Quarterly'), z.literal('SemiAnnual')]).describe(`
        * * Field Name: BillingFrequency
        * * Display Name: Billing Frequency
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual`),
    BillingAnchorMonth: z.number().nullable().describe(`
        * * Field Name: BillingAnchorMonth
        * * Display Name: Billing Anchor Month
        * * SQL Data Type: tinyint`),
    BillingAnchorDay: z.number().nullable().describe(`
        * * Field Name: BillingAnchorDay
        * * Display Name: Billing Anchor Day
        * * SQL Data Type: tinyint`),
    PaymentTermsTypeID: z.string().nullable().describe(`
        * * Field Name: PaymentTermsTypeID
        * * Display Name: Payment Terms Type ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Orders: Payment Terms Types (vwPaymentTermsTypes.ID)`),
    CurrencyID: z.string().nullable().describe(`
        * * Field Name: CurrencyID
        * * Display Name: Currency ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Accounting: Currencies (vwCurrencies.ID)
        * * Description: Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in this app converts between currencies. It exists so a term states the currency it was written in, rather than that being inferred from the selling company years later.`),
    EarlyTerminationDate: z.date().nullable().describe(`
        * * Field Name: EarlyTerminationDate
        * * Display Name: Early Termination Date
        * * SQL Data Type: date`),
    RenewalProbability: z.number().nullable().describe(`
        * * Field Name: RenewalProbability
        * * Display Name: Renewal Probability
        * * SQL Data Type: decimal(5, 4)
        * * Description: 0..1 likelihood this term renews. Exists because a renewal forecast in bizapps-sales reads it.`),
    ExecutedDate: z.date().nullable().describe(`
        * * Field Name: ExecutedDate
        * * Display Name: Executed Date
        * * SQL Data Type: date`),
    Notes: z.string().nullable().describe(`
        * * Field Name: Notes
        * * Display Name: Notes
        * * SQL Data Type: nvarchar(MAX)`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    PaymentTermsType: z.string().nullable().describe(`
        * * Field Name: PaymentTermsType
        * * Display Name: Payment Terms Type
        * * SQL Data Type: nvarchar(200)`),
    Currency: z.string().nullable().describe(`
        * * Field Name: Currency
        * * Display Name: Currency
        * * SQL Data Type: nvarchar(80)`),
    RootRenewalOfTermID: z.string().nullable().describe(`
        * * Field Name: RootRenewalOfTermID
        * * Display Name: Root Renewal Of Term ID
        * * SQL Data Type: uniqueidentifier`),
});

export type mjBizAppsContractsContractTermEntityType = z.infer<typeof mjBizAppsContractsContractTermSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Types
 */
export const mjBizAppsContractsContractTypeSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    Code: z.string().describe(`
        * * Field Name: Code
        * * Display Name: Code
        * * SQL Data Type: nvarchar(50)
        * * Description: Stable machine key, unique. Referenced by CloseWonPolicy in bizapps-sales, so renaming Name is safe and changing Code is not.`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(100)`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    DefaultTermMonths: z.number().nullable().describe(`
        * * Field Name: DefaultTermMonths
        * * Display Name: Default Term Months
        * * SQL Data Type: int`),
    DefaultBillingFrequency: z.union([z.literal('Annual'), z.literal('Custom'), z.literal('Milestone'), z.literal('Monthly'), z.literal('Quarterly'), z.literal('SemiAnnual')]).nullable().describe(`
        * * Field Name: DefaultBillingFrequency
        * * Display Name: Default Billing Frequency
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual`),
    DefaultAutoRenew: z.boolean().describe(`
        * * Field Name: DefaultAutoRenew
        * * Display Name: Default Auto Renew
        * * SQL Data Type: bit
        * * Default Value: 0`),
    RequiresSignature: z.boolean().describe(`
        * * Field Name: RequiresSignature
        * * Display Name: Requires Signature
        * * SQL Data Type: bit
        * * Default Value: 1`),
    DefaultEscalationPercent: z.number().nullable().describe(`
        * * Field Name: DefaultEscalationPercent
        * * Display Name: Default Escalation Percent
        * * SQL Data Type: decimal(7, 4)`),
    DefaultMaxEscalationPercent: z.number().nullable().describe(`
        * * Field Name: DefaultMaxEscalationPercent
        * * Display Name: Default Max Escalation Percent
        * * SQL Data Type: decimal(7, 4)`),
    DefaultRenewalNoticeDays: z.number().nullable().describe(`
        * * Field Name: DefaultRenewalNoticeDays
        * * Display Name: Default Renewal Notice Days
        * * SQL Data Type: int`),
    DefaultCancellationWindowDays: z.number().nullable().describe(`
        * * Field Name: DefaultCancellationWindowDays
        * * Display Name: Default Cancellation Window Days
        * * SQL Data Type: int`),
    RenewalMode: z.union([z.literal('Auto'), z.literal('Deal'), z.literal('Manual')]).describe(`
        * * Field Name: RenewalMode
        * * Display Name: Renewal Mode
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Deal
    * * Value List Type: List
    * * Possible Values 
    *   * Auto
    *   * Deal
    *   * Manual
        * * Description: How a term of this type renews. Deal = a renewal is a deal (L-18); bizapps-sales calls Contracts.RenewTerm when a renewal deal closes, so renewal gets its own pipeline and win-rate. Auto = the Scheduled Job renews with no deal, for evergreen and B2C. Manual = a human triggers it.`),
    AllowsCoterm: z.boolean().describe(`
        * * Field Name: AllowsCoterm
        * * Display Name: Allows Coterm
        * * SQL Data Type: bit
        * * Default Value: 1
        * * Description: Whether a term of this type may absorb a mid-term addition aligned to the term end date (co-terming).`),
    DriverClass: z.string().nullable().describe(`
        * * Field Name: DriverClass
        * * Display Name: Driver Class
        * * SQL Data Type: nvarchar(255)
        * * Description: OPTIONAL ClassFactory key for a behaviour subclass, following SubscriptionType rather than RevenueRecognitionType: the columns ARE the rules and a base class reads them. Supply a driver only when a customer needs something the columns cannot express.`),
    IsActive: z.boolean().describe(`
        * * Field Name: IsActive
        * * Display Name: Is Active
        * * SQL Data Type: bit
        * * Default Value: 1`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
});

export type mjBizAppsContractsContractTypeEntityType = z.infer<typeof mjBizAppsContractsContractTypeSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contracts
 */
export const mjBizAppsContractsContractSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractNumber: z.string().describe(`
        * * Field Name: ContractNumber
        * * Display Name: Contract Number
        * * SQL Data Type: nvarchar(50)
        * * Description: CTR-{seq} from ContractSequence. Unique.`),
    ContractTypeID: z.string().describe(`
        * * Field Name: ContractTypeID
        * * Display Name: Contract Type ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Types (vwContractTypes.ID)`),
    CompanyID: z.string().describe(`
        * * Field Name: CompanyID
        * * Display Name: Company ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Companies (vwCompanies.ID)
        * * Description: The SELLING company (__mj.Company) — which of our entities holds this agreement. Not the customer.`),
    CustomerOrganizationID: z.string().nullable().describe(`
        * * Field Name: CustomerOrganizationID
        * * Display Name: Customer Organization ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
        * * Description: The customer, when the customer is an organization. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.`),
    CustomerPersonID: z.string().nullable().describe(`
        * * Field Name: CustomerPersonID
        * * Display Name: Customer Person ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
        * * Description: The customer, when the customer is an individual. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.`),
    PrimaryContactPersonID: z.string().nullable().describe(`
        * * Field Name: PrimaryContactPersonID
        * * Display Name: Primary Contact Person ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)`),
    OwnerUserID: z.string().nullable().describe(`
        * * Field Name: OwnerUserID
        * * Display Name: Owner User ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Users (vwUsers.ID)`),
    ParentContractID: z.string().nullable().describe(`
        * * Field Name: ParentContractID
        * * Display Name: Parent Contract ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
        * * Description: Self-FK for MSA -> SOW nesting (D-5). Modelled as a self-reference rather than a distinct Agreement entity until the two genuinely diverge.`),
    SupersededByContractID: z.string().nullable().describe(`
        * * Field Name: SupersededByContractID
        * * Display Name: Superseded By Contract ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)`),
    Status: z.union([z.literal('Active'), z.literal('Draft'), z.literal('Expired'), z.literal('PendingSignature'), z.literal('Superseded'), z.literal('Terminated')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(30)
        * * Default Value: Draft
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Draft
    *   * Expired
    *   * PendingSignature
    *   * Superseded
    *   * Terminated`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    EffectiveDate: z.date().nullable().describe(`
        * * Field Name: EffectiveDate
        * * Display Name: Effective Date
        * * SQL Data Type: date`),
    ExecutedDate: z.date().nullable().describe(`
        * * Field Name: ExecutedDate
        * * Display Name: Executed Date
        * * SQL Data Type: date`),
    AutoRenew: z.boolean().describe(`
        * * Field Name: AutoRenew
        * * Display Name: Auto Renew
        * * SQL Data Type: bit
        * * Default Value: 0`),
    CancellationWindowDays: z.number().nullable().describe(`
        * * Field Name: CancellationWindowDays
        * * Display Name: Cancellation Window Days
        * * SQL Data Type: int`),
    TerminationPolicy: z.string().nullable().describe(`
        * * Field Name: TerminationPolicy
        * * Display Name: Termination Policy
        * * SQL Data Type: nvarchar(MAX)`),
    ExternalReferenceID: z.string().nullable().describe(`
        * * Field Name: ExternalReferenceID
        * * Display Name: External Reference ID
        * * SQL Data Type: nvarchar(255)`),
    __mj_CreatedAt: z.date().describe(`
        * * Field Name: __mj_CreatedAt
        * * Display Name: Created At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    __mj_UpdatedAt: z.date().describe(`
        * * Field Name: __mj_UpdatedAt
        * * Display Name: Updated At
        * * SQL Data Type: datetimeoffset
        * * Default Value: getutcdate()`),
    ContractType: z.string().describe(`
        * * Field Name: ContractType
        * * Display Name: Contract Type
        * * SQL Data Type: nvarchar(100)`),
    Company: z.string().describe(`
        * * Field Name: Company
        * * Display Name: Company
        * * SQL Data Type: nvarchar(50)`),
    CustomerOrganization: z.string().nullable().describe(`
        * * Field Name: CustomerOrganization
        * * Display Name: Customer Organization
        * * SQL Data Type: nvarchar(255)`),
    CustomerPerson: z.string().nullable().describe(`
        * * Field Name: CustomerPerson
        * * Display Name: Customer Person
        * * SQL Data Type: nvarchar(201)`),
    PrimaryContactPerson: z.string().nullable().describe(`
        * * Field Name: PrimaryContactPerson
        * * Display Name: Primary Contact Person
        * * SQL Data Type: nvarchar(201)`),
    OwnerUser: z.string().nullable().describe(`
        * * Field Name: OwnerUser
        * * Display Name: Owner User
        * * SQL Data Type: nvarchar(100)`),
    RootParentContractID: z.string().nullable().describe(`
        * * Field Name: RootParentContractID
        * * Display Name: Root Parent Contract ID
        * * SQL Data Type: uniqueidentifier`),
    RootSupersededByContractID: z.string().nullable().describe(`
        * * Field Name: RootSupersededByContractID
        * * Display Name: Root Superseded By Contract ID
        * * SQL Data Type: uniqueidentifier`),
});

export type mjBizAppsContractsContractEntityType = z.infer<typeof mjBizAppsContractsContractSchema>;
 
 

/**
 * MJ_BizApps_Contracts: Contract Amendments - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractAmendment
 * * Base View: vwContractAmendments
 * * @description A mid-term change to a LIVE term. Renewals do NOT come through here — they start a new ContractTerm with RenewalOfTermID set.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Amendments')
export class mjBizAppsContractsContractAmendmentEntity extends BaseEntity<mjBizAppsContractsContractAmendmentEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Amendments record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Amendments record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractAmendmentEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: AmendmentNumber
    * * Display Name: Amendment Number
    * * SQL Data Type: int
    */
    get AmendmentNumber(): number {
        return this.Get('AmendmentNumber');
    }
    set AmendmentNumber(value: number) {
        this.Set('AmendmentNumber', value);
    }

    /**
    * * Field Name: EffectiveDate
    * * Display Name: Effective Date
    * * SQL Data Type: date
    */
    get EffectiveDate(): Date {
        return this.Get('EffectiveDate');
    }
    set EffectiveDate(value: Date) {
        this.Set('EffectiveDate', value);
    }

    /**
    * * Field Name: AmendmentType
    * * Display Name: Amendment Type
    * * SQL Data Type: nvarchar(30)
    * * Value List Type: List
    * * Possible Values 
    *   * AddProduct
    *   * ChangePrice
    *   * ChangeQuantity
    *   * Coterm
    *   * Other
    *   * PartialTerminate
    */
    get AmendmentType(): 'AddProduct' | 'ChangePrice' | 'ChangeQuantity' | 'Coterm' | 'Other' | 'PartialTerminate' {
        return this.Get('AmendmentType');
    }
    set AmendmentType(value: 'AddProduct' | 'ChangePrice' | 'ChangeQuantity' | 'Coterm' | 'Other' | 'PartialTerminate') {
        this.Set('AmendmentType', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(20)
    * * Default Value: Draft
    * * Value List Type: List
    * * Possible Values 
    *   * Applied
    *   * Approved
    *   * Cancelled
    *   * Draft
    *   * PendingApproval
    *   * Rejected
    */
    get Status(): 'Applied' | 'Approved' | 'Cancelled' | 'Draft' | 'PendingApproval' | 'Rejected' {
        return this.Get('Status');
    }
    set Status(value: 'Applied' | 'Approved' | 'Cancelled' | 'Draft' | 'PendingApproval' | 'Rejected') {
        this.Set('Status', value);
    }

    /**
    * * Field Name: ApprovalTaskID
    * * Display Name: Approval Task ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Tasks: Tasks (vwTasks.ID)
    * * Description: The bizapps-tasks Task gating this amendment. Raised for non-standard terms, discounts beyond a rep's SalesAuthority, and early-termination waivers; TaskType OnComplete/OnReject hooks call back into contracts to advance or reject.
    */
    get ApprovalTaskID(): string | null {
        return this.Get('ApprovalTaskID');
    }
    set ApprovalTaskID(value: string | null) {
        this.Set('ApprovalTaskID', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: ApprovalTask
    * * Display Name: Approval Task
    * * SQL Data Type: nvarchar(255)
    */
    get ApprovalTask(): string | null {
        return this.Get('ApprovalTask');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Billing Events - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractBillingEvent
 * * Base View: vwContractBillingEvents
 * * @description Each billing occurrence AND the audit trail: the record that answers "why did the customer get this bill on this date, and what produced it". A failure stays Failed with a reason rather than retrying into a duplicate — duplicate billing is the kind of defect a customer finds before we do.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Billing Events')
export class mjBizAppsContractsContractBillingEventEntity extends BaseEntity<mjBizAppsContractsContractBillingEventEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Billing Events record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Billing Events record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractBillingEventEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractBillingScheduleID
    * * Display Name: Contract Billing Schedule ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Billing Schedules (vwContractBillingSchedules.ID)
    */
    get ContractBillingScheduleID(): string | null {
        return this.Get('ContractBillingScheduleID');
    }
    set ContractBillingScheduleID(value: string | null) {
        this.Set('ContractBillingScheduleID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: ScheduledDate
    * * Display Name: Scheduled Date
    * * SQL Data Type: date
    */
    get ScheduledDate(): Date {
        return this.Get('ScheduledDate');
    }
    set ScheduledDate(value: Date) {
        this.Set('ScheduledDate', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(20)
    * * Default Value: Scheduled
    * * Value List Type: List
    * * Possible Values 
    *   * Failed
    *   * Generated
    *   * Scheduled
    *   * Skipped
    */
    get Status(): 'Failed' | 'Generated' | 'Scheduled' | 'Skipped' {
        return this.Get('Status');
    }
    set Status(value: 'Failed' | 'Generated' | 'Scheduled' | 'Skipped') {
        this.Set('Status', value);
    }

    /**
    * * Field Name: OrderID
    * * Display Name: Order ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Orders: Order Headers (vwOrderHeaders.ID)
    * * Description: The ONE consolidated order this event produced, via Orders.CreateOrderInState. A legal downward reference: contracts sits above orders. Status=Generated requires it, which is what makes the status transition a real idempotency guard.
    */
    get OrderID(): string | null {
        return this.Get('OrderID');
    }
    set OrderID(value: string | null) {
        this.Set('OrderID', value);
    }

    /**
    * * Field Name: ComputedAmount
    * * Display Name: Computed Amount
    * * SQL Data Type: decimal(19, 4)
    * * Description: A STAMP of the total Orders.PreviewOrder returned — never a figure computed in this app. Contracts decides WHAT to bill and never what it costs.
    */
    get ComputedAmount(): number | null {
        return this.Get('ComputedAmount');
    }
    set ComputedAmount(value: number | null) {
        this.Set('ComputedAmount', value);
    }

    /**
    * * Field Name: GeneratedAt
    * * Display Name: Generated At
    * * SQL Data Type: datetimeoffset
    */
    get GeneratedAt(): Date | null {
        return this.Get('GeneratedAt');
    }
    set GeneratedAt(value: Date | null) {
        this.Set('GeneratedAt', value);
    }

    /**
    * * Field Name: FailureReason
    * * Display Name: Failure Reason
    * * SQL Data Type: nvarchar(MAX)
    */
    get FailureReason(): string | null {
        return this.Get('FailureReason');
    }
    set FailureReason(value: string | null) {
        this.Set('FailureReason', value);
    }

    /**
    * * Field Name: Notes
    * * Display Name: Notes
    * * SQL Data Type: nvarchar(MAX)
    */
    get Notes(): string | null {
        return this.Get('Notes');
    }
    set Notes(value: string | null) {
        this.Set('Notes', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Billing Schedules - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractBillingSchedule
 * * Base View: vwContractBillingSchedules
 * * @description How a term produces bills. One term may carry MORE THAN ONE schedule — a quarterly subscription cadence AND a milestone schedule for an attached SOW.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Billing Schedules')
export class mjBizAppsContractsContractBillingScheduleEntity extends BaseEntity<mjBizAppsContractsContractBillingScheduleEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Billing Schedules record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Billing Schedules record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractBillingScheduleEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: ScheduleType
    * * Display Name: Schedule Type
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Cadence
    *   * Custom
    *   * Milestone
    */
    get ScheduleType(): 'Cadence' | 'Custom' | 'Milestone' {
        return this.Get('ScheduleType');
    }
    set ScheduleType(value: 'Cadence' | 'Custom' | 'Milestone') {
        this.Set('ScheduleType', value);
    }

    /**
    * * Field Name: Frequency
    * * Display Name: Frequency
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual
    */
    get Frequency(): 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual' | null {
        return this.Get('Frequency');
    }
    set Frequency(value: 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual' | null) {
        this.Set('Frequency', value);
    }

    /**
    * * Field Name: AnchorDate
    * * Display Name: Anchor Date
    * * SQL Data Type: date
    */
    get AnchorDate(): Date | null {
        return this.Get('AnchorDate');
    }
    set AnchorDate(value: Date | null) {
        this.Set('AnchorDate', value);
    }

    /**
    * * Field Name: IsActive
    * * Display Name: Is Active
    * * SQL Data Type: bit
    * * Default Value: 1
    */
    get IsActive(): boolean {
        return this.Get('IsActive');
    }
    set IsActive(value: boolean) {
        this.Set('IsActive', value);
    }

    /**
    * * Field Name: Notes
    * * Display Name: Notes
    * * SQL Data Type: nvarchar(MAX)
    */
    get Notes(): string | null {
        return this.Get('Notes');
    }
    set Notes(value: string | null) {
        this.Set('Notes', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Commitments - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractCommitment
 * * Base View: vwContractCommitments
 * * @description Minimums, prepaid draws and true-ups. ConsumedAmount is deliberately NOT capped at CommittedAmount: over-consumption against a minimum is a real state to record and report, not an error to reject at write time.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Commitments')
export class mjBizAppsContractsContractCommitmentEntity extends BaseEntity<mjBizAppsContractsContractCommitmentEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Commitments record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Commitments record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractCommitmentEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: CommitmentType
    * * Display Name: Commitment Type
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Draw
    *   * Minimum
    *   * Prepaid
    */
    get CommitmentType(): 'Draw' | 'Minimum' | 'Prepaid' {
        return this.Get('CommitmentType');
    }
    set CommitmentType(value: 'Draw' | 'Minimum' | 'Prepaid') {
        this.Set('CommitmentType', value);
    }

    /**
    * * Field Name: CommittedAmount
    * * Display Name: Committed Amount
    * * SQL Data Type: decimal(19, 4)
    */
    get CommittedAmount(): number {
        return this.Get('CommittedAmount');
    }
    set CommittedAmount(value: number) {
        this.Set('CommittedAmount', value);
    }

    /**
    * * Field Name: ConsumedAmount
    * * Display Name: Consumed Amount
    * * SQL Data Type: decimal(19, 4)
    * * Default Value: 0
    */
    get ConsumedAmount(): number {
        return this.Get('ConsumedAmount');
    }
    set ConsumedAmount(value: number) {
        this.Set('ConsumedAmount', value);
    }

    /**
    * * Field Name: PeriodStart
    * * Display Name: Period Start
    * * SQL Data Type: date
    */
    get PeriodStart(): Date | null {
        return this.Get('PeriodStart');
    }
    set PeriodStart(value: Date | null) {
        this.Set('PeriodStart', value);
    }

    /**
    * * Field Name: PeriodEnd
    * * Display Name: Period End
    * * SQL Data Type: date
    */
    get PeriodEnd(): Date | null {
        return this.Get('PeriodEnd');
    }
    set PeriodEnd(value: Date | null) {
        this.Set('PeriodEnd', value);
    }

    /**
    * * Field Name: TrueUpPolicy
    * * Display Name: True Up Policy
    * * SQL Data Type: nvarchar(20)
    * * Default Value: BillShortfall
    * * Value List Type: List
    * * Possible Values 
    *   * BillShortfall
    *   * Forfeit
    *   * Rollover
    * * Description: What happens to an unconsumed minimum at period end: BillShortfall adds the gap to the next bill, Forfeit drops it, Rollover carries it forward.
    */
    get TrueUpPolicy(): 'BillShortfall' | 'Forfeit' | 'Rollover' {
        return this.Get('TrueUpPolicy');
    }
    set TrueUpPolicy(value: 'BillShortfall' | 'Forfeit' | 'Rollover') {
        this.Set('TrueUpPolicy', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(20)
    * * Default Value: Open
    * * Value List Type: List
    * * Possible Values 
    *   * Closed
    *   * Forfeited
    *   * Open
    *   * TruedUp
    */
    get Status(): 'Closed' | 'Forfeited' | 'Open' | 'TruedUp' {
        return this.Get('Status');
    }
    set Status(value: 'Closed' | 'Forfeited' | 'Open' | 'TruedUp') {
        this.Set('Status', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Events - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractEvent
 * * Base View: vwContractEvents
 * * @description Immutable lifecycle log, mirroring orders' SubscriptionEvent. Never edited, never deleted. This is the SYSTEM record; customer-visible events also write a common.Activity row so the agreement appears on the account timeline. Neither replaces the other.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Events')
export class mjBizAppsContractsContractEventEntity extends BaseEntity<mjBizAppsContractsContractEventEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Events record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Events record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractEventEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractID
    * * Display Name: Contract ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    */
    get ContractID(): string {
        return this.Get('ContractID');
    }
    set ContractID(value: string) {
        this.Set('ContractID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string | null {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string | null) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: EventType
    * * Display Name: Event Type
    * * SQL Data Type: nvarchar(50)
    */
    get EventType(): string {
        return this.Get('EventType');
    }
    set EventType(value: string) {
        this.Set('EventType', value);
    }

    /**
    * * Field Name: EventDate
    * * Display Name: Event Date
    * * SQL Data Type: datetimeoffset
    * * Default Value: sysdatetimeoffset()
    */
    get EventDate(): Date {
        return this.Get('EventDate');
    }
    set EventDate(value: Date) {
        this.Set('EventDate', value);
    }

    /**
    * * Field Name: Payload
    * * Display Name: Payload
    * * SQL Data Type: nvarchar(MAX)
    */
    get Payload(): string | null {
        return this.Get('Payload');
    }
    set Payload(value: string | null) {
        this.Set('Payload', value);
    }

    /**
    * * Field Name: PerformedByUserID
    * * Display Name: Performed By User ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ: Users (vwUsers.ID)
    */
    get PerformedByUserID(): string | null {
        return this.Get('PerformedByUserID');
    }
    set PerformedByUserID(value: string | null) {
        this.Set('PerformedByUserID', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: PerformedByUser
    * * Display Name: Performed By User
    * * SQL Data Type: nvarchar(100)
    */
    get PerformedByUser(): string | null {
        return this.Get('PerformedByUser');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Lines - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractLine
 * * Base View: vwContractLines
 * * @description What the agreement covers. LineType is what lets ONE table serve subscriptions, one-time fees, milestone draws, usage true-ups and minimum commitments — the billing engine reads it and nothing else branches on it.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Lines')
export class mjBizAppsContractsContractLineEntity extends BaseEntity<mjBizAppsContractsContractLineEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Lines record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Lines record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractLineEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractTermID
    * * Display Name: Contract Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    */
    get ContractTermID(): string {
        return this.Get('ContractTermID');
    }
    set ContractTermID(value: string) {
        this.Set('ContractTermID', value);
    }

    /**
    * * Field Name: ProductID
    * * Display Name: Product ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Orders: Products (vwProducts.ID)
    */
    get ProductID(): string {
        return this.Get('ProductID');
    }
    set ProductID(value: string) {
        this.Set('ProductID', value);
    }

    /**
    * * Field Name: LineType
    * * Display Name: Line Type
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Milestone
    *   * Minimum
    *   * OneTime
    *   * Subscription
    *   * Usage
    * * Description: Subscription | OneTime | Milestone | Usage | Minimum. Usage is present in the value list although usage metering is out of v1, so the schema need not change when metering arrives.
    */
    get LineType(): 'Milestone' | 'Minimum' | 'OneTime' | 'Subscription' | 'Usage' {
        return this.Get('LineType');
    }
    set LineType(value: 'Milestone' | 'Minimum' | 'OneTime' | 'Subscription' | 'Usage') {
        this.Set('LineType', value);
    }

    /**
    * * Field Name: Quantity
    * * Display Name: Quantity
    * * SQL Data Type: decimal(18, 4)
    * * Default Value: 1
    */
    get Quantity(): number {
        return this.Get('Quantity');
    }
    set Quantity(value: number) {
        this.Set('Quantity', value);
    }

    /**
    * * Field Name: ContractedUnitPrice
    * * Display Name: Contracted Unit Price
    * * SQL Data Type: decimal(19, 4)
    * * Description: The negotiated per-unit price. NULL means RESOLVE NORMALLY — the line is covered by the agreement but priced from the catalog. A non-null value is what ContractPriceResolver returns into orders' pricing walk; escalation is applied by the resolver at billing time, not stored here.
    */
    get ContractedUnitPrice(): number | null {
        return this.Get('ContractedUnitPrice');
    }
    set ContractedUnitPrice(value: number | null) {
        this.Set('ContractedUnitPrice', value);
    }

    /**
    * * Field Name: DiscountPct
    * * Display Name: Discount Pct
    * * SQL Data Type: decimal(7, 4)
    */
    get DiscountPct(): number | null {
        return this.Get('DiscountPct');
    }
    set DiscountPct(value: number | null) {
        this.Set('DiscountPct', value);
    }

    /**
    * * Field Name: StartDate
    * * Display Name: Start Date
    * * SQL Data Type: date
    */
    get StartDate(): Date | null {
        return this.Get('StartDate');
    }
    set StartDate(value: Date | null) {
        this.Set('StartDate', value);
    }

    /**
    * * Field Name: EndDate
    * * Display Name: End Date
    * * SQL Data Type: date
    * * Description: Co-term stubs live here: a line added mid-term starts at the amendment date and ends at the TERM's end date, so the stub prorates on the next billing event. This is the capability standalone subscriptions structurally cannot provide, and the reason the contract owns the calendar.
    */
    get EndDate(): Date | null {
        return this.Get('EndDate');
    }
    set EndDate(value: Date | null) {
        this.Set('EndDate', value);
    }

    /**
    * * Field Name: SubscriptionID
    * * Display Name: Subscription ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Orders: Subscriptions (vwSubscriptions.ID)
    * * Description: The materialized orders Subscription for a LineType=Subscription line. This linkage lives HERE and points up the graph: orders never learns the word "contract", only that the subscription's BillingMode is External so SpawnRenewals skips it.
    */
    get SubscriptionID(): string | null {
        return this.Get('SubscriptionID');
    }
    set SubscriptionID(value: string | null) {
        this.Set('SubscriptionID', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: DisplayOrder
    * * Display Name: Display Order
    * * SQL Data Type: int
    * * Default Value: 0
    */
    get DisplayOrder(): number {
        return this.Get('DisplayOrder');
    }
    set DisplayOrder(value: number) {
        this.Set('DisplayOrder', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: Product
    * * Display Name: Product
    * * SQL Data Type: nvarchar(200)
    */
    get Product(): string {
        return this.Get('Product');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Sequences - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractSequence
 * * Base View: vwContractSequences
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Sequences')
export class mjBizAppsContractsContractSequenceEntity extends BaseEntity<mjBizAppsContractsContractSequenceEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Sequences record from the database
    * @param ID: number - primary key value to load the MJ_BizApps_Contracts: Contract Sequences record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractSequenceEntity
    * @method
    * @override
    */
    public async Load(ID: number, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: int
    * * Default Value: 1
    */
    get ID(): number {
        return this.Get('ID');
    }
    set ID(value: number) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: NextSequenceNumber
    * * Display Name: Next Sequence Number
    * * SQL Data Type: int
    * * Default Value: 1
    */
    get NextSequenceNumber(): number {
        return this.Get('NextSequenceNumber');
    }
    set NextSequenceNumber(value: number) {
        this.Set('NextSequenceNumber', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Terms - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractTerm
 * * Base View: vwContractTerms
 * * @description One period of an agreement. A RENEWAL creates a NEW term with RenewalOfTermID set; a mid-term change is a ContractAmendment against the existing one. Conflating those two is the most common contract-model mistake.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Terms')
export class mjBizAppsContractsContractTermEntity extends BaseEntity<mjBizAppsContractsContractTermEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Terms record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Terms record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTermEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractID
    * * Display Name: Contract ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    */
    get ContractID(): string {
        return this.Get('ContractID');
    }
    set ContractID(value: string) {
        this.Set('ContractID', value);
    }

    /**
    * * Field Name: TermNumber
    * * Display Name: Term Number
    * * SQL Data Type: int
    */
    get TermNumber(): number {
        return this.Get('TermNumber');
    }
    set TermNumber(value: number) {
        this.Set('TermNumber', value);
    }

    /**
    * * Field Name: StartDate
    * * Display Name: Start Date
    * * SQL Data Type: date
    */
    get StartDate(): Date {
        return this.Get('StartDate');
    }
    set StartDate(value: Date) {
        this.Set('StartDate', value);
    }

    /**
    * * Field Name: EndDate
    * * Display Name: End Date
    * * SQL Data Type: date
    */
    get EndDate(): Date {
        return this.Get('EndDate');
    }
    set EndDate(value: Date) {
        this.Set('EndDate', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(20)
    * * Default Value: Pending
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Completed
    *   * Pending
    *   * PendingSignature
    *   * Terminated
    */
    get Status(): 'Active' | 'Completed' | 'Pending' | 'PendingSignature' | 'Terminated' {
        return this.Get('Status');
    }
    set Status(value: 'Active' | 'Completed' | 'Pending' | 'PendingSignature' | 'Terminated') {
        this.Set('Status', value);
    }

    /**
    * * Field Name: RenewalOfTermID
    * * Display Name: Renewal Of Term ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Terms (vwContractTerms.ID)
    * * Description: Self-FK chaining back to the term this one renewed, making the renewal history navigable without a separate lineage table.
    */
    get RenewalOfTermID(): string | null {
        return this.Get('RenewalOfTermID');
    }
    set RenewalOfTermID(value: string | null) {
        this.Set('RenewalOfTermID', value);
    }

    /**
    * * Field Name: CommittedAmount
    * * Display Name: Committed Amount
    * * SQL Data Type: decimal(19, 4)
    */
    get CommittedAmount(): number | null {
        return this.Get('CommittedAmount');
    }
    set CommittedAmount(value: number | null) {
        this.Set('CommittedAmount', value);
    }

    /**
    * * Field Name: EscalationPercent
    * * Display Name: Escalation Percent
    * * SQL Data Type: decimal(7, 4)
    * * Description: The rate increase applied at renewal, per EscalationBasis. Applied BY THE RESOLVER at billing time from the term rules — never baked into stored line prices, which then go stale.
    */
    get EscalationPercent(): number | null {
        return this.Get('EscalationPercent');
    }
    set EscalationPercent(value: number | null) {
        this.Set('EscalationPercent', value);
    }

    /**
    * * Field Name: EscalationBasis
    * * Display Name: Escalation Basis
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Index
    *   * ListPrice
    *   * PriorTerm
    */
    get EscalationBasis(): 'Index' | 'ListPrice' | 'PriorTerm' | null {
        return this.Get('EscalationBasis');
    }
    set EscalationBasis(value: 'Index' | 'ListPrice' | 'PriorTerm' | null) {
        this.Set('EscalationBasis', value);
    }

    /**
    * * Field Name: MaxEscalationPercent
    * * Display Name: Max Escalation Percent
    * * SQL Data Type: decimal(7, 4)
    */
    get MaxEscalationPercent(): number | null {
        return this.Get('MaxEscalationPercent');
    }
    set MaxEscalationPercent(value: number | null) {
        this.Set('MaxEscalationPercent', value);
    }

    /**
    * * Field Name: RenewalNoticeDays
    * * Display Name: Renewal Notice Days
    * * SQL Data Type: int
    */
    get RenewalNoticeDays(): number | null {
        return this.Get('RenewalNoticeDays');
    }
    set RenewalNoticeDays(value: number | null) {
        this.Set('RenewalNoticeDays', value);
    }

    /**
    * * Field Name: BillingFrequency
    * * Display Name: Billing Frequency
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual
    */
    get BillingFrequency(): 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual' {
        return this.Get('BillingFrequency');
    }
    set BillingFrequency(value: 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual') {
        this.Set('BillingFrequency', value);
    }

    /**
    * * Field Name: BillingAnchorMonth
    * * Display Name: Billing Anchor Month
    * * SQL Data Type: tinyint
    */
    get BillingAnchorMonth(): number | null {
        return this.Get('BillingAnchorMonth');
    }
    set BillingAnchorMonth(value: number | null) {
        this.Set('BillingAnchorMonth', value);
    }

    /**
    * * Field Name: BillingAnchorDay
    * * Display Name: Billing Anchor Day
    * * SQL Data Type: tinyint
    */
    get BillingAnchorDay(): number | null {
        return this.Get('BillingAnchorDay');
    }
    set BillingAnchorDay(value: number | null) {
        this.Set('BillingAnchorDay', value);
    }

    /**
    * * Field Name: PaymentTermsTypeID
    * * Display Name: Payment Terms Type ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Orders: Payment Terms Types (vwPaymentTermsTypes.ID)
    */
    get PaymentTermsTypeID(): string | null {
        return this.Get('PaymentTermsTypeID');
    }
    set PaymentTermsTypeID(value: string | null) {
        this.Set('PaymentTermsTypeID', value);
    }

    /**
    * * Field Name: CurrencyID
    * * Display Name: Currency ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Accounting: Currencies (vwCurrencies.ID)
    * * Description: Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in this app converts between currencies. It exists so a term states the currency it was written in, rather than that being inferred from the selling company years later.
    */
    get CurrencyID(): string | null {
        return this.Get('CurrencyID');
    }
    set CurrencyID(value: string | null) {
        this.Set('CurrencyID', value);
    }

    /**
    * * Field Name: EarlyTerminationDate
    * * Display Name: Early Termination Date
    * * SQL Data Type: date
    */
    get EarlyTerminationDate(): Date | null {
        return this.Get('EarlyTerminationDate');
    }
    set EarlyTerminationDate(value: Date | null) {
        this.Set('EarlyTerminationDate', value);
    }

    /**
    * * Field Name: RenewalProbability
    * * Display Name: Renewal Probability
    * * SQL Data Type: decimal(5, 4)
    * * Description: 0..1 likelihood this term renews. Exists because a renewal forecast in bizapps-sales reads it.
    */
    get RenewalProbability(): number | null {
        return this.Get('RenewalProbability');
    }
    set RenewalProbability(value: number | null) {
        this.Set('RenewalProbability', value);
    }

    /**
    * * Field Name: ExecutedDate
    * * Display Name: Executed Date
    * * SQL Data Type: date
    */
    get ExecutedDate(): Date | null {
        return this.Get('ExecutedDate');
    }
    set ExecutedDate(value: Date | null) {
        this.Set('ExecutedDate', value);
    }

    /**
    * * Field Name: Notes
    * * Display Name: Notes
    * * SQL Data Type: nvarchar(MAX)
    */
    get Notes(): string | null {
        return this.Get('Notes');
    }
    set Notes(value: string | null) {
        this.Set('Notes', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: PaymentTermsType
    * * Display Name: Payment Terms Type
    * * SQL Data Type: nvarchar(200)
    */
    get PaymentTermsType(): string | null {
        return this.Get('PaymentTermsType');
    }

    /**
    * * Field Name: Currency
    * * Display Name: Currency
    * * SQL Data Type: nvarchar(80)
    */
    get Currency(): string | null {
        return this.Get('Currency');
    }

    /**
    * * Field Name: RootRenewalOfTermID
    * * Display Name: Root Renewal Of Term ID
    * * SQL Data Type: uniqueidentifier
    */
    get RootRenewalOfTermID(): string | null {
        return this.Get('RootRenewalOfTermID');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Types - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractType
 * * Base View: vwContractTypes
 * * @description Named defaults for a class of agreement (Standard, MSA, SOW, Membership, Evergreen, Pilot). Configuration as data: the engine READS these columns rather than branching on the type name.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Types')
export class mjBizAppsContractsContractTypeEntity extends BaseEntity<mjBizAppsContractsContractTypeEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Types record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Types record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTypeEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: Code
    * * Display Name: Code
    * * SQL Data Type: nvarchar(50)
    * * Description: Stable machine key, unique. Referenced by CloseWonPolicy in bizapps-sales, so renaming Name is safe and changing Code is not.
    */
    get Code(): string {
        return this.Get('Code');
    }
    set Code(value: string) {
        this.Set('Code', value);
    }

    /**
    * * Field Name: Name
    * * Display Name: Name
    * * SQL Data Type: nvarchar(100)
    */
    get Name(): string {
        return this.Get('Name');
    }
    set Name(value: string) {
        this.Set('Name', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: DefaultTermMonths
    * * Display Name: Default Term Months
    * * SQL Data Type: int
    */
    get DefaultTermMonths(): number | null {
        return this.Get('DefaultTermMonths');
    }
    set DefaultTermMonths(value: number | null) {
        this.Set('DefaultTermMonths', value);
    }

    /**
    * * Field Name: DefaultBillingFrequency
    * * Display Name: Default Billing Frequency
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Annual
    *   * Custom
    *   * Milestone
    *   * Monthly
    *   * Quarterly
    *   * SemiAnnual
    */
    get DefaultBillingFrequency(): 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual' | null {
        return this.Get('DefaultBillingFrequency');
    }
    set DefaultBillingFrequency(value: 'Annual' | 'Custom' | 'Milestone' | 'Monthly' | 'Quarterly' | 'SemiAnnual' | null) {
        this.Set('DefaultBillingFrequency', value);
    }

    /**
    * * Field Name: DefaultAutoRenew
    * * Display Name: Default Auto Renew
    * * SQL Data Type: bit
    * * Default Value: 0
    */
    get DefaultAutoRenew(): boolean {
        return this.Get('DefaultAutoRenew');
    }
    set DefaultAutoRenew(value: boolean) {
        this.Set('DefaultAutoRenew', value);
    }

    /**
    * * Field Name: RequiresSignature
    * * Display Name: Requires Signature
    * * SQL Data Type: bit
    * * Default Value: 1
    */
    get RequiresSignature(): boolean {
        return this.Get('RequiresSignature');
    }
    set RequiresSignature(value: boolean) {
        this.Set('RequiresSignature', value);
    }

    /**
    * * Field Name: DefaultEscalationPercent
    * * Display Name: Default Escalation Percent
    * * SQL Data Type: decimal(7, 4)
    */
    get DefaultEscalationPercent(): number | null {
        return this.Get('DefaultEscalationPercent');
    }
    set DefaultEscalationPercent(value: number | null) {
        this.Set('DefaultEscalationPercent', value);
    }

    /**
    * * Field Name: DefaultMaxEscalationPercent
    * * Display Name: Default Max Escalation Percent
    * * SQL Data Type: decimal(7, 4)
    */
    get DefaultMaxEscalationPercent(): number | null {
        return this.Get('DefaultMaxEscalationPercent');
    }
    set DefaultMaxEscalationPercent(value: number | null) {
        this.Set('DefaultMaxEscalationPercent', value);
    }

    /**
    * * Field Name: DefaultRenewalNoticeDays
    * * Display Name: Default Renewal Notice Days
    * * SQL Data Type: int
    */
    get DefaultRenewalNoticeDays(): number | null {
        return this.Get('DefaultRenewalNoticeDays');
    }
    set DefaultRenewalNoticeDays(value: number | null) {
        this.Set('DefaultRenewalNoticeDays', value);
    }

    /**
    * * Field Name: DefaultCancellationWindowDays
    * * Display Name: Default Cancellation Window Days
    * * SQL Data Type: int
    */
    get DefaultCancellationWindowDays(): number | null {
        return this.Get('DefaultCancellationWindowDays');
    }
    set DefaultCancellationWindowDays(value: number | null) {
        this.Set('DefaultCancellationWindowDays', value);
    }

    /**
    * * Field Name: RenewalMode
    * * Display Name: Renewal Mode
    * * SQL Data Type: nvarchar(20)
    * * Default Value: Deal
    * * Value List Type: List
    * * Possible Values 
    *   * Auto
    *   * Deal
    *   * Manual
    * * Description: How a term of this type renews. Deal = a renewal is a deal (L-18); bizapps-sales calls Contracts.RenewTerm when a renewal deal closes, so renewal gets its own pipeline and win-rate. Auto = the Scheduled Job renews with no deal, for evergreen and B2C. Manual = a human triggers it.
    */
    get RenewalMode(): 'Auto' | 'Deal' | 'Manual' {
        return this.Get('RenewalMode');
    }
    set RenewalMode(value: 'Auto' | 'Deal' | 'Manual') {
        this.Set('RenewalMode', value);
    }

    /**
    * * Field Name: AllowsCoterm
    * * Display Name: Allows Coterm
    * * SQL Data Type: bit
    * * Default Value: 1
    * * Description: Whether a term of this type may absorb a mid-term addition aligned to the term end date (co-terming).
    */
    get AllowsCoterm(): boolean {
        return this.Get('AllowsCoterm');
    }
    set AllowsCoterm(value: boolean) {
        this.Set('AllowsCoterm', value);
    }

    /**
    * * Field Name: DriverClass
    * * Display Name: Driver Class
    * * SQL Data Type: nvarchar(255)
    * * Description: OPTIONAL ClassFactory key for a behaviour subclass, following SubscriptionType rather than RevenueRecognitionType: the columns ARE the rules and a base class reads them. Supply a driver only when a customer needs something the columns cannot express.
    */
    get DriverClass(): string | null {
        return this.Get('DriverClass');
    }
    set DriverClass(value: string | null) {
        this.Set('DriverClass', value);
    }

    /**
    * * Field Name: IsActive
    * * Display Name: Is Active
    * * SQL Data Type: bit
    * * Default Value: 1
    */
    get IsActive(): boolean {
        return this.Get('IsActive');
    }
    set IsActive(value: boolean) {
        this.Set('IsActive', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }
}


/**
 * MJ_BizApps_Contracts: Contracts - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: Contract
 * * Base View: vwContracts
 * * @description The agreement. Deliberately carries NO reference to a Deal (L-15): sales sits above contracts so a reference upward inverts the dependency graph, and the cardinality is one contract to MANY deals (the original sale, every renewal, every expansion). The reverse lookup lives in sales as Deal.ContractID and returns a set.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')
export class mjBizAppsContractsContractEntity extends BaseEntity<mjBizAppsContractsContractEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contracts record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contracts record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractEntity
    * @method
    * @override
    */
    public async Load(ID: string, EntityRelationshipsToLoad?: string[]) : Promise<boolean> {
        const compositeKey: CompositeKey = new CompositeKey();
        compositeKey.KeyValuePairs.push({ FieldName: 'ID', Value: ID });
        return await super.InnerLoad(compositeKey, EntityRelationshipsToLoad);
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: uniqueidentifier
    * * Default Value: newsequentialid()
    */
    get ID(): string {
        return this.Get('ID');
    }
    set ID(value: string) {
        this.Set('ID', value);
    }

    /**
    * * Field Name: ContractNumber
    * * Display Name: Contract Number
    * * SQL Data Type: nvarchar(50)
    * * Description: CTR-{seq} from ContractSequence. Unique.
    */
    get ContractNumber(): string {
        return this.Get('ContractNumber');
    }
    set ContractNumber(value: string) {
        this.Set('ContractNumber', value);
    }

    /**
    * * Field Name: ContractTypeID
    * * Display Name: Contract Type ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Types (vwContractTypes.ID)
    */
    get ContractTypeID(): string {
        return this.Get('ContractTypeID');
    }
    set ContractTypeID(value: string) {
        this.Set('ContractTypeID', value);
    }

    /**
    * * Field Name: CompanyID
    * * Display Name: Company ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ: Companies (vwCompanies.ID)
    * * Description: The SELLING company (__mj.Company) — which of our entities holds this agreement. Not the customer.
    */
    get CompanyID(): string {
        return this.Get('CompanyID');
    }
    set CompanyID(value: string) {
        this.Set('CompanyID', value);
    }

    /**
    * * Field Name: CustomerOrganizationID
    * * Display Name: Customer Organization ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
    * * Description: The customer, when the customer is an organization. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.
    */
    get CustomerOrganizationID(): string | null {
        return this.Get('CustomerOrganizationID');
    }
    set CustomerOrganizationID(value: string | null) {
        this.Set('CustomerOrganizationID', value);
    }

    /**
    * * Field Name: CustomerPersonID
    * * Display Name: Customer Person ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    * * Description: The customer, when the customer is an individual. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.
    */
    get CustomerPersonID(): string | null {
        return this.Get('CustomerPersonID');
    }
    set CustomerPersonID(value: string | null) {
        this.Set('CustomerPersonID', value);
    }

    /**
    * * Field Name: PrimaryContactPersonID
    * * Display Name: Primary Contact Person ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    */
    get PrimaryContactPersonID(): string | null {
        return this.Get('PrimaryContactPersonID');
    }
    set PrimaryContactPersonID(value: string | null) {
        this.Set('PrimaryContactPersonID', value);
    }

    /**
    * * Field Name: OwnerUserID
    * * Display Name: Owner User ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ: Users (vwUsers.ID)
    */
    get OwnerUserID(): string | null {
        return this.Get('OwnerUserID');
    }
    set OwnerUserID(value: string | null) {
        this.Set('OwnerUserID', value);
    }

    /**
    * * Field Name: ParentContractID
    * * Display Name: Parent Contract ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    * * Description: Self-FK for MSA -> SOW nesting (D-5). Modelled as a self-reference rather than a distinct Agreement entity until the two genuinely diverge.
    */
    get ParentContractID(): string | null {
        return this.Get('ParentContractID');
    }
    set ParentContractID(value: string | null) {
        this.Set('ParentContractID', value);
    }

    /**
    * * Field Name: SupersededByContractID
    * * Display Name: Superseded By Contract ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    */
    get SupersededByContractID(): string | null {
        return this.Get('SupersededByContractID');
    }
    set SupersededByContractID(value: string | null) {
        this.Set('SupersededByContractID', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(30)
    * * Default Value: Draft
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Draft
    *   * Expired
    *   * PendingSignature
    *   * Superseded
    *   * Terminated
    */
    get Status(): 'Active' | 'Draft' | 'Expired' | 'PendingSignature' | 'Superseded' | 'Terminated' {
        return this.Get('Status');
    }
    set Status(value: 'Active' | 'Draft' | 'Expired' | 'PendingSignature' | 'Superseded' | 'Terminated') {
        this.Set('Status', value);
    }

    /**
    * * Field Name: Description
    * * Display Name: Description
    * * SQL Data Type: nvarchar(MAX)
    */
    get Description(): string | null {
        return this.Get('Description');
    }
    set Description(value: string | null) {
        this.Set('Description', value);
    }

    /**
    * * Field Name: EffectiveDate
    * * Display Name: Effective Date
    * * SQL Data Type: date
    */
    get EffectiveDate(): Date | null {
        return this.Get('EffectiveDate');
    }
    set EffectiveDate(value: Date | null) {
        this.Set('EffectiveDate', value);
    }

    /**
    * * Field Name: ExecutedDate
    * * Display Name: Executed Date
    * * SQL Data Type: date
    */
    get ExecutedDate(): Date | null {
        return this.Get('ExecutedDate');
    }
    set ExecutedDate(value: Date | null) {
        this.Set('ExecutedDate', value);
    }

    /**
    * * Field Name: AutoRenew
    * * Display Name: Auto Renew
    * * SQL Data Type: bit
    * * Default Value: 0
    */
    get AutoRenew(): boolean {
        return this.Get('AutoRenew');
    }
    set AutoRenew(value: boolean) {
        this.Set('AutoRenew', value);
    }

    /**
    * * Field Name: CancellationWindowDays
    * * Display Name: Cancellation Window Days
    * * SQL Data Type: int
    */
    get CancellationWindowDays(): number | null {
        return this.Get('CancellationWindowDays');
    }
    set CancellationWindowDays(value: number | null) {
        this.Set('CancellationWindowDays', value);
    }

    /**
    * * Field Name: TerminationPolicy
    * * Display Name: Termination Policy
    * * SQL Data Type: nvarchar(MAX)
    */
    get TerminationPolicy(): string | null {
        return this.Get('TerminationPolicy');
    }
    set TerminationPolicy(value: string | null) {
        this.Set('TerminationPolicy', value);
    }

    /**
    * * Field Name: ExternalReferenceID
    * * Display Name: External Reference ID
    * * SQL Data Type: nvarchar(255)
    */
    get ExternalReferenceID(): string | null {
        return this.Get('ExternalReferenceID');
    }
    set ExternalReferenceID(value: string | null) {
        this.Set('ExternalReferenceID', value);
    }

    /**
    * * Field Name: __mj_CreatedAt
    * * Display Name: Created At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_CreatedAt(): Date {
        return this.Get('__mj_CreatedAt');
    }

    /**
    * * Field Name: __mj_UpdatedAt
    * * Display Name: Updated At
    * * SQL Data Type: datetimeoffset
    * * Default Value: getutcdate()
    */
    get __mj_UpdatedAt(): Date {
        return this.Get('__mj_UpdatedAt');
    }

    /**
    * * Field Name: ContractType
    * * Display Name: Contract Type
    * * SQL Data Type: nvarchar(100)
    */
    get ContractType(): string {
        return this.Get('ContractType');
    }

    /**
    * * Field Name: Company
    * * Display Name: Company
    * * SQL Data Type: nvarchar(50)
    */
    get Company(): string {
        return this.Get('Company');
    }

    /**
    * * Field Name: CustomerOrganization
    * * Display Name: Customer Organization
    * * SQL Data Type: nvarchar(255)
    */
    get CustomerOrganization(): string | null {
        return this.Get('CustomerOrganization');
    }

    /**
    * * Field Name: CustomerPerson
    * * Display Name: Customer Person
    * * SQL Data Type: nvarchar(201)
    */
    get CustomerPerson(): string | null {
        return this.Get('CustomerPerson');
    }

    /**
    * * Field Name: PrimaryContactPerson
    * * Display Name: Primary Contact Person
    * * SQL Data Type: nvarchar(201)
    */
    get PrimaryContactPerson(): string | null {
        return this.Get('PrimaryContactPerson');
    }

    /**
    * * Field Name: OwnerUser
    * * Display Name: Owner User
    * * SQL Data Type: nvarchar(100)
    */
    get OwnerUser(): string | null {
        return this.Get('OwnerUser');
    }

    /**
    * * Field Name: RootParentContractID
    * * Display Name: Root Parent Contract ID
    * * SQL Data Type: uniqueidentifier
    */
    get RootParentContractID(): string | null {
        return this.Get('RootParentContractID');
    }

    /**
    * * Field Name: RootSupersededByContractID
    * * Display Name: Root Superseded By Contract ID
    * * SQL Data Type: uniqueidentifier
    */
    get RootSupersededByContractID(): string | null {
        return this.Get('RootSupersededByContractID');
    }
}
