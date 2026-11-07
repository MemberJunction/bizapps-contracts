-- =============================================================================
-- PostgreSQL counterpart of V202610122200__v0.8.x__ContractType_Code.sql
-- A stable Code on ContractType (issue #96)
-- =============================================================================
-- Same change as the T-SQL file; see its header for why Code exists, why it
-- takes four statements, and how existing rows get their code.
--
-- HOW IT WAS MADE: `mj migrate convert --split --bake-codegen` (MJ CLI 6.1.6)
-- against a PostgreSQL 17 database built from migrations only: MJ core v6.1.6,
-- bizapps-common and bizapps-tasks `migrations-pg` from main, this app's
-- baseline (B202609211300) and the three v0.8.x files before this one.
--   * Hand-written DDL: the transpiler's output, with the T-SQL header it had
--     folded into the ADD COLUMN removed, and the NOT NULL step stated as
--     SET NOT NULL (the column's type does not change).
--   * CodeGen objects (vwContractTypes, vwContractsGenerated, the six CRUD
--     functions, update triggers, FK indexes, grants): native PostgreSQL CodeGen
--     output from the bake. One grant block on vwContracts came out wrapped twice
--     in the same $if_view_exists$ tag (MemberJunction/MJ#5552); it is unwrapped
--     here, as in the baseline.
--   * CodeGen-captured metadata: the baker keeps the EntityField insert and
--     drops the rest (MemberJunction/MJ#5550), so the rest is written from the
--     T-SQL capture: the schema-refresh calls (PostgreSQL's take the excluded
--     schemas only, as in the baseline), the Code field's properties and
--     category, and the three Contract Type validators, whose code and source
--     strings are copied verbatim.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;

-- ===================== Hand-written DDL (transpiled) =====================

ALTER TABLE __mj_bizappscontracts."ContractType"
ADD COLUMN "Code" VARCHAR(50) NULL;

UPDATE __mj_bizappscontracts."ContractType" SET "Code" = 'ORDER_FORM'
WHERE
  "ID" = '33333333-0000-4000-8000-000000001001';
UPDATE __mj_bizappscontracts."ContractType" SET "Code" = 'STATEMENT_OF_WORK'
WHERE
  "ID" = '33333333-0000-4000-8000-000000001002';
UPDATE __mj_bizappscontracts."ContractType" SET "Code" = 'PAYMENT_LINK'
WHERE
  "ID" = '33333333-0000-4000-8000-000000001003';
UPDATE __mj_bizappscontracts."ContractType" SET "Code" = 'CHANGE_ORDER'
WHERE
  "ID" = '33333333-0000-4000-8000-000000001004';
UPDATE __mj_bizappscontracts."ContractType" SET "Code" = LEFT(CAST(UPPER(REPLACE(LTRIM(RTRIM("Name")), ' ', '_')) AS TEXT), 50)
WHERE
  "Code" IS NULL;

ALTER TABLE __mj_bizappscontracts."ContractType" ALTER COLUMN "Code" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractType"
ADD CONSTRAINT "UQ_ContractType_Code" UNIQUE (
  "Code"
);

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."Code" IS 'Stable machine code other apps and metadata use to find this type (for example ORDER_FORM). Unique. Unlike Name, it is not a label: renaming the type leaves the Code alone, and changing the Code breaks every caller that names it.';

-- ===================== CodeGen-captured metadata =====================

/* SQL text to update existing entities from schema */
SELECT "__mj"."spUpdateExistingEntitiesFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to insert 1 new entity field(s) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '46976b91-ef82-4d60-a6ec-bf645ec8d56f' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'Code')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('46976b91-ef82-4d60-a6ec-bf645ec8d56f', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'Code', 'Code', 'Stable machine code other apps and metadata use to find this type (for example ORDER_FORM). Unique. Unlike Name, it is not a label: renaming the type leaves the Code alone, and changing the Code breaks every caller that names it.', 'nvarchar', 100, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* SQL text to update existing entity fields from schema */
SELECT "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to set default column width where needed */
SELECT "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to sync schema info from database schemas */
SELECT "__mj"."spUpdateSchemaInfoFromDatabase"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

-- ===================== CodeGen (native PG, baked) =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Index for Foreign Keys
-- ============================================================


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: vwContractTypes
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Types
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractType
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTypes"
AS
SELECT
    c.*
FROM
    "__mj_bizappscontracts"."ContractType" AS c
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
    AND tc.relname = 'vwContractTypes'
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
    AND tc.relname = 'vwContractTypes'
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
        AND tc.relname = 'vwContractTypes'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTypes" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spCreateContractType
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractType"(
    p_id UUID DEFAULT NULL,
    p_name varchar(100) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_requiresexecuteddocument BOOLEAN DEFAULT NULL,
    p_status varchar(10) DEFAULT NULL,
    p_mustberoot BOOLEAN DEFAULT NULL,
    p_mustbechild BOOLEAN DEFAULT NULL,
    p_templaterequired BOOLEAN DEFAULT NULL,
    p_defaultautorenew_clear boolean DEFAULT false,
    p_defaultautorenew BOOLEAN DEFAULT NULL,
    p_defaultrenewalnoticedays_clear boolean DEFAULT false,
    p_defaultrenewalnoticedays int DEFAULT NULL,
    p_defaultcancellationwindowdays_clear boolean DEFAULT false,
    p_defaultcancellationwindowdays int DEFAULT NULL,
    p_defaultannualincreasepercent_clear boolean DEFAULT false,
    p_defaultannualincreasepercent decimal(7, 4) DEFAULT NULL,
    p_code varchar(50) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTypes" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractType"
        (
            "ID",
            "Name",
                "Description",
                "RequiresExecutedDocument",
                "Status",
                "MustBeRoot",
                "MustBeChild",
                "TemplateRequired",
                "DefaultAutoRenew",
                "DefaultRenewalNoticeDays",
                "DefaultCancellationWindowDays",
                "DefaultAnnualIncreasePercent",
                "Code"
        )
    VALUES
        (
            v_new_id,
            p_name,
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END,
                COALESCE(p_requiresexecuteddocument, TRUE),
                COALESCE(p_status, 'Active'),
                COALESCE(p_mustberoot, FALSE),
                COALESCE(p_mustbechild, FALSE),
                COALESCE(p_templaterequired, FALSE),
                CASE WHEN p_defaultautorenew_clear = true THEN NULL ELSE COALESCE(p_defaultautorenew, NULL) END,
                CASE WHEN p_defaultrenewalnoticedays_clear = true THEN NULL ELSE COALESCE(p_defaultrenewalnoticedays, NULL) END,
                CASE WHEN p_defaultcancellationwindowdays_clear = true THEN NULL ELSE COALESCE(p_defaultcancellationwindowdays, NULL) END,
                CASE WHEN p_defaultannualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_defaultannualincreasepercent, NULL) END,
                p_code
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTypes"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractType" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spUpdateContractType
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractType"(
    p_id UUID,
    p_name varchar(100) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_requiresexecuteddocument BOOLEAN DEFAULT NULL,
    p_status varchar(10) DEFAULT NULL,
    p_mustberoot BOOLEAN DEFAULT NULL,
    p_mustbechild BOOLEAN DEFAULT NULL,
    p_templaterequired BOOLEAN DEFAULT NULL,
    p_defaultautorenew_clear boolean DEFAULT false,
    p_defaultautorenew BOOLEAN DEFAULT NULL,
    p_defaultrenewalnoticedays_clear boolean DEFAULT false,
    p_defaultrenewalnoticedays int DEFAULT NULL,
    p_defaultcancellationwindowdays_clear boolean DEFAULT false,
    p_defaultcancellationwindowdays int DEFAULT NULL,
    p_defaultannualincreasepercent_clear boolean DEFAULT false,
    p_defaultannualincreasepercent decimal(7, 4) DEFAULT NULL,
    p_code varchar(50) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTypes" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractType"
    SET
        "Name" = COALESCE(p_name, "Name"),
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END,
        "RequiresExecutedDocument" = COALESCE(p_requiresexecuteddocument, "RequiresExecutedDocument"),
        "Status" = COALESCE(p_status, "Status"),
        "MustBeRoot" = COALESCE(p_mustberoot, "MustBeRoot"),
        "MustBeChild" = COALESCE(p_mustbechild, "MustBeChild"),
        "TemplateRequired" = COALESCE(p_templaterequired, "TemplateRequired"),
        "DefaultAutoRenew" = CASE WHEN p_defaultautorenew_clear = true THEN NULL ELSE COALESCE(p_defaultautorenew, "DefaultAutoRenew") END,
        "DefaultRenewalNoticeDays" = CASE WHEN p_defaultrenewalnoticedays_clear = true THEN NULL ELSE COALESCE(p_defaultrenewalnoticedays, "DefaultRenewalNoticeDays") END,
        "DefaultCancellationWindowDays" = CASE WHEN p_defaultcancellationwindowdays_clear = true THEN NULL ELSE COALESCE(p_defaultcancellationwindowdays, "DefaultCancellationWindowDays") END,
        "DefaultAnnualIncreasePercent" = CASE WHEN p_defaultannualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_defaultannualincreasepercent, "DefaultAnnualIncreasePercent") END,
        "Code" = COALESCE(p_code, "Code")
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTypes"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractType" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractType table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_type"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_type" ON "__mj_bizappscontracts"."ContractType";

CREATE TRIGGER "trg_update_contract_type"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractType"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_type"();



-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spDeleteContractType
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractType"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractType"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractType" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_contract_type_id"
    ON "__mj_bizappscontracts"."Contract" ("ContractTypeID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_company_id"
    ON "__mj_bizappscontracts"."Contract" ("CompanyID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_customer_organization_id"
    ON "__mj_bizappscontracts"."Contract" ("CustomerOrganizationID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_primary_contact_person_id"
    ON "__mj_bizappscontracts"."Contract" ("PrimaryContactPersonID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_contract_template_id"
    ON "__mj_bizappscontracts"."Contract" ("ContractTemplateID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_creating_entity_id"
    ON "__mj_bizappscontracts"."Contract" ("CreatingEntityID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_parent_contract_id"
    ON "__mj_bizappscontracts"."Contract" ("ParentContractID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_superseded_by_contract_id"
    ON "__mj_bizappscontracts"."Contract" ("SupersededByContractID");

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

-- ===================== CodeGen-captured metadata (after the objects) =====================

/* SQL text to update existing entity fields from schema (1 scoped entities) */
SELECT "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks', 'C8909A57-6DDB-4585-BE00-E707C5B4F262');

/* SQL text to set default column width where needed */
SELECT "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* Set field properties for entity */
UPDATE __mj."EntityField"
   SET "DefaultInView" = TRUE
 WHERE "ID" = '46976B91-EF82-4D60-A6EC-BF645EC8D56F'
   AND "AutoUpdateDefaultInView" = TRUE;

/* Set categories for 1 fields */
-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.Code
UPDATE __mj."EntityField"
   SET "Category" = 'Contract Type Details',
       "GeneratedFormSection" = 'Category',
       "ExtendedType" = 'Code',
       "CodeType" = 'Other'
 WHERE "ID" = '46976B91-EF82-4D60-A6EC-BF645EC8D56F';

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Types */
-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultAnnualIncreasePercent was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM __mj."GeneratedCode" WHERE "CategoryID" = (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators') AND "LinkedEntityID" = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND "LinkedRecordPrimaryKey" = 'DA53B111-BC39-49F6-BCFB-55380E260227'
  ) THEN
    INSERT INTO __mj."GeneratedCode" ("ID", "CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
VALUES ('848f22bb-fe03-48f9-985e-0bad97f30306', (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([DefaultAnnualIncreasePercent] IS NULL OR [DefaultAnnualIncreasePercent]>=(0))', 'public ValidateDefaultAnnualIncreasePercentGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.DefaultAnnualIncreasePercent != null && this.DefaultAnnualIncreasePercent < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultAnnualIncreasePercent",
			"Default annual increase percentage must be greater than or equal to 0.",
			this.DefaultAnnualIncreasePercent,
			ValidationErrorType.Failure
		));
	}
}', 'Default annual increase percentage must be zero or greater.', 'ValidateDefaultAnnualIncreasePercentGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'DA53B111-BC39-49F6-BCFB-55380E260227');
  END IF;
END $$;

-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultCancellationWindowDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM __mj."GeneratedCode" WHERE "CategoryID" = (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators') AND "LinkedEntityID" = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND "LinkedRecordPrimaryKey" = '111CFB1B-1EFB-4E60-A79D-41A391EF596A'
  ) THEN
    INSERT INTO __mj."GeneratedCode" ("ID", "CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
VALUES ('0f9d1a44-b851-4991-a1a9-a9de8fb6e037', (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([DefaultCancellationWindowDays] IS NULL OR [DefaultCancellationWindowDays]>=(0))', 'public ValidateDefaultCancellationWindowDaysGreaterOrEqualToZero(result: ValidationResult) {
	if (this.DefaultCancellationWindowDays != null && this.DefaultCancellationWindowDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultCancellationWindowDays",
			"Default cancellation window days must be greater than or equal to 0.",
			this.DefaultCancellationWindowDays,
			ValidationErrorType.Failure
		));
	}
}', 'Default cancellation window days must be zero or a positive number if provided.', 'ValidateDefaultCancellationWindowDaysGreaterOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '111CFB1B-1EFB-4E60-A79D-41A391EF596A');
  END IF;
END $$;

-- CHECK constraint for MJ_BizApps_Contracts: Contract Types: Field: DefaultRenewalNoticeDays was newly set or modified since the last generation of the validation function, the code was regenerated and updating the GeneratedCode table with the new generated validation function
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM __mj."GeneratedCode" WHERE "CategoryID" = (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators') AND "LinkedEntityID" = 'DF238F34-2837-EF11-86D4-6045BDEE16E6' AND "LinkedRecordPrimaryKey" = 'E9A6CB34-2B1C-44A9-8260-D7E14C7B1F49'
  ) THEN
    INSERT INTO __mj."GeneratedCode" ("ID", "CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
VALUES ('ff7c8bda-1103-42b6-bc10-774df0a49116', (SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([DefaultRenewalNoticeDays] IS NULL OR [DefaultRenewalNoticeDays]>=(0))', 'public ValidateDefaultRenewalNoticeDaysMin(result: ValidationResult) {
	if (this.DefaultRenewalNoticeDays != null && this.DefaultRenewalNoticeDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"DefaultRenewalNoticeDays",
			"Default renewal notice days must be greater than or equal to 0.",
			this.DefaultRenewalNoticeDays,
			ValidationErrorType.Failure
		));
	}
}', 'Default renewal notice days cannot be negative if specified.', 'ValidateDefaultRenewalNoticeDaysMin', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'E9A6CB34-2B1C-44A9-8260-D7E14C7B1F49');
  END IF;
END $$;
