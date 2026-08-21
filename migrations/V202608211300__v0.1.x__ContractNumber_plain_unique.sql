-- =============================================================================
-- V202608211300 — replace the FILTERED unique index on ContractNumber with a PLAIN one.
--
-- WHY, reversing V202608211200's filtered index one migration later (Marcelo, 2026-08-21).
--
-- Both forms give the SAME guarantee for real numbers: every non-NULL ContractNumber is
-- unique. The only difference is how many UN-numbered rows may exist:
--
--   FILTERED (WHERE ContractNumber IS NOT NULL)  -> NULLs are not indexed at all, so any
--                                                   number of NULL rows is permitted.
--   PLAIN                                        -> SQL Server treats NULLs as comparable
--                                                   and permits exactly ONE.
--
-- The plain index is therefore STRICTLY STRONGER here, and it costs the application nothing:
-- ContractEntityServer.Save() mints a number whenever the incoming value is null or blank, so
-- the entity path never sends a NULL in the first place. The only way to create one is raw SQL
-- that bypasses the entity — and a second such row is exactly what we want the database to
-- refuse rather than accumulate.
--
-- NO APPLICATION-LEVEL NULL CHECK IS NEEDED, and deliberately none is added. A query inside
-- Save() asking "does another NULL already exist?" would be both racy and redundant: the entity
-- guarantees a number on the way in, and the index is the floor underneath it. The ordering
-- question (does an app check run before the database's?) does not arise, because there is no
-- app check.
--
-- Bonus: plain indexes carry none of the filtered-index SET requirements. V202608211200's
-- filtered index made every INSERT depend on QUOTED_IDENTIFIER being ON, which fails from a
-- plain sqlcmd session with a message about SET options that names neither the table nor the
-- real cause. That trap goes away with this migration.
--
-- Forward-only rather than editing V202608211200: it is already applied, and editing an applied
-- script breaks its Flyway checksum on every database that ran it.
-- =============================================================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF EXISTS (SELECT 1 FROM sys.indexes
            WHERE object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
              AND name = N'UQ_Contract_ContractNumber'
              AND filter_definition IS NOT NULL)
BEGIN
    DROP INDEX [UQ_Contract_ContractNumber] ON [${flyway:defaultSchema}].[Contract];
    PRINT 'Dropped the FILTERED UQ_Contract_ContractNumber.';
END
GO

-- Guard the swap: if more than one NULL already exists, a plain unique index cannot be created,
-- and failing here with a clear message beats a raw index-build error.
IF (SELECT COUNT(*) FROM [${flyway:defaultSchema}].[Contract] WHERE [ContractNumber] IS NULL) > 1
BEGIN
    RAISERROR (N'Cannot create a plain unique index on ContractNumber: more than one row has a NULL number. Assign numbers to those contracts first (they can only have been created by raw SQL bypassing the entity).', 16, 1);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
                WHERE object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
                  AND name = N'UQ_Contract_ContractNumber')
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UQ_Contract_ContractNumber]
        ON [${flyway:defaultSchema}].[Contract] ([ContractNumber]);
    PRINT 'Created UQ_Contract_ContractNumber as a PLAIN unique index (one NULL permitted).';
END
GO
