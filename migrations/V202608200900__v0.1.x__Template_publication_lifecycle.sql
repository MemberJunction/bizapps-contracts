-- =============================================================================
-- V202608200900 — ContractTemplate gains a publication lifecycle, and provision
--                 immutability re-keys onto it (including the missing INSERT guard).
-- =============================================================================
-- TWO PROBLEMS, ONE CAUSE. R-1 froze a referenced template's provisions against UPDATE and
-- DELETE. It was simultaneously TOO LOOSE and TOO STRICT, and both halves come from gating on
-- "is this template referenced" when the honest question is "has this template been published".
--
--   TOO LOOSE: the trigger was `AFTER UPDATE, DELETE`. **INSERT was unguarded**, so a clause
--   could be ADDED to an agreement version customers had already signed -- the same harm R-1
--   exists to prevent, and the case that actually surfaced this (Marcelo, 2026-08-20).
--
--   TOO STRICT: a provision added AFTER a contract referenced the template was never part of
--   what anyone signed, yet it became immediately unremovable. Worse, the live data has
--   referenced templates that are plainly still being authored -- "Master Agreement —
--   2026-07-15" has **4 contracts and 1 provision** -- so "referenced therefore frozen"
--   strands real work with no way to finish it.
--
-- SO PUBLICATION BECOMES AN EXPLICIT ACT rather than something inferred from references:
--
--   Draft      freely editable; provisions added, edited and deleted at will. May not be
--              NEWLY referenced by a contract.
--   Published  frozen -- no INSERT, no UPDATE of the terms, no DELETE. Referenceable.
--
-- Terms change on a published version? Publish a NEW VERSION. That is what ContractTemplate's
-- VersionLabel / IntroducedDate exist for, and it is why provision-level soft-delete was
-- REJECTED (Marcelo, 2026-08-20): it would build a second, finer-grained versioning system
-- beside the one that already exists, and "what did this customer sign" would degrade from
-- "template T" into "the provisions of T active on date X" -- a temporal query, which is
-- precisely what versioning avoids.
--
-- ONE-WAY, DELIBERATELY. Published -> Draft is refused in the entity subclass. A freeze you can
-- lift by flipping a column is not a freeze.
--
-- EVERY EXISTING TEMPLATE BECOMES DRAFT, INCLUDING THE REFERENCED ONES. Nothing here was ever
-- formally published -- the concept is new as of this migration -- and calling the referenced
-- ones Published would freeze the two that are mid-authoring. The rule that keeps the existing
-- 13 contracts valid is that "a contract may not reference a Draft template" polices only NEW
-- references, the same shape R-5 (retired types) and R-12 (unusable templates) already use.
--
-- NO SEED VALUE HERE. `metadata/contract-templates/` owns the rows; the column default plus this
-- backfill set the state, and metadata carries it from the next push onward.
-- =============================================================================

-- 1. The lifecycle column. 'Draft' | 'Published' -- and room on the SAME axis for a future
--    'Withdrawn', which is why this is one Status column rather than a publication flag beside a
--    separate active/retired flag.
IF COL_LENGTH('${flyway:defaultSchema}.ContractTemplate', 'Status') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate]
        ADD [Status] NVARCHAR(20) NOT NULL CONSTRAINT [DF_ContractTemplate_Status] DEFAULT 'Draft';
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE [parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplate]')
       AND [name] = 'CK_ContractTemplate_Status'
)
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate]
        ADD CONSTRAINT [CK_ContractTemplate_Status] CHECK ([Status] IN ('Draft', 'Published'));
GO

EXEC sp_addextendedproperty @name = N'MS_Description',
    @value = N'Publication lifecycle. ''Draft'' — freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. ''Published'' — the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version — that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractTemplate',
    @level2type = N'COLUMN', @level2name = N'Status';
GO

-- 2. Re-key provision immutability onto Status, AND add the INSERT branch that was missing.
--    The `Description` and `ProvisionSortKey` columns stay out of the frozen set for the same
--    reason as before: annotating a document, and a key derived from its own numbering, are not
--    changing what it says. (ProvisionSortKey cannot be written at all -- it is computed.)
IF OBJECT_ID('[${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability];
GO

CREATE TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- INSERT: a published version does not gain clauses. This branch is the one R-1 was missing,
    -- and it is the half that let a signed agreement silently grow.
    IF NOT EXISTS (SELECT 1 FROM deleted)
       AND EXISTS (
            SELECT 1 FROM inserted i
              JOIN [${flyway:defaultSchema}].[ContractTemplate] t ON t.[ID] = i.[ContractTemplateID]
             WHERE t.[Status] = 'Published'
       )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50104, 'A provision cannot be added to a PUBLISHED agreement version — that would silently grow the terms of every contract already referencing it. Publish a new version instead.', 1;
    END;

    -- DELETE: nor does it lose them.
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

    -- UPDATE: and its terms do not change. Value comparison, not mere "an UPDATE happened" --
    -- `mj sync push` re-pushes all 74 provision rows and a trigger fires on identical values, so
    -- without this comparison a routine seed push would fail. NULL-safe on ProvisionText because
    -- `i.x <> d.x` is UNKNOWN when either side is NULL.
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

-- 3. Everything that exists today becomes Draft — see the header. This is a no-op on a fresh
--    install (the default already applies) and idempotent on a re-run.
UPDATE [${flyway:defaultSchema}].[ContractTemplate]
   SET [Status] = 'Draft'
 WHERE [Status] NOT IN ('Draft', 'Published');
GO
