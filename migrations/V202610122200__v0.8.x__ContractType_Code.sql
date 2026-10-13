-- =============================================================================
-- V202610122200 — a stable Code on ContractType.
-- =============================================================================
-- Issue #96. Besides its ID, a contract type's only unique key was its Name, so
-- another app that creates contracts had to find a type by its display label.
-- bizapps-sales does exactly that when a won deal creates a contract: its policy
-- names "Order Form", and renaming that type in Configuration stops Closed Won
-- from creating contracts, with nothing pointing at the rename as the cause.
--
-- Code is the identifier a caller holds instead: UPPER_SNAKE, unique, required,
-- and never derived from the Name again after this migration sets it. A label
-- can change freely; the Code is what other apps and metadata reference. This
-- is the shape bizapps-tasks gave TaskType.Code.
--
-- WHY FOUR STATEMENTS AND NOT ONE ALTER TABLE ... ADD. The convention here is
-- one ADD with its constraints inline (V202609140100). That works for nullable
-- columns. A required, unique column on a table that already has rows cannot be
-- added in one statement: there is no default that is unique per row, so the
-- column is added nullable, every row is given a code, and only then is it made
-- NOT NULL and unique. No IF guards: the migration runs once, in order.
--
-- THE SHIPPED TYPES ARE SET BY ID, not by name, so a host that has already
-- renamed one still gets the intended code. Every other row (a type a host
-- created itself) takes its Name in UPPER_SNAKE. If two such names collapse to
-- the same code, UQ_ContractType_Code fails this migration and names the
-- duplicate; rename one type and rerun.
-- =============================================================================

ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD
    [Code] NVARCHAR(50) NULL;
GO

UPDATE [${flyway:defaultSchema}].[ContractType] SET [Code] = N'ORDER_FORM'        WHERE [ID] = '33333333-0000-4000-8000-000000001001';
UPDATE [${flyway:defaultSchema}].[ContractType] SET [Code] = N'STATEMENT_OF_WORK' WHERE [ID] = '33333333-0000-4000-8000-000000001002';
UPDATE [${flyway:defaultSchema}].[ContractType] SET [Code] = N'PAYMENT_LINK'      WHERE [ID] = '33333333-0000-4000-8000-000000001003';
UPDATE [${flyway:defaultSchema}].[ContractType] SET [Code] = N'CHANGE_ORDER'      WHERE [ID] = '33333333-0000-4000-8000-000000001004';

UPDATE [${flyway:defaultSchema}].[ContractType]
SET [Code] = LEFT(UPPER(REPLACE(LTRIM(RTRIM([Name])), N' ', N'_')), 50)
WHERE [Code] IS NULL;
GO

ALTER TABLE [${flyway:defaultSchema}].[ContractType] ALTER COLUMN [Code] NVARCHAR(50) NOT NULL;
GO

ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD
    CONSTRAINT [UQ_ContractType_Code] UNIQUE ([Code]);
GO

---------------------------------------------------------------------------
-- Description. CodeGen copies it onto the EntityField row, so this is the
-- text an admin reads next to the field on the Contract Type form.
---------------------------------------------------------------------------
EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Stable machine code other apps and metadata use to find this type (for example ORDER_FORM). Unique. Unlike Name, it is not a label: renaming the type leaves the Code alone, and changing the Code breaks every caller that names it.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractType',
    @level2type=N'COLUMN', @level2name=N'Code';
GO
