-- =============================================================================
-- V202609191700 — Predictive Contract Expiration & Non-Renewal Risk
-- =============================================================================
-- Adds operational prediction columns to Contract (PredictedNonRenewalRisk,
-- PredictedRenewalRiskBand, PredictedRenewalScoredAt) and updates vwContracts
-- with target variable NonRenewalOutcome and engineered features.
-- =============================================================================

ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD
    [PredictedNonRenewalRisk] DECIMAL(5, 4) NULL,
    [PredictedRenewalRiskBand] NVARCHAR(20) NULL,
    [PredictedRenewalScoredAt] DATETIMEOFFSET NULL,
    CONSTRAINT [CK_Contract_PredictedRenewalRiskBand]
        CHECK ([PredictedRenewalRiskBand] IS NULL OR [PredictedRenewalRiskBand] IN ('Low', 'Medium', 'High', 'Critical'));
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Predicted probability (0.0000 to 1.0000) that this commercial agreement will fail to renew prior to the required notice deadline.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'Contract',
    @level2type = N'COLUMN', @level2name = N'PredictedNonRenewalRisk';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Derived operational risk band classifying renewal risk: Low (<20%), Medium (20-50%), High (50-80%), Critical (>=80%).',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'Contract',
    @level2type = N'COLUMN', @level2name = N'PredictedRenewalRiskBand';
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Timestamp of the most recent predictive model scoring execution for this contract.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'Contract',
    @level2type = N'COLUMN', @level2name = N'PredictedRenewalScoredAt';
GO

CREATE OR ALTER VIEW [${flyway:defaultSchema}].[vwContracts]
AS
SELECT
    g.*,
    CASE
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= CAST(GETUTCDATE() AS date) THEN 'Terminated'
        WHEN g.SupersededByContractID IS NOT NULL                          THEN 'Superseded'
        WHEN g.EndDate IS NOT NULL AND g.EndDate < CAST(GETUTCDATE() AS date) THEN 'Expired'
        WHEN g.EffectiveDate IS NOT NULL AND g.EffectiveDate <= CAST(GETUTCDATE() AS date) THEN 'Active'
        WHEN g.ExecutedDate IS NOT NULL                                    THEN 'Executed'
        ELSE 'Draft'
    END AS [State],
    CAST(CASE
        WHEN ct.RequiresExecutedDocument = 1
         AND NOT EXISTS (
                SELECT 1
                  FROM [${mjSchema}].[FileEntityRecordLink] fl
                 WHERE fl.EntityID = (SELECT e.ID FROM [${mjSchema}].[Entity] e
                                       WHERE e.Name = 'MJ_BizApps_Contracts: Contracts')
                   AND fl.RecordID = CAST(g.ID AS nvarchar(450))
             )
        THEN 1 ELSE 0
    END AS bit) AS [IsAwaitingDocument],
    CASE WHEN g.EndDate IS NULL THEN NULL
         ELSE DATEDIFF(day, CAST(GETUTCDATE() AS date), g.EndDate) END AS [DaysToEnd],
    CASE WHEN g.EndDate IS NULL OR g.RenewalNoticeDays IS NULL THEN NULL
         ELSE DATEADD(day, -g.RenewalNoticeDays, g.EndDate) END AS [RenewalNoticeDeadline],
    CAST(CASE
        WHEN g.EndDate IS NOT NULL AND g.CancellationWindowDays IS NOT NULL
         AND CAST(GETUTCDATE() AS date) >= DATEADD(day, -g.CancellationWindowDays, g.EndDate)
         AND CAST(GETUTCDATE() AS date) <= g.EndDate
        THEN 1 ELSE 0
    END AS bit) AS [IsInCancellationWindow],
    CASE
        WHEN g.SupersededByContractID IS NOT NULL THEN 0
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= CAST(GETUTCDATE() AS date) THEN 1
        WHEN g.EndDate IS NOT NULL AND g.EndDate < CAST(GETUTCDATE() AS date) THEN 1
        ELSE NULL
    END AS [NonRenewalOutcome],
    CASE WHEN g.EffectiveDate IS NOT NULL AND g.EndDate IS NOT NULL THEN DATEDIFF(day, g.EffectiveDate, g.EndDate) ELSE NULL END AS [TermLengthDays],
    CASE WHEN g.EndDate IS NOT NULL AND g.RenewalNoticeDays IS NOT NULL THEN DATEDIFF(day, CAST(GETUTCDATE() AS date), DATEADD(day, -g.RenewalNoticeDays, g.EndDate)) ELSE NULL END AS [DaysUntilNoticeDeadline],
    CASE WHEN g.HasModifications = 1 THEN 1 ELSE 0 END AS [HasModificationsFlag],
    CASE WHEN g.AutoRenew = 1 THEN 1 ELSE 0 END AS [AutoRenewFlag],
    CASE WHEN g.ParentContractID IS NOT NULL THEN 1 ELSE 0 END AS [HasParentContract],
    CASE WHEN g.CancellationWindowDays > 0 THEN 1 ELSE 0 END AS [HasCancellationWindow],
    CASE WHEN g.AnnualIncreasePercent > 0 THEN 1 ELSE 0 END AS [HasAnnualIncrease]
