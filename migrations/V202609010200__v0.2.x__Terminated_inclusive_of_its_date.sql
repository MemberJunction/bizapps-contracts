-- =============================================================================
-- V202609010200 — a contract is Terminated ON its Terminated Date, not the day after.
-- =============================================================================
-- Issue #28 item 13. `vwContracts` read `TerminatedDate < CAST(GETUTCDATE() AS
-- date)`, so setting Terminated Date = today saved successfully and left the chip
-- reading Active until tomorrow. The boundary is now `<=`.
--
-- THIS REVERSES A DOCUMENTED DECISION, so the reasoning is set out rather than
-- quietly overwritten. V202608240200 derived the exclusive boundary from EndDate:
-- a period ending on a date runs through the END of that date, an agreement
-- "terminating on 31 December" being in force all of 31 December, and concluded
-- that TerminatedDate deserved "the same treatment as EndDate ... both are
-- dates".
--
-- The symmetry is the part that does not hold. EndDate is the last day OF the
-- term; the agreement is in force through it, `<` is correct, and it is
-- deliberately LEFT ALONE. TerminatedDate is the date the agreement WAS ENDED --
-- an event, not the natural close of a period. "Terminated on 15 March" means
-- dead on the 15th. Two columns both being `date` does not make an event and a
-- period boundary the same kind of thing.
--
-- The issue author reached the same split explicitly, which is why this is read as
-- a deliberate override rather than an oversight: item 13 states the EndDate
-- argument in full and says to LEAVE `<` there while changing Terminated. The form
-- already agrees -- item 19 replaced the Dates hint with "Setting this marks the
-- contract Terminated from this date.", which asserts the inclusive reading.
--
-- WHAT DOES NOT CHANGE, and it was the earlier file's genuine fix: a FUTURE
-- TerminatedDate -- notice served, effective later -- must not read as already
-- terminated. `<= today` still leaves tomorrow's termination Active today. Only
-- the same-day case moves. `state-derivation.mjs` is updated in the same commit:
-- its "terminated TODAY" fixture now expects Terminated.
--
-- Superseded is untouched. Item 13 confirms the current behaviour -- a predecessor
-- reads Superseded as soon as it is linked, regardless of the successor's dates --
-- as intended.
--
-- Carries the whole view because that is how CREATE OR ALTER works; the only
-- executable difference from V202609010100 is one character in the Terminated
-- branch.
-- =============================================================================

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
    --
    --               The boundary is `<= today`, INCLUSIVE, and this reverses the reading
    --               V202608240200 shipped (issue #28 item 13). That file argued the
    --               boundary from EndDate: "a period ending on a date runs through the
    --               END of that date (an agreement 'terminating on 31 December' is in
    --               force all of 31 December)", and concluded "same treatment as EndDate
    --               below, which is the point: both are dates".
    --
    --               THE SYMMETRY IS THE PART THAT WAS WRONG. EndDate is the last day OF
    --               the term -- the agreement is in force through it, so `<` is right and
    --               is deliberately LEFT ALONE below. TerminatedDate is the date the
    --               agreement WAS ENDED: an event, not the natural close of a period.
    --               "Terminated on 15 March" means dead on the 15th. Two columns being
    --               `date` does not make an event and a period boundary the same thing,
    --               and treating them alike made the form say one thing and the chip
    --               another -- the Dates hint promised "Terminated regardless of its
    --               term" while a contract terminated today still read Active. That hint
    --               is now "Setting this marks the contract Terminated from this date."
    --               (item 19), which asserts exactly this inclusive reading.
    --
    --               WHAT DOES NOT CHANGE, and it was the other file's real fix: a FUTURE
    --               TerminatedDate -- notice served, effective later -- must NOT read as
    --               already terminated. `<= today` still leaves tomorrow's termination
    --               Active today. Only the same-day case moves. (A contract specifying a
    --               TIME, or an immediate for-cause termination, needs datetime2 -- not
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

GO

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];
GO
