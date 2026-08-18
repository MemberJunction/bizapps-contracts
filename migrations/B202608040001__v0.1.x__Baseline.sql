-- =============================================================================
-- BizApps Contracts — THE BASELINE (v0.1.0)
-- =============================================================================
-- ONE FILE. Schema, SchemaInfo registration, seven tables and their constraints,
-- and the CodeGen output that turns bare tables into a working app. Applying this
-- file to an empty database produces an installed contracts app; nothing else is
-- required before `mj sync push` seeds the reference vocabulary.
--
-- THIS IS A CLEAN-SHEET REPLACEMENT of the v1 ten-table schema. v1 was an
-- agreement ENGINE — it owned commitment, term structure, escalation, billing
-- events and contracted pricing, and produced orders. Subscriptions in
-- bizapps-orders do all of that now, so keeping it here would leave two systems
-- that have to agree about money. What remains is the source of truth for our
-- obligations and the place to find the documents that show them.
--
-- Gone with v1: ContractTerm, ContractLine, ContractBillingSchedule,
-- ContractBillingEvent, ContractCommitment, ContractAmendment, ContractEvent, and
-- the old behaviour-carrying ContractType.
--
-- PRE-PRODUCTION PRACTICE. Nothing here is published, so schema changes EDIT THIS
-- FILE IN PLACE and the database is rebuilt from zero — no incremental fix-up
-- migrations. Switch to additive-only at first publish, after which an applied
-- migration is immutable. See migrations/_README.md.
--
-- Design source of truth: plans/bizapps-contracts-master.md and
-- plans/ERD-planned.md in this repo. Decisions D-1..D-23; the ERD's §9 reversal
-- log records every ruling that changed the shape, with owner and date.
--
-- FOUR RULES THIS SCHEMA OBEYS (ERD §0):
--   1. Every reference is a real foreign key. The one exception is the typed
--      polymorphic pair in §3.5 (CreatingEntityID + CreatingRecordID).
--   2. Nothing here hard-references bizapps-sales. Sales creates contracts, so
--      sales depends on us; a reference upward would invert the graph.
--   3. Structured obligations are COLUMNS; textual deviations are MODIFICATION
--      ROWS. This is why there is no TerminationPolicy column (R-6).
--   4. Documents, signatures and audit are MJ's — __mj.FileEntityRecordLink,
--      __mj.SignatureRequest, __mj.RecordChange all point AT us. There is no
--      document column and no audit table here.
--
-- NO STATUS COLUMN, DELIBERATELY (R-18). Four of its five values were projections
-- of the dates and the two self-FKs; the fifth (Draft) was the finance task
-- wearing a status. Lifecycle is derived as `State` on the app-owned layered base
-- view, together with IsAwaitingDocument and IsChangeOrder — see the follow-up
-- migration that installs the wrapper.
--
-- Seed rows for ContractType, ContractTemplateType and the Master Agreement's
-- provisions ship via metadata/ with hardcoded UUIDs (the bizapps-common
-- address-types pattern). NEVER as INSERTs here. ContractSequence is the one
-- exception: a singleton counter, not vocabulary, and it must exist before the
-- first contract is written.
-- =============================================================================

-- =============================================================================
-- 1. SCHEMA
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '__mj_BizAppsContracts')
    EXEC('CREATE SCHEMA __mj_BizAppsContracts');
GO

-- =============================================================================
-- 2. SCHEMA INFO — entity-name prefix for CodeGen (must match mj.config.cjs)
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM __mj.SchemaInfo WHERE SchemaName = '__mj_BizAppsContracts')
INSERT INTO __mj.SchemaInfo
(
  ID,
  SchemaName,
  EntityIDMin, EntityIDMax,
  Comments,
  Description,
  EntityNamePrefix, EntityNameSuffix
)
VALUES
(
  '1A531C07-5F1A-448D-A2BF-B986801F4F1D',
  '__mj_BizAppsContracts',
  1, 1000000,
  NULL,
  'MemberJunction: BizApps Contracts — the record of our obligations, and where the documents live',
  'MJ_BizApps_Contracts: ', NULL
);
GO

