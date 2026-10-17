-- =============================================================================
-- V202610121200 — the provision guard refuses with THROW alone (#87).
-- =============================================================================
-- trg_ContractTemplateProvision_Immutability refused an UPDATE (50102) or DELETE
-- (50101) of a provision on a PUBLISHED template with ROLLBACK TRANSACTION and then
-- THROW. MemberJunction runs every save as INSERT INTO @ResultTable EXEC sp..., and
-- every delete of an entity that tracks record changes the same way. SQL Server
-- forbids ROLLBACK anywhere inside an INSERT-EXEC, including in a trigger the
-- procedure fires, so the ROLLBACK itself failed with error 3915 ("Cannot use the
-- ROLLBACK statement within an INSERT-EXEC statement") and the caller never saw the
-- rule that refused the write. The baseline's header said spUpdate and spDelete are
-- not called that way; they are.
--
-- THROW alone still undoes the write: a trigger runs with XACT_ABORT ON, so the
-- error dooms and rolls back the whole transaction, including earlier writes in a
-- caller's transaction. The INSERT branch already worked this way.
--
-- The body is the baseline's (B202608040001, section 6.2) with the two ROLLBACK
-- lines removed and the comments corrected. Conditions, error numbers, messages and
-- check order are unchanged. A trigger carries no MJ metadata, so there is no
-- CodeGen capture.
-- =============================================================================

CREATE OR ALTER TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- No branch issues ROLLBACK: MJ reaches this trigger through INSERT ... EXEC on every
    -- create, update and delete, where ROLLBACK raises 3915 in place of the rule's message.
    -- THROW dooms the transaction on its own.

    -- INSERT
    IF NOT EXISTS (SELECT 1 FROM deleted)
       AND EXISTS (
            SELECT 1 FROM inserted i
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = i.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        THROW 50104, 'A provision cannot be added to a PUBLISHED agreement version — that would silently grow the terms of every contract already referencing it. Publish a new version instead.', 1;
    END;

    -- DELETE
    IF NOT EXISTS (SELECT 1 FROM inserted)
       AND EXISTS (
            SELECT 1 FROM deleted d
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = d.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        THROW 50101, 'A provision cannot be deleted from a PUBLISHED agreement version — that would remove a clause from an agreement someone signed. Publish a new version instead; a published version is a historical record.', 1;
    END;

    -- UPDATE: value comparison, not mere "an UPDATE happened" — `mj sync push` re-pushes every
    -- provision row and a trigger fires on identical values, so without this an ordinary seed push
    -- would fail. NULL-safe on ProvisionText because `i.x <> d.x` is UNKNOWN when either side is NULL.
    -- Description and ProvisionSortKey stay outside the frozen set.
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
        THROW 50102, 'ProvisionNumber, Title, ProvisionText and the owning template cannot change on a PUBLISHED agreement version — editing one rewrites what a customer agreed to. Publish a new version instead. (Description remains editable.)', 1;
    END;
END;
GO
