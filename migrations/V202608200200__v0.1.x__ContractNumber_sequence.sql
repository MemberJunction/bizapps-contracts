-- =============================================================================
-- V202608200200 — Replace the ContractSequence COUNTER TABLE with a real SQL SEQUENCE.
-- =============================================================================
-- THE HOLE THIS CLOSES IS THE ENTITY, NOT THE COUNTER. `ContractSequence` is a TABLE, so
-- CodeGen registered it as an MJ ENTITY, which gave it a grid, a form and AllowCreateAPI /
-- AllowUpdateAPI / AllowDeleteAPI all true. Meanwhile `spAssignNextContractNumber` never
-- touched that entity -- it ran `UPDATE ... WITH (HOLDLOCK, UPDLOCK)` straight at the table.
-- So the writable entity was a surface with exactly one use: a user winding
-- NextSequenceNumber backwards, after which the sproc happily re-mints numbers already in
-- use until UQ_Contract_ContractNumber starts refusing saves -- one contract at a time,
-- with no hint why.
--
-- A SQL SERVER SEQUENCE IS A DIFFERENT KIND OF OBJECT, not a table. **CodeGen never sees
-- it**, because it is not a table. No entity, no grid, no editable field, nothing to
-- protect. The counter row, the table, the entity metadata and the hole all leave together.
-- It is also atomic by design, so the HOLDLOCK/UPDLOCK dance goes away.
--
-- NO CACHE, deliberately. SQL Server caches a block of sequence values and an unclean
-- shutdown discards the unused remainder, so the next value JUMPS. `NO CACHE` removes the
-- skip at the cost of a catalog write per call -- free at a handful of contracts a day, and
-- it makes the numbering easier to explain to finance. Note this is about UNCLEAN SHUTDOWN
-- gaps; ordinary gaps (a save that fails after taking a number) remain normal and are not
-- something to fix, exactly as before.
--
-- SEEDING OVER EXISTING DATA. `CREATE SEQUENCE` cannot take a subquery in START WITH, so
-- this is two steps: create it low and unconditionally, then RESTART it above whatever has
-- already been minted. `TRY_CAST` rather than `CAST` is load-bearing -- a hand-entered or
-- legacy number that does not match CTR-<digits> yields NULL instead of failing the whole
-- migration -- and ISNULL(...,0)+1 makes the empty-table case start at 1, not 0, because the
-- format is CTR-000001 and starting at 0 would mint CTR-000000 as the first contract.
--
-- ⚠ THE NUMBER JUMPS ON THIS DATABASE, AND THAT IS RULED OK. The plan predicted the restart
-- would compute 27 (one past CTR-000026). It does not: this database's demo data occupies a
-- reserved CTR-9000xx block, so MAX+1 is **900009** and the next real contract will be
-- CTR-900009. Ruled by Marcelo 2026-08-20: "if the design of the sequence means it will jump
-- to the highest number that is ok ... in production there will be no demo block, and that's
-- totally okay to have here as well." No special-casing of the demo block -- a migration that
-- knows about demo data is a migration that lies on a real install.
--
-- ONE MECHANISM AT A TIME. The table is dropped in the SAME migration that creates the
-- sequence, so there is never a window in which two mechanisms could mint the same number.
-- =============================================================================

-- 1. The sequence. Created low and idempotently; step 2 positions it.
IF NOT EXISTS (
    SELECT 1 FROM sys.sequences s
      JOIN sys.schemas sc ON sc.schema_id = s.schema_id
     WHERE s.name = 'seq_ContractNumber' AND sc.name = '${flyway:defaultSchema}'
)
BEGIN
    CREATE SEQUENCE [${flyway:defaultSchema}].[seq_ContractNumber]
        AS INT START WITH 1 INCREMENT BY 1 NO CACHE;
END
GO

