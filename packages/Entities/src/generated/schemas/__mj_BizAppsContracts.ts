import { z } from "zod";


/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Orders
 */
export const mjBizAppsContractsContractOrderSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractID: z.string().describe(`
        * * Field Name: ContractID
        * * Display Name: Contract ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
        * * Description: The contract whose terms apply to the order.`),
    OrderID: z.string().describe(`
        * * Field Name: OrderID
        * * Display Name: Order ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Orders: Order Headers (vwOrderHeaders.ID)
        * * Description: The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.`),
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
    Contract: z.string().nullable().describe(`
        * * Field Name: Contract
        * * Display Name: Contract
        * * SQL Data Type: nvarchar(50)`),
    Order: z.string().nullable().describe(`
        * * Field Name: Order
        * * Display Name: Order
        * * SQL Data Type: nvarchar(50)`),
});

export type mjBizAppsContractsContractOrderEntityType = z.infer<typeof mjBizAppsContractsContractOrderSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Template Modifications
 */
export const mjBizAppsContractsContractTemplateModificationSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractID: z.string().describe(`
        * * Field Name: ContractID
        * * Display Name: Contract
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)`),
    ContractTemplateProvisionID: z.string().describe(`
        * * Field Name: ContractTemplateProvisionID
        * * Display Name: Contract Template Provision
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Template Provisions (vwContractTemplateProvisions.ID)
        * * Description: The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.`),
    ModificationText: z.string().describe(`
        * * Field Name: ModificationText
        * * Display Name: Modification Text
        * * SQL Data Type: nvarchar(MAX)
        * * Description: What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.`),
    Notes: z.string().nullable().describe(`
        * * Field Name: Notes
        * * Display Name: Notes
        * * SQL Data Type: nvarchar(MAX)
        * * Description: Optional working note, e.g. who negotiated it.`),
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
    Contract: z.string().nullable().describe(`
        * * Field Name: Contract
        * * Display Name: Contract
        * * SQL Data Type: nvarchar(50)`),
    ContractTemplateProvision: z.string().describe(`
        * * Field Name: ContractTemplateProvision
        * * Display Name: Contract Template Provision
        * * SQL Data Type: nvarchar(20)`),
});

export type mjBizAppsContractsContractTemplateModificationEntityType = z.infer<typeof mjBizAppsContractsContractTemplateModificationSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Template Provisions
 */
