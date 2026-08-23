-- =============================================================================
-- V202608040002 — the two layered base views: hand CodeGen a PRIVATE name.
-- =============================================================================
-- Contracts and Contract Templates use MJ's layered base views (MJ#3419): CodeGen
-- owns a generated inner view under GeneratedBaseViewName, and the APPLICATION owns
-- the public BaseView as a thin wrapper adding derived columns. This file sets the
-- flags and carries the regenerated inner views; the NEXT file creates the wrappers.
--
-- WHY THIS IS NOT IN THE BASELINE, given that everything else was folded into it.
-- The layering is a SEQUENCE, not a state, and the ordering is forced twice over:
--
--   1. The flags live on __mj.Entity rows that DO NOT EXIST until the baseline's own
--      CodeGen capture inserts them. An UPDATE placed anywhere in the baseline is a
--      no-op against a row that is not there yet.
--   2. A wrapper view cannot be created before the view it selects FROM. SQL Server
--      has deferred name resolution for procedure bodies but NOT for views, so the
--      generated inner view has to exist first — which is why the wrappers are a
--      third file rather than the tail of this one.
--
-- WHY THE FLAGS SHIP AS A MIGRATION AT ALL, rather than only in metadata/entities/.
-- A fresh environment runs migrate -> codegen -> sync push. That FIRST codegen, seeing
-- BaseViewGenerated = 1, resolves its target to the PUBLIC name and DROP/CREATEs
-- vwContracts as a plain generated view — silently destroying the wrapper. Shipping the
-- flags here means every environment that migrates has them before any codegen can run.
--
-- Keyed by entity NAME, never by ID: entity IDs are minted at first registration, so a
-- hardcoded UUID stops matching the first time a database is rebuilt from zero. Both
-- UPDATEs skip cleanly when the row is absent.
--
-- ⚠ THE CAPTURE BELOW EXISTS BECAUSE CODEGEN'S LOG AND ITS EXECUTION DISAGREE. CodeGen
-- writes an object to its SQL output only for entities it considers MODIFIED, and
-- flipping BaseViewGenerated does not count as a modification — but it still CREATEs
-- vwContractsGenerated / vwContractTemplatesGenerated in the database it is pointed at.
-- So a plain post-flag codegen run produces a capture with the two generated views
-- MISSING, and the omission is invisible until a fresh install reaches the wrapper and
-- fails on an object nothing ever created. The capture below was taken with
-- forceRegeneration.baseViews scoped to these two entities, which is what makes it
-- complete. If you ever re-capture this file, force base-view regeneration or check by
-- name that both *Generated views are present.
-- =============================================================================

UPDATE [${mjSchema}].[Entity]
   SET [BaseViewGenerated] = 0,
       [GeneratedBaseViewName] = 'vwContractsGenerated'
 WHERE [Name] = 'MJ_BizApps_Contracts: Contracts'
   AND ([BaseViewGenerated] <> 0
        OR [GeneratedBaseViewName] IS NULL
        OR [GeneratedBaseViewName] <> 'vwContractsGenerated');
GO

UPDATE [${mjSchema}].[Entity]
   SET [BaseViewGenerated] = 0,
       [GeneratedBaseViewName] = 'vwContractTemplatesGenerated'
 WHERE [Name] = 'MJ_BizApps_Contracts: Contract Templates'
   AND ([BaseViewGenerated] <> 0
        OR [GeneratedBaseViewName] IS NULL
        OR [GeneratedBaseViewName] <> 'vwContractTemplatesGenerated');
GO


















































/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to update entity field related entity name field map for entity field ID 6DB0692A-42CD-4AC5-A43B-49ECC81EF370 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='6DB0692A-42CD-4AC5-A43B-49ECC81EF370', @RelatedEntityNameFieldMap='ParentContract';

/* SQL text to update entity field related entity name field map for entity field ID 44BC44EF-A6F2-4630-A899-487CE0E3CC56 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='44BC44EF-A6F2-4630-A899-487CE0E3CC56', @RelatedEntityNameFieldMap='SupersededByContract';

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to update entity field related entity name field map for entity field ID 982E307B-667C-4955-99DE-F9A96FAB2CB2 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='982E307B-667C-4955-99DE-F9A96FAB2CB2', @RelatedEntityNameFieldMap='Contract';

/* Base View SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: vwContractTemplatesGenerated
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
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplatesGenerated]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTemplatesGenerated];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTemplatesGenerated]
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
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplates]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplates] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
END;

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Templates */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Permissions for vwContractTemplates
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTemplates]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplates] TO [cdp_UI], [cdp_Developer], [cdp_Integration]';
END;

/* SQL text to update entity field related entity name field map for entity field ID 0864CB7F-E532-402F-9F16-102EC14993C6 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='0864CB7F-E532-402F-9F16-102EC14993C6', @RelatedEntityNameFieldMap='ContractTemplateProvision';

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

/* SQL text to delete unneeded entity fields */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to insert 2 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '98336d4e-6f80-4f25-bfec-827d94128191' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'Contract')) BEGIN
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
            '98336d4e-6f80-4f25-bfec-827d94128191',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 8,
            'Contract',
            'Contract',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9c030856-2774-4c96-801f-e31e5f76edbb' OR (EntityID = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND Name = 'ContractTemplateProvision')) BEGIN
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
            '9c030856-2774-4c96-801f-e31e5f76edbb',
            'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- Entity: MJ_BizApps_Contracts: Contract Template Modifications
            (SELECT COALESCE(MAX([Sequence]), 0) FROM [${mjSchema}].[EntityField] WHERE [EntityID] = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 9,
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

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