-- =============================================================================
-- 2.A TYPES
-- =============================================================================
-- None. If this app ever adds a user-defined table type, split it into its own
-- earlier-timestamped migration first: a trigger that declares a variable of a
-- type created in the same transaction deadlocks on the type's own metadata lock,
-- and it surfaces as `Msg 1205` at an innocent CodeGen backfill hundreds of
-- batches later, reading as server instability rather than an ordering bug.

-- =============================================================================
-- 3. TABLES
-- =============================================================================

---------------------------------------------------------------------------
-- 3.1 ContractTemplateType — the kind of standard agreement.
--     A lookup TABLE rather than a CHECK, for the reason accounting gives for
--     GLAccountRole: the value list is additive at runtime (a data-processing
--     addendum, a BAA, a reseller agreement) and a business user should add one
--     without a migration. Carries no behaviour.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTemplateType (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    Status NVARCHAR(10) NOT NULL DEFAULT 'Active',
    CONSTRAINT PK_ContractTemplateType PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplateType_Name UNIQUE (Name),
    CONSTRAINT CK_ContractTemplateType_Status CHECK (Status IN ('Active','Inactive'))
);
GO

---------------------------------------------------------------------------
-- 3.2 ContractTemplate — one VERSION of a standard agreement.
--     In practice the Master Agreement, published at a date-versioned public URL
--     that never goes away, so a customer who signed in June 2026 stays bound to
--     the June 2026 text.
--
--     SourceURL is NOT NULL: every template we have is a published dated URL, and
--     that is the whole mechanism. A template nobody can open is not a record of
--     anything. If a privately-held template ever arrives, relaxing this is a
--     one-line additive change made with the real case in hand (ERD §4.1).
--
--     Carries no prose of its own — ContentText was removed (R-11) and every
--     clause's standard wording lives on its provision row instead (R-15/D-16).
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTemplate (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Name NVARCHAR(200) NOT NULL,
    ContractTemplateTypeID UNIQUEIDENTIFIER NOT NULL,
    VersionLabel NVARCHAR(50) NULL,
    IntroducedDate DATE NULL,
    SourceURL NVARCHAR(1000) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractTemplate PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplate_Name UNIQUE (Name)
);
GO

---------------------------------------------------------------------------
-- 3.3 ContractTemplateProvision — the numbered clause list of a template
--     version, and the home of all standard contract text (D-16).
--
--     It hangs off ContractTemplate rather than standing alone because provision
--     numbering belongs to a VERSION: the moment v7 renumbers, a single global
--     list is wrong.
--
--     Sequence exists because ProvisionNumber does not sort as text — '3.10'
--     lands before '3.5' — and a legal document has a canonical order.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTemplateProvision (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTemplateID UNIQUEIDENTIFIER NOT NULL,
    ProvisionNumber NVARCHAR(20) NOT NULL,
    Title NVARCHAR(200) NOT NULL,
    ProvisionText NVARCHAR(MAX) NULL,
    Description NVARCHAR(MAX) NULL,
    Sequence INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_ContractTemplateProvision PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplateProvision_Template_Number
        UNIQUE (ContractTemplateID, ProvisionNumber)
);
GO

---------------------------------------------------------------------------
-- 3.4 ContractType — the kind of paper.
--     RequiresExecutedDocument is the one behavioural column, and it is
--     configuration-as-data rather than a branch on a type name: it is what stops
--     a Payment Link contract asking forever for paper that will never arrive.
--     "Awaiting the document" is then DERIVED as `requires it AND no linked file`
--     (ERD §4.5) — never a status, never a column.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractType (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    RequiresExecutedDocument BIT NOT NULL DEFAULT 1,
    Status NVARCHAR(10) NOT NULL DEFAULT 'Active',
    CONSTRAINT PK_ContractType PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractType_Name UNIQUE (Name),
    CONSTRAINT CK_ContractType_Status CHECK (Status IN ('Active','Inactive'))
);
GO

