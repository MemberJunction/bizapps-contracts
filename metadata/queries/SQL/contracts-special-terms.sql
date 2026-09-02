-- Clients with special terms — the Contracts dashboard's fourth tile.
--
-- Two figures in ONE row, because they are one statement on the screen: "3 clients, across 7
-- contracts". Read as two queries they could disagree by the width of a write landing between them,
-- and the footnote would quietly contradict the number above it.
--
-- WHY THIS IS A STORED QUERY. The tile counts CUSTOMERS, not contracts, and a distinct count is not
-- a shape RunView returns — counting client-side would mean paging every modified contract to the
-- browser just to de-duplicate an id. The set is small today and would still be the wrong shape.
--
-- Scope matches the tile's own wording exactly — agreements IN FORCE that deviate from standard
-- terms. An expired contract that once carried modifications is history, not a live negotiation, so
-- 'Active' and 'Executed' are the only states that count. Change this and the dashboard's grid stops
-- agreeing with the tile above it.
--
-- CompanyIDs is optional and arrives from the dashboard's company chips. `sqlIn` quotes and escapes
-- every element, so no id reaches SQL text unescaped; an empty array is guarded by the `if` rather
-- than passed through, because `sqlIn` renders `(NULL)` for an empty list — which would match
-- nothing and silently turn "All companies" into "no companies".
SELECT
    COUNT(DISTINCT c.CustomerOrganizationID) AS CustomerCount,
    COUNT(*) AS ContractCount
FROM [__mj_BizAppsContracts].vwContracts c
WHERE c.HasModifications = 1
  AND c.State IN (N'Active', N'Executed')
  {% if CompanyIDs and CompanyIDs.length %}
  AND c.CompanyID IN {{ CompanyIDs | sqlIn }}
  {% endif %};
