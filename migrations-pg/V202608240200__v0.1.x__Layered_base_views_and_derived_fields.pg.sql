-- ============================================================================
-- MemberJunction PostgreSQL Migration
-- Converted from SQL Server using TypeScript conversion pipeline
-- ============================================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Schema
--
-- The schema name is emitted UNQUOTED, so PostgreSQL folds it to lowercase. That is deliberate and
-- self-consistent: everything downstream in a converted migration refers to it unquoted too, so
-- both definition and lookup land on the same folded name.
--
-- DOWNSTREAM NOTE for the build engineer: a PostgreSQL database that was populated by an EARLIER
-- converter — one that emitted a quoted, case-preserved name — already holds that mixed-case
-- schema: for a target named MySchema_Name, the quoted "MySchema_Name". Re-converting against
-- that database creates a SECOND, empty schema myschema_name rather than reusing the existing
-- one, because IF NOT EXISTS compares the folded name and finds no match. The repo's own committed
-- migrations-pg files are unaffected (the only quoted CREATE SCHEMAs there are the four pg_dump
-- baselines, which this path does not produce), so this is an open-app / downstream concern, not
-- one for this repo's Flyway history.
CREATE SCHEMA IF NOT EXISTS __mj_BizAppsContracts;
SET search_path TO __mj_BizAppsContracts, public;

-- Ensure backslashes in string literals are treated literally (not as escape sequences)
SET standard_conforming_strings = on;

-- NOTE: Earlier converter versions made INTEGER to BOOLEAN cast implicit by
-- modifying the system catalog so SS-style INSERT INTO bool_col VALUES (1)
-- would work. That modification required pg_catalog write privileges, which
-- managed PG (RDS, Aurora, Cloud SQL, Azure) does not grant. As of v5.30 all
-- bulk INSERTs are emitted with native TRUE/FALSE values directly, so the
-- cast modification is no longer needed. Removed to support managed-PG
-- installs out of the box.


-- ===================== Data (INSERT/UPDATE/DELETE) =====================

DO $mj$
BEGIN
  ---------------------------------------------------------------------------
  -- 3 · Register every column these views ADD, so MJ can see them. Without an
  --     EntityField row the column exists in SQL and there is no RunView filter,
  --     no grid column and no typed property on the entity class. A fresh install
  --     never runs CodeGen, so the discovery has to ship as a migration.
  --
  --     TWO OF THESE ARE NOT DERIVED COLUMNS: ParentContract and
  --     SupersededByContract are the joined NAME columns for Contract's two
  --     self-referencing FKs. They are registered here for a sequencing reason
  --     rather than a conceptual one -- they first appear in the GENERATED inner
  --     view built by the previous migration, and no CodeGen run happens after
  --     that point in a fresh install, so nothing else would ever register them.
  --     Leaving them out is not harmless: the Lineage panel reads
  --     Record.ParentContract for the parent's display name, and an unregistered
  --     column is not a property on the entity class -- it reads as blank rather
  --     than failing.
  ---------------------------------------------------------------------------
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_State IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_State AND "Name" = 'State') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_State,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_State),
  'State', 'State', NULL,
  'varchar', 10, 0, 0,
  0,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  1,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_IsAwaitingDocument IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_IsAwaitingDocument AND "Name" = 'IsAwaitingDocument') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_IsAwaitingDocument,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_IsAwaitingDocument),
  'IsAwaitingDocument', 'Is Awaiting Document', NULL,
  'BOOLEAN', 1, 1, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_DaysToEnd IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_DaysToEnd AND "Name" = 'DaysToEnd') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_DaysToEnd,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_DaysToEnd),
  'DaysToEnd', 'Days To End', NULL,
  'INTEGER', 4, 10, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_RenewalNoticeDeadline IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_RenewalNoticeDeadline AND "Name" = 'RenewalNoticeDeadline') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_RenewalNoticeDeadline,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_RenewalNoticeDeadline),
  'RenewalNoticeDeadline', 'Renewal Notice Deadline', NULL,
  'date', 3, 10, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_IsInCancellationWindow IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_IsInCancellationWindow AND "Name" = 'IsInCancellationWindow') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_IsInCancellationWindow,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_IsInCancellationWindow),
  'IsInCancellationWindow', 'Is In Cancellation Window', NULL,
  'BOOLEAN', 1, 1, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contract Templates'
  );
  IF v_e_IsUsable IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_IsUsable AND "Name" = 'IsUsable') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_IsUsable,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_IsUsable),
  'IsUsable', 'Is Usable', 'Whether the standard terms this version names can actually be READ: it records a SourceURL, or a file is attached to it. Derived in vwContractTemplates — a tem',
  'BOOLEAN', 1, NULL, NULL,
  0,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  1,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_ParentContract IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_ParentContract AND "Name" = 'ParentContract') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_ParentContract,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_ParentContract),
  'ParentContract', 'Parent Contract', NULL,
  'TEXT', 100, 0, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;

