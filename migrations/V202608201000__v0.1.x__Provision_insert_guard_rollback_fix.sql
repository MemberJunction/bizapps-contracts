-- =============================================================================
-- V202608201000 — The INSERT branch must THROW without ROLLBACK.
-- =============================================================================
-- V202608200900 added the missing INSERT guard, and it worked -- the row was refused -- but the user
-- saw this instead of the message:
--
--     Cannot use the ROLLBACK statement within an INSERT-EXEC statement.
--
-- WHY. MJ's provider calls the generated CRUD procedure as `INSERT ... EXEC spCreate...` so it can
-- capture the returned row. SQL Server forbids `ROLLBACK TRANSACTION` anywhere inside an INSERT-EXEC,
-- including in a trigger fired by it. The UPDATE and DELETE branches are unaffected because
-- `spUpdate`/`spDelete` are not invoked that way -- which is exactly why this surfaced only on INSERT
-- and only once a template was actually published.
--
-- THE FIX IS TO REMOVE THE ROLLBACK, NOT TO WEAKEN THE GUARD. A `THROW` inside a trigger raises an
-- error that dooms the transaction, so the INSERT is still refused and nothing is written -- verified
-- after applying, because "the error changed" and "the row is gone" are different claims. The other
-- two branches keep their explicit ROLLBACK: it is the documented shape for a trigger that must undo
-- a statement, and they are not reached through INSERT-EXEC.
--
-- The application-level guard added alongside this (ContractTemplateProvisionEntityServer refuses
-- creating a provision on a published version) is what a user should normally hit. This trigger stays
-- the floor for every other writer, and now it fails with its own message rather than SQL Server's
-- complaint about the mechanism.
-- =============================================================================

IF OBJECT_ID('[${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability];
GO

CREATE TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: no ROLLBACK here -- see the header. THROW dooms the transaction on its own.
    IF NOT EXISTS (SELECT 1 FROM deleted)
       AND EXISTS (
            SELECT 1 FROM inserted i
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = i.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        THROW 50104, 'A provision cannot be added to a PUBLISHED agreement version — that would silently grow the terms of every contract already referencing it. Publish a new version instead.', 1;
    END;

    -- DELETE: not reached through INSERT-EXEC, so the explicit ROLLBACK is both allowed and correct.
    IF NOT EXISTS (SELECT 1 FROM inserted)
       AND EXISTS (
            SELECT 1 FROM deleted d
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = d.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50101, 'A provision cannot be deleted from a PUBLISHED agreement version — that would remove a clause from an agreement someone signed. Publish a new version instead; a published version is a historical record.', 1;
    END;

    -- UPDATE: value comparison, not mere "an UPDATE happened" — `mj sync push` re-pushes every
    -- provision row and a trigger fires on identical values, so without this an ordinary seed push
    -- would fail. NULL-safe on ProvisionText because `i.x <> d.x` is UNKNOWN when either side is NULL.
    IF EXISTS (
        SELECT 1
          FROM deleted d
          JOIN inserted i ON i.[ID] = d.[ID]
          JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = d.[ContractTemplateID]
         WHERE t.[Status] = 'Published'
           AND (
                    i.[ProvisionNumber] <> d.[ProvisionNumber]
                 OR i.[Title]           <> d.[Title]
                 OR ISNULL(CAST(i.[ProvisionText] AS NVARCHAR(MAX)), N'') <> ISNULL(CAST(d.[ProvisionText] AS NVARCHAR(MAX)), N'')
                 OR ISNULL(i.[ContractTemplateID], '00000000-0000-0000-0000-000000000000')
                    <> ISNULL(d.[ContractTemplateID], '00000000-0000-0000-0000-000000000000')
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50102, 'ProvisionNumber, Title, ProvisionText and the owning template cannot change on a PUBLISHED agreement version — editing one rewrites what a customer agreed to. Publish a new version instead. (Description remains editable.)', 1;
    END;
END;
GO