FROM
    [${flyway:defaultSchema}].[vwContractsGenerated] g
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[ContractType] ct
  ON
    g.ContractTypeID = ct.ID;
GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO

DECLARE @entityID UNIQUEIDENTIFIER = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
DECLARE @fields TABLE (
    Name NVARCHAR(100),
    DisplayName NVARCHAR(100),
    Type NVARCHAR(50),
    Length INT,
    Precision INT,
    Scale INT,
    Description NVARCHAR(500)
);

INSERT INTO @fields (Name, DisplayName, Type, Length, Precision, Scale, Description) VALUES
('NonRenewalOutcome', 'Non Renewal Outcome', 'int', 4, 10, 0, 'Binary outcome: 1 if contract reached conclusion without renewal (terminated or expired), 0 if superseded/renewed, NULL if active/in-flight.'),
('TermLengthDays', 'Term Length Days', 'int', 4, 10, 0, 'Duration of contract term in days between effective date and end date.'),
('DaysUntilNoticeDeadline', 'Days Until Notice Deadline', 'int', 4, 10, 0, 'Days remaining until the required non-renewal notice deadline.'),
('HasModificationsFlag', 'Has Modifications Flag', 'int', 4, 10, 0, 'Flag indicating whether the agreement contains custom modifications or clause deviations.'),
('AutoRenewFlag', 'Auto Renew Flag', 'int', 4, 10, 0, 'Flag indicating whether auto-renewal is enabled.'),
('HasParentContract', 'Has Parent Contract', 'int', 4, 10, 0, 'Flag indicating whether this agreement is an amendment or child contract.'),
('HasCancellationWindow', 'Has Cancellation Window', 'int', 4, 10, 0, 'Flag indicating whether a cancellation window is configured.'),
('HasAnnualIncrease', 'Has Annual Increase', 'int', 4, 10, 0, 'Flag indicating whether annual percentage increases apply.');

MERGE INTO [${mjSchema}].[EntityField] AS target
USING (
    SELECT 
        NEWID() AS ID,
        @entityID AS EntityID,
        (SELECT ISNULL(MAX(Sequence), 0) FROM [${mjSchema}].[EntityField] WHERE EntityID = @entityID) + 
            ROW_NUMBER() OVER (ORDER BY f.Name) AS Sequence,
        f.Name,
        f.DisplayName,
        f.Description,
        f.Type,
        f.Length,
        f.Precision,
        f.Scale,
        1 AS AllowsNull,
        0 AS DefaultInView,
        1 AS IsVirtual,
        0 AS AllowUpdateAPI,
        'Active' AS Status
    FROM @fields f
) AS source
ON target.EntityID = source.EntityID AND target.Name = source.Name
WHEN NOT MATCHED THEN
    INSERT (ID, EntityID, Sequence, Name, DisplayName, Description, Type, Length, Precision, Scale, AllowsNull, DefaultInView, IsVirtual, AllowUpdateAPI, Status)
    VALUES (source.ID, source.EntityID, source.Sequence, source.Name, source.DisplayName, source.Description, source.Type, source.Length, source.Precision, source.Scale, source.AllowsNull, source.DefaultInView, source.IsVirtual, source.AllowUpdateAPI, source.Status);
GO


















































-- =============================================================================
-- GENERATED BY MemberJunction CodeGen — DO NOT EDIT BY HAND
-- =============================================================================

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to insert 3 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1de502c3-42f6-4246-b7a0-90f61c38d586' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'PredictedNonRenewalRisk')) BEGIN
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
            '1de502c3-42f6-4246-b7a0-90f61c38d586',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'),
            'PredictedNonRenewalRisk',
            'Predicted Non Renewal Risk',
            'Predicted probability (0.0000 to 1.0000) that this commercial agreement will fail to renew prior to the required notice deadline.',
            'decimal',
            5,
            5,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e25c8e07-f5dc-4d15-9ef4-56f51111575e' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'PredictedRenewalRiskBand')) BEGIN
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
            'e25c8e07-f5dc-4d15-9ef4-56f51111575e',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'),
            'PredictedRenewalRiskBand',
            'Predicted Renewal Risk Band',
            'Derived operational risk band classifying renewal risk: Low (<20%), Medium (20-50%), High (50-80%), Critical (>=80%).',
            'nvarchar',
            40,
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2e2a570-28ca-4b84-b2c7-aa09d546fd72' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'PredictedRenewalScoredAt')) BEGIN
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
            'e2e2a570-28ca-4b84-b2c7-aa09d546fd72',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'),
            'PredictedRenewalScoredAt',
            'Predicted Renewal Scored At',
            'Timestamp of the most recent predictive model scoring execution for this contract.',
            'datetimeoffset',
            10,
            34,
            7,
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

