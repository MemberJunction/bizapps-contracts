import { BaseEntity, EntitySaveOptions, EntityDeleteOptions, CompositeKey, ValidationResult, ValidationErrorInfo, ValidationErrorType, Metadata, ProviderType, DatabaseProviderBase } from "@memberjunction/core";
import { RegisterClass } from "@memberjunction/global";
import { z } from "zod";

export const loadModule = () => {
  // no-op, only used to ensure this file is a valid module and to allow easy loading
}

     
 
/**
 * zod schema definition for the entity MJ_BizApps_Contracts: Contract Sequences
 */
export const mjBizAppsContractsContractSequenceSchema = z.object({
    ID: z.number().describe(`
        * * Field Name: ID
        * * Display Name: ID
        * * SQL Data Type: int`),
    NextSequenceNumber: z.number().describe(`
        * * Field Name: NextSequenceNumber
        * * Display Name: Next Sequence Number
        * * SQL Data Type: int
        * * Default Value: 1
        * * Description: The next number to hand out. Advanced server-side by ContractEntityServer.Save().`),
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
    ModificationText: z.string().nullable().describe(`
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
    Contract: z.string().describe(`
        * * Field Name: Contract
        * * Display Name: Contract Reference
        * * SQL Data Type: nvarchar(50)`),
    ContractTemplateProvision: z.string().describe(`
        * * Field Name: ContractTemplateProvision
        * * Display Name: Provision Reference
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
    ProvisionText: z.string().nullable().describe(`
        * * Field Name: ProvisionText
        * * Display Name: Provision Text
        * * SQL Data Type: nvarchar(MAX)
        * * Description: The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
        * * SQL Data Type: nvarchar(MAX)`),
    Sequence: z.number().describe(`
        * * Field Name: Sequence
        * * Display Name: Sequence
        * * SQL Data Type: int
        * * Default Value: 0
        * * Description: Display order. Earns its place because ProvisionNumber does not sort as text ("3.10" lands before "3.5") and a legal document has a canonical order.`),
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
    SourceURL: z.string().describe(`
        * * Field Name: SourceURL
        * * Display Name: Source URL
        * * SQL Data Type: nvarchar(1000)
        * * Description: The dated public URL. NOT NULL — every template we have is a published URL and it is what the executed PDF cites; a template nobody can open is not a record of anything.`),
    Description: z.string().nullable().describe(`
        * * Field Name: Description
        * * Display Name: Description
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
    ContractTemplateType: z.string().describe(`
        * * Field Name: ContractTemplateType
        * * Display Name: Template Type
        * * SQL Data Type: nvarchar(100)`),
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
    ParentStatusRequirement: z.union([z.literal('Prohibited'), z.literal('Required')]).nullable().describe(`
        * * Field Name: ParentStatusRequirement
        * * Display Name: Parent Status Requirement
        * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Prohibited
    *   * Required
        * * Description: Whether a contract of this type must, must not, or may name a ParentContractID: 'Required' (a Change Order amends something, so it has to say what), 'Prohibited' (a root agreement), or NULL for no restriction. Enforced in ContractEntityServer.ValidateAsync. Replaced a comparison against this row's NAME, which stopped working the moment anyone renamed it.`),
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
        * * Display Name: Contract Type
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Types (vwContractTypes.ID)`),
    CompanyID: z.string().describe(`
        * * Field Name: CompanyID
        * * Display Name: Selling Company
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
        * * Display Name: Primary Contact
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
        * * Description: Their named contact, optional.`),
    ContractTemplateID: z.string().nullable().describe(`
        * * Field Name: ContractTemplateID
        * * Display Name: Contract Template
        * * SQL Data Type: uniqueidentifier
        * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Templates (vwContractTemplates.ID)
        * * Description: The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.`),
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
        * * Display Name: Renewal Notice Days
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
    ContractType: z.string().describe(`
        * * Field Name: ContractType
        * * Display Name: Contract Type Name
        * * SQL Data Type: nvarchar(100)`),
    Company: z.string().describe(`
        * * Field Name: Company
        * * Display Name: Company Name
        * * SQL Data Type: nvarchar(50)`),
    CustomerOrganization: z.string().describe(`
        * * Field Name: CustomerOrganization
        * * Display Name: Customer Organization Name
        * * SQL Data Type: nvarchar(255)`),
    PrimaryContactPerson: z.string().nullable().describe(`
        * * Field Name: PrimaryContactPerson
        * * Display Name: Primary Contact Name
        * * SQL Data Type: nvarchar(100)`),
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
        * * Display Name: Parent Contract Name
        * * SQL Data Type: nvarchar(50)`),
    SupersededByContract: z.string().nullable().describe(`
        * * Field Name: SupersededByContract
        * * Display Name: Superseded By Name
        * * SQL Data Type: nvarchar(50)`),
    RootParentContractID: z.string().nullable().describe(`
        * * Field Name: RootParentContractID
        * * Display Name: Root Parent Contract
        * * SQL Data Type: uniqueidentifier`),
    RootSupersededByContractID: z.string().nullable().describe(`
        * * Field Name: RootSupersededByContractID
        * * Display Name: Root Superseded By
        * * SQL Data Type: uniqueidentifier`),
    State: z.string().describe(`
        * * Field Name: State
        * * Display Name: Contract State
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
});

export type mjBizAppsContractsContractEntityType = z.infer<typeof mjBizAppsContractsContractSchema>;
 
 

/**
 * MJ_BizApps_Contracts: Contract Sequences - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractSequence
 * * Base View: vwContractSequences
 * * @description Singleton counter behind ContractNumber (CTR-{seq}), the same shape orders uses for ORD- and PAY-. Seeded in the baseline because it is a counter rather than vocabulary: it must exist before the first contract is written.
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
    * Validate() method override for MJ_BizApps_Contracts: Contract Sequences entity. This is an auto-generated method that invokes the generated validators for this entity for the following fields:
    * * ID: The ID of this record must be exactly 1, which restricts the table to a single configuration or system row.
    * * NextSequenceNumber: The next sequence number must be greater than zero to ensure valid sequencing.
    * @public
    * @method
    * @override
    */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.ValidateIdIsOne(result);
        this.ValidateNextSequenceNumberGreaterThanZero(result);
        result.Success = result.Success && (result.Errors.length === 0);

        return result;
    }

    /**
    * The ID of this record must be exactly 1, which restricts the table to a single configuration or system row.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateIdIsOne(result: ValidationResult) {
    	if (this.ID !== 1) {
    		result.Errors.push(new ValidationErrorInfo(
    			"ID",
    			"The ID must be equal to 1.",
    			this.ID,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * The next sequence number must be greater than zero to ensure valid sequencing.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateNextSequenceNumberGreaterThanZero(result: ValidationResult) {
    	if (this.NextSequenceNumber != null && this.NextSequenceNumber <= 0) {
    		result.Errors.push(new ValidationErrorInfo(
    			"NextSequenceNumber",
    			"The next sequence number must be greater than zero.",
    			this.NextSequenceNumber,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * * Field Name: ID
    * * Display Name: ID
    * * SQL Data Type: int
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
    * * Description: The next number to hand out. Advanced server-side by ContractEntityServer.Save().
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
 * MJ_BizApps_Contracts: Contract Template Modifications - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractTemplateModification
 * * Base View: vwContractTemplateModifications
 * * @description What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Modifications')
export class mjBizAppsContractsContractTemplateModificationEntity extends BaseEntity<mjBizAppsContractsContractTemplateModificationEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Template Modifications record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Template Modifications record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTemplateModificationEntity
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
    * * Display Name: Contract
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
    * * Field Name: ContractTemplateProvisionID
    * * Display Name: Contract Template Provision
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Template Provisions (vwContractTemplateProvisions.ID)
    * * Description: The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.
    */
    get ContractTemplateProvisionID(): string {
        return this.Get('ContractTemplateProvisionID');
    }
    set ContractTemplateProvisionID(value: string) {
        this.Set('ContractTemplateProvisionID', value);
    }

    /**
    * * Field Name: ModificationText
    * * Display Name: Modification Text
    * * SQL Data Type: nvarchar(MAX)
    * * Description: What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.
    */
    get ModificationText(): string | null {
        return this.Get('ModificationText');
    }
    set ModificationText(value: string | null) {
        this.Set('ModificationText', value);
    }

    /**
    * * Field Name: Notes
    * * Display Name: Notes
    * * SQL Data Type: nvarchar(MAX)
    * * Description: Optional working note, e.g. who negotiated it.
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
    * * Field Name: Contract
    * * Display Name: Contract Reference
    * * SQL Data Type: nvarchar(50)
    */
    get Contract(): string {
        return this.Get('Contract');
    }

    /**
    * * Field Name: ContractTemplateProvision
    * * Display Name: Provision Reference
    * * SQL Data Type: nvarchar(20)
    */
    get ContractTemplateProvision(): string {
        return this.Get('ContractTemplateProvision');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Template Provisions - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractTemplateProvision
 * * Base View: vwContractTemplateProvisions
 * * @description The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Provisions')
export class mjBizAppsContractsContractTemplateProvisionEntity extends BaseEntity<mjBizAppsContractsContractTemplateProvisionEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Template Provisions record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Template Provisions record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTemplateProvisionEntity
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
    * * Field Name: ContractTemplateID
    * * Display Name: Contract Template
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Templates (vwContractTemplates.ID)
    */
    get ContractTemplateID(): string {
        return this.Get('ContractTemplateID');
    }
    set ContractTemplateID(value: string) {
        this.Set('ContractTemplateID', value);
    }

    /**
    * * Field Name: ProvisionNumber
    * * Display Name: Provision Number
    * * SQL Data Type: nvarchar(20)
    * * Description: The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.
    */
    get ProvisionNumber(): string {
        return this.Get('ProvisionNumber');
    }
    set ProvisionNumber(value: string) {
        this.Set('ProvisionNumber', value);
    }

    /**
    * * Field Name: Title
    * * Display Name: Title
    * * SQL Data Type: nvarchar(200)
    * * Description: The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.
    */
    get Title(): string {
        return this.Get('Title');
    }
    set Title(value: string) {
        this.Set('Title', value);
    }

    /**
    * * Field Name: ProvisionText
    * * Display Name: Provision Text
    * * SQL Data Type: nvarchar(MAX)
    * * Description: The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.
    */
    get ProvisionText(): string | null {
        return this.Get('ProvisionText');
    }
    set ProvisionText(value: string | null) {
        this.Set('ProvisionText', value);
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
    * * Field Name: Sequence
    * * Display Name: Sequence
    * * SQL Data Type: int
    * * Default Value: 0
    * * Description: Display order. Earns its place because ProvisionNumber does not sort as text ("3.10" lands before "3.5") and a legal document has a canonical order.
    */
    get Sequence(): number {
        return this.Get('Sequence');
    }
    set Sequence(value: number) {
        this.Set('Sequence', value);
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
    * * Field Name: ContractTemplate
    * * Display Name: Contract Template Name
    * * SQL Data Type: nvarchar(200)
    */
    get ContractTemplate(): string {
        return this.Get('ContractTemplate');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Template Types - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractTemplateType
 * * Base View: vwContractTemplateTypes
 * * @description The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Template Types')
export class mjBizAppsContractsContractTemplateTypeEntity extends BaseEntity<mjBizAppsContractsContractTemplateTypeEntityType> {
    /**
    * Loads the MJ_BizApps_Contracts: Contract Template Types record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Template Types record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTemplateTypeEntity
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
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(10)
    * * Default Value: Active
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Inactive
    * * Description: Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.
    */
    get Status(): 'Active' | 'Inactive' {
        return this.Get('Status');
    }
    set Status(value: 'Active' | 'Inactive') {
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
 * MJ_BizApps_Contracts: Contract Templates - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractTemplate
 * * Base View: vwContractTemplates
 * * @description One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contract Templates')
export class mjBizAppsContractsContractTemplateEntity extends BaseEntity<mjBizAppsContractsContractTemplateEntityType> {

  /**
  * Related records: MJ_BizApps_Contracts: Contract Template Provisions
  *
  * Loads, validates and persists as one unit with this MJ_BizApps_Contracts: Contract Templates record — see
  * guides/TRANSACTIONS_AND_BATCHING_GUIDE.md. Declared by the RelatedRecordCollection metadata on
  * the 'MJ_BizApps_Contracts: Contract Templates → MJ_BizApps_Contracts: Contract Template Provisions' relationship; edit that row, not this file.
  *
  */
  public readonly Provisions = this.DeclareRelatedRecords<mjBizAppsContractsContractTemplateProvisionEntity>({
      Name: 'Provisions',
        RelatedEntity: 'MJ_BizApps_Contracts: Contract Template Provisions',
        RelatedEntityJoinField: 'ContractTemplateID',
        OrderBy: 'Sequence ASC',
        Load: 'explicit',
        OnRemove: 'delete',
        Source: 'database',
        Sequence: { Field: 'Sequence', From: 1 },
  });

    /**
    * Loads the MJ_BizApps_Contracts: Contract Templates record from the database
    * @param ID: string - primary key value to load the MJ_BizApps_Contracts: Contract Templates record.
    * @param EntityRelationshipsToLoad - (optional) the relationships to load
    * @returns {Promise<boolean>} - true if successful, false otherwise
    * @public
    * @async
    * @memberof mjBizAppsContractsContractTemplateEntity
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
    * * Field Name: Name
    * * Display Name: Name
    * * SQL Data Type: nvarchar(200)
    */
    get Name(): string {
        return this.Get('Name');
    }
    set Name(value: string) {
        this.Set('Name', value);
    }

    /**
    * * Field Name: ContractTemplateTypeID
    * * Display Name: Template Type ID
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Template Types (vwContractTemplateTypes.ID)
    */
    get ContractTemplateTypeID(): string {
        return this.Get('ContractTemplateTypeID');
    }
    set ContractTemplateTypeID(value: string) {
        this.Set('ContractTemplateTypeID', value);
    }

    /**
    * * Field Name: VersionLabel
    * * Display Name: Version Label
    * * SQL Data Type: nvarchar(50)
    * * Description: The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.
    */
    get VersionLabel(): string | null {
        return this.Get('VersionLabel');
    }
    set VersionLabel(value: string | null) {
        this.Set('VersionLabel', value);
    }

    /**
    * * Field Name: IntroducedDate
    * * Display Name: Introduced Date
    * * SQL Data Type: date
    * * Description: When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.
    */
    get IntroducedDate(): Date | null {
        return this.Get('IntroducedDate');
    }
    set IntroducedDate(value: Date | null) {
        this.Set('IntroducedDate', value);
    }

    /**
    * * Field Name: SourceURL
    * * Display Name: Source URL
    * * SQL Data Type: nvarchar(1000)
    * * Description: The dated public URL. NOT NULL — every template we have is a published URL and it is what the executed PDF cites; a template nobody can open is not a record of anything.
    */
    get SourceURL(): string {
        return this.Get('SourceURL');
    }
    set SourceURL(value: string) {
        this.Set('SourceURL', value);
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
    * * Field Name: ContractTemplateType
    * * Display Name: Template Type
    * * SQL Data Type: nvarchar(100)
    */
    get ContractTemplateType(): string {
        return this.Get('ContractTemplateType');
    }
}


/**
 * MJ_BizApps_Contracts: Contract Types - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: ContractType
 * * Base View: vwContractTypes
 * * @description The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.
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
    * * Field Name: RequiresExecutedDocument
    * * Display Name: Requires Executed Document
    * * SQL Data Type: bit
    * * Default Value: 1
    * * Description: Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.
    */
    get RequiresExecutedDocument(): boolean {
        return this.Get('RequiresExecutedDocument');
    }
    set RequiresExecutedDocument(value: boolean) {
        this.Set('RequiresExecutedDocument', value);
    }

    /**
    * * Field Name: Status
    * * Display Name: Status
    * * SQL Data Type: nvarchar(10)
    * * Default Value: Active
    * * Value List Type: List
    * * Possible Values 
    *   * Active
    *   * Inactive
    * * Description: Active | Inactive.
    */
    get Status(): 'Active' | 'Inactive' {
        return this.Get('Status');
    }
    set Status(value: 'Active' | 'Inactive') {
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

    /**
    * * Field Name: ParentStatusRequirement
    * * Display Name: Parent Status Requirement
    * * SQL Data Type: nvarchar(20)
    * * Value List Type: List
    * * Possible Values 
    *   * Prohibited
    *   * Required
    * * Description: Whether a contract of this type must, must not, or may name a ParentContractID: 'Required' (a Change Order amends something, so it has to say what), 'Prohibited' (a root agreement), or NULL for no restriction. Enforced in ContractEntityServer.ValidateAsync. Replaced a comparison against this row's NAME, which stopped working the moment anyone renamed it.
    */
    get ParentStatusRequirement(): 'Prohibited' | 'Required' | null {
        return this.Get('ParentStatusRequirement');
    }
    set ParentStatusRequirement(value: 'Prohibited' | 'Required' | null) {
        this.Set('ParentStatusRequirement', value);
    }
}


/**
 * MJ_BizApps_Contracts: Contracts - strongly typed entity sub-class
 * * Schema: __mj_BizAppsContracts
 * * Base Table: Contract
 * * Base View: vwContracts
 * * @description The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.
 * * Primary Key: ID
 * @extends {BaseEntity}
 * @class
 * @public
 */
@RegisterClass(BaseEntity, 'MJ_BizApps_Contracts: Contracts')
export class mjBizAppsContractsContractEntity extends BaseEntity<mjBizAppsContractsContractEntityType> {

  /**
  * Related records: MJ_BizApps_Contracts: Contract Template Modifications
  *
  * Loads, validates and persists as one unit with this MJ_BizApps_Contracts: Contracts record — see
  * guides/TRANSACTIONS_AND_BATCHING_GUIDE.md. Declared by the RelatedRecordCollection metadata on
  * the 'MJ_BizApps_Contracts: Contracts → MJ_BizApps_Contracts: Contract Template Modifications' relationship; edit that row, not this file.
  *
  */
  public readonly Modifications = this.DeclareRelatedRecords<mjBizAppsContractsContractTemplateModificationEntity>({
      Name: 'Modifications',
        RelatedEntity: 'MJ_BizApps_Contracts: Contract Template Modifications',
        RelatedEntityJoinField: 'ContractID',
        OrderBy: '__mj_CreatedAt ASC',
        Load: 'explicit',
        OnRemove: 'delete',
        Source: 'database',
  });

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
    * Validate() method override for MJ_BizApps_Contracts: Contracts entity. This is an auto-generated method that invokes the generated validators for this entity for the following fields:
    * * AnnualIncreasePercent: The annual increase percentage must be greater than or equal to 0% if it is specified.
    * * CancellationWindowDays: The cancellation window, if specified, must be 0 days or greater.
    * * RenewalNoticeDays: The renewal notice days must be a non-negative number (0 or greater) if it is specified.
    * * Table-Level: Both the creating entity and the creating record must be provided together, or both must be left empty. You cannot specify one without the other.
    * * Table-Level: The contract end date must be on or after the effective date.
    * * Table-Level: A contract cannot be its own parent contract. This prevents circular references in the contract hierarchy.
    * * Table-Level: A contract cannot be superseded by itself. If a superseding contract is specified, it must be a different contract.
    * @public
    * @method
    * @override
    */
    public override Validate(): ValidationResult {
        const result = super.Validate();
        this.ValidateAnnualIncreasePercentGreaterThanOrEqualToZero(result);
        this.ValidateCancellationWindowDaysMinimum(result);
        this.ValidateRenewalNoticeDaysGreaterThanOrEqualToZero(result);
        this.ValidateCreatingEntityAndRecordCoexistence(result);
        this.ValidateEndDateAfterOrEqualToEffectiveDate(result);
        this.ValidateParentContractIDNotEqualToID(result);
        this.ValidateSupersededByContractIDNotSelf(result);
        result.Success = result.Success && (result.Errors.length === 0);

        return result;
    }

    /**
    * The annual increase percentage must be greater than or equal to 0% if it is specified.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateAnnualIncreasePercentGreaterThanOrEqualToZero(result: ValidationResult) {
    	if (this.AnnualIncreasePercent != null && this.AnnualIncreasePercent < 0) {
    		result.Errors.push(new ValidationErrorInfo(
    			"AnnualIncreasePercent",
    			"Annual increase percentage must be greater than or equal to 0.",
    			this.AnnualIncreasePercent,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * The cancellation window, if specified, must be 0 days or greater.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateCancellationWindowDaysMinimum(result: ValidationResult) {
    	if (this.CancellationWindowDays != null && this.CancellationWindowDays < 0) {
    		result.Errors.push(new ValidationErrorInfo(
    			"CancellationWindowDays",
    			"Cancellation window days must be 0 or greater.",
    			this.CancellationWindowDays,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * The renewal notice days must be a non-negative number (0 or greater) if it is specified.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateRenewalNoticeDaysGreaterThanOrEqualToZero(result: ValidationResult) {
    	if (this.RenewalNoticeDays != null && this.RenewalNoticeDays < 0) {
    		result.Errors.push(new ValidationErrorInfo(
    			"RenewalNoticeDays",
    			"Renewal notice days must be greater than or equal to 0.",
    			this.RenewalNoticeDays,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * Both the creating entity and the creating record must be provided together, or both must be left empty. You cannot specify one without the other.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateCreatingEntityAndRecordCoexistence(result: ValidationResult) {
    	const hasEntity = this.CreatingEntityID != null && this.CreatingEntityID !== "";
    	const hasRecord = this.CreatingRecordID != null && this.CreatingRecordID !== "";
    
    	if (hasEntity !== hasRecord) {
    		result.Errors.push(new ValidationErrorInfo(
    			"CreatingEntityID",
    			"Both Creating Entity and Creating Record must be provided together, or both must be left empty.",
    			this.CreatingEntityID,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * The contract end date must be on or after the effective date.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateEndDateAfterOrEqualToEffectiveDate(result: ValidationResult) {
    	if (this.EndDate != null && this.EffectiveDate != null) {
    		if (this.EndDate < this.EffectiveDate) {
    			result.Errors.push(new ValidationErrorInfo(
    				"EndDate",
    				"The contract end date must be on or after the effective date.",
    				this.EndDate,
    				ValidationErrorType.Failure
    			));
    		}
    	}
    }

    /**
    * A contract cannot be its own parent contract. This prevents circular references in the contract hierarchy.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateParentContractIDNotEqualToID(result: ValidationResult) {
    	if (this.ParentContractID != null && this.ParentContractID === this.ID) {
    		result.Errors.push(new ValidationErrorInfo(
    			"ParentContractID",
    			"A contract cannot be set as its own parent contract.",
    			this.ParentContractID,
    			ValidationErrorType.Failure
    		));
    	}
    }

    /**
    * A contract cannot be superseded by itself. If a superseding contract is specified, it must be a different contract.
    * @param result - the ValidationResult object to add any errors or warnings to
    * @public
    * @method
    */
    public ValidateSupersededByContractIDNotSelf(result: ValidationResult) {
        if (this.SupersededByContractID != null && this.SupersededByContractID === this.ID) {
            result.Errors.push(new ValidationErrorInfo(
                "SupersededByContractID",
                "A contract cannot be superseded by itself.",
                this.SupersededByContractID,
                ValidationErrorType.Failure
            ));
        }
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
    * * Display Name: Contract Type
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
    * * Display Name: Selling Company
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ: Companies (vwCompanies.ID)
    * * Description: The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.
    */
    get CompanyID(): string {
        return this.Get('CompanyID');
    }
    set CompanyID(value: string) {
        this.Set('CompanyID', value);
    }

    /**
    * * Field Name: CustomerOrganizationID
    * * Display Name: Customer Organization
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: Organizations (vwOrganizations.ID)
    * * Description: The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.
    */
    get CustomerOrganizationID(): string {
        return this.Get('CustomerOrganizationID');
    }
    set CustomerOrganizationID(value: string) {
        this.Set('CustomerOrganizationID', value);
    }

    /**
    * * Field Name: PrimaryContactPersonID
    * * Display Name: Primary Contact
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Common: People (vwPeople.ID)
    * * Description: Their named contact, optional.
    */
    get PrimaryContactPersonID(): string | null {
        return this.Get('PrimaryContactPersonID');
    }
    set PrimaryContactPersonID(value: string | null) {
        this.Set('PrimaryContactPersonID', value);
    }

    /**
    * * Field Name: ContractTemplateID
    * * Display Name: Contract Template
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contract Templates (vwContractTemplates.ID)
    * * Description: The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.
    */
    get ContractTemplateID(): string | null {
        return this.Get('ContractTemplateID');
    }
    set ContractTemplateID(value: string | null) {
        this.Set('ContractTemplateID', value);
    }

    /**
    * * Field Name: CreatingEntityID
    * * Display Name: Creating Entity
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ: Entities (vwEntities.ID)
    * * Description: Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.
    */
    get CreatingEntityID(): string | null {
        return this.Get('CreatingEntityID');
    }
    set CreatingEntityID(value: string | null) {
        this.Set('CreatingEntityID', value);
    }

    /**
    * * Field Name: CreatingRecordID
    * * Display Name: Creating Record ID
    * * SQL Data Type: nvarchar(450)
    * * Description: Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.
    */
    get CreatingRecordID(): string | null {
        return this.Get('CreatingRecordID');
    }
    set CreatingRecordID(value: string | null) {
        this.Set('CreatingRecordID', value);
    }

    /**
    * * Field Name: ParentContractID
    * * Display Name: Parent Contract
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    * * Description: The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.
    */
    get ParentContractID(): string | null {
        return this.Get('ParentContractID');
    }
    set ParentContractID(value: string | null) {
        this.Set('ParentContractID', value);
    }

    /**
    * * Field Name: SupersededByContractID
    * * Display Name: Superseded By
    * * SQL Data Type: uniqueidentifier
    * * Related Entity/Foreign Key: MJ_BizApps_Contracts: Contracts (vwContracts.ID)
    * * Description: The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.
    */
    get SupersededByContractID(): string | null {
        return this.Get('SupersededByContractID');
    }
    set SupersededByContractID(value: string | null) {
        this.Set('SupersededByContractID', value);
    }

    /**
    * * Field Name: SigningProviderURL
    * * Display Name: Signing Provider URL
    * * SQL Data Type: nvarchar(1000)
    * * Description: Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.
    */
    get SigningProviderURL(): string | null {
        return this.Get('SigningProviderURL');
    }
    set SigningProviderURL(value: string | null) {
        this.Set('SigningProviderURL', value);
    }

    /**
    * * Field Name: EffectiveDate
    * * Display Name: Effective Date
    * * SQL Data Type: date
    * * Description: When the agreement takes effect.
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
    * * Description: When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.
    */
    get ExecutedDate(): Date | null {
        return this.Get('ExecutedDate');
    }
    set ExecutedDate(value: Date | null) {
        this.Set('ExecutedDate', value);
    }

    /**
    * * Field Name: EndDate
    * * Display Name: End Date
    * * SQL Data Type: date
    * * Description: When the current term ends. This is what drives the renewal watchlist and every expiry projection.
    */
    get EndDate(): Date | null {
        return this.Get('EndDate');
    }
    set EndDate(value: Date | null) {
        this.Set('EndDate', value);
    }

    /**
    * * Field Name: TerminatedDate
    * * Display Name: Terminated Date
    * * SQL Data Type: date
    * * Description: When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.
    */
    get TerminatedDate(): Date | null {
        return this.Get('TerminatedDate');
    }
    set TerminatedDate(value: Date | null) {
        this.Set('TerminatedDate', value);
    }

    /**
    * * Field Name: AutoRenew
    * * Display Name: Auto Renew
    * * SQL Data Type: bit
    * * Default Value: 0
    * * Description: Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.
    */
    get AutoRenew(): boolean {
        return this.Get('AutoRenew');
    }
    set AutoRenew(value: boolean) {
        this.Set('AutoRenew', value);
    }

    /**
    * * Field Name: RenewalNoticeDays
    * * Display Name: Renewal Notice Days
    * * SQL Data Type: int
    * * Description: Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.
    */
    get RenewalNoticeDays(): number | null {
        return this.Get('RenewalNoticeDays');
    }
    set RenewalNoticeDays(value: number | null) {
        this.Set('RenewalNoticeDays', value);
    }

    /**
    * * Field Name: CancellationWindowDays
    * * Display Name: Cancellation Window Days
    * * SQL Data Type: int
    * * Description: Days of notice the customer owes to cancel without renewing.
    */
    get CancellationWindowDays(): number | null {
        return this.Get('CancellationWindowDays');
    }
    set CancellationWindowDays(value: number | null) {
        this.Set('CancellationWindowDays', value);
    }

    /**
    * * Field Name: AnnualIncreasePercent
    * * Display Name: Annual Increase Percent
    * * SQL Data Type: decimal(7, 4)
    * * Description: The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.
    */
    get AnnualIncreasePercent(): number | null {
        return this.Get('AnnualIncreasePercent');
    }
    set AnnualIncreasePercent(value: number | null) {
        this.Set('AnnualIncreasePercent', value);
    }

    /**
    * * Field Name: HasModifications
    * * Display Name: Has Modifications
    * * SQL Data Type: bit
    * * Default Value: 0
    * * Description: Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.
    */
    get HasModifications(): boolean {
        return this.Get('HasModifications');
    }
    set HasModifications(value: boolean) {
        this.Set('HasModifications', value);
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
    * * Field Name: Notes
    * * Display Name: Notes
    * * SQL Data Type: nvarchar(MAX)
    * * Description: Free-text working notes for whoever is processing the contract.
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
    * * Field Name: ContractType
    * * Display Name: Contract Type Name
    * * SQL Data Type: nvarchar(100)
    */
    get ContractType(): string {
        return this.Get('ContractType');
    }

    /**
    * * Field Name: Company
    * * Display Name: Company Name
    * * SQL Data Type: nvarchar(50)
    */
    get Company(): string {
        return this.Get('Company');
    }

    /**
    * * Field Name: CustomerOrganization
    * * Display Name: Customer Organization Name
    * * SQL Data Type: nvarchar(255)
    */
    get CustomerOrganization(): string {
        return this.Get('CustomerOrganization');
    }

    /**
    * * Field Name: PrimaryContactPerson
    * * Display Name: Primary Contact Name
    * * SQL Data Type: nvarchar(100)
    */
    get PrimaryContactPerson(): string | null {
        return this.Get('PrimaryContactPerson');
    }

    /**
    * * Field Name: ContractTemplate
    * * Display Name: Contract Template Name
    * * SQL Data Type: nvarchar(200)
    */
    get ContractTemplate(): string | null {
        return this.Get('ContractTemplate');
    }

    /**
    * * Field Name: CreatingEntity
    * * Display Name: Creating Entity Name
    * * SQL Data Type: nvarchar(255)
    */
    get CreatingEntity(): string | null {
        return this.Get('CreatingEntity');
    }

    /**
    * * Field Name: ParentContract
    * * Display Name: Parent Contract Name
    * * SQL Data Type: nvarchar(50)
    */
    get ParentContract(): string | null {
        return this.Get('ParentContract');
    }

    /**
    * * Field Name: SupersededByContract
    * * Display Name: Superseded By Name
    * * SQL Data Type: nvarchar(50)
    */
    get SupersededByContract(): string | null {
        return this.Get('SupersededByContract');
    }

    /**
    * * Field Name: RootParentContractID
    * * Display Name: Root Parent Contract
    * * SQL Data Type: uniqueidentifier
    */
    get RootParentContractID(): string | null {
        return this.Get('RootParentContractID');
    }

    /**
    * * Field Name: RootSupersededByContractID
    * * Display Name: Root Superseded By
    * * SQL Data Type: uniqueidentifier
    */
    get RootSupersededByContractID(): string | null {
        return this.Get('RootSupersededByContractID');
    }

    /**
    * * Field Name: State
    * * Display Name: Contract State
    * * SQL Data Type: varchar(10)
    */
    get State(): string {
        return this.Get('State');
    }

    /**
    * * Field Name: IsAwaitingDocument
    * * Display Name: Is Awaiting Document
    * * SQL Data Type: bit
    */
    get IsAwaitingDocument(): boolean | null {
        return this.Get('IsAwaitingDocument');
    }

    /**
    * * Field Name: DaysToEnd
    * * Display Name: Days To End
    * * SQL Data Type: int
    */
    get DaysToEnd(): number | null {
        return this.Get('DaysToEnd');
    }

    /**
    * * Field Name: RenewalNoticeDeadline
    * * Display Name: Renewal Notice Deadline
    * * SQL Data Type: date
    */
    get RenewalNoticeDeadline(): Date | null {
        return this.Get('RenewalNoticeDeadline');
    }

    /**
    * * Field Name: IsInCancellationWindow
    * * Display Name: Is In Cancellation Window
    * * SQL Data Type: bit
    */
    get IsInCancellationWindow(): boolean | null {
        return this.Get('IsInCancellationWindow');
    }
}
