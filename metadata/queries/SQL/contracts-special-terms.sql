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
-- 'Active' and 'Executed' are the only states that count.
--
-- ⚠ THE SAME PREDICATE IS WRITTEN ONCE MORE IN TYPESCRIPT, as the 'special-terms' pill in
-- packages/Angular/src/lib/pages/contract-grid.page.ts — the list this tile CLICKS THROUGH TO. The
-- two cannot be collapsed: this one has to run server-side because it counts DISTINCT customers,
-- and that one is a client filter over the same view. Change either and change both, or the tile's
-- "across N contracts" footnote stops matching the row count of the list it opens.
--
-- There is deliberately no test comparing the two strings. This repo mirrored a rule across
-- TypeScript and SQL once before, guarded it with a text comparison, and the renderings still
-- diverged semantically while looking alike (see packages/Entities/src/contract-state.ts). The
-- on-screen disagreement between footnote and row count is the better detector.
--
-- CompanyIDs is optional and arrives from the dashboard's company chips. `sqlIn` quotes and escapes
-- every element, so no id reaches SQL text unescaped; an empty array is guarded by the `if` rather
-- than passed through, because `sqlIn` renders `(NULL)` for an empty list — which would match
-- nothing and silently turn "All companies" into "no companies".
--
-- ⚠ THE PARAMETER ROW IS OWNED BY EXTRACTION, NOT BY metadata/. There is deliberately no
-- `MJ: Query Parameters` entry in `.contracts-special-terms.json`, and adding one breaks the push.
-- `MJQueryEntityServer.Save` runs the query-extraction pipeline synchronously after the base save
-- whenever the query is new or its SQL is dirty, so the pipeline writes its own row — fresh GUID,
-- `DetectionMethod` 'AI' — before MetadataSync gets to any declared child, and the declared row then
-- violates `UQ_QueryParameter_QueryID_Name`. Reordering alone would not settle it either:
-- `updateParameterIfChanged` forces `DetectionMethod` back to 'AI' and overwrites Description and
-- SampleValue from the template on every SQL change, so a hand-declared row has no stable state.
--
-- The row still reaches a host, because `metadata/` ships exactly one way — inside the release
-- `V…__Metadata_Sync.sql`, which is the SQL logger's output from an in-process push and therefore
-- captures extraction's own `spCreateQueryParameter` call alongside the sync's writes. That is the
-- whole guarantee: without a parameter row the processor rejects `CompanyIDs` as an unknown
-- parameter and the tile renders a dash rather than a count.
--
-- Making the declaration work needs MetadataSync to write sync-supplied parameters before the parent
-- save that triggers extraction, and extraction to yield to them: MemberJunction/MJ#4545.
SELECT
    COUNT(DISTINCT c.CustomerOrganizationID) AS CustomerCount,
    COUNT(*) AS ContractCount
FROM [__mj_BizAppsContracts].vwContracts c
WHERE c.HasModifications = 1
  AND c.State IN (N'Active', N'Executed')
  {% if CompanyIDs and CompanyIDs.length %}
  AND c.CompanyID IN {{ CompanyIDs | sqlIn }}
  {% endif %};
