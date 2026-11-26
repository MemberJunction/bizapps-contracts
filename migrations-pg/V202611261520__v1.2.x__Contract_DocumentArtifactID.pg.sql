-- @mj-pg-provenance: split-bake v1 source=V202611261520__v1.2.x__Contract_DocumentArtifactID.sql source-sha256=195bb0f4cbacae9f2ceeba0d63e7a5560999f48971a9345c833fe52304c11c62 mode=needs-hand-rebaked
-- ============================================================================
-- MemberJunction PostgreSQL Migration — V202611261520__v1.2.x__Contract_DocumentArtifactID.sql
-- Split-and-regenerate with INLINE NATIVE CodeGen baking: hand-written DDL transpiled
-- (AST dialect), metadata DML inline, and CodeGen objects (views/sprocs/triggers/grants)
-- baked natively from `mj codegen`. Applies standalone via `mj migrate` — no deploy codegen.
-- ============================================================================

-- None required: UUID defaults use the built-in gen_random_uuid() (PostgreSQL 13+).
CREATE SCHEMA IF NOT EXISTS __mj_BizAppsContracts;
SET search_path TO __mj_BizAppsContracts, public;
SET standard_conforming_strings = on;

ALTER TABLE __mj_BizAppsContracts."Contract"
  ADD COLUMN "DocumentArtifactID" UUID NULL CONSTRAINT "FK_Contract_DocumentArtifact" REFERENCES "__mj"."Artifact" (
    "ID"
  );

COMMENT ON COLUMN __mj_BizAppsContracts."Contract"."DocumentArtifactID" IS 'Optional link to an MJ Doc ([__mj].[Artifact]) holding a versioned long-form document such as an Assembled Contract Draft, AI Contract Review Memo, or Executive Summary. Distinct from signed final PDFs attached via MJ: Files (Executed Agreement category) and from relational ContractTemplateProvision / ContractTemplateModification clause rows.';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'db297c5d-0d36-409b-828a-f92d276cf8b9' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'DocumentArtifactID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('db297c5d-0d36-409b-828a-f92d276cf8b9', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'), 'DocumentArtifactID', 'Document Artifact ID', 'Optional link to an MJ Doc ([__mj].[Artifact]) holding a versioned long-form document such as an Assembled Contract Draft, AI Contract Review Memo, or Executive Summary. Distinct from signed final PDFs attached via MJ: Files (Executed Agreement category) and from relational ContractTemplateProvision / ContractTemplateModification clause rows.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, 'F48D2341-8667-40BB-BCA8-87D7F80E16CD', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'cea42cdc-66ff-4ca6-b502-0bf78615ff5e' OR ("EntityID" = 'F48D2341-8667-40BB-BCA8-87D7F80E16CD' AND "RelatedEntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "RelatedEntityJoinField" = 'DocumentArtifactID')) THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('cea42cdc-66ff-4ca6-b502-0bf78615ff5e', 'F48D2341-8667-40BB-BCA8-87D7F80E16CD', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'DocumentArtifactID', 'One To Many', TRUE, TRUE, 8, NOW(), NOW());
  END IF;
END $$;

SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'DB297C5D-0D36-409B-828A-F92D276CF8B9', p_RelatedEntityNameFieldMap => 'DocumentArtifact');

