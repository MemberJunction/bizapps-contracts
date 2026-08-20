-- =============================================================================
-- V202608192340 — ContractTemplateModification.ModificationText becomes NOT NULL.
-- =============================================================================
-- WHY THIS COLUMN AND NOT THE OTHER ONE. A modification row asserts "this clause was
-- negotiated". `ProvisionText` holds the standard wording; `ModificationText` holds
-- what the paper says instead, and the PAIR is the app's reason to exist -- a dispute
-- needs the comparison, not either half. A row that names a provision and records no
-- negotiated language is therefore the one row in this schema that cannot be worth
-- keeping: it says a deviation exists and refuses to say what it is.
--
-- TWO CHANGES, not one: the column becomes NOT NULL *and* gains a CHECK forbidding blank. The
-- second is not belt-and-braces -- see step 3 below, where the empty string was measured passing
-- the NOT NULL.
--
-- `Notes` stays nullable, deliberately. Commentary about who negotiated it is
-- genuinely optional, and making it required would only teach people to type "n/a".
--
-- ORDER MATTERS, AND IT IS THE WHOLE MIGRATION. Backfill first, THEN alter. An
-- `ALTER COLUMN ... NOT NULL` that meets a single NULL fails, and it fails AFTER
-- Flyway has recorded nothing -- so the migration is half-applied on precisely the
-- databases that have real content, and clean on the empty ones where nobody would
-- notice. Doing both in one migration means there is no window in which the column is
-- required and the data does not satisfy it.
--
-- THE FILLER TEXT IS DELIBERATELY UGLY. It has to be findable: a backfilled row is not
-- a modification anyone recorded, and someone reviewing the negotiated language needs
-- to be able to separate "nobody typed this" from "the paper really says this". A
-- neutral placeholder like an empty string or a single space would satisfy the
-- constraint and hide the distinction forever.
--
-- Measured on this instance before writing it: 3 modification rows, 0 of them NULL --
-- so the backfill is a no-op here. It is not decoration: the constraint is what makes
-- the app's central pair reliable, and any database seeded before today can have them.
-- =============================================================================

-- 1. Backfill. Guarded on the column still being nullable so a re-run on an
--    already-migrated database touches nothing (the UPDATE would be a no-op anyway,
--    but reading a column that is already NOT NULL for NULLs is a wasted scan).
IF EXISTS (
    SELECT 1
      FROM sys.columns c
     WHERE c.[object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateModification]')
       AND c.[name]      = 'ModificationText'
       AND c.[is_nullable] = 1
)
BEGIN
    UPDATE [${flyway:defaultSchema}].[ContractTemplateModification]
       SET [ModificationText] = N'[NOT RECORDED — backfilled when ModificationText became required]'
     WHERE [ModificationText] IS NULL
        OR LEN(LTRIM(RTRIM([ModificationText]))) = 0;
END
GO

-- 2. Require it. Idempotent on the same `is_nullable` probe, because ALTER COLUMN is
--    not conditional on its own and re-running it against a NOT NULL column is a
--    needless table rewrite rather than an error.
IF EXISTS (
    SELECT 1
      FROM sys.columns c
     WHERE c.[object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateModification]')
       AND c.[name]      = 'ModificationText'
       AND c.[is_nullable] = 1
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification]
        ALTER COLUMN [ModificationText] NVARCHAR(MAX) NOT NULL;
END
GO

-- 3. NOT NULL is NOT ENOUGH, and this was measured rather than reasoned about. With only the
--    ALTER above applied, a GraphQL update setting ModificationText to '' was ACCEPTED (probed
--    against this instance on 2026-08-20): SQL Server's NOT NULL permits the empty string, and
--    MJ's `EntityField.Validate()` nullability check tests null/undefined only. So the column
--    was required and still able to hold nothing, which is exactly the state this migration
--    exists to forbid -- a row asserting "this clause was negotiated" that does not say how.
--
--    A CHECK is the right tier because the rule reads one column of the SAME ROW: it needs no
--    other table, so it is the cheapest possible floor and nothing -- raw SQL, a future service,
--    another app -- can get underneath it.
--
--    IT ALSO BUYS THE TYPESCRIPT SIDE FOR FREE, which is the reason not to hand-write a blank
--    check in the entity subclass. CodeGen turns a CHECK expression into a generated `Validate()`
--    method with a field-named `Source` (verified in this repo: all seven Contract CHECKs have
--    one). Writing it by hand as well would be a second copy of one rule, free to drift the next
--    time the constraint changes -- the failure R-2 of plans/backend-requirements.md was
--    withdrawn for proposing.
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE [parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateModification]')
       AND [name] = 'CK_ContractTemplateModification_TextNotBlank'
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateModification]
        ADD CONSTRAINT [CK_ContractTemplateModification_TextNotBlank]
            CHECK (LEN(LTRIM(RTRIM([ModificationText]))) > 0);
END
GO


















































-- -----------------------------------------------------------------------------
-- The 50 blank lines above separate hand-written DDL from CodeGen output, per this
-- repo's convention (migration-conventions.test.ts asserts exactly 50).
--
-- WHY THESE TWO PROCEDURES ARE HERE AT ALL. Nullability is not a cosmetic property of
-- a column as far as CodeGen is concerned: it decides the CRUD procedure's SIGNATURE.
-- A nullable column gets a companion `@<Field>_Clear bit = 0` parameter and a
-- `CASE WHEN @X_Clear = 1 THEN NULL ELSE ISNULL(@X, [X]) END` assignment, because
-- "set this to NULL" and "do not change this" are different intentions that a single
-- nullable parameter cannot express. A NOT NULL column needs neither -- there is no
-- longer a NULL to mean -- so CodeGen drops the parameter and collapses the
-- assignment to a plain ISNULL. On the create side `@ModificationText nvarchar(MAX)`
-- loses its `= NULL` default and becomes required.
--
-- So the ALTER above without these below would leave the database with procedures that
-- still advertise a `_Clear` flag for a column that cannot be cleared, and MJ's
-- generated GraphQL layer -- regenerated from the same metadata -- would stop sending
-- it. Applying only the first half of this migration produces a schema whose DDL and
-- whose CRUD surface disagree.
--
-- `vwContractTemplateModifications` is deliberately NOT re-emitted. It is `SELECT c.*`
-- plus two FK display joins, so it surfaces the column's new nullability without being
-- regenerated, and re-emitting an unchanged view adds churn that reads like a change.
-- Same judgement, and the same wording, as V202608192100.
--
-- The `__mj.EntityField.AllowsNull` metadata row is also not carried here, for the
-- reason MJ's own guide gives: CodeGen runs AFTER migrations on every install, and it
-- is what owns entity metadata. A migration that also wrote it would give one fact two
-- owners. Verified on this instance: `mj migrate` left AllowsNull = 1 and the CodeGen
-- run that followed set it to 0.
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand below this line.
-- -----------------------------------------------------------------------------

------------------------------------------------------------
-- spCreateContractTemplateModification — regenerated: @ModificationText is now
-- required and its _Clear companion is gone.
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spCreateContractTemplateModification];
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

------------------------------------------------------------
-- spUpdateContractTemplateModification — regenerated: same reason. The assignment
-- collapses from the _Clear CASE to a plain ISNULL.
------------------------------------------------------------
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spUpdateContractTemplateModification];
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
