-- =============================================================================
-- V202611021400 — Contract.ContractTemplateID description (#137) and
--                 ContractType.ContractTemplateTypeID (#114).
-- =============================================================================
-- 1. Issue #137: Contract.ContractTemplateID's baseline MS_Description stated
--    that the column is nullable because a contract created automatically at
--    Closed Won has none until finance reads the PDF. This schema has no
--    dependency on sales or Closed Won; the column is nullable because contract
--    types with TemplateRequired = 0 (Change Order, Statement of Work) carry no
--    standard agreement version of their own, and because a newly created
--    contract leaves it empty when no Published, usable template exists yet.
--
-- 2. Issue #114: ContractType had TemplateRequired (bit) but no reference to
--    ContractTemplateType, so template defaulting selected the newest Published,
--    usable template across all template types regardless of which ContractType
--    was chosen. Adding a nullable ContractTemplateTypeID foreign key lets each
--    template-requiring ContractType name the kind of standard agreement it
--    incorporates by default (Order Form and Payment Link -> Master Agreement),
--    while types with TemplateRequired = 0 (or types that leave the FK null)
--    remain unconstrained.
-- =============================================================================

EXEC sp_updateextendedproperty @name=N'MS_Description',
    @value=N'The agreement version this contract incorporates. Nullable because contract types with TemplateRequired = 0 (such as Change Order and Statement of Work) carry no standard agreement version of their own, and because a newly created contract leaves this empty when no Published, usable template exists yet.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'Contract',
    @level2type=N'COLUMN', @level2name=N'ContractTemplateID';
GO

ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD
    [ContractTemplateTypeID] UNIQUEIDENTIFIER NULL
        CONSTRAINT [FK_ContractType_ContractTemplateType]
        FOREIGN KEY REFERENCES [${flyway:defaultSchema}].[ContractTemplateType]([ID]);
GO

UPDATE [${flyway:defaultSchema}].[ContractType]
SET [ContractTemplateTypeID] = '33333333-0000-4000-8000-000000002001'
WHERE [ID] IN ('33333333-0000-4000-8000-000000001001', '33333333-0000-4000-8000-000000001003');
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Which kind of standard agreement (ContractTemplateType) a contract of this type incorporates by default when TemplateRequired = 1. Nullable because types with TemplateRequired = 0 carry no template, and a type that leaves this NULL falls back to the newest Published, usable template across all template types.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'ContractTemplateTypeID';
GO


















































-- =============================================================================
-- CodeGen capture — everything below this line is GENERATED. Replace it wholesale
-- on regeneration; see docs/database-migrations.md § the 50-blank-line rule.
-- =============================================================================
/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to insert new entity fields */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8a4c5e92-3b71-4d08-9f16-2e65d093c410' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'ContractTemplateTypeID')) BEGIN
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
            '8a4c5e92-3b71-4d08-9f16-2e65d093c410',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'ContractTemplateTypeID',
            'Contract Template Type ID',
            'Which kind of standard agreement (ContractTemplateType) a contract of this type incorporates by default when TemplateRequired = 1. Nullable because types with TemplateRequired = 0 carry no template, and a type that leaves this NULL falls back to the newest Published, usable template across all template types.',
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

/* SQL text to create Entity Relationship: MJ_BizApps_Contracts: Contract Template Types -> MJ_BizApps_Contracts: Contract Types (One To Many via ContractTemplateTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'd947b1e3-5c82-4a6f-9214-7e03f8a6b512'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('d947b1e3-5c82-4a6f-9214-7e03f8a6b512', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'ContractTemplateTypeID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
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
-----------------------------------------------------------------
-- Index for foreign key ContractTemplateTypeID in table ContractType
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractType_ContractTemplateTypeID'
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractType]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractType_ContractTemplateTypeID ON [${flyway:defaultSchema}].[ContractType] ([ContractTemplateTypeID]);

/* SQL text to update entity field related entity name field map for entity field ID 8A4C5E92-3B71-4D08-9F16-2E65D093C410 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='8A4C5E92-3B71-4D08-9F16-2E65D093C410', @RelatedEntityNameFieldMap='ContractTemplateType';

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
    c.*,
    mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[Name] AS [ContractTemplateType]
FROM
    [${flyway:defaultSchema}].[ContractType] AS c
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[ContractTemplateType] AS mjBizAppsContractsContractTemplateType_ContractTemplateTypeID
  ON
    [c].[ContractTemplateTypeID] = mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[ID]
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
    @DefaultAnnualIncreasePercent decimal(7, 4) = NULL,
    @Code nvarchar(50),
    @ContractTemplateTypeID_Clear bit = 0,
    @ContractTemplateTypeID uniqueidentifier = NULL
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
                [DefaultAnnualIncreasePercent],
                [Code],
                [ContractTemplateTypeID]
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
                CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, NULL) END,
                @Code,
                CASE WHEN @ContractTemplateTypeID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateTypeID, NULL) END
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
                [DefaultAnnualIncreasePercent],
                [Code],
                [ContractTemplateTypeID]
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
                CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, NULL) END,
                @Code,
                CASE WHEN @ContractTemplateTypeID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateTypeID, NULL) END
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
    @DefaultAnnualIncreasePercent decimal(7, 4) = NULL,
    @Code nvarchar(50) = NULL,
    @ContractTemplateTypeID_Clear bit = 0,
    @ContractTemplateTypeID uniqueidentifier = NULL
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
        [DefaultAnnualIncreasePercent] = CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, [DefaultAnnualIncreasePercent]) END,
        [Code] = ISNULL(@Code, [Code]),
        [ContractTemplateTypeID] = CASE WHEN @ContractTemplateTypeID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateTypeID, [ContractTemplateTypeID]) END
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

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Types */

REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Developer]
REVOKE EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] FROM [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration];

/* SQL text to insert virtual entity field for joined ContractTemplateType name */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c2f14d80-6a35-491e-84c7-5b90e374a821' OR (EntityID = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND Name = 'ContractTemplateType')) BEGIN
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
            'c2f14d80-6a35-491e-84c7-5b90e374a821',
            'C8909A57-6DDB-4585-BE00-E707C5B4F262', -- Entity: MJ_BizApps_Contracts: Contract Types
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'),
            'ContractTemplateType',
            'Contract Template Type',
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

/* SQL text to update existing entity fields from schema (2 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Sync Contract.ContractTemplateID EntityField description with MS_Description (#137) */
UPDATE [${mjSchema}].[EntityField]
SET [Description] = N'The agreement version this contract incorporates. Nullable because contract types with TemplateRequired = 0 (such as Change Order and Statement of Work) carry no standard agreement version of their own, and because a newly created contract leaves this empty when no Published, usable template exists yet.'
WHERE [ID] = 'B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA'
  AND [AutoUpdateDescription] = 1;

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Set categories for 2 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ContractTemplateTypeID
UPDATE [${mjSchema}].[EntityField]
SET
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   DisplayName = 'Default Template Type',
   ExtendedType = NULL,
   CodeType = NULL
WHERE
   ID = '8A4C5E92-3B71-4D08-9F16-2E65D093C410' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ContractTemplateType
UPDATE [${mjSchema}].[EntityField]
SET
   Category = 'Configuration Rules',
   GeneratedFormSection = 'Category',
   DisplayName = 'Default Template Type Name',
   ExtendedType = NULL,
   CodeType = NULL
WHERE
   ID = 'C2F14D80-6A35-491E-84C7-5B90E374A821' AND AutoUpdateCategory = 1;
