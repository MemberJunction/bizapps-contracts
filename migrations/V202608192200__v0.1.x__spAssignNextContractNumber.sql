-- =============================================================================
-- V202608192200 — the CTR- counter moves into a stored procedure.
-- =============================================================================
-- WHY, and it is a convention question rather than a preference. `ContractEntityServer`
-- minted contract numbers by running the read-modify-write inline from TypeScript:
-- `UPDATE … WITH (UPDLOCK, HOLDLOCK) OUTPUT deleted.NextSequenceNumber INTO @seq`.
-- Every read in that class has since moved to `RunView`, which left this as the only
-- hand-written SQL in the app — and the only thing in it that cannot run on
-- PostgreSQL, since `UPDLOCK` / `HOLDLOCK` / `OUTPUT … INTO` have no PG equivalent.
--
-- The atomicity genuinely cannot move to application code: two concurrent creates
-- would both read N and both mint the same number, and the collision would surface
-- later as a unique-index violation on the contract insert rather than as a
-- serialised wait. So the lock stays in the database — but it belongs in a DATABASE
-- OBJECT, not in a TypeScript string.
--
-- THIS IS ACCOUNTING'S PATTERN, adopted deliberately rather than invented here.
-- `bizapps-accounting` keeps `spAssignNextJournalEntryNumber` /
-- `spAssignNextJournalEntryBatchNumber` at DB level for exactly this reason and calls
-- them from `SequenceService.ts`, whose docblock says it plainly: the sprocs "require
-- atomic HOLDLOCK+UPDLOCK read-modify-write semantics that don't translate to
-- app-level code under concurrency. Everything else moves to TypeScript." Orders is
-- the counter-example — it still inlines the same UPDATE in four places, which is the
-- thing not to copy.
--
-- WHAT IT BUYS. The TypeScript becomes one dialect-free `EXEC`, so a PostgreSQL port
-- writes a PG function with the same name and signature and changes no application
-- code — the dialect difference lives where dialect differences belong. It also puts
-- the number FORMAT in one place; accounting made the same call (its sproc returns the
-- formatted 'BATCH-000001').
--
-- ⚠ STILL NOT GAP-FREE, and the old comment in the TypeScript claimed otherwise before
-- being corrected. On a standalone save the counter is consumed before the row's own
-- transaction opens, so a later failure has already spent a number. Inside a graph save
-- the rollback releases it. The unique index is the real guard; "gap-conscious" is a
-- promise this cannot keep, so it is not made.
-- =============================================================================

DROP PROCEDURE IF EXISTS [${flyway:defaultSchema}].[spAssignNextContractNumber];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spAssignNextContractNumber]
    @ContractNumber NVARCHAR(50) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NextSeq INT;

    -- HOLDLOCK + UPDLOCK on the singleton row: concurrent callers serialise here rather
    -- than colliding on UQ_Contract_ContractNumber. The row is seeded by the baseline,
    -- so a missing one is a broken install and must fail loudly rather than be created.
    UPDATE [${flyway:defaultSchema}].[ContractSequence] WITH (HOLDLOCK, UPDLOCK)
       SET @NextSeq = NextSequenceNumber,
           NextSequenceNumber = NextSequenceNumber + 1
     WHERE ID = 1;

    IF @NextSeq IS NULL
        THROW 50001, 'spAssignNextContractNumber: the ContractSequence singleton row (ID=1) is missing. It is seeded by the baseline migration.', 1;

    SET @ContractNumber = N'CTR-' + RIGHT(N'000000' + CAST(@NextSeq AS NVARCHAR(6)), 6);
END;
GO
