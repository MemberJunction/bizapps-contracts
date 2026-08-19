-- =============================================================================
-- V202608182002 — the derived columns become virtual EntityFields.
-- =============================================================================
-- The third and last file of Contracts' layered base view. The PREVIOUS migration
-- created the wrapper; this one is the CodeGen convergence capture that discovers
-- its six added columns and registers them as virtual `__mj.EntityField` rows:
-- State, IsAwaitingDocument, IsChangeOrder, DaysToEnd, RenewalNoticeDeadline,
-- IsInCancellationWindow.
--
-- WITHOUT THIS FILE the columns exist in SQL and MJ cannot see them — no RunView
-- filter, no grid column, no typed property on the entity class. A fresh install
-- never runs CodeGen, so the discovery has to ship as a migration.
--
-- ⚠ THIS CAPTURE MUST STAY BEHIND THE WRAPPER IN THE MIGRATION TRAIN. It was
-- generated against a database where vwContracts already had the derived columns,
-- and it contains `spDeleteUnneededEntityFields` sweeps that compare metadata to
-- the live view. Replayed BEFORE the wrapper exists, those sweeps delete the very
-- rows the file just inserted — orders proved that with stage-test on 2026-08-13
-- (V202608131542). The filename timestamp is what enforces the ordering, so do not
-- renumber it below V202608182001.
--
-- WHY IT IS A SEPARATE FILE, where orders appended the same capture INTO its
-- wrapper migration: orders authored both halves before either was applied.
-- V202608182001 was already applied here, and editing an applied migration changes
-- its checksum, which makes Flyway refuse every subsequent migrate on this database.
-- A later file is functionally identical — it runs after the wrapper either way —
-- and it costs one filename instead of a database rebuild.
--
-- Sequence numbers use apply-time `MAX([Sequence]) + n`, so the rows land after
-- whatever real columns exist rather than at hardcoded positions that a later
-- schema change would collide with.
-- =============================================================================

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to insert 10 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '311ed78c-9fb7-4fea-bd58-658856689ae5' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'Contract')) BEGIN
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
            '311ed78c-9fb7-4fea-bd58-658856689ae5',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 8,
            'Contract',
            'Contract',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e27a21b0-3a89-4d33-ad22-bf5e8c44228f' OR (EntityID = '2E611A7D-2FBB-4A45-A9C8-103834BF026A' AND Name = 'ContractTemplateProvision')) BEGIN
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
            'e27a21b0-3a89-4d33-ad22-bf5e8c44228f',
            '2E611A7D-2FBB-4A45-A9C8-103834BF026A', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '2E611A7D-2FBB-4A45-A9C8-103834BF026A') + 9,
            'ContractTemplateProvision',
            'Contract Template Provision',
            NULL,
            'nvarchar',
            40,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '98facab7-0c04-4961-9992-0c19820f5ede' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'ParentContract')) BEGIN
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
            '98facab7-0c04-4961-9992-0c19820f5ede',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 32,
            'ParentContract',
            'Parent Contract',
            NULL,
            'nvarchar',
            100,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3cddb251-167f-40aa-bd0c-14ff49e262e8' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'SupersededByContract')) BEGIN
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
            '3cddb251-167f-40aa-bd0c-14ff49e262e8',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 33,
            'SupersededByContract',
            'Superseded By Contract',
            NULL,
            'nvarchar',
            100,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4da14560-07c1-409f-b266-8c7cee30dab3' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'State')) BEGIN
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
            '4da14560-07c1-409f-b266-8c7cee30dab3',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 36,
            'State',
            'State',
            NULL,
            'varchar',
            10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a71d317a-136f-43bd-8197-22528c84081e' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'IsAwaitingDocument')) BEGIN
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
            'a71d317a-136f-43bd-8197-22528c84081e',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 37,
            'IsAwaitingDocument',
            'Is Awaiting Document',
            NULL,
            'bit',
            1,
            1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd9c31160-630a-41a4-af0a-74a7c7e1d864' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'IsChangeOrder')) BEGIN
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
            'd9c31160-630a-41a4-af0a-74a7c7e1d864',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 38,
            'IsChangeOrder',
            'Is Change Order',
            NULL,
            'bit',
            1,
            1,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd7aa65a0-5577-4b3c-8b60-ddebe8d4648d' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'DaysToEnd')) BEGIN
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
            'd7aa65a0-5577-4b3c-8b60-ddebe8d4648d',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 39,
            'DaysToEnd',
            'Days To End',
            NULL,
            'int',
            4,
            10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '15720256-8eee-44bc-b109-2023c4413e14' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'RenewalNoticeDeadline')) BEGIN
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
            '15720256-8eee-44bc-b109-2023c4413e14',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 40,
            'RenewalNoticeDeadline',
            'Renewal Notice Deadline',
            NULL,
            'date',
            3,
            10,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e7485605-e4ce-46f5-a830-4300a09de8ff' OR (EntityID = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20' AND Name = 'IsInCancellationWindow')) BEGIN
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
            'e7485605-e4ce-46f5-a830-4300a09de8ff',
            '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20') + 41,
            'IsInCancellationWindow',
            'Is In Cancellation Window',
            NULL,
            'bit',
            1,
            1,
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

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

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
    c.*,
    mjBizAppsContractsContract_ContractID.[ContractNumber] AS [Contract],
    mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID.[ProvisionNumber] AS [ContractTemplateProvision]