-- ===================== CodeGen (native PG, baked) =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
-- ============================================================
-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'ContractTypeID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_contract_type_id"
            ON "__mj_bizappscontracts"."Contract" ("ContractTypeID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'CompanyID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_company_id"
            ON "__mj_bizappscontracts"."Contract" ("CompanyID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'CustomerOrganizationID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_customer_organization_id"
            ON "__mj_bizappscontracts"."Contract" ("CustomerOrganizationID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'PrimaryContactPersonID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_primary_contact_person_id"
            ON "__mj_bizappscontracts"."Contract" ("PrimaryContactPersonID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'ContractTemplateID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_contract_template_id"
            ON "__mj_bizappscontracts"."Contract" ("ContractTemplateID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'CreatingEntityID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_creating_entity_id"
            ON "__mj_bizappscontracts"."Contract" ("CreatingEntityID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'CreatingRecordID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_creating_record_id"
            ON "__mj_bizappscontracts"."Contract" ("CreatingRecordID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'ParentContractID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_parent_contract_id"
            ON "__mj_bizappscontracts"."Contract" ("ParentContractID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'SupersededByContractID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_superseded_by_contract_id"
            ON "__mj_bizappscontracts"."Contract" ("SupersededByContractID");
    END IF;
END
$$;

-- Skipped when another non-partial index already leads with the column.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index ix
        INNER JOIN pg_class t ON t.oid = ix.indrelid
        INNER JOIN pg_namespace n ON n.oid = t.relnamespace
        WHERE n.nspname = '__mj_bizappscontracts'
          AND t.relname = 'Contract'
          AND ix.indpred IS NULL
          AND ix.indnkeyatts >= 1
              AND ix.indkey[0] = (SELECT a.attnum FROM pg_attribute a WHERE a.attrelid = t.oid AND a.attname = 'DocumentArtifactID')
    ) THEN
        CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_document_artifact_id"
            ON "__mj_bizappscontracts"."Contract" ("DocumentArtifactID");
    END IF;
END
$$;

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
    mjbizappscontractsContract_SupersededByContractID."ContractNumber" AS "SupersededByContract",
    MJArtifact_DocumentArtifactID."Name" AS "DocumentArtifact"
FROM
    "__mj_bizappscontracts"."Contract" AS c
LEFT OUTER JOIN
    "__mj_bizappscontracts"."ContractType" AS mjbizappscontractsContractType_ContractTypeID
  ON
    "c"."ContractTypeID" = mjbizappscontractsContractType_ContractTypeID."ID"
LEFT OUTER JOIN
    "__mj"."Company" AS MJCompany_CompanyID
  ON
    "c"."CompanyID" = MJCompany_CompanyID."ID"
LEFT OUTER JOIN
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
LEFT OUTER JOIN
    "__mj"."Artifact" AS MJArtifact_DocumentArtifactID
  ON
    "c"."DocumentArtifactID" = MJArtifact_DocumentArtifactID."ID"
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
    grants_sql  TEXT,
    depth       INT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_deps;

  -- Every view that DROP ... CASCADE removes: direct dependents AND theirs, transitively.
  -- Capturing only direct dependents restored vwTestRuns after a vwTestSuiteRuns regen but
  -- not vwConversations / vwConversationDetails, which select from vwTestRuns — they and their
  -- CRUD functions stayed permanently missing. depth is the LONGEST path from the target, so
  -- replaying in depth order always recreates a view after every view it reads.
  CREATE TEMP TABLE IF NOT EXISTS _vw_regen_dep_oids (
    view_oid OID,
    depth    INT
  ) ON COMMIT DROP;
  DELETE FROM _vw_regen_dep_oids;
  INSERT INTO _vw_regen_dep_oids (view_oid, depth)
  WITH RECURSIVE deps(view_oid, depth) AS (
      SELECT DISTINCT dc.oid, 1
      FROM pg_depend d
      JOIN pg_rewrite r ON r.oid = d.objid AND d.classid = 'pg_rewrite'::regclass
      JOIN pg_class dc ON dc.oid = r.ev_class AND dc.relkind IN ('v', 'm')
      JOIN pg_class tc ON tc.oid = d.refobjid
      JOIN pg_namespace tn ON tn.oid = tc.relnamespace
      WHERE tn.nspname = '__mj_bizappscontracts'
        AND tc.relname = 'vwContractsGenerated'
        AND tc.relkind IN ('v', 'm')
        AND dc.oid <> tc.oid
    UNION
      SELECT dc.oid, deps.depth + 1
      FROM deps
      JOIN pg_depend d ON d.refobjid = deps.view_oid
      JOIN pg_rewrite r ON r.oid = d.objid AND d.classid = 'pg_rewrite'::regclass
      JOIN pg_class dc ON dc.oid = r.ev_class AND dc.relkind IN ('v', 'm')
      WHERE dc.oid <> deps.view_oid
        AND deps.depth < 50
  )
  SELECT view_oid, MAX(depth) FROM deps GROUP BY view_oid;

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
  INSERT INTO _vw_regen_deps (schema_name, view_name, relkind, definition, grants_sql, depth)
  SELECT
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
       WHERE g.privilege IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')),
      o.depth
  FROM _vw_regen_dep_oids o
  JOIN pg_class dc ON dc.oid = o.view_oid
  JOIN pg_namespace dn ON dn.oid = dc.relnamespace;

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
  -- The set is the target view plus every view captured above, because CASCADE drops the
  -- functions of each of them, not only the target's.
  INSERT INTO _vw_regen_fn_deps (schema_name, fn_name, fn_oid, definition)
  SELECT DISTINCT
      pn.nspname,
      pp.proname,
      pp.oid,
      pg_get_functiondef(pp.oid)
  FROM pg_proc pp
  JOIN pg_namespace pn ON pn.oid = pp.pronamespace
  WHERE pp.prokind IN ('f', 'p')
    AND EXISTS (
      SELECT 1
      FROM pg_class c
      WHERE (c.oid IN (SELECT view_oid FROM _vw_regen_dep_oids)
             OR c.oid = (SELECT tc.oid FROM pg_class tc
                         JOIN pg_namespace tn ON tn.oid = tc.relnamespace
                         WHERE tn.nspname = '__mj_bizappscontracts'
                           AND tc.relname = 'vwContractsGenerated'
                           AND tc.relkind IN ('v', 'm')))
        AND (pp.prorettype = c.reltype
             OR EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.classid = 'pg_proc'::regclass
                          AND d.objid = pp.oid
                          AND d.refobjid = c.oid))
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
  FOR rec IN SELECT schema_name, view_name, relkind, definition, grants_sql FROM _vw_regen_deps ORDER BY depth, view_name LOOP
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
  DROP TABLE _vw_regen_dep_oids;
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
    p_predictedrenewalscoredat TIMESTAMPTZ DEFAULT NULL,
    p_carrydiscountonrenewal BOOLEAN DEFAULT NULL,
    p_documentartifactid_clear boolean DEFAULT false,
    p_documentartifactid UUID DEFAULT NULL
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
                "PredictedRenewalScoredAt",
                "CarryDiscountOnRenewal",
                "DocumentArtifactID"
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
                CASE WHEN p_predictedrenewalscoredat_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalscoredat, NULL) END,
                COALESCE(p_carrydiscountonrenewal, FALSE),
                CASE WHEN p_documentartifactid_clear = true THEN NULL ELSE COALESCE(p_documentartifactid, NULL) END
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
    p_predictedrenewalscoredat TIMESTAMPTZ DEFAULT NULL,
    p_carrydiscountonrenewal BOOLEAN DEFAULT NULL,
    p_documentartifactid_clear boolean DEFAULT false,
    p_documentartifactid UUID DEFAULT NULL
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
        "PredictedRenewalScoredAt" = CASE WHEN p_predictedrenewalscoredat_clear = true THEN NULL ELSE COALESCE(p_predictedrenewalscoredat, "PredictedRenewalScoredAt") END,
        "CarryDiscountOnRenewal" = COALESCE(p_carrydiscountonrenewal, "CarryDiscountOnRenewal"),
        "DocumentArtifactID" = CASE WHEN p_documentartifactid_clear = true THEN NULL ELSE COALESCE(p_documentartifactid, "DocumentArtifactID") END,
        "__mj_UpdatedAt" = (NOW() AT TIME ZONE 'UTC')
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

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '47b1e39e-673e-41de-9759-7fd2d87953f8' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'DocumentArtifact')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('47b1e39e-673e-41de-9759-7fd2d87953f8', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'), 'DocumentArtifact', 'Document Artifact', NULL, 'nvarchar', 510, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;
