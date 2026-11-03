-- =============================================================================
-- PostgreSQL counterpart of V202611031700__v0.10.x__Persist_NonRenewalOutcome.sql
-- The renewal-risk label is stored, not computed on every read (issue #159)
-- =============================================================================
-- Same change as the T-SQL file; see its header for why. The objects differ in
-- form only:
--   * fnContractNonRenewalOutcome is a scalar SQL function (IMMUTABLE: its
--     result depends only on its arguments, the day included).
--   * The label is written by a BEFORE INSERT OR UPDATE row trigger that sets
--     NEW."NonRenewalOutcome", so PostgreSQL needs no second UPDATE and no
--     guard against the __mj_UpdatedAt trigger.
--   * spRecordContractNonRenewalOutcomes is a function returning the number of
--     rows it changed; the Contracts.RecordNonRenewalOutcomes action calls it
--     with SELECT. "Differs" is IS DISTINCT FROM, which treats NULL as equal.
--
-- HOW IT WAS MADE. `mj migrate convert --split --bake-codegen` (MJ CLI 6.1.6)
-- halts on this file: it reports the function, procedure and trigger as gaps
-- and bakes nothing until they are hand-written, and its view output does not
-- match the shipped one (boolean columns compared to 1, DATEDIFF rewritten as
-- epoch arithmetic). So:
--   * Hand-written DDL: written from the T-SQL file. vwContracts is the
--     PostgreSQL baseline's definition (its V202609211200 section) with the
--     label expression removed; the label now arrives through g.*.
--   * vwContracts must be dropped, not replaced: PostgreSQL cannot remove a
--     column from a view with CREATE OR REPLACE, and the label column moves
--     into g.*. DROP ... CASCADE also drops spCreateContract and
--     spUpdateContract, which return the view's row type.
--   * CodeGen objects (vwContractsGenerated, the three CRUD functions, the
--     update trigger, grants): the native PostgreSQL CodeGen block for Contract
--     from V202610122200's bake, unchanged. The T-SQL capture shows CodeGen's
--     output for these objects did not change (NonRenewalOutcome keeps
--     AllowUpdateAPI = false, so the CRUD functions take no parameter for it);
--     recreating vwContractsGenerated is what makes c.* include the new column.
--   * CodeGen-captured metadata: the four schema-refresh calls, in the
--     PostgreSQL form the earlier files use.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;

-- ===================== Hand-written DDL =====================

ALTER TABLE __mj_bizappscontracts."Contract"
  ADD COLUMN "NonRenewalOutcome" INTEGER NULL
    CONSTRAINT "CK_Contract_NonRenewalOutcome" CHECK ("NonRenewalOutcome" IN (0, 1));

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."NonRenewalOutcome" IS 'The renewal-risk model''s training label, recorded by the database: 0 when the contract was superseded (renewed), 1 when it was terminated or its term ended without renewal, NULL while the outcome is open. Written by trgContract_RecordNonRenewalOutcome on every save and by spRecordContractNonRenewalOutcomes when an end date passes; a value sent on save is replaced.';

CREATE FUNCTION __mj_bizappscontracts."fnContractNonRenewalOutcome"(
    "SupersededByContractID" UUID,
    "TerminatedDate"         DATE,
    "EndDate"                DATE,
    "AsOf"                   DATE
) RETURNS INTEGER
LANGUAGE sql IMMUTABLE
AS $fn$
    SELECT CASE
        WHEN "SupersededByContractID" IS NOT NULL                        THEN 0
        WHEN "TerminatedDate" IS NOT NULL AND "TerminatedDate" <= "AsOf" THEN 1
        WHEN "EndDate" IS NOT NULL AND "EndDate" < "AsOf"                THEN 1
        ELSE NULL
    END;
$fn$;

-- vwContracts goes first (see the header); the CodeGen block below recreates
-- vwContractsGenerated and the CRUD functions, then vwContracts is recreated.
DROP VIEW __mj_bizappscontracts."vwContracts" CASCADE;

-- ===================== CodeGen (native PG, baked in V202610122200; unchanged) =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: vwContractsGenerated
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contracts
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  Contract
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractsGenerated"
AS
SELECT
    c.*,
    mjbizappscontractsContractType_ContractTypeID."Name" AS "ContractType",
    MJCompany_CompanyID."Name" AS "Company",
    mjBizAppsCommonOrganization_CustomerOrganizationID."Name" AS "CustomerOrganization",
    mjBizAppsCommonPerson_PrimaryContactPersonID."DisplayName" AS "PrimaryContactPerson",
    mjbizappscontractsContractTemplate_ContractTemplateID."Name" AS "ContractTemplate",
    MJEntity_CreatingEntityID."Name" AS "CreatingEntity",
    mjbizappscontractsContract_ParentContractID."ContractNumber" AS "ParentContract",
    mjbizappscontractsContract_SupersededByContractID."ContractNumber" AS "SupersededByContract"
FROM
    "__mj_bizappscontracts"."Contract" AS c
INNER JOIN
    "__mj_bizappscontracts"."ContractType" AS mjbizappscontractsContractType_ContractTypeID
  ON
    "c"."ContractTypeID" = mjbizappscontractsContractType_ContractTypeID."ID"
INNER JOIN
    "__mj"."Company" AS MJCompany_CompanyID
  ON
    "c"."CompanyID" = MJCompany_CompanyID."ID"
INNER JOIN
    "__mj_bizappscommon"."Organization" AS mjBizAppsCommonOrganization_CustomerOrganizationID
  ON
    "c"."CustomerOrganizationID" = mjBizAppsCommonOrganization_CustomerOrganizationID."ID"
LEFT OUTER JOIN
    "__mj_bizappscommon"."Person" AS mjBizAppsCommonPerson_PrimaryContactPersonID
  ON
    "c"."PrimaryContactPersonID" = mjBizAppsCommonPerson_PrimaryContactPersonID."ID"
LEFT OUTER JOIN
    "__mj_bizappscontracts"."ContractTemplate" AS mjbizappscontractsContractTemplate_ContractTemplateID
  ON
    "c"."ContractTemplateID" = mjbizappscontractsContractTemplate_ContractTemplateID."ID"
LEFT OUTER JOIN
    "__mj"."Entity" AS MJEntity_CreatingEntityID
  ON
    "c"."CreatingEntityID" = MJEntity_CreatingEntityID."ID"
LEFT OUTER JOIN
    "__mj_bizappscontracts"."Contract" AS mjbizappscontractsContract_ParentContractID
  ON
    "c"."ParentContractID" = mjbizappscontractsContract_ParentContractID."ID"
LEFT OUTER JOIN
    "__mj_bizappscontracts"."Contract" AS mjbizappscontractsContract_SupersededByContractID
  ON
    "c"."SupersededByContractID" = mjbizappscontractsContract_SupersededByContractID."ID"
$vsql$;
  rec RECORD;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- 42P16: column rename/reorder/type change. CREATE OR REPLACE can't handle
  -- non-additive shape changes — must DROP CASCADE + recreate. CASCADE drops
  -- every dependent view (anything that JOINs this view in its body), so we
  -- capture each dependent's definition + grants BEFORE the drop and replay
  -- them afterward (best-effort). Without this, on a fresh-DB replay where
  -- one entity's wrapper triggers (e.g. vwAIModelTypes shape changed since
  -- baseline V202605021056), CASCADE wipes downstream views (vwAIModels)
  -- that the wrapper for this entity doesn't know how to recreate, and
  -- those views stay permanently missing.
  CREATE TEMP TABLE IF NOT EXISTS _vw_regen_deps (
    schema_name TEXT,
    view_name   TEXT,
    relkind     CHAR(1),
    definition  TEXT,
    grants_sql  TEXT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_deps;

  -- Capture dependent FUNCTIONS too. CASCADE drops every function with
  -- RETURNS SETOF <view> (the codegen-emitted spCreate/spUpdate/spDelete
  -- pattern) when the target view is dropped. Without restoring them,
  -- post-codegen CRUD validation reports those routines as missing —
  -- e.g. "MJ: Recommendation Items → missing create routine
  -- spCreateRecommendationItem" — even though the next codegen pass
  -- emits them. The restored definitions are pg_get_functiondef() output
  -- which is a complete CREATE OR REPLACE FUNCTION statement plus a
  -- trailing semicolon; replaying them verbatim recreates the function
  -- with its original body, parameter list, and return type.
  CREATE TEMP TABLE IF NOT EXISTS _vw_regen_fn_deps (
    schema_name TEXT,
    fn_name     TEXT,
    fn_oid      OID,
    definition  TEXT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_fn_deps;

  -- Capture dependents. NOTES on the grants_sql build:
  --   - Resolve role name via pg_get_userbyid(oid) — returns the bare,
  --     unquoted role name (or 'unknown (OID=N)' if the oid no longer
  --     exists). pg_get_userbyid is a public catalog function available to
  --     every database user, including unprivileged accounts on managed
  --     PostgreSQL services (Amazon RDS, Azure Database for PostgreSQL,
  --     Cloud SQL) where pg_authid is restricted to the rds_superuser /
  --     azure_pg_admin / cloudsqlsuperuser group. Earlier revisions joined
  --     to pg_authid which works on self-hosted PG but fails with
  --     "permission denied for table pg_authid" on managed services.
  --   - The earlier (broken) approach cast (aclexplode).grantee::regrole::text
  --     which RETURNS the role name pre-quoted when it contains uppercase
  --     (e.g. cdp_Developer comes back already wrapped); calling quote_ident
  --     on the already-quoted string double-wrapped and the GRANT failed at
  --     replay with "role does not exist". Using
  --     pg_get_userbyid returns a bare name and lets quote_ident wrap it
  --     correctly exactly once.
  --   - PUBLIC is grantee oid 0; pg_get_userbyid(0) returns 'unknown
  --     (OID=0)' so handle the PUBLIC case explicitly and use it as the
  --     literal 'PUBLIC' rather than quote_ident on the synthetic name.
  INSERT INTO _vw_regen_deps (schema_name, view_name, relkind, definition, grants_sql)
  SELECT DISTINCT
      dn.nspname,
      dc.relname,
      dc.relkind,
      pg_get_viewdef(dc.oid),
      (SELECT string_agg(
          'GRANT ' || g.privilege || ' ON ' || quote_ident(dn.nspname) || '.' || quote_ident(dc.relname) ||
          ' TO ' || (CASE WHEN g.grantee_oid = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee_oid)) END) || ';',
          E'
')
       FROM (
           SELECT (aclexplode(dc.relacl)).grantee AS grantee_oid,
                  (aclexplode(dc.relacl)).privilege_type AS privilege
       ) g
       WHERE g.privilege IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'))
  FROM pg_depend d
  JOIN pg_rewrite r ON r.oid = d.objid AND d.classid = 'pg_rewrite'::regclass
  JOIN pg_class dc ON dc.oid = r.ev_class AND dc.relkind IN ('v', 'm')
  JOIN pg_namespace dn ON dn.oid = dc.relnamespace
  JOIN pg_class tc ON tc.oid = d.refobjid
  JOIN pg_namespace tn ON tn.oid = tc.relnamespace
  WHERE tn.nspname = '__mj_bizappscontracts'
    AND tc.relname = 'vwContractsGenerated'
    AND tc.relkind IN ('v', 'm')
    AND dc.oid <> tc.oid;

  -- Capture dependent functions. Two paths matter on PG:
  --   1. Functions whose RETURN type references the view (RETURNS SETOF
  --      <view>) — pg_depend records this as type=pg_type → pg_class.
  --   2. Functions whose body references the view (used by sql functions
  --      and by some plpgsql edge cases) — pg_depend records this as
  --      pg_proc → pg_class.
  -- pg_get_functiondef returns a complete CREATE OR REPLACE FUNCTION
  -- statement that we replay verbatim. We DO include RETURNS-only
  -- references because that's the dominant codegen pattern (sp* CRUD
  -- functions all RETURNS SETOF the matching vwX).
  INSERT INTO _vw_regen_fn_deps (schema_name, fn_name, fn_oid, definition)
  SELECT DISTINCT
      pn.nspname,
      pp.proname,
      pp.oid,
      pg_get_functiondef(pp.oid)
  FROM pg_depend d
  JOIN pg_proc pp ON pp.oid = d.objid AND d.classid = 'pg_proc'::regclass
  JOIN pg_namespace pn ON pn.oid = pp.pronamespace
  JOIN pg_class tc ON tc.oid = d.refobjid
  JOIN pg_namespace tn ON tn.oid = tc.relnamespace
  WHERE tn.nspname = '__mj_bizappscontracts'
    AND tc.relname = 'vwContractsGenerated'
    AND tc.relkind IN ('v', 'm')
  UNION
  SELECT DISTINCT
      pn.nspname,
      pp.proname,
      pp.oid,
      pg_get_functiondef(pp.oid)
  FROM pg_depend d
  JOIN pg_type pt ON pt.oid = d.refobjid AND d.refclassid = 'pg_type'::regclass
  JOIN pg_proc pp ON pp.prorettype = pt.oid OR pt.typrelid = pp.oid
  JOIN pg_namespace pn ON pn.oid = pp.pronamespace
  WHERE EXISTS (
      SELECT 1 FROM pg_class tc
      JOIN pg_namespace tn ON tn.oid = tc.relnamespace
      WHERE tc.reltype = pt.oid
        AND tn.nspname = '__mj_bizappscontracts'
        AND tc.relname = 'vwContractsGenerated'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractsGenerated" CASCADE;
  EXECUTE vsql;

  -- Replay captured dependents. Best-effort: log + continue on failure.
  -- IMPORTANT: the CREATE VIEW and the GRANTs run in SEPARATE inner BEGIN
  -- blocks. PL/pgSQL's BEGIN ... EXCEPTION creates an implicit savepoint
  -- and rolls back EVERY statement in the block on any exception. If we
  -- combined CREATE+GRANT in one block and a GRANT failed (e.g. role not
  -- present in target environment), the just-recreated VIEW would also
  -- get rolled back and stay missing — the exact failure mode this
  -- wrapper exists to prevent.
  FOR rec IN SELECT schema_name, view_name, relkind, definition, grants_sql FROM _vw_regen_deps LOOP
    BEGIN
      IF rec.relkind = 'm' THEN
        EXECUTE 'CREATE MATERIALIZED VIEW ' || quote_ident(rec.schema_name) || '.' || quote_ident(rec.view_name) || ' AS ' || rec.definition;
      ELSE
        EXECUTE 'CREATE VIEW ' || quote_ident(rec.schema_name) || '.' || quote_ident(rec.view_name) || ' AS ' || rec.definition;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Best-effort restore skipped dependent %.%: %', rec.schema_name, rec.view_name, SQLERRM;
    END;

    IF rec.grants_sql IS NOT NULL THEN
      BEGIN
        EXECUTE rec.grants_sql;
      EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Best-effort grant restore skipped %.%: %', rec.schema_name, rec.view_name, SQLERRM;
      END;
    END IF;
  END LOOP;

  -- Replay captured dependent functions AFTER all dependent views are
  -- restored — most codegen-emitted sp* functions reference both the
  -- target view AND the dependent views in their bodies/return types.
  -- Wrapped per-function in its own savepoint so a single failure
  -- doesn't poison subsequent restores or the just-recreated target.
  FOR rec IN SELECT schema_name, fn_name, definition FROM _vw_regen_fn_deps LOOP
    BEGIN
      EXECUTE rec.definition;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Best-effort restore skipped dependent function %.%: %', rec.schema_name, rec.fn_name, SQLERRM;
    END;
  END LOOP;

  DROP TABLE _vw_regen_deps;
  DROP TABLE _vw_regen_fn_deps;
END $vw_regen$;

DO $if_view_exists$
BEGIN
  IF to_regclass('"__mj_bizappscontracts"."vwContracts"') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Integration";';
  END IF;
END
$if_view_exists$;


DO $if_view_exists$
BEGIN
  IF to_regclass('"__mj_bizappscontracts"."vwContracts"') IS NOT NULL THEN
    EXECUTE 'SELECT "__mj"."spRebindLayeredOuterView"(''__mj_bizappscontracts'', ''vwContracts'', ''vwContractsGenerated'');';
  END IF;
END
$if_view_exists$;


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
-- ============================================================
DO $if_view_exists$
BEGIN
  IF to_regclass('"__mj_bizappscontracts"."vwContracts"') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Integration";';
  END IF;
END
$if_view_exists$;



-- ===================== Hand-written DDL (continued): vwContracts =====================

CREATE VIEW __mj_bizappscontracts."vwContracts"
AS
SELECT
    g.*,
    CASE
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= bt."Today" THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < bt."Today" THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= bt."Today" THEN 'Active'
        WHEN g."ExecutedDate" IS NOT NULL THEN 'Executed'
        ELSE 'Draft'
    END AS "State",
    CASE
        WHEN ct."RequiresExecutedDocument" = TRUE
         AND NOT EXISTS (
                SELECT 1
                  FROM __mj."FileEntityRecordLink" fl
                  JOIN __mj."File" f
                    ON f."ID" = fl."FileID"
                  JOIN __mj."FileCategory" fc
                    ON fc."ID" = f."CategoryID"
                 WHERE fl."EntityID" = (SELECT e."ID" FROM __mj."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts')
                   AND lower(fl."RecordID") = g."ID"::text
                   AND fc."Name" = 'Executed Agreement'
             )
        THEN TRUE ELSE FALSE
    END AS "IsAwaitingDocument",
    CASE WHEN g."EndDate" IS NULL THEN NULL
         ELSE (g."EndDate" - bt."Today") END AS "DaysToEnd",
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE (g."EndDate" - g."RenewalNoticeDays") END AS "RenewalNoticeDeadline",
    CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND bt."Today" >= (g."EndDate" - g."CancellationWindowDays")
         AND bt."Today" <= g."EndDate"
        THEN TRUE ELSE FALSE
    END AS "IsInCancellationWindow",
    CASE WHEN g."EffectiveDate" IS NOT NULL AND g."EndDate" IS NOT NULL THEN (g."EndDate" - g."EffectiveDate") ELSE NULL END AS "TermLengthDays",
    CASE WHEN g."EndDate" IS NOT NULL AND g."RenewalNoticeDays" IS NOT NULL THEN ((g."EndDate" - g."RenewalNoticeDays") - bt."Today") ELSE NULL END AS "DaysUntilNoticeDeadline",
    CASE WHEN g."HasModifications" = TRUE THEN 1 ELSE 0 END AS "HasModificationsFlag",
    CASE WHEN g."AutoRenew" = TRUE THEN 1 ELSE 0 END AS "AutoRenewFlag",
    CASE WHEN g."ParentContractID" IS NOT NULL THEN 1 ELSE 0 END AS "HasParentContract",
    CASE WHEN g."CancellationWindowDays" > 0 THEN 1 ELSE 0 END AS "HasCancellationWindow",
    CASE WHEN g."AnnualIncreasePercent" > 0 THEN 1 ELSE 0 END AS "HasAnnualIncrease"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
CROSS JOIN
    __mj_bizappscommon."fnBusinessToday"() AS bt
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID";

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";

-- ===================== CodeGen (continued): CRUD functions =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: spCreateContract
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR Contract
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContract'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContract"(
    p_id UUID DEFAULT NULL,
    p_contractnumber_clear boolean DEFAULT false,
    p_contractnumber varchar(50) DEFAULT NULL,
    p_contracttypeid UUID DEFAULT NULL,
    p_companyid UUID DEFAULT NULL,
    p_customerorganizationid UUID DEFAULT NULL,
    p_primarycontactpersonid_clear boolean DEFAULT false,
    p_primarycontactpersonid UUID DEFAULT NULL,
    p_contracttemplateid_clear boolean DEFAULT false,
    p_contracttemplateid UUID DEFAULT NULL,
    p_creatingentityid_clear boolean DEFAULT false,
    p_creatingentityid UUID DEFAULT NULL,
    p_creatingrecordid_clear boolean DEFAULT false,
    p_creatingrecordid varchar(450) DEFAULT NULL,
    p_parentcontractid_clear boolean DEFAULT false,
    p_parentcontractid UUID DEFAULT NULL,
    p_supersededbycontractid_clear boolean DEFAULT false,
    p_supersededbycontractid UUID DEFAULT NULL,
    p_signingproviderurl_clear boolean DEFAULT false,
    p_signingproviderurl varchar(1000) DEFAULT NULL,
    p_effectivedate_clear boolean DEFAULT false,
    p_effectivedate date DEFAULT NULL,
    p_executeddate_clear boolean DEFAULT false,
    p_executeddate date DEFAULT NULL,
    p_enddate_clear boolean DEFAULT false,
    p_enddate date DEFAULT NULL,
    p_terminateddate_clear boolean DEFAULT false,
    p_terminateddate date DEFAULT NULL,
    p_autorenew BOOLEAN DEFAULT NULL,
    p_renewalnoticedays_clear boolean DEFAULT false,
    p_renewalnoticedays int DEFAULT NULL,
    p_cancellationwindowdays_clear boolean DEFAULT false,
    p_cancellationwindowdays int DEFAULT NULL,
    p_annualincreasepercent_clear boolean DEFAULT false,
    p_annualincreasepercent decimal(7, 4) DEFAULT NULL,
    p_hasmodifications BOOLEAN DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL,
    p_predictednonrenewalrisk_clear boolean DEFAULT false,
    p_predictednonrenewalrisk decimal(5, 4) DEFAULT NULL,
    p_predictedrenewalriskband_clear boolean DEFAULT false,
    p_predictedrenewalriskband varchar(20) DEFAULT NULL,
    p_predictedrenewalscoredat_clear boolean DEFAULT false,
    p_predictedrenewalscoredat TIMESTAMPTZ DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContracts" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."Contract"
        (
            "ID",
            "ContractNumber",
                "ContractTypeID",
                "CompanyID",
                "CustomerOrganizationID",
                "PrimaryContactPersonID",
                "ContractTemplateID",
                "CreatingEntityID",
                "CreatingRecordID",
                "ParentContractID",
                "SupersededByContractID",
                "SigningProviderURL",
                "EffectiveDate",
                "ExecutedDate",
                "EndDate",
                "TerminatedDate",
                "AutoRenew",
                "RenewalNoticeDays",
                "CancellationWindowDays",
                "AnnualIncreasePercent",
                "HasModifications",
                "Description",
                "Notes",
                "PredictedNonRenewalRisk",
                "PredictedRenewalRiskBand",
                "PredictedRenewalScoredAt"
        )
    VALUES
        (
            v_new_id,
            CASE WHEN p_contractnumber_clear = true THEN NULL ELSE COALESCE(p_contractnumber, NULL) END,
                p_contracttypeid,
                p_companyid,
                p_customerorganizationid,
                CASE WHEN p_primarycontactpersonid_clear = true THEN NULL ELSE COALESCE(p_primarycontactpersonid, NULL) END,
                CASE WHEN p_contracttemplateid_clear = true THEN NULL ELSE COALESCE(p_contracttemplateid, NULL) END,
                CASE WHEN p_creatingentityid_clear = true THEN NULL ELSE COALESCE(p_creatingentityid, NULL) END,
                CASE WHEN p_creatingrecordid_clear = true THEN NULL ELSE COALESCE(p_creatingrecordid, NULL) END,
                CASE WHEN p_parentcontractid_clear = true THEN NULL ELSE COALESCE(p_parentcontractid, NULL) END,
                CASE WHEN p_supersededbycontractid_clear = true THEN NULL ELSE COALESCE(p_supersededbycontractid, NULL) END,
                CASE WHEN p_signingproviderurl_clear = true THEN NULL ELSE COALESCE(p_signingproviderurl, NULL) END,
                CASE WHEN p_effectivedate_clear = true THEN NULL ELSE COALESCE(p_effectivedate, NULL) END,
                CASE WHEN p_executeddate_clear = true THEN NULL ELSE COALESCE(p_executeddate, NULL) END,
                CASE WHEN p_enddate_clear = true THEN NULL ELSE COALESCE(p_enddate, NULL) END,
                CASE WHEN p_terminateddate_clear = true THEN NULL ELSE COALESCE(p_terminateddate, NULL) END,
                COALESCE(p_autorenew, FALSE),
                CASE WHEN p_renewalnoticedays_clear = true THEN NULL ELSE COALESCE(p_renewalnoticedays, NULL) END,
                CASE WHEN p_cancellationwindowdays_clear = true THEN NULL ELSE COALESCE(p_cancellationwindowdays, NULL) END,
                CASE WHEN p_annualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_annualincreasepercent, NULL) END,
                COALESCE(p_hasmodifications, FALSE),
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END,
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END,
                CASE WHEN p_predictednonrenewalrisk_clear = true THEN NULL ELSE COALESCE(p_predictednonrenewalrisk, NULL) END,
                CASE WHEN p_predictedrenewalriskband_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalriskband, NULL) END,
                CASE WHEN p_predictedrenewalscoredat_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalscoredat, NULL) END
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContracts"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: spUpdateContract
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR Contract
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContract'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContract"(
    p_id UUID,
    p_contractnumber_clear boolean DEFAULT false,
    p_contractnumber varchar(50) DEFAULT NULL,
    p_contracttypeid UUID DEFAULT NULL,
    p_companyid UUID DEFAULT NULL,
    p_customerorganizationid UUID DEFAULT NULL,
    p_primarycontactpersonid_clear boolean DEFAULT false,
    p_primarycontactpersonid UUID DEFAULT NULL,
    p_contracttemplateid_clear boolean DEFAULT false,
    p_contracttemplateid UUID DEFAULT NULL,
    p_creatingentityid_clear boolean DEFAULT false,
    p_creatingentityid UUID DEFAULT NULL,
    p_creatingrecordid_clear boolean DEFAULT false,
    p_creatingrecordid varchar(450) DEFAULT NULL,
    p_parentcontractid_clear boolean DEFAULT false,
    p_parentcontractid UUID DEFAULT NULL,
    p_supersededbycontractid_clear boolean DEFAULT false,
    p_supersededbycontractid UUID DEFAULT NULL,
    p_signingproviderurl_clear boolean DEFAULT false,
    p_signingproviderurl varchar(1000) DEFAULT NULL,
    p_effectivedate_clear boolean DEFAULT false,
    p_effectivedate date DEFAULT NULL,
    p_executeddate_clear boolean DEFAULT false,
    p_executeddate date DEFAULT NULL,
    p_enddate_clear boolean DEFAULT false,
    p_enddate date DEFAULT NULL,
    p_terminateddate_clear boolean DEFAULT false,
    p_terminateddate date DEFAULT NULL,
    p_autorenew BOOLEAN DEFAULT NULL,
    p_renewalnoticedays_clear boolean DEFAULT false,
    p_renewalnoticedays int DEFAULT NULL,
    p_cancellationwindowdays_clear boolean DEFAULT false,
    p_cancellationwindowdays int DEFAULT NULL,
    p_annualincreasepercent_clear boolean DEFAULT false,
    p_annualincreasepercent decimal(7, 4) DEFAULT NULL,
    p_hasmodifications BOOLEAN DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL,
    p_predictednonrenewalrisk_clear boolean DEFAULT false,
    p_predictednonrenewalrisk decimal(5, 4) DEFAULT NULL,
    p_predictedrenewalriskband_clear boolean DEFAULT false,
    p_predictedrenewalriskband varchar(20) DEFAULT NULL,
    p_predictedrenewalscoredat_clear boolean DEFAULT false,
    p_predictedrenewalscoredat TIMESTAMPTZ DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContracts" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."Contract"
    SET
        "ContractNumber" = CASE WHEN p_contractnumber_clear = true THEN NULL ELSE COALESCE(p_contractnumber, "ContractNumber") END,
        "ContractTypeID" = COALESCE(p_contracttypeid, "ContractTypeID"),
        "CompanyID" = COALESCE(p_companyid, "CompanyID"),
        "CustomerOrganizationID" = COALESCE(p_customerorganizationid, "CustomerOrganizationID"),
        "PrimaryContactPersonID" = CASE WHEN p_primarycontactpersonid_clear = true THEN NULL ELSE COALESCE(p_primarycontactpersonid, "PrimaryContactPersonID") END,
        "ContractTemplateID" = CASE WHEN p_contracttemplateid_clear = true THEN NULL ELSE COALESCE(p_contracttemplateid, "ContractTemplateID") END,
        "CreatingEntityID" = CASE WHEN p_creatingentityid_clear = true THEN NULL ELSE COALESCE(p_creatingentityid, "CreatingEntityID") END,
        "CreatingRecordID" = CASE WHEN p_creatingrecordid_clear = true THEN NULL ELSE COALESCE(p_creatingrecordid, "CreatingRecordID") END,
        "ParentContractID" = CASE WHEN p_parentcontractid_clear = true THEN NULL ELSE COALESCE(p_parentcontractid, "ParentContractID") END,
        "SupersededByContractID" = CASE WHEN p_supersededbycontractid_clear = true THEN NULL ELSE COALESCE(p_supersededbycontractid, "SupersededByContractID") END,
        "SigningProviderURL" = CASE WHEN p_signingproviderurl_clear = true THEN NULL ELSE COALESCE(p_signingproviderurl, "SigningProviderURL") END,
        "EffectiveDate" = CASE WHEN p_effectivedate_clear = true THEN NULL ELSE COALESCE(p_effectivedate, "EffectiveDate") END,
        "ExecutedDate" = CASE WHEN p_executeddate_clear = true THEN NULL ELSE COALESCE(p_executeddate, "ExecutedDate") END,
        "EndDate" = CASE WHEN p_enddate_clear = true THEN NULL ELSE COALESCE(p_enddate, "EndDate") END,
        "TerminatedDate" = CASE WHEN p_terminateddate_clear = true THEN NULL ELSE COALESCE(p_terminateddate, "TerminatedDate") END,
        "AutoRenew" = COALESCE(p_autorenew, "AutoRenew"),
        "RenewalNoticeDays" = CASE WHEN p_renewalnoticedays_clear = true THEN NULL ELSE COALESCE(p_renewalnoticedays, "RenewalNoticeDays") END,
        "CancellationWindowDays" = CASE WHEN p_cancellationwindowdays_clear = true THEN NULL ELSE COALESCE(p_cancellationwindowdays, "CancellationWindowDays") END,
        "AnnualIncreasePercent" = CASE WHEN p_annualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_annualincreasepercent, "AnnualIncreasePercent") END,
        "HasModifications" = COALESCE(p_hasmodifications, "HasModifications"),
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END,
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END,
        "PredictedNonRenewalRisk" = CASE WHEN p_predictednonrenewalrisk_clear = true THEN NULL ELSE COALESCE(p_predictednonrenewalrisk, "PredictedNonRenewalRisk") END,
        "PredictedRenewalRiskBand" = CASE WHEN p_predictedrenewalriskband_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalriskband, "PredictedRenewalRiskBand") END,
        "PredictedRenewalScoredAt" = CASE WHEN p_predictedrenewalscoredat_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalscoredat, "PredictedRenewalScoredAt") END
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContracts"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the Contract table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract" ON "__mj_bizappscontracts"."Contract";