export const mjBizAppsContractsContractTemplateProvisionSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    ContractTemplateID: z.string().describe(`
        * * Field Name: ContractTemplateID
        * * Display Name: Contract Template
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Templates (vwContractTemplates.ID)`),
    ProvisionNumber: z.string().describe(`
        * * Field Name: ProvisionNumber
        * * Display Name: Provision Number
        * * SQL Data Type: nvarchar(20)
        * * Description: The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.`),
    Title: z.string().describe(`
        * * Field Name: Title
        * * Display Name: Title
        * * SQL Data Type: nvarchar(200)
        * * Description: The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.`),
    ProvisionText: z.string().describe(`
        * * Field Name: ProvisionText
        * * Display Name: Provision Text
        * * SQL Data Type: nvarchar(MAX)
        * * Description: The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    ProvisionSortKey: z.string().nullable().describe(`
        * * Field Name: ProvisionSortKey
        * * Display Name: Sort Key
        * * SQL Data Type: nvarchar(200)
        * * Description: Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order ('1.9' before '1.10'), which ordering by ProvisionNumber cannot. READ-ONLY -- a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.`),
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
    ContractTemplate: z.string().describe(`
        * * Field Name: ContractTemplate
        * * Display Name: Contract Template Name
        * * SQL Data Type: nvarchar(200)`),
});

export type mjBizAppsContractsContractTemplateProvisionEntityType = z.infer<typeof mjBizAppsContractsContractTemplateProvisionSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Template Types
 */
export const mjBizAppsContractsContractTemplateTypeSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(100)`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    Status: z.union([z.literal('Active'), z.literal('Inactive')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(10)
        * * Default Value: Active
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Inactive
        * * Description: Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.`),
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

export type mjBizAppsContractsContractTemplateTypeEntityType = z.infer<typeof mjBizAppsContractsContractTemplateTypeSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Templates
 */
export const mjBizAppsContractsContractTemplateSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(200)`),
    ContractTemplateTypeID: z.string().describe(`
        * * Field Name: ContractTemplateTypeID
        * * Display Name: Template Type ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Template Types (vwContractTemplateTypes.ID)`),
    VersionLabel: z.string().nullable().describe(`
        * * Field Name: VersionLabel
        * * Display Name: Version Label
        * * SQL Data Type: nvarchar(50)
        * * Description: The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.`),
    IntroducedDate: z.date().nullable().describe(`
        * * Field Name: IntroducedDate
        * * Display Name: Introduced Date
        * * SQL Data Type: date
        * * Description: When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.`),
    SourceURL: z.string().nullable().describe(`
        * * Field Name: SourceURL
        * * Display Name: Source URL
        * * SQL Data Type: nvarchar(1000)
        * * Description: The dated public URL a customer can open to read the standard terms. NULLABLE: reachability is enforceable by nothing (a well-formed dead link passes any format check), and the real rule is "a URL OR an attached file" — the file half attaching through __mj.FileEntityRecordLink, which cannot reference a record that does not exist yet, so on CREATE it is unsatisfiable in principle. A template with neither is INCOMPLETE rather than invalid; the derived IsUsable column on vwContractTemplates is what says so.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    Status: z.union([z.literal('Draft'), z.literal('Published')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(20)
        * * Default Value: Draft
    * * Value List Type: List
    * * Possible Values 
    *   * Draft
    *   * Published
        * * Description: Publication lifecycle. 'Draft' -- freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. 'Published' -- the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version -- that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.`),
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
    ContractTemplateType: z.string().nullable().describe(`
        * * Field Name: ContractTemplateType
        * * Display Name: Template Type
        * * SQL Data Type: nvarchar(100)`),
    IsUsable: z.boolean().nullable().describe(`
        * * Field Name: IsUsable
        * * Display Name: Is Usable
        * * SQL Data Type: bit`),
});

export type mjBizAppsContractsContractTemplateEntityType = z.infer<typeof mjBizAppsContractsContractTemplateSchema>;

/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Types
 */
