-- =============================================================================
-- V202608200500 — R-12 part 1 of 2: SourceURL becomes nullable, and ContractTemplate
--                 moves to the LAYERED base-view topology.
-- =============================================================================
-- ⚠ THIS FILE MUST LAND BEFORE THE NEXT CODEGEN RUN, and the reason is BUILD-STATE §5
-- gotcha 6. CodeGen owns the base view for every entity. If the entity still says
-- `BaseViewGenerated = 1`, the next CodeGen resolves its target to the PUBLIC name
-- `vwContractTemplates` and DROP/CREATEs it as a plain generated view -- silently
-- destroying the wrapper that part 2 creates. Setting the flags first tells CodeGen to
-- own `vwContractTemplatesGenerated` instead and leave the public name to us.
--
-- The `UPDATE` is keyed by entity NAME, never a literal UUID: entity IDs are minted at
-- first registration, so a hardcoded one stops matching the first time this database is
-- rebuilt from zero. It skips cleanly when the row is absent, because a fresh install runs
-- migrations before CodeGen has registered anything.
--
-- WHY SourceURL BECOMES NULLABLE (ruled by Marcelo, 2026-08-19). The ERD asks for "a public
-- URL that never goes away", and REACHABILITY IS ENFORCEABLE BY NOTHING -- whether a URL
-- still resolves is a fact about the outside world, and format validation is weak because a
-- well-formed dead link passes. So the column stops pretending. The real requirement is
-- "a URL **or** an attached file", and a file attaches through __mj.FileEntityRecordLink
-- keyed on RecordID -- which cannot be linked to a record that does not exist yet. On CREATE
-- the file half is therefore unsatisfiable in principle, and no NOT NULL, CHECK or pre-save
-- validation can express the rule without blocking the ordinary act of authoring a template.
--
-- A template with neither is not INVALID, it is INCOMPLETE -- an ordinary state to pass
-- through. Part 2 derives `IsUsable` so the UI can SAY SO, which is a status a person can
-- see and fix rather than an error that stops a save.
-- =============================================================================

-- 1. SourceURL becomes optional. The current NOT NULL is also what makes the generated form
--    mark the field required, so this is what actually changes the authoring experience.
IF EXISTS (
    SELECT 1 FROM sys.columns c
     WHERE c.[object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplate]')
       AND c.[name] = 'SourceURL' AND c.[is_nullable] = 0
)
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplate]
        ALTER COLUMN [SourceURL] NVARCHAR(1000) NULL;
GO

-- 2. Hand the GENERATED view a private name, so the public one becomes ours.
UPDATE [${mjSchema}].[Entity]
   SET [BaseViewGenerated]      = 0,
       [GeneratedBaseViewName]  = 'vwContractTemplatesGenerated'
 WHERE [Name] = 'MJ_BizApps_Contracts: Contract Templates'
   AND ([BaseViewGenerated] <> 0
        OR [GeneratedBaseViewName] IS NULL
        OR [GeneratedBaseViewName] <> 'vwContractTemplatesGenerated');
GO

-- 3. Create the inner view under its new name NOW, rather than waiting for CodeGen. Part 2's
--    wrapper selects from it, so it has to exist for that migration to compile -- and on a
--    fresh install CodeGen has not run yet. This body is CodeGen's own output for
--    `vwContractTemplates`, renamed; CodeGen will regenerate it in place from here on.
CREATE OR ALTER VIEW [${flyway:defaultSchema}].[vwContractTemplatesGenerated]
AS
SELECT
    c.*,
    mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[Name] AS [ContractTemplateType]
FROM
    [${flyway:defaultSchema}].[ContractTemplate] AS c
INNER JOIN
    [${flyway:defaultSchema}].[ContractTemplateType] AS mjBizAppsContractsContractTemplateType_ContractTemplateTypeID
  ON
    [c].[ContractTemplateTypeID] = mjBizAppsContractsContractTemplateType_ContractTemplateTypeID.[ID];
GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplatesGenerated] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO
