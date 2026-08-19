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

-- =============================================================================
-- SECTION 6 — CODEGEN CAPTURE
-- =============================================================================
-- Everything above this line creates TABLES. Everything below is CodeGen's own
-- output, captured verbatim from the run that registered this schema: the
-- `__mj.Entity` and `__mj.EntityField` rows, the seven base views, the CRUD
-- procedures, the `__mj_UpdatedAt` triggers, the FK indexes, the permission
-- grants and the ApplicationEntity links.
--
-- WITHOUT THIS SECTION THE BASELINE INSTALLS NOTHING USABLE. Proven, not
-- assumed: applying the file without it to a fresh database yielded 8 tables,
-- 0 views and 0 entity rows — bare tables that MJ cannot see, against which
-- `mj sync push` fails because no `MJ_BizApps_Contracts:*` entity exists for a
-- seed record to resolve. Caught on review of PR #9, 2026-08-18.
--
-- HOW IT WAS PRODUCED (repeat this, do not hand-edit below):
--   1. `mjdev wipe-db <slug> --yes`
--   2. MJ core + common → tasks → accounting → orders → contracts migrations
--      (each app's own `pnpm run mj:migrate`; mjdev's app engine is broken
--      against MJ 6 next — MJDev#28)
--   3. `DOTENV_CONFIG_PATH=../mj/.env pnpm run mj:codegen`
--   4. append `migrations/codegen/CodeGen_Run_*.sql` below this banner
-- Schema names are already substituted with ${flyway:defaultSchema} /
-- ${mjSchema} by the SQLOutput.schemaPlaceholders config — do not re-run a
-- find-and-replace over it.
--
-- ⚠ CodeGen exits NON-ZERO even on success, because its AFTER commands shell out
-- to `npm` inside a pnpm workspace (WORKAROUNDS.md W-3). Never gate the append on
-- the exit code — check the output for `✔ MJ CodeGen complete` instead. A skipped
-- append is exactly the failure this section documents.
--
-- NOTE ON THE BASE VIEWS BELOW: they are generated at the PUBLIC names
-- (vwContracts, …), which is correct for this file. `Contracts` then becomes a
-- LAYERED base view in the next migration, which flips the flags and moves the
-- generated view to vwContractsGenerated so the app can own vwContracts as a
-- wrapper carrying State, IsAwaitingDocument and IsChangeOrder. That ordering is
-- deliberate and is orders' proven train (V202608131541/1542) — see those files.
-- =============================================================================

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Types */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '8d50b054-0e15-48c2-907a-ba598e28ea25',
         'MJ_BizApps_Contracts: Contract Template Types',
         'Contract Template Types',
         'The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.',
         NULL,
         'ContractTemplateType',
         'vwContractTemplateTypes',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to create new application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[Application] WHERE [ID] = '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[Application] (ID, Name, Description, SchemaAutoAddNewEntities, Path, AutoUpdatePath, DefaultForNewUser)
                       VALUES ('976feb0c-7f26-4bc8-83f1-8b5c775e6cd1', '${flyway:defaultSchema}', 'Generated for schema', '${flyway:defaultSchema}', 'mjbizappscontracts', 1, 0)
   END;

/* Adding role UI to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1' AND [RoleID] = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('976feb0c-7f26-4bc8-83f1-8b5c775e6cd1', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* Adding role Developer to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1' AND [RoleID] = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('976feb0c-7f26-4bc8-83f1-8b5c775e6cd1', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1)
   END;

/* Adding role Integration to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1' AND [RoleID] = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('976feb0c-7f26-4bc8-83f1-8b5c775e6cd1', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Types to application ID: '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976feb0c-7f26-4bc8-83f1-8b5c775e6cd1', '8d50b054-0e15-48c2-907a-ba598e28ea25', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976feb0c-7f26-4bc8-83f1-8b5c775e6cd1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('8d50b054-0e15-48c2-907a-ba598e28ea25', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('8d50b054-0e15-48c2-907a-ba598e28ea25', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('8d50b054-0e15-48c2-907a-ba598e28ea25', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Templates */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '21c7d64a-28f3-4535-819a-e0dd384a5580',
         'MJ_BizApps_Contracts: Contract Templates',
         'Contract Templates',
         'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.',
         NULL,
         'ContractTemplate',
         'vwContractTemplates',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Templates to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', '21c7d64a-28f3-4535-819a-e0dd384a5580', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('21c7d64a-28f3-4535-819a-e0dd384a5580', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('21c7d64a-28f3-4535-819a-e0dd384a5580', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('21c7d64a-28f3-4535-819a-e0dd384a5580', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Provisions */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '27a600ca-6a2e-4c85-84ae-924183ec1681',
         'MJ_BizApps_Contracts: Contract Template Provisions',
         'Contract Template Provisions',
         'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.',
         NULL,
         'ContractTemplateProvision',
         'vwContractTemplateProvisions',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Provisions to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', '27a600ca-6a2e-4c85-84ae-924183ec1681', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('27a600ca-6a2e-4c85-84ae-924183ec1681', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('27a600ca-6a2e-4c85-84ae-924183ec1681', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('27a600ca-6a2e-4c85-84ae-924183ec1681', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Types */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'ebb3f628-267e-44d6-8f18-258ac28ff981',
         'MJ_BizApps_Contracts: Contract Types',
         'Contract Types',
         'The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.',
         NULL,
         'ContractType',
         'vwContractTypes',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Types to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', 'ebb3f628-267e-44d6-8f18-258ac28ff981', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('ebb3f628-267e-44d6-8f18-258ac28ff981', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('ebb3f628-267e-44d6-8f18-258ac28ff981', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('ebb3f628-267e-44d6-8f18-258ac28ff981', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Sequences */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '96271f4a-ac8d-47c8-bb5d-c7180910b2c7',
         'MJ_BizApps_Contracts: Contract Sequences',
         'Contract Sequences',
         'Singleton counter behind ContractNumber (CTR-{seq}), the same shape orders uses for ORD- and PAY-. Seeded in the baseline because it is a counter rather than vocabulary: it must exist before the first contract is written.',
         NULL,
         'ContractSequence',
         'vwContractSequences',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Sequences to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', '96271f4a-ac8d-47c8-bb5d-c7180910b2c7', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('96271f4a-ac8d-47c8-bb5d-c7180910b2c7', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('96271f4a-ac8d-47c8-bb5d-c7180910b2c7', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('96271f4a-ac8d-47c8-bb5d-c7180910b2c7', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contracts */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '4cc3db2d-f01f-405e-a47d-b14ba2f1ab20',
         'MJ_BizApps_Contracts: Contracts',
         'Contracts',
         'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.',
         NULL,
         'Contract',
         'vwContracts',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contracts to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', '4cc3db2d-f01f-405e-a47d-b14ba2f1ab20', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4cc3db2d-f01f-405e-a47d-b14ba2f1ab20', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4cc3db2d-f01f-405e-a47d-b14ba2f1ab20', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4cc3db2d-f01f-405e-a47d-b14ba2f1ab20', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Modifications */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '2e611a7d-2fbb-4a45-a9c8-103834bf026a',
         'MJ_BizApps_Contracts: Contract Template Modifications',
         'Contract Template Modifications',
         'What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.',
         NULL,
         'ContractTemplateModification',
         'vwContractTemplateModifications',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Modifications to application ID: '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1', '2e611a7d-2fbb-4a45-a9c8-103834bf026a', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '976FEB0C-7F26-4BC8-83F1-8B5C775E6CD1'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2e611a7d-2fbb-4a45-a9c8-103834bf026a', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2e611a7d-2fbb-4a45-a9c8-103834bf026a', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2e611a7d-2fbb-4a45-a9c8-103834bf026a', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
UPDATE [${flyway:defaultSchema}].[ContractTemplateModification] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateModification___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
UPDATE [${flyway:defaultSchema}].[ContractTemplateModification] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateModification */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateModification___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
UPDATE [${flyway:defaultSchema}].[ContractType] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractType___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
UPDATE [${flyway:defaultSchema}].[ContractType] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractType___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
UPDATE [${flyway:defaultSchema}].[ContractTemplateProvision] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateProvision___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
UPDATE [${flyway:defaultSchema}].[ContractTemplateProvision] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateProvision */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateProvision___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
UPDATE [${flyway:defaultSchema}].[Contract] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD CONSTRAINT [DF___mj_BizAppsContracts_Contract___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
UPDATE [${flyway:defaultSchema}].[Contract] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD CONSTRAINT [DF___mj_BizAppsContracts_Contract___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
UPDATE [${flyway:defaultSchema}].[ContractTemplateType] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateType___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
UPDATE [${flyway:defaultSchema}].[ContractTemplateType] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplateType */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplateType___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
UPDATE [${flyway:defaultSchema}].[ContractSequence] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractSequence___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
UPDATE [${flyway:defaultSchema}].[ContractSequence] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractSequence___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
UPDATE [${flyway:defaultSchema}].[ContractTemplate] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplate___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
UPDATE [${flyway:defaultSchema}].[ContractTemplate] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTemplate */
ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTemplate___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to insert 67 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fd9c658f-66ce-43a1-ae3a-40db31530608' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fd9c658f-66ce-43a1-ae3a-40db31530608',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9d1ecade-25c0-4a9c-912a-6b993c5afd35' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'ContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9d1ecade-25c0-4a9c-912a-6b993c5afd35',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 2,
            'ContractID',
            'Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '51331345-4ae4-4882-959a-6046cbbddace' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'ContractTemplateProvisionID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '51331345-4ae4-4882-959a-6046cbbddace',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 3,
            'ContractTemplateProvisionID',
            'Contract Template Provision ID',
            'The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '27A600CA-6A2E-4C85-84AE-924183EC1681',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8178cf5d-d3a4-4405-8fda-90d79b627d55' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'ModificationText')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8178cf5d-d3a4-4405-8fda-90d79b627d55',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 4,
            'ModificationText',
            'Modification Text',
            'What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8dab9c2d-48b0-4c25-8bd3-4dd74029d29a' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'Notes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8dab9c2d-48b0-4c25-8bd3-4dd74029d29a',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 5,
            'Notes',
            'Notes',
            'Optional working note, e.g. who negotiated it.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c89c9aa4-4c51-4623-a042-f475c18b415a' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c89c9aa4-4c51-4623-a042-f475c18b415a',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 6,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9987b09c-fffa-460c-9b86-f1692c1728aa' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9987b09c-fffa-460c-9b86-f1692c1728aa',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 7,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '05cfd8f7-b9cf-4a9c-83e4-d1a2d5ad5105' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '05cfd8f7-b9cf-4a9c-83e4-d1a2d5ad5105',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2c9e961b-6a55-4ce7-9a24-b7c3dfdcb2ff' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2c9e961b-6a55-4ce7-9a24-b7c3dfdcb2ff',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 2,
            'Name',
            'Name',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '238b5941-dc97-43f2-a464-4ed207dda3fe' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '238b5941-dc97-43f2-a464-4ed207dda3fe',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 3,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8c5a7de7-0ecf-42dd-a733-9b18bec29c2b' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = 'RequiresExecutedDocument')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8c5a7de7-0ecf-42dd-a733-9b18bec29c2b',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 4,
            'RequiresExecutedDocument',
            'Requires Executed Document',
            'Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.',
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9a369d85-8c82-4399-885d-837575e37f3c' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9a369d85-8c82-4399-885d-837575e37f3c',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 5,
            'Status',
            'Status',
            'Active | Inactive.',
            'nvarchar',
            20,
            0,
            0,
            0,
            'Active',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '550a2932-55a8-496e-a3f2-84529afeb12f' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '550a2932-55a8-496e-a3f2-84529afeb12f',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 6,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c967e14d-7969-4060-a44b-7ed6783c67bd' OR (EntityID = 'EBB3F628-267E-44D6-8F18-258AC28FF981' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c967e14d-7969-4060-a44b-7ed6783c67bd',
            'EBB3F628-267E-44D6-8F18-258AC28FF981', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981') + 7,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '03fab201-6a05-4f84-a3f4-ad6de9aa4a62' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '03fab201-6a05-4f84-a3f4-ad6de9aa4a62',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b17d0f3b-300e-4c9b-b466-7dfcb5612ec3' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'ContractTemplateID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b17d0f3b-300e-4c9b-b466-7dfcb5612ec3',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 2,
            'ContractTemplateID',
            'Contract Template ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '21C7D64A-28F3-4535-819A-E0DD384A5580',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8399a578-ade9-4c82-a02c-8b7c8efdacb8' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'ProvisionNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8399a578-ade9-4c82-a02c-8b7c8efdacb8',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 3,
            'ProvisionNumber',
            'Provision Number',
            'The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.',
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'dca6d2e5-a043-4407-9a1c-2af676b06d7b' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'Title')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'dca6d2e5-a043-4407-9a1c-2af676b06d7b',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 4,
            'Title',
            'Title',
            'The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.',
            'nvarchar',
            400,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '73b20d56-83dd-4e73-be91-d7fda3cacb25' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'ProvisionText')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '73b20d56-83dd-4e73-be91-d7fda3cacb25',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 5,
            'ProvisionText',
            'Provision Text',
            'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '901d4a8e-91e0-4cdc-b072-98f78d8383eb' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '901d4a8e-91e0-4cdc-b072-98f78d8383eb',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 6,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2278bcb3-6241-45b9-a353-858ec91ff45e' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'Sequence')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2278bcb3-6241-45b9-a353-858ec91ff45e',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 7,
            'Sequence',
            'Sequence',
            'Display order. Earns its place because ProvisionNumber does not sort as text ("3.10" lands before "3.5") and a legal document has a canonical order.',
            'int',
            4,
            10,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0c64db7b-30ee-4fff-8ea8-51bf362d50d0' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0c64db7b-30ee-4fff-8ea8-51bf362d50d0',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 8,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'cf6f8b7c-9560-4770-b07b-32327c139c7f' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'cf6f8b7c-9560-4770-b07b-32327c139c7f',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 9,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3509fda6-f406-42df-805a-a0a7028a2726' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3509fda6-f406-42df-805a-a0a7028a2726',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0dfe97cd-d90a-4b2c-9b9a-281e0fc10d7c' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ContractNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0dfe97cd-d90a-4b2c-9b9a-281e0fc10d7c',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 2,
            'ContractNumber',
            'Contract Number',
            'CTR-{seq} from ContractSequence. Unique.',
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd4c3be29-b422-41a9-8678-d14a5f43c47d' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ContractTypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd4c3be29-b422-41a9-8678-d14a5f43c47d',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 3,
            'ContractTypeID',
            'Contract Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            'EBB3F628-267E-44D6-8F18-258AC28FF981',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '03540125-572c-432b-8e73-2c568464b563' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CompanyID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '03540125-572c-432b-8e73-2c568464b563',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 4,
            'CompanyID',
            'Company ID',
            'The SELLING company (${mjSchema}.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            'D4238F34-2837-EF11-86D4-6045BDEE16E6',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8cf73c13-3cde-4175-a5ff-f8e361476946' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CustomerOrganizationID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8cf73c13-3cde-4175-a5ff-f8e361476946',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 5,
            'CustomerOrganizationID',
            'Customer Organization ID',
            'The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            'C70448F9-9792-41D7-A82C-784B66429D54',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'bdc1ade5-d9c2-4405-9785-dab3818bb0cd' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'PrimaryContactPersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'bdc1ade5-d9c2-4405-9785-dab3818bb0cd',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 6,
            'PrimaryContactPersonID',
            'Primary Contact Person ID',
            'Their named contact, optional.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '49623009-21ad-45e6-9b40-cb4182fe8e35' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ContractTemplateID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '49623009-21ad-45e6-9b40-cb4182fe8e35',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 7,
            'ContractTemplateID',
            'Contract Template ID',
            'The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '21C7D64A-28F3-4535-819A-E0DD384A5580',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8ac97591-0971-45d9-82e9-6bbae6ececd3' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CreatingEntityID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8ac97591-0971-45d9-82e9-6bbae6ececd3',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 8,
            'CreatingEntityID',
            'Creating Entity ID',
            'Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to ${mjSchema}.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'E0238F34-2837-EF11-86D4-6045BDEE16E6',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2ed938e-b1d8-485b-b964-00cb44615977' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CreatingRecordID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e2ed938e-b1d8-485b-b964-00cb44615977',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 9,
            'CreatingRecordID',
            'Creating Record ID',
            'Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.',
            'nvarchar',
            900,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '433e610e-1199-4a89-a3be-23eee91bb6b3' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ParentContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '433e610e-1199-4a89-a3be-23eee91bb6b3',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 10,
            'ParentContractID',
            'Parent Contract ID',
            'The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fda34007-6e79-4a3d-ac5a-3813db33e863' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'SupersededByContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fda34007-6e79-4a3d-ac5a-3813db33e863',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 11,
            'SupersededByContractID',
            'Superseded By Contract ID',
            'The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fe229628-c86b-4319-aa97-c7dfe82a34fa' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'SigningProviderURL')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fe229628-c86b-4319-aa97-c7dfe82a34fa',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 12,
            'SigningProviderURL',
            'Signing Provider URL',
            'Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.',
            'nvarchar',
            2000,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '85c2054c-4939-415f-bcb1-a29385b881ad' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'EffectiveDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '85c2054c-4939-415f-bcb1-a29385b881ad',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 13,
            'EffectiveDate',
            'Effective Date',
            'When the agreement takes effect.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c24027f0-5986-4183-ac69-cdd31e60c934' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ExecutedDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c24027f0-5986-4183-ac69-cdd31e60c934',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 14,
            'ExecutedDate',
            'Executed Date',
            'When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '368a7e42-7c2c-41dd-8de8-dbd1ad2fc7a1' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'EndDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '368a7e42-7c2c-41dd-8de8-dbd1ad2fc7a1',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 15,
            'EndDate',
            'End Date',
            'When the current term ends. This is what drives the renewal watchlist and every expiry projection.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '390191a8-15ab-4ece-aebf-9de1beeda25d' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'TerminatedDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '390191a8-15ab-4ece-aebf-9de1beeda25d',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 16,
            'TerminatedDate',
            'Terminated Date',
            'When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '418fdbd3-daf6-45af-a89b-581e3921c2bd' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'AutoRenew')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '418fdbd3-daf6-45af-a89b-581e3921c2bd',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 17,
            'AutoRenew',
            'Auto Renew',
            'Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.',
            'bit',
            1,
            1,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '472d4155-f2b0-4b06-b6e7-2f58a90314e0' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'RenewalNoticeDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '472d4155-f2b0-4b06-b6e7-2f58a90314e0',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 18,
            'RenewalNoticeDays',
            'Renewal Notice Days',
            'Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fdee00c3-9a3b-4d05-a67c-d296289d9dbd' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CancellationWindowDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fdee00c3-9a3b-4d05-a67c-d296289d9dbd',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 19,
            'CancellationWindowDays',
            'Cancellation Window Days',
            'Days of notice the customer owes to cancel without renewing.',
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '547b4e55-e673-465f-b8d3-ca1286745190' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'AnnualIncreasePercent')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '547b4e55-e673-465f-b8d3-ca1286745190',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 20,
            'AnnualIncreasePercent',
            'Annual Increase Percent',
            'The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.',
            'decimal',
            5,
            7,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '629927e7-6f7a-43f3-81fa-cdecedfd62e5' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'HasModifications')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '629927e7-6f7a-43f3-81fa-cdecedfd62e5',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 21,
            'HasModifications',
            'Has Modifications',
            'Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.',
            'bit',
            1,
            1,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '88857639-49fe-4aa8-8581-b696375b159b' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '88857639-49fe-4aa8-8581-b696375b159b',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 22,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ce64dafd-b5fe-4eff-a70f-53072e819b84' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'Notes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ce64dafd-b5fe-4eff-a70f-53072e819b84',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 23,
            'Notes',
            'Notes',
            'Free-text working notes for whoever is processing the contract.',
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd2fb1812-df75-423a-911e-de5df46ff664' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd2fb1812-df75-423a-911e-de5df46ff664',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 24,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '324dd9b0-514c-4f1a-a1d0-69569f6e31d8' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '324dd9b0-514c-4f1a-a1d0-69569f6e31d8',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 25,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c8ba6c3a-441d-4413-b663-019c586f31fe' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c8ba6c3a-441d-4413-b663-019c586f31fe',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0e90c2b4-35ea-4baf-8e1d-3b84c2ac04ef' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0e90c2b4-35ea-4baf-8e1d-3b84c2ac04ef',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 2,
            'Name',
            'Name',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0a73a8b4-bf4c-41e2-8519-c796bab1d4be' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0a73a8b4-bf4c-41e2-8519-c796bab1d4be',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 3,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ab630039-0c2b-48aa-bb8e-8462cf310418' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ab630039-0c2b-48aa-bb8e-8462cf310418',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 4,
            'Status',
            'Status',
            'Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.',
            'nvarchar',
            20,
            0,
            0,
            0,
            'Active',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '90811d6b-1399-4560-976e-61b1b508eb39' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '90811d6b-1399-4560-976e-61b1b508eb39',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 5,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7c15e29a-c176-4945-bd90-335f51d442e5' OR (EntityID = '8D50B054-0E15-48C2-907A-BA598E28EA25' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7c15e29a-c176-4945-bd90-335f51d442e5',
            '8D50B054-0E15-48C2-907A-BA598E28EA25', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25') + 6,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9f76a3fc-f70d-4299-8a95-51f210c2d0c7' OR (EntityID = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9f76a3fc-f70d-4299-8a95-51f210c2d0c7',
            '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7') + 1,
            'ID',
            'ID',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8abc07ae-5b21-4e8e-a8f5-8ca85c4a1086' OR (EntityID = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7' AND Name = 'NextSequenceNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8abc07ae-5b21-4e8e-a8f5-8ca85c4a1086',
            '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7') + 2,
            'NextSequenceNumber',
            'Next Sequence Number',
            'The next number to hand out. Advanced server-side by ContractEntityServer.Save().',
            'int',
            4,
            10,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '666c1337-41c4-4e43-9e14-7fb95213f703' OR (EntityID = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '666c1337-41c4-4e43-9e14-7fb95213f703',
            '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7') + 3,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd047bbd2-777b-49d8-9396-7327c80e6697' OR (EntityID = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd047bbd2-777b-49d8-9396-7327c80e6697',
            '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7') + 4,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '66a5d587-22a3-4067-9952-130a308424ac' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '66a5d587-22a3-4067-9952-130a308424ac',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 1,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c3469c04-ae31-47a4-a208-8bc2e1c8b227' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c3469c04-ae31-47a4-a208-8bc2e1c8b227',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 2,
            'Name',
            'Name',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a243f09c-98f4-4ac3-8319-50505000c0c4' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'ContractTemplateTypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a243f09c-98f4-4ac3-8319-50505000c0c4',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 3,
            'ContractTemplateTypeID',
            'Contract Template Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '8D50B054-0E15-48C2-907A-BA598E28EA25',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2e50007b-b763-4d1d-80b3-979e5530ed89' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'VersionLabel')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2e50007b-b763-4d1d-80b3-979e5530ed89',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 4,
            'VersionLabel',
            'Version Label',
            'The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.',
            'nvarchar',
            100,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0e75c05a-3ac9-4e05-a559-cda0d1b2dc46' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'IntroducedDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0e75c05a-3ac9-4e05-a559-cda0d1b2dc46',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 5,
            'IntroducedDate',
            'Introduced Date',
            'When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '76cebf85-736b-485a-8b3e-cfbe6f91d266' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'SourceURL')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '76cebf85-736b-485a-8b3e-cfbe6f91d266',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 6,
            'SourceURL',
            'Source URL',
            'The dated public URL. NOT NULL — every template we have is a published URL and it is what the executed PDF cites; a template nobody can open is not a record of anything.',
            'nvarchar',
            2000,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '90bfa9ba-7a5a-4aa2-b33e-254cc4cde43b' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '90bfa9ba-7a5a-4aa2-b33e-254cc4cde43b',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 7,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0326bef3-855a-443b-a0a2-3749030c99e5' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0326bef3-855a-443b-a0a2-3749030c99e5',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 8,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0595ead0-a56c-4222-8e37-86677705e3e4' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0595ead0-a56c-4222-8e37-86677705e3e4',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 9,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to insert entity field value with ID 57341624-eaad-4d34-b3ce-6b191459b12c */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('57341624-eaad-4d34-b3ce-6b191459b12c', 'AB630039-0C2B-48AA-BB8E-8462CF310418', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID e0409adc-37e5-40b4-9710-a300512766a0 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('e0409adc-37e5-40b4-9710-a300512766a0', 'AB630039-0C2B-48AA-BB8E-8462CF310418', 2, 'Inactive', 'Inactive', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID AB630039-0C2B-48AA-BB8E-8462CF310418 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='AB630039-0C2B-48AA-BB8E-8462CF310418';

/* SQL text to insert entity field value with ID b31fc797-3a3c-4b08-b688-04a8be9a2754 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b31fc797-3a3c-4b08-b688-04a8be9a2754', '9A369D85-8C82-4399-885D-837575E37F3C', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 8a731007-02e7-4d68-9364-4bb355abba9f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('8a731007-02e7-4d68-9364-4bb355abba9f', '9A369D85-8C82-4399-885D-837575E37F3C', 2, 'Inactive', 'Inactive', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 9A369D85-8C82-4399-885D-837575E37F3C */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='9A369D85-8C82-4399-885D-837575E37F3C';


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Types -> MJ_BizApps_Contracts: Contracts (One To Many via ContractTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '92121cc1-6622-40e5-b038-2c713d64b9c3'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('92121cc1-6622-40e5-b038-2c713d64b9c3', 'EBB3F628-267E-44D6-8F18-258AC28FF981', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'ContractTypeID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Companies -> MJ_BizApps_Contracts: Contracts (One To Many via CompanyID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'c84e82fe-8f43-417d-8d35-9e52a7a65c88'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('c84e82fe-8f43-417d-8d35-9e52a7a65c88', 'D4238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'CompanyID', 'One To Many', 1, 1, 27, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Entities -> MJ_BizApps_Contracts: Contracts (One To Many via CreatingEntityID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'fccd3d5b-0519-4471-8d90-60d6f729a086'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('fccd3d5b-0519-4471-8d90-60d6f729a086', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'CreatingEntityID', 'One To Many', 1, 1, 82, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: Organizations -> MJ_BizApps_Contracts: Contracts (One To Many via CustomerOrganizationID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'c71f6281-b3eb-4d61-99df-bf618d8bd83e'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('c71f6281-b3eb-4d61-99df-bf618d8bd83e', 'C70448F9-9792-41D7-A82C-784B66429D54', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'CustomerOrganizationID', 'One To Many', 1, 1, 17, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Template Provisions -> MJ_BizApps_Contracts: Contract Template Modifications (One To Many via ContractTemplateProvisionID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '702b4ad3-4436-42b3-abac-2aa3686bb8c7'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('702b4ad3-4436-42b3-abac-2aa3686bb8c7', '27A600CA-6A2E-4C85-84AE-924183EC1681', '2E611A7D-2FBB-4A45-A9C8-103834BF026A', 'ContractTemplateProvisionID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via SupersededByContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'e6d3a47f-bf2b-4364-b3b8-dc84e4b0f5f7'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('e6d3a47f-bf2b-4364-b3b8-dc84e4b0f5f7', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'SupersededByContractID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via ParentContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '5e7929bb-a959-4633-92e7-5b97732851a0'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('5e7929bb-a959-4633-92e7-5b97732851a0', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'ParentContractID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Template Modifications (One To Many via ContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '16f4ff6d-d41b-4c33-a696-b3caae484474'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('16f4ff6d-d41b-4c33-a696-b3caae484474', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', '2E611A7D-2FBB-4A45-A9C8-103834BF026A', 'ContractID', 'One To Many', 1, 1, 3, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Template Types -> MJ_BizApps_Contracts: Contract Templates (One To Many via ContractTemplateTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '687f1d71-7131-4a77-ab45-0ca5e6a7793b'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('687f1d71-7131-4a77-ab45-0ca5e6a7793b', '8D50B054-0E15-48C2-907A-BA598E28EA25', '21C7D64A-28F3-4535-819A-E0DD384A5580', 'ContractTemplateTypeID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: People -> MJ_BizApps_Contracts: Contracts (One To Many via PrimaryContactPersonID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '6e520337-5c18-455e-bd7e-a89af2cbb5d3'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('6e520337-5c18-455e-bd7e-a89af2cbb5d3', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'PrimaryContactPersonID', 'One To Many', 1, 1, 21, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Templates -> MJ_BizApps_Contracts: Contracts (One To Many via ContractTemplateID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '87dbd38b-29b9-48a3-b429-4375a0e2eaf9'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('87dbd38b-29b9-48a3-b429-4375a0e2eaf9', '21C7D64A-28F3-4535-819A-E0DD384A5580', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'ContractTemplateID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Templates -> MJ_BizApps_Contracts: Contract Template Provisions (One To Many via ContractTemplateID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '1a3d0133-d2d0-4302-9ba8-24e6fbdeb583'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('1a3d0133-d2d0-4302-9ba8-24e6fbdeb583', '21C7D64A-28F3-4535-819A-E0DD384A5580', '27A600CA-6A2E-4C85-84AE-924183EC1681', 'ContractTemplateID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* Index for Foreign Keys for ContractSequence */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

/* Index for Foreign Keys for ContractTemplateModification */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractID in table ContractTemplateModification
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTemplateModification_ContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateModification]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTemplateModification_ContractID ON [${flyway:defaultSchema}].[ContractTemplateModification] ([ContractID]);

-- Index for foreign key ContractTemplateProvisionID in table ContractTemplateModification
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTemplateModification_ContractTemplateProvisionID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateModification]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTemplateModification_ContractTemplateProvisionID ON [${flyway:defaultSchema}].[ContractTemplateModification] ([ContractTemplateProvisionID]);

/* Index for Foreign Keys for ContractTemplateProvision */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTemplateID in table ContractTemplateProvision
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTemplateProvision_ContractTemplateID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateProvision]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTemplateProvision_ContractTemplateID ON [${flyway:defaultSchema}].[ContractTemplateProvision] ([ContractTemplateID]);

/* SQL text to update entity field related entity name field map for entity field ID B17D0F3B-300E-4C9B-B466-7DFCB5612EC3 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='B17D0F3B-300E-4C9B-B466-7DFCB5612EC3', @RelatedEntityNameFieldMap='ContractTemplate';

/* Index for Foreign Keys for ContractTemplateType */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

/* Index for Foreign Keys for ContractTemplate */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTemplateTypeID in table ContractTemplate
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTemplate_ContractTemplateTypeID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplate]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTemplate_ContractTemplateTypeID ON [${flyway:defaultSchema}].[ContractTemplate] ([ContractTemplateTypeID]);

/* SQL text to update entity field related entity name field map for entity field ID A243F09C-98F4-4AC3-8319-50505000C0C4 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='A243F09C-98F4-4AC3-8319-50505000C0C4', @RelatedEntityNameFieldMap='ContractTemplateType';

/* Base View SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: vwContractSequences
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Sequences
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractSequence
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractSequences]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractSequences];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractSequences]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractSequence] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractSequences] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: Permissions for vwContractSequences
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractSequences] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spCreateContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractSequence]
    @ID int = NULL,
    @NextSequenceNumber int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO
    [${flyway:defaultSchema}].[ContractSequence]
        (
            [NextSequenceNumber],
                [ID]
        )
    VALUES
        (
            ISNULL(@NextSequenceNumber, 1),
                @ID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractSequences] WHERE [ID] = @ID
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spUpdateContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractSequence]
    @ID int,
    @NextSequenceNumber int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractSequence]
    SET
        [NextSequenceNumber] = ISNULL(@NextSequenceNumber, [NextSequenceNumber])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractSequences] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractSequences]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractSequence] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractSequence table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractSequence]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractSequence];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractSequence
ON [${flyway:defaultSchema}].[ContractSequence]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractSequence]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractSequence] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: vwContractTemplateModifications
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Modifications
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractTemplateModification
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplateModifications]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTemplateModifications];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTemplateModifications]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractTemplateModification] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateModifications] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Permissions for vwContractTemplateModifications
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateModifications] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spCreateContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractTemplateModification]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateModification];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateModification]
    @ID uniqueidentifier = NULL,
    @ContractID uniqueidentifier,
    @ContractTemplateProvisionID uniqueidentifier,
    @ModificationText_Clear bit = 0,
    @ModificationText nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateModification]
            (
                [ID],
                [ContractID],
                [ContractTemplateProvisionID],
                [ModificationText],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractID,
                @ContractTemplateProvisionID,
                CASE WHEN @ModificationText_Clear = 1 THEN NULL ELSE ISNULL(@ModificationText, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateModification]
            (
                [ContractID],
                [ContractTemplateProvisionID],
                [ModificationText],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractID,
                @ContractTemplateProvisionID,
                CASE WHEN @ModificationText_Clear = 1 THEN NULL ELSE ISNULL(@ModificationText, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTemplateModifications] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateModification] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Template Modifications */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateModification] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spUpdateContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateModification]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateModification];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateModification]
    @ID uniqueidentifier,
    @ContractID uniqueidentifier = NULL,
    @ContractTemplateProvisionID uniqueidentifier = NULL,
    @ModificationText_Clear bit = 0,
    @ModificationText nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateModification]
    SET
        [ContractID] = ISNULL(@ContractID, [ContractID]),
        [ContractTemplateProvisionID] = ISNULL(@ContractTemplateProvisionID, [ContractTemplateProvisionID]),
        [ModificationText] = CASE WHEN @ModificationText_Clear = 1 THEN NULL ELSE ISNULL(@ModificationText, [ModificationText]) END,
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateModifications] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateModifications]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateModification] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateModification table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateModification]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateModification];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateModification
ON [${flyway:defaultSchema}].[ContractTemplateModification]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateModification]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractTemplateModification] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Template Modifications */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateModification] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Template Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: vwContractTemplateTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Types
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractTemplateType
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplateTypes]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTemplateTypes];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTemplateTypes]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractTemplateType] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Template Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: Permissions for vwContractTemplateTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Template Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spCreateContractTemplateType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTemplateType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractTemplateType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateType]
    @ID uniqueidentifier = NULL,
    @Name nvarchar(100),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateType]
            (
                [ID],
                [Name],
                [Description],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Active')
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateType]
            (
                [Name],
                [Description],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Active')
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTemplateTypes] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateType] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Template Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateType] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Template Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spUpdateContractTemplateType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateType]
    @ID uniqueidentifier,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateType]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Status] = ISNULL(@Status, [Status])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateTypes] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateTypes]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateType] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateType table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateType]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateType];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateType
