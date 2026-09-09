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


-- ===================== Views =====================

DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsContracts';
  v_target_name CONSTANT TEXT := 'vwContractTemplatesGenerated';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsContracts."vwContractTemplatesGenerated"
AS SELECT
    c.*,
    "mjBizAppsContractsContractTemplateType_ContractTemplateTypeID"."Name" AS "ContractTemplateType"
FROM
    __mj_BizAppsContracts."ContractTemplate" AS c
INNER JOIN
    __mj_BizAppsContracts."ContractTemplateType" AS "mjBizAppsContractsContractTemplateType_ContractTemplateTypeID"
  ON
    c."ContractTemplateTypeID" = "mjBizAppsContractsContractTemplateType_ContractTemplateTypeID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsContracts';
  v_target_name CONSTANT TEXT := 'vwContractTemplateModifications';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsContracts."vwContractTemplateModifications"
AS SELECT
    c.*,
    "mjBizAppsContractsContract_ContractID"."ContractNumber" AS "Contract",
    "mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID"."ProvisionNumber" AS "ContractTemplateProvision"
FROM
    __mj_BizAppsContracts."ContractTemplateModification" AS c
INNER JOIN
    __mj_BizAppsContracts."Contract" AS "mjBizAppsContractsContract_ContractID"
  ON
    c."ContractID" = "mjBizAppsContractsContract_ContractID"."ID"
INNER JOIN
    __mj_BizAppsContracts."ContractTemplateProvision" AS "mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID"
  ON
    c."ContractTemplateProvisionID" = "mjBizAppsContractsContractTemplateProvision_ContractTemplateProvisionID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;

DO $do$
DECLARE
  v_target_schema CONSTANT TEXT := '__mj_BizAppsContracts';
  v_target_name CONSTANT TEXT := 'vwContractsGenerated';
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_BizAppsContracts."vwContractsGenerated"
AS SELECT
    c.*,
    "mjBizAppsContractsContractType_ContractTypeID"."Name" AS "ContractType",
    "MJCompany_CompanyID"."Name" AS "Company",
    "mjBizAppsCommonOrganization_CustomerOrganizationID"."Name" AS "CustomerOrganization",
    "mjBizAppsCommonPerson_PrimaryContactPersonID"."FirstName" AS "PrimaryContactPerson",
    "mjBizAppsContractsContractTemplate_ContractTemplateID"."Name" AS "ContractTemplate",
    "MJEntity_CreatingEntityID"."Name" AS "CreatingEntity",
    "mjBizAppsContractsContract_ParentContractID"."ContractNumber" AS "ParentContract",
    "mjBizAppsContractsContract_SupersededByContractID"."ContractNumber" AS "SupersededByContract"
FROM
    __mj_BizAppsContracts."Contract" AS c
INNER JOIN
    __mj_BizAppsContracts."ContractType" AS "mjBizAppsContractsContractType_ContractTypeID"
  ON
    c."ContractTypeID" = "mjBizAppsContractsContractType_ContractTypeID"."ID"
INNER JOIN
    ${mjSchema}."Company" AS "MJCompany_CompanyID"
  ON
    c."CompanyID" = "MJCompany_CompanyID"."ID"
INNER JOIN
    ${mjSchema}_BizAppsCommon."Organization" AS "mjBizAppsCommonOrganization_CustomerOrganizationID"
  ON
    c."CustomerOrganizationID" = "mjBizAppsCommonOrganization_CustomerOrganizationID"."ID"
LEFT OUTER JOIN
    ${mjSchema}_BizAppsCommon."Person" AS "mjBizAppsCommonPerson_PrimaryContactPersonID"
  ON
    c."PrimaryContactPersonID" = "mjBizAppsCommonPerson_PrimaryContactPersonID"."ID"
LEFT OUTER JOIN
    __mj_BizAppsContracts."ContractTemplate" AS "mjBizAppsContractsContractTemplate_ContractTemplateID"
  ON
    c."ContractTemplateID" = "mjBizAppsContractsContractTemplate_ContractTemplateID"."ID"
LEFT OUTER JOIN
    ${mjSchema}."Entity" AS "MJEntity_CreatingEntityID"
  ON
    c."CreatingEntityID" = "MJEntity_CreatingEntityID"."ID"
LEFT OUTER JOIN
    __mj_BizAppsContracts."Contract" AS "mjBizAppsContractsContract_ParentContractID"
  ON
    c."ParentContractID" = "mjBizAppsContractsContract_ParentContractID"."ID"
LEFT OUTER JOIN
    __mj_BizAppsContracts."Contract" AS "mjBizAppsContractsContract_SupersededByContractID"
  ON
    c."SupersededByContractID" = "mjBizAppsContractsContract_SupersededByContractID"."ID"$vsql$;
  v_target_oid OID;
  v_dep RECORD;
  v_captured JSONB[] := ARRAY[]::JSONB[];
  v_n INTEGER;
BEGIN
  EXECUTE vsql;
