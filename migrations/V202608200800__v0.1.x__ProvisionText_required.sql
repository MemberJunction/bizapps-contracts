-- =============================================================================
-- V202608200800 — ContractTemplateProvision.ProvisionText becomes NOT NULL and not-blank.
-- =============================================================================
-- Same treatment as ModificationText (V202608192340), and for the same reason: a provision is the
-- STANDARD wording of a clause, and a modification is only meaningful read as a PAIR against it. A
-- provision row that names a clause and records no text is half of a comparison a dispute needs --
-- and worse than a missing modification, because every modification pointing at it inherits the gap.
--
-- Marcelo saved an empty one through the UI on 2026-08-20, which is how this was found: the column was
-- nullable and nothing above the database refused it.
--
-- NOT NULL IS NOT ENOUGH, exactly as with ModificationText. SQL Server accepts '' in a NOT NULL column
-- and MJ's `EntityField.Validate()` tests null/undefined only (baseEntity.ts:315 — logged in
-- MJ-UPSTREAM.md, since every app with a required string column has this). So the CHECK is what makes
-- NOT NULL mean what a reader assumes. `> 0`, not a minimum length: one character passes, deliberately.
--
-- CodeGen turns that CHECK into a generated validator, so no blank check is hand-written here (the R-2
-- trap: a second copy of one rule, free to drift).
--
-- ⚠⚠ THE BACKFILL MUST DISABLE R-1's IMMUTABILITY TRIGGER, AND THIS IS THE WHOLE DIFFICULTY.
-- `trg_ContractTemplateProvision_Immutability` (V202608200100) rejects any change to `ProvisionText` on
-- a provision whose template a contract references. The one row needing a backfill here -- provision
-- 20.2 of the Master Agreement -- sits on a template **7 contracts reference**, so the UPDATE below is
-- precisely what that trigger exists to refuse. Without the DISABLE this migration fails, and it fails
-- with the trigger's own message, which reads like a bug in the migration rather than the trigger
-- correctly doing its job.
--
-- Disabling it is legitimate HERE and nowhere casually: the trigger protects agreed terms from being
-- rewritten, and filling in a blank is not rewriting an agreed term -- there was nothing there to
-- agree to. The window is two statements wide and inside this migration's transaction, so a failure
-- rolls the disable back with everything else and the trigger cannot be left off.
--
-- The filler text is deliberately ugly so a reader can tell "nobody typed this" from "the paper says
-- this" -- the same reasoning as ModificationText's.
-- =============================================================================

-- 1. Backfill, with the immutability trigger held off for exactly this UPDATE.
IF EXISTS (
    SELECT 1 FROM __mj_BizAppsContracts.ContractTemplateProvision
     WHERE [ProvisionText] IS NULL OR LEN(LTRIM(RTRIM([ProvisionText]))) = 0
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision]
        DISABLE TRIGGER [trg_ContractTemplateProvision_Immutability];

    UPDATE [${flyway:defaultSchema}].[ContractTemplateProvision]
       SET [ProvisionText] = N'[NOT RECORDED — backfilled when ProvisionText became required]'
     WHERE [ProvisionText] IS NULL
        OR LEN(LTRIM(RTRIM([ProvisionText]))) = 0;

    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision]
        ENABLE TRIGGER [trg_ContractTemplateProvision_Immutability];
END
GO

-- 2. Require it.
IF EXISTS (
    SELECT 1 FROM sys.columns c
     WHERE c.[object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateProvision]')
       AND c.[name] = 'ProvisionText' AND c.[is_nullable] = 1
)
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision]
        ALTER COLUMN [ProvisionText] NVARCHAR(MAX) NOT NULL;
GO

-- 3. And forbid blank, which the NOT NULL does not.
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE [parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateProvision]')
       AND [name] = 'CK_ContractTemplateProvision_TextNotBlank'
)
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision]
        ADD CONSTRAINT [CK_ContractTemplateProvision_TextNotBlank]
            CHECK (LEN(LTRIM(RTRIM([ProvisionText]))) > 0);
GO

-- 4. Belt: the trigger must be back on. If step 1 somehow left it disabled, say so loudly rather than
--    shipping a database whose central immutability guarantee is silently off.
IF EXISTS (
    SELECT 1 FROM sys.triggers
     WHERE [name] = 'trg_ContractTemplateProvision_Immutability' AND [is_disabled] = 1
)
    THROW 50103, 'trg_ContractTemplateProvision_Immutability is DISABLED after the ProvisionText backfill. Provision immutability (R-1) is not being enforced. Re-enable it before using this database.', 1;
GO
