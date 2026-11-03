-- =============================================================================================
-- BizApps Contracts v0.10.x -- Metadata_Sync
-- =============================================================================================
-- Ships the PostgreSQL dialect variant (`MJ: Query SQLs`, PlatformKey = 'postgresql') for the
-- `Contracts Special Terms` stored query (`metadata/queries/.contracts-special-terms.json`, #167).
-- =============================================================================================

-- Save MJ: Query SQLs (core SP call only)
DECLARE @ID_3001 UNIQUEIDENTIFIER,
@QueryID_3001 UNIQUEIDENTIFIER,
@SQLDialectID_3001 UNIQUEIDENTIFIER,
@SQL_3001 NVARCHAR(MAX)
SET
  @ID_3001 = '33333333-0000-4000-8000-000000003001'
SET
  @QueryID_3001 = 'A93597C0-100E-4059-ABC5-E08DD708E520'
SET
  @SQLDialectID_3001 = '426915F2-D4FE-4AB9-97A8-39063561DE9F'
SET
  @SQL_3001 = N'-- PostgreSQL variant of `contracts-special-terms.sql` (#167).
--
-- Counts DISTINCT customers holding at least one Active or Executed contract with recorded
-- modifications, and the number of such contracts. Referenced by
-- `metadata/queries/.contracts-special-terms.json` via `MJ: Query SQLs` (`PlatformKey=postgresql`).
SELECT
    COUNT(DISTINCT c."CustomerOrganizationID") AS "CustomerCount",
    COUNT(*) AS "ContractCount"
FROM "__mj_bizappscontracts"."vwContracts" c
WHERE c."HasModifications" = TRUE
  AND c."State" IN (''Active'', ''Executed'')
  {% if CompanyIDs and CompanyIDs.length %}
  AND c."CompanyID" IN {{ CompanyIDs | sqlIn }}
  {% endif %};
'
EXEC [${mjSchema}].spCreateQuerySQL @ID = @ID_3001,
  @QueryID = @QueryID_3001,
  @SQLDialectID = @SQLDialectID_3001,
  @SQL = @SQL_3001;
GO
