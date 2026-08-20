-- =============================================================================
-- V202608192100 — ContractType.ParentStatusRequirement replaces a name match and
--                 the derived IsChangeOrder column.
-- =============================================================================
-- WHAT THIS REPLACES, AND WHY IT WAS WRONG. The server subclass enforced "a change
-- order must name the contract it changes" by reading the contract's type row and
-- comparing its NAME to the string 'Change Order'. A display name is not a rule:
-- rename that row in the UI — an ordinary thing to do to a lookup value — and the
-- rule silently stops firing, with no error and nothing failing. The type table
-- carried no column expressing the constraint, so the check had nowhere else to
-- look. Now it does.
--
-- THREE STATES, on the TYPE because that is what the restriction is a property of:
--
--   'Required'    a contract of this type MUST name a ParentContractID. Change Order:
--                 a change order that amends nothing is not a change order, and it
--                 would never appear in the original agreement's lineage.
--   'Prohibited'  a contract of this type must NOT name one — it is a root agreement.
--   NULL          unrestricted. The default, and the honest answer for Order Form,
--                 Statement of Work and Payment Link: each of those CAN sit under a
--                 master agreement and can equally stand alone, and inventing a rule
--                 to make the column look complete would be inventing a constraint
--                 the business does not have.
--
-- Modelled as NVARCHAR + CHECK rather than a bit pair or a lookup table because that
-- is how MJ models an enum: CodeGen's ParseCheckConstraints reads the constraint into
-- the field's ValueList metadata, so the UI renders a dropdown and the generated
-- entity gets a union type, with no further work. A bit pair (CanHaveParent /
-- MustHaveParent) would also encode "neither", which is not a state that means
-- anything.
--
-- ⚠ SCOPE: this is the PARENT axis only — may this type of contract have a parent.
-- Whether a change order may ITSELF be amended by another change order is a separate
-- question on a separate axis, deliberately not answered here; a single column cannot
-- carry both without four values that read ambiguously.
--
-- ALSO IN THIS MIGRATION: the derived IsChangeOrder column is dropped from vwContracts
-- and its EntityField metadata row is removed. It restated `ParentContractID IS NOT
-- NULL` under a name that implied a TYPE distinction it never read — a Change Order
-- with its parent not yet set read IsChangeOrder = 0, and an Order Form sitting under
-- a master agreement read 1. The FK answers the "does it have a parent" question
-- directly, and this new column answers the "what does its type allow" question
-- properly, so the middle abstraction was only ever able to mislead.
-- =============================================================================

ALTER TABLE [${flyway:defaultSchema}].[ContractType]
    ADD [ParentStatusRequirement] NVARCHAR(20) NULL;
GO

ALTER TABLE [${flyway:defaultSchema}].[ContractType]
    ADD CONSTRAINT [CK_ContractType_ParentStatusRequirement]
        CHECK ([ParentStatusRequirement] IN ('Required', 'Prohibited'));
GO

EXEC sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'Whether a contract of this type must, must not, or may name a ParentContractID: ''Required'' (a Change Order amends something, so it has to say what), ''Prohibited'' (a root agreement), or NULL for no restriction. Enforced in ContractEntityServer.ValidateAsync. Replaced a comparison against this row''s NAME, which stopped working the moment anyone renamed it.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractType',
    @level2type = N'COLUMN', @level2name = N'ParentStatusRequirement';
GO

-- NO SEED VALUE HERE, deliberately (Marcelo, 2026-08-19). Data that has to exist in the database is
-- seeded through the metadata sync system, not through migrations: `metadata/contract-types/` already
-- owns all four ContractType rows with fixed UUIDs, so `ParentStatusRequirement` belongs beside
-- `RequiresExecutedDocument` in that file and arrives via `mj sync push`. A migration that also set it
-- would give the same value two owners, and the migration's copy would silently win on a fresh install
-- until the next push — which is the drift this app keeps designing away.
--
-- This migration therefore adds the COLUMN and its constraint. What goes IN it is metadata's job.

-- Drop the IsChangeOrder virtual EntityField. The column disappears from vwContracts in
-- V202608182001; leaving its metadata row behind would leave MJ describing a column the
-- view no longer returns, which surfaces as a null-valued field on every form and grid
-- rather than as an error.
DELETE f
  FROM [${mjSchema}].[EntityField] f
 INNER JOIN [${mjSchema}].[Entity] e ON e.[ID] = f.[EntityID]
 WHERE e.[SchemaName] = '${flyway:defaultSchema}'
   AND e.[BaseTable]  = 'Contract'
   AND f.[Name]       = 'IsChangeOrder';
GO

-- -----------------------------------------------------------------------------
-- The 50 blank lines below separate hand-written DDL from CodeGen output, per this
-- repo's convention (migration-conventions.test.ts asserts exactly 50).
--
-- WHY THIS SECTION WAS ASSEMBLED BY HAND. `mjdev app capture <slug> <app> codegen`
-- is the sanctioned way to produce it, and it cannot run on this instance: it dies
-- at provider boot with "[Fatal] Cannot read properties of undefined (reading
-- 'Instance')" — the same failure as `mjdev app migrate` (plans/WORKAROUNDS.md
-- W-2). So the objects CodeGen rewrote in the database were read back out of it
-- with OBJECT_DEFINITION and pasted below. The content is CodeGen's; only the
-- transport is manual.
--
-- Only the two procedures are here. `vwContractTypes` is `SELECT c.*`, so it
-- surfaces the new column without being regenerated, and re-emitting an unchanged
-- view would add churn that reads like a change.
-- -----------------------------------------------------------------------------


















































-- This was generated by the MemberJunction CodeGen tool.

------------------------------------------------------------
-- spCreateContractType — regenerated for ParentStatusRequirement
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spCreateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractType]
    @ID uniqueidentifier = NULL,
    @Name nvarchar(100),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @RequiresExecutedDocument bit = NULL,
    @Status nvarchar(10) = NULL,
    @ParentStatusRequirement_Clear bit = 0,
    @ParentStatusRequirement nvarchar(20) = NULL
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
                [ParentStatusRequirement]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active'),
                CASE WHEN @ParentStatusRequirement_Clear = 1 THEN NULL ELSE ISNULL(@ParentStatusRequirement, NULL) END
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
                [ParentStatusRequirement]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@RequiresExecutedDocument, 1),
                ISNULL(@Status, 'Active'),
                CASE WHEN @ParentStatusRequirement_Clear = 1 THEN NULL ELSE ISNULL(@ParentStatusRequirement, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO

------------------------------------------------------------
-- spUpdateContractType — regenerated for ParentStatusRequirement
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spUpdateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType]
    @ID uniqueidentifier,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @RequiresExecutedDocument bit = NULL,
    @Status nvarchar(10) = NULL,
    @ParentStatusRequirement_Clear bit = 0,
    @ParentStatusRequirement nvarchar(20) = NULL
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
        [ParentStatusRequirement] = CASE WHEN @ParentStatusRequirement_Clear = 1 THEN NULL ELSE ISNULL(@ParentStatusRequirement, [ParentStatusRequirement]) END
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