ON [${flyway:defaultSchema}].[ContractTemplateType]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateType]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractTemplateType] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Template Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateType] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spDeleteContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractSequence]
    @ID int
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractSequence]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spDeleteContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractTemplateModification]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateModification];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateModification]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractTemplateModification]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateModification] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Template Modifications */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateModification] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Template Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spDeleteContractTemplateType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTemplateType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractTemplateType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateType]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractTemplateType]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateType] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Template Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateType] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Template Provisions */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: vwContractTemplateProvisions
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Provisions
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractTemplateProvision
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplateProvisions]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTemplateProvisions];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTemplateProvisions]
AS
SELECT
    c.*,
    mjBizAppsContractsContractTemplate_ContractTemplateID.[Name] AS [ContractTemplate]
FROM
    [${flyway:defaultSchema}].[ContractTemplateProvision] AS c
INNER JOIN
    [${flyway:defaultSchema}].[ContractTemplate] AS mjBizAppsContractsContractTemplate_ContractTemplateID
  ON
    [c].[ContractTemplateID] = mjBizAppsContractsContractTemplate_ContractTemplateID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateProvisions] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Template Provisions */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: Permissions for vwContractTemplateProvisions
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplateProvisions] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Template Provisions */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spCreateContractTemplateProvision
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTemplateProvision
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractTemplateProvision]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateProvision];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplateProvision]
    @ID uniqueidentifier = NULL,
    @ContractTemplateID uniqueidentifier,
    @ProvisionNumber nvarchar(20),
    @Title nvarchar(200),
    @ProvisionText_Clear bit = 0,
    @ProvisionText nvarchar(MAX) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Sequence int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateProvision]
            (
                [ID],
                [ContractTemplateID],
                [ProvisionNumber],
                [Title],
                [ProvisionText],
                [Description],
                [Sequence]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTemplateID,
                @ProvisionNumber,
                @Title,
                CASE WHEN @ProvisionText_Clear = 1 THEN NULL ELSE ISNULL(@ProvisionText, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Sequence, 0)
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplateProvision]
            (
                [ContractTemplateID],
                [ProvisionNumber],
                [Title],
                [ProvisionText],
                [Description],
                [Sequence]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTemplateID,
                @ProvisionNumber,
                @Title,
                CASE WHEN @ProvisionText_Clear = 1 THEN NULL ELSE ISNULL(@ProvisionText, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Sequence, 0)
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTemplateProvisions] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Template Provisions */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Template Provisions */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spUpdateContractTemplateProvision
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateProvision
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateProvision]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateProvision];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateProvision]
    @ID uniqueidentifier,
    @ContractTemplateID uniqueidentifier = NULL,
    @ProvisionNumber nvarchar(20) = NULL,
    @Title nvarchar(200) = NULL,
    @ProvisionText_Clear bit = 0,
    @ProvisionText nvarchar(MAX) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Sequence int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateProvision]
    SET
        [ContractTemplateID] = ISNULL(@ContractTemplateID, [ContractTemplateID]),
        [ProvisionNumber] = ISNULL(@ProvisionNumber, [ProvisionNumber]),
        [Title] = ISNULL(@Title, [Title]),
        [ProvisionText] = CASE WHEN @ProvisionText_Clear = 1 THEN NULL ELSE ISNULL(@ProvisionText, [ProvisionText]) END,
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Sequence] = ISNULL(@Sequence, [Sequence])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateProvisions] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateProvisions]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateProvision table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateProvision]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateProvision];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateProvision
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateProvision]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractTemplateProvision] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Template Provisions */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Template Provisions */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spDeleteContractTemplateProvision
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTemplateProvision
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractTemplateProvision]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateProvision];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplateProvision]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractTemplateProvision]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Template Provisions */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: vwContractTemplates
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Templates
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractTemplate
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplates]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTemplates];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTemplates]
AS
SELECT
    c.*,
    mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[Name] AS [ContractTemplateType]
