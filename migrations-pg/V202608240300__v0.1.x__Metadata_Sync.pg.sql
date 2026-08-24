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

-- Save MJ_BizApps_Contracts: Contract Template Types (core SP call only)
DO $mj$
DECLARE
  p_ID_b0d4fcb3 UUID;
  p_Name_b0d4fcb3 VARCHAR(100);
  p_Description_b0d4fcb3 TEXT;
  p_Status_b0d4fcb3 VARCHAR(10);
BEGIN
  p_ID_b0d4fcb3 := '33333333-0000-4000-8000-000000002001';
  p_Name_b0d4fcb3 := 'Master Agreement';
  p_Description_b0d4fcb3 := 'The numbered-provision standard-terms document, versioned by publication date. Every Order Form and Payment Link incorporates one version of it, and a negotiated deviation from one of its provisions is a Contract Template Modification.';
  p_Status_b0d4fcb3 := 'Active';
  PERFORM __mj_BizAppsContracts."spCreateContractTemplateType"(p_ID := p_ID_b0d4fcb3, p_Name := p_Name_b0d4fcb3, p_Description := p_Description_b0d4fcb3, p_Status := p_Status_b0d4fcb3);
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Template Types (core SP call only)
DO $mj$
DECLARE
  p_ID_a5b7685c UUID;
  p_Name_a5b7685c VARCHAR(100);
  p_Description_a5b7685c TEXT;
  p_Status_a5b7685c VARCHAR(10);
BEGIN
  p_ID_a5b7685c := '33333333-0000-4000-8000-000000002002';
  p_Name_a5b7685c := 'Statement of Work';
  p_Description_a5b7685c := 'Standard SOW language. Seeded so the type exists; no versioned template is registered against it yet, because the business does not version its SOW language (Amith, 2026-08-18).';
  p_Status_a5b7685c := 'Active';
  PERFORM __mj_BizAppsContracts."spCreateContractTemplateType"(p_ID := p_ID_a5b7685c, p_Name := p_Name_a5b7685c, p_Description := p_Description_a5b7685c, p_Status := p_Status_a5b7685c);
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Types (core SP call only)
DO $mj$
DECLARE
  p_ID_5574320d UUID;
  p_Name_5574320d VARCHAR(100);
  p_Description_5574320d TEXT;
  p_RequiresExecutedDocument_5574320d BOOLEAN;
  p_Status_5574320d VARCHAR(10);
  p_MustBeRoot_5574320d BOOLEAN;
  p_MustBeChild_5574320d BOOLEAN;
  p_TemplateRequired_5574320d BOOLEAN;
BEGIN
  p_ID_5574320d := '33333333-0000-4000-8000-000000001001';
  p_Name_5574320d := 'Order Form';
  p_Description_5574320d := 'The commercial document a customer signs to buy — the ordinary agreement. Sits beneath a Master Agreement whose provisions it incorporates by reference, which is why the Order Form carries the ContractTemplateID rather than the MA carrying anything about it — hence TemplateRequired = 1. Signed paper is expected (RequiresExecutedDocument = 1), so it appears on the Awaiting-documents worklist until the executed file is registered. Reinstated Active 2026-08-20 (Marcelo), reversing the R-4 retirement.';
  p_RequiresExecutedDocument_5574320d := TRUE;
  p_Status_5574320d := 'Active';
  p_MustBeRoot_5574320d := FALSE;
  p_MustBeChild_5574320d := FALSE;
  p_TemplateRequired_5574320d := TRUE;
  PERFORM __mj_BizAppsContracts."spCreateContractType"(p_ID := p_ID_5574320d, p_Name := p_Name_5574320d, p_Description := p_Description_5574320d, p_RequiresExecutedDocument := p_RequiresExecutedDocument_5574320d, p_Status := p_Status_5574320d, p_MustBeRoot := p_MustBeRoot_5574320d, p_MustBeChild := p_MustBeChild_5574320d, p_TemplateRequired := p_TemplateRequired_5574320d);
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Types (core SP call only)
DO $mj$
DECLARE
  p_ID_9e472895 UUID;
  p_Name_9e472895 VARCHAR(100);
  p_Description_9e472895 TEXT;
  p_RequiresExecutedDocument_9e472895 BOOLEAN;
  p_Status_9e472895 VARCHAR(10);
  p_MustBeRoot_9e472895 BOOLEAN;
  p_MustBeChild_9e472895 BOOLEAN;
  p_TemplateRequired_9e472895 BOOLEAN;