CREATE TRIGGER "trg_update_contract"
BEFORE UPDATE ON "__mj_bizappscontracts"."Contract"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract"();



-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: spDeleteContract
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR Contract
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContract'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContract"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."Contract"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Integration";


-- ===================== Hand-written DDL (continued): recording the label =====================

CREATE FUNCTION __mj_bizappscontracts."trgContract_RecordNonRenewalOutcome_func"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $trg$
BEGIN
    NEW."NonRenewalOutcome" := __mj_bizappscontracts."fnContractNonRenewalOutcome"(
        NEW."SupersededByContractID", NEW."TerminatedDate", NEW."EndDate",
        (SELECT bt."Today" FROM __mj_bizappscommon."fnBusinessToday"() AS bt));
    RETURN NEW;
END;
$trg$;

CREATE TRIGGER "trgContract_RecordNonRenewalOutcome"
BEFORE INSERT OR UPDATE ON __mj_bizappscontracts."Contract"
FOR EACH ROW EXECUTE FUNCTION __mj_bizappscontracts."trgContract_RecordNonRenewalOutcome_func"();

CREATE FUNCTION __mj_bizappscontracts."spRecordContractNonRenewalOutcomes"()
RETURNS INTEGER
LANGUAGE plpgsql
AS $proc$
DECLARE
    changed INTEGER;
BEGIN
    UPDATE __mj_bizappscontracts."Contract" AS c
       SET "NonRenewalOutcome" = o.outcome
      FROM (SELECT x."ID",
                   __mj_bizappscontracts."fnContractNonRenewalOutcome"(
                       x."SupersededByContractID", x."TerminatedDate", x."EndDate", bt."Today") AS outcome
              FROM __mj_bizappscontracts."Contract" AS x
             CROSS JOIN __mj_bizappscommon."fnBusinessToday"() AS bt) AS o
     WHERE o."ID" = c."ID"
       AND c."NonRenewalOutcome" IS DISTINCT FROM o.outcome;
    GET DIAGNOSTICS changed = ROW_COUNT;
    RETURN changed;
END;
$proc$;

-- Record every existing contract's label.
SELECT __mj_bizappscontracts."spRecordContractNonRenewalOutcomes"();

-- ===================== CodeGen-captured metadata =====================

/* SQL text to update existing entities from schema */
SELECT "__mj"."spUpdateExistingEntitiesFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to update existing entity fields from schema */
SELECT "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to set default column width where needed */
SELECT "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to sync schema info from database schemas */
SELECT "__mj"."spUpdateSchemaInfoFromDatabase"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');