FROM
    [${flyway:defaultSchema}].[ContractTemplateModification] AS c
INNER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_ContractID
  ON
    [c].[ContractID] = mjBizAppsContractsContract_ContractID.[ID]
INNER JOIN
    [${flyway:defaultSchema}].[ContractTemplateProvision] AS mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID
  ON
    [c].[ContractTemplateProvisionID] = mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID.[ID]
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
    mjBizAppsCommonPerson_PrimaryContactPersonID.[FirstName] AS [PrimaryContactPerson],
    mjBizAppsContractsContractTemplate_ContractTemplateID.[Name] AS [ContractTemplate],
    MJEntity_CreatingEntityID.[Name] AS [CreatingEntity],
    mjBizAppsContractsContract_ParentContractID.[ContractNumber] AS [ParentContract],
    mjBizAppsContractsContract_SupersededByContractID.[ContractNumber] AS [SupersededByContract],
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
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_ParentContractID
  ON
    [c].[ParentContractID] = mjBizAppsContractsContract_ParentContractID.[ID]
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_SupersededByContractID
  ON
    [c].[SupersededByContractID] = mjBizAppsContractsContract_SupersededByContractID.[ID]
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]([c].[ID], [c].[ParentContractID]) AS root_ParentContractID
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]([c].[ID], [c].[SupersededByContractID]) AS root_SupersededByContractID
GO
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
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
    EXEC sp_executesql N'GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
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

/* SQL text to delete unneeded entity fields (2 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks', @EntityIDs='2E611A7D-2FBB-4A45-A9C8-103834BF026A,4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20';

/* SQL text to update existing entity fields from schema (2 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks', @EntityIDs='2E611A7D-2FBB-4A45-A9C8-103834BF026A,4CC3DB2D-F01F-405E-A47D-B14BA2F1AB20';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsOrders,${mjSchema}_BizAppsTasks';

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '4DA14560-07C1-409F-B266-8C7CEE30DAB3'
               AND AutoUpdateDefaultInView = 1;

/* Set field properties for entity */

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = '311ED78C-9FB7-4FEA-BD58-658856689AE5'
               AND AutoUpdateDefaultInView = 1;

               UPDATE [${mjSchema}].[EntityField]
               SET DefaultInView = 1
               WHERE ID = 'E27A21B0-3A89-4D33-AD22-BF5E8C44228F'
               AND AutoUpdateDefaultInView = 1;

/* Set categories for 9 fields */

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ID 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'FD9C658F-66CE-43A1-AE3A-40DB31530608' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_CreatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'C89C9AA4-4C51-4623-A042-F475C18B415A' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.__mj_UpdatedAt 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9987B09C-FFFA-460C-9B86-F1692C1728AA' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractID 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '9D1ECADE-25C0-4A9C-912A-6B993C5AFD35' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractTemplateProvisionID 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Template Provision',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '51331345-4AE4-4882-959A-6046CBBDDACE' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.Contract 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Contract Reference',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '311ED78C-9FB7-4FEA-BD58-658856689AE5' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ContractTemplateProvision 
UPDATE [${mjSchema}].[EntityField]
SET 
   Category = 'Contract Association',
   GeneratedFormSection = 'Category',
   DisplayName = 'Provision Reference',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = 'E27A21B0-3A89-4D33-AD22-BF5E8C44228F' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.ModificationText 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8178CF5D-D3A4-4405-8FDA-90D79B627D55' AND AutoUpdateCategory = 1;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Template Modifications.Notes 
UPDATE [${mjSchema}].[EntityField]
SET 
   GeneratedFormSection = 'Category',
   ExtendedType = NULL,
   CodeType = NULL
WHERE 
   ID = '8DAB9C2D-48B0-4C25-8BD3-4DD74029D29A' AND AutoUpdateCategory = 1;

/* Refresh custom base views for modified entities so schema changes are picked up */
EXEC sp_refreshview '${flyway:defaultSchema}.vwContractsGenerated';
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'EXEC sp_refreshview ''${flyway:defaultSchema}.vwContracts'';';
END;