export const mjBizAppsContractsContractTypeSchema = z.object({
    ID: z.string().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: uniqueidentifier
        * * Default Value: newsequentialid()`),
    Name: z.string().describe(`
        * * Field Name: Name
        * * Display Name: Name
        * * SQL Data Type: nvarchar(100)`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    RequiresExecutedDocument: z.boolean().describe(`
        * * Field Name: RequiresExecutedDocument
        * * Display Name: Requires Executed Document
        * * SQL Data Type: bit
        * * Default Value: 1
        * * Description: Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.`),
    Status: z.union([z.literal('Active'), z.literal('Inactive')]).describe(`
        * * Field Name: Status
        * * Display Name: Status
        * * SQL Data Type: nvarchar(10)
        * * Default Value: Active
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Inactive
        * * Description: Active | Inactive.`),
    MustBeRoot: z.boolean().describe(`
        * * Field Name: MustBeRoot
        * * Display Name: Must Be Root
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: This type of contract may NOT name a ParentContractID -- it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.`),
    MustBeChild: z.boolean().describe(`
        * * Field Name: MustBeChild
        * * Display Name: Must Be Child
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: This type of contract MUST name a ParentContractID -- a Change Order that amends nothing is not a change order, and would never appear in the original agreement's lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.`),
    TemplateRequired: z.boolean().describe(`
        * * Field Name: TemplateRequired
        * * Display Name: Template Required
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: This type of contract must carry its own ContractTemplateID -- the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because 'where in the tree' and 'does it need its own paper' are different questions and a future type could want any combination.`),
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
    DefaultAutoRenew: z.boolean().nullable().describe(`
        * * Field Name: DefaultAutoRenew
        * * Display Name: Default Auto Renew
        * * SQL Data Type: bit
        * * Description: Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract's own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.`),
    DefaultRenewalNoticeDays: z.number().nullable().describe(`
        * * Field Name: DefaultRenewalNoticeDays
        * * Display Name: Default Renewal Notice Days
        * * SQL Data Type: int
        * * Description: Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.`),
    DefaultCancellationWindowDays: z.number().nullable().describe(`
        * * Field Name: DefaultCancellationWindowDays
        * * Display Name: Default Cancellation Window Days
        * * SQL Data Type: int
        * * Description: Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.`),
    DefaultAnnualIncreasePercent: z.number().nullable().describe(`
        * * Field Name: DefaultAnnualIncreasePercent
        * * Display Name: Default Annual Increase Percent
        * * SQL Data Type: decimal(7, 4)
        * * Description: Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.`),
    Code: z.string().describe(`
        * * Field Name: Code
        * * Display Name: Code
        * * SQL Data Type: nvarchar(50)
        * * Description: Stable machine code other apps and metadata use to find this type (for example ORDER_FORM). Unique. Unlike Name, it is not a label: renaming the type leaves the Code alone, and changing the Code breaks every caller that names it.`),
    ContractTemplateTypeID: z.string().nullable().describe(`
        * * Field Name: ContractTemplateTypeID
        * * Display Name: Default Template Type
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Template Types (vwContractTemplateTypes.ID)
        * * Description: Which kind of standard agreement (ContractTemplateType) a contract of this type incorporates by default when TemplateRequired = 1. Nullable because types with TemplateRequired = 0 carry no template, and a type that leaves this NULL falls back to the newest Published, usable template across all template types.`),
    ContractTemplateType: z.string().nullable().describe(`
        * * Field Name: ContractTemplateType
        * * Display Name: Default Template Type Name
        * * SQL Data Type: nvarchar(100)`),
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
    ContractNumber: z.string().nullable().describe(`
        * * Field Name: ContractNumber
        * * Display Name: Contract Number
        * * SQL Data Type: nvarchar(50)
        * * Description: CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express 'NOT NULL, assigned by the server on insert' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be 'fixed': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.`),
    ContractTypeID: z.string().describe(`
        * * Field Name: ContractTypeID
        * * Display Name: Contract Type
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Types (vwContractTypes.ID)`),
    CompanyID: z.string().describe(`
        * * Field Name: CompanyID
        * * Display Name: Company
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Companies (vwCompanies.ID)
        * * Description: The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.`),
    CustomerOrganizationID: z.string().describe(`
        * * Field Name: CustomerOrganizationID
        * * Display Name: Customer Organization
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
        * * Description: The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.`),
    PrimaryContactPersonID: z.string().nullable().describe(`
        * * Field Name: PrimaryContactPersonID
        * * Display Name: Primary Contact Person
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
        * * Description: Their named contact, optional.`),
    ContractTemplateID: z.string().nullable().describe(`
        * * Field Name: ContractTemplateID
        * * Display Name: Contract Template
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Templates (vwContractTemplates.ID)
        * * Description: The agreement version this contract incorporates. Nullable because contract types with TemplateRequired = 0 (such as Change Order and Statement of Work) carry no standard agreement version of their own, and because a newly created contract leaves this empty when no Published, usable template exists yet.`),
    CreatingEntityID: z.string().nullable().describe(`
        * * Field Name: CreatingEntityID
        * * Display Name: Creating Entity
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Entities (vwEntities.ID)
        * * Description: Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.`),
    CreatingRecordID: z.string().nullable().describe(`
        * * Field Name: CreatingRecordID
        * * Display Name: Creating Record ID
        * * SQL Data Type: nvarchar(450)
        * * Description: Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.`),
    ParentContractID: z.string().nullable().describe(`
        * * Field Name: ParentContractID
        * * Display Name: Parent Contract
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
        * * Description: The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.`),
    SupersededByContractID: z.string().nullable().describe(`
        * * Field Name: SupersededByContractID
        * * Display Name: Superseded By
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
        * * Description: The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.`),
    SigningProviderURL: z.string().nullable().describe(`
        * * Field Name: SigningProviderURL
        * * Display Name: Signing Provider URL
        * * SQL Data Type: nvarchar(1000)
        * * Description: Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.`),
    EffectiveDate: z.date().nullable().describe(`
        * * Field Name: EffectiveDate
        * * Display Name: Effective Date
        * * SQL Data Type: date
        * * Description: When the agreement takes effect.`),
    ExecutedDate: z.date().nullable().describe(`
        * * Field Name: ExecutedDate
        * * Display Name: Executed Date
        * * SQL Data Type: date
        * * Description: When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.`),
    EndDate: z.date().nullable().describe(`
        * * Field Name: EndDate
        * * Display Name: End Date
        * * SQL Data Type: date
        * * Description: When the current term ends. This is what drives the renewal watchlist and every expiry projection.`),
    TerminatedDate: z.date().nullable().describe(`
        * * Field Name: TerminatedDate
        * * Display Name: Terminated Date
        * * SQL Data Type: date
        * * Description: When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.`),
    AutoRenew: z.boolean().describe(`
        * * Field Name: AutoRenew
        * * Display Name: Auto Renew
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.`),
    RenewalNoticeDays: z.number().nullable().describe(`
        * * Field Name: RenewalNoticeDays
        * * Display Name: Renewal Notice (Days)
        * * SQL Data Type: int
        * * Description: Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.`),
    CancellationWindowDays: z.number().nullable().describe(`
        * * Field Name: CancellationWindowDays
        * * Display Name: Cancellation Window Days
        * * SQL Data Type: int
        * * Description: Days of notice the customer owes to cancel without renewing.`),
    AnnualIncreasePercent: z.number().nullable().describe(`
        * * Field Name: AnnualIncreasePercent
        * * Display Name: Annual Increase Percent
        * * SQL Data Type: decimal(7, 4)
        * * Description: The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.`),
    HasModifications: z.boolean().describe(`
        * * Field Name: HasModifications
        * * Display Name: Has Modifications
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    Notes: z.string().nullable().describe(`
        * * Field Name: Notes
        * * Display Name: Notes
        * * SQL Data Type: nvarchar(MAX)
        * * Description: Free-text working notes for whoever is processing the contract.`),
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
    PredictedNonRenewalRisk: z.number().nullable().describe(`
        * * Field Name: PredictedNonRenewalRisk
        * * Display Name: Predicted Non Renewal Risk
        * * SQL Data Type: decimal(5, 4)
        * * Description: Predicted probability (0.0000 to 1.0000) that this commercial agreement will fail to renew prior to the required notice deadline.`),
    PredictedRenewalRiskBand: z.union([z.literal('Critical'), z.literal('High'), z.literal('Low'), z.literal('Medium')]).nullable().describe(`
        * * Field Name: PredictedRenewalRiskBand
        * * Display Name: Predicted Renewal Risk Band
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Critical
    *   * High
    *   * Low
    *   * Medium
        * * Description: Derived operational risk band classifying renewal risk: Low (<20%), Medium (20-50%), High (50-80%), Critical (>=80%).`),
    PredictedRenewalScoredAt: z.date().nullable().describe(`
        * * Field Name: PredictedRenewalScoredAt
        * * Display Name: Predicted Renewal Scored At
        * * SQL Data Type: datetimeoffset
        * * Description: Timestamp of the most recent predictive model scoring execution for this contract.`),
    NonRenewalOutcome: z.union([z.literal(0), z.literal(1)]).nullable().describe(`
        * * Field Name: NonRenewalOutcome
        * * Display Name: Non Renewal Outcome
        * * SQL Data Type: int
    * * Value List Type: List
    * * Possible Values 
    *   * 0
    *   * 1
        * * Description: The renewal-risk model's training label, recorded by the database: 0 when the contract was superseded (renewed), 1 when it was terminated or its term ended without renewal, NULL while the outcome is open. Written by trgContract_RecordNonRenewalOutcome on every save and by spRecordContractNonRenewalOutcomes when an end date passes; a value sent on save is replaced.`),
    CarryDiscountOnRenewal: z.boolean().describe(`
        * * Field Name: CarryDiscountOnRenewal
        * * Display Name: Carry Discount On Renewal
        * * SQL Data Type: bit
        * * Default Value: 0
        * * Description: Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.`),
    DocumentArtifactID: z.string().nullable().describe(`
        * * Field Name: DocumentArtifactID
        * * Display Name: Document Artifact ID
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ: Artifacts (vwArtifacts.ID)
        * * Description: Optional link to an MJ Doc ([__mj].[Artifact]) holding a versioned long-form document such as an Assembled Contract Draft, AI Contract Review Memo, or Executive Summary. Distinct from signed final PDFs attached via MJ: Files (Executed Agreement category) and from relational ContractTemplateProvision / ContractTemplateModification clause rows.`),
    ContractType: z.string().nullable().describe(`
        * * Field Name: ContractType
        * * Display Name: Contract Type Name
        * * SQL Data Type: nvarchar(100)`),
    Company: z.string().nullable().describe(`
        * * Field Name: Company
        * * Display Name: Company Name
        * * SQL Data Type: nvarchar(50)`),
    CustomerOrganization: z.string().nullable().describe(`
        * * Field Name: CustomerOrganization
        * * Display Name: Customer Organization Name
        * * SQL Data Type: nvarchar(255)`),
    PrimaryContactPerson: z.string().nullable().describe(`
        * * Field Name: PrimaryContactPerson
        * * Display Name: Primary Contact Name
        * * SQL Data Type: nvarchar(250)`),
    ContractTemplate: z.string().nullable().describe(`
        * * Field Name: ContractTemplate
        * * Display Name: Contract Template Name
        * * SQL Data Type: nvarchar(200)`),
    CreatingEntity: z.string().nullable().describe(`
        * * Field Name: CreatingEntity
        * * Display Name: Creating Entity Name
        * * SQL Data Type: nvarchar(255)`),
    ParentContract: z.string().nullable().describe(`
        * * Field Name: ParentContract
        * * Display Name: Parent Contract
        * * SQL Data Type: nvarchar(50)`),
    SupersededByContract: z.string().nullable().describe(`
        * * Field Name: SupersededByContract
        * * Display Name: Superseded By Contract
        * * SQL Data Type: nvarchar(50)`),
    DocumentArtifact: z.string().nullable().describe(`
        * * Field Name: DocumentArtifact
        * * Display Name: Document Artifact
        * * SQL Data Type: nvarchar(255)`),
    State: z.string().describe(`
        * * Field Name: State
        * * Display Name: State
        * * SQL Data Type: varchar(10)`),
    IsAwaitingDocument: z.boolean().nullable().describe(`
        * * Field Name: IsAwaitingDocument
        * * Display Name: Is Awaiting Document
        * * SQL Data Type: bit`),
    DaysToEnd: z.number().nullable().describe(`
        * * Field Name: DaysToEnd
        * * Display Name: Days To End
        * * SQL Data Type: int`),
    RenewalNoticeDeadline: z.date().nullable().describe(`
        * * Field Name: RenewalNoticeDeadline
        * * Display Name: Renewal Notice Deadline
        * * SQL Data Type: date`),
    IsInCancellationWindow: z.boolean().nullable().describe(`
        * * Field Name: IsInCancellationWindow
        * * Display Name: Is In Cancellation Window
        * * SQL Data Type: bit`),
    TermLengthDays: z.number().nullable().describe(`
        * * Field Name: TermLengthDays
        * * Display Name: Term Length Days
        * * SQL Data Type: int`),
    DaysUntilNoticeDeadline: z.number().nullable().describe(`
        * * Field Name: DaysUntilNoticeDeadline
        * * Display Name: Days Until Notice Deadline
        * * SQL Data Type: int`),
    HasModificationsFlag: z.number().describe(`
        * * Field Name: HasModificationsFlag
        * * Display Name: Has Modifications Flag
        * * SQL Data Type: int`),
    AutoRenewFlag: z.number().describe(`
        * * Field Name: AutoRenewFlag
        * * Display Name: Auto Renew Flag
        * * SQL Data Type: int`),
    HasParentContract: z.number().describe(`
        * * Field Name: HasParentContract
        * * Display Name: Has Parent Contract
        * * SQL Data Type: int`),
    HasCancellationWindow: z.number().describe(`
        * * Field Name: HasCancellationWindow
        * * Display Name: Has Cancellation Window
        * * SQL Data Type: int`),
    HasAnnualIncrease: z.number().describe(`
        * * Field Name: HasAnnualIncrease
        * * Display Name: Has Annual Increase
        * * SQL Data Type: int`),
});

export type mjBizAppsContractsContractEntityType = z.infer<typeof mjBizAppsContractsContractSchema>;