BEGIN
  p_ID_9e472895 := '33333333-0000-4000-8000-000000001002';
  p_Name_9e472895 := 'Statement of Work';
  p_Description_9e472895 := 'Scoped services with a defined end. Amith, 2026-08-18: SOWs have standard language but no versioned template — so an SOW contract may have no ContractTemplateID, and that is not a gap to fill. Paper is still expected.';
  p_RequiresExecutedDocument_9e472895 := TRUE;
  p_Status_9e472895 := 'Active';
  p_MustBeRoot_9e472895 := TRUE;
  p_MustBeChild_9e472895 := FALSE;
  p_TemplateRequired_9e472895 := TRUE;
  PERFORM __mj_BizAppsContracts."spCreateContractType"(p_ID := p_ID_9e472895, p_Name := p_Name_9e472895, p_Description := p_Description_9e472895, p_RequiresExecutedDocument := p_RequiresExecutedDocument_9e472895, p_Status := p_Status_9e472895, p_MustBeRoot := p_MustBeRoot_9e472895, p_MustBeChild := p_MustBeChild_9e472895, p_TemplateRequired := p_TemplateRequired_9e472895);
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Types (core SP call only)
DO $mj$
DECLARE
  p_ID_8b89bf80 UUID;
  p_Name_8b89bf80 VARCHAR(100);
  p_Description_8b89bf80 TEXT;
  p_RequiresExecutedDocument_8b89bf80 BOOLEAN;
  p_Status_8b89bf80 VARCHAR(10);
  p_MustBeRoot_8b89bf80 BOOLEAN;
  p_MustBeChild_8b89bf80 BOOLEAN;
  p_TemplateRequired_8b89bf80 BOOLEAN;
BEGIN
  p_ID_8b89bf80 := '33333333-0000-4000-8000-000000001003';
  p_Name_8b89bf80 := 'Payment Link';
  p_Description_8b89bf80 := 'The sub-$10k self-serve case: finance sends a HubSpot payment link that references the Master Agreement, and nobody signs anything. There is an implied contract, so it IS a contract — it carries a ContractTemplateID (TemplateRequired = 1, because the MA it incorporates is the only thing stating the terms) and no document. This is the one type where RequiresExecutedDocument is false, and the reason that column exists at all: it is what keeps a Payment Link OFF the Awaiting-documents worklist instead of sitting there forever waiting on paper that will never arrive. Reinstated Active 2026-08-20 (Marcelo), reversing the R-4 retirement; final shape pending Andrew''s confirmation.';
  p_RequiresExecutedDocument_8b89bf80 := FALSE;
  p_Status_8b89bf80 := 'Active';
  p_MustBeRoot_8b89bf80 := FALSE;
  p_MustBeChild_8b89bf80 := FALSE;
  p_TemplateRequired_8b89bf80 := TRUE;
  PERFORM __mj_BizAppsContracts."spCreateContractType"(p_ID := p_ID_8b89bf80, p_Name := p_Name_8b89bf80, p_Description := p_Description_8b89bf80, p_RequiresExecutedDocument := p_RequiresExecutedDocument_8b89bf80, p_Status := p_Status_8b89bf80, p_MustBeRoot := p_MustBeRoot_8b89bf80, p_MustBeChild := p_MustBeChild_8b89bf80, p_TemplateRequired := p_TemplateRequired_8b89bf80);
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Types (core SP call only)
DO $mj$
DECLARE
  p_ID_d32186e0 UUID;
  p_Name_d32186e0 VARCHAR(100);
  p_Description_d32186e0 TEXT;
  p_RequiresExecutedDocument_d32186e0 BOOLEAN;
  p_Status_d32186e0 VARCHAR(10);
  p_MustBeRoot_d32186e0 BOOLEAN;
  p_MustBeChild_d32186e0 BOOLEAN;
  p_TemplateRequired_d32186e0 BOOLEAN;
BEGIN
  p_ID_d32186e0 := '33333333-0000-4000-8000-000000001004';
  p_Name_d32186e0 := 'Change Order';
  p_Description_d32186e0 := 'Amends an existing agreement rather than replacing it: signed paper of its own, its own dates, and a ParentContractID naming what it changes. MustBeChild = 1 is what enforces that parent — the server subclass reads that flag, where it once compared this row''s NAME to the string ''Change Order'' and silently stopped working if anyone renamed it. It carries no template of its own (TemplateRequired = 0); a modification recorded on a change order may cite any provision of a template at or above it in the tree.';
  p_RequiresExecutedDocument_d32186e0 := TRUE;
  p_Status_d32186e0 := 'Active';
  p_MustBeRoot_d32186e0 := FALSE;
  p_MustBeChild_d32186e0 := TRUE;
  p_TemplateRequired_d32186e0 := FALSE;
  PERFORM __mj_BizAppsContracts."spCreateContractType"(p_ID := p_ID_d32186e0, p_Name := p_Name_d32186e0, p_Description := p_Description_d32186e0, p_RequiresExecutedDocument := p_RequiresExecutedDocument_d32186e0, p_Status := p_Status_d32186e0, p_MustBeRoot := p_MustBeRoot_d32186e0, p_MustBeChild := p_MustBeChild_d32186e0, p_TemplateRequired := p_TemplateRequired_d32186e0);
END $mj$;


-- ===================== Other =====================

-- End of SQL Logging Session
-- Session ID: d1c3204d-5a28-4007-96df-2cdc3d478801
-- Completed: 2026-08-24T02:34:23.408Z
-- Duration: 16608ms
-- Total Statements: 27