---------------------------------------------------------------------------
-- 3.5 ContractSequence — singleton counter behind CTR-{seq}.
--     Same shape orders uses for ORD- and PAY-. Seeded here because it is a
--     counter, not vocabulary: it must exist before the first contract is written.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractSequence (
    ID INT NOT NULL,
    NextSequenceNumber INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_ContractSequence PRIMARY KEY (ID),
    CONSTRAINT CK_ContractSequence_Singleton CHECK (ID = 1),
    CONSTRAINT CK_ContractSequence_NextSeq CHECK (NextSequenceNumber > 0)
);
GO

INSERT INTO __mj_BizAppsContracts.ContractSequence (ID, NextSequenceNumber)
VALUES (1, 1);
GO

---------------------------------------------------------------------------
-- 3.6 Contract — the signed agreement. One row = one piece of signed (or
--     implied) paper, and the centre of the app.
--
--     CompanyID and CustomerOrganizationID are not the same kind of thing:
--     __mj.Company is OUR legal entity (which Blue Cypress company sells this),
--     Organization is the customer. CompanyID is not reliably derivable from the
--     deal, which is why it is stored.
--
--     CustomerOrganizationID is NOT NULL and there is no CustomerPersonID: the
--     individual case lives entirely in orders. "The contract layer is much more
--     the B2B scenario, not B2C."
--
--     CreatingEntityID + CreatingRecordID is the typed polymorphic pair naming
--     the record that CREATED this contract — in practice a Deal. A hard FK is
--     impossible by rule 2, and this is the pattern accounting uses for
--     JournalEntry provenance. Half the reference IS enforced: the entity FK.
--
--     NOTHING ABOUT A DOCUMENT IS REQUIRED TO SAVE A CONTRACT (ruled 2026-08-18).
--     There is no document column at all; files attach through
--     __mj.FileEntityRecordLink, and SigningProviderURL is the direct link to the
--     document in the signing provider.
--
--     ExecutedDate may legitimately PRECEDE EffectiveDate — sign in December for a
--     January start is the ordinary case, not an anomaly. v1 had a constraint
--     forbidding it and it rejected exactly the data a correct contract produces.
--
--     HasModifications is asserted by a person, not derived: its job is to say "go
--     read the PDF" BEFORE anyone has recorded the modifications. One direction IS
--     enforced, server-side — if modification rows exist the flag must be true —
--     and it is never cleared automatically (ERD §4.4).
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.Contract (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractNumber NVARCHAR(50) NOT NULL,
    ContractTypeID UNIQUEIDENTIFIER NOT NULL,
    CompanyID UNIQUEIDENTIFIER NOT NULL,
    CustomerOrganizationID UNIQUEIDENTIFIER NOT NULL,
    PrimaryContactPersonID UNIQUEIDENTIFIER NULL,
    ContractTemplateID UNIQUEIDENTIFIER NULL,
    CreatingEntityID UNIQUEIDENTIFIER NULL,
    CreatingRecordID NVARCHAR(450) NULL,
    ParentContractID UNIQUEIDENTIFIER NULL,
    SupersededByContractID UNIQUEIDENTIFIER NULL,
    SigningProviderURL NVARCHAR(1000) NULL,
    EffectiveDate DATE NULL,
    ExecutedDate DATE NULL,
    EndDate DATE NULL,
    TerminatedDate DATE NULL,
    AutoRenew BIT NOT NULL DEFAULT 0,
    RenewalNoticeDays INT NULL,
    CancellationWindowDays INT NULL,
    AnnualIncreasePercent DECIMAL(7,4) NULL,
    HasModifications BIT NOT NULL DEFAULT 0,
    Description NVARCHAR(MAX) NULL,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_Contract PRIMARY KEY (ID),
    -- The polymorphic pair is set together or not at all. Same shape accounting
    -- uses; CodeGen derives the generated validator from this expression, so each
    -- column is named ONCE (repeating one makes CodeGen emit a call to a method it
    -- never defines — a build break in generated code that orders documented).
    CONSTRAINT CK_Contract_CreatingPairBothOrNeither CHECK (
        (CreatingEntityID IS NULL AND CreatingRecordID IS NULL)
     OR (CreatingEntityID IS NOT NULL AND CreatingRecordID IS NOT NULL)
    ),
    -- A contract cannot be its own parent or its own successor. Deeper cycles are
    -- the engine's problem; these catch the ones a UI produces by accident.
    CONSTRAINT CK_Contract_ParentNotSelf CHECK (ParentContractID IS NULL OR ParentContractID <> ID),
    CONSTRAINT CK_Contract_SupersededNotSelf CHECK (SupersededByContractID IS NULL OR SupersededByContractID <> ID),
    CONSTRAINT CK_Contract_RenewalNoticeDays CHECK (RenewalNoticeDays IS NULL OR RenewalNoticeDays >= 0),
    CONSTRAINT CK_Contract_CancellationWindow CHECK (CancellationWindowDays IS NULL OR CancellationWindowDays >= 0),
    CONSTRAINT CK_Contract_AnnualIncrease CHECK (AnnualIncreasePercent IS NULL OR AnnualIncreasePercent >= 0),
    CONSTRAINT CK_Contract_Dates CHECK (EndDate IS NULL OR EffectiveDate IS NULL OR EndDate >= EffectiveDate)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_Contract_ContractNumber
    ON __mj_BizAppsContracts.Contract (ContractNumber);
GO

-- The polymorphic record id is not a foreign key, so it earns an index of its own:
-- "which contract did this deal create" is the reverse lookup sales will run.
CREATE NONCLUSTERED INDEX IX_Contract_CreatingRecord
    ON __mj_BizAppsContracts.Contract (CreatingEntityID, CreatingRecordID);
GO

---------------------------------------------------------------------------
-- 3.7 ContractTemplateModification — what THIS contract changed about the
--     standard agreement.
--
--     Deliberately lean. It names a provision and carries what the contract says
--     instead; the standard wording sits on the provision row, and reading the two
--     as a pair is the point (D-16).
--
--     NO ContractTemplateID (R-16). The provision belongs to exactly one template
--     in every future, so Modification -> Provision -> Template derives it, and a
--     stored copy of a derivation can only agree or lie. What replaces it is the
--     rule that was always implicit and now lives server-side: a modification's
--     provision must belong to a template this contract incorporates.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTemplateModification (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractID UNIQUEIDENTIFIER NOT NULL,
    ContractTemplateProvisionID UNIQUEIDENTIFIER NOT NULL,
    ModificationText NVARCHAR(MAX) NULL,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractTemplateModification PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplateModification_Contract_Provision
        UNIQUE (ContractID, ContractTemplateProvisionID)
);
GO

-- =============================================================================
-- 4. FOREIGN KEYS
-- =============================================================================
-- One ALTER per table per reference, which is the convention CodeGen's index
-- generation expects.

---------------------------------------------------------------------------
-- 4.1 Within __mj_BizAppsContracts
---------------------------------------------------------------------------
ALTER TABLE __mj_BizAppsContracts.ContractTemplate
    ADD CONSTRAINT FK_ContractTemplate_ContractTemplateType
    FOREIGN KEY (ContractTemplateTypeID) REFERENCES __mj_BizAppsContracts.ContractTemplateType(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractTemplateProvision
    ADD CONSTRAINT FK_ContractTemplateProvision_ContractTemplate
    FOREIGN KEY (ContractTemplateID) REFERENCES __mj_BizAppsContracts.ContractTemplate(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_ContractType
    FOREIGN KEY (ContractTypeID) REFERENCES __mj_BizAppsContracts.ContractType(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_ContractTemplate
    FOREIGN KEY (ContractTemplateID) REFERENCES __mj_BizAppsContracts.ContractTemplate(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_ParentContract
    FOREIGN KEY (ParentContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_SupersededByContract
    FOREIGN KEY (SupersededByContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractTemplateModification
    ADD CONSTRAINT FK_ContractTemplateModification_Contract
    FOREIGN KEY (ContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractTemplateModification
    ADD CONSTRAINT FK_ContractTemplateModification_ContractTemplateProvision
    FOREIGN KEY (ContractTemplateProvisionID) REFERENCES __mj_BizAppsContracts.ContractTemplateProvision(ID);
GO

---------------------------------------------------------------------------
-- 4.A CROSS-APP FOREIGN KEYS — real constraints, not soft UUID columns.
--     FOUR of them, down from thirteen in v1: everything pointing at orders left
--     with ContractLine and ContractBillingEvent, accounting's Currency left with
--     ContractTerm, and tasks' Task left with ContractAmendment. Contracts no
--     longer references orders, accounting or tasks at all.
--
--     These schemas MUST exist — MJ core and BizAppsCommon migrations run first —
--     which the dependency declaration in mj-app.json guarantees.
---------------------------------------------------------------------------
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_Company
    FOREIGN KEY (CompanyID) REFERENCES __mj.Company(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_CustomerOrganization
    FOREIGN KEY (CustomerOrganizationID) REFERENCES __mj_BizAppsCommon.Organization(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_PrimaryContactPerson
    FOREIGN KEY (PrimaryContactPersonID) REFERENCES __mj_BizAppsCommon.Person(ID);
GO

-- Half of the polymorphic pair, and the half worth enforcing: it says WHAT KIND of
-- record CreatingRecordID points at, which is what lets MJ resolve the pair
-- generically without contracts knowing what a Deal is.
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_CreatingEntity
    FOREIGN KEY (CreatingEntityID) REFERENCES __mj.Entity(ID);
GO

-- =============================================================================
-- 5. EXTENDED PROPERTIES
-- =============================================================================
-- MS_Description on every table and every meaningful column: CodeGen turns these
-- into entity and entity-field descriptions, so this is the only place the
-- reasoning reaches a person reading the app rather than the repo.

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateType';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateType', @level2type=N'COLUMN', @level2name=N'Status';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate', @level2type=N'COLUMN', @level2name=N'VersionLabel';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate', @level2type=N'COLUMN', @level2name=N'IntroducedDate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The dated public URL. NOT NULL — every template we have is a published URL and it is what the executed PDF cites; a template nobody can open is not a record of anything.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate', @level2type=N'COLUMN', @level2name=N'SourceURL';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'ProvisionNumber';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'Title';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'ProvisionText';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Display order. Earns its place because ProvisionNumber does not sort as text ("3.10" lands before "3.5") and a legal document has a canonical order.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'Sequence';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'RequiresExecutedDocument';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Active | Inactive.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'Status';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Singleton counter behind ContractNumber (CTR-{seq}), the same shape orders uses for ORD- and PAY-. Seeded in the baseline because it is a counter rather than vocabulary: it must exist before the first contract is written.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractSequence';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The next number to hand out. Advanced server-side by ContractEntityServer.Save().', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractSequence', @level2type=N'COLUMN', @level2name=N'NextSequenceNumber';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'CTR-{seq} from ContractSequence. Unique.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ContractNumber';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CompanyID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CustomerOrganizationID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Their named contact, optional.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'PrimaryContactPersonID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ContractTemplateID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CreatingEntityID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CreatingRecordID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ParentContractID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'SupersededByContractID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'SigningProviderURL';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'When the agreement takes effect.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'EffectiveDate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ExecutedDate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'When the current term ends. This is what drives the renewal watchlist and every expiry projection.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'EndDate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'TerminatedDate';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'AutoRenew';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'RenewalNoticeDays';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Days of notice the customer owes to cancel without renewing.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CancellationWindowDays';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'AnnualIncreasePercent';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'HasModifications';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Free-text working notes for whoever is processing the contract.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'Notes';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateModification';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateModification', @level2type=N'COLUMN', @level2name=N'ContractTemplateProvisionID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateModification', @level2type=N'COLUMN', @level2name=N'ModificationText';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Optional working note, e.g. who negotiated it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateModification', @level2type=N'COLUMN', @level2name=N'Notes';
GO