/* SQL text to insert entity field value with ID 1ec3de11-5522-4d8e-ab20-86ad2f1071ee */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('1ec3de11-5522-4d8e-ab20-86ad2f1071ee', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 1, 'Critical', 'Critical', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f89a14ec-d3da-4e98-a21a-4ce2e8bec8c6 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f89a14ec-d3da-4e98-a21a-4ce2e8bec8c6', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 2, 'High', 'High', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 667682f8-3679-4027-98ed-c6bd11a4d6d8 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('667682f8-3679-4027-98ed-c6bd11a4d6d8', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 3, 'Low', 'Low', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID d0d8f5a2-2102-4890-9941-8e965f2d750f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('d0d8f5a2-2102-4890-9941-8e965f2d750f', 'E25C8E07-F5DC-4D15-9EF4-56F51111575E', 4, 'Medium', 'Medium', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID E25C8E07-F5DC-4D15-9EF4-56F51111575E */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='E25C8E07-F5DC-4D15-9EF4-56F51111575E';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

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
    EXEC sp_executesql N'REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_UI]
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
    EXEC sp_executesql N'REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Developer]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_Integration]
REVOKE SELECT ON [${flyway:defaultSchema}].[vwContracts] FROM [cdp_UI]
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
    @Notes nvarchar(MAX) = NULL,
    @PredictedNonRenewalRisk_Clear bit = 0,
    @PredictedNonRenewalRisk decimal(5, 4) = NULL,
    @PredictedRenewalRiskBand_Clear bit = 0,
    @PredictedRenewalRiskBand nvarchar(20) = NULL,
    @PredictedRenewalScoredAt_Clear bit = 0,
    @PredictedRenewalScoredAt datetimeoffset = NULL
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
                [Notes],
                [PredictedNonRenewalRisk],
                [PredictedRenewalRiskBand],
                [PredictedRenewalScoredAt]
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
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END,
                CASE WHEN @PredictedNonRenewalRisk_Clear = 1 THEN NULL ELSE ISNULL(@PredictedNonRenewalRisk, NULL) END,
                CASE WHEN @PredictedRenewalRiskBand_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalRiskBand, NULL) END,
                CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, NULL) END
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
                [Notes],
                [PredictedNonRenewalRisk],
                [PredictedRenewalRiskBand],
                [PredictedRenewalScoredAt]
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
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END,
                CASE WHEN @PredictedNonRenewalRisk_Clear = 1 THEN NULL ELSE ISNULL(@PredictedNonRenewalRisk, NULL) END,
                CASE WHEN @PredictedRenewalRiskBand_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalRiskBand, NULL) END,
                CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, NULL) END
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
    @Notes nvarchar(MAX) = NULL,
    @PredictedNonRenewalRisk_Clear bit = 0,
    @PredictedNonRenewalRisk decimal(5, 4) = NULL,
    @PredictedRenewalRiskBand_Clear bit = 0,
    @PredictedRenewalRiskBand nvarchar(20) = NULL,
    @PredictedRenewalScoredAt_Clear bit = 0,
    @PredictedRenewalScoredAt datetimeoffset = NULL
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
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END,
        [PredictedNonRenewalRisk] = CASE WHEN @PredictedNonRenewalRisk_Clear = 1 THEN NULL ELSE ISNULL(@PredictedNonRenewalRisk, [PredictedNonRenewalRisk]) END,
        [PredictedRenewalRiskBand] = CASE WHEN @PredictedRenewalRiskBand_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalRiskBand, [PredictedRenewalRiskBand]) END,
        [PredictedRenewalScoredAt] = CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, [PredictedRenewalScoredAt]) END
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

/* SQL text to delete unneeded entity fields (1 scoped entities) */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='5DEB0B11-ED6C-48B3-9200-F4441396C5E2', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to update existing entity fields from schema (1 scoped entities) */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @EntityIDs='5DEB0B11-ED6C-48B3-9200-F4441396C5E2', @IncludedSchemaNames='${flyway:defaultSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema}', @IncludedSchemaNames='${flyway:defaultSchema}';

/* Refresh custom base views for modified entities so schema changes are picked up */
EXEC sp_refreshview '${flyway:defaultSchema}.vwContractsGenerated';
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'EXEC sp_refreshview ''${flyway:defaultSchema}.vwContracts'';';
END;

