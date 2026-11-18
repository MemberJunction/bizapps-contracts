-- =============================================================================
-- V202611121200 — ContractOrder, the link from a contract to the orders it
--                 produced, and Contract.CarryDiscountOnRenewal (issue #77)
-- =============================================================================
-- Orders reprices a renewal from two fields on the subscription:
-- RenewalIncreasePercent and CarryDiscountOnRenewal. The contract is where the
-- negotiated values are recorded, but nothing could carry them over: a contract
-- named its customer and nothing it governs, and Orders cannot reference this
-- app because foreign keys point up the install order, never down.
--
-- WHY THE LINK NAMES ORDERS, NOT SUBSCRIPTIONS. The order a deal produced is
-- known the moment the deal closes. Its subscriptions are created by Orders as
-- the order is processed, so at close they may not exist yet. Each subscription
-- names the order line that created it, so a contract's subscriptions are
-- derived as ContractOrder -> OrderLine -> Subscription whenever the terms are
-- pushed, and a subscription created later is found on the next push. One
-- contract links to many orders (the original sale, expansions, renewals), and
-- an order may be governed by more than one contract.
--
-- CarryDiscountOnRenewal records what the paper says: a first-term discount
-- continues into renewal terms (a multi-year concession). It defaults to 0, the
-- rule finance set for every renewal. The uplift needs no new column:
-- AnnualIncreasePercent already holds it, seeded from the contract type.
--
-- Plain DDL: no existence guards. Migrations run once, in order.
--
-- Install order: this file's foreign key to __mj_BizAppsOrders.OrderHeader is
-- why mj-app.json now depends on mj-bizapps-orders. The schema name is written
-- out, as the baseline writes __mj_BizAppsCommon: it is another app's schema,
-- not one of this file's placeholders.
--
-- No cascade on either key: deleting a contract with linked orders is refused
-- by ContractEntityServer's delete guard, and an order linked to a contract
-- cannot be deleted until the link is removed.
-- =============================================================================

CREATE TABLE [${flyway:defaultSchema}].[ContractOrder] (
    [ID] UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT [DF_ContractOrder_ID] DEFAULT NEWSEQUENTIALID(),
    [ContractID] UNIQUEIDENTIFIER NOT NULL,
    [OrderID] UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT [PK_ContractOrder] PRIMARY KEY ([ID]),
    CONSTRAINT [UQ_ContractOrder_ContractOrder] UNIQUE ([ContractID], [OrderID]),
    CONSTRAINT [FK_ContractOrder_Contract]
        FOREIGN KEY ([ContractID]) REFERENCES [${flyway:defaultSchema}].[Contract] ([ID]),
    CONSTRAINT [FK_ContractOrder_OrderHeader]
        FOREIGN KEY ([OrderID]) REFERENCES [__mj_BizAppsOrders].[OrderHeader] ([ID])
);
GO

-- The unique constraint leads with ContractID, which serves "this contract's
-- orders". The reverse question, "which contracts govern this order", gets its own.
CREATE NONCLUSTERED INDEX [IX_ContractOrder_OrderID]
    ON [${flyway:defaultSchema}].[ContractOrder] ([OrderID]);
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'An order this contract governs. The contract''s renewal terms (annual increase, whether a discount continues) are copied to every subscription the order''s lines created. Written when a deal closes with both a contract and an order, or by hand for an order the contract covers.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'The contract whose terms apply to the order.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder',
    @level2type=N'COLUMN', @level2name=N'ContractID';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder',
    @level2type=N'COLUMN', @level2name=N'OrderID';
GO

ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD
    [CarryDiscountOnRenewal] BIT NOT NULL
        CONSTRAINT [DF_Contract_CarryDiscountOnRenewal] DEFAULT (0);
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'Contract',
    @level2type=N'COLUMN', @level2name=N'CarryDiscountOnRenewal';
GO


















































-- =============================================================================
-- CodeGen capture — everything below this line is GENERATED. Replace it wholesale
-- on regeneration; see docs/database-migrations.md § the 50-blank-line rule.
-- =============================================================================
-- Captured with omitRecurringScriptsFromLog: true, so the capture carries no
-- spDeleteUnneededEntityFields call. One hand edit: CodeGen also emitted the 0/1
-- value list for Contract.NonRenewalOutcome (two EntityFieldValue inserts and a
-- ValueListType update), keyed by that field's EntityField ID in the capture
-- database. V202611031700 created that field through the field refresh, so its ID
-- differs on every host and the insert fails its foreign key on a clean replay.
-- That value list is earlier drift, not this change, and is left out here.
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Orders */

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
         [AllowCaching],
         [TrackRecordChanges],
         [AuditRecordAccess],
         [AuditViewRuns],
         [AllowAllRowsAPI],
         [AllowCreateAPI],
         [AllowUpdateAPI],
         [AllowDeleteAPI],
         [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d',
         'MJ_BizApps_Contracts: Contract Orders',
         'Contract Orders',
         'An order this contract governs. The contract''s renewal terms (annual increase, whether a discount continues) are copied to every subscription the order''s lines created. Written when a deal closes with both a contract and an order, or by hand for an order the contract covers.',
         NULL,
         'ContractOrder',
         'vwContractOrders',
         '${flyway:defaultSchema}',
         1,
         1,
         0,
         1,
         0,
         0,
         0,
         1,
         1,
         1,
         1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add entity MJ_BizApps_Contracts: Contract Orders to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                    ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                    ('891E92FE-561A-4FED-8EDC-E2D96FB18541', '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier), CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier) AND [RoleID] = CAST('E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier), CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier) AND [RoleID] = CAST('DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                ([EntityID], [RoleID], [Type], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt])
              SELECT CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier), CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier), 'Allow', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE()
              WHERE NOT EXISTS (
                SELECT 1 FROM [${mjSchema}].[EntityPermission]
                WHERE [EntityID] = CAST('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AS uniqueidentifier) AND [RoleID] = CAST('DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AS uniqueidentifier) AND [Type] = 'Allow'
              );

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractOrder */
UPDATE [${flyway:defaultSchema}].[ContractOrder] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractOrder___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractOrder */
UPDATE [${flyway:defaultSchema}].[ContractOrder] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractOrder */
ALTER TABLE [${flyway:defaultSchema}].[ContractOrder] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractOrder___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to insert 6 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '28f8dfb4-9339-4a7f-8e6e-b04796b2346d' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = 'ID')) BEGIN
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
            '28f8dfb4-9339-4a7f-8e6e-b04796b2346d',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
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
            0,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd6f1f326-efd6-4db3-bf6c-890c9fd9e631' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = 'ContractID')) BEGIN
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
            'd6f1f326-efd6-4db3-bf6c-890c9fd9e631',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
            'ContractID',
            'Contract ID',
            'The contract whose terms apply to the order.',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '275211a7-c882-4e63-9eb5-bd6063ce2bf5' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = 'OrderID')) BEGIN
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
            '275211a7-c882-4e63-9eb5-bd6063ce2bf5',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
            'OrderID',
            'Order ID',
            'The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.',
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
            'FC529BC8-FF09-44A9-B454-26EAFDAC791B',
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b6fbe26d-8aaf-4366-ab20-5211751c4dbb' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = '__mj_CreatedAt')) BEGIN
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
            'b6fbe26d-8aaf-4366-ab20-5211751c4dbb',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
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
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f49138c4-d431-4225-ad63-caf13458b382' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = '__mj_UpdatedAt')) BEGIN
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
            'f49138c4-d431-4225-ad63-caf13458b382',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
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
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5f016939-6a80-450d-b51c-84fda3e217a2' OR (EntityID = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND Name = 'CarryDiscountOnRenewal')) BEGIN
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
            '5f016939-6a80-450d-b51c-84fda3e217a2',
            '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- Entity: MJ_BizApps_Contracts: Contracts
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'),
            'CarryDiscountOnRenewal',
            'Carry Discount On Renewal',
            'Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.',
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

/* Deterministic search-flag hygiene — clear AllowUserSearchAPI */

         UPDATE [${mjSchema}].[Entity]
         SET [AllowUserSearchAPI] = 0
         WHERE [ID] IN (
            SELECT e.[ID]
            FROM [${mjSchema}].[Entity] e
            WHERE e.[AllowUserSearchAPI] = 1
              AND e.[AutoUpdateAllowUserSearchAPI] = 1
              AND e.[VirtualEntity] = 0
              AND ISNULL(e.[FullTextSearchEnabled], 0) = 0
              AND e.[SchemaName] NOT IN ('sys','staging','dbo','${mjSchema}','__mj_BizAppsAccounting','__mj_BizAppsCommon','__mj_BizAppsOrders','__mj_BizAppsTasks')
              AND NOT EXISTS (
               SELECT 1 FROM [${mjSchema}].[EntityField] f2
               WHERE f2.[EntityID] = e.[ID]
                 AND f2.[IncludeInUserSearchAPI] = 1
            )
         );


/* Create Entity Relationship: MJ_BizApps_Orders: Order Headers -> MJ_BizApps_Contracts: Contract Orders (One To Many via OrderID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '333cb15d-7154-405b-a2c1-706466376188' OR ([EntityID] = 'FC529BC8-FF09-44A9-B454-26EAFDAC791B' AND [RelatedEntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND [RelatedEntityJoinField] = 'OrderID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('333cb15d-7154-405b-a2c1-706466376188', 'FC529BC8-FF09-44A9-B454-26EAFDAC791B', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', 'OrderID', 'One To Many', 1, 1, 17, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Orders (One To Many via ContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'f0557b4c-8817-4773-af59-47e278a5fa27' OR ([EntityID] = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND [RelatedEntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND [RelatedEntityJoinField] = 'ContractID')
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('f0557b4c-8817-4773-af59-47e278a5fa27', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', 'ContractID', 'One To Many', 1, 1, 4, GETUTCDATE(), GETUTCDATE())
   END;

/* Index for Foreign Keys for ContractOrder */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractID in table ContractOrder
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractOrder_ContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractOrder]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractOrder_ContractID ON [${flyway:defaultSchema}].[ContractOrder] ([ContractID]);

