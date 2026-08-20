-- =============================================================================
-- V202608200100 — A referenced template's provisions become immutable.
-- =============================================================================
-- THE APP'S CENTRAL PROMISE, PREVIOUSLY UNENFORCED. A template version is a historical
-- record: a customer who signed in June 2026 stays bound to the June 2026 version. But
-- `ProvisionNumber`, `Title` and `ProvisionText` were freely editable on a template that
-- signed contracts already incorporate. Editing one silently rewrote what a customer
-- agreed to -- and every ContractTemplateModification beside it now compares negotiated
-- language against standard language that was never offered. Nothing errored. The
-- contract still rendered. That is the worst shape a defect can have.
--
-- WHAT IS FROZEN, AND WHAT IS NOT. The three columns above are the TERMS. `Description`
-- and `Sequence` are not: ordering a document and annotating it internally are not
-- changing what it says, so they stay editable on a referenced template.
--
-- THE GATE IS ANY REFERENCE (Marcelo, 2026-08-20). Not "any executed contract" -- a
-- person drafting does not expect the provision to shift under them either, so a Draft
-- carve-out buys nothing and costs a hole.
--
-- WHY A TRIGGER *AND* CODE. The subclass exists so a human sees a sentence naming the
-- field and saying what to do instead (publish a new version). The trigger is the floor
-- nothing can get under -- raw SQL, a future service, another app, a data load. Rewriting
-- signed terms is the case where a bypass is silent corruption rather than a bad edit in
-- our own UI, which is exactly the bar ADR/§7 sets for spending a trigger. Same
-- belt-and-braces as accounting's trg_JournalEntry_Immutability, whose shape this copies.
--
-- ⚠⚠ THE VALUE COMPARISON IS NOT OPTIONAL, AND THIS IS THE TRAP.
-- `metadata/contract-provisions/.contract-provisions.json` holds all 73 provisions and is
-- pushed by `mj sync push` with `updateExistingRecords: true`. **A trigger fires on UPDATE
-- even when every value is identical.** So a trigger written as "an UPDATE happened on a
-- referenced provision -> reject" would break a routine seed re-push the moment any
-- contract references the Master Agreement -- which is constantly -- and the breakage
-- would look like a metadata problem, not a trigger problem. Comparing OLD vs NEW lets an
-- identical re-push pass untouched. Accounting's triggers dodge the same trap the same way.
--
-- NULL-SAFETY: `ProvisionText` is nullable, and `i.x <> d.x` is UNKNOWN (not true) when
-- either side is NULL -- so a NULL-to-value edit would slip through a naive comparison.
-- ISNULL to a sentinel, and CAST first because it is NVARCHAR(MAX). `ProvisionNumber` and
-- `Title` are NOT NULL, so a plain `<>` is correct and clearer for those.
--
-- SET-BASED: one EXISTS over `deleted` joined to `inserted`, so a bulk provision edit
-- costs one probe per STATEMENT rather than per row. The reference probe is an index seek
-- on IDX_AUTO_MJ_FKEY_Contract_ContractTemplateID that stops at the first hit.
-- =============================================================================

IF OBJECT_ID('[${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability];
GO

CREATE TRIGGER [${flyway:defaultSchema}].[trg_ContractTemplateProvision_Immutability]
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    -- DELETE: refuse when any deleted provision belonged to a template a contract references.
    -- Deleting a clause out of a signed agreement is the same act as rewriting it.
    IF NOT EXISTS (SELECT 1 FROM inserted)
       AND EXISTS (
            SELECT 1
              FROM deleted d
             WHERE EXISTS (
                       SELECT 1
                         FROM [${flyway:defaultSchema}].[Contract] c
                        WHERE c.[ContractTemplateID] = d.[ContractTemplateID]
                   )
       )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50101, 'A provision cannot be deleted from a template that contracts already incorporate — that would remove a clause from an agreement someone signed. Publish a new template version instead; a referenced version is a historical record.', 1;
    END;

    -- UPDATE: refuse only when a TERM actually changed. Description and Sequence are absent
    -- from this list on purpose, and so is the identical-values case (see the header).
    IF EXISTS (
        SELECT 1
          FROM deleted d
          JOIN inserted i ON i.[ID] = d.[ID]
         WHERE (
                    i.[ProvisionNumber] <> d.[ProvisionNumber]
                 OR i.[Title]           <> d.[Title]
                 OR ISNULL(CAST(i.[ProvisionText] AS NVARCHAR(MAX)), N'') <> ISNULL(CAST(d.[ProvisionText] AS NVARCHAR(MAX)), N'')
               )
           AND EXISTS (
                    SELECT 1
                      FROM [${flyway:defaultSchema}].[Contract] c
                     WHERE c.[ContractTemplateID] = d.[ContractTemplateID]
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50102, 'ProvisionNumber, Title and ProvisionText cannot change on a template that contracts already incorporate — editing one rewrites what a customer agreed to. Publish a new template version instead. (Description and Sequence remain editable.)', 1;
    END;
END;
GO
