-- =============================================================================
-- V202608211000 — give ContractNumber a DEFAULT so a NEW contract can be saved.
--
-- THE BUG THIS FIXES. `ContractNumber` is NOT NULL and assigned by the server on
-- insert (spAssignNextContractNumber, from seq_ContractNumber). But MJ's
-- client-side `EntityField.Validate()` refuses a NOT NULL field that is null:
--
--     if (!ef.AllowsNull && value == null) {
--         if (ef.DefaultValue is empty)     -> ERROR            <-- we landed here
--         else if (this._OldValue != null)  -> ERROR (existing record only)
--     }
--
-- So the browser blocked every create with "Contract Number cannot be null"
-- before the server ever got the chance to mint one. MJ ALREADY models
-- "NOT NULL but supplied on insert" — it keys it on DefaultValue — and this
-- column was the only one on the table that is NOT NULL, defaultless and
-- server-assigned. `ID` on this same table has always worked precisely because
-- it carries DEFAULT (newsequentialid()) while MJ assigns the uuid client-side.
-- This makes ContractNumber match that arrangement.
--
-- ⚠ THE DEFAULT IS A SIGNAL AND A BACKSTOP, NOT THE MECHANISM. MJ's generated
-- spCreateContract takes @ContractNumber and inserts it explicitly, so this
-- DEFAULT does not fire on any normal write — exactly as ID's does not. Its two
-- real jobs are (1) populate EntityField.DefaultValue so the client stops
-- objecting, and (2) catch a direct SQL insert that omits the column. The
-- authoritative minting stays in ContractEntityServer.Save(). Do not read this
-- constraint as "where contract numbers come from".
--
-- The expression was verified accepted by SQL Server before this migration was
-- written (constraint created and dropped, no sequence value consumed):
--   (N'CTR-'+format(NEXT VALUE FOR [__mj_BizAppsContracts].[seq_ContractNumber],N'D6'))
-- Note D6 is a MINIMUM width, not a maximum — at 1,000,000 it yields CTR-1000000
-- and keeps growing, so there is no digit ceiling to outgrow.
-- =============================================================================

IF NOT EXISTS (
    SELECT 1
      FROM sys.default_constraints dc
      JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
     WHERE dc.parent_object_id = OBJECT_ID(N'[${flyway:defaultSchema}].[Contract]')
       AND c.name = N'ContractNumber'
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[Contract]
        ADD CONSTRAINT [DF_Contract_ContractNumber]
        DEFAULT (N'CTR-' + FORMAT(NEXT VALUE FOR [${flyway:defaultSchema}].[seq_ContractNumber], N'D6'))
        FOR [ContractNumber];

    PRINT 'Added DF_Contract_ContractNumber.';
END
ELSE
    PRINT 'ContractNumber already has a default constraint — nothing to do.';
GO