EXCEPTION WHEN invalid_table_definition THEN
  -- Column list changed; need CASCADE. Preserve dependent views first.
  SELECT c.oid INTO v_target_oid
  FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = v_target_schema AND c.relname = v_target_name AND c.relkind = 'v';
  IF v_target_oid IS NOT NULL THEN
    FOR v_dep IN
      WITH RECURSIVE deps AS (
        SELECT c.oid, c.relname AS name, n.nspname AS schema, 1 AS depth
        FROM pg_rewrite r
        JOIN pg_depend d ON d.objid = r.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE d.refobjid = v_target_oid AND d.deptype = 'n'
          AND c.oid <> v_target_oid AND c.relkind = 'v'
        UNION
        SELECT c.oid, c.relname, n.nspname, p.depth + 1
        FROM deps p
        JOIN pg_rewrite r ON TRUE
        JOIN pg_depend d ON d.objid = r.oid AND d.refobjid = p.oid
        JOIN pg_class c ON c.oid = r.ev_class
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relkind = 'v' AND c.oid <> p.oid
      )
      SELECT oid, name, schema, MAX(depth) AS max_depth,
             pg_catalog.pg_get_viewdef(oid, true) AS viewdef
      FROM deps GROUP BY oid, name, schema
      ORDER BY MAX(depth) ASC
    LOOP
      v_captured := v_captured || jsonb_build_object(
        'schema', v_dep.schema, 'name', v_dep.name, 'def', v_dep.viewdef);
    END LOOP;
  END IF;
  EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', v_target_schema, v_target_name);
  EXECUTE vsql;
  IF v_captured IS NOT NULL AND array_length(v_captured, 1) > 0 THEN
    FOR v_n IN 1..array_length(v_captured, 1) LOOP
      BEGIN
        EXECUTE format('CREATE VIEW %I.%I AS %s',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', v_captured[v_n]->>'def');
      EXCEPTION WHEN others THEN
        RAISE WARNING 'Could not restore dependent view %.%: %',
          v_captured[v_n]->>'schema', v_captured[v_n]->>'name', SQLERRM;
      END;
    END LOOP;
  END IF;
END;
$do$;


-- ===================== Stored Procedures (sp*) =====================

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsContracts].[spCreateContractTemplateModification]
--     @ID UUID = NULL,
--     @ContractID UUID,
--     @ContractTemplateProvisionID UUID,
--   ...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsContracts].[spUpdateContractTemplateModification]
--     @ID UUID,
--     @ContractID UUID = NULL,
--     @ContractTemplateProvisionID UUID = N...