-- Index for foreign key OrderID in table ContractOrder
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractOrder_OrderID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractOrder]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractOrder_OrderID ON [${flyway:defaultSchema}].[ContractOrder] ([OrderID]);

/* SQL text to update entity field related entity name field map for entity field ID D6F1F326-EFD6-4DB3-BF6C-890C9FD9E631 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='D6F1F326-EFD6-4DB3-BF6C-890C9FD9E631', @RelatedEntityNameFieldMap='Contract';

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
    [__mj_BizAppsCommon].[Organization] AS mjBizAppsCommonOrganization_CustomerOrganizationID
  ON
    [c].[CustomerOrganizationID] = mjBizAppsCommonOrganization_CustomerOrganizationID.[ID]
LEFT OUTER JOIN
    [__mj_BizAppsCommon].[Person] AS mjBizAppsCommonPerson_PrimaryContactPersonID
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

/* Refresh layered base view for MJ_BizApps_Contracts: Contracts after its inner view changed */
EXEC sp_refreshview '${flyway:defaultSchema}.vwContractsGenerated';
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'EXEC sp_refreshview ''${flyway:defaultSchema}.vwContracts'';';
END

GO

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
    @PredictedRenewalScoredAt datetimeoffset = NULL,
    @CarryDiscountOnRenewal bit = NULL
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
                [PredictedRenewalScoredAt],
                [CarryDiscountOnRenewal]
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
                CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, NULL) END,
                ISNULL(@CarryDiscountOnRenewal, 0)
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
                [PredictedRenewalScoredAt],
                [CarryDiscountOnRenewal]
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
                CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, NULL) END,
                ISNULL(@CarryDiscountOnRenewal, 0)
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
    @PredictedRenewalScoredAt datetimeoffset = NULL,
    @CarryDiscountOnRenewal bit = NULL
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
        [PredictedRenewalScoredAt] = CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, [PredictedRenewalScoredAt]) END,
        [CarryDiscountOnRenewal] = ISNULL(@CarryDiscountOnRenewal, [CarryDiscountOnRenewal])
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

