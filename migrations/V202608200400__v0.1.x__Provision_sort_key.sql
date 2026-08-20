-- =============================================================================
-- V202608200400 — ProvisionSortKey replaces the hand-maintained Sequence column.
-- =============================================================================
-- `Sequence` IS ALREADY WRONG IN THE LIVE DATA, which is what settles whether this is worth
-- doing. It is an int defaulting to 0 with no unique constraint and no rule, and the seeded
-- Master Agreement already contains a collision: ProvisionNumber '1' and '1.1' both claim
-- Sequence 1. Two rows in one template claim the same position, nothing errors, and the grid
-- picks between them arbitrarily. That is the failure mode of a hand-maintained copy of an
-- order the ProvisionNumber already states -- the stored projection §7.2 forbids. (Measured:
-- 1 colliding pair across 73 provisions.)
--
-- THIS REVERSES ERD R-14, which kept `Sequence` because "provision numbers do not sort as text
-- and a legal document has a canonical order". The premise is correct and the conclusion does
-- not follow: a DERIVED sort key preserves the canonical order without a maintained column, and
-- the kept column has already failed at the job it was kept for. Logged as R-20 in
-- plans/ERD-planned.md §9 per the reversal-log convention.
--
-- ORDERING BY ProvisionNumber DIRECTLY DOES NOT WORK. It is nvarchar, so string comparison puts
-- '1.10' before '1.9' and '10.1' before '2.1'. The problem is not that the comparison is wrong,
-- it is that it is MISALIGNED -- it compares a units digit against a tens digit. Zero-padding
-- every run of digits to a fixed width lines the places up, so character-by-character
-- comparison becomes place-by-place comparison, which is what comparing numbers means. This is
-- a collation key, a completely standard technique, and the same reason dates are written
-- 2026-08-20 rather than 8/20/2026.
--
-- WHY A UDF RATHER THAN AN INLINE TWO-SEGMENT EXPRESSION. The plan offers both and asks the
-- implementer to say which. Chosen: the UDF, generalised to ANY depth.
--   · The alternative was an inline expression covering two segments plus a CHECK refusing a
--     ProvisionNumber with more than two. Today's data has at most two (max 1 dot, max length
--     5), so both work NOW.
--   · But that CHECK is a PRODUCT restriction, not a technical one. A legal document plausibly
--     numbers clauses 1.2.3, and forbidding that to keep a sort expression short would be the
--     schema dictating drafting conventions. This function handles any number of segments and
--     any mix of digits and letters, so nothing has to be refused.
--   · It stays PERSISTED and INDEXABLE, which is the property that mattered: the function is
--     WITH SCHEMABINDING and deterministic (no table access, no nondeterministic builtins), so
--     SQL Server can prove the value cannot change on its own.
--
-- HOW IT SORTS (verified against the boundary cases after applying):
--     1 | 1.1 | 1.1A | 1.1B | 1.2 | 1.9 | 1.10 | 1.11 | 2.1 | 2.10B | 10.1 | 12.3
--
-- AND THE ENCODING THAT DOES NOT WORK, recorded so it is not re-proposed: mapping A->1 and
-- appending (1.1A -> 1.11) collides as soon as a segment reaches two digits -- 1.10 also
-- encodes to 1.1, so the tenth sub-clause becomes the first. A decimal has one point; a
-- provision number has an arbitrary number of independent segments.
--
-- WHY NO LAYERED VIEW. The CodeGen base view is `SELECT c.*`, so a new column on the table
-- appears in vwContractTemplateProvisions automatically. That also means BUILD-STATE §5
-- gotcha 6 (a layered view needs two migrations with the entity flags set before the first
-- CodeGen) does not apply here at all -- avoided by not building a wrapper, not by being
-- careful around one. An indexed view would also have been impossible: SQL Server requires
-- WITH SCHEMABINDING and forbids referencing another view, and ours would sit on the generated
-- inner view.
-- =============================================================================