FROM
    [${flyway:defaultSchema}].[ContractTemplate] AS c
INNER JOIN
    [${flyway:defaultSchema}].[ContractTemplateType] AS mjBizAppsContractsContractTemplateType_ContractTemplateTypeID
  ON
    [c].[ContractTemplateTypeID] = mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplates] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Permissions for vwContractTemplates
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplates] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spCreateContractTemplate
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTemplate
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractTemplate]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplate];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractTemplate]
    @ID uniqueidentifier = NULL,
    @Name nvarchar(200),
    @ContractTemplateTypeID uniqueidentifier,
    @VersionLabel_Clear bit = 0,
    @VersionLabel nvarchar(50) = NULL,
    @IntroducedDate_Clear bit = 0,
    @IntroducedDate date = NULL,
    @SourceURL nvarchar(1000),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplate]
            (
                [ID],
                [Name],
                [ContractTemplateTypeID],
                [VersionLabel],
                [IntroducedDate],
                [SourceURL],
                [Description]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                @ContractTemplateTypeID,
                CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, NULL) END,
                CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, NULL) END,
                @SourceURL,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractTemplate]
            (
                [Name],
                [ContractTemplateTypeID],
                [VersionLabel],
                [IntroducedDate],
                [SourceURL],
                [Description]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                @ContractTemplateTypeID,
                CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, NULL) END,
                CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, NULL) END,
                @SourceURL,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTemplates] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplate] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Templates */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTemplate] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spUpdateContractTemplate
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplate
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplate]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplate];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplate]
    @ID uniqueidentifier,
    @Name nvarchar(200) = NULL,
    @ContractTemplateTypeID uniqueidentifier = NULL,
    @VersionLabel_Clear bit = 0,
    @VersionLabel nvarchar(50) = NULL,
    @IntroducedDate_Clear bit = 0,
    @IntroducedDate date = NULL,
    @SourceURL nvarchar(1000) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplate]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [ContractTemplateTypeID] = ISNULL(@ContractTemplateTypeID, [ContractTemplateTypeID]),
        [VersionLabel] = CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, [VersionLabel]) END,
        [IntroducedDate] = CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, [IntroducedDate]) END,
        [SourceURL] = ISNULL(@SourceURL, [SourceURL]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplates] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplates]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplate] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplate table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplate]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplate];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplate
ON [${flyway:defaultSchema}].[ContractTemplate]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplate]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractTemplate] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Templates */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplate] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spDeleteContractTemplate
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTemplate
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractTemplate]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplate];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTemplate]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractTemplate]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplate] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Templates */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTemplate] TO [cdp_Developer], [cdp_Integration];

/* Index for Foreign Keys for ContractType */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

/* Index for Foreign Keys for Contract */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTypeID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_ContractTypeID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_ContractTypeID ON [${flyway:defaultSchema}].[Contract] ([ContractTypeID]);

-- Index for foreign key CompanyID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CompanyID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CompanyID ON [${flyway:defaultSchema}].[Contract] ([CompanyID]);

-- Index for foreign key CustomerOrganizationID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CustomerOrganizationID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CustomerOrganizationID ON [${flyway:defaultSchema}].[Contract] ([CustomerOrganizationID]);

-- Index for foreign key PrimaryContactPersonID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_PrimaryContactPersonID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_PrimaryContactPersonID ON [${flyway:defaultSchema}].[Contract] ([PrimaryContactPersonID]);

-- Index for foreign key ContractTemplateID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_ContractTemplateID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_ContractTemplateID ON [${flyway:defaultSchema}].[Contract] ([ContractTemplateID]);

-- Index for foreign key CreatingEntityID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CreatingEntityID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CreatingEntityID ON [${flyway:defaultSchema}].[Contract] ([CreatingEntityID]);

-- Index for foreign key ParentContractID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_ParentContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_ParentContractID ON [${flyway:defaultSchema}].[Contract] ([ParentContractID]);

-- Index for foreign key SupersededByContractID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_SupersededByContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_SupersededByContractID ON [${flyway:defaultSchema}].[Contract] ([SupersededByContractID]);

/* SQL text to update entity field related entity name field map for entity field ID D4C3BE29-B422-41A9-8678-D14A5F43C47D */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='D4C3BE29-B422-41A9-8678-D14A5F43C47D', @RelatedEntityNameFieldMap='ContractType';

/* Base View SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: vwContractTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Types
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractType
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTypes]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTypes];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTypes]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractType] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Permissions for vwContractTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spCreateContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractType]
    @ID uniqueidentifier = NULL,
    @Name nvarchar(100),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @RequiresExecutedDocument bit = NULL,
    @Status nvarchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractType]
            (
                [ID],
                [Name],
                [Description],
                [RequiresExecutedDocument],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active')
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractType]
            (
                [Name],
                [Description],
                [RequiresExecutedDocument],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active')
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spUpdateContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType]
    @ID uniqueidentifier,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @RequiresExecutedDocument bit = NULL,
    @Status nvarchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [RequiresExecutedDocument] = ISNULL(@RequiresExecutedDocument, [RequiresExecutedDocument]),
        [Status] = ISNULL(@Status, [Status])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTypes]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractType table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractType]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractType];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractType
ON [${flyway:defaultSchema}].[ContractType]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractType] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spDeleteContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractType]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractType]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

/* SQL text to update entity field related entity name field map for entity field ID 03540125-572C-432B-8E73-2C568464B563 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='03540125-572C-432B-8E73-2C568464B563', @RelatedEntityNameFieldMap='Company';

/* SQL text to update entity field related entity name field map for entity field ID 8CF73C13-3CDE-4175-A5FF-F8E361476946 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='8CF73C13-3CDE-4175-A5FF-F8E361476946', @RelatedEntityNameFieldMap='CustomerOrganization';

/* SQL text to update entity field related entity name field map for entity field ID BDC1ADE5-D9C2-4405-9785-DAB3818BB0CD */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='BDC1ADE5-D9C2-4405-9785-DAB3818BB0CD', @RelatedEntityNameFieldMap='PrimaryContactPerson';

/* SQL text to update entity field related entity name field map for entity field ID 49623009-21AD-45E6-9B40-CB4182FE8E35 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='49623009-21AD-45E6-9B40-CB4182FE8E35', @RelatedEntityNameFieldMap='ContractTemplate';

/* SQL text to update entity field related entity name field map for entity field ID 8AC97591-0971-45D9-82E9-6BBAE6ECECD3 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='8AC97591-0971-45D9-82E9-6BBAE6ECECD3', @RelatedEntityNameFieldMap='CreatingEntity';

/* Root ID Function SQL for MJ_BizApps_Contracts: Contracts.ParentContractID */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: fnContractParentContractID_GetRootID
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
------------------------------------------------------------
----- ROOT ID FUNCTION FOR: [Contract].[ParentContractID]
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]', 'IF') IS NOT NULL
    DROP FUNCTION [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID];
GO

CREATE FUNCTION [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]
(
    @RecordID uniqueidentifier,
    @ParentID uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    WITH CTE_RootParent AS (
        SELECT
            [ID],
            [ParentContractID],
            [ID] AS [RootParentID],
            0 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract]
        WHERE
            [ID] = COALESCE(@ParentID, @RecordID)

        UNION ALL

        SELECT
            c.[ID],
            c.[ParentContractID],
            c.[ID] AS [RootParentID],
            p.[Depth] + 1 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract] c
        INNER JOIN
            CTE_RootParent p ON c.[ID] = p.[ParentContractID]
        WHERE
            p.[Depth] < 100
    )
    SELECT TOP 1
        [RootParentID] AS RootID
    FROM
        CTE_RootParent
    WHERE
        [ParentContractID] IS NULL
    ORDER BY
        [RootParentID]
);
GO

/* Root ID Function SQL for MJ_BizApps_Contracts: Contracts.SupersededByContractID */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: fnContractSupersededByContractID_GetRootID
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
------------------------------------------------------------
----- ROOT ID FUNCTION FOR: [Contract].[SupersededByContractID]
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]', 'IF') IS NOT NULL
    DROP FUNCTION [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID];
GO

CREATE FUNCTION [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]
(
    @RecordID uniqueidentifier,
    @ParentID uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    WITH CTE_RootParent AS (
        SELECT
            [ID],
            [SupersededByContractID],
            [ID] AS [RootParentID],
            0 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract]
        WHERE
            [ID] = COALESCE(@ParentID, @RecordID)

        UNION ALL

        SELECT
            c.[ID],
            c.[SupersededByContractID],
            c.[ID] AS [RootParentID],
            p.[Depth] + 1 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract] c
        INNER JOIN
            CTE_RootParent p ON c.[ID] = p.[SupersededByContractID]
        WHERE
            p.[Depth] < 100
    )
    SELECT TOP 1
        [RootParentID] AS RootID
    FROM
        CTE_RootParent
    WHERE
        [SupersededByContractID] IS NULL
    ORDER BY
        [RootParentID]
);
GO