/* SQL text to update entity field related entity name field map for entity field ID 275211A7-C882-4E63-9EB5-BD6063CE2BF5 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='275211A7-C882-4E63-9EB5-BD6063CE2BF5', @RelatedEntityNameFieldMap='Order';

/* Base View SQL for MJ_BizApps_Contracts: Contract Orders */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: vwContractOrders
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Orders
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractOrder
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractOrders]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractOrders];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractOrders]
AS
SELECT
    c.*,
    mjBizAppsContractsContract_ContractID.[ContractNumber] AS [Contract],
    mjBizAppsOrdersOrderHeader_OrderID.[OrderNumber] AS [Order]
FROM
    [${flyway:defaultSchema}].[ContractOrder] AS c
INNER JOIN
    [${flyway:defaultSchema}].[Contract] AS mjBizAppsContractsContract_ContractID
  ON
    [c].[ContractID] = mjBizAppsContractsContract_ContractID.[ID]
INNER JOIN
    [__mj_BizAppsOrders].[OrderHeader] AS mjBizAppsOrdersOrderHeader_OrderID
  ON
    [c].[OrderID] = mjBizAppsOrdersOrderHeader_OrderID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractOrders] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Orders */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: Permissions for vwContractOrders
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractOrders] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Orders */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spCreateContractOrder
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractOrder
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractOrder]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractOrder];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractOrder]
    @ID uniqueidentifier = NULL,
    @ContractID uniqueidentifier,
    @OrderID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractOrder]
            (
                [ID],
                [ContractID],
                [OrderID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractID,
                @OrderID
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractOrder]
            (
                [ContractID],
                [OrderID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractID,
                @OrderID
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractOrders] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractOrder] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Orders */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractOrder] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Orders */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spUpdateContractOrder
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractOrder
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractOrder]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractOrder];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractOrder]
    @ID uniqueidentifier,
    @ContractID uniqueidentifier = NULL,
    @OrderID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractOrder]
    SET
        [ContractID] = ISNULL(@ContractID, [ContractID]),
        [OrderID] = ISNULL(@OrderID, [OrderID])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractOrders] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractOrders]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractOrder] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractOrder table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractOrder]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractOrder];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractOrder
ON [${flyway:defaultSchema}].[ContractOrder]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractOrder]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractOrder] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Orders */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractOrder] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Orders */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spDeleteContractOrder
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractOrder
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractOrder]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractOrder];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractOrder]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractOrder]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractOrder] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Orders */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractOrder] TO [cdp_Developer], [cdp_Integration];

/* SQL text to insert 2 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'aab3d822-2597-453d-88b6-b8df6f467d14' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = 'Contract')) BEGIN
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
            'aab3d822-2597-453d-88b6-b8df6f467d14',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
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

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0e381161-4f50-4a1d-b9f8-540364171db5' OR (EntityID = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND Name = 'Order')) BEGIN
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
            '0e381161-4f50-4a1d-b9f8-540364171db5',
            '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', -- Entity: MJ_BizApps_Contracts: Contract Orders
            (SELECT COALESCE(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'),
            'Order',
            'Order',
            NULL,
            'nvarchar',
            80,
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

/* Refresh custom base views for modified entities so schema changes are picked up */
EXEC sp_refreshview '${flyway:defaultSchema}.vwContractsGenerated';
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
BEGIN
    EXEC sp_executesql N'EXEC sp_refreshview ''${flyway:defaultSchema}.vwContracts'';';
END;