DO $mj$
BEGIN
  SELECT "ID" FROM ${mjSchema}."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
  );
  IF v_e_SupersededByContract IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM ${mjSchema}."EntityField"
  WHERE "EntityID" = v_e_SupersededByContract AND "Name" = 'SupersededByContract') THEN
  INSERT INTO ${mjSchema}."EntityField"
  ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
  "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
  "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
  VALUES (
  v_e_SupersededByContract,
  (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM ${mjSchema}."EntityField" WHERE "EntityID" = v_e_SupersededByContract),
  'SupersededByContract', 'Superseded By Contract', NULL,
  'TEXT', 100, 0, 0,
  1,   -- AllowsNull
  1,   -- IsVirtual: derived in the wrapper view, not a table column
  0,   -- DefaultInView
  0,   -- AllowUpdateAPI: derived, therefore read-only
  1,   -- IncludeInGeneratedForm
  0, 0
  );
  END IF;
END $mj$;


-- ===================== Grants =====================

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsContracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT SELECT ON __mj_BizAppsContracts."vwContractTemplates" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
-- ===================== Other =====================

-- NOTE: unrecognized batch type (UNKNOWN) — passed through as-is
-- =============================================================================
-- V202608240200 — the application-owned WRAPPER views, and the derived columns
--                 they add registered as virtual EntityFields.
-- =============================================================================
-- The last file of the layered base views. The previous migration set the flags and
-- created CodeGen's inner views; this one creates the two views the application owns
-- and then tells MJ about the columns they add.
--
-- WHY IT IS A SEPARATE FILE FROM THE FLAGS. A view cannot be created before the view
-- it selects FROM — SQL Server has deferred name resolution for procedure bodies but
-- not for views — so vwContractsGenerated has to be committed before vwContracts can
-- compile. That is the whole reason the layering costs three files instead of one.
--
-- WHAT IS DERIVED HERE, AND WHY IT IS NOT STORED (ERD §7.2). Every added column is a
-- projection of facts the row already holds. A stored copy of a projection can only
-- agree or lie, and the lie is silent: a nightly job that misses one row leaves a
-- contract reading Active forever. The cost of deriving is one view; the cost of
-- storing is a reconciliation problem nobody owns. This is what replaced the v1
-- `Status` column outright (D-19 / ERD R-18) — four of its five values were
-- projections of these same dates and self-FKs, and the fifth, `Draft`, was the
-- finance TASK wearing a status.
--
-- ⚠ THE FIELD REGISTRATIONS BELOW ARE EXPLICIT INSERTS, NOT A CODEGEN CAPTURE, and
-- that is a deliberate change from the migration train this baseline replaces. The
-- old train registered the Contract half by capturing a third CodeGen run, which
-- carried a real hazard: a capture contains spDeleteUnneededEntityFields sweeps that
-- compare metadata against the LIVE base view, so replaying it anywhere the wrapper
-- did not yet exist DELETED the very rows the file had just inserted. Explicit
-- INSERTs have no sweep, are idempotent by their NOT EXISTS guard, are a tenth the
-- size, and can be read. This also follows what the ContractTemplate half already
-- did (IsUsable was registered this way from the start).
--
-- Sequence is computed at APPLY TIME, never a literal. MJ's rule (migrations/CLAUDE.md):
-- the number CodeGen writes is a placeholder that a REPEATABLE script renumbers, and
-- Flyway runs every versioned migration before any repeatable script — so on a
-- from-scratch database a literal never gets renumbered in time, and a second
-- migration touching the same entity collides on UQ_EntityField_EntityID_Sequence
-- while reporting itself as an unrelated foreign-key error. It cannot fail on a
-- working dev database; it fails only on fresh installs.
--
-- ⓘ The five Contract derived fields carry NO Description, which is inherited from the
-- capture that used to register them rather than intended. Filling them in is a
-- content change, deliberately not made here so this baseline stays a pure refactor of
-- what the old train produced. Tracked separately.
-- =============================================================================

