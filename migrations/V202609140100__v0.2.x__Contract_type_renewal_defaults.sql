-- =============================================================================
-- V202609140100 — renewal-obligation DEFAULTS on ContractType.
-- =============================================================================
-- Golive #217 (story C-US1, #99). C-US1 says the renewal-obligation fields on a
-- new contract are seeded from the selected Contract Type, and re-seeded when the
-- type is changed before saving. Nothing implemented it: ContractType carried no
-- default columns at all, so finance typed all four fields by hand on every
-- contract, including the ones where the type already determines the answer.
--
-- These four columns are a STARTING POINT, NOT A RULE, and the distinction is the
-- whole design. Nothing reads them at save time; no validation consults them; a
-- contract may state anything the paper states. They are copied into the contract
-- ONCE, at the moment a type is picked on an UNSAVED record, and from then on the
-- contract's own values are the only ones that matter. That is what separates
-- them from the type's three existing RULE columns (MustBeRoot, MustBeChild,
-- TemplateRequired), which ContractEntityServer enforces on every save.
--
-- WHY THIS IS NOT A REVERSAL OF THE v2 REBUILD. v1 seeded six types with fourteen
-- columns of billing defaults — term months, billing frequency, escalation
-- percents, renewal mode, coterm — and the rebuild deleted all of it because v2
-- does not bill and does not renew on a schedule (see the note in
-- metadata/contract-types/.contract-types.json). The deletion was about the
-- system DECIDING things from a type. Pre-filling a form the user then edits
-- decides nothing, and the four seeded types ship with these columns NULL, so an
-- install that never touches the Configuration page behaves exactly as it does
-- today.
--
-- DefaultAutoRenew IS NULLABLE, unlike Contract.AutoRenew which it seeds. A bit
-- has two values and the type needs three answers: renews, does not renew, and NO
-- OPINION — leave whatever the contract already says. A NOT NULL default would
-- have made every type assert something about auto-renewal whether or not anyone
-- had considered it, and "0 because nobody set it" is indistinguishable from "0
-- because a Payment Link genuinely never renews". NULL means this column does not
-- participate in seeding; that is the state every existing row starts in.
--
-- The three numeric defaults mirror their Contract counterparts exactly — INT,
-- DECIMAL(7,4), and the same >= 0 CHECKs — because a value that is legal on the
-- type and illegal on the contract would seed a record that cannot be saved.
-- =============================================================================

---------------------------------------------------------------------------
-- The columns, in ONE statement with their constraints.
--
-- No IF guards anywhere in this file, and that is the convention rather than
-- an oversight: migrations always run in order and exactly once, so a script
-- never has to defend itself against a database that already has its changes.
-- Guards are noise, and they make the PostgreSQL conversion harder.
--
-- The three numeric floors mirror CK_Contract_* on the columns these seed. A
-- negative notice period is not a shorter one, it is a data entry error, and
-- catching it on the TYPE means catching it once rather than on every contract
-- the type seeds.
---------------------------------------------------------------------------
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD
    [DefaultAutoRenew] BIT NULL,
    [DefaultRenewalNoticeDays] INT NULL,
    [DefaultCancellationWindowDays] INT NULL,
    [DefaultAnnualIncreasePercent] DECIMAL(7,4) NULL,
    CONSTRAINT [CK_ContractType_DefaultRenewalNoticeDays]
        CHECK ([DefaultRenewalNoticeDays] IS NULL OR [DefaultRenewalNoticeDays] >= 0),
    CONSTRAINT [CK_ContractType_DefaultCancellationWindow]
        CHECK ([DefaultCancellationWindowDays] IS NULL OR [DefaultCancellationWindowDays] >= 0),
    CONSTRAINT [CK_ContractType_DefaultAnnualIncrease]
        CHECK ([DefaultAnnualIncreasePercent] IS NULL OR [DefaultAnnualIncreasePercent] >= 0);
GO

---------------------------------------------------------------------------
-- Descriptions. CodeGen copies these onto the EntityField rows, so this is the
-- text an admin reads on the Contract Type form -- the only place the
-- "starting point, not a rule" distinction can be stated where it is read.
---------------------------------------------------------------------------
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultAutoRenew';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultRenewalNoticeDays';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultCancellationWindowDays';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultAnnualIncreasePercent';
GO


















































-- =============================================================================
-- CodeGen capture — everything below this line is GENERATED. Replace it wholesale
-- on regeneration; see docs/database-migrations.md § the 50-blank-line rule.
--
-- Captured from a FROM-ZERO replay: the whole contracts train applied to a clean
-- database carrying MJ core + bizapps-common, then `mj sync push --dir metadata`,
-- then `mj codegen` — in that order. The push has to land before CodeGen runs,
-- or CodeGen reads settings that are not there yet and regenerates without them.
--
-- Note what is NOT here, and why. CodeGen emits no `Update FieldCategory…`
-- statements any more: the field-category setting lives in
-- `metadata/entity-settings/` and was already in the database when this ran, so
-- there was nothing for CodeGen to generate. An earlier draft of this migration
-- hand-wrote that setting as SQL, which is exactly what the metadata folder is
-- for. The four fields' `Category` is metadata for the same reason and lives in
-- `metadata/entity-fields/.default-contract-terms-category.json`; a host receives
-- both through the release-time Metadata_Sync, not through this file.
-- =============================================================================
/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to insert 4 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0e84b4a9-1d67-4563-a5a0-ef4f75c80694' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultAutoRenew')) BEGIN
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
            '0e84b4a9-1d67-4563-a5a0-ef4f75c80694',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'DefaultAutoRenew',
            'Default Auto Renew',
            'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.',
            'bit',
            1,
            1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e9a6cb34-2b1c-44a9-8260-d7e14c7b1f49' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultRenewalNoticeDays')) BEGIN
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
            'e9a6cb34-2b1c-44a9-8260-d7e14c7b1f49',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'DefaultRenewalNoticeDays',
            'Default Renewal Notice Days',
            'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '111cfb1b-1efb-4e60-a79d-41a391ef596a' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultCancellationWindowDays')) BEGIN
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
            '111cfb1b-1efb-4e60-a79d-41a391ef596a',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'DefaultCancellationWindowDays',
            'Default Cancellation Window Days',
            'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'da53b111-bc39-49f6-bcfb-55380e260227' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultAnnualIncreasePercent')) BEGIN
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
            'da53b111-bc39-49f6-bcfb-55380e260227',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'DefaultAnnualIncreasePercent',
            'Default Annual Increase Percent',
            'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.',
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

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

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
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_UI]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Integration]
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

REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_UI]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Integration]
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
    @TemplateRequired bit = NULL,
    @DefaultAutoRenew_Clear bit = 0,
    @DefaultAutoRenew bit = NULL,
    @DefaultRenewalNoticeDays_Clear bit = 0,
    @DefaultRenewalNoticeDays int = NULL,
    @DefaultCancellationWindowDays_Clear bit = 0,
    @DefaultCancellationWindowDays int = NULL,
    @DefaultAnnualIncreasePercent_Clear bit = 0,
    @DefaultAnnualIncreasePercent decimal(7, 4) = NULL
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
                [TemplateRequired],
                [DefaultAutoRenew],
                [DefaultRenewalNoticeDays],
                [DefaultCancellationWindowDays],
                [DefaultAnnualIncreasePercent]
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
                ISNULL(@TemplateRequired, 0),
                CASE WHEN @DefaultAutoRenew_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAutoRenew, NULL) END,
                CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, NULL) END,
                CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, NULL) END,
                CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, NULL) END
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
                [TemplateRequired],
                [DefaultAutoRenew],
                [DefaultRenewalNoticeDays],
                [DefaultCancellationWindowDays],
                [DefaultAnnualIncreasePercent]
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
                ISNULL(@TemplateRequired, 0),
                CASE WHEN @DefaultAutoRenew_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAutoRenew, NULL) END,
                CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, NULL) END,
                CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, NULL) END,
                CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Integration]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Developer]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Types */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Integration]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Developer]
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
    @TemplateRequired bit = NULL,
    @DefaultAutoRenew_Clear bit = 0,
    @DefaultAutoRenew bit = NULL,
    @DefaultRenewalNoticeDays_Clear bit = 0,
    @DefaultRenewalNoticeDays int = NULL,
    @DefaultCancellationWindowDays_Clear bit = 0,
    @DefaultCancellationWindowDays int = NULL,
    @DefaultAnnualIncreasePercent_Clear bit = 0,
    @DefaultAnnualIncreasePercent decimal(7, 4) = NULL
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
        [TemplateRequired] = ISNULL(@TemplateRequired, [TemplateRequired]),
        [DefaultAutoRenew] = CASE WHEN @DefaultAutoRenew_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAutoRenew, [DefaultAutoRenew]) END,
        [DefaultRenewalNoticeDays] = CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, [DefaultRenewalNoticeDays]) END,
        [DefaultCancellationWindowDays] = CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, [DefaultCancellationWindowDays]) END,
        [DefaultAnnualIncreasePercent] = CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, [DefaultAnnualIncreasePercent]) END
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

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Integration]
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

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: vwContractsGenerated
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
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractsGenerated]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractsGenerated];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractsGenerated]
AS
SELECT
    c.*,
    mjBizAppsContractsContractType_ContractTypeID.[Name] AS [ContractType],
    MJCompany_CompanyID.[Name] AS [Company],
    mjBizAppsCommonOrganization_CustomerOrganizationID.[Name] AS [CustomerOrganization],
    mjBizAppsCommonPerson_PrimaryContactPersonID.[DisplayName] AS [PrimaryContactPerson],
    mjBizAppsContractsContractTemplate_ContractTemplateID.[Name] AS [ContractTemplate],
    MJEntity_CreatingEntityID.[Name] AS [CreatingEntity],
    mjBizAppsContractsContract_ParentContractID.[ContractNumber] AS [ParentContract],
    mjBizAppsContractsContract_SupersededByContractID.[ContractNumber] AS [SupersededByContract]
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
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_ParentContractID
  ON
    [c].[ParentContractID] = mjBizAppsContractsContract_ParentContractID.[ID]
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_SupersededByContractID
  ON
    [c].[SupersededByContractID] = mjBizAppsContractsContract_SupersededByContractID.[ID]
GO
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_UI]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Developer]
GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
END;

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_UI]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Developer]
GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
END;

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
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contracts */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] FROM [cdp_Integration]
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

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] FROM [cdp_Integration]
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

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration];

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
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Types */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

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
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contracts */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* SQL text to delete unneeded entity fields (2 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to update existing entity fields from schema (2 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Refresh custom base views for modified entities so schema changes are picked up */
EXEC sp_refreshview '${flyway:defaultSchema}.vwContractsGenerated';
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'EXEC sp_refreshview ''${flyway:defaultSchema}.vwContracts'';';
END;