-- SKIPPED: procedure (auto-conversion not supported)
-- CREATE PROCEDURE [__mj_BizAppsContracts].[spDeleteContractTemplateModification]
--     @ID UUID
-- AS
-- BEGIN
--     SET NOCOUNT ON;
-- 
--     DELETE FROM
--         [__mj_BizAppsContracts].[ContractTemplate...


-- ===================== Triggers =====================

-- SKIPPED: trigger (auto-conversion not supported)
-- CREATE TRIGGER [__mj_BizAppsContracts].trgUpdateContractTemplateModification
ON "__mj_BizAppsContracts"."ContractTemplateModification"
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [__m


-- ===================== Data (INSERT/UPDATE/DELETE) =====================

-- =============================================================================
-- V202608240100 — the two layered base views: hand CodeGen a PRIVATE name.
-- =============================================================================
-- Contracts and Contract Templates use MJ's layered base views (MJ#3419): CodeGen
-- owns a generated inner view under GeneratedBaseViewName, and the APPLICATION owns
-- the public BaseView as a thin wrapper adding derived columns. This file sets the
-- flags and carries the regenerated inner views; the NEXT file creates the wrappers.
--
-- WHY THIS IS NOT IN THE BASELINE, given that everything else was folded into it.
-- The layering is a SEQUENCE, not a state, and the ordering is forced twice over:
--
--   1. The flags live on __mj.Entity rows that DO NOT EXIST until the baseline's own
--      CodeGen capture inserts them. An UPDATE placed anywhere in the baseline is a
--      no-op against a row that is not there yet.
--   2. A wrapper view cannot be created before the view it selects FROM. SQL Server
--      has deferred name resolution for procedure bodies but NOT for views, so the
--      generated inner view has to exist first — which is why the wrappers are a
--      third file rather than the tail of this one.
--
-- WHY THE FLAGS SHIP AS A MIGRATION AT ALL, rather than only in metadata/entities/.
-- A fresh environment runs migrate -> codegen -> sync push. That FIRST codegen, seeing
-- BaseViewGenerated = 1, resolves its target to the PUBLIC name and DROP/CREATEs
-- vwContracts as a plain generated view — silently destroying the wrapper. Shipping the
-- flags here means every environment that migrates has them before any codegen can run.
--
-- Keyed by entity NAME, never by ID: entity IDs are minted at first registration, so a
-- hardcoded UUID stops matching the first time a database is rebuilt from zero. Both
-- UPDATEs skip cleanly when the row is absent.
--
-- ⚠ THE CAPTURE BELOW EXISTS BECAUSE CODEGEN'S LOG AND ITS EXECUTION DISAGREE. CodeGen
-- writes an object to its SQL output only for entities it considers MODIFIED, and
-- flipping BaseViewGenerated does not count as a modification — but it still CREATEs
-- vwContractsGenerated / vwContractTemplatesGenerated in the database it is pointed at.
-- So a plain post-flag codegen run produces a capture with the two generated views
-- MISSING, and the omission is invisible until a fresh install reaches the wrapper and
-- fails on an object nothing ever created. The capture below was taken with
-- forceRegeneration.baseViews scoped to these two entities, which is what makes it
-- complete. If you ever re-capture this file, force base-view regeneration or check by
-- name that both *Generated views are present.
-- =============================================================================

UPDATE ${mjSchema}."Entity"
   SET "BaseViewGenerated" = FALSE,
       "GeneratedBaseViewName" = 'vwContractsGenerated'
 WHERE "Name" = 'MJ_BizApps_Contracts: Contracts'
   AND ("BaseViewGenerated" <> FALSE
        OR "GeneratedBaseViewName" IS NULL
        OR "GeneratedBaseViewName" <> 'vwContractsGenerated');

UPDATE ${mjSchema}."Entity"
   SET "BaseViewGenerated" = FALSE,
       "GeneratedBaseViewName" = 'vwContractTemplatesGenerated'
 WHERE "Name" = 'MJ_BizApps_Contracts: Contract Templates'
   AND ("BaseViewGenerated" <> FALSE
        OR "GeneratedBaseViewName" IS NULL
        OR "GeneratedBaseViewName" <> 'vwContractTemplatesGenerated');

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '98336d4e-6f80-4f25-bfec-827d94128191' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'Contract')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '98336d4e-6f80-4f25-bfec-827d94128191',
        'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- "Entity": "MJ_BizApps_Contracts": "Contract" "Template" "Modifications"
        (SELECT COALESCE(MAX("Sequence"), 0) FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 8,
        'Contract',
        'Contract',
        NULL,
        'TEXT',
        100,
        0,
        0,
        1,
        NULL,
        0,
        0,
        1,
        0,
        NULL,
        NULL,
        0,
        0,
        0,
        0,
        0,
        0,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM ${mjSchema}."EntityField" WHERE "ID" = '9c030856-2774-4c96-801f-e31e5f76edbb' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ContractTemplateProvision')
    ) THEN
        INSERT INTO ${mjSchema}."EntityField"
        (
        "ID",
        "EntityID",
        "Sequence",
        "Name",
        "DisplayName",
        "Description",
        "Type",
        "Length",
        "Precision",
        "Scale",
        "AllowsNull",
        "DefaultValue",
        "AutoIncrement",
        "AllowUpdateAPI",
        "IsVirtual",
        "IsComputed",
        "RelatedEntityID",
        "RelatedEntityFieldName",
        "IsNameField",
        "IncludeInUserSearchAPI",
        "IncludeRelatedEntityNameFieldInBaseView",
        "DefaultInView",
        "IsPrimaryKey",
        "IsUnique",
        "RelatedEntityDisplayType",
        "__mj_CreatedAt",
        "__mj_UpdatedAt"
        )
        VALUES
        (
        '9c030856-2774-4c96-801f-e31e5f76edbb',
        'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', -- "Entity": "MJ_BizApps_Contracts": "Contract" "Template" "Modifications"
        (SELECT COALESCE(MAX("Sequence"), 0) FROM ${mjSchema}."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 9,
        'ContractTemplateProvision',
        'Contract Template Provision',
        NULL,
        'TEXT',
        40,
        0,
        0,
        0,
        NULL,
        0,
        0,
        1,
        0,
        NULL,
        NULL,
        0,
        0,
        0,
        0,
        0,
        0,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;


-- ===================== Grants =====================

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsContracts."vwContractTemplateModifications" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Permissions for vwContractTemplateModifications
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

DO $$ BEGIN GRANT SELECT ON __mj_BizAppsContracts."vwContractTemplateModifications" TO "cdp_UI", "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spCreateContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spCreateContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spCreate Permissions for MJ_BizApps_Contracts: Contract Template Modifications */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spCreateContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spUpdate SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spUpdateContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spUpdateContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spUpdateContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete SQL for MJ_BizApps_Contracts: Contract Template Modifications */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spDeleteContractTemplateModification
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------;

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spDeleteContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* spDelete Permissions for MJ_BizApps_Contracts: Contract Template Modifications */

DO $$ BEGIN GRANT EXECUTE ON FUNCTION __mj_BizAppsContracts."spDeleteContractTemplateModification" TO "cdp_Developer", "cdp_Integration"; EXCEPTION WHEN others THEN NULL; END $$;
/* Base View SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: vwContractsGenerated
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contracts
-----               SCHEMA:      __mj_BizAppsContracts
-----               BASE TABLE:  Contract
-----               PRIMARY KEY: ID
------------------------------------------------------------;


-- ===================== Other =====================

/* SQL text to update existing entities from schema */

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Template Modifications */
