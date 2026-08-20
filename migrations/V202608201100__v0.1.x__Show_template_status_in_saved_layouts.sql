-- =============================================================================
-- V202608201100 — Add Status to any saved Contract Templates grid layout.
-- =============================================================================
-- `ContractTemplate.Status` arrived in V202608200900 with `DefaultInView = 1`, so it appears
-- automatically for anyone who has never customised that grid. It does NOT appear for anyone who has:
-- MJ persists a per-user layout as a `__mj.UserSetting` row keyed
-- `default-view-setting/<Entity Name>`, and that layout PINS its column list regardless of metadata.
-- A layout saved before the column existed simply does not mention it.
--
-- Normally that is correct behaviour and I would leave it alone -- adding a column should not silently
-- rearrange someone's chosen layout, and the column chooser is right there. This one is different:
-- `Status` is not a nicety, it is the lifecycle state that now decides whether a version can be
-- referenced by a contract at all and whether its provisions can be edited. A saved layout that
-- predates it hides load-bearing information, and the user has no reason to know to go looking.
--
-- APPENDED, NOT RESET. The alternative -- deleting the setting so metadata takes over -- also works
-- and costs the user their column widths and ordering. `JSON_MODIFY(..., 'append $.columnSettings')`
-- is a first-class operation here, so there is no reason to take that cost. (Contrast
-- V202608200700, which DID delete the row: there the saved layout named a column that no longer
-- existed and the page failed to load, so there was nothing worth preserving.)
--
-- THE FIELD ID IS LOOKED UP, NOT HARDCODED. `EntityField.ID` is minted at first registration, so the
-- value on this instance is not the value anywhere else -- the same reason V202608200400 drops its
-- default constraint by lookup. Idempotent via the NOT EXISTS: a re-run adds nothing.
-- =============================================================================

DECLARE @statusFieldID NVARCHAR(36) = (
    SELECT CAST(f.[ID] AS NVARCHAR(36))
      FROM [${mjSchema}].[EntityField] f
     INNER JOIN [${mjSchema}].[Entity] e ON e.[ID] = f.[EntityID]
     WHERE e.[SchemaName] = '${flyway:defaultSchema}'
       AND e.[BaseTable]  = 'ContractTemplate'
       AND f.[Name]       = 'Status'
);

IF @statusFieldID IS NOT NULL
BEGIN
    UPDATE us
       SET [Value] = JSON_MODIFY(
                us.[Value],
                'append $.columnSettings',
                JSON_QUERY(
                    N'{"ID":"' + @statusFieldID + N'","Name":"Status","DisplayName":"Status",'
                  + N'"hidden":false,"width":150,"orderIndex":'
                  + CAST((SELECT COUNT(*) FROM OPENJSON(us.[Value], '$.columnSettings')) AS NVARCHAR(10))
                  + N'}'
                )
            )
      FROM [${mjSchema}].[UserSetting] us
     WHERE us.[Setting] = 'default-view-setting/MJ_BizApps_Contracts: Contract Templates'
       AND ISJSON(us.[Value]) = 1
       AND NOT EXISTS (
            SELECT 1
              FROM OPENJSON(us.[Value], '$.columnSettings')
                   WITH ([Name] NVARCHAR(200) '$.Name') c
             WHERE c.[Name] = 'Status'
       );
END
GO
