-- =============================================================================
-- V202608200600 — R-12 part 2 of 2: the wrapper that derives IsUsable, and its metadata.
-- =============================================================================
-- A template is USABLE when someone can actually read the standard terms it names: either it
-- records a URL, or a file is attached to it. Neither half is expressible as a constraint --
-- see part 1 for why -- so it is DERIVED and the UI renders it. A red "Unusable" chip is a
-- state a person can see and fix; a save-time refusal is a person being blocked by something
-- they cannot see.
--
-- IT HAS TO BE A VIEW, and that is the contrast with R-11 worth keeping in mind: R-11's sort
-- key is a pure function of one column in one row, so it is a computed column and needs no
-- view at all. `IsUsable` reads ANOTHER TABLE (`__mj.FileEntityRecordLink`), and a computed
-- column cannot do that. Row-local scalar -> computed column; reads another table -> layered
-- view. This is the second case.
--
-- THE ENTITY ID IS LOOKED UP BY NAME, not hardcoded -- copied deliberately from
-- `Contract.IsAwaitingDocument`, which does the same thing for the same reason: entity IDs are
-- minted at first registration, so a literal UUID stops matching the first time this database
-- is rebuilt from zero. Precedent, not invention.
--
-- KEEPING IT ONE BIT is deliberate. A later third state -- say "URL recorded but unreachable",
-- once something checks -- becomes a view change and a chip colour rather than a schema
-- migration.
-- =============================================================================

CREATE OR ALTER VIEW [${flyway:defaultSchema}].[vwContractTemplates]
AS
SELECT
    g.*,
    CAST(CASE
        WHEN g.[SourceURL] IS NOT NULL AND LEN(LTRIM(RTRIM(g.[SourceURL]))) > 0 THEN 1
        WHEN EXISTS (
                SELECT 1
                  FROM [${mjSchema}].[FileEntityRecordLink] fl
                 WHERE fl.[EntityID] = (SELECT e.[ID] FROM [${mjSchema}].[Entity] e
                                         WHERE e.[Name] = 'MJ_BizApps_Contracts: Contract Templates')
                   AND fl.[RecordID] = CAST(g.[ID] AS NVARCHAR(450))
             ) THEN 1
        ELSE 0
    END AS bit) AS [IsUsable]
FROM
    [${flyway:defaultSchema}].[vwContractTemplatesGenerated] AS g;
GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTemplates] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO

-- Register IsUsable so MJ can SEE it: without the EntityField row the column exists in SQL and
-- there is no RunView filter, no grid column and no typed property on the entity class. A fresh
-- install never runs CodeGen, so the discovery has to ship as a migration.
--
-- ⚠ SEQUENCE IS COMPUTED AT APPLY TIME, never a literal. MJ's rule (migrations/CLAUDE.md): the
-- number CodeGen writes is a placeholder that a REPEATABLE script renumbers, and Flyway runs every
-- versioned migration before any repeatable script -- so on a from-scratch database a literal never
-- gets renumbered in time and a second migration touching the same entity collides on
-- UQ_EntityField_EntityID_Sequence, reporting itself as an unrelated foreign-key error. It cannot
-- fail on a working dev database; it fails only on fresh installs.
DECLARE @templateEntityID UNIQUEIDENTIFIER = (
    SELECT [ID] FROM [${mjSchema}].[Entity] WHERE [Name] = 'MJ_BizApps_Contracts: Contract Templates'
);

IF @templateEntityID IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField]
                    WHERE [EntityID] = @templateEntityID AND [Name] = 'IsUsable')
BEGIN
    INSERT INTO [${mjSchema}].[EntityField]
        ([EntityID], [Sequence], [Name], [DisplayName], [Description], [Type], [Length], [AllowsNull],
         [IsVirtual], [DefaultInView], [AllowUpdateAPI], [IncludeInGeneratedForm], [IsPrimaryKey], [IsUnique])
    VALUES (
        @templateEntityID,
        (SELECT ISNULL(MAX([Sequence]), 0) + 1 FROM [${mjSchema}].[EntityField] WHERE [EntityID] = @templateEntityID),
        'IsUsable',
        'Is Usable',
        'Whether the standard terms this version names can actually be READ: it records a SourceURL, or a file is attached to it. Derived in vwContractTemplates — a template with neither is incomplete rather than invalid, which is an ordinary state while one is being authored. Reachability of a URL is deliberately NOT asserted; nothing can.',
        'bit',
        1,
        0,      -- AllowsNull: the CASE always returns 0 or 1
        1,      -- IsVirtual: derived in the view, not a table column
        1,      -- DefaultInView: the point of the flag is to be visible
        0,      -- AllowUpdateAPI: derived, so read-only
        1,      -- IncludeInGeneratedForm
        0, 0
    );
END
GO