-- 2. Position it above every number already minted. Uses dynamic SQL because ALTER SEQUENCE
--    takes a literal, not an expression.
DECLARE @next INT = (
    SELECT ISNULL(MAX(TRY_CAST(SUBSTRING([ContractNumber], 5, 20) AS INT)), 0) + 1
      FROM [${flyway:defaultSchema}].[Contract]
     WHERE [ContractNumber] LIKE 'CTR-%'
);
DECLARE @current INT = (
    SELECT CAST(current_value AS INT) FROM sys.sequences s
      JOIN sys.schemas sc ON sc.schema_id = s.schema_id
     WHERE s.name = 'seq_ContractNumber' AND sc.name = '${flyway:defaultSchema}'
);
-- Only ever move FORWARD. A re-run on a database that has since minted more numbers must not
-- wind the sequence back underneath them.
--    ⚠ The string is built into a VARIABLE first. `EXEC(N'...' + CAST(@next AS NVARCHAR(20)))` does
--    NOT compile: EXEC() concatenates only string literals and variables, never a function call, and
--    it fails with the unhelpful "Incorrect syntax near 'CAST'". (The plan's snippet has this bug.)
IF @current IS NULL OR @next > @current
BEGIN
    DECLARE @sql NVARCHAR(400) =
        N'ALTER SEQUENCE [${flyway:defaultSchema}].[seq_ContractNumber] RESTART WITH ' + CAST(@next AS NVARCHAR(20));
    EXEC sp_executesql @sql;
END
GO

-- 3. The sproc keeps its NAME and SIGNATURE, so no application code changes -- ContractEntityServer
--    still calls `EXEC spAssignNextContractNumber @ContractNumber OUTPUT`. Only the mechanism inside
--    changes, which is the whole point of having put the lock in a database object rather than in a
--    TypeScript string. It also makes the PostgreSQL port a database exercise.
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spAssignNextContractNumber];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spAssignNextContractNumber]
    @ContractNumber NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- No HOLDLOCK, no UPDLOCK, no singleton row to be missing: NEXT VALUE FOR is atomic and
    -- never hands the same value to two callers.
    DECLARE @NextSeq INT = NEXT VALUE FOR [${flyway:defaultSchema}].[seq_ContractNumber];

    -- FORMAT pads to six digits WITHOUT truncating a longer number. The previous
    -- `RIGHT(N'000000' + CAST(@NextSeq AS NVARCHAR(6)), 6)` silently produced 'CTR-000000' at
    -- 1,000,000 -- it kept the LAST six characters of an over-long string. Unreachable in
    -- practice, and not worth carrying forward now that the line is being rewritten anyway.
    SET @ContractNumber = N'CTR-' + FORMAT(@NextSeq, N'D6');
END;
GO

-- 4. Retire the entity. ORDER MATTERS -- these are FK children of __mj.Entity, so they go first.
--    Every DELETE is scoped by the entity's own ID, resolved by schema + base table so this is
--    safe on a database where the ID differs.
--
--    Leaving the metadata behind is the actual trap (the same one the IsChangeOrder removal hit):
--    MJ would describe an entity whose table does not exist, which surfaces as a broken grid rather
--    than as an error. If a future MJ adds another FK child of Entity, the final DELETE fails loudly
--    with a foreign-key error -- which is the right outcome, and better than a silent orphan.
DECLARE @eid UNIQUEIDENTIFIER = (
    SELECT [ID] FROM [${mjSchema}].[Entity]
     WHERE [SchemaName] = '${flyway:defaultSchema}' AND [BaseTable] = 'ContractSequence'
);

IF @eid IS NOT NULL
BEGIN
    DELETE FROM [${mjSchema}].[ApplicationEntity]  WHERE [EntityID] = @eid;
    DELETE FROM [${mjSchema}].[EntityPermission]   WHERE [EntityID] = @eid;
    DELETE FROM [${mjSchema}].[EntityField]        WHERE [EntityID] = @eid;
    -- EntitySetting is guarded because it is a NEWER child of Entity than the other three, so an
    -- older MJ may not have the table. It is also the one this migration originally MISSED: the
    -- first run failed on FK_EntitySetting_Entity, which is exactly the loud failure the comment
    -- above promises, and the whole file rolled back (skyway runs one transaction per migration).
    -- The complete set of FK children of __mj.Entity carrying rows for an entity was then read off
    -- sys.foreign_keys rather than guessed at one error per attempt.
    IF OBJECT_ID('[${mjSchema}].[EntitySetting]', 'U') IS NOT NULL
        DELETE FROM [${mjSchema}].[EntitySetting] WHERE [EntityID] = @eid;
    DELETE FROM [${mjSchema}].[Entity]             WHERE [ID]       = @eid;
END
GO

-- 5. The generated database objects, then the table itself. CodeGen produced the CRUD sprocs, the
--    view and the __mj_UpdatedAt trigger; they have to go before the table they read.
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spCreateContractSequence];
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spUpdateContractSequence];
DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spDeleteContractSequence];
GO
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractSequence]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractSequence];
GO
DROP VIEW IF EXISTS [${flyway:defaultSchema}].[vwContractSequences];
GO
DROP TABLE IF EXISTS [${flyway:defaultSchema}].[ContractSequence];
GO

-- 6. The COLUMN DESCRIPTION still named the table this migration deletes. Left alone, MJ would carry
--    "CTR-{seq} from ContractSequence" as the help text for Contract.ContractNumber -- prose pointing
--    at an object that no longer exists, which is the same trap as leaving the entity metadata behind,
--    just quieter. CodeGen syncs extended properties into __mj.EntityField.Description, so correcting
--    it here is what makes the next CodeGen run correct.
IF EXISTS (
    SELECT 1 FROM sys.extended_properties
     WHERE [major_id] = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
       AND [minor_id] = COLUMNPROPERTY(OBJECT_ID('[${flyway:defaultSchema}].[Contract]'), 'ContractNumber', 'ColumnId')
       AND [name] = 'MS_Description'
)
BEGIN
    EXEC sp_updateextendedproperty
        @name = N'MS_Description',
        @value = N'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. Gaps are normal and are not to be "fixed" — a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.',
        @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
        @level1type = N'TABLE',  @level1name = N'Contract',
        @level2type = N'COLUMN', @level2name = N'ContractNumber';
END
GO
