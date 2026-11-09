-- =============================================================================
-- PostgreSQL counterpart of V202611021400__v0.10.x__Contract_template_id_description_and_type_template.sql
-- Contract.ContractTemplateID description (#137) and ContractType.ContractTemplateTypeID (#114).
-- =============================================================================
-- Same change as the T-SQL file; see its header for why Contract.ContractTemplateID's
-- description was corrected and how ContractType.ContractTemplateTypeID associates
-- each template-requiring contract type with its default ContractTemplateType.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;

-- ===================== Hand-written DDL (transpiled) =====================

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."ContractTemplateID" IS 'The agreement version this contract incorporates. Nullable because contract types with TemplateRequired = 0 (such as Change Order and Statement of Work) carry no standard agreement version of their own, and because a newly created contract leaves this empty when no Published, usable template exists yet.';

ALTER TABLE __mj_bizappscontracts."ContractType"
ADD COLUMN "ContractTemplateTypeID" UUID NULL
  CONSTRAINT "FK_ContractType_ContractTemplateType"
  REFERENCES __mj_bizappscontracts."ContractTemplateType"("ID");

UPDATE __mj_bizappscontracts."ContractType"
SET "ContractTemplateTypeID" = '33333333-0000-4000-8000-000000002001'
WHERE "ID" IN ('33333333-0000-4000-8000-000000001001', '33333333-0000-4000-8000-000000001003');

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."ContractTemplateTypeID" IS 'Which kind of standard agreement (ContractTemplateType) a contract of this type incorporates by default when TemplateRequired = 1. Nullable because types with TemplateRequired = 0 carry no template, and a type that leaves this NULL falls back to the newest Published, usable template across all template types.';

-- ===================== CodeGen-captured metadata =====================

/* SQL text to update existing entities from schema */
SELECT "__mj"."spUpdateExistingEntitiesFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to insert 1 new entity field(s) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '8a4c5e92-3b71-4d08-9f16-2e65d093c410' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'ContractTemplateTypeID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('8a4c5e92-3b71-4d08-9f16-2e65d093c410', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'ContractTemplateTypeID', 'Contract Template Type ID', 'Which kind of standard agreement (ContractTemplateType) a contract of this type incorporates by default when TemplateRequired = 1. Nullable because types with TemplateRequired = 0 carry no template, and a type that leaves this NULL falls back to the newest Published, usable template across all template types.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* SQL text to create Entity Relationship: MJ_BizApps_Contracts: Contract Template Types -> MJ_BizApps_Contracts: Contract Types (One To Many via ContractTemplateTypeID) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'd947b1e3-5c82-4a6f-9214-7e03f8a6b512') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d947b1e3-5c82-4a6f-9214-7e03f8a6b512', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'ContractTemplateTypeID', 'One To Many', TRUE, TRUE, 2, NOW(), NOW());
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
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_type_contract_template_type_id"
    ON "__mj_bizappscontracts"."ContractType" ("ContractTemplateTypeID");

/* SQL text to update entity field related entity name field map for entity field ID 8a4c5e92-3b71-4d08-9f16-2e65d093c410 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => '8a4c5e92-3b71-4d08-9f16-2e65d093c410', p_RelatedEntityNameFieldMap => 'ContractTemplateType');

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
    c.*,
    mjbizappscontractsContractTemplateType_ContractTemplateTypeID."Name" AS "ContractTemplateType"
FROM
    "__mj_bizappscontracts"."ContractType" AS c
LEFT OUTER JOIN
    "__mj_bizappscontracts"."ContractTemplateType" AS mjbizappscontractsContractTemplateType_ContractTemplateTypeID
  ON
    "c"."ContractTemplateTypeID" = mjbizappscontractsContractTemplateType_ContractTemplateTypeID."ID"
$vsql$;
  rec RECORD;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  CREATE TEMP TABLE IF NOT EXISTS _vw_regen_deps (
    schema_name TEXT,
    view_name   TEXT,
    relkind     CHAR(1),
    definition  TEXT,
    grants_sql  TEXT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_deps;

  CREATE TEMP TABLE IF NOT EXISTS _vw_regen_fn_deps (
    schema_name TEXT,
    fn_name     TEXT,
    fn_oid      OID,
    definition  TEXT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_fn_deps;

  INSERT INTO _vw_regen_deps (schema_name, view_name, relkind, definition, grants_sql)
  SELECT DISTINCT
      dn.nspname,
      dc.relname,
      dc.relkind,
      pg_get_viewdef(dc.oid),
      (SELECT string_agg(
          'GRANT ' || g.privilege || ' ON ' || quote_ident(dn.nspname) || '.' || quote_ident(dc.relname) ||
          ' TO ' || (CASE WHEN g.grantee_oid = 0 THEN 'PUBLIC' ELSE quote_ident(pg_get_userbyid(g.grantee_oid)) END) || ';',
          E'\n')
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
    p_code varchar(50) DEFAULT NULL,
    p_contracttemplatetypeid_clear boolean DEFAULT false,
    p_contracttemplatetypeid UUID DEFAULT NULL
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
                "Code",
                "ContractTemplateTypeID"
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
                p_code,
                CASE WHEN p_contracttemplatetypeid_clear = true THEN NULL ELSE COALESCE(p_contracttemplatetypeid, NULL) END
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
    p_code varchar(50) DEFAULT NULL,
    p_contracttemplatetypeid_clear boolean DEFAULT false,
    p_contracttemplatetypeid UUID DEFAULT NULL
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
        "Code" = COALESCE(p_code, "Code"),
        "ContractTemplateTypeID" = CASE WHEN p_contracttemplatetypeid_clear = true THEN NULL ELSE COALESCE(p_contracttemplatetypeid, "ContractTemplateTypeID") END
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

-- ===================== CodeGen-captured metadata (after the objects) =====================

/* SQL text to insert virtual entity field for joined ContractTemplateType name */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'c2f14d80-6a35-491e-84c7-5b90e374a821' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'ContractTemplateType')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('c2f14d80-6a35-491e-84c7-5b90e374a821', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'ContractTemplateType', 'Contract Template Type', NULL, 'nvarchar', 200, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* SQL text to update existing entity fields from schema (2 scoped entities) */
SELECT "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks', 'C8909A57-6DDB-4585-BE00-E707C5B4F262,5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

/* Sync Contract.ContractTemplateID EntityField description with MS_Description (#137) */
UPDATE __mj."EntityField"
   SET "Description" = 'The agreement version this contract incorporates. Nullable because contract types with TemplateRequired = 0 (such as Change Order and Statement of Work) carry no standard agreement version of their own, and because a newly created contract leaves this empty when no Published, usable template exists yet.'
 WHERE "ID" = 'B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA'
   AND "AutoUpdateDescription" = TRUE;

/* SQL text to set default column width where needed */
SELECT "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* Set categories for 2 fields */
-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ContractTemplateTypeID
UPDATE __mj."EntityField"
   SET "Category" = 'Configuration Rules',
       "GeneratedFormSection" = 'Category',
       "DisplayName" = 'Default Template Type',
       "ExtendedType" = NULL,
       "CodeType" = NULL
 WHERE "ID" = '8A4C5E92-3B71-4D08-9F16-2E65D093C410'
   AND "AutoUpdateCategory" = TRUE;

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contract Types.ContractTemplateType
UPDATE __mj."EntityField"
   SET "Category" = 'Configuration Rules',
       "GeneratedFormSection" = 'Category',
       "DisplayName" = 'Default Template Type Name',
       "ExtendedType" = NULL,
       "CodeType" = NULL
 WHERE "ID" = 'C2F14D80-6A35-491E-84C7-5B90E374A821'
   AND "AutoUpdateCategory" = TRUE;
