-- =============================================================================
-- PostgreSQL counterpart of V202611121200__v0.13.x__Contract_order_link_and_carry_discount.sql
-- ContractOrder, the link from a contract to the orders it produced, and
-- Contract.CarryDiscountOnRenewal (issue #77)
-- =============================================================================
-- Same change as the T-SQL file; see its header for why. The objects differ in
-- form only:
--   * ContractOrder's foreign key names __mj_bizappsorders."OrderHeader": the
--     Orders app's schema as PostgreSQL holds it (unquoted, so lower case), the
--     way earlier files name __mj_bizappscommon. Orders must be installed first.
--   * CarryDiscountOnRenewal is BOOLEAN NOT NULL DEFAULT FALSE.
--
-- HOW IT WAS MADE. Written by hand from the T-SQL file; no PostgreSQL database
-- at this app's v0.12.3 state could be built to bake CodeGen from.
--   * Hand-written DDL: from the T-SQL file's DDL.
--   * CodeGen-captured metadata: the T-SQL capture's statements in PostgreSQL
--     form (the new entity, its application link and three permissions, its
--     timestamp columns, eight EntityField rows, two relationships, the two
--     name-field maps, the search-flag hygiene update), IDs and strings copied
--     verbatim. The T-SQL capture carries no schema-refresh calls, so neither
--     does this file; `mj migrate` runs the metadata heal for the app schema.
--   * Contract: vwContracts must be dropped, not replaced, because the new
--     column lands inside g.* (as V202611031700 explains for NonRenewalOutcome).
--     vwContractsGenerated, the update trigger, spDeleteContract and
--     vwContracts are V202611031700's definitions, unchanged; spCreateContract
--     and spUpdateContract are too, plus the CarryDiscountOnRenewal parameter,
--     matching the T-SQL file's procedures.
--   * ContractOrder: native PostgreSQL CodeGen objects (FK indexes,
--     vwContractOrders, the three CRUD functions, the update trigger, grants),
--     written from the baseline's native block for ContractTemplateModification,
--     an entity of the same shape, with this table's columns and joins.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;

-- ===================== Hand-written DDL =====================

CREATE TABLE __mj_bizappscontracts."ContractOrder" (
  "ID" UUID NOT NULL DEFAULT gen_random_uuid(),
  "ContractID" UUID NOT NULL,
  "OrderID" UUID NOT NULL,
  CONSTRAINT "PK_ContractOrder" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractOrder_ContractOrder" UNIQUE ("ContractID", "OrderID"),
  CONSTRAINT "FK_ContractOrder_Contract"
    FOREIGN KEY ("ContractID") REFERENCES __mj_bizappscontracts."Contract" ("ID"),
  CONSTRAINT "FK_ContractOrder_OrderHeader"
    FOREIGN KEY ("OrderID") REFERENCES __mj_bizappsorders."OrderHeader" ("ID")
);

-- The unique constraint leads with ContractID, which serves "this contract's
-- orders". The reverse question, "which contracts govern this order", gets its own.
CREATE INDEX "IX_ContractOrder_OrderID"
  ON __mj_bizappscontracts."ContractOrder" ("OrderID");

COMMENT ON TABLE __mj_bizappscontracts."ContractOrder" IS 'An order this contract governs. The contract''s renewal terms (annual increase, whether a discount continues) are copied to every subscription the order''s lines created. Written when a deal closes with both a contract and an order, or by hand for an order the contract covers.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractOrder"."ContractID" IS 'The contract whose terms apply to the order.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractOrder"."OrderID" IS 'The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.';

ALTER TABLE __mj_bizappscontracts."Contract"
  ADD COLUMN "CarryDiscountOnRenewal" BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CarryDiscountOnRenewal" IS 'Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.';

-- ===================== CodeGen-captured metadata =====================

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Orders */
INSERT INTO "__mj"."Entity" ("ID", "Name", "DisplayName", "Description", "NameSuffix", "BaseTable", "BaseView", "SchemaName", "IncludeInAPI", "AllowUserSearchAPI", "AllowCaching", "TrackRecordChanges", "AuditRecordAccess", "AuditViewRuns", "AllowAllRowsAPI", "AllowCreateAPI", "AllowUpdateAPI", "AllowDeleteAPI", "UserViewMaxRows", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', 'MJ_BizApps_Contracts: Contract Orders', 'Contract Orders', 'An order this contract governs. The contract''s renewal terms (annual increase, whether a discount continues) are copied to every subscription the order''s lines created. Written when a deal closes with both a contract and an order, or by hand for an order the contract covers.', NULL, 'ContractOrder', 'vwContractOrders', '__mj_bizappscontracts', TRUE, TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE, 1000, NOW(), NOW());

/* SQL generated to add entity MJ_BizApps_Contracts: Contract Orders to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" ("ApplicationID", "EntityID", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('891E92FE-561A-4FED-8EDC-E2D96FB18541', '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."ApplicationEntity" WHERE "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'), NOW(), NOW());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role UI */
INSERT INTO "__mj"."EntityPermission" ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 'Allow', TRUE, FALSE, FALSE, FALSE, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM "__mj"."EntityPermission"
  WHERE "EntityID" = '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AND "RoleID" = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E' AND "Type" = 'Allow'
);

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role Developer */
INSERT INTO "__mj"."EntityPermission" ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 'Allow', TRUE, TRUE, TRUE, TRUE, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM "__mj"."EntityPermission"
  WHERE "EntityID" = '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AND "RoleID" = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E' AND "Type" = 'Allow'
);

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Orders for role Integration */
INSERT INTO "__mj"."EntityPermission" ("EntityID", "RoleID", "Type", "CanRead", "CanCreate", "CanUpdate", "CanDelete", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 'Allow', TRUE, TRUE, TRUE, TRUE, NOW(), NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM "__mj"."EntityPermission"
  WHERE "EntityID" = '5cabae2b-ddfa-4678-a147-cbd8d4b77a1d' AND "RoleID" = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E' AND "Type" = 'Allow'
);

