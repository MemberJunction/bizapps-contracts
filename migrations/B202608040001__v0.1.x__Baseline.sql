-- =============================================================================
-- BizApps Contracts — THE BASELINE (v0.1.0)
-- =============================================================================
-- Schema, SchemaInfo registration, the contract-number SEQUENCE, the sort-key
-- function, SIX tables and their constraints, the two app-owned programmable
-- objects, and the CodeGen output that turns bare tables into a working app.
--
-- IT IS THE FIRST OF FOUR FILES, not the whole install. Three more follow, and the
-- split is forced rather than stylistic: the layered-view flags live on __mj.Entity
-- rows that this file's own capture creates (so they cannot precede it), a wrapper
-- view cannot be created before the view it selects FROM (SQL Server defers name
-- resolution for procedure bodies but not for views), and seed data has to follow
-- both. See docs/database-migrations.md for the train and the conventions.
--
-- Everything that COULD be folded in has been: 22 incremental migrations were
-- collapsed back into this file on 2026-08-23, immediately before first publish.
-- That licence is now closed — schema changes after this point are new V migrations.
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
-- migration is immutable. See docs/database-migrations.md.
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
-- 2.B FUNCTIONS REQUIRED BY COMPUTED COLUMNS
-- =============================================================================
-- fnProvisionSortKey is created BEFORE the tables because ContractTemplateProvision
-- declares a PERSISTED computed column over it, and SQL Server resolves a computed
-- column's expression at CREATE TABLE time -- there is no deferred name resolution
-- for it as there is for a procedure body.

CREATE OR ALTER FUNCTION [${flyway:defaultSchema}].[fnProvisionSortKey] (@ProvisionNumber NVARCHAR(20))
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    IF @ProvisionNumber IS NULL RETURN NULL;

    DECLARE @out    NVARCHAR(200) = N'';
    DECLARE @digits NVARCHAR(20)  = N'';
    DECLARE @i      INT = 1;
    DECLARE @len    INT = LEN(@ProvisionNumber);
    DECLARE @c      NCHAR(1);

    WHILE @i <= @len
    BEGIN
        SET @c = SUBSTRING(@ProvisionNumber, @i, 1);
        IF @c LIKE N'[0-9]'
            SET @digits = @digits + @c;
        ELSE
        BEGIN
            IF LEN(@digits) > 0
            BEGIN
                -- Pad to 6, but never TRUNCATE a longer run: RIGHT(...,6) on a 7-digit run would
                -- drop its leading digit and sort it wildly wrong. Runs that long do not exist
                -- here, and the expression should not be the reason they cannot.
                SET @out = @out + RIGHT(REPLICATE(N'0', 6) + @digits,
                                        CASE WHEN LEN(@digits) > 6 THEN LEN(@digits) ELSE 6 END);
                SET @digits = N'';
            END
            -- UPPER so '1.1a' and '1.1A' land together rather than in two places.
            SET @out = @out + UPPER(@c);
        END
        SET @i = @i + 1;
    END

    IF LEN(@digits) > 0
        SET @out = @out + RIGHT(REPLICATE(N'0', 6) + @digits,
                                CASE WHEN LEN(@digits) > 6 THEN LEN(@digits) ELSE 6 END);

    RETURN @out;
END;
GO

-- =============================================================================
-- 2.C SEQUENCES
-- =============================================================================
-- NO CACHE, deliberately: SQL Server caches a block of sequence values and an unclean
-- shutdown discards the unused remainder, so the next value JUMPS. NO CACHE removes the
-- skip at the cost of a catalog write per call -- free at a handful of contracts a day,
-- and it makes the numbering easier to explain to finance. Ordinary gaps (a save that
-- fails after taking a number) remain normal and are not something to fix.
CREATE SEQUENCE __mj_BizAppsContracts.seq_ContractNumber
    AS INT START WITH 1 INCREMENT BY 1 NO CACHE;
GO

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
--     SourceURL IS NULLABLE, and the earlier NOT NULL is a corrected mistake rather
--     than a relaxation (ruled by Marcelo, 2026-08-19). The ERD asked for "a public URL
--     that never goes away" and REACHABILITY IS ENFORCEABLE BY NOTHING: whether a URL
--     still resolves is a fact about the outside world, and format validation is weak
--     because a well-formed dead link passes. The real requirement is "a URL OR an
--     attached file" -- and a file attaches through __mj.FileEntityRecordLink keyed on
--     RecordID, which cannot reference a record that does not exist yet. On CREATE the
--     file half is unsatisfiable in principle, so no NOT NULL, CHECK or pre-save rule
--     can express it without blocking the ordinary act of authoring a template. A
--     template with neither is INCOMPLETE, not invalid -- an ordinary state to pass
--     through -- and the derived IsUsable column on vwContractTemplates is what lets the
--     UI say so, which a person can see and fix rather than an error that stops a save.
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
    -- NULLABLE (Marcelo, 2026-08-19). See the header note above: the real rule is
    -- "a URL OR an attached file", and the file half is unsatisfiable at CREATE time.
    SourceURL NVARCHAR(1000) NULL,
    Description NVARCHAR(MAX) NULL,
    Status NVARCHAR(20) NOT NULL CONSTRAINT DF_ContractTemplate_Status DEFAULT 'Draft',
    CONSTRAINT PK_ContractTemplate PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplate_Name UNIQUE (Name)
    , CONSTRAINT CK_ContractTemplate_Status CHECK (Status IN ('Draft', 'Published'))
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
--     ProvisionSortKey is a PERSISTED computed collation key, not a stored order:
--     ProvisionNumber does not sort as text ('1.10' lands before '1.9'), and a legal
--     document has a canonical order. A hand-maintained Sequence column held that job
--     in v1 and had ALREADY collided in the seeded data -- '1' and '1.1' both claiming
--     position 1 -- which is the failure mode of storing a projection of something the
--     ProvisionNumber already states. Derived, it cannot disagree with itself.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTemplateProvision (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTemplateID UNIQUEIDENTIFIER NOT NULL,
    ProvisionNumber NVARCHAR(20) NOT NULL,
    Title NVARCHAR(200) NOT NULL,
    ProvisionText NVARCHAR(MAX) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    -- Derived, PERSISTED so it can be indexed; see 2.B for the function and why it is
    -- created first. Nobody can write a sort key, which is the point.
    ProvisionSortKey AS (__mj_BizAppsContracts.fnProvisionSortKey(ProvisionNumber)) PERSISTED,
    CONSTRAINT PK_ContractTemplateProvision PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplateProvision_Template_Number
        UNIQUE (ContractTemplateID, ProvisionNumber),
    CONSTRAINT CK_ContractTemplateProvision_TextNotBlank
        CHECK (LEN(LTRIM(RTRIM(ProvisionText))) > 0)
);
GO

-- Template first: every real query is scoped to one template.
CREATE INDEX IX_ContractTemplateProvision_SortKey
    ON __mj_BizAppsContracts.ContractTemplateProvision (ContractTemplateID, ProvisionSortKey);
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
    -- Where in the contract tree this type may sit. Mutually exclusive; BOTH FALSE means
    -- unrestricted, which is the honest default and what two of the four seeded types want.
    -- These REPLACED a three-state ParentStatusRequirement string whose values invert the
    -- rule if read in the wrong order.
    MustBeRoot BIT NOT NULL CONSTRAINT DF_ContractType_MustBeRoot DEFAULT 0,
    MustBeChild BIT NOT NULL CONSTRAINT DF_ContractType_MustBeChild DEFAULT 0,
    -- Whether a contract of this type must carry its own ContractTemplateID.
    TemplateRequired BIT NOT NULL CONSTRAINT DF_ContractType_TemplateRequired DEFAULT 0,
    CONSTRAINT PK_ContractType PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractType_Name UNIQUE (Name),
    CONSTRAINT CK_ContractType_Status CHECK (Status IN ('Active','Inactive')),
    CONSTRAINT CK_ContractType_RootOrChild CHECK (NOT (MustBeRoot = 1 AND MustBeChild = 1))
);
GO

