-- PostgreSQL variant of `contracts-special-terms.sql` (#167).
--
-- Counts DISTINCT customers holding at least one Active or Executed contract with recorded
-- modifications, and the number of such contracts. Referenced by
-- `metadata/queries/.contracts-special-terms.json` via `MJ: Query SQLs` (`PlatformKey=postgresql`).
SELECT
    COUNT(DISTINCT c."CustomerOrganizationID") AS "CustomerCount",
    COUNT(*) AS "ContractCount"
FROM "__mj_bizappscontracts"."vwContracts" c
WHERE c."HasModifications" = TRUE
  AND c."State" IN ('Active', 'Executed')
  {% if CompanyIDs and CompanyIDs.length %}
  AND c."CompanyID" IN {{ CompanyIDs | sqlIn }}
  {% endif %};
