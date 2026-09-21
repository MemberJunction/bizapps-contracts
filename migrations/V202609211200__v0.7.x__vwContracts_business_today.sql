-- =============================================================================
-- V202609211200 — the lifecycle is judged on the BUSINESS day, not the UTC day.
-- =============================================================================
-- bc-aidp-next-golive#168. Every date comparison in this view was made against the
-- SERVER'S UTC calendar day, which is already tomorrow for the whole American
-- evening: a contract ending 31 December read as Expired from 6 PM Central on the
-- 31st, and DaysToEnd, DaysUntilNoticeDeadline, NonRenewalOutcome and
-- IsInCancellationWindow all moved an evening early.
--
-- SIX, not seven: 31 December is CST, which is UTC-6, so the UTC day rolls at
-- 18:00 Central. Half the year Central is on CDT (UTC-5) and the roll is at 7 PM.
-- The hour is not the bug and neither number is the fix — the whole evening is
-- wrong in both — but a worked example that does not survive arithmetic is how a
-- reader concludes the rest of the reasoning was not checked either.
--
-- "Today" is now `bt.Today` from bizapps-common's `fnBusinessToday()`: the calendar
-- day in the zone the business books in (the instance's `BizApps.BusinessTimeZone`
-- setting), CROSS JOINed ONCE per query so every column in a row answers on the same
-- day. Nine comparisons change; nothing else about the view does.
--
-- DEPENDENCY. `[__mj_BizAppsCommon].[fnBusinessToday]()` ships in bizapps-common's
-- business-time-zone migration. It must be applied to this database FIRST. The guard
-- below fails this migration with a readable message rather than letting SQL Server
-- report an invalid object name from inside a view body.
--
-- ⚠ THIS MIGRATION RE-CREATES THE WHOLE VIEW, so it carries forward every decision
-- already made about it. Three are worth naming because each was lost or nearly lost
-- once already:
--
--  * ITEM 13 (V202608300100): `Terminated` is INCLUSIVE of its date (`<=`), because
--    the Dates tab tells the user that setting the date marks the contract Terminated
--    FROM that date. `Expired` deliberately stays `<`: an End Date is the last day the
--    agreement COVERS, a Terminated Date is the day it STOPS.
--  * ITEM 16 (V202609010100): `IsAwaitingDocument` counts only a linked file carrying
--    the file CATEGORY named 'Executed Agreement'. **This was silently reverted by
--    V202609202354**, whose re-creation of the view dropped the File/FileCategory
--    joins and went back to "any linked file clears the flag" — so attaching an
--    exhibit, a draft or the wrong PDF silences the warning again. Restored here,
--    with the reasoning that was written for it. Nothing tested it: the guards in
--    `executed-agreement-panel.test.ts` and `dates-executed-doc-and-readonly.test.ts`
--    pinned themselves to the migration that SEEDS the category row, not to the
--    newest definer of the view, so they stayed green straight through the
--    regression. Both now resolve the newest definer, through the same helper
--    `contract-state.test.ts` uses.
--  * V202609202354: the predictive/engineered feature columns (NonRenewalOutcome,
--    TermLengthDays, DaysUntilNoticeDeadline, HasModificationsFlag, AutoRenewFlag,
--    HasParentContract, HasCancellationWindow, HasAnnualIncrease) are carried forward
--    verbatim, with their date comparisons moved onto `bt.Today` like the rest.
--
-- Idempotent: CREATE OR ALTER is by definition re-appliable, and the guard is a read.
-- =============================================================================

---------------------------------------------------------------------------
-- 0 · The business-day function must already exist.
---------------------------------------------------------------------------
IF OBJECT_ID('[__mj_BizAppsCommon].[fnBusinessToday]', 'IF') IS NULL
BEGIN
    THROW 51168, 'bizapps-contracts V202609211200 requires [__mj_BizAppsCommon].[fnBusinessToday](). Apply the bizapps-common business-time-zone migration to this database first.', 1;
END
GO

---------------------------------------------------------------------------
-- 1 · vwContracts, judged on the business day.
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
    --               The boundary is `<= bt.Today`, NOT `IS NOT NULL` (item 13, shipped in
    --               V202608300100 and carried forward here): the Dates tab tells the
    --               user that setting a Terminated Date marks the contract Terminated
    --               FROM that date, so the day itself must read Terminated rather than
    --               Active-until-midnight. A FUTURE TerminatedDate — notice served,
    --               effective later — still reads as not yet terminated, which is why
    --               this is a date comparison and not `IS NOT NULL`.
    --               NOT symmetric with EndDate below, deliberately: an End Date is the
    --               last day the agreement COVERS, a Terminated Date is the day it
    --               STOPS, so `Expired` stays `<` and making the pair match would
    --               expire every contract a day early. (A contract that specifies a
    --               TIME, or an immediate for-cause termination, needs datetime2 — not
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
    --
    -- The three date boundaries are compared against `bt.Today` — the calendar day in
    -- the BUSINESS time zone (#168) — and no longer against the server's UTC day.
    CASE
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= bt.Today THEN 'Terminated'
        WHEN g.SupersededByContractID IS NOT NULL                          THEN 'Superseded'
        WHEN g.EndDate IS NOT NULL AND g.EndDate < bt.Today THEN 'Expired'
        WHEN g.EffectiveDate IS NOT NULL AND g.EffectiveDate <= bt.Today THEN 'Active'
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
    -- WHICH FILE COUNTS (issue #28 item 16). ANY linked file used to clear the flag,
    -- so attaching an exhibit, a draft or the wrong PDF silenced the warning — the
    -- system could not tell the executed agreement from a scan of a business card.
    -- The link has to carry MJ's file CATEGORY named 'Executed Agreement'.
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

    -- DAYS TO END — signed, so an expired contract reads negative rather than
    -- clamping to zero and looking like it ends today. Counted from the business day.
    CASE WHEN g.EndDate IS NULL THEN NULL
         ELSE DATEDIFF(day, bt.Today, g.EndDate) END AS [DaysToEnd],

    -- RENEWAL NOTICE DEADLINE — the last day we can give notice and still meet the
    -- obligation the paper states. This is the watchlist's sort key: the date that
    -- matters is not when the contract ends, it is when our chance to act on it ends.
    -- Pure date arithmetic on stored columns, so no notion of "today" enters it.
    CASE WHEN g.EndDate IS NULL OR g.RenewalNoticeDays IS NULL THEN NULL
         ELSE DATEADD(day, -g.RenewalNoticeDays, g.EndDate) END AS [RenewalNoticeDeadline],

    -- IS IN CANCELLATION WINDOW — today falls inside the customer's cancellation
    -- notice period. Deliberately a separate column from the renewal deadline even
    -- though many agreements set the two day-counts equal: they are different
    -- obligations owed by different parties, and conflating them is exactly how a
    -- notice obligation gets missed (see the RenewalNoticeDays column comment).
    CAST(CASE
        WHEN g.EndDate IS NOT NULL AND g.CancellationWindowDays IS NOT NULL
         AND bt.Today >= DATEADD(day, -g.CancellationWindowDays, g.EndDate)
         AND bt.Today <= g.EndDate
        THEN 1 ELSE 0
    END AS bit) AS [IsInCancellationWindow],

    -- ── Engineered features for Predictive Studio (V202609202354), carried forward ──

    -- NON RENEWAL OUTCOME — the training label: 1 when the agreement ended without
    -- renewing, 0 when it was superseded (a renewal IS a supersession), NULL while
    -- the outcome is still unknown. Same boundaries as State, so it must read the
    -- same day State does.
    CASE
        WHEN g.SupersededByContractID IS NOT NULL THEN 0
        WHEN g.TerminatedDate IS NOT NULL AND g.TerminatedDate <= bt.Today THEN 1
        WHEN g.EndDate IS NOT NULL AND g.EndDate < bt.Today THEN 1
        ELSE NULL
    END AS [NonRenewalOutcome],
    CASE WHEN g.EffectiveDate IS NOT NULL AND g.EndDate IS NOT NULL THEN DATEDIFF(day, g.EffectiveDate, g.EndDate) ELSE NULL END AS [TermLengthDays],
    CASE WHEN g.EndDate IS NOT NULL AND g.RenewalNoticeDays IS NOT NULL THEN DATEDIFF(day, bt.Today, DATEADD(day, -g.RenewalNoticeDays, g.EndDate)) ELSE NULL END AS [DaysUntilNoticeDeadline],
    CASE WHEN g.HasModifications = 1 THEN 1 ELSE 0 END AS [HasModificationsFlag],
    CASE WHEN g.AutoRenew = 1 THEN 1 ELSE 0 END AS [AutoRenewFlag],
    CASE WHEN g.ParentContractID IS NOT NULL THEN 1 ELSE 0 END AS [HasParentContract],
    CASE WHEN g.CancellationWindowDays > 0 THEN 1 ELSE 0 END AS [HasCancellationWindow],
    CASE WHEN g.AnnualIncreasePercent > 0 THEN 1 ELSE 0 END AS [HasAnnualIncrease]
FROM
    [${flyway:defaultSchema}].[vwContractsGenerated] g
CROSS JOIN
    [__mj_BizAppsCommon].[fnBusinessToday]() AS bt
LEFT OUTER JOIN
    [${flyway:defaultSchema}].[ContractType] ct
  ON
    g.ContractTypeID = ct.ID;
GO

-- Grants, guarded the way V202609202354 guards them: a database that has not created one of
-- the cdp_* principals is a legitimate install, and an unguarded GRANT aborts the migration there.
IF DATABASE_PRINCIPAL_ID('cdp_UI') IS NOT NULL
    EXEC('GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI]');
IF DATABASE_PRINCIPAL_ID('cdp_Developer') IS NOT NULL
    EXEC('GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_Developer]');
IF DATABASE_PRINCIPAL_ID('cdp_Integration') IS NOT NULL
    EXEC('GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_Integration]');
GO