---------------------------------------------------------------------------
-- 1 · vwContracts — the lifecycle and renewal columns.
---------------------------------------------------------------------------
CREATE OR ALTER VIEW "__mj_BizAppsContracts"."vwContracts"
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
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" < CAST(NOW() AS date) THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL                          THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < CAST(NOW() AS date) THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= CAST(NOW() AS date) THEN 'Active'
        WHEN g."ExecutedDate" IS NOT NULL                                    THEN 'Executed'
        ELSE 'Draft'
    END AS "State",

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
        WHEN ct."RequiresExecutedDocument" = 1
         AND NOT EXISTS (
                SELECT 1
                  FROM "${mjSchema}"."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM "${mjSchema}"."Entity" e
                                       WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts')
                   AND fl."RecordID" = CAST(g."ID" AS VARCHAR(450))
             )
        THEN 1 ELSE 0
    END AS bit) AS "IsAwaitingDocument",

    -- IS CHANGE ORDER — reads the FK, not the type name. A change order is a
    -- first-class contract that names what it amends; the ContractType row is how a
    -- person labels it, ParentContractID is the structural fact. Keeping the
    -- derivation on the FK means a mislabelled type cannot make the lineage lie.

    -- DAYS TO END — signed, so an expired contract reads negative rather than
    -- clamping to zero and looking like it ends today.
    CASE WHEN g."EndDate" IS NULL THEN NULL
         ELSE DATEDIFF(day, CAST(NOW() AS date), g."EndDate") END AS "DaysToEnd",

    -- RENEWAL NOTICE DEADLINE — the last day we can give notice and still meet the
    -- obligation the paper states. This is the watchlist's sort key: the date that
    -- matters is not when the contract ends, it is when our chance to act on it ends.
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE DATEADD(day, -g."RenewalNoticeDays", g."EndDate") END AS "RenewalNoticeDeadline",

    -- IS IN CANCELLATION WINDOW — today falls inside the customer's cancellation
    -- notice period. Deliberately a separate column from the renewal deadline even
    -- though many agreements set the two day-counts equal: they are different
    -- obligations owed by different parties, and conflating them is exactly how a
    -- notice obligation gets missed (see the RenewalNoticeDays column comment).
    CAST(CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND CAST(NOW() AS date) >= DATEADD(day, -g."CancellationWindowDays", g."EndDate")
         AND CAST(NOW() AS date) <= g."EndDate"
        THEN 1 ELSE 0
    END AS bit) AS "IsInCancellationWindow"
FROM
    "__mj_BizAppsContracts"."vwContractsGenerated" g
LEFT OUTER JOIN
    "__mj_BizAppsContracts"."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID";

-- NOTE: unrecognized batch type (UNKNOWN) — passed through as-is
---------------------------------------------------------------------------
-- 2 · vwContractTemplates — IsUsable.
--
--     It HAS to be a view, and the contrast with ProvisionSortKey is worth
--     keeping in mind: a sort key is a pure function of one column in one row,
--     so it is a computed column and needs no view at all. IsUsable reads
--     ANOTHER TABLE (__mj.FileEntityRecordLink), and a computed column cannot.
--     Row-local scalar -> computed column; reads another table -> layered view.
---------------------------------------------------------------------------
CREATE OR ALTER VIEW "__mj_BizAppsContracts"."vwContractTemplates"
AS
SELECT
    g.*,
    CAST(CASE
        WHEN g."SourceURL" IS NOT NULL AND LENGTH(LTRIM(RTRIM(g."SourceURL"))) > 0 THEN 1
        WHEN EXISTS (
                SELECT 1
                  FROM "${mjSchema}"."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM "${mjSchema}"."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contract Templates')
                   AND fl."RecordID" = CAST(g."ID" AS VARCHAR(450))
             ) THEN 1
        ELSE 0
    END AS bit) AS "IsUsable"
FROM
    "__mj_BizAppsContracts"."vwContractTemplatesGenerated" AS g;