/* Base View SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: vwContracts
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contracts
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  Contract
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContracts];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContracts]
AS
SELECT
    c.*,
    mjBizAppsContractsContractType_ContractTypeID.[Name] AS [ContractType],
    MJCompany_CompanyID.[Name] AS [Company],
    mjBizAppsCommonOrganization_CustomerOrganizationID.[Name] AS [CustomerOrganization],
    mjBizAppsCommonPerson_PrimaryContactPersonID.[FirstName] AS [PrimaryContactPerson],
    mjBizAppsContractsContractTemplate_ContractTemplateID.[Name] AS [ContractTemplate],
    MJEntity_CreatingEntityID.[Name] AS [CreatingEntity],
    root_ParentContractID.RootID AS [RootParentContractID],
    root_SupersededByContractID.RootID AS [RootSupersededByContractID]
FROM
    [${flyway:defaultSchema}].[Contract] AS c
INNER JOIN
    [${flyway:defaultSchema}].[ContractType] AS mjBizAppsContractsContractType_ContractTypeID
  ON
    [c].[ContractTypeID] = mjBizAppsContractsContractType_ContractTypeID.[ID]
INNER JOIN
    [${mjSchema}].[Company] AS MJCompany_CompanyID
  ON
    [c].[CompanyID] = MJCompany_CompanyID.[ID]
INNER JOIN
    [${mjSchema}_BizAppsCommon].[Organization] AS mjBizAppsCommonOrganization_CustomerOrganizationID
  ON
    [c].[CustomerOrganizationID] = mjBizAppsCommonOrganization_CustomerOrganizationID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsCommon].[Person] AS mjBizAppsCommonPerson_PrimaryContactPersonID
  ON
    [c].[PrimaryContactPersonID] = mjBizAppsCommonPerson_PrimaryContactPersonID.[ID]
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[ContractTemplate] AS mjBizAppsContractsContractTemplate_ContractTemplateID
  ON
    [c].[ContractTemplateID] = mjBizAppsContractsContractTemplate_ContractTemplateID.[ID]
LEFT OUTER JOIN
    [${mjSchema}].[Entity] AS MJEntity_CreatingEntityID
  ON
    [c].[CreatingEntityID] = MJEntity_CreatingEntityID.[ID]
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]([c].[ID], [c].[ParentContractID]) AS root_ParentContractID
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]([c].[ID], [c].[SupersededByContractID]) AS root_SupersededByContractID
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spCreateContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContract]
    @ID uniqueidentifier = NULL,
    @ContractNumber nvarchar(50),
    @ContractTypeID uniqueidentifier,
    @CompanyID uniqueidentifier,
    @CustomerOrganizationID uniqueidentifier,
    @PrimaryContactPersonID_Clear bit = 0,
    @PrimaryContactPersonID uniqueidentifier = NULL,
    @ContractTemplateID_Clear bit = 0,
    @ContractTemplateID uniqueidentifier = NULL,
    @CreatingEntityID_Clear bit = 0,
    @CreatingEntityID uniqueidentifier = NULL,
    @CreatingRecordID_Clear bit = 0,
    @CreatingRecordID nvarchar(450) = NULL,
    @ParentContractID_Clear bit = 0,
    @ParentContractID uniqueidentifier = NULL,
    @SupersededByContractID_Clear bit = 0,
    @SupersededByContractID uniqueidentifier = NULL,
    @SigningProviderURL_Clear bit = 0,
    @SigningProviderURL nvarchar(1000) = NULL,
    @EffectiveDate_Clear bit = 0,
    @EffectiveDate date = NULL,
    @ExecutedDate_Clear bit = 0,
    @ExecutedDate date = NULL,
    @EndDate_Clear bit = 0,
    @EndDate date = NULL,
    @TerminatedDate_Clear bit = 0,
    @TerminatedDate date = NULL,
    @AutoRenew bit = NULL,
    @RenewalNoticeDays_Clear bit = 0,
    @RenewalNoticeDays int = NULL,
    @CancellationWindowDays_Clear bit = 0,
    @CancellationWindowDays int = NULL,
    @AnnualIncreasePercent_Clear bit = 0,
    @AnnualIncreasePercent decimal(7, 4) = NULL,
    @HasModifications bit = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[Contract]
            (
                [ID],
                [ContractNumber],
                [ContractTypeID],
                [CompanyID],
                [CustomerOrganizationID],
                [PrimaryContactPersonID],
                [ContractTemplateID],
                [CreatingEntityID],
                [CreatingRecordID],
                [ParentContractID],
                [SupersededByContractID],
                [SigningProviderURL],
                [EffectiveDate],
                [ExecutedDate],
                [EndDate],
                [TerminatedDate],
                [AutoRenew],
                [RenewalNoticeDays],
                [CancellationWindowDays],
                [AnnualIncreasePercent],
                [HasModifications],
                [Description],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractNumber,
                @ContractTypeID,
                @CompanyID,
                @CustomerOrganizationID,
                CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, NULL) END,
                CASE WHEN @ContractTemplateID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateID, NULL) END,
                CASE WHEN @CreatingEntityID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingEntityID, NULL) END,
                CASE WHEN @CreatingRecordID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingRecordID, NULL) END,
                CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, NULL) END,
                CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, NULL) END,
                CASE WHEN @SigningProviderURL_Clear = 1 THEN NULL ELSE ISNULL(@SigningProviderURL, NULL) END,
                CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, NULL) END,
                CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, NULL) END,
                CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, NULL) END,
                CASE WHEN @TerminatedDate_Clear = 1 THEN NULL ELSE ISNULL(@TerminatedDate, NULL) END,
                ISNULL(@AutoRenew, 0),
                CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, NULL) END,
                CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, NULL) END,
                CASE WHEN @AnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@AnnualIncreasePercent, NULL) END,
                ISNULL(@HasModifications, 0),
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[Contract]
            (
                [ContractNumber],
                [ContractTypeID],
                [CompanyID],
                [CustomerOrganizationID],
                [PrimaryContactPersonID],
                [ContractTemplateID],
                [CreatingEntityID],
                [CreatingRecordID],
                [ParentContractID],
                [SupersededByContractID],
                [SigningProviderURL],
                [EffectiveDate],
                [ExecutedDate],
                [EndDate],
                [TerminatedDate],
                [AutoRenew],
                [RenewalNoticeDays],
                [CancellationWindowDays],
                [AnnualIncreasePercent],
                [HasModifications],
                [Description],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractNumber,
                @ContractTypeID,
                @CompanyID,
                @CustomerOrganizationID,
                CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, NULL) END,
                CASE WHEN @ContractTemplateID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateID, NULL) END,
                CASE WHEN @CreatingEntityID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingEntityID, NULL) END,
                CASE WHEN @CreatingRecordID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingRecordID, NULL) END,
                CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, NULL) END,
                CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, NULL) END,
                CASE WHEN @SigningProviderURL_Clear = 1 THEN NULL ELSE ISNULL(@SigningProviderURL, NULL) END,
                CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, NULL) END,
                CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, NULL) END,
                CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, NULL) END,
                CASE WHEN @TerminatedDate_Clear = 1 THEN NULL ELSE ISNULL(@TerminatedDate, NULL) END,
                ISNULL(@AutoRenew, 0),
                CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, NULL) END,
                CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, NULL) END,
                CASE WHEN @AnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@AnnualIncreasePercent, NULL) END,
                ISNULL(@HasModifications, 0),
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContracts] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spUpdateContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContract]
    @ID uniqueidentifier,
    @ContractNumber nvarchar(50) = NULL,
    @ContractTypeID uniqueidentifier = NULL,
    @CompanyID uniqueidentifier = NULL,
    @CustomerOrganizationID uniqueidentifier = NULL,
    @PrimaryContactPersonID_Clear bit = 0,
    @PrimaryContactPersonID uniqueidentifier = NULL,
    @ContractTemplateID_Clear bit = 0,
    @ContractTemplateID uniqueidentifier = NULL,
    @CreatingEntityID_Clear bit = 0,
    @CreatingEntityID uniqueidentifier = NULL,
    @CreatingRecordID_Clear bit = 0,
    @CreatingRecordID nvarchar(450) = NULL,
    @ParentContractID_Clear bit = 0,
    @ParentContractID uniqueidentifier = NULL,
    @SupersededByContractID_Clear bit = 0,
    @SupersededByContractID uniqueidentifier = NULL,
    @SigningProviderURL_Clear bit = 0,
    @SigningProviderURL nvarchar(1000) = NULL,
    @EffectiveDate_Clear bit = 0,
    @EffectiveDate date = NULL,
    @ExecutedDate_Clear bit = 0,
    @ExecutedDate date = NULL,
    @EndDate_Clear bit = 0,
    @EndDate date = NULL,
    @TerminatedDate_Clear bit = 0,
    @TerminatedDate date = NULL,
    @AutoRenew bit = NULL,
    @RenewalNoticeDays_Clear bit = 0,
    @RenewalNoticeDays int = NULL,
    @CancellationWindowDays_Clear bit = 0,
    @CancellationWindowDays int = NULL,
    @AnnualIncreasePercent_Clear bit = 0,
    @AnnualIncreasePercent decimal(7, 4) = NULL,
    @HasModifications bit = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[Contract]
    SET
        [ContractNumber] = ISNULL(@ContractNumber, [ContractNumber]),
        [ContractTypeID] = ISNULL(@ContractTypeID, [ContractTypeID]),
        [CompanyID] = ISNULL(@CompanyID, [CompanyID]),
        [CustomerOrganizationID] = ISNULL(@CustomerOrganizationID, [CustomerOrganizationID]),
        [PrimaryContactPersonID] = CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, [PrimaryContactPersonID]) END,
        [ContractTemplateID] = CASE WHEN @ContractTemplateID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateID, [ContractTemplateID]) END,
        [CreatingEntityID] = CASE WHEN @CreatingEntityID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingEntityID, [CreatingEntityID]) END,
        [CreatingRecordID] = CASE WHEN @CreatingRecordID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingRecordID, [CreatingRecordID]) END,
        [ParentContractID] = CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, [ParentContractID]) END,
        [SupersededByContractID] = CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, [SupersededByContractID]) END,
        [SigningProviderURL] = CASE WHEN @SigningProviderURL_Clear = 1 THEN NULL ELSE ISNULL(@SigningProviderURL, [SigningProviderURL]) END,
        [EffectiveDate] = CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, [EffectiveDate]) END,
        [ExecutedDate] = CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, [ExecutedDate]) END,
        [EndDate] = CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, [EndDate]) END,
        [TerminatedDate] = CASE WHEN @TerminatedDate_Clear = 1 THEN NULL ELSE ISNULL(@TerminatedDate, [TerminatedDate]) END,
        [AutoRenew] = ISNULL(@AutoRenew, [AutoRenew]),
        [RenewalNoticeDays] = CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, [RenewalNoticeDays]) END,
        [CancellationWindowDays] = CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, [CancellationWindowDays]) END,
        [AnnualIncreasePercent] = CASE WHEN @AnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@AnnualIncreasePercent, [AnnualIncreasePercent]) END,
        [HasModifications] = ISNULL(@HasModifications, [HasModifications]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContracts] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContracts]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the Contract table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContract]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContract];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContract
ON [${flyway:defaultSchema}].[Contract]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[Contract]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[Contract] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spDeleteContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContract]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[Contract]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* SQL text to delete unneeded entity fields (7 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks', @EntityIDs='8D50B054-0E15-48C2-907A-BA598E28EA25,21C7D64A-28F3-4535-819A-E0DD384A5580,27A600CA-6A2E-4C85-84AE-924183EC1681,EBB3F628-267E-44D6-8F18-258AC28FF981,96271F4A-AC8D-47C8-BB5D-C7180910B2C7,4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20,2E611A7D-2FBB-4A45-A9C8-103834BF026A';

/* SQL text to insert 10 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b557d486-b203-4c3f-baa5-28537687f51b' OR (EntityID = '27A600CA-6A2E-4C85-84AE-924183EC1681' AND Name = 'ContractTemplate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b557d486-b203-4c3f-baa5-28537687f51b',
            '27A600CA-6A2E-4C85-84AE-924183EC1681', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681') + 10,
            'ContractTemplate',
            'Contract Template',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ffc73e89-1843-4bdb-aa51-e086b19a6bf8' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ContractType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ffc73e89-1843-4bdb-aa51-e086b19a6bf8',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 26,
            'ContractType',
            'Contract Type',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ef543396-9a94-466a-bfb6-591f89b0056b' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'Company')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ef543396-9a94-466a-bfb6-591f89b0056b',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 27,
            'Company',
            'Company',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8de097b3-d81b-4579-a397-e7a77888b79a' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CustomerOrganization')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8de097b3-d81b-4579-a397-e7a77888b79a',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 28,
            'CustomerOrganization',
            'Customer Organization',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '13acf151-bd8b-4f43-bf50-36d83c7d3b76' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'PrimaryContactPerson')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '13acf151-bd8b-4f43-bf50-36d83c7d3b76',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 29,
            'PrimaryContactPerson',
            'Primary Contact Person',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd16fcb6b-fceb-46c7-8ae0-5ac08f9a930e' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ContractTemplate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd16fcb6b-fceb-46c7-8ae0-5ac08f9a930e',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 30,
            'ContractTemplate',
            'Contract Template',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'edf1cb45-eea0-4121-9fcc-52e4ee1f33ea' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'CreatingEntity')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'edf1cb45-eea0-4121-9fcc-52e4ee1f33ea',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 31,
            'CreatingEntity',
            'Creating Entity',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '15088b1b-6b7b-48de-8b16-e11b02623ab1' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'RootParentContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '15088b1b-6b7b-48de-8b16-e11b02623ab1',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 32,
            'RootParentContractID',
            'Root Parent Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '646c61dd-2a04-4397-8241-179e367ad2fe' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'RootSupersededByContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '646c61dd-2a04-4397-8241-179e367ad2fe',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 33,
            'RootSupersededByContractID',
            'Root Superseded By Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'eac5daca-e9e0-4884-b6fa-27534fd0624c' OR (EntityID = '21C7D64A-28F3-4535-819A-E0DD384A5580' AND Name = 'ContractTemplateType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'eac5daca-e9e0-4884-b6fa-27534fd0624c',
            '21C7D64A-28F3-4535-819A-E0DD384A5580', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580') + 10,
            'ContractTemplateType',
            'Contract Template Type',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema (7 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks', @EntityIDs='8D50B054-0E15-48C2-907A-BA598E28EA25,21C7D64A-28F3-4535-819A-E0DD384A5580,27A600CA-6A2E-4C85-84AE-924183EC1681,EBB3F628-267E-44D6-8F18-258AC28FF981,96271F4A-AC8D-47C8-BB5D-C7180910B2C7,4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20,2E611A7D-2FBB-4A45-A9C8-103834BF026A';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '9F76A3FC-F70D-4299-8A95-51F210C2D0C7'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8ABC07AE-5B21-4E8E-A8F5-8CA85C4A1086'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'AB630039-0C2B-48AA-BB8E-8462CF310418'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = '8D50B054-0E15-48C2-907A-BA598E28EA25'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '2E50007B-B763-4D1D-80B3-979E5530ED89'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '0E75C05A-3AC9-4E05-A559-CDA0D1B2DC46'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'EAC5DACA-E9E0-4884-B6FA-27534FD0624C'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = 'C3469C04-AE31-47A4-A208-8BC2E1C8B227'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = '8399A578-ADE9-4C82-A02C-8B7C8EFDACB8'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8399A578-ADE9-4C82-A02C-8B7C8EFDACB8'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'DCA6D2E5-A043-4407-9A1C-2AF676B06D7B'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '2278BCB3-6241-45B9-A353-858EC91FF45E'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '8399A578-ADE9-4C82-A02C-8B7C8EFDACB8'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = 'DCA6D2E5-A043-4407-9A1C-2AF676B06D7B'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = '8399A578-ADE9-4C82-A02C-8B7C8EFDACB8'
               AND AutoUpdateUserSearchPredicate = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = 'DCA6D2E5-A043-4407-9A1C-2AF676B06D7B'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '9D1ECADE-25C0-4A9C-912A-6B993C5AFD35'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '51331345-4AE4-4882-959A-6046CBBDDACE'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '9987B09C-FFFA-460C-9B86-F1692C1728AA'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set categories for 4 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Sequences.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9F76A3FC-F70D-4299-8A95-51F210C2D0C7' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Sequences.NextSequenceNumber 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Sequence Configuration',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8ABC07AE-5B21-4E8E-A8F5-8CA85C4A1086' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Sequences.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '666C1337-41C4-4E43-9E14-7FB95213F703' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Sequences.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D047BBD2-777B-49D8-9396-7327C80E6697' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-list-ol */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-list-ol', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('e9ff53f3-0b6e-434c-843f-4fc8748df995', '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', 'FieldCategoryInfo', '{"Sequence Configuration":{"icon":"fa fa-sort-numeric-up","description":"Configuration settings for managing automated sequence counters"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('a4e03c6a-27c4-4b81-b110-1171f2d44eab', '96271F4A-AC8D-47C8-BB5D-C7180910B2C7', 'FieldCategoryIcons', '{"Sequence Configuration":"fa fa-sort-numeric-up","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set categories for 6 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C8BA6C3A-441D-4413-B663-019C586F31FE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0E90C2B4-35EA-4BAF-8E1D-3B84C2AC04EF' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0A73A8B4-BF4C-41E2-8519-C796BAB1D4BE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'AB630039-0C2B-48AA-BB8E-8462CF310418' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '90811D6B-1399-4560-976E-61B1B508EB39' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '7C15E29A-C176-4945-BD90-335F51D442E5' AND AutoUpdateCategory = 1;

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 0, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '96271F4A-AC8D-47C8-BB5D-C7180910B2C7';

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '8D50B054-0E15-48C2-907A-BA598E28EA25';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('ce476d1b-f917-4617-83b5-470b02a01f29', '8D50B054-0E15-48C2-907A-BA598E28EA25', 'FieldCategoryInfo', '{"Template Details":{"icon":"fa fa-file-alt","description":"Information defining the contract template type, including name, description, and status."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('4c935056-c78d-42d0-9a92-14b9588f003c', '8D50B054-0E15-48C2-907A-BA598E28EA25', 'FieldCategoryIcons', '{"Template Details":"fa fa-file-alt","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 0, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '8D50B054-0E15-48C2-907A-BA598E28EA25';

/* Set categories for 7 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FD9C658F-66CE-43A1-AE3A-40DB31530608' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9D1ECADE-25C0-4A9C-912A-6B993C5AFD35' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractTemplateProvisionID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Template Provision',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '51331345-4AE4-4882-959A-6046CBBDDACE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ModificationText 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Modification Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8178CF5D-D3A4-4405-8FDA-90D79B627D55' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.Notes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Modification Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8DAB9C2D-48B0-4C25-8BD3-4DD74029D29A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C89C9AA4-4C51-4623-A042-F475C18B415A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9987B09C-FFFA-460C-9B86-F1692C1728AA' AND AutoUpdateCategory = 1;

/* Set categories for 10 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '66A5D587-22A3-4067-9952-130A308424AC' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C3469C04-AE31-47A4-A208-8BC2E1C8B227' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ContractTemplateTypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Template Type ID',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'A243F09C-98F4-4AC3-8319-50505000C0C4' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ContractTemplateType 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Template Type',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'EAC5DACA-E9E0-4884-B6FA-27534FD0624C' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.VersionLabel 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '2E50007B-B763-4D1D-80B3-979E5530ED89' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.IntroducedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0E75C05A-3AC9-4E05-A559-CDA0D1B2DC46' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.SourceURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = 'URL',
   CodeType = NULL
WHERE 
   ID = '76CEBF85-736B-485A-8B3E-CFBE6F91D266' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '90BFA9BA-7A5A-4AA2-B33E-254CC4CDE43B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0326BEF3-855A-443B-A0A2-3749030C99E5' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0595EAD0-A56C-4222-8E37-86677705E3E4' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('000d1197-98bc-4331-a368-24393e98ea67', '2E611A7D-2FBB-4A45-A9C8-103834BF026A', 'FieldCategoryInfo', '{"Contract Association":{"icon":"fa fa-link","description":"Links the modification to the parent contract and the specific template clause it replaces."},"Modification Details":{"icon":"fa fa-align-left","description":"The specific text changes and supporting negotiation notes for the contract."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('5c63b56a-5b1e-40da-857c-fea6e48ed4fd', '2E611A7D-2FBB-4A45-A9C8-103834BF026A', 'FieldCategoryIcons', '{"Contract Association":"fa fa-link","Modification Details":"fa fa-align-left","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '21C7D64A-28F3-4535-819A-E0DD384A5580';

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('26f1bacf-c033-458a-b4d1-3496648f48ae', '21C7D64A-28F3-4535-819A-E0DD384A5580', 'FieldCategoryInfo', '{"Template Details":{"icon":"fa fa-file-alt","description":"Core information about the contract template version, including type, versioning, and hosting URL."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('7bc2dcb2-f5fc-4ce4-aaf5-350f1cfa0ddd', '21C7D64A-28F3-4535-819A-E0DD384A5580', 'FieldCategoryIcons', '{"Template Details":"fa fa-file-alt","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '21C7D64A-28F3-4535-819A-E0DD384A5580';

/* Set categories for 10 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '03FAB201-6A05-4F84-A3F4-AD6DE9AA4A62' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ContractTemplateID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B17D0F3B-300E-4C9B-B466-7DFCB5612EC3' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ContractTemplate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B557D486-B203-4C3F-BAA5-28537687F51B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ProvisionNumber 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8399A578-ADE9-4C82-A02C-8B7C8EFDACB8' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.Title 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'DCA6D2E5-A043-4407-9A1C-2AF676B06D7B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ProvisionText 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Content',
   GeneratedFormSection = 'Category',
   ExtendedType = 'Code',
   CodeType = 'Other'
WHERE 
   ID = '73B20D56-83DD-4E73-BE91-D7FDA3CACB25' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Content',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '901D4A8E-91E0-4CDC-B072-98F78D8383EB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.Sequence 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '2278BCB3-6241-45B9-A353-858EC91FF45E' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0C64DB7B-30EE-4FFF-8EA8-51BF362D50D0' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'CF6F8B7C-9560-4770-B07B-32327C139C7F' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '27A600CA-6A2E-4C85-84AE-924183EC1681';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('4cfac1b8-0fe1-4571-9bcd-cbf3417818ca', '27A600CA-6A2E-4C85-84AE-924183EC1681', 'FieldCategoryInfo', '{"Template Association":{"icon":"fa fa-link","description":"Links identifying which contract template version this provision belongs to"},"Provision Details":{"icon":"fa fa-list-ol","description":"Identification, titling, and ordering of the contract clause"},"Provision Content":{"icon":"fa fa-align-left","description":"The actual legal text and supporting description of the provision"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('eed802f1-9d03-410e-97f9-8e26dbe8da05', '27A600CA-6A2E-4C85-84AE-924183EC1681', 'FieldCategoryIcons', '{"Template Association":"fa fa-link","Provision Details":"fa fa-list-ol","Provision Content":"fa fa-align-left","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '27A600CA-6A2E-4C85-84AE-924183EC1681';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8C5A7DE7-0ECF-42DD-A733-9B18BEC29C2B'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '9A369D85-8C82-4399-885D-837575E37F3C'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = 'EBB3F628-267E-44D6-8F18-258AC28FF981'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = '0DFE97CD-D90A-4B2C-9B9A-281E0FC10D7C'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '0DFE97CD-D90A-4B2C-9B9A-281E0FC10D7C'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '85C2054C-4939-415F-BCB1-A29385B881AD'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '368A7E42-7C2C-41DD-8DE8-DBD1AD2FC7A1'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'FFC73E89-1843-4BDB-AA51-E086B19A6BF8'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8DE097B3-D81B-4579-A397-E7A77888B79A'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '0DFE97CD-D90A-4B2C-9B9A-281E0FC10D7C'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = '0DFE97CD-D90A-4B2C-9B9A-281E0FC10D7C'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set categories for 7 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '05CFD8F7-B9CF-4A9C-83E4-D1A2D5AD5105' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '2C9E961B-6A55-4CE7-9A24-B7C3DFDCB2FF' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '238B5941-DC97-43F2-A464-4ED207DDA3FE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.RequiresExecutedDocument 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8C5A7DE7-0ECF-42DD-A733-9B18BEC29C2B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9A369D85-8C82-4399-885D-837575E37F3C' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '550A2932-55A8-496E-A3F2-84529AFEB12F' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C967E14D-7969-4060-A44B-7ED6783C67BD' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('567da4c1-ef45-4df9-9115-d9e39d147676', 'EBB3F628-267E-44D6-8F18-258AC28FF981', 'FieldCategoryInfo', '{"Contract Type Details":{"icon":"fa fa-file-contract","description":"Definition, business requirements, and operational status of contract types"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('8009a7aa-ef46-4d27-a461-d0029843f9a3', 'EBB3F628-267E-44D6-8F18-258AC28FF981', 'FieldCategoryIcons', '{"Contract Type Details":"fa fa-file-contract","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 0, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = 'EBB3F628-267E-44D6-8F18-258AC28FF981';

/* Set categories for 33 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '3509FDA6-F406-42DF-805A-A0A7028A2726' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractNumber 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0DFE97CD-D90A-4B2C-9B9A-281E0FC10D7C' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Type',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D4C3BE29-B422-41A9-8678-D14A5F43C47D' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractType 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Type Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FFC73E89-1843-4BDB-AA51-E086B19A6BF8' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CompanyID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Company',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '03540125-572C-432B-8E73-2C568464B563' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Company 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Company Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'EF543396-9A94-466A-BFB6-591F89B0056B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CustomerOrganizationID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Customer Organization',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8CF73C13-3CDE-4175-A5FF-F8E361476946' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CustomerOrganization 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Customer Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8DE097B3-D81B-4579-A397-E7A77888B79A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.PrimaryContactPersonID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Primary Contact',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'BDC1ADE5-D9C2-4405-9785-DAB3818BB0CD' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.PrimaryContactPerson 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Parties and Context',
   GeneratedFormSection = 'Category',
   DisplayName = 'Primary Contact Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '13ACF151-BD8B-4F43-BF50-36D83C7D3B76' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTemplateID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '49623009-21AD-45E6-9B40-CB4182FE8E35' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTemplate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D16FCB6B-FCEB-46C7-8AE0-5AC08F9A930E' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingEntityID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8AC97591-0971-45D9-82E9-6BBAE6ECECD3' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingEntity 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'EDF1CB45-EEA0-4121-9FCC-52E4EE1F33EA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingRecordID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'E2ED938E-B1D8-485B-B964-00CB44615977' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ParentContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Parent Contract',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '433E610E-1199-4A89-A3BE-23EEE91BB6B3' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.SupersededByContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Superseded By',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FDA34007-6E79-4A3D-AC5A-3813DB33E863' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.RootParentContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Root Parent Contract',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '15088B1B-6B7B-48DE-8B16-E11B02623AB1' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.RootSupersededByContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Root Superseded By',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '646C61DD-2A04-4397-8241-179E367AD2FE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.EffectiveDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '85C2054C-4939-415F-BCB1-A29385B881AD' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ExecutedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C24027F0-5986-4183-AC69-CDD31E60C934' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.EndDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '368A7E42-7C2C-41DD-8DE8-DBD1AD2FC7A1' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.TerminatedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '390191A8-15AB-4ECE-AEBF-9DE1BEEDA25D' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.AutoRenew 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '418FDBD3-DAF6-45AF-A89B-581E3921C2BD' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.RenewalNoticeDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '472D4155-F2B0-4B06-B6E7-2F58A90314E0' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CancellationWindowDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FDEE00C3-9A3B-4D05-A67C-D296289D9DBD' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.AnnualIncreasePercent 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '547B4E55-E673-465F-B8D3-CA1286745190' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.SigningProviderURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   ExtendedType = 'URL',
   CodeType = NULL
WHERE 
   ID = 'FE229628-C86B-4319-AA97-C7DFE82A34FA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.HasModifications 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Overview',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '629927E7-6F7A-43F3-81FA-CDECEDFD62E5' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Notes and Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '88857639-49FE-4AA8-8581-B696375B159B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Notes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Notes and Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'CE64DAFD-B5FE-4EFF-A70F-53072E819B84' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D2FB1812-DF75-423A-911E-DE5DF46FF664' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '324DD9B0-514C-4F1A-A1D0-69569F6E31D8' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('798eb0e0-fe54-489e-a682-cb7d2a1cce1c', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'FieldCategoryInfo', '{"Contract Overview":{"icon":"fa fa-file-contract","description":"Core identification, template, and document reference details."},"Parties and Context":{"icon":"fa fa-users","description":"Information about the selling company, customer, and primary contacts."},"Provenance":{"icon":"fa fa-project-diagram","description":"Reference to the source entity and record that created this contract."},"Contract Lifecycle":{"icon":"fa fa-history","description":"Relationship chain for amendments, renewals, and superseding contracts."},"Dates and Terms":{"icon":"fa fa-calendar-alt","description":"Key contractual dates including effective, execution, and expiration terms."},"Renewal Terms":{"icon":"fa fa-sync-alt","description":"Terms governing renewals, notice periods, and annual price escalations."},"Notes and Details":{"icon":"fa fa-align-left","description":"Descriptive text and processing notes."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('9b1f4820-d4ee-48e7-9bcd-d12f0d08430d', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', 'FieldCategoryIcons', '{"Contract Overview":"fa fa-file-contract","Parties and Context":"fa fa-users","Provenance":"fa fa-project-diagram","Contract Lifecycle":"fa fa-history","Dates and Terms":"fa fa-calendar-alt","Renewal Terms":"fa fa-sync-alt","Notes and Details":"fa fa-align-left","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20';

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Sequences */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Sequences: Field: NextSequenceNumber was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([NextSequenceNumber]>(0))', 'public ValidateNextSequenceNumberGreaterThanZero(result: ValidationResult) {
	if (this.NextSequenceNumber != null && this.NextSequenceNumber <= 0) {
		result.Errors.push(new ValidationErrorInfo(
			"NextSequenceNumber",
			"The next sequence number must be greater than zero.",
			this.NextSequenceNumber,
			ValidationErrorType.Failure
		));
	}
}', 'The next sequence number must be greater than zero to ensure valid sequencing.', 'ValidateNextSequenceNumberGreaterThanZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '8ABC07AE-5B21-4E8E-A8F5-8CA85C4A1086');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contracts */
-- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: AnnualIncreasePercent was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([AnnualIncreasePercent] IS NULL OR [AnnualIncreasePercent]>=(0))', 'public ValidateAnnualIncreasePercentGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.AnnualIncreasePercent != null && this.AnnualIncreasePercent < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"AnnualIncreasePercent",
			"Annual increase percentage must be greater than or equal to 0.",
			this.AnnualIncreasePercent,
			ValidationErrorType.Failure
		));
	}
}', 'The annual increase percentage must be greater than or equal to 0% if it is specified.', 'ValidateAnnualIncreasePercentGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '547B4E55-E673-465F-B8D3-CA1286745190');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: CancellationWindowDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([CancellationWindowDays] IS NULL OR [CancellationWindowDays]>=(0))', 'public ValidateCancellationWindowDaysMinimum(result: ValidationResult) {
	if (this.CancellationWindowDays != null && this.CancellationWindowDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"CancellationWindowDays",
			"Cancellation window days must be 0 or greater.",
			this.CancellationWindowDays,
			ValidationErrorType.Failure
		));
	}
}', 'The cancellation window, if specified, must be 0 days or greater.', 'ValidateCancellationWindowDaysMinimum', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'FDEE00C3-9A3B-4D05-A67C-D296289D9DBD');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: RenewalNoticeDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([RenewalNoticeDays] IS NULL OR [RenewalNoticeDays]>=(0))', 'public ValidateRenewalNoticeDaysGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.RenewalNoticeDays != null && this.RenewalNoticeDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"RenewalNoticeDays",
			"Renewal notice days must be greater than or equal to 0.",
			this.RenewalNoticeDays,
			ValidationErrorType.Failure
		));
	}
}', 'The renewal notice days must be a non-negative number (0 or greater) if it is specified.', 'ValidateRenewalNoticeDaysGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '472D4155-F2B0-4B06-B6E7-2F58A90314E0');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([CreatingEntityID] IS NULL AND [CreatingRecordID] IS NULL OR [CreatingEntityID] IS NOT NULL AND [CreatingRecordID] IS NOT NULL)', 'public ValidateCreatingEntityAndRecordCoexistence(result: ValidationResult) {
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
}', 'Both the creating entity and the creating record must be provided together, or both must be left empty. You cannot specify one without the other.', 'ValidateCreatingEntityAndRecordCoexistence', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([EndDate] IS NULL OR [EffectiveDate] IS NULL OR [EndDate]>=[EffectiveDate])', 'public ValidateEndDateAfterOrEqualToEffectiveDate(result: ValidationResult) {
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
}', 'The contract end date must be on or after the effective date.', 'ValidateEndDateAfterOrEqualToEffectiveDate', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([ParentContractID] IS NULL OR [ParentContractID]<>[ID])', 'public ValidateParentContractIDNotEqualToID(result: ValidationResult) {
	if (this.ParentContractID != null && this.ParentContractID === this.ID) {
		result.Errors.push(new ValidationErrorInfo(
			"ParentContractID",
			"A contract cannot be set as its own parent contract.",
			this.ParentContractID,
			ValidationErrorType.Failure
		));
	}
}', 'A contract cannot be its own parent contract. This prevents circular references in the contract hierarchy.', 'ValidateParentContractIDNotEqualToID', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([SupersededByContractID] IS NULL OR [SupersededByContractID]<>[ID])', 'public ValidateSupersededByContractIDNotSelf(result: ValidationResult) {
    if (this.SupersededByContractID != null && this.SupersededByContractID === this.ID) {
        result.Errors.push(new ValidationErrorInfo(
            "SupersededByContractID",
            "A contract cannot be superseded by itself.",
            this.SupersededByContractID,
            ValidationErrorType.Failure
        ));
    }
}', 'A contract cannot be superseded by itself. If a superseding contract is specified, it must be a different contract.', 'ValidateSupersededByContractIDNotSelf', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20');

