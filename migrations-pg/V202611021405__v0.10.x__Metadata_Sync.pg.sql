-- =============================================================================================
-- PostgreSQL counterpart of V202611021405__v0.10.x__Metadata_Sync.sql -- BizApps Contracts v0.10.x Metadata_Sync
-- =============================================================================================
-- Ships the PostgreSQL dialect variant (`MJ: Query SQLs`, PlatformKey = 'postgresql') for the
-- `Contracts Special Terms` stored query (`metadata/queries/.contracts-special-terms.json`, #167).
-- =============================================================================================

SET standard_conforming_strings = on;
-- ===================== Data (INSERT/UPDATE/DELETE) =====================

-- Save MJ: Query SQLs (core SP call only)
DO $mj$
DECLARE
  p_ID_3001 UUID;
  p_QueryID_3001 UUID;
  p_SQLDialectID_3001 UUID;
  p_SQL_3001 TEXT;
BEGIN
  p_ID_3001 := '33333333-0000-4000-8000-000000003001';
  p_QueryID_3001 := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_SQLDialectID_3001 := '426915F2-D4FE-4AB9-97A8-39063561DE9F';
  p_SQL_3001 := '-- PostgreSQL variant of `contracts-special-terms.sql` (#167).
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
';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateQuerySQL'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM "${mjSchema}"."spCreateQuerySQL"(p_data := jsonb_build_object(
      'ID', p_ID_3001,
      'QueryID', p_QueryID_3001,
      'SQLDialectID', p_SQLDialectID_3001,
      'SQL', p_SQL_3001
    ));
  ELSE
    PERFORM "${mjSchema}"."spCreateQuerySQL"(
      p_ID := p_ID_3001,
      p_QueryID := p_QueryID_3001,
      p_SQLDialectID := p_SQLDialectID_3001,
      p_SQL := p_SQL_3001
    );
  END IF;
END $mj$;