/* SQL text to add special date fields __mj_CreatedAt and __mj_UpdatedAt to entity __mj_bizappscontracts.ContractOrder */
ALTER TABLE __mj_bizappscontracts."ContractOrder"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL;

UPDATE __mj_bizappscontracts."ContractOrder" SET "__mj_CreatedAt" = NOW() WHERE "__mj_CreatedAt" IS NULL;

ALTER TABLE __mj_bizappscontracts."ContractOrder" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractOrder" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractOrder"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL;

UPDATE __mj_bizappscontracts."ContractOrder" SET "__mj_UpdatedAt" = NOW() WHERE "__mj_UpdatedAt" IS NULL;

ALTER TABLE __mj_bizappscontracts."ContractOrder" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractOrder" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

/* SQL text to insert 6 new entity field(s) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '28f8dfb4-9339-4a7f-8e6e-b04796b2346d' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('28f8dfb4-9339-4a7f-8e6e-b04796b2346d', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd6f1f326-efd6-4db3-bf6c-890c9fd9e631' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = 'ContractID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d6f1f326-efd6-4db3-bf6c-890c9fd9e631', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), 'ContractID', 'Contract ID', 'The contract whose terms apply to the order.', 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '275211a7-c882-4e63-9eb5-bd6063ce2bf5' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = 'OrderID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('275211a7-c882-4e63-9eb5-bd6063ce2bf5', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), 'OrderID', 'Order ID', 'The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.', 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, 'FC529BC8-FF09-44A9-B454-26EAFDAC791B', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'b6fbe26d-8aaf-4366-ab20-5211751c4dbb' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('b6fbe26d-8aaf-4366-ab20-5211751c4dbb', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'f49138c4-d431-4225-ad63-caf13458b382' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('f49138c4-d431-4225-ad63-caf13458b382', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '5f016939-6a80-450d-b51c-84fda3e217a2' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CarryDiscountOnRenewal')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('5f016939-6a80-450d-b51c-84fda3e217a2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'), 'CarryDiscountOnRenewal', 'Carry Discount On Renewal', 'Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* Deterministic search-flag hygiene — clear AllowUserSearchAPI */
UPDATE "__mj"."Entity"
SET "AllowUserSearchAPI" = FALSE
WHERE "ID" IN (
   SELECT e."ID"
   FROM "__mj"."Entity" e
   WHERE e."AllowUserSearchAPI" = TRUE
     AND e."AutoUpdateAllowUserSearchAPI" = TRUE
     AND e."VirtualEntity" = FALSE
     AND COALESCE(e."FullTextSearchEnabled", FALSE) = FALSE
     AND e."SchemaName" NOT IN ('sys','staging','dbo','__mj','__mj_bizappsaccounting','__mj_bizappscommon','__mj_bizappsorders','__mj_bizappstasks')
     AND NOT EXISTS (
      SELECT 1 FROM "__mj"."EntityField" f2
      WHERE f2."EntityID" = e."ID"
        AND f2."IncludeInUserSearchAPI" = TRUE
   )
);

/* Create Entity Relationship: MJ_BizApps_Orders: Order Headers -> MJ_BizApps_Contracts: Contract Orders (One To Many via OrderID) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '333cb15d-7154-405b-a2c1-706466376188' OR ("EntityID" = 'FC529BC8-FF09-44A9-B454-26EAFDAC791B' AND "RelatedEntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "RelatedEntityJoinField" = 'OrderID')) THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('333cb15d-7154-405b-a2c1-706466376188', 'FC529BC8-FF09-44A9-B454-26EAFDAC791B', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', 'OrderID', 'One To Many', TRUE, TRUE, 17, NOW(), NOW());
  END IF;
END $$;

/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Orders (One To Many via ContractID) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'f0557b4c-8817-4773-af59-47e278a5fa27' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "RelatedEntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "RelatedEntityJoinField" = 'ContractID')) THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('f0557b4c-8817-4773-af59-47e278a5fa27', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D', 'ContractID', 'One To Many', TRUE, TRUE, 4, NOW(), NOW());
  END IF;
END $$;

-- ===================== CodeGen (native PG): Contract Order FK indexes =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: Index for Foreign Keys
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_order_contract_id"
    ON "__mj_bizappscontracts"."ContractOrder" ("ContractID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_order_order_id"
    ON "__mj_bizappscontracts"."ContractOrder" ("OrderID");

/* SQL text to update entity field related entity name field map for entity field ID D6F1F326-EFD6-4DB3-BF6C-890C9FD9E631 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'D6F1F326-EFD6-4DB3-BF6C-890C9FD9E631', p_RelatedEntityNameFieldMap => 'Contract');

-- vwContracts goes first (see the header); the CodeGen block below recreates
-- vwContractsGenerated and the CRUD functions, then vwContracts is recreated.
DROP VIEW __mj_bizappscontracts."vwContracts" CASCADE;

-- ===================== CodeGen (native PG): Contract =====================

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



-- ===================== Hand-written: vwContracts (unchanged since V202611031700) =====================

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

-- ===================== CodeGen (continued): Contract CRUD functions =====================

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
    p_carrydiscountonrenewal BOOLEAN DEFAULT NULL
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
                "CarryDiscountOnRenewal"
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
                COALESCE(p_carrydiscountonrenewal, FALSE)
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
    p_carrydiscountonrenewal BOOLEAN DEFAULT NULL
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
        "CarryDiscountOnRenewal" = COALESCE(p_carrydiscountonrenewal, "CarryDiscountOnRenewal")
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

-- ===================== CodeGen (native PG): Contract Order =====================

/* SQL text to update entity field related entity name field map for entity field ID 275211A7-C882-4E63-9EB5-BD6063CE2BF5 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => '275211A7-C882-4E63-9EB5-BD6063CE2BF5', p_RelatedEntityNameFieldMap => 'Order');

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: vwContractOrders
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Orders
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractOrder
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractOrders"
AS
SELECT
    c.*,
    mjbizappscontractsContract_ContractID."ContractNumber" AS "Contract",
    mjBizAppsOrdersOrderHeader_OrderID."OrderNumber" AS "Order"
FROM
    "__mj_bizappscontracts"."ContractOrder" AS c
INNER JOIN
    "__mj_bizappscontracts"."Contract" AS mjbizappscontractsContract_ContractID
  ON
    "c"."ContractID" = mjbizappscontractsContract_ContractID."ID"
INNER JOIN
    "__mj_bizappsorders"."OrderHeader" AS mjBizAppsOrdersOrderHeader_OrderID
  ON
    "c"."OrderID" = mjBizAppsOrdersOrderHeader_OrderID."ID"
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
    AND tc.relname = 'vwContractOrders'
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
    AND tc.relname = 'vwContractOrders'
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
        AND tc.relname = 'vwContractOrders'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractOrders" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractOrders" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractOrders" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractOrders" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spCreateContractOrder
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractOrder
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractOrder'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractOrder"(
    p_id UUID DEFAULT NULL,
    p_contractid UUID DEFAULT NULL,
    p_orderid UUID DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractOrders" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractOrder"
        (
            "ID",
            "ContractID",
                "OrderID"
        )
    VALUES
        (
            v_new_id,
            p_contractid,
                p_orderid
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractOrders"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractOrder" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractOrder" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spUpdateContractOrder
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractOrder
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractOrder'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractOrder"(
    p_id UUID,
    p_contractid UUID DEFAULT NULL,
    p_orderid UUID DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractOrders" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractOrder"
    SET
        "ContractID" = COALESCE(p_contractid, "ContractID"),
        "OrderID" = COALESCE(p_orderid, "OrderID")
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractOrders"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractOrder" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractOrder" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractOrder table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_order"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_order" ON "__mj_bizappscontracts"."ContractOrder";

CREATE TRIGGER "trg_update_contract_order"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractOrder"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_order"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Orders
-- Item: spDeleteContractOrder
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractOrder
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractOrder'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractOrder"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractOrder"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractOrder" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractOrder" TO "cdp_Integration";

-- ===================== CodeGen-captured metadata (after the objects) =====================

/* SQL text to insert 2 new entity field(s) */
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'aab3d822-2597-453d-88b6-b8df6f467d14' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = 'Contract')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('aab3d822-2597-453d-88b6-b8df6f467d14', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), 'Contract', 'Contract', NULL, 'nvarchar', 100, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0e381161-4f50-4a1d-b9f8-540364171db5' OR ("EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' AND "Name" = 'Order')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0e381161-4f50-4a1d-b9f8-540364171db5', '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D' /* Entity: MJ_BizApps_Contracts: Contract Orders */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = '5CABAE2B-DDFA-4678-A147-CBD8D4B77A1D'), 'Order', 'Order', NULL, 'nvarchar', 80, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;
