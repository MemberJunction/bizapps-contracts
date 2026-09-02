-- =============================================================================
-- V202609010100 — "Awaiting document" means the EXECUTED AGREEMENT is missing.
-- =============================================================================
-- Issue #28 item 16. `vwContracts.IsAwaitingDocument` cleared as soon as ANY file
-- was linked to the contract, so attaching an exhibit, a draft or the wrong PDF
-- silenced the warning. The system had no way to tell the executed agreement from
-- a scan of a business card, which makes the chip worse than absent: it reports
-- "paper received" on a contract nobody has signed.
--
-- The link must now carry MJ's file CATEGORY named 'Executed Agreement'.
--
-- WHY A CATEGORY AND NOT A COLUMN ON Contract. ERD R-8 deliberately ships no
-- `ExecutedDocumentFileID` FK -- a contract must be creatable before any paper
-- exists, and the generic link table is sufficient. "What kind of document is
-- this" is a property of the FILE, which is exactly what `__mj.FileCategory` is
-- for. One contract can hold the executed agreement, its exhibits and a
-- countersigned amendment; only the first answers this question.
--
-- TWO STEPS, AND THE ORDER MATTERS ONLY ONE WAY. The category row is seeded first
-- so the view never resolves against an empty table on a fresh install. The view
-- itself is safe either way: it joins by NAME, so it simply reports every contract
-- as awaiting until the row exists, rather than failing.
--
-- LOOKED UP BY NAME, never by ID. Both the Entity id (CodeGen mints it at first
-- registration) and the category id (seeded per database) differ between
-- environments, so a hardcoded UUID stops matching the first time either is
-- rebuilt from zero. Idempotent throughout: re-running seeds nothing twice and
-- CREATE OR ALTER is by definition re-appliable.
--
-- ⚠ WHAT THIS MIGRATION DELIBERATELY DOES NOT DO. Item 13 asks for `Terminated`
-- to become inclusive of its date (`TerminatedDate <= today`). It is NOT here.
-- The current `<` is a documented, reasoned decision in
-- V202608240200 -- "a period ending on a date runs through the END of that date
-- (an agreement 'terminating on 31 December' is in force all of 31 December)" --
-- and `test-harnesses/state-derivation.mjs` asserts it in three fixtures. Item 13
-- reverses that on purpose or by oversight, and which one it is needs a person to
-- say. Bundling it in here would have buried the contradiction in a migration
-- nobody re-reads.
-- =============================================================================

---------------------------------------------------------------------------
-- 1 · The category. Idempotent by NAME, which is what the view resolves on.
---------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[FileCategory] WHERE [Name] = N'Executed Agreement')
BEGIN
    INSERT INTO [${mjSchema}].[FileCategory] ([ID], [Name], [Description])
    VALUES (NEWID(), N'Executed Agreement',
            N'The signed contract itself, as opposed to an exhibit, a draft or a countersigned amendment. Contracts' IsAwaitingDocument reports a contract as awaiting paper until a file in this category is linked to it.');
END
GO

---------------------------------------------------------------------------
-- 2 · vwContracts, with IsAwaitingDocument narrowed to that category.
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
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate < CAST(GETUTCDATE() AS date) THEN 'Terminated'
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
    -- WHICH FILE COUNTS, and this is the change (issue #28 item 16). ANY linked file
    -- used to clear the flag, so attaching an exhibit, a draft or the wrong PDF
    -- silenced the warning -- the system could not tell the executed agreement from
    -- a scan of a business card. The link now has to carry MJ's file CATEGORY named
    -- 'Executed Agreement'.
    --
    -- A CATEGORY RATHER THAN A COLUMN ON Contract, deliberately: ERD R-8 ships no
    -- ExecutedDocumentFileID FK, and a category is a property of the FILE, which is
    -- where "what kind of document is this" belongs. One contract can hold the
    -- executed agreement, its exhibits and a countersigned amendment, and only the
    -- first answers this question.
    --
    -- BOTH lookups are BY NAME rather than hardcoded: CodeGen mints the Entity id on
    -- first registration and the category row is seeded per database, so a literal
    -- UUID stops matching the first time either is rebuilt from zero.
    CAST(CASE
        WHEN ct.RequiresExecutedDocument = 1
         AND NOT EXISTS (
                SELECT 1
                  FROM [${mjSchema}].[FileEntityRecordLink] fl
                  JOIN [${mjSchema}].[File] f
                    ON f.ID = fl.FileID
                  JOIN [${mjSchema}].[FileCategory] fc
                    ON fc.ID = f.CategoryID
                 WHERE fl.EntityID = (SELECT e.ID FROM [${mjSchema}].[Entity] e
                                       WHERE e.Name = 'MJ_BizApps_Contracts: Contracts')
                   AND fl.RecordID = CAST(g.ID AS nvarchar(450))
                   AND fc.Name = 'Executed Agreement'
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

GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO
