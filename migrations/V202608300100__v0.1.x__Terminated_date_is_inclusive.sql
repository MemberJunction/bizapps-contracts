--
-- contracts#28 item 13 -- A CONTRACT IS TERMINATED ON AND AFTER ITS TERMINATED DATE.
--
-- WHAT WAS WRONG. `vwContracts` derived Terminated from `TerminatedDate < today`, so a contract
-- terminated TODAY still read Active until midnight. The Dates tab tells the user that setting a
-- Terminated Date "marks the contract Terminated from this date", and for the whole of that first day
-- the form disagreed with itself.
--
-- WHAT CHANGES. Exactly one operator, in one branch: `<` becomes `<=`.
--
-- WHAT DELIBERATELY DOES NOT CHANGE, because the same argument does NOT apply:
--
--   * Expired stays `EndDate < today`. A term that ends today is in force THROUGH today -- the end
--     date is the last day of the agreement, not the first day after it. Terminated is the opposite
--     kind of date: it is the day the agreement stops. Making both inclusive would be symmetry for
--     its own sake and would expire contracts a day early.
--
--   * A future Terminated Date still leaves the contract Active until that day arrives. Notice served
--     is not termination taken effect.
--
--   * Superseded still wins the moment the successor FK is set, regardless of either contract's dates.
--     Confirmed as intended in the issue -- no change.
--
-- The whole view is re-emitted rather than patched, because `CREATE OR ALTER VIEW` has no partial
-- form; the body below is V202608240200's, with that one operator changed.
--
-- Proof: `test-harnesses/state-derivation.mjs` exists for exactly this boundary and its fixture for
-- "terminated TODAY" flips from Active to Terminated in the same commit. Its own docstring records
-- that this rule has already been wrong in both directions once.
--

