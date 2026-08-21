-- =============================================================================
-- V202608211100 — REVERT the ContractNumber DEFAULT added in V202608211000.
--
-- WHY IT IS BEING REVERTED, one migration later. The DEFAULT was correct SQL and did
-- exactly what it was meant to (give MJ's client-side validator a DefaultValue so a
-- server-assigned NOT NULL column stops being demanded from the user). But MJ's CodeGen
-- cannot consume an EXPRESSION default: it emits the default into the generated create
-- procedure as if it were a literal, wrapped in single quotes --
--
--     ISNULL(@ContractNumber, 'N'CTR-'+format(NEXT VALUE FOR ...)')
--
-- -- which nests quotes, fails with "Incorrect syntax near '-'", and leaves
-- spCreateContract DROPPED AND NOT RECREATED. Contracts could not be created at all.
-- Filed upstream; the note is in plans/backend-requirements.md.
--
-- Forward-only rather than editing V202608211000: that migration is already applied, and
-- editing an applied script breaks its Flyway checksum for every database that ran it.
--
-- The original problem (the browser refusing a null ContractNumber on create) is NOT
-- solved by this revert and is deliberately left open rather than papered over with a
-- second workaround. See the item in plans/backend-requirements.md for the options.
-- =============================================================================

IF EXISTS (
    SELECT 1
      FROM sys.default_constraints dc
      JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
     WHERE dc.parent_object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
       AND c.name = N'ContractNumber'
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[Contract] DROP CONSTRAINT [DF_Contract_ContractNumber];
    PRINT 'Dropped DF_Contract_ContractNumber.';
END
ELSE
    PRINT 'No ContractNumber default present — nothing to drop.';
GO
