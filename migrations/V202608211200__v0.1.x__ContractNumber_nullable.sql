-- =============================================================================
-- V202608211200 — ContractNumber becomes NULLABLE, with a FILTERED unique index.
--
-- WHY, after two failed attempts at keeping it NOT NULL. The number is minted by
-- ContractEntityServer.Save() from seq_ContractNumber, so it is never supplied by
-- the user — but MJ has no way to say "NOT NULL, assigned by the server on insert"
-- (MJ#4001), and both available workarounds break creation in opposite directions:
--
--   · a DB DEFAULT      -> CodeGen string-quotes an EXPRESSION default into
--                          spCreateContract, which then fails to compile and is
--                          left DROPPED. Contracts could not be created at all.
--                          (MJ#4000; added and reverted in V202608211000/1100.)
--   · AllowUpdateAPI=0  -> silences the validator, but a ReadOnly field is OMITTED
--                          FROM THE INSERT PAYLOAD, so the procedure fails with
--                          "expects parameter '@ContractNumber', which was not
--                          supplied". Reverted in metadata.
--
-- So the column becomes nullable and the SERVER holds the invariant instead of the
-- database. That is a real trade, stated plainly: nothing at the schema level now
-- guarantees every contract has a number. What enforces it is
-- ContractEntityServer.Save(), which mints one whenever the incoming value is null
-- or blank. Ruled by Marcelo, 2026-08-21.
--
-- THE FILTERED INDEX IS THE POINT OF THIS MIGRATION, not an afterthought. SQL Server
-- permits exactly ONE NULL in a plain UNIQUE index, so simply relaxing the column
-- would mean the SECOND unnumbered row collides on UQ_Contract_ContractNumber —
-- reported as a duplicate-key error about uniqueness, which is a far more confusing
-- failure than the one being fixed. `WHERE ContractNumber IS NOT NULL` excludes the
-- nulls from the index entirely, so uniqueness still holds for every real number and
-- any number of in-flight nulls is fine.
--
-- Filtered indexes require quoted-identifier / ANSI settings at CREATE time; Flyway
-- runs with them on, and they are set explicitly here so this does not depend on the
-- session that happens to apply it.
-- =============================================================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1 · drop the plain unique index before altering the column it covers
IF EXISTS (SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
              AND name = N'UQ_Contract_ContractNumber')
BEGIN
    DROP INDEX [UQ_Contract_ContractNumber] ON [${flyway:defaultSchema}].[Contract];
    PRINT 'Dropped UQ_Contract_ContractNumber (plain).';
END
GO

-- 2 · relax the column
IF EXISTS (SELECT 1 FROM sys.columns
            WHERE object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
              AND name = N'ContractNumber' AND is_nullable = 0)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[Contract]
        ALTER COLUMN [ContractNumber] NVARCHAR(50) NULL;
    PRINT 'ContractNumber is now nullable.';
END
GO

-- 3 · restore uniqueness for real numbers only
IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
                  AND name = N'UQ_Contract_ContractNumber')
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UQ_Contract_ContractNumber]
        ON [${flyway:defaultSchema}].[Contract] ([ContractNumber])
        WHERE [ContractNumber] IS NOT NULL;
    PRINT 'Recreated UQ_Contract_ContractNumber as a FILTERED unique index.';
END
GO