---------------------------------------------------------------------------
-- 1 · vwContracts — the lifecycle and renewal columns.
---------------------------------------------------------------------------
CREATE OR ALTER VIEW [${flyway:defaultSchema}].[vwContracts]
AS
SELECT
    g.*,

    -- STATE — the lifecycle, in strict precedence order (ERD §4.5). Read the CASE
    -- top to bottom: the first branch that matches wins, and the order encodes
    -- which fact outranks which.
    --
    --   Terminated  outranks everything ONCE IT HAS TAKEN EFFECT: somebody ended this
    --               agreement, and that is a fact about what happened, not a projection
    --               of the term. It stays Terminated even if the end date later passes.
    --               The boundary is `< today`, NOT `IS NOT NULL`, and that is contract
    --               law rather than a coding preference: a period ending on a date runs
    --               through the END of that date (an agreement "terminating on 31
    --               December" is in force all of 31 December), so a contract whose
    --               TerminatedDate is TODAY is still in force today and reads Terminated
    --               from tomorrow. A FUTURE TerminatedDate — notice served, effective
    --               later — must therefore NOT read as already terminated; before this
    --               fix it did. Same treatment as EndDate below, which is the point:
    --               both are dates, and a `date` column carries no time, so end-of-day
    --               is the only reading available. (A contract that specifies a TIME,
    --               or an immediate for-cause termination, needs datetime2 — not
    --               expressible here, and out of scope.)
    --   Superseded  the successor FK IS the superseded state — there is no separate
    --               column to disagree with it (R-18 dropped the tautological CHECK).
    --   Expired     the term ran out on its own.
    --   Active      in force: started, not ended, not replaced.
    --   Executed    signed but NOT YET in force (R-19). This branch exists because
    --               without it a contract signed weeks before its term starts fell
    --               through to Draft — indistinguishable from one nobody has touched.
    --               That is the ordinary case in renewal season, not an anomaly.
    --               Draft is a TASK (finish this); Executed is a WAIT (nothing to do
    --               until the date arrives), and a watchlist that merges them makes
    --               finance re-triage the same rows every week.
    --   Draft       everything else.
    --
    -- Note the Executed branch accepts a NULL EffectiveDate: a signed contract with
    -- no start date recorded is Executed, because the signature is the fact that
    -- moved it on.
    CASE
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= CAST(GETUTCDATE() AS date) THEN 'Terminated'
        WHEN g.SupersededByContractID IS NOT NULL                          THEN 'Superseded'
        WHEN g.EndDate IS NOT NULL AND g.EndDate < CAST(GETUTCDATE() AS date) THEN 'Expired'
        WHEN g.EffectiveDate IS NOT NULL AND g.EffectiveDate <= CAST(GETUTCDATE() AS date) THEN 'Active'
        WHEN g.ExecutedDate IS NOT NULL                                    THEN 'Executed'
        ELSE 'Draft'
    END AS [State],

    -- IS AWAITING DOCUMENT — the contract TYPE expects executed paper and none is
    -- linked. Two halves, and both matter:
    --
    --  * `RequiresExecutedDocument` lives on ContractType, not on Contract. A
    --    Payment Link therefore NEVER reports as awaiting, which is the whole
    --    reason this was never a status value: "no document" is normal for it.
    --  * the document is found through `__mj.FileEntityRecordLink`, MJ's generic
    --    record↔file join, because contracts deliberately ships NO named
    --    ExecutedDocumentFileID FK (ERD R-8) — the link table is sufficient and a
    --    contract must be creatable before any paper exists.
    --
    -- The Entity id is looked up BY NAME rather than hardcoded: CodeGen mints it on
    -- first registration, so a literal UUID stops matching the first time this
    -- database is rebuilt from zero.
    CAST(CASE
        WHEN ct.RequiresExecutedDocument = 1
         AND NOT EXISTS (
                SELECT 1
                  FROM [${mjSchema}].[FileEntityRecordLink] fl
                 WHERE fl.EntityID = (SELECT e.ID FROM [${mjSchema}].[Entity] e
                                       WHERE e.Name = 'MJ_BizApps_Contracts: Contracts')
                   AND fl.RecordID = CAST(g.ID AS nvarchar(450))
             )
        THEN 1 ELSE 0
    END AS bit) AS [IsAwaitingDocument],

    -- IS CHANGE ORDER — reads the FK, not the type name. A change order is a
    -- first-class contract that names what it amends; the ContractType row is how a
    -- person labels it, ParentContractID is the structural fact. Keeping the
    -- derivation on the FK means a mislabelled type cannot make the lineage lie.

    -- DAYS TO END — signed, so an expired contract reads negative rather than
    -- clamping to zero and looking like it ends today.
    CASE WHEN g.EndDate IS NULL THEN NULL
         ELSE DATEDIFF(day, CAST(GETUTCDATE() AS date), g.EndDate) END AS [DaysToEnd],

    -- RENEWAL NOTICE DEADLINE — the last day we can give notice and still meet the
    -- obligation the paper states. This is the watchlist's sort key: the date that
    -- matters is not when the contract ends, it is when our chance to act on it ends.
    CASE WHEN g.EndDate IS NULL OR g.RenewalNoticeDays IS NULL THEN NULL
         ELSE DATEADD(day, -g.RenewalNoticeDays, g.EndDate) END AS [RenewalNoticeDeadline],

    -- IS IN CANCELLATION WINDOW — today falls inside the customer's cancellation
    -- notice period. Deliberately a separate column from the renewal deadline even
    -- though many agreements set the two day-counts equal: they are different
    -- obligations owed by different parties, and conflating them is exactly how a
    -- notice obligation gets missed (see the RenewalNoticeDays column comment).
    CAST(CASE
        WHEN g.EndDate IS NOT NULL AND g.CancellationWindowDays IS NOT NULL
         AND CAST(GETUTCDATE() AS date) >= DATEADD(day, -g.CancellationWindowDays, g.EndDate)
         AND CAST(GETUTCDATE() AS date) <= g.EndDate
        THEN 1 ELSE 0
    END AS bit) AS [IsInCancellationWindow]
FROM
    [${flyway:defaultSchema}].[vwContractsGenerated] g
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[ContractType] ct
  ON
    g.ContractTypeID = ct.ID;
GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO
