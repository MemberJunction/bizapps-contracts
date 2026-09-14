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
-- 1 · The columns. Idempotent: COL_LENGTH returns NULL for a column that is
--     not there, and the whole block is skipped on a database that has them.
---------------------------------------------------------------------------
IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'DefaultAutoRenew') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [DefaultAutoRenew] BIT NULL;
GO

IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'DefaultRenewalNoticeDays') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [DefaultRenewalNoticeDays] INT NULL;
GO

IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'DefaultCancellationWindowDays') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [DefaultCancellationWindowDays] INT NULL;
GO

IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'DefaultAnnualIncreasePercent') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [DefaultAnnualIncreasePercent] DECIMAL(7,4) NULL;
GO

---------------------------------------------------------------------------
-- 2 · The same floors the contract's own columns carry (CK_Contract_*). A
--     negative notice period is not a shorter one, it is a data entry error,
--     and catching it on the TYPE means it is caught once rather than on every
--     contract the type seeds.
---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [name] = 'CK_ContractType_DefaultRenewalNoticeDays')
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [CK_ContractType_DefaultRenewalNoticeDays]
        CHECK ([DefaultRenewalNoticeDays] IS NULL OR [DefaultRenewalNoticeDays] >= 0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [name] = 'CK_ContractType_DefaultCancellationWindow')
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [CK_ContractType_DefaultCancellationWindow]
        CHECK ([DefaultCancellationWindowDays] IS NULL OR [DefaultCancellationWindowDays] >= 0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE [name] = 'CK_ContractType_DefaultAnnualIncrease')
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [CK_ContractType_DefaultAnnualIncrease]
        CHECK ([DefaultAnnualIncreasePercent] IS NULL OR [DefaultAnnualIncreasePercent] >= 0);
GO

---------------------------------------------------------------------------
-- 3 · Descriptions. CodeGen copies these onto the EntityField rows, so this is
--     the text an admin reads on the Contract Type form — the only place the
--     "starting point, not a rule" distinction can be stated where it is read.
--     Guarded individually: a re-run must not fail on a property already there.
---------------------------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties ep
    WHERE ep.major_id = OBJECT_ID('${flyway:defaultSchema}.ContractType')
      AND ep.minor_id = COLUMNPROPERTY(OBJECT_ID('${flyway:defaultSchema}.ContractType'), 'DefaultAutoRenew', 'ColumnId')
      AND ep.[name] = 'MS_Description')
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultAutoRenew';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties ep
    WHERE ep.major_id = OBJECT_ID('${flyway:defaultSchema}.ContractType')
      AND ep.minor_id = COLUMNPROPERTY(OBJECT_ID('${flyway:defaultSchema}.ContractType'), 'DefaultRenewalNoticeDays', 'ColumnId')
      AND ep.[name] = 'MS_Description')
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultRenewalNoticeDays';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties ep
    WHERE ep.major_id = OBJECT_ID('${flyway:defaultSchema}.ContractType')
      AND ep.minor_id = COLUMNPROPERTY(OBJECT_ID('${flyway:defaultSchema}.ContractType'), 'DefaultCancellationWindowDays', 'ColumnId')
      AND ep.[name] = 'MS_Description')
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultCancellationWindowDays';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.extended_properties ep
    WHERE ep.major_id = OBJECT_ID('${flyway:defaultSchema}.ContractType')
      AND ep.minor_id = COLUMNPROPERTY(OBJECT_ID('${flyway:defaultSchema}.ContractType'), 'DefaultAnnualIncreasePercent', 'ColumnId')
      AND ep.[name] = 'MS_Description')
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'DefaultAnnualIncreasePercent';
GO

---------------------------------------------------------------------------
-- 4 · The form section these four fields live in, MERGED rather than replaced.
--
--     ⚠ THIS BLOCK IS HAND-WRITTEN AND THE CAPTURE BELOW HAS BEEN TRIMMED TO
--     MATCH. CodeGen emitted its own pair of UPDATEs here, and both set the
--     WHOLE `FieldCategoryInfo` / `FieldCategoryIcons` JSON to the one category
--     it had just generated — dropping `Contract Type Details`, `Configuration
--     Rules` and `System Metadata`, which the baseline seeds (B…Baseline.sql
--     lines 8601 and 8606) and the generated form reads for each section's icon
--     and description. Applying it as emitted would silently strip three
--     sections' chrome on every install. The two statements were therefore
--     REMOVED from the capture and replaced by the merge below.
--
--     Anyone re-capturing this migration must do the same: regenerate, delete
--     CodeGen's two `Update FieldCategory…` statements, and leave this block
--     standing. Filed upstream; until it is fixed the trim is the fix.
---------------------------------------------------------------------------
DECLARE @ContractTypeEntityID UNIQUEIDENTIFIER =
    (SELECT TOP 1 [ID] FROM [${mjSchema}].[Entity]
      WHERE [SchemaName] = '${flyway:defaultSchema}' AND [BaseTable] = 'ContractType');

-- Looked up by NAME, never by a literal: CodeGen mints the Entity id at first
-- registration, so it differs between databases. Skips cleanly when the row is
-- absent — on a fresh install CodeGen's own registration runs in the capture below.
IF @ContractTypeEntityID IS NOT NULL
BEGIN
    UPDATE [${mjSchema}].[EntitySetting]
       SET [Value] = N'{"Contract Type Details":{"icon":"fa fa-info-circle","description":"Basic identification and status information for the contract type"},"Configuration Rules":{"icon":"fa fa-cogs","description":"Business logic and constraints governing contract behavior and placement"},"Default Contract Terms":{"icon":"fa fa-sliders-h","description":"Default renewal terms copied onto a new contract of this type. A starting point the user may change, not a rule."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}',
           [__mj_UpdatedAt] = GETUTCDATE()
     WHERE [EntityID] = @ContractTypeEntityID AND [Name] = 'FieldCategoryInfo';

    UPDATE [${mjSchema}].[EntitySetting]
       SET [Value] = N'{"Contract Type Details":"fa fa-info-circle","Configuration Rules":"fa fa-cogs","Default Contract Terms":"fa fa-sliders-h","System Metadata":"fa fa-cog"}',
           [__mj_UpdatedAt] = GETUTCDATE()
     WHERE [EntityID] = @ContractTypeEntityID AND [Name] = 'FieldCategoryIcons';
END
GO


















































-- =============================================================================
-- CodeGen capture — everything below this line is GENERATED. Replace it wholesale
-- on regeneration; see docs/database-migrations.md § the 50-blank-line rule.
--
-- TRIMMED, deliberately: CodeGen's two `Update FieldCategory…` statements were
-- removed and replaced by the hand-written merge in step 4 above. Re-apply that
-- trim every time this capture is regenerated.
-- =============================================================================
/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to insert 4 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '37ef1ace-158d-4b02-9731-ac989b80ab64' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultAutoRenew')) BEGIN
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
            '37ef1ace-158d-4b02-9731-ac989b80ab64',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '886e3bf0-6f99-4bad-b049-d19d34897288' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultRenewalNoticeDays')) BEGIN
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
            '886e3bf0-6f99-4bad-b049-d19d34897288',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1289ff74-772b-4e77-b68d-5fef1e798e0a' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultCancellationWindowDays')) BEGIN
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
            '1289ff74-772b-4e77-b68d-5fef1e798e0a',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b5b42453-03af-4806-8b87-7e80d7c78164' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'DefaultAnnualIncreasePercent')) BEGIN
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
            'b5b42453-03af-4806-8b87-7e80d7c78164',
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
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_UI]
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

REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContractTypes] FROM [cdp_UI]
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
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Types */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] FROM [cdp_Integration]
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

/* SQL text to delete unneeded entity fields (1 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='C8909A57-6DDB-4585-BE00-E707C5B4F262', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to update existing entity fields from schema (1 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='C8909A57-6DDB-4585-BE00-E707C5B4F262', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Set categories for 4 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.DefaultAutoRenew 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Default Contract Terms',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '37EF1ACE-158D-4B02-9731-AC989B80AB64';

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.DefaultRenewalNoticeDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Default Contract Terms',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '886E3BF0-6F99-4BAD-B049-D19D34897288';

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.DefaultCancellationWindowDays 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Default Contract Terms',
   GeneratedFormSection = 'Category'
WHERE 
   ID = '1289FF74-772B-4E77-B68D-5FEF1E798E0A';

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.DefaultAnnualIncreasePercent 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Default Contract Terms',
   GeneratedFormSection = 'Category'
WHERE 
   ID = 'B5B42453-03AF-4806-8B87-7E80D7C78164';

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Types */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultAnnualIncreasePercent was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[GeneratedCode] WHERE [CategoryID] = (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators') AND [LinkedEntityID] = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND [LinkedRecordPrimaryKey] = 'B5B42453-03AF-4806-8B87-7E80D7C78164'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[GeneratedCode] ([ID], [CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
VALUES ('7f9d40d2-25e3-452d-a404-da56d0831ee1', (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([DefaultAnnualIncreasePercent] IS NULL OR [DefaultAnnualIncreasePercent]>=(0))', 'public ValidateDefaultAnnualIncreasePercentGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.DefaultAnnualIncreasePercent != null && this.DefaultAnnualIncreasePercent < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultAnnualIncreasePercent",
			"Default annual increase percentage must be greater than or equal to 0.",
			this.DefaultAnnualIncreasePercent,
			ValidationErrorType.Failure
		));
	}
}', 'The default annual increase percentage must be greater than or equal to 0% if it is specified.', 'ValidateDefaultAnnualIncreasePercentGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'B5B42453-03AF-4806-8B87-7E80D7C78164')
   END;

-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultCancellationWindowDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[GeneratedCode] WHERE [CategoryID] = (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators') AND [LinkedEntityID] = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND [LinkedRecordPrimaryKey] = '1289FF74-772B-4E77-B68D-5FEF1E798E0A'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[GeneratedCode] ([ID], [CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
VALUES ('24722a93-596a-4b57-8b31-5b027411061d', (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([DefaultCancellationWindowDays] IS NULL OR [DefaultCancellationWindowDays]>=(0))', 'public ValidateDefaultCancellationWindowDaysMin(result: ValidationResult) {
	if (this.DefaultCancellationWindowDays != null && this.DefaultCancellationWindowDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultCancellationWindowDays",
			"The default cancellation window days must be 0 or greater.",
			this.DefaultCancellationWindowDays,
			ValidationErrorType.Failure
		));
	}
}', 'The default cancellation window days, if specified, must be a non-negative number (0 or greater).', 'ValidateDefaultCancellationWindowDaysMin', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '1289FF74-772B-4E77-B68D-5FEF1E798E0A')
   END;

-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultRenewalNoticeDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[GeneratedCode] WHERE [CategoryID] = (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators') AND [LinkedEntityID] = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND [LinkedRecordPrimaryKey] = '886E3BF0-6F99-4BAD-B049-D19D34897288'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[GeneratedCode] ([ID], [CategoryID], [GeneratedByModelID], [GeneratedAt], [Language], [Status], [Source], [Code], [Description], [Name], [LinkedEntityID], [LinkedRecordPrimaryKey])
VALUES ('60cbce5b-012b-49c5-b94f-4445a99f00ec', (SELECT [ID] FROM [${mjSchema}].[vwGeneratedCodeCategories] WHERE [Name]='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', GETUTCDATE(), 'TypeScript', 'Approved', '([DefaultRenewalNoticeDays] IS NULL OR [DefaultRenewalNoticeDays]>=(0))', 'public ValidateDefaultRenewalNoticeDaysMin(result: ValidationResult) {
	if (this.DefaultRenewalNoticeDays != null && this.DefaultRenewalNoticeDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultRenewalNoticeDays",
			"Default renewal notice days must be 0 or greater.",
			this.DefaultRenewalNoticeDays,
			ValidationErrorType.Failure
		));
	}
}', 'The default renewal notice days, if specified, must be 0 or greater to ensure a valid notice period.', 'ValidateDefaultRenewalNoticeDaysMin', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '886E3BF0-6F99-4BAD-B049-D19D34897288')
   END;