-----------------------------------------------------------------------------
-- 3.5 (retired) ContractSequence -- the counter is a SEQUENCE, see 2.C.
--     v1 used a singleton counter TABLE, copying the shape orders uses for ORD- and
--     PAY-. A table is registered by CodeGen as an MJ ENTITY, which handed it a grid,
--     a form and AllowUpdateAPI -- an editable surface whose only use was winding the
--     counter backwards, after which numbers already in use get re-minted until
--     UQ_Contract_ContractNumber starts refusing saves one contract at a time with no
--     hint why. A SEQUENCE is not a table, so CodeGen never sees it: no entity, no
--     grid, nothing to protect. It is also atomic, which retires the HOLDLOCK/UPDLOCK
--     dance the old sproc needed.
---------------------------------------------------------------------------

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
    -- NULLABLE, and the server holds the invariant instead of the database.
    -- ContractEntityServer.Save() mints a number whenever the incoming value is null or
    -- blank, so the entity path never sends one. MJ has no way to declare "NOT NULL,
    -- assigned by the server on insert" (MJ#4001), and both available workarounds break
    -- creation in opposite directions: a DB DEFAULT makes CodeGen string-quote an
    -- EXPRESSION default into spCreateContract, which then fails to compile and is left
    -- DROPPED (MJ#4000); AllowUpdateAPI=0 silences the validator but omits the field from
    -- the insert payload, so the procedure fails on a missing @ContractNumber.
    -- UQ_Contract_ContractNumber below is PLAIN rather than filtered: SQL Server permits
    -- exactly one NULL, and a second un-numbered row is precisely what should be refused
    -- rather than accumulated. Ruled by Marcelo, 2026-08-21.
    ContractNumber NVARCHAR(50) NULL,
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
    ModificationText NVARCHAR(MAX) NOT NULL,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractTemplateModification PRIMARY KEY (ID),
    CONSTRAINT UQ_ContractTemplateModification_Contract_Provision
        UNIQUE (ContractID, ContractTemplateProvisionID),
    -- A modification that records no change is a row asserting nothing.
    CONSTRAINT CK_ContractTemplateModification_TextNotBlank
        CHECK (LEN(LTRIM(RTRIM(ModificationText))) > 0)
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
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The dated public URL a customer can open to read the standard terms. NULLABLE: reachability is enforceable by nothing (a well-formed dead link passes any format check), and the real rule is "a URL OR an attached file" — the file half attaching through __mj.FileEntityRecordLink, which cannot reference a record that does not exist yet, so on CREATE it is unsatisfiable in principle. A template with neither is INCOMPLETE rather than invalid; the derived IsUsable column on vwContractTemplates is what says so.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate', @level2type=N'COLUMN', @level2name=N'SourceURL';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Publication lifecycle. ''Draft'' -- freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. ''Published'' -- the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version -- that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplate', @level2type=N'COLUMN', @level2name=N'Status';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'ProvisionNumber';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'Title';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'ProvisionText';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order (''1.9'' before ''1.10''), which ordering by ProvisionNumber cannot. READ-ONLY -- a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTemplateProvision', @level2type=N'COLUMN', @level2name=N'ProvisionSortKey';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'RequiresExecutedDocument';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Active | Inactive.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'Status';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'This type of contract may NOT name a ParentContractID -- it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'MustBeRoot';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'This type of contract MUST name a ParentContractID -- a Change Order that amends nothing is not a change order, and would never appear in the original agreement''s lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'MustBeChild';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'This type of contract must carry its own ContractTemplateID -- the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because ''where in the tree'' and ''does it need its own paper'' are different questions and a future type could want any combination.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'TemplateRequired';
GO

EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express ''NOT NULL, assigned by the server on insert'' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be ''fixed'': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ContractNumber';
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
-- 6. APP-OWNED PROGRAMMABLE OBJECTS
-- =============================================================================
-- Everything here is written by hand and owned by this app -- CodeGen neither
-- generates nor regenerates any of it. (CodeGen's own output is section 7.)
-- The two layered base views that wrap CodeGen's generated views are NOT here:
-- a view cannot be created before the view it selects from, so they follow the
-- capture in their own migration. See the next V file.

---------------------------------------------------------------------------
-- 6.1 spAssignNextContractNumber -- the only place a contract number is minted.
--     Keeps its name and signature across the counter-table-to-sequence change,
--     so ContractEntityServer still calls EXEC spAssignNextContractNumber
--     @ContractNumber OUTPUT. Putting the lock in a database object rather than a
--     TypeScript string is what made that swap invisible to the application, and
--     it makes the PostgreSQL port a database exercise.
---------------------------------------------------------------------------
CREATE PROCEDURE [${flyway:defaultSchema}].[spAssignNextContractNumber]
    @ContractNumber NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- No HOLDLOCK, no UPDLOCK, no singleton row to be missing: NEXT VALUE FOR is atomic and
    -- never hands the same value to two callers.
    DECLARE @NextSeq INT = NEXT VALUE FOR [${flyway:defaultSchema}].[seq_ContractNumber];

    -- FORMAT pads to six digits WITHOUT truncating a longer number. The previous
    -- `RIGHT(N'000000' + CAST(@NextSeq AS NVARCHAR(6)), 6)` silently produced 'CTR-000000' at
    -- 1,000,000 -- it kept the LAST six characters of an over-long string. Unreachable in
    -- practice, and not worth carrying forward now that the line is being rewritten anyway.
    SET @ContractNumber = N'CTR-' + FORMAT(@NextSeq, N'D6');
END;
GO

---------------------------------------------------------------------------
-- 6.2 trg_ContractTemplateProvision_Immutability -- a PUBLISHED agreement
--     version neither gains, loses nor changes clauses (R-1).
--
--     THE INSERT BRANCH DELIBERATELY HAS NO ROLLBACK. MJ's provider calls the
--     generated CRUD procedure as INSERT ... EXEC spCreate... so it can capture the
--     returned row, and SQL Server forbids ROLLBACK TRANSACTION anywhere inside an
--     INSERT-EXEC -- including in a trigger fired by it, which surfaced to users as
--     "Cannot use the ROLLBACK statement within an INSERT-EXEC statement" instead of
--     the real message. THROW alone dooms the transaction, so the row is still
--     refused. UPDATE and DELETE keep their explicit ROLLBACK: spUpdate/spDelete are
--     not invoked that way, and it is the documented shape for undoing a statement.
--
--     The UPDATE branch compares VALUES, not merely "an UPDATE happened": mj sync
--     push re-pushes every provision row and a trigger fires on identical values, so
--     without the comparison a routine seed push would fail. Description and
--     ProvisionSortKey stay outside the frozen set -- annotating a document, and a key
--     derived from its own numbering, are not changing what it says (and the sort key
--     cannot be written at all).
---------------------------------------------------------------------------
CREATE TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: no ROLLBACK here -- see the header. THROW dooms the transaction on its own.
    IF NOT EXISTS (SELECT 1 FROM deleted)
       AND EXISTS (
            SELECT 1 FROM inserted i
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = i.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        THROW 50104, 'A provision cannot be added to a PUBLISHED agreement version — that would silently grow the terms of every contract already referencing it. Publish a new version instead.', 1;
    END;

    -- DELETE: not reached through INSERT-EXEC, so the explicit ROLLBACK is both allowed and correct.
    IF NOT EXISTS (SELECT 1 FROM inserted)
       AND EXISTS (
            SELECT 1 FROM deleted d
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = d.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50101, 'A provision cannot be deleted from a PUBLISHED agreement version — that would remove a clause from an agreement someone signed. Publish a new version instead; a published version is a historical record.', 1;
    END;

    -- UPDATE: value comparison, not mere "an UPDATE happened" — `mj sync push` re-pushes every
    -- provision row and a trigger fires on identical values, so without this an ordinary seed push
    -- would fail. NULL-safe on ProvisionText because `i.x <> d.x` is UNKNOWN when either side is NULL.
    IF EXISTS (
        SELECT 1
          FROM deleted d
          JOIN inserted i ON i.[ID] = d.[ID]
          JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = d.[ContractTemplateID]
         WHERE t.[Status] = 'Published'
           AND (
                    i.[ProvisionNumber] <> d.[ProvisionNumber]
                 OR i.[Title]           <> d.[Title]
                 OR ISNULL(CAST(i.[ProvisionText] AS NVARCHAR(MAX)), N'') <> ISNULL(CAST(d.[ProvisionText] AS NVARCHAR(MAX)), N'')
                 OR ISNULL(i.[ContractTemplateID], '00000000-0000-0000-0000-000000000000')
                    <> ISNULL(d.[ContractTemplateID], '00000000-0000-0000-0000-000000000000')
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50102, 'ProvisionNumber, Title, ProvisionText and the owning template cannot change on a PUBLISHED agreement version — editing one rewrites what a customer agreed to. Publish a new version instead. (Description remains editable.)', 1;
    END;
END;
GO


















































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
         '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
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
      SELECT 1 FROM [${mjSchema}].[Application] WHERE [ID] = '891e92fe-561a-4fed-8edc-e2d96fb18541'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[Application] (ID, Name, Description, SchemaAutoAddNewEntities, Path, AutoUpdatePath, DefaultForNewUser)
                       VALUES ('891e92fe-561a-4fed-8edc-e2d96fb18541', '${flyway:defaultSchema}', 'Generated for schema', '${flyway:defaultSchema}', 'mjbizappscontracts', 1, 0)
   END;

/* Adding role UI to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND [RoleID] = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* Adding role Developer to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND [RoleID] = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1)
   END;

/* Adding role Integration to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND [RoleID] = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Types to application ID: '891e92fe-561a-4fed-8edc-e2d96fb18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891e92fe-561a-4fed-8edc-e2d96fb18541', '4e3f97be-e196-4cc0-9b5d-cc50de8967a0', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891e92fe-561a-4fed-8edc-e2d96fb18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4e3f97be-e196-4cc0-9b5d-cc50de8967a0', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4e3f97be-e196-4cc0-9b5d-cc50de8967a0', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4e3f97be-e196-4cc0-9b5d-cc50de8967a0', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

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
         '731f2890-1415-40de-9073-d22ea23392b3',
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

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Templates to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891E92FE-561A-4FED-8EDC-E2D96FB18541', '731f2890-1415-40de-9073-d22ea23392b3', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('731f2890-1415-40de-9073-d22ea23392b3', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('731f2890-1415-40de-9073-d22ea23392b3', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('731f2890-1415-40de-9073-d22ea23392b3', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

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
         '317df592-8c20-473d-b097-2ab239877438',
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

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Provisions to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891E92FE-561A-4FED-8EDC-E2D96FB18541', '317df592-8c20-473d-b097-2ab239877438', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317df592-8c20-473d-b097-2ab239877438', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317df592-8c20-473d-b097-2ab239877438', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317df592-8c20-473d-b097-2ab239877438', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

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
         'c8909a57-6ddb-4585-be00-e707c5b4f262',
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

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Types to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891E92FE-561A-4FED-8EDC-E2D96FB18541', 'c8909a57-6ddb-4585-be00-e707c5b4f262', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('c8909a57-6ddb-4585-be00-e707c5b4f262', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('c8909a57-6ddb-4585-be00-e707c5b4f262', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('c8909a57-6ddb-4585-be00-e707c5b4f262', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

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
         '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
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

/* SQL generated to add new entity MJ_BizApps_Contracts: Contracts to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891E92FE-561A-4FED-8EDC-E2D96FB18541', '5deb0b11-ed6c-48b3-9200-f4441396c5e2', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5deb0b11-ed6c-48b3-9200-f4441396c5e2', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5deb0b11-ed6c-48b3-9200-f4441396c5e2', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5deb0b11-ed6c-48b3-9200-f4441396c5e2', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

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
         'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
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

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Modifications to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('891E92FE-561A-4FED-8EDC-E2D96FB18541', 'b05a480f-f7c5-4d45-8ea3-c90e9a14f225', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('b05a480f-f7c5-4d45-8ea3-c90e9a14f225', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('b05a480f-f7c5-4d45-8ea3-c90e9a14f225', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('b05a480f-f7c5-4d45-8ea3-c90e9a14f225', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

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

/* SQL text to insert 67 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'da55d974-f70e-42d0-a12a-04f2efd46a85' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ID')) BEGIN
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
            'da55d974-f70e-42d0-a12a-04f2efd46a85',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fd673fee-72ab-4109-89b1-db5bcee9eb3e' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ContractTemplateID')) BEGIN
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
            'fd673fee-72ab-4109-89b1-db5bcee9eb3e',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 2,
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
            '731F2890-1415-40DE-9073-D22EA23392B3',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'cfb7315f-8759-4728-bd30-faae93f97106' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ProvisionNumber')) BEGIN
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
            'cfb7315f-8759-4728-bd30-faae93f97106',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 3,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ce9ce69a-95cf-4cf0-bda8-f5f5e661a40b' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'Title')) BEGIN
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
            'ce9ce69a-95cf-4cf0-bda8-f5f5e661a40b',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 4,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd2cd9029-4db4-4ad1-85a2-abbfda35eafd' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ProvisionText')) BEGIN
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
            'd2cd9029-4db4-4ad1-85a2-abbfda35eafd',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 5,
            'ProvisionText',
            'Provision Text',
            'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.',
            'nvarchar',
            -1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1bfda475-470f-4f3c-8b5d-b0dbdced2ee3' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'Description')) BEGIN
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
            '1bfda475-470f-4f3c-8b5d-b0dbdced2ee3',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 6,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2e082ebc-4a00-4c39-8f6d-f7b680f5b345' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ProvisionSortKey')) BEGIN
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
            '2e082ebc-4a00-4c39-8f6d-f7b680f5b345',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 7,
            'ProvisionSortKey',
            'Provision Sort Key',
            'Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order (''1.9'' before ''1.10''), which ordering by ProvisionNumber cannot. READ-ONLY -- a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.',
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6b098c7f-9119-4c60-94b5-ca2aca14309f' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = '__mj_CreatedAt')) BEGIN
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
            '6b098c7f-9119-4c60-94b5-ca2aca14309f',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 8,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9f515edd-be69-4955-9c10-eb1819ddfd2c' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = '__mj_UpdatedAt')) BEGIN
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
            '9f515edd-be69-4955-9c10-eb1819ddfd2c',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 9,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4796bc59-bf1a-41cf-83b5-29e8f8880c47' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'ID')) BEGIN
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
            '4796bc59-bf1a-41cf-83b5-29e8f8880c47',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '982e307b-667c-4955-99de-f9a96fab2cb2' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'ContractID')) BEGIN
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
            '982e307b-667c-4955-99de-f9a96fab2cb2',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 2,
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
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0864cb7f-e532-402f-9f16-102ec14993c6' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'ContractTemplateProvisionID')) BEGIN
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
            '0864cb7f-e532-402f-9f16-102ec14993c6',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 3,
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
            '317DF592-8C20-473D-B097-2AB239877438',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0d2fc779-82ca-4d68-a711-3d871a356164' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'ModificationText')) BEGIN
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
            '0d2fc779-82ca-4d68-a711-3d871a356164',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 4,
            'ModificationText',
            'Modification Text',
            'What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.',
            'nvarchar',
            -1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '87bb27cb-98b7-4704-bdc5-7871f8f394eb' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'Notes')) BEGIN
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
            '87bb27cb-98b7-4704-bdc5-7871f8f394eb',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '18518499-1dd3-4369-bd76-59b62eeba5b8' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = '__mj_CreatedAt')) BEGIN
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
            '18518499-1dd3-4369-bd76-59b62eeba5b8',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 6,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '54072096-c4e2-450c-97fa-bf162e2485d6' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = '__mj_UpdatedAt')) BEGIN
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
            '54072096-c4e2-450c-97fa-bf162e2485d6',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 7,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b592f895-7e87-480a-8663-9d3c70f812d5' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = 'ID')) BEGIN
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
            'b592f895-7e87-480a-8663-9d3c70f812d5',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'eece216e-ec2b-4630-9e17-3fcde668f32a' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = 'Name')) BEGIN
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
            'eece216e-ec2b-4630-9e17-3fcde668f32a',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 2,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3ec31ca1-a410-4a25-bb23-1e668a16a125' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = 'Description')) BEGIN
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
            '3ec31ca1-a410-4a25-bb23-1e668a16a125',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 3,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0e2ab42b-29f2-4151-a424-aba78bba163b' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = 'Status')) BEGIN
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
            '0e2ab42b-29f2-4151-a424-aba78bba163b',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 4,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e7d55020-c93e-46b9-89e5-19088cbedb0a' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = '__mj_CreatedAt')) BEGIN
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
            'e7d55020-c93e-46b9-89e5-19088cbedb0a',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '26168480-7c59-4436-b954-4979f44f7014' OR (EntityID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND Name = '__mj_UpdatedAt')) BEGIN
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
            '26168480-7c59-4436-b954-4979f44f7014',
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', -- Entity: MJ_BizApps_Contracts: Contract Template Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 6,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a8bf5461-4a41-4388-8761-50b79fc598b4' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'ID')) BEGIN
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
            'a8bf5461-4a41-4388-8761-50b79fc598b4',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1fc39118-f7f8-4ba7-9940-f341e35f4fdb' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'Name')) BEGIN
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
            '1fc39118-f7f8-4ba7-9940-f341e35f4fdb',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 2,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7b8ec82e-cf52-4f4c-980d-47a15194ea12' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'ContractTemplateTypeID')) BEGIN
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
            '7b8ec82e-cf52-4f4c-980d-47a15194ea12',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 3,
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
            '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd4e48fff-2f10-4e2e-a036-4d98bdafca99' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'VersionLabel')) BEGIN
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
            'd4e48fff-2f10-4e2e-a036-4d98bdafca99',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 4,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd20b1f02-4f4b-4a8e-894d-4d74f32a6282' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'IntroducedDate')) BEGIN
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
            'd20b1f02-4f4b-4a8e-894d-4d74f32a6282',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5f27fb9a-a089-46ce-a332-f7e7de745bcf' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'SourceURL')) BEGIN
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
            '5f27fb9a-a089-46ce-a332-f7e7de745bcf',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 6,
            'SourceURL',
            'Source URL',
            'The dated public URL a customer can open to read the standard terms. NULLABLE: reachability is enforceable by nothing (a well-formed dead link passes any format check), and the real rule is "a URL OR an attached file" — the file half attaching through ${mjSchema}.FileEntityRecordLink, which cannot reference a record that does not exist yet, so on CREATE it is unsatisfiable in principle. A template with neither is INCOMPLETE rather than invalid; the derived IsUsable column on vwContractTemplates is what says so.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7f9a6927-ca1d-441b-9682-7035c95393d8' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'Description')) BEGIN
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
            '7f9a6927-ca1d-441b-9682-7035c95393d8',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 7,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e84e1c35-41c9-4a59-8ad2-6d426fdb7e6b' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'Status')) BEGIN
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
            'e84e1c35-41c9-4a59-8ad2-6d426fdb7e6b',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 8,
            'Status',
            'Status',
            'Publication lifecycle. ''Draft'' -- freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. ''Published'' -- the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version -- that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.',
            'nvarchar',
            40,
            0,
            0,
            0,
            'Draft',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e586db3a-8fca-424f-bb0f-ae34be10c686' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = '__mj_CreatedAt')) BEGIN
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
            'e586db3a-8fca-424f-bb0f-ae34be10c686',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 9,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b0e8e57c-69a5-4a3f-bad2-ccbf75f2ff30' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = '__mj_UpdatedAt')) BEGIN
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
            'b0e8e57c-69a5-4a3f-bad2-ccbf75f2ff30',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9c8643d3-2b82-41a6-80f6-d29abb68d1cb' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'ID')) BEGIN
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
            '9c8643d3-2b82-41a6-80f6-d29abb68d1cb',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '84119ad2-cba8-466b-b20a-8a94c20fce3f' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'Name')) BEGIN
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
            '84119ad2-cba8-466b-b20a-8a94c20fce3f',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 2,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '46b195b4-ea25-41a4-bb78-83b2014a930c' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'Description')) BEGIN
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
            '46b195b4-ea25-41a4-bb78-83b2014a930c',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 3,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '62afa042-4658-4d78-b9c3-1bdd0b3997d4' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'RequiresExecutedDocument')) BEGIN
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
            '62afa042-4658-4d78-b9c3-1bdd0b3997d4',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 4,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '59601a28-9aed-4e62-8b3b-ea21b769b9eb' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'Status')) BEGIN
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
            '59601a28-9aed-4e62-8b3b-ea21b769b9eb',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd252cc6d-3196-4616-aaef-93ffc7ce6887' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'MustBeRoot')) BEGIN
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
            'd252cc6d-3196-4616-aaef-93ffc7ce6887',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 6,
            'MustBeRoot',
            'Must Be Root',
            'This type of contract may NOT name a ParentContractID -- it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '04ba23cd-ec7a-495b-81df-47474ef8c0eb' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'MustBeChild')) BEGIN
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
            '04ba23cd-ec7a-495b-81df-47474ef8c0eb',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 7,
            'MustBeChild',
            'Must Be Child',
            'This type of contract MUST name a ParentContractID -- a Change Order that amends nothing is not a change order, and would never appear in the original agreement''s lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '444fc85a-bd7a-4967-8633-a4e1f8acb4ce' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'TemplateRequired')) BEGIN
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
            '444fc85a-bd7a-4967-8633-a4e1f8acb4ce',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 8,
            'TemplateRequired',
            'Template Required',
            'This type of contract must carry its own ContractTemplateID -- the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because ''where in the tree'' and ''does it need its own paper'' are different questions and a future type could want any combination.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6a869a40-c89a-43f5-bc80-94a104e9fc46' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = '__mj_CreatedAt')) BEGIN
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
            '6a869a40-c89a-43f5-bc80-94a104e9fc46',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 9,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '68821111-317c-4ab8-922e-f1ec8aea0973' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = '__mj_UpdatedAt')) BEGIN
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
            '68821111-317c-4ab8-922e-f1ec8aea0973',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '04e8aa9d-c2dc-489d-b081-75c4e6ddfa6b' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ID')) BEGIN
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
            '04e8aa9d-c2dc-489d-b081-75c4e6ddfa6b',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8677055b-2482-4250-98c1-afc3dae57393' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ContractNumber')) BEGIN
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
            '8677055b-2482-4250-98c1-afc3dae57393',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 2,
            'ContractNumber',
            'Contract Number',
            'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express ''NOT NULL, assigned by the server on insert'' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be ''fixed'': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.',
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
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'df26a6b1-eb6c-42d8-b236-cd13f58c9b78' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ContractTypeID')) BEGIN
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
            'df26a6b1-eb6c-42d8-b236-cd13f58c9b78',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 3,
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
            'C8909A57-6DDB-4585-BE00-E707C5B4F262',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CompanyID')) BEGIN
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
            'bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 4,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f11c9543-f483-4bed-a9ce-3e7659d24011' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CustomerOrganizationID')) BEGIN
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
            'f11c9543-f483-4bed-a9ce-3e7659d24011',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd47233ed-0ebf-4329-b270-99f70589cd7f' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'PrimaryContactPersonID')) BEGIN
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
            'd47233ed-0ebf-4329-b270-99f70589cd7f',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 6,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ContractTemplateID')) BEGIN
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
            'b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 7,
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
            '731F2890-1415-40DE-9073-D22EA23392B3',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '316a9f07-54f1-4038-862a-c25a2084f274' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CreatingEntityID')) BEGIN
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
            '316a9f07-54f1-4038-862a-c25a2084f274',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 8,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '611650f5-bfc3-4809-b9b1-80ac9979b450' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CreatingRecordID')) BEGIN
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
            '611650f5-bfc3-4809-b9b1-80ac9979b450',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 9,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6db0692a-42cd-4ac5-a43b-49ecc81ef370' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ParentContractID')) BEGIN
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
            '6db0692a-42cd-4ac5-a43b-49ecc81ef370',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 10,
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
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '44bc44ef-a6f2-4630-a899-487ce0e3cc56' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'SupersededByContractID')) BEGIN
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
            '44bc44ef-a6f2-4630-a899-487ce0e3cc56',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 11,
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
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '131ce82f-ac93-4dcf-95c0-3ea4fc681c2c' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'SigningProviderURL')) BEGIN
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
            '131ce82f-ac93-4dcf-95c0-3ea4fc681c2c',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 12,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5605ab79-a11a-4561-8b34-b7567a36f27a' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'EffectiveDate')) BEGIN
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
            '5605ab79-a11a-4561-8b34-b7567a36f27a',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 13,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9ed4a8cc-e0b8-4880-945a-4bd6dd6368c6' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ExecutedDate')) BEGIN
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
            '9ed4a8cc-e0b8-4880-945a-4bd6dd6368c6',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 14,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '343becbd-079b-443a-998c-2e7ddccd8a01' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'EndDate')) BEGIN
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
            '343becbd-079b-443a-998c-2e7ddccd8a01',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 15,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd312f0c4-ad4d-4f0b-b54a-1051ec735464' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'TerminatedDate')) BEGIN
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
            'd312f0c4-ad4d-4f0b-b54a-1051ec735464',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 16,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8b3c517c-ff01-4121-a740-632df75f3c05' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'AutoRenew')) BEGIN
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
            '8b3c517c-ff01-4121-a740-632df75f3c05',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 17,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '573064ac-38a8-42a2-95b2-ccbd605004ea' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'RenewalNoticeDays')) BEGIN
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
            '573064ac-38a8-42a2-95b2-ccbd605004ea',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 18,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c6464adc-6683-4d4b-aa7a-64f9e052d225' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CancellationWindowDays')) BEGIN
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
            'c6464adc-6683-4d4b-aa7a-64f9e052d225',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 19,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3b2625e1-c5ab-462c-aa7e-533c5f40646d' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'AnnualIncreasePercent')) BEGIN
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
            '3b2625e1-c5ab-462c-aa7e-533c5f40646d',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 20,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd54ddebd-615b-4d29-a995-246c3c0f7408' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'HasModifications')) BEGIN
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
            'd54ddebd-615b-4d29-a995-246c3c0f7408',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 21,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '30b733e2-70e1-4d55-ba83-73fedba848fa' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'Description')) BEGIN
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
            '30b733e2-70e1-4d55-ba83-73fedba848fa',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 22,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '68e70227-d818-4f11-8fe4-553f5c84be53' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'Notes')) BEGIN
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
            '68e70227-d818-4f11-8fe4-553f5c84be53',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 23,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7c14348e-69de-4f66-b62c-99c0a7e415af' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = '__mj_CreatedAt')) BEGIN
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
            '7c14348e-69de-4f66-b62c-99c0a7e415af',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 24,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0eba35ec-fb3d-4978-8650-fc6229a9180e' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = '__mj_UpdatedAt')) BEGIN
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
            '0eba35ec-fb3d-4978-8650-fc6229a9180e',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 25,
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
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to insert entity field value with ID 217e9e49-0b4f-44c1-9f68-035f69e7a7bd */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('217e9e49-0b4f-44c1-9f68-035f69e7a7bd', '0E2AB42B-29F2-4151-A424-ABA78BBA163B', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 3ba9d65c-2cc4-4b0b-9be7-376aaab7234b */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('3ba9d65c-2cc4-4b0b-9be7-376aaab7234b', '0E2AB42B-29F2-4151-A424-ABA78BBA163B', 2, 'Inactive', 'Inactive', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 0E2AB42B-29F2-4151-A424-ABA78BBA163B */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='0E2AB42B-29F2-4151-A424-ABA78BBA163B';

/* SQL text to insert entity field value with ID 0b3ec358-4aec-4e2c-9361-94626326c8d6 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0b3ec358-4aec-4e2c-9361-94626326c8d6', 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B', 1, 'Draft', 'Draft', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID ad6ada75-99df-45c1-b852-5c3aebaf6220 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ad6ada75-99df-45c1-b852-5c3aebaf6220', 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B', 2, 'Published', 'Published', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B';

/* SQL text to insert entity field value with ID 6b1d3830-0e26-4457-b945-b8c05221c54e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('6b1d3830-0e26-4457-b945-b8c05221c54e', '59601A28-9AED-4E62-8B3B-EA21B769B9EB', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 39fba98a-d6e1-4f28-bb74-5f40e0e43f3f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('39fba98a-d6e1-4f28-bb74-5f40e0e43f3f', '59601A28-9AED-4E62-8B3B-EA21B769B9EB', 2, 'Inactive', 'Inactive', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 59601A28-9AED-4E62-8B3B-EA21B769B9EB */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='59601A28-9AED-4E62-8B3B-EA21B769B9EB';


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Template Provisions -> MJ_BizApps_Contracts: Contract Template Modifications (One To Many via ContractTemplateProvisionID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '82939a7c-51c9-4723-bcd7-3caecf976536'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('82939a7c-51c9-4723-bcd7-3caecf976536', '317DF592-8C20-473D-B097-2AB239877438', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'ContractTemplateProvisionID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Companies -> MJ_BizApps_Contracts: Contracts (One To Many via CompanyID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'aa2aa995-a5fa-4565-8355-90e26f36365d'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('aa2aa995-a5fa-4565-8355-90e26f36365d', 'D4238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CompanyID', 'One To Many', 1, 1, 7, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Entities -> MJ_BizApps_Contracts: Contracts (One To Many via CreatingEntityID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '7fa39de0-72c9-4956-ad6c-476397a1aeac'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('7fa39de0-72c9-4956-ad6c-476397a1aeac', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CreatingEntityID', 'One To Many', 1, 1, 77, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: Organizations -> MJ_BizApps_Contracts: Contracts (One To Many via CustomerOrganizationID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'c674fabb-6df9-434e-90c0-99ec631f234b'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('c674fabb-6df9-434e-90c0-99ec631f234b', 'C70448F9-9792-41D7-A82C-784B66429D54', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CustomerOrganizationID', 'One To Many', 1, 1, 5, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Template Types -> MJ_BizApps_Contracts: Contract Templates (One To Many via ContractTemplateTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '05bfcb9a-898f-4d3b-9341-9c2a5fc9c996'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('05bfcb9a-898f-4d3b-9341-9c2a5fc9c996', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', '731F2890-1415-40DE-9073-D22EA23392B3', 'ContractTemplateTypeID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Templates -> MJ_BizApps_Contracts: Contract Template Provisions (One To Many via ContractTemplateID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'e415e5bf-fcaa-49a6-bf33-ef3bc2d0d865'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('e415e5bf-fcaa-49a6-bf33-ef3bc2d0d865', '731F2890-1415-40DE-9073-D22EA23392B3', '317DF592-8C20-473D-B097-2AB239877438', 'ContractTemplateID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Templates -> MJ_BizApps_Contracts: Contracts (One To Many via ContractTemplateID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '7790db07-7e7f-4f4a-a661-fac992fa5cf7'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('7790db07-7e7f-4f4a-a661-fac992fa5cf7', '731F2890-1415-40DE-9073-D22EA23392B3', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ContractTemplateID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: People -> MJ_BizApps_Contracts: Contracts (One To Many via PrimaryContactPersonID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '6f16093e-ba7a-44c9-8e06-901f3383c7dc'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('6f16093e-ba7a-44c9-8e06-901f3383c7dc', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'PrimaryContactPersonID', 'One To Many', 1, 1, 4, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Types -> MJ_BizApps_Contracts: Contracts (One To Many via ContractTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '37d5be77-a5a5-47f3-b217-e5ae72daafe9'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('37d5be77-a5a5-47f3-b217-e5ae72daafe9', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ContractTypeID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Template Modifications (One To Many via ContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '0a972e9e-abaa-47fe-8dd7-90d1a60dc25d'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('0a972e9e-abaa-47fe-8dd7-90d1a60dc25d', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'ContractID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via SupersededByContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '3b056bc8-b985-403a-9dcc-accef921c323'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('3b056bc8-b985-403a-9dcc-accef921c323', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'SupersededByContractID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via ParentContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'e45a646d-9a56-45e8-9c64-5583e38654c2'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('e45a646d-9a56-45e8-9c64-5583e38654c2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ParentContractID', 'One To Many', 1, 1, 3, GETUTCDATE(), GETUTCDATE())
   END;

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

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

/* SQL text to update entity field related entity name field map for entity field ID FD673FEE-72AB-4109-89B1-DB5BCEE9EB3E */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='FD673FEE-72AB-4109-89B1-DB5BCEE9EB3E', @RelatedEntityNameFieldMap='ContractTemplate';

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

/* SQL text to update entity field related entity name field map for entity field ID 7B8EC82E-CF52-4F4C-980D-47A15194EA12 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='7B8EC82E-CF52-4F4C-980D-47A15194EA12', @RelatedEntityNameFieldMap='ContractTemplateType';

/* Index for Foreign Keys for ContractType */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

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
    @ModificationText nvarchar(MAX),
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
                @ModificationText,
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
                @ModificationText,
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
        [ModificationText] = ISNULL(@ModificationText, [ModificationText]),
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
    @Status nvarchar(10) = NULL,
    @MustBeRoot bit = NULL,
    @MustBeChild bit = NULL,
    @TemplateRequired bit = NULL
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
                [Status],
                [MustBeRoot],
                [MustBeChild],
                [TemplateRequired]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active'),
                ISNULL(@MustBeRoot, 0),
                ISNULL(@MustBeChild, 0),
                ISNULL(@TemplateRequired, 0)
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
                [Status],
                [MustBeRoot],
                [MustBeChild],
                [TemplateRequired]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active'),
                ISNULL(@MustBeRoot, 0),
                ISNULL(@MustBeChild, 0),
                ISNULL(@TemplateRequired, 0)
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
    @Status nvarchar(10) = NULL,
    @MustBeRoot bit = NULL,
    @MustBeChild bit = NULL,
    @TemplateRequired bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [RequiresExecutedDocument] = ISNULL(@RequiresExecutedDocument, [RequiresExecutedDocument]),
        [Status] = ISNULL(@Status, [Status]),
        [MustBeRoot] = ISNULL(@MustBeRoot, [MustBeRoot]),
        [MustBeChild] = ISNULL(@MustBeChild, [MustBeChild]),
        [TemplateRequired] = ISNULL(@TemplateRequired, [TemplateRequired])
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
    @ProvisionText nvarchar(MAX),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL
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
                [Description]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTemplateID,
                @ProvisionNumber,
                @Title,
                @ProvisionText,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END
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
                [Description]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTemplateID,
                @ProvisionNumber,
                @Title,
                @ProvisionText,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END
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
    @ProvisionText nvarchar(MAX) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateProvision]
    SET
        [ContractTemplateID] = ISNULL(@ContractTemplateID, [ContractTemplateID]),
        [ProvisionNumber] = ISNULL(@ProvisionNumber, [ProvisionNumber]),
        [Title] = ISNULL(@Title, [Title]),
        [ProvisionText] = ISNULL(@ProvisionText, [ProvisionText]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END
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
    @SourceURL_Clear bit = 0,
    @SourceURL nvarchar(1000) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(20) = NULL
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
                [Description],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                @ContractTemplateTypeID,
                CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, NULL) END,
                CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, NULL) END,
                CASE WHEN @SourceURL_Clear = 1 THEN NULL ELSE ISNULL(@SourceURL, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Draft')
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
                [Description],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                @ContractTemplateTypeID,
                CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, NULL) END,
                CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, NULL) END,
                CASE WHEN @SourceURL_Clear = 1 THEN NULL ELSE ISNULL(@SourceURL, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Draft')
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
    @SourceURL_Clear bit = 0,
    @SourceURL nvarchar(1000) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(20) = NULL
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
        [SourceURL] = CASE WHEN @SourceURL_Clear = 1 THEN NULL ELSE ISNULL(@SourceURL, [SourceURL]) END,
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Status] = ISNULL(@Status, [Status])
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

/* SQL text to update entity field related entity name field map for entity field ID DF26A6B1-EB6C-42D8-B236-CD13F58C9B78 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='DF26A6B1-EB6C-42D8-B236-CD13F58C9B78', @RelatedEntityNameFieldMap='ContractType';

/* SQL text to update entity field related entity name field map for entity field ID BAD7AA2F-EE2B-430A-B182-B7E4B7E09F8A */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='BAD7AA2F-EE2B-430A-B182-B7E4B7E09F8A', @RelatedEntityNameFieldMap='Company';

/* SQL text to update entity field related entity name field map for entity field ID F11C9543-F483-4BED-A9CE-3E7659D24011 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='F11C9543-F483-4BED-A9CE-3E7659D24011', @RelatedEntityNameFieldMap='CustomerOrganization';

/* SQL text to update entity field related entity name field map for entity field ID D47233ED-0EBF-4329-B270-99F70589CD7F */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='D47233ED-0EBF-4329-B270-99F70589CD7F', @RelatedEntityNameFieldMap='PrimaryContactPerson';

/* SQL text to update entity field related entity name field map for entity field ID B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA', @RelatedEntityNameFieldMap='ContractTemplate';

/* SQL text to update entity field related entity name field map for entity field ID 316A9F07-54F1-4038-862A-C25A2084F274 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='316A9F07-54F1-4038-862A-C25A2084F274', @RelatedEntityNameFieldMap='CreatingEntity';

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
    MJEntity_CreatingEntityID.[Name] AS [CreatingEntity]
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
    @ContractNumber_Clear bit = 0,
    @ContractNumber nvarchar(50) = NULL,
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
                CASE WHEN @ContractNumber_Clear = 1 THEN NULL ELSE ISNULL(@ContractNumber, NULL) END,
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
                CASE WHEN @ContractNumber_Clear = 1 THEN NULL ELSE ISNULL(@ContractNumber, NULL) END,
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
    @ContractNumber_Clear bit = 0,
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
        [ContractNumber] = CASE WHEN @ContractNumber_Clear = 1 THEN NULL ELSE ISNULL(@ContractNumber, [ContractNumber]) END,
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

/* SQL text to delete unneeded entity fields (6 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}', @EntityIDs='4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0,731F2890-1415-40DE-9073-D22EA23392B3,317DF592-8C20-473D-B097-2AB239877438,C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2,B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* SQL text to insert 8 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f56ab0cb-ec8f-429a-a33f-beddc6bb9f67' OR (EntityID = '317DF592-8C20-473D-B097-2AB239877438' AND Name = 'ContractTemplate')) BEGIN
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
            'f56ab0cb-ec8f-429a-a33f-beddc6bb9f67',
            '317DF592-8C20-473D-B097-2AB239877438', -- Entity: MJ_BizApps_Contracts: Contract Template Provisions
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438') + 10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1e89d300-7f0d-4c94-9ba2-65f616951731' OR (EntityID = '731F2890-1415-40DE-9073-D22EA23392B3' AND Name = 'ContractTemplateType')) BEGIN
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
            '1e89d300-7f0d-4c94-9ba2-65f616951731',
            '731F2890-1415-40DE-9073-D22EA23392B3', -- Entity: MJ_BizApps_Contracts: Contract Templates
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3') + 11,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '14bda941-ce85-4a14-8fdc-3681b8c52418' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ContractType')) BEGIN
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
            '14bda941-ce85-4a14-8fdc-3681b8c52418',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 26,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a2b9a232-351c-4cf9-a050-6f059f146806' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'Company')) BEGIN
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
            'a2b9a232-351c-4cf9-a050-6f059f146806',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 27,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8fbc1aac-1342-4584-991f-aab1c31ce673' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CustomerOrganization')) BEGIN
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
            '8fbc1aac-1342-4584-991f-aab1c31ce673',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 28,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2999f51a-9170-4028-b142-2f33d7e056ed' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'PrimaryContactPerson')) BEGIN
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
            '2999f51a-9170-4028-b142-2f33d7e056ed',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 29,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3df1fccc-6c4f-4cef-abec-836517ba655a' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'ContractTemplate')) BEGIN
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
            '3df1fccc-6c4f-4cef-abec-836517ba655a',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 30,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b35327d2-0775-4cd2-9d4a-0fa1a2c98aa0' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CreatingEntity')) BEGIN
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
            'b35327d2-0775-4cd2-9d4a-0fa1a2c98aa0',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 31,
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

/* SQL text to update existing entity fields from schema (6 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}', @EntityIDs='4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0,731F2890-1415-40DE-9073-D22EA23392B3,317DF592-8C20-473D-B097-2AB239877438,C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2,B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '62AFA042-4658-4D78-B9C3-1BDD0B3997D4'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '59601A28-9AED-4E62-8B3B-EA21B769B9EB'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '444FC85A-BD7A-4967-8633-A4E1F8ACB4CE'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '0E2AB42B-29F2-4151-A424-ABA78BBA163B'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '982E307B-667C-4955-99DE-F9A96FAB2CB2'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '0864CB7F-E532-402F-9F16-102EC14993C6'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'D20B1F02-4F4B-4A8E-894D-4D74F32A6282'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '1E89D300-7F0D-4C94-9BA2-65F616951731'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'BeginsWith'
               WHERE ID = '1FC39118-F7F8-4BA7-9940-F341E35F4FDB'
               AND AutoUpdateUserSearchPredicate = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = 'CFB7315F-8759-4728-BD30-FAAE93F97106'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'CFB7315F-8759-4728-BD30-FAAE93F97106'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'CE9CE69A-95CF-4CF0-BDA8-F5F5E661A40B'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'F56AB0CB-EC8F-429A-A33F-BEDDC6BB9F67'
               AND AutoUpdateDefaultInView = 1;

            UPDATE [${mjSchema}].[Entity]
            SET AllowUserSearchAPI = 0
            WHERE ID = '317DF592-8C20-473D-B097-2AB239877438'
            AND AutoUpdateAllowUserSearchAPI = 1;

/* Set categories for 6 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B592F895-7E87-480A-8663-9D3C70F812D5' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'EECE216E-EC2B-4630-9E17-3FCDE668F32A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '3EC31CA1-A410-4A25-BB23-1E668A16A125' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0E2AB42B-29F2-4151-A424-ABA78BBA163B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'E7D55020-C93E-46B9-89E5-19088CBEDB0A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Types.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '26168480-7C59-4436-B954-4979F44F7014' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('0b578442-b41f-484b-827e-d47e4013c7bb', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'FieldCategoryInfo', '{"Contract Template Details":{"icon":"fa fa-file-contract","description":"Information defining the specific type of contract template"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('1296ce7e-6406-4540-887c-dad2b35d435e', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'FieldCategoryIcons', '{"Contract Template Details":"fa fa-file-contract","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 0, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0';

/* Set categories for 7 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '4796BC59-BF1A-41CF-83B5-29E8F8880C47' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '982E307B-667C-4955-99DE-F9A96FAB2CB2' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractTemplateProvisionID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Provision',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0864CB7F-E532-402F-9F16-102EC14993C6' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ModificationText 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Modification Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0D2FC779-82CA-4D68-A711-3D871A356164' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.Notes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Modification Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '87BB27CB-98B7-4704-BDC5-7871F8F394EB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '18518499-1DD3-4369-BD76-59B62EEBA5B8' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '54072096-C4E2-450C-97FA-BF162E2485D6' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('7c40ba9f-d702-4e58-a74f-51e0db251f13', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'FieldCategoryInfo', '{"Contract Association":{"icon":"fa fa-link","description":"Links the modification to the parent contract and specific template provision."},"Modification Details":{"icon":"fa fa-edit","description":"The specific text changes and supporting notes for the contract modification."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('0e258280-451a-4b0c-bcc4-19ae5309b564', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'FieldCategoryIcons', '{"Contract Association":"fa fa-link","Modification Details":"fa fa-edit","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* Set categories for 10 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9C8643D3-2B82-41A6-80F6-D29ABB68D1CB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '84119AD2-CBA8-466B-B20A-8A94C20FCE3F' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '46B195B4-EA25-41A4-BB78-83B2014A930C' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Type Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '59601A28-9AED-4E62-8B3B-EA21B769B9EB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.RequiresExecutedDocument 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '62AFA042-4658-4D78-B9C3-1BDD0B3997D4' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.MustBeRoot 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D252CC6D-3196-4616-AAEF-93FFC7CE6887' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.MustBeChild 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '04BA23CD-EC7A-495B-81DF-47474EF8C0EB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.TemplateRequired 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '444FC85A-BD7A-4967-8633-A4E1F8ACB4CE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '6A869A40-C89A-43F5-BC80-94A104E9FC46' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '68821111-317C-4AB8-922E-F1EC8AEA0973' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('d2d62a86-3c4a-442a-bc2c-a0498b5f5632', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'FieldCategoryInfo', '{"Contract Type Details":{"icon":"fa fa-info-circle","description":"Basic identification and status information for the contract type"},"Configuration Rules":{"icon":"fa fa-cogs","description":"Business logic and constraints governing contract behavior and placement"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('14088b52-f54b-47e4-bc16-9c4f325c7450', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'FieldCategoryIcons', '{"Contract Type Details":"fa fa-info-circle","Configuration Rules":"fa fa-cogs","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 0, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262';

/* Set categories for 10 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'DA55D974-F70E-42D0-A12A-04F2EFD46A85' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ContractTemplateID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FD673FEE-72AB-4109-89B1-DB5BCEE9EB3E' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ContractTemplate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'F56AB0CB-EC8F-429A-A33F-BEDDC6BB9F67' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ProvisionNumber 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'CFB7315F-8759-4728-BD30-FAAE93F97106' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.Title 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'CE9CE69A-95CF-4CF0-BDA8-F5F5E661A40B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ProvisionText 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D2CD9029-4DB4-4AD1-85A2-ABBFDA35EAFD' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provision Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '1BFDA475-470F-4F3C-8B5D-B0DBDCED2EE3' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.ProvisionSortKey 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   DisplayName = 'Sort Key',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '2E082EBC-4A00-4C39-8F6D-F7B680F5B345' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '6B098C7F-9119-4C60-94B5-CA2ACA14309F' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Provisions.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9F515EDD-BE69-4955-9C10-EB1819DDFD2C' AND AutoUpdateCategory = 1;

/* Set categories for 11 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'A8BF5461-4A41-4388-8761-50B79FC598B4' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.Name 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '1FC39118-F7F8-4BA7-9940-F341E35F4FDB' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ContractTemplateTypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Template Type ID',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '7B8EC82E-CF52-4F4C-980D-47A15194EA12' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.ContractTemplateType 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Template Type',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '1E89D300-7F0D-4C94-9BA2-65F616951731' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.VersionLabel 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Template Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '7F9A6927-CA1D-441B-9682-7035C95393D8' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.IntroducedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Lifecycle and Access',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D20B1F02-4F4B-4A8E-894D-4D74F32A6282' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.SourceURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Lifecycle and Access',
   GeneratedFormSection = 'Category',
   ExtendedType = 'URL',
   CodeType = NULL
WHERE 
   ID = '5F27FB9A-A089-46CE-A332-F7E7DE745BCF' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.Status 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Lifecycle and Access',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'E586DB3A-8FCA-424F-BB0F-AE34BE10C686' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Templates.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B0E8E57C-69A5-4A3F-BAD2-CCBF75F2FF30' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '731F2890-1415-40DE-9073-D22EA23392B3';

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '317DF592-8C20-473D-B097-2AB239877438';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('b676e178-ea28-4c40-b59e-a0cb7e1a6d4c', '731F2890-1415-40DE-9073-D22EA23392B3', 'FieldCategoryInfo', '{"Template Details":{"icon":"fa fa-info-circle","description":"Core identifying information and classification for the contract template"},"Lifecycle and Access":{"icon":"fa fa-history","description":"Information regarding template availability, publication status, and public access links"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('f09f4e8e-415b-49d6-8c5b-2f31320e2b2a', '317DF592-8C20-473D-B097-2AB239877438', 'FieldCategoryInfo', '{"Template Association":{"icon":"fa fa-link","description":"Links the provision to the specific contract template version"},"Provision Details":{"icon":"fa fa-align-left","description":"Core content, numbering, and descriptive information for the contract clause"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit, sorting, and identification fields"}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('04cd7a19-f678-4e64-a3a3-21af4d94c378', '317DF592-8C20-473D-B097-2AB239877438', 'FieldCategoryIcons', '{"Template Association":"fa fa-link","Provision Details":"fa fa-align-left","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('4fca29d1-19bb-45a4-ada3-2a2c25d24d78', '731F2890-1415-40DE-9073-D22EA23392B3', 'FieldCategoryIcons', '{"Template Details":"fa fa-info-circle","Lifecycle and Access":"fa fa-history","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '731F2890-1415-40DE-9073-D22EA23392B3';

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '317DF592-8C20-473D-B097-2AB239877438';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET IsNameField = 1
               WHERE ID = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND AutoUpdateIsNameField = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '5605AB79-A11A-4561-8B34-B7567A36F27A'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '343BECBD-079B-443A-998C-2E7DDCCD8A01'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '14BDA941-CE85-4A14-8FDC-3681B8C52418'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '8FBC1AAC-1342-4584-991F-AAB1C31CE673'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET IncludeInUserSearchAPI = 1
               WHERE ID = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND AutoUpdateIncludeInUserSearchAPI = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET UserSearchPredicateAPI = 'Exact'
               WHERE ID = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND AutoUpdateUserSearchPredicate = 1;

/* Set categories for 31 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '04E8AA9D-C2DC-489D-B081-75C4E6DDFA6B' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractNumber 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8677055B-2482-4250-98C1-AFC3DAE57393' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTypeID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Type',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'DF26A6B1-EB6C-42D8-B236-CD13F58C9B78' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractType 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Type Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '14BDA941-CE85-4A14-8FDC-3681B8C52418' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CompanyID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Selling Company',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'BAD7AA2F-EE2B-430A-B182-B7E4B7E09F8A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Company 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Company Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'A2B9A232-351C-4CF9-A050-6F059F146806' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CustomerOrganizationID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Customer Organization',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'F11C9543-F483-4BED-A9CE-3E7659D24011' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CustomerOrganization 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Customer Organization Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8FBC1AAC-1342-4584-991F-AAB1C31CE673' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.PrimaryContactPersonID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Primary Contact Person',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D47233ED-0EBF-4329-B270-99F70589CD7F' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.PrimaryContactPerson 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Stakeholders',
   GeneratedFormSection = 'Category',
   DisplayName = 'Primary Contact Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '2999F51A-9170-4028-B142-2F33D7E056ED' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTemplateID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ContractTemplate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '3DF1FCCC-6C4F-4CEF-ABEC-836517BA655A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingEntityID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   DisplayName = 'Creating Entity',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '316A9F07-54F1-4038-862A-C25A2084F274' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingEntity 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   DisplayName = 'Creating Entity Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'B35327D2-0775-4CD2-9D4A-0FA1A2C98AA0' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CreatingRecordID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Provenance',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '611650F5-BFC3-4809-B9B1-80AC9979B450' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ParentContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Parent Contract',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '6DB0692A-42CD-4AC5-A43B-49ECC81EF370' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.SupersededByContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Lifecycle',
   GeneratedFormSection = 'Category',
   DisplayName = 'Superseded By',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '44BC44EF-A6F2-4630-A899-487CE0E3CC56' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.SigningProviderURL 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   ExtendedType = 'URL',
   CodeType = NULL
WHERE 
   ID = '131CE82F-AC93-4DCF-95C0-3EA4FC681C2C' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.EffectiveDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '5605AB79-A11A-4561-8B34-B7567A36F27A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.ExecutedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9ED4A8CC-E0B8-4880-945A-4BD6DD6368C6' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.EndDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '343BECBD-079B-443A-998C-2E7DDCCD8A01' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.TerminatedDate 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Dates and Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D312F0C4-AD4D-4F0B-B54A-1051EC735464' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.AutoRenew 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8B3C517C-FF01-4121-A740-632DF75F3C05' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.RenewalNoticeDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '573064AC-38A8-42A2-95B2-CCBD605004EA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.CancellationWindowDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C6464ADC-6683-4D4B-AA7A-64F9E052D225' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.AnnualIncreasePercent 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Renewal Terms',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '3B2625E1-C5AB-462C-AA7E-533C5F40646D' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.HasModifications 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Details',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'D54DDEBD-615B-4D29-A995-246C3C0F7408' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Description 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Notes and Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '30B733E2-70E1-4D55-BA83-73FEDBA848FA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.Notes 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Notes and Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '68E70227-D818-4F11-8FE4-553F5C84BE53' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '7C14348E-69DE-4F66-B62C-99C0A7E415AF' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'System Metadata',
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '0EBA35EC-FB3D-4978-8650-FC6229A9180E' AND AutoUpdateCategory = 1;

/* Set entity icon to fa fa-file-contract */

               UPDATE [${mjSchema}].[Entity]
               SET [Icon] = 'fa fa-file-contract', [__mj_UpdatedAt] = GETUTCDATE()
               WHERE [ID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';

/* Insert FieldCategoryInfo setting for entity */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('9921cd66-81de-40a8-b6ad-2e814ffc09b9', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'FieldCategoryInfo', '{"Contract Details":{"icon":"fa fa-file-contract","description":"Core information regarding the contract agreement, type, and document links."},"Stakeholders":{"icon":"fa fa-users","description":"Entities and individuals involved in the contract."},"Provenance":{"icon":"fa fa-project-diagram","description":"References to the source records that created this contract."},"Contract Lifecycle":{"icon":"fa fa-sync","description":"Relationships defining amendments and contract replacements."},"Dates and Terms":{"icon":"fa fa-calendar-alt","description":"Key dates governing the contract term and execution."},"Renewal Terms":{"icon":"fa fa-redo","description":"Renewal conditions, notice periods, and price adjustments."},"Notes and Metadata":{"icon":"fa fa-align-left","description":"Additional context and internal notes."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking information."}}', GETUTCDATE(), GETUTCDATE());

/* Insert FieldCategoryIcons setting (legacy) */

               INSERT INTO [${mjSchema}].[EntitySetting] ([ID], [EntityID], [Name], [Value], [__mj_CreatedAt], [__mj_UpdatedAt])
               VALUES ('710847a6-de1d-4884-81db-bde4530e9a74', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'FieldCategoryIcons', '{"Contract Details":"fa fa-file-contract","Stakeholders":"fa fa-users","Provenance":"fa fa-project-diagram","Contract Lifecycle":"fa fa-sync","Dates and Terms":"fa fa-calendar-alt","Renewal Terms":"fa fa-redo","Notes and Metadata":"fa fa-align-left","System Metadata":"fa fa-cog"}', GETUTCDATE(), GETUTCDATE());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */

         UPDATE [${mjSchema}].[ApplicationEntity]
         SET [DefaultForNewUser] = 1, [__mj_UpdatedAt] = GETUTCDATE()
         WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Template Modifications */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Template Modifications: Field: ModificationText was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '(len(ltrim(rtrim([ModificationText])))>(0))', 'public ValidateModificationTextNotEmpty(result: ValidationResult) {
	if (this.ModificationText == null || this.ModificationText.trim().length === 0) {
		result.Errors.push(new ValidationErrorInfo(
			"ModificationText",
			"Modification text cannot be empty or contain only whitespace.",
			this.ModificationText,
			ValidationErrorType.Failure
		));
	}
}', 'The modification text must contain actual text and cannot be empty or consist only of spaces.', 'ValidateModificationTextNotEmpty', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '0D2FC779-82CA-4D68-A711-3D871A356164');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Template Provisions */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Template Provisions: Field: ProvisionText was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '(len(ltrim(rtrim([ProvisionText])))>(0))', 'public ValidateProvisionTextNotEmpty(result: ValidationResult) {
	if (this.ProvisionText === undefined || this.ProvisionText === null || this.ProvisionText.trim().length === 0) {
		result.Errors.push(new ValidationErrorInfo(
			"ProvisionText",
			"Provision text cannot be empty or consist only of spaces.",
			this.ProvisionText,
			ValidationErrorType.Failure
		));
	}
}', 'The provision text cannot be empty or consist only of spaces. It must contain actual text content.', 'ValidateProvisionTextNotEmpty', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'D2CD9029-4DB4-4AD1-85A2-ABBFDA35EAFD');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Types */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Types @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '(NOT ([MustBeRoot]=(1) AND [MustBeChild]=(1)))', 'public ValidateRootAndChildExclusivity(result: ValidationResult) {
	if (this.MustBeRoot && this.MustBeChild) {
		result.Errors.push(new ValidationErrorInfo(
			"MustBeRoot",
			"An entity cannot be designated as both a root and a child at the same time.",
			this.MustBeRoot,
			ValidationErrorType.Failure
		));
	}
}', 'An entity cannot be designated as both a root and a child at the same time.', 'ValidateRootAndChildExclusivity', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', 'C8909A57-6DDB-4585-BE00-E707C5B4F262');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contracts */
-- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: AnnualIncreasePercent was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([AnnualIncreasePercent] IS NULL OR [AnnualIncreasePercent]>=(0))', 'public ValidateAnnualIncreasePercentNonNegative(result: ValidationResult) {
	if (this.AnnualIncreasePercent != null && this.AnnualIncreasePercent < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"AnnualIncreasePercent",
			"Annual increase percentage must be greater than or equal to 0.",
			this.AnnualIncreasePercent,
			ValidationErrorType.Failure
		));
	}
}', 'The annual increase percentage must be greater than or equal to zero, ensuring that contract rates do not decrease automatically.', 'ValidateAnnualIncreasePercentNonNegative', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '3B2625E1-C5AB-462C-AA7E-533C5F40646D');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: CancellationWindowDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([CancellationWindowDays] IS NULL OR [CancellationWindowDays]>=(0))', 'public ValidateCancellationWindowDaysGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.CancellationWindowDays != null && this.CancellationWindowDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"CancellationWindowDays",
			"Cancellation window days must be 0 or a positive number.",
			this.CancellationWindowDays,
			ValidationErrorType.Failure
		));
	}
}', 'The cancellation window days must be zero or a positive number, ensuring that we do not record a negative number of days for the contract cancellation period.', 'ValidateCancellationWindowDaysGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'C6464ADC-6683-4D4B-AA7A-64F9E052D225');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts: Field: RenewalNoticeDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([RenewalNoticeDays] IS NULL OR [RenewalNoticeDays]>=(0))', 'public ValidateRenewalNoticeDaysGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.RenewalNoticeDays != null && this.RenewalNoticeDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"RenewalNoticeDays",
			"Renewal notice days must be 0 or greater.",
			this.RenewalNoticeDays,
			ValidationErrorType.Failure
		));
	}
}', 'Renewal notice days must be 0 or greater, if specified.', 'ValidateRenewalNoticeDaysGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '573064AC-38A8-42A2-95B2-CCBD605004EA');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([CreatingEntityID] IS NULL AND [CreatingRecordID] IS NULL OR [CreatingEntityID] IS NOT NULL AND [CreatingRecordID] IS NOT NULL)', 'public ValidateCreatingEntityAndRecordCoexistence(result: ValidationResult) {
	const hasEntity = this.CreatingEntityID != null;
	const hasRecord = this.CreatingRecordID != null && this.CreatingRecordID !== "";

	if (hasEntity !== hasRecord) {
		result.Errors.push(new ValidationErrorInfo(
			"CreatingEntityID",
			"Creating Entity ID and Creating Record ID must either both be specified or both be empty.",
			this.CreatingEntityID,
			ValidationErrorType.Failure
		));
	}
}', 'Both Creating Entity ID and Creating Record ID must be provided together, or both must be left empty, to ensure consistent tracking of the source entity and record.', 'ValidateCreatingEntityAndRecordCoexistence', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([EndDate] IS NULL OR [EffectiveDate] IS NULL OR [EndDate]>=[EffectiveDate])', 'public ValidateEndDateAfterOrEqualToEffectiveDate(result: ValidationResult) {
    if (this.EndDate != null && this.EffectiveDate != null) {
        if (this.EndDate < this.EffectiveDate) {
            result.Errors.push(new ValidationErrorInfo(
                "EndDate",
                "The contract End Date must be on or after the Effective Date.",
                this.EndDate,
                ValidationErrorType.Failure
            ));
        }
    }
}', 'The contract end date must be on or after the effective date to ensure logical date ordering.', 'ValidateEndDateAfterOrEqualToEffectiveDate', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([ParentContractID] IS NULL OR [ParentContractID]<>[ID])', 'public ValidateParentContractIDNotEqualToID(result: ValidationResult) {
	if (this.ParentContractID != null && this.ParentContractID === this.ID) {
		result.Errors.push(new ValidationErrorInfo(
			"ParentContractID",
			"A contract cannot be its own parent contract.",
			this.ParentContractID,
			ValidationErrorType.Failure
		));
	}
}', 'A contract cannot be its own parent contract to prevent circular references in the contract hierarchy.', 'ValidateParentContractIDNotEqualToID', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

            -- CHECK constraint for MJ_BizApps_Contracts: Contracts @ Table Level was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
INSERT INTO [${mjSchema}].[GeneratedCode] ([CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
                      VALUES ((SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([SupersededByContractID] IS NULL OR [SupersededByContractID]<>[ID])', 'public ValidateSupersededByContractIDNotEqualToID(result: ValidationResult) {
	if (this.SupersededByContractID != null && this.SupersededByContractID === this.ID) {
		result.Errors.push(new ValidationErrorInfo(
			"SupersededByContractID",
			"A contract cannot be superseded by itself. Please select a different contract.",
			this.SupersededByContractID,
			ValidationErrorType.Failure
		));
	}
}', 'A contract cannot be superseded by itself. The superseding contract must be a different contract record.', 'ValidateSupersededByContractIDNotEqualToID', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