-- 1. The key function. Deterministic + schemabound so a computed column may PERSIST it.
CREATE OR ALTER FUNCTION [${flyway:defaultSchema}].[fnProvisionSortKey] (@ProvisionNumber NVARCHAR(20))
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    IF @ProvisionNumber IS NULL RETURN NULL;

    DECLARE @out    NVARCHAR(200) = N'';
    DECLARE @digits NVARCHAR(20)  = N'';
    DECLARE @i      INT = 1;
    DECLARE @len    INT = LEN(@ProvisionNumber);
    DECLARE @c      NCHAR(1);

    WHILE @i <= @len
    BEGIN
        SET @c = SUBSTRING(@ProvisionNumber, @i, 1);
        IF @c LIKE N'[0-9]'
            SET @digits = @digits + @c;
        ELSE
        BEGIN
            IF LEN(@digits) > 0
            BEGIN
                -- Pad to 6, but never TRUNCATE a longer run: RIGHT(...,6) on a 7-digit run would
                -- drop its leading digit and sort it wildly wrong. Runs that long do not exist
                -- here, and the expression should not be the reason they cannot.
                SET @out = @out + RIGHT(REPLICATE(N'0', 6) + @digits,
                                        CASE WHEN LEN(@digits) > 6 THEN LEN(@digits) ELSE 6 END);
                SET @digits = N'';
            END
            -- UPPER so '1.1a' and '1.1A' land together rather than in two places.
            SET @out = @out + UPPER(@c);
        END
        SET @i = @i + 1;
    END

    IF LEN(@digits) > 0
        SET @out = @out + RIGHT(REPLICATE(N'0', 6) + @digits,
                                CASE WHEN LEN(@digits) > 6 THEN LEN(@digits) ELSE 6 END);

    RETURN @out;
END;
GO

-- 2. The computed column, PERSISTED so it can be indexed.
IF COL_LENGTH('${flyway:defaultSchema}.ContractTemplateProvision', 'ProvisionSortKey') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision]
        ADD [ProvisionSortKey] AS ([${flyway:defaultSchema}].[fnProvisionSortKey]([ProvisionNumber])) PERSISTED;
GO

-- 3. Composite index, template first, because every real query is scoped to one template.
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ContractTemplateProvision_SortKey'
                 AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateProvision]'))
    CREATE INDEX [IX_ContractTemplateProvision_SortKey]
        ON [${flyway:defaultSchema}].[ContractTemplateProvision] ([ContractTemplateID], [ProvisionSortKey]);
GO

EXEC sp_addextendedproperty @name = N'MS_Description',
    @value = N'Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order ("1.9" before "1.10"), which ordering by ProvisionNumber cannot. READ-ONLY — a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractTemplateProvision',
    @level2type = N'COLUMN', @level2name = N'ProvisionSortKey';
GO

-- 4. Retire Sequence: its EntityField metadata row (and any value-list children) before the
--    column, so MJ is never describing a column that does not exist -- the IsChangeOrder trap,
--    which surfaces as a null-valued field on every form rather than as an error.
DECLARE @seqFieldID UNIQUEIDENTIFIER = (
    SELECT f.[ID] FROM [${mjSchema}].[EntityField] f
     INNER JOIN [${mjSchema}].[Entity] e ON e.[ID] = f.[EntityID]
     WHERE e.[SchemaName] = '${flyway:defaultSchema}'
       AND e.[BaseTable]  = 'ContractTemplateProvision'
       AND f.[Name]       = 'Sequence'
);
IF @seqFieldID IS NOT NULL
BEGIN
    DELETE FROM [${mjSchema}].[EntityFieldValue] WHERE [EntityFieldID] = @seqFieldID;
    DELETE FROM [${mjSchema}].[EntityField]      WHERE [ID]            = @seqFieldID;
END
GO

--    ⚠ ITS DEFAULT CONSTRAINT FIRST, AND BY LOOKUP RATHER THAN BY NAME. The baseline wrote
--    `Sequence INT NOT NULL DEFAULT 0` without naming the constraint, so SQL Server generated one
--    (`DF__ContractT__Seque__58B461E8` here). Auto-generated names embed an object id, so they DIFFER
--    PER DATABASE -- hardcoding the one from this instance would work here and fail on every other
--    install. DROP COLUMN refuses while it exists, which is how this was found: the first run failed
--    with "one or more objects access this column" and rolled the whole file back.
DECLARE @seqDefault SYSNAME = (
    SELECT d.[name]
      FROM sys.default_constraints d
      JOIN sys.columns c ON c.[object_id] = d.[parent_object_id] AND c.[column_id] = d.[parent_column_id]
     WHERE d.[parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractTemplateProvision]')
       AND c.[name] = 'Sequence'
);
IF @seqDefault IS NOT NULL
BEGIN
    DECLARE @dropDefault NVARCHAR(400) =
        N'ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] DROP CONSTRAINT ' + QUOTENAME(@seqDefault);
    EXEC sp_executesql @dropDefault;
END

IF COL_LENGTH('${flyway:defaultSchema}.ContractTemplateProvision', 'Sequence') IS NOT NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractTemplateProvision] DROP COLUMN [Sequence];
GO
