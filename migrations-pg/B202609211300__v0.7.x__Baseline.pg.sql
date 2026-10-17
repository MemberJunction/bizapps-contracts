-- ============================================================================
-- BizApps Contracts — PostgreSQL baseline (covers every T-SQL migration through
-- V202609211200, v0.7.x).
--
-- One file instead of nine counterparts: the T-SQL history was replayed on
-- PostgreSQL 17 (MJ core 6.1.5 + bizapps-common + bizapps-tasks), each step
-- converted with `mj migrate convert --split --bake-codegen` where the 6.1.5
-- converter handles it, and by hand where it does not. Hand-written parts:
--   * fnProvisionSortKey (IMMUTABLE, for the stored generated column),
--     seq_ContractNumber, spAssignNextContractNumber, the provision
--     immutability trigger, and the ContractTemplateProvision table;
--   * the vwContracts / vwContractTemplates wrapper views, one version per
--     T-SQL migration that changed them, and the fields they register;
--   * the predictive renewal columns and their field registrations.
-- CodeGen objects (views, CRUD functions, triggers, grants) are native PG
-- CodeGen output. CodeGen's captured metadata (name fields, search settings,
-- field categories, validators) and the Metadata_Sync come from the T-SQL
-- files through the rule-based converter.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;


-- ============================================================================
-- Objects the tables need
-- ============================================================================
-- =============================================================================
-- APP-OWNED OBJECTS THE TABLES NEED (hand-written PL/pgSQL)
-- =============================================================================
-- fnProvisionSortKey comes before the tables because ContractTemplateProvision's
-- ProvisionSortKey is a stored generated column over it. PostgreSQL resolves a
-- generated column's expression at CREATE TABLE time and requires the function to
-- be IMMUTABLE; it is (the result depends only on the argument).


-- Collation key for a provision number: every run of digits zero-padded to six
-- places (never truncated when longer), every other character upper-cased, so
-- '1.10' sorts after '1.9' and '1.1a' lands with '1.1A'.
CREATE OR REPLACE FUNCTION __mj_bizappscontracts."fnProvisionSortKey"(p_provision_number VARCHAR(20))
RETURNS VARCHAR(200)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_out    TEXT := '';
    v_digits TEXT := '';
    v_c      TEXT;
    v_i      INT;
BEGIN
    IF p_provision_number IS NULL THEN
        RETURN NULL;
    END IF;

    FOR v_i IN 1 .. length(p_provision_number) LOOP
        v_c := substr(p_provision_number, v_i, 1);
        IF v_c BETWEEN '0' AND '9' THEN
            v_digits := v_digits || v_c;
        ELSE
            IF length(v_digits) > 0 THEN
                v_out := v_out || lpad(v_digits, greatest(length(v_digits), 6), '0');
                v_digits := '';
            END IF;
            v_out := v_out || upper(v_c);
        END IF;
    END LOOP;

    IF length(v_digits) > 0 THEN
        v_out := v_out || lpad(v_digits, greatest(length(v_digits), 6), '0');
    END IF;

    RETURN v_out;
END;
$$;

-- PostgreSQL sequences have no cross-restart gap from caching unless CACHE > 1;
-- CACHE 1 is the default and matches the T-SQL NO CACHE.
CREATE SEQUENCE __mj_bizappscontracts."seq_ContractNumber" AS INTEGER START WITH 1 INCREMENT BY 1 CACHE 1;


-- ============================================================================
-- Baseline: tables, constraints, metadata (B202608040001)
-- ============================================================================
-- ============================================================================
-- MemberJunction PostgreSQL Migration — B202608040001__v0.1.x__Baseline.sql
-- Split-and-regenerate with INLINE NATIVE CodeGen baking: hand-written DDL transpiled
-- (AST dialect), metadata DML inline, and CodeGen objects (views/sprocs/triggers/grants)
-- baked natively from `mj codegen`. Applies standalone via `mj migrate` — no deploy codegen.
-- ============================================================================


DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."SchemaInfo" WHERE "SchemaName" = '__mj_bizappscontracts') THEN
    INSERT INTO "__mj"."SchemaInfo" ("ID", "SchemaName", "EntityIDMin", "EntityIDMax", "Comments", "Description", "EntityNamePrefix", "EntityNameSuffix") VALUES ('1A531C07-5F1A-448D-A2BF-B986801F4F1D', '__mj_bizappscontracts', 1, 1000000, NULL, 'MemberJunction: BizApps Contracts — the record of our obligations, and where the documents live', 'MJ_BizApps_Contracts: ', NULL);
  END IF;
END $$;

/* ============================================================================= */
/* 3. TABLES */
/* ============================================================================= */
/* ------------------------------------------------------------------------- */
/* 3.1 ContractTemplateType — the kind of standard agreement. */
/*     A lookup TABLE rather than a CHECK, for the reason accounting gives for */
/*     GLAccountRole: the value list is additive at runtime (a data-processing */
/*     addendum, a BAA, a reseller agreement) and a business user should add one */
/*     without a migration. Carries no behaviour. */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."ContractTemplateType" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "Name" VARCHAR(100) NOT NULL,
  "Description" TEXT NULL,
  "Status" VARCHAR(10) NOT NULL DEFAULT 'Active',
  CONSTRAINT "PK_ContractTemplateType" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractTemplateType_Name" UNIQUE (
    "Name"
  ),
  CONSTRAINT "CK_ContractTemplateType_Status" CHECK ("Status" IN ('Active', 'Inactive'))
);

/* ------------------------------------------------------------------------- */
/* 3.2 ContractTemplate — one VERSION of a standard agreement. */
/*     In practice the Master Agreement, published at a date-versioned public URL */
/*     that never goes away, so a customer who signed in June 2026 stays bound to */
/*     the June 2026 text. */
/*     SourceURL IS NULLABLE, and the earlier NOT NULL is a corrected mistake rather */
/*     than a relaxation (ruled by Marcelo, 2026-08-19). The ERD asked for "a public URL */
/*     that never goes away" and REACHABILITY IS ENFORCEABLE BY NOTHING: whether a URL */
/*     still resolves is a fact about the outside world, and format validation is weak */
/*     because a well-formed dead link passes. The real requirement is "a URL OR an */
/*     attached file" -- and a file attaches through __mj.FileEntityRecordLink keyed on */
/*     RecordID, which cannot reference a record that does not exist yet. On CREATE the */
/*     file half is unsatisfiable in principle, so no NOT NULL, CHECK or pre-save rule */
/*     can express it without blocking the ordinary act of authoring a template. A */
/*     template with neither is INCOMPLETE, not invalid -- an ordinary state to pass */
/*     through -- and the derived IsUsable column on vwContractTemplates is what lets the */
/*     UI say so, which a person can see and fix rather than an error that stops a save. */
/*     Carries no prose of its own — ContentText was removed (R-11) and every */
/*     clause's standard wording lives on its provision row instead (R-15/D-16). */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."ContractTemplate" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "Name" VARCHAR(200) NOT NULL,
  "ContractTemplateTypeID" UUID NOT NULL,
  "VersionLabel" VARCHAR(50) NULL,
  "IntroducedDate" DATE NULL,
  "SourceURL" /* NULLABLE (Marcelo, 2026-08-19). See the header note above: the real rule is */ /* "a URL OR an attached file", and the file half is unsatisfiable at CREATE time. */ VARCHAR(1000) NULL,
  "Description" TEXT NULL,
  "Status" VARCHAR(20) NOT NULL DEFAULT 'Draft',
  CONSTRAINT "PK_ContractTemplate" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractTemplate_Name" UNIQUE (
    "Name"
  ),
  CONSTRAINT "CK_ContractTemplate_Status" CHECK ("Status" IN ('Draft', 'Published'))
);

/* ------------------------------------------------------------------------- */
/* 3.3 ContractTemplateProvision — the numbered clause list of a template */
/*     version, and the home of all standard contract text (D-16). */
/*     ProvisionSortKey is a STORED generated collation key over */
/*     fnProvisionSortKey (created first, IMMUTABLE): ProvisionNumber does not */
/*     sort as text ('1.10' lands before '1.9'). Nobody can write a sort key. */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."ContractTemplateProvision" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "ContractTemplateID" UUID NOT NULL,
  "ProvisionNumber" VARCHAR(20) NOT NULL,
  "Title" VARCHAR(200) NOT NULL,
  "ProvisionText" TEXT NOT NULL,
  "Description" TEXT NULL,
  "ProvisionSortKey" VARCHAR(200) GENERATED ALWAYS AS (__mj_bizappscontracts."fnProvisionSortKey"("ProvisionNumber")) STORED,
  CONSTRAINT "PK_ContractTemplateProvision" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractTemplateProvision_Template_Number" UNIQUE ("ContractTemplateID", "ProvisionNumber"),
  CONSTRAINT "CK_ContractTemplateProvision_TextNotBlank" CHECK (length(btrim("ProvisionText")) > 0)
);

/* Template first: every real query is scoped to one template. */
CREATE INDEX "IX_ContractTemplateProvision_SortKey" ON "__mj_bizappscontracts"."ContractTemplateProvision"("ContractTemplateID", "ProvisionSortKey");

/* ------------------------------------------------------------------------- */
/* 3.4 ContractType — the kind of paper. */
/*     RequiresExecutedDocument is the one behavioural column, and it is */
/*     configuration-as-data rather than a branch on a type name: it is what stops */
/*     a Payment Link contract asking forever for paper that will never arrive. */
/*     "Awaiting the document" is then DERIVED as `requires it AND no linked file` */
/*     (ERD §4.5) — never a status, never a column. */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."ContractType" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "Name" VARCHAR(100) NOT NULL,
  "Description" TEXT NULL,
  "RequiresExecutedDocument" BOOLEAN NOT NULL DEFAULT TRUE,
  "Status" VARCHAR(10) NOT NULL DEFAULT 'Active',
  "MustBeRoot" /* Where in the contract tree this type may sit. Mutually exclusive; BOTH FALSE means */ /* unrestricted, which is the honest default and what two of the four seeded types want. */ /* These REPLACED a three-state ParentStatusRequirement string whose values invert the */ /* rule if read in the wrong order. */ BOOLEAN NOT NULL DEFAULT FALSE,
  "MustBeChild" BOOLEAN NOT NULL DEFAULT FALSE,
  "TemplateRequired" /* Whether a contract of this type must carry its own ContractTemplateID. */ BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT "PK_ContractType" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractType_Name" UNIQUE (
    "Name"
  ),
  CONSTRAINT "CK_ContractType_Status" CHECK ("Status" IN ('Active', 'Inactive')),
  CONSTRAINT "CK_ContractType_RootOrChild" CHECK (NOT (
    "MustBeRoot" = TRUE AND "MustBeChild" = TRUE
  ))
);

/* --------------------------------------------------------------------------- */
/* 3.5 (retired) ContractSequence -- the counter is a SEQUENCE, see 2.C. */
/*     v1 used a singleton counter TABLE, copying the shape orders uses for ORD- and */
/*     PAY-. A table is registered by CodeGen as an MJ ENTITY, which handed it a grid, */
/*     a form and AllowUpdateAPI -- an editable surface whose only use was winding the */
/*     counter backwards, after which numbers already in use get re-minted until */
/*     UQ_Contract_ContractNumber starts refusing saves one contract at a time with no */
/*     hint why. A SEQUENCE is not a table, so CodeGen never sees it: no entity, no */
/*     grid, nothing to protect. It is also atomic, which retires the HOLDLOCK/UPDLOCK */
/*     dance the old sproc needed. */
/* ------------------------------------------------------------------------- */
/* ------------------------------------------------------------------------- */
/* 3.6 Contract — the signed agreement. One row = one piece of signed (or */
/*     implied) paper, and the centre of the app. */
/*     CompanyID and CustomerOrganizationID are not the same kind of thing: */
/*     __mj.Company is OUR legal entity (which Blue Cypress company sells this), */
/*     Organization is the customer. CompanyID is not reliably derivable from the */
/*     deal, which is why it is stored. */
/*     CustomerOrganizationID is NOT NULL and there is no CustomerPersonID: the */
/*     individual case lives entirely in orders. "The contract layer is much more */
/*     the B2B scenario, not B2C." */
/*     CreatingEntityID + CreatingRecordID is the typed polymorphic pair naming */
/*     the record that CREATED this contract — in practice a Deal. A hard FK is */
/*     impossible by rule 2, and this is the pattern accounting uses for */
/*     JournalEntry provenance. Half the reference IS enforced: the entity FK. */
/*     NOTHING ABOUT A DOCUMENT IS REQUIRED TO SAVE A CONTRACT (ruled 2026-08-18). */
/*     There is no document column at all; files attach through */
/*     __mj.FileEntityRecordLink, and SigningProviderURL is the direct link to the */
/*     document in the signing provider. */
/*     ExecutedDate may legitimately PRECEDE EffectiveDate — sign in December for a */
/*     January start is the ordinary case, not an anomaly. v1 had a constraint */
/*     forbidding it and it rejected exactly the data a correct contract produces. */
/*     HasModifications is asserted by a person, not derived: its job is to say "go */
/*     read the PDF" BEFORE anyone has recorded the modifications. One direction IS */
/*     enforced, server-side — if modification rows exist the flag must be true — */
/*     and it is never cleared automatically (ERD §4.4). */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."Contract" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "ContractNumber" /* NULLABLE, and the server holds the invariant instead of the database. */ /* ContractEntityServer.Save() mints a number whenever the incoming value is null or */ /* blank, so the entity path never sends one. MJ has no way to declare "NOT NULL, */ /* assigned by the server on insert" (MJ#4001), and both available workarounds break */ /* creation in opposite directions: a DB DEFAULT makes CodeGen string-quote an */ /* EXPRESSION default into spCreateContract, which then fails to compile and is left */ /* DROPPED (MJ#4000); AllowUpdateAPI=0 silences the validator but omits the field from */ /* the insert payload, so the procedure fails on a missing @ContractNumber. */ /* UQ_Contract_ContractNumber below is PLAIN rather than filtered: SQL Server permits */ /* exactly one NULL, and a second un-numbered row is precisely what should be refused */ /* rather than accumulated. Ruled by Marcelo, 2026-08-21. */ VARCHAR(50) NULL,
  "ContractTypeID" UUID NOT NULL,
  "CompanyID" UUID NOT NULL,
  "CustomerOrganizationID" UUID NOT NULL,
  "PrimaryContactPersonID" UUID NULL,
  "ContractTemplateID" UUID NULL,
  "CreatingEntityID" UUID NULL,
  "CreatingRecordID" VARCHAR(450) NULL,
  "ParentContractID" UUID NULL,
  "SupersededByContractID" UUID NULL,
  "SigningProviderURL" VARCHAR(1000) NULL,
  "EffectiveDate" DATE NULL,
  "ExecutedDate" DATE NULL,
  "EndDate" DATE NULL,
  "TerminatedDate" DATE NULL,
  "AutoRenew" BOOLEAN NOT NULL DEFAULT FALSE,
  "RenewalNoticeDays" INT NULL,
  "CancellationWindowDays" INT NULL,
  "AnnualIncreasePercent" DECIMAL(7, 4) NULL,
  "HasModifications" BOOLEAN NOT NULL DEFAULT FALSE,
  "Description" TEXT NULL,
  "Notes" TEXT NULL,
  CONSTRAINT "PK_Contract" PRIMARY KEY ("ID"),
  CONSTRAINT "CK_Contract_CreatingPairBothOrNeither" CHECK ((
    "CreatingEntityID" IS NULL AND "CreatingRecordID" IS NULL
  )
  OR (
    NOT "CreatingEntityID" IS NULL AND NOT "CreatingRecordID" IS NULL
  )),
  CONSTRAINT "CK_Contract_ParentNotSelf" CHECK ("ParentContractID" IS NULL OR "ParentContractID" <> "ID"),
  CONSTRAINT "CK_Contract_SupersededNotSelf" CHECK ("SupersededByContractID" IS NULL OR "SupersededByContractID" <> "ID"),
  CONSTRAINT "CK_Contract_RenewalNoticeDays" CHECK ("RenewalNoticeDays" IS NULL OR "RenewalNoticeDays" >= 0),
  CONSTRAINT "CK_Contract_CancellationWindow" CHECK ("CancellationWindowDays" IS NULL OR "CancellationWindowDays" >= 0),
  CONSTRAINT "CK_Contract_AnnualIncrease" CHECK ("AnnualIncreasePercent" IS NULL OR "AnnualIncreasePercent" >= 0),
  CONSTRAINT "CK_Contract_Dates" CHECK ("EndDate" IS NULL OR "EffectiveDate" IS NULL OR "EndDate" >= "EffectiveDate")
);

CREATE UNIQUE INDEX "UQ_Contract_ContractNumber" ON "__mj_bizappscontracts"."Contract"("ContractNumber");

/* The polymorphic record id is not a foreign key, so it earns an index of its own: */
/* "which contract did this deal create" is the reverse lookup sales will run. */
CREATE INDEX "IX_Contract_CreatingRecord" ON "__mj_bizappscontracts"."Contract"("CreatingEntityID", "CreatingRecordID");

/* ------------------------------------------------------------------------- */
/* 3.7 ContractTemplateModification — what THIS contract changed about the */
/*     standard agreement. */
/*     Deliberately lean. It names a provision and carries what the contract says */
/*     instead; the standard wording sits on the provision row, and reading the two */
/*     as a pair is the point (D-16). */
/*     NO ContractTemplateID (R-16). The provision belongs to exactly one template */
/*     in every future, so Modification -> Provision -> Template derives it, and a */
/*     stored copy of a derivation can only agree or lie. What replaces it is the */
/*     rule that was always implicit and now lives server-side: a modification's */
/*     provision must belong to a template this contract incorporates. */
/* ------------------------------------------------------------------------- */
CREATE TABLE "__mj_bizappscontracts"."ContractTemplateModification" (
  "ID" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "ContractID" UUID NOT NULL,
  "ContractTemplateProvisionID" UUID NOT NULL,
  "ModificationText" TEXT NOT NULL,
  "Notes" TEXT NULL,
  CONSTRAINT "PK_ContractTemplateModification" PRIMARY KEY ("ID"),
  CONSTRAINT "UQ_ContractTemplateModification_Contract_Provision" UNIQUE (
    "ContractID",
    "ContractTemplateProvisionID"
  ),
  CONSTRAINT "CK_ContractTemplateModification_TextNotBlank" CHECK (length(btrim("ModificationText")) > 0)
);

ALTER TABLE "__mj_bizappscontracts"."ContractTemplate"
  ADD CONSTRAINT "FK_ContractTemplate_ContractTemplateType" FOREIGN KEY ("ContractTemplateTypeID") REFERENCES "__mj_bizappscontracts"."ContractTemplateType" (
    "ID"
  )
 /* ============================================================================= */ /* 4. FOREIGN KEYS */ /* ============================================================================= */ /* One ALTER per table per reference, which is the convention CodeGen's index */ /* generation expects. */ /* ------------------------------------------------------------------------- */ /* 4.1 Within __mj_bizappscontracts */ /* ------------------------------------------------------------------------- */;

ALTER TABLE "__mj_bizappscontracts"."ContractTemplateProvision"
  ADD CONSTRAINT "FK_ContractTemplateProvision_ContractTemplate" FOREIGN KEY ("ContractTemplateID") REFERENCES "__mj_bizappscontracts"."ContractTemplate" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_ContractType" FOREIGN KEY ("ContractTypeID") REFERENCES "__mj_bizappscontracts"."ContractType" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_ContractTemplate" FOREIGN KEY ("ContractTemplateID") REFERENCES "__mj_bizappscontracts"."ContractTemplate" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_ParentContract" FOREIGN KEY ("ParentContractID") REFERENCES "__mj_bizappscontracts"."Contract" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_SupersededByContract" FOREIGN KEY ("SupersededByContractID") REFERENCES "__mj_bizappscontracts"."Contract" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."ContractTemplateModification"
  ADD CONSTRAINT "FK_ContractTemplateModification_Contract" FOREIGN KEY ("ContractID") REFERENCES "__mj_bizappscontracts"."Contract" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."ContractTemplateModification"
  ADD CONSTRAINT "FK_ContractTemplateModification_ContractTemplateProvision" FOREIGN KEY ("ContractTemplateProvisionID") REFERENCES "__mj_bizappscontracts"."ContractTemplateProvision" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_Company" FOREIGN KEY ("CompanyID") REFERENCES "__mj"."Company" (
    "ID"
  )
 /* ------------------------------------------------------------------------- */ /* 4.A CROSS-APP FOREIGN KEYS — real constraints, not soft UUID columns. */ /*     FOUR of them, down from thirteen in v1: everything pointing at orders left */ /*     with ContractLine and ContractBillingEvent, accounting's Currency left with */ /*     ContractTerm, and tasks' Task left with ContractAmendment. Contracts no */ /*     longer references orders, accounting or tasks at all. */ /*     These schemas MUST exist — MJ core and BizAppsCommon migrations run first — */ /*     which the dependency declaration in mj-app.json guarantees. */ /* ------------------------------------------------------------------------- */;

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_CustomerOrganization" FOREIGN KEY ("CustomerOrganizationID") REFERENCES "__mj_bizappscommon"."Organization" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_PrimaryContactPerson" FOREIGN KEY ("PrimaryContactPersonID") REFERENCES "__mj_bizappscommon"."Person" (
    "ID"
  );

ALTER TABLE "__mj_bizappscontracts"."Contract"
  ADD CONSTRAINT "FK_Contract_CreatingEntity" FOREIGN KEY ("CreatingEntityID") REFERENCES "__mj"."Entity" (
    "ID"
  )
 /* Half of the polymorphic pair, and the half worth enforcing: it says WHAT KIND of */ /* record CreatingRecordID points at, which is what lets MJ resolve the pair */ /* generically without contracts knowing what a Deal is. */;

COMMENT ON TABLE __mj_bizappscontracts."ContractTemplateType" IS 'The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateType"."Status" IS 'Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.';

COMMENT ON TABLE __mj_bizappscontracts."ContractTemplate" IS 'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplate"."VersionLabel" IS 'The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplate"."IntroducedDate" IS 'When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplate"."SourceURL" IS 'The dated public URL a customer can open to read the standard terms. NULLABLE: reachability is enforceable by nothing (a well-formed dead link passes any format check), and the real rule is "a URL OR an attached file" — the file half attaching through __mj.FileEntityRecordLink, which cannot reference a record that does not exist yet, so on CREATE it is unsatisfiable in principle. A template with neither is INCOMPLETE rather than invalid; the derived IsUsable column on vwContractTemplates is what says so.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplate"."Status" IS 'Publication lifecycle. ''Draft'' -- freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. ''Published'' -- the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version -- that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.';

COMMENT ON TABLE __mj_bizappscontracts."ContractTemplateProvision" IS 'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateProvision"."ProvisionNumber" IS 'The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateProvision"."Title" IS 'The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateProvision"."ProvisionText" IS 'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateProvision"."ProvisionSortKey" IS 'Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order (''1.9'' before ''1.10''), which ordering by ProvisionNumber cannot. READ-ONLY -- a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.';

COMMENT ON TABLE __mj_bizappscontracts."ContractType" IS 'The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."RequiresExecutedDocument" IS 'Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."Status" IS 'Active | Inactive.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."MustBeRoot" IS 'This type of contract may NOT name a ParentContractID -- it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."MustBeChild" IS 'This type of contract MUST name a ParentContractID -- a Change Order that amends nothing is not a change order, and would never appear in the original agreement''s lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."TemplateRequired" IS 'This type of contract must carry its own ContractTemplateID -- the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because ''where in the tree'' and ''does it need its own paper'' are different questions and a future type could want any combination.';

COMMENT ON TABLE __mj_bizappscontracts."Contract" IS 'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."ContractNumber" IS 'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express ''NOT NULL, assigned by the server on insert'' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be ''fixed'': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CompanyID" IS 'The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CustomerOrganizationID" IS 'The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."PrimaryContactPersonID" IS 'Their named contact, optional.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."ContractTemplateID" IS 'The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CreatingEntityID" IS 'Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CreatingRecordID" IS 'Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."ParentContractID" IS 'The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."SupersededByContractID" IS 'The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."SigningProviderURL" IS 'Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."EffectiveDate" IS 'When the agreement takes effect.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."ExecutedDate" IS 'When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."EndDate" IS 'When the current term ends. This is what drives the renewal watchlist and every expiry projection.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."TerminatedDate" IS 'When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."AutoRenew" IS 'Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."RenewalNoticeDays" IS 'Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."CancellationWindowDays" IS 'Days of notice the customer owes to cancel without renewing.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."AnnualIncreasePercent" IS 'The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."HasModifications" IS 'Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.';

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."Notes" IS 'Free-text working notes for whoever is processing the contract.';

COMMENT ON TABLE __mj_bizappscontracts."ContractTemplateModification" IS 'What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateModification"."ContractTemplateProvisionID" IS 'The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateModification"."ModificationText" IS 'What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractTemplateModification"."Notes" IS 'Optional working note, e.g. who negotiated it.';

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Types */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
    'MJ_BizApps_Contracts: Contract Template Types',
    'Contract Template Types',
    'The kind of standard agreement (Master Agreement, Statement of Work). A lookup TABLE rather than a CHECK because the list is additive at runtime and a business user should be able to add one without a migration. Carries no behaviour.',
    NULL,
    'ContractTemplateType',
    'vwContractTemplateTypes',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to create new application __mj_bizappscontracts */;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."Application" WHERE "ID" = '891e92fe-561a-4fed-8edc-e2d96fb18541') THEN
    INSERT INTO "__mj"."Application" ("ID", "Name", "Description", "SchemaAutoAddNewEntities", "Path", "AutoUpdatePath", "DefaultForNewUser") VALUES ('891e92fe-561a-4fed-8edc-e2d96fb18541', '__mj_bizappscontracts', 'Generated for schema', '__mj_bizappscontracts', 'mjbizappscontracts', TRUE, FALSE);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."ApplicationRole" WHERE "ApplicationID" = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND "RoleID" = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E') THEN
    INSERT INTO "__mj"."ApplicationRole" ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, FALSE);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."ApplicationRole" WHERE "ApplicationID" = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND "RoleID" = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E') THEN
    INSERT INTO "__mj"."ApplicationRole" ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, TRUE);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."ApplicationRole" WHERE "ApplicationID" = '891e92fe-561a-4fed-8edc-e2d96fb18541' AND "RoleID" = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E') THEN
    INSERT INTO "__mj"."ApplicationRole" ("ApplicationID", "RoleID", "CanAccess", "CanAdmin") VALUES ('891e92fe-561a-4fed-8edc-e2d96fb18541', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', TRUE, FALSE);
  END IF;
END $$;

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Types to application ID: '891e92fe-561a-4fed-8edc-e2d96fb18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891e92fe-561a-4fed-8edc-e2d96fb18541',
    '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891e92fe-561a-4fed-8edc-e2d96fb18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Types for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '4e3f97be-e196-4cc0-9b5d-cc50de8967a0',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Templates */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '731f2890-1415-40de-9073-d22ea23392b3',
    'MJ_BizApps_Contracts: Contract Templates',
    'Contract Templates',
    'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.',
    NULL,
    'ContractTemplate',
    'vwContractTemplates',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Templates to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891E92FE-561A-4FED-8EDC-E2D96FB18541',
    '731f2890-1415-40de-9073-d22ea23392b3',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '731f2890-1415-40de-9073-d22ea23392b3',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '731f2890-1415-40de-9073-d22ea23392b3',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Templates for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '731f2890-1415-40de-9073-d22ea23392b3',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Provisions */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '317df592-8c20-473d-b097-2ab239877438',
    'MJ_BizApps_Contracts: Contract Template Provisions',
    'Contract Template Provisions',
    'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.',
    NULL,
    'ContractTemplateProvision',
    'vwContractTemplateProvisions',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Provisions to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891E92FE-561A-4FED-8EDC-E2D96FB18541',
    '317df592-8c20-473d-b097-2ab239877438',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '317df592-8c20-473d-b097-2ab239877438',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '317df592-8c20-473d-b097-2ab239877438',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Provisions for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '317df592-8c20-473d-b097-2ab239877438',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Types */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'c8909a57-6ddb-4585-be00-e707c5b4f262',
    'MJ_BizApps_Contracts: Contract Types',
    'Contract Types',
    'The kind of paper: Order Form, Statement of Work, Payment Link, Change Order. A lookup TABLE for the same reason as ContractTemplateType.',
    NULL,
    'ContractType',
    'vwContractTypes',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Types to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891E92FE-561A-4FED-8EDC-E2D96FB18541',
    'c8909a57-6ddb-4585-be00-e707c5b4f262',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'c8909a57-6ddb-4585-be00-e707c5b4f262',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'c8909a57-6ddb-4585-be00-e707c5b4f262',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'c8909a57-6ddb-4585-be00-e707c5b4f262',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to create new entity MJ_BizApps_Contracts: Contracts */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
    'MJ_BizApps_Contracts: Contracts',
    'Contracts',
    'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.',
    NULL,
    'Contract',
    'vwContracts',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to add new entity MJ_BizApps_Contracts: Contracts to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891E92FE-561A-4FED-8EDC-E2D96FB18541',
    '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '5deb0b11-ed6c-48b3-9200-f4441396c5e2',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Template Modifications */
INSERT INTO "__mj"."Entity" (
  "ID",
  "Name",
  "DisplayName",
  "Description",
  "NameSuffix",
  "BaseTable",
  "BaseView",
  "SchemaName",
  "IncludeInAPI",
  "AllowUserSearchAPI",
  "AllowCaching",
  "TrackRecordChanges",
  "AuditRecordAccess",
  "AuditViewRuns",
  "AllowAllRowsAPI",
  "AllowCreateAPI",
  "AllowUpdateAPI",
  "AllowDeleteAPI",
  "UserViewMaxRows",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
    'MJ_BizApps_Contracts: Contract Template Modifications',
    'Contract Template Modifications',
    'What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.',
    NULL,
    'ContractTemplateModification',
    'vwContractTemplateModifications',
    '__mj_bizappscontracts',
    TRUE,
    TRUE,
    FALSE,
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    TRUE,
    TRUE,
    TRUE,
    1000,
    NOW(),
    NOW()
  );
/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Template Modifications to application ID: '891E92FE-561A-4FED-8EDC-E2D96FB18541' */
INSERT INTO "__mj"."ApplicationEntity" (
  "ApplicationID",
  "EntityID",
  "Sequence",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '891E92FE-561A-4FED-8EDC-E2D96FB18541',
    'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
    (
      SELECT
        COALESCE(MAX("Sequence"), 0) + 1
      FROM "__mj"."ApplicationEntity"
      WHERE
        "ApplicationID" = '891E92FE-561A-4FED-8EDC-E2D96FB18541'
    ),
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role UI */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
    'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    FALSE,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Developer */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
    'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Template Modifications for role Integration */
INSERT INTO "__mj"."EntityPermission" (
  "EntityID",
  "RoleID",
  "CanRead",
  "CanCreate",
  "CanUpdate",
  "CanDelete",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'b05a480f-f7c5-4d45-8ea3-c90e9a14f225',
    'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E',
    TRUE,
    TRUE,
    TRUE,
    TRUE,
    NOW(),
    NOW()
  );
/* SQL text to update existing entities from schema */
SELECT
  "__mj"."spUpdateExistingEntitiesFromSchema"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateProvision */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateProvision */
UPDATE __mj_bizappscontracts."ContractTemplateProvision" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateProvision' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateProvision */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateProvision */
UPDATE __mj_bizappscontracts."ContractTemplateProvision" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateProvision' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateProvision" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplateModification"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateModification */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateModification */
UPDATE __mj_bizappscontracts."ContractTemplateModification" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateModification' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateModification" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateModification" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplateModification"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateModification */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateModification */
UPDATE __mj_bizappscontracts."ContractTemplateModification" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateModification' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateModification" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateModification" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplateType"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateType */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplateType */
UPDATE __mj_bizappscontracts."ContractTemplateType" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateType' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateType" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateType" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplateType"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateType */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplateType */
UPDATE __mj_bizappscontracts."ContractTemplateType" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplateType' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplateType" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplateType" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplate"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplate */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractTemplate */
UPDATE __mj_bizappscontracts."ContractTemplate" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplate' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplate" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplate" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractTemplate"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplate */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractTemplate */
UPDATE __mj_bizappscontracts."ContractTemplate" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractTemplate' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractTemplate" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractTemplate" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractType"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractType */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.ContractType */
UPDATE __mj_bizappscontracts."ContractType" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractType' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractType" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractType" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."ContractType"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractType */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.ContractType */
UPDATE __mj_bizappscontracts."ContractType" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'ContractType' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."ContractType" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."ContractType" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."Contract"
ADD COLUMN "__mj_CreatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.Contract */;

/* SQL text to add special date field __mj_CreatedAt to entity __mj_bizappscontracts.Contract */
UPDATE __mj_bizappscontracts."Contract" SET "__mj_CreatedAt" = NOW()
WHERE
  "__mj_CreatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'Contract' AND a.attname = '__mj_CreatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."Contract" ALTER COLUMN "__mj_CreatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_CreatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."Contract" ALTER COLUMN "__mj_CreatedAt" SET DEFAULT NOW();

ALTER TABLE __mj_bizappscontracts."Contract"
ADD COLUMN "__mj_UpdatedAt" TIMESTAMPTZ NULL /* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.Contract */;

/* SQL text to add special date field __mj_UpdatedAt to entity __mj_bizappscontracts.Contract */
UPDATE __mj_bizappscontracts."Contract" SET "__mj_UpdatedAt" = NOW()
WHERE
  "__mj_UpdatedAt" IS NULL;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT ns.nspname AS sch, dv.relname AS vw
    FROM pg_depend d
    JOIN pg_rewrite rw ON rw.oid = d.objid
    JOIN pg_class dv ON dv.oid = rw.ev_class AND dv.relkind = 'v'
    JOIN pg_namespace ns ON ns.oid = dv.relnamespace
    JOIN pg_class tc ON tc.oid = d.refobjid
    JOIN pg_attribute a ON a.attrelid = tc.oid AND a.attnum = d.refobjsubid
    WHERE tc.relname = 'Contract' AND a.attname = '__mj_UpdatedAt'
  LOOP
    EXECUTE format('DROP VIEW IF EXISTS %I.%I CASCADE', r.sch, r.vw);
  END LOOP;
END $$;
ALTER TABLE __mj_bizappscontracts."Contract" ALTER COLUMN "__mj_UpdatedAt" TYPE TIMESTAMPTZ, ALTER COLUMN "__mj_UpdatedAt" SET NOT NULL;

ALTER TABLE __mj_bizappscontracts."Contract" ALTER COLUMN "__mj_UpdatedAt" SET DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'da55d974-f70e-42d0-a12a-04f2efd46a85' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('da55d974-f70e-42d0-a12a-04f2efd46a85', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'fd673fee-72ab-4109-89b1-db5bcee9eb3e' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ContractTemplateID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('fd673fee-72ab-4109-89b1-db5bcee9eb3e', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 2, 'ContractTemplateID', 'Contract Template ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, '731F2890-1415-40DE-9073-D22EA23392B3', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'cfb7315f-8759-4728-bd30-faae93f97106' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ProvisionNumber')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('cfb7315f-8759-4728-bd30-faae93f97106', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 3, 'ProvisionNumber', 'Provision Number', 'The clause number as the document writes it, e.g. "3.5(b)". Unique within its template.', 'nvarchar', 40, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'ce9ce69a-95cf-4cf0-bda8-f5f5e661a40b' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'Title')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('ce9ce69a-95cf-4cf0-bda8-f5f5e661a40b', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 4, 'Title', 'Title', 'The clause heading, e.g. "Limitation of Liability". This plus the number is what a person picks from.', 'nvarchar', 400, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd2cd9029-4db4-4ad1-85a2-abbfda35eafd' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ProvisionText')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d2cd9029-4db4-4ad1-85a2-abbfda35eafd', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 5, 'ProvisionText', 'Provision Text', 'The STANDARD wording of this clause. Read as a pair with ContractTemplateModification.ModificationText, which holds what a given contract says instead — a dispute needs the comparison, not either half.', 'nvarchar', -1, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '1bfda475-470f-4f3c-8b5d-b0dbdced2ee3' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'Description')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('1bfda475-470f-4f3c-8b5d-b0dbdced2ee3', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 6, 'Description', 'Description', NULL, 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '2e082ebc-4a00-4c39-8f6d-f7b680f5b345' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ProvisionSortKey')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('2e082ebc-4a00-4c39-8f6d-f7b680f5b345', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 7, 'ProvisionSortKey', 'Provision Sort Key', 'Collation key derived from ProvisionNumber: every run of digits zero-padded to six places, everything else upper-cased. Makes a plain SQL ORDER BY produce natural order (''1.9'' before ''1.10''), which ordering by ProvisionNumber cannot. READ-ONLY -- a persisted computed column; nobody should be able to set a sort key. Replaced the hand-maintained Sequence column, which had already collided in the seeded data.', 'nvarchar', 400, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, TRUE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '6b098c7f-9119-4c60-94b5-ca2aca14309f' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('6b098c7f-9119-4c60-94b5-ca2aca14309f', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 8, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '9f515edd-be69-4955-9c10-eb1819ddfd2c' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('9f515edd-be69-4955-9c10-eb1819ddfd2c', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 9, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '4796bc59-bf1a-41cf-83b5-29e8f8880c47' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('4796bc59-bf1a-41cf-83b5-29e8f8880c47', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '982e307b-667c-4955-99de-f9a96fab2cb2' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ContractID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('982e307b-667c-4955-99de-f9a96fab2cb2', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 2, 'ContractID', 'Contract ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0864cb7f-e532-402f-9f16-102ec14993c6' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ContractTemplateProvisionID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0864cb7f-e532-402f-9f16-102ec14993c6', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 3, 'ContractTemplateProvisionID', 'Contract Template Provision ID', 'The provision being modified — the structured identifier, and the only one. A server rule enforces what this replaces: the provision must belong to a template this contract incorporates.', 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, '317DF592-8C20-473D-B097-2AB239877438', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0d2fc779-82ca-4d68-a711-3d871a356164' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ModificationText')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0d2fc779-82ca-4d68-a711-3d871a356164', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 4, 'ModificationText', 'Modification Text', 'What this contract says INSTEAD of the standard clause. Read as a pair with ContractTemplateProvision.ProvisionText.', 'nvarchar', -1, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '87bb27cb-98b7-4704-bdc5-7871f8f394eb' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'Notes')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('87bb27cb-98b7-4704-bdc5-7871f8f394eb', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 5, 'Notes', 'Notes', 'Optional working note, e.g. who negotiated it.', 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '18518499-1dd3-4369-bd76-59b62eeba5b8' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('18518499-1dd3-4369-bd76-59b62eeba5b8', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 6, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '54072096-c4e2-450c-97fa-bf162e2485d6' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('54072096-c4e2-450c-97fa-bf162e2485d6', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 7, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'b592f895-7e87-480a-8663-9d3c70f812d5' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('b592f895-7e87-480a-8663-9d3c70f812d5', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'eece216e-ec2b-4630-9e17-3fcde668f32a' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = 'Name')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('eece216e-ec2b-4630-9e17-3fcde668f32a', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 2, 'Name', 'Name', NULL, 'nvarchar', 200, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '3ec31ca1-a410-4a25-bb23-1e668a16a125' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = 'Description')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('3ec31ca1-a410-4a25-bb23-1e668a16a125', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 3, 'Description', 'Description', NULL, 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0e2ab42b-29f2-4151-a424-aba78bba163b' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = 'Status')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0e2ab42b-29f2-4151-a424-aba78bba163b', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 4, 'Status', 'Status', 'Active | Inactive. Retiring a type hides it from pickers without touching the templates that used it.', 'nvarchar', 20, 0, 0, FALSE, 'Active', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'e7d55020-c93e-46b9-89e5-19088cbedb0a' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e7d55020-c93e-46b9-89e5-19088cbedb0a', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 5, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '26168480-7c59-4436-b954-4979f44f7014' OR ("EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('26168480-7c59-4436-b954-4979f44f7014', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0' /* Entity: MJ_BizApps_Contracts: Contract Template Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0') + 6, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'a8bf5461-4a41-4388-8761-50b79fc598b4' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('a8bf5461-4a41-4388-8761-50b79fc598b4', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '1fc39118-f7f8-4ba7-9940-f341e35f4fdb' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'Name')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('1fc39118-f7f8-4ba7-9940-f341e35f4fdb', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 2, 'Name', 'Name', NULL, 'nvarchar', 400, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '7b8ec82e-cf52-4f4c-980d-47a15194ea12' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'ContractTemplateTypeID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('7b8ec82e-cf52-4f4c-980d-47a15194ea12', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 3, 'ContractTemplateTypeID', 'Contract Template Type ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd4e48fff-2f10-4e2e-a036-4d98bdafca99' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'VersionLabel')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d4e48fff-2f10-4e2e-a036-4d98bdafca99', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 4, 'VersionLabel', 'Version Label', 'The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.', 'nvarchar', 100, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd20b1f02-4f4b-4a8e-894d-4d74f32a6282' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'IntroducedDate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d20b1f02-4f4b-4a8e-894d-4d74f32a6282', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 5, 'IntroducedDate', 'Introduced Date', 'When this version started being offered. NOT an effective date: a template becomes effective for a customer when THAT customer signs it, never on a calendar date. Naming it EffectiveDate would invite exactly the wrong query.', 'date', 3, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '5f27fb9a-a089-46ce-a332-f7e7de745bcf' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'SourceURL')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('5f27fb9a-a089-46ce-a332-f7e7de745bcf', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 6, 'SourceURL', 'Source URL', 'The dated public URL a customer can open to read the standard terms. NULLABLE: reachability is enforceable by nothing (a well-formed dead link passes any format check), and the real rule is "a URL OR an attached file" — the file half attaching through __mj.FileEntityRecordLink, which cannot reference a record that does not exist yet, so on CREATE it is unsatisfiable in principle. A template with neither is INCOMPLETE rather than invalid; the derived IsUsable column on vwContractTemplates is what says so.', 'nvarchar', 2000, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '7f9a6927-ca1d-441b-9682-7035c95393d8' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'Description')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('7f9a6927-ca1d-441b-9682-7035c95393d8', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 7, 'Description', 'Description', NULL, 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'e84e1c35-41c9-4a59-8ad2-6d426fdb7e6b' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'Status')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e84e1c35-41c9-4a59-8ad2-6d426fdb7e6b', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 8, 'Status', 'Status', 'Publication lifecycle. ''Draft'' -- freely editable, provisions may be added, changed and removed, and a contract may not NEWLY reference it. ''Published'' -- the provisions are frozen against INSERT, UPDATE and DELETE by trg_ContractTemplateProvision_Immutability, and contracts may reference it. Publishing is ONE-WAY (enforced in ContractTemplateEntity): to change published terms, publish a new version -- that is what VersionLabel exists for. Existing references are never invalidated by this column; only new ones are policed, the same way ContractType.Status works.', 'nvarchar', 40, 0, 0, FALSE, 'Draft', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'e586db3a-8fca-424f-bb0f-ae34be10c686' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e586db3a-8fca-424f-bb0f-ae34be10c686', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 9, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'b0e8e57c-69a5-4a3f-bad2-ccbf75f2ff30' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('b0e8e57c-69a5-4a3f-bad2-ccbf75f2ff30', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 10, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '9c8643d3-2b82-41a6-80f6-d29abb68d1cb' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('9c8643d3-2b82-41a6-80f6-d29abb68d1cb', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '84119ad2-cba8-466b-b20a-8a94c20fce3f' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'Name')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('84119ad2-cba8-466b-b20a-8a94c20fce3f', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 2, 'Name', 'Name', NULL, 'nvarchar', 200, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, TRUE, TRUE, FALSE, TRUE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '46b195b4-ea25-41a4-bb78-83b2014a930c' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'Description')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('46b195b4-ea25-41a4-bb78-83b2014a930c', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 3, 'Description', 'Description', NULL, 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '62afa042-4658-4d78-b9c3-1bdd0b3997d4' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'RequiresExecutedDocument')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('62afa042-4658-4d78-b9c3-1bdd0b3997d4', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 4, 'RequiresExecutedDocument', 'Requires Executed Document', 'Whether paper is ever expected for this kind of contract. No for a Payment Link, which has an implied agreement and no signature. This is what stops such a contract asking forever for a document that will never arrive: "awaiting the document" is DERIVED as requires-it AND no-linked-file, never stored and never a status value.', 'bit', 1, 1, 0, FALSE, '(1)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '59601a28-9aed-4e62-8b3b-ea21b769b9eb' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'Status')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('59601a28-9aed-4e62-8b3b-ea21b769b9eb', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 5, 'Status', 'Status', 'Active | Inactive.', 'nvarchar', 20, 0, 0, FALSE, 'Active', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd252cc6d-3196-4616-aaef-93ffc7ce6887' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'MustBeRoot')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d252cc6d-3196-4616-aaef-93ffc7ce6887', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 6, 'MustBeRoot', 'Must Be Root', 'This type of contract may NOT name a ParentContractID -- it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '04ba23cd-ec7a-495b-81df-47474ef8c0eb' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'MustBeChild')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('04ba23cd-ec7a-495b-81df-47474ef8c0eb', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 7, 'MustBeChild', 'Must Be Child', 'This type of contract MUST name a ParentContractID -- a Change Order that amends nothing is not a change order, and would never appear in the original agreement''s lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '444fc85a-bd7a-4967-8633-a4e1f8acb4ce' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'TemplateRequired')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('444fc85a-bd7a-4967-8633-a4e1f8acb4ce', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 8, 'TemplateRequired', 'Template Required', 'This type of contract must carry its own ContractTemplateID -- the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because ''where in the tree'' and ''does it need its own paper'' are different questions and a future type could want any combination.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '6a869a40-c89a-43f5-bc80-94a104e9fc46' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('6a869a40-c89a-43f5-bc80-94a104e9fc46', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 9, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '68821111-317c-4ab8-922e-f1ec8aea0973' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('68821111-317c-4ab8-922e-f1ec8aea0973', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262') + 10, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '04e8aa9d-c2dc-489d-b081-75c4e6ddfa6b' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('04e8aa9d-c2dc-489d-b081-75c4e6ddfa6b', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 1, 'ID', 'ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, 'newsequentialid()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, TRUE, FALSE, FALSE, TRUE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '8677055b-2482-4250-98c1-afc3dae57393' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ContractNumber')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('8677055b-2482-4250-98c1-afc3dae57393', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 2, 'ContractNumber', 'Contract Number', 'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express ''NOT NULL, assigned by the server on insert'' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be ''fixed'': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.', 'nvarchar', 100, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'df26a6b1-eb6c-42d8-b236-cd13f58c9b78' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ContractTypeID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('df26a6b1-eb6c-42d8-b236-cd13f58c9b78', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 3, 'ContractTypeID', 'Contract Type ID', NULL, 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CompanyID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 4, 'CompanyID', 'Company ID', 'The SELLING company (__mj.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.', 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, 'D4238F34-2837-EF11-86D4-6045BDEE16E6', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'f11c9543-f483-4bed-a9ce-3e7659d24011' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CustomerOrganizationID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('f11c9543-f483-4bed-a9ce-3e7659d24011', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 5, 'CustomerOrganizationID', 'Customer Organization ID', 'The customer. NOT NULL: contracts are B2B here by definition, and the individual case lives entirely in orders. v1 allowed an organization-or-person XOR; that is gone.', 'uniqueidentifier', 16, 0, 0, FALSE, NULL, FALSE, TRUE, FALSE, FALSE, 'C70448F9-9792-41D7-A82C-784B66429D54', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd47233ed-0ebf-4329-b270-99f70589cd7f' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'PrimaryContactPersonID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d47233ed-0ebf-4329-b270-99f70589cd7f', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 6, 'PrimaryContactPersonID', 'Primary Contact Person ID', 'Their named contact, optional.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ContractTemplateID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 7, 'ContractTemplateID', 'Contract Template ID', 'The agreement version this contract incorporates. Nullable because a contract created automatically at Closed Won has none until finance reads the PDF.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, '731F2890-1415-40DE-9073-D22EA23392B3', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '316a9f07-54f1-4038-862a-c25a2084f274' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CreatingEntityID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('316a9f07-54f1-4038-862a-c25a2084f274', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 8, 'CreatingEntityID', 'Creating Entity ID', 'Polymorphic reference part 1: the MJ Entity of the record that CREATED this contract, in practice Deals. A real foreign key to __mj.Entity — this is the half that is enforced, and the half that lets MJ resolve the pair generically. Same pattern accounting uses for JournalEntry provenance.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, 'E0238F34-2837-EF11-86D4-6045BDEE16E6', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '611650f5-bfc3-4809-b9b1-80ac9979b450' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CreatingRecordID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('611650f5-bfc3-4809-b9b1-80ac9979b450', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 9, 'CreatingRecordID', 'Creating Record ID', 'Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.', 'nvarchar', 900, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '6db0692a-42cd-4ac5-a43b-49ecc81ef370' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ParentContractID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('6db0692a-42cd-4ac5-a43b-49ecc81ef370', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 10, 'ParentContractID', 'Parent Contract ID', 'The contract this one amends. How a change order attaches: a change order is signed paper with its own PDF, dates and modifications, so it reuses this entity rather than getting one of its own. The original stays in force.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '44bc44ef-a6f2-4630-a899-487ce0e3cc56' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'SupersededByContractID')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('44bc44ef-a6f2-4630-a899-487ce0e3cc56', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 11, 'SupersededByContractID', 'Superseded By Contract ID', 'The contract that REPLACED this one, where an agreement was re-papered rather than amended. Also the sole source of the derived Superseded state, which is why the old CHECK tying it to a Status column disappeared with that column.', 'uniqueidentifier', 16, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ID', FALSE, FALSE, TRUE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '131ce82f-ac93-4dcf-95c0-3ea4fc681c2c' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'SigningProviderURL')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('131ce82f-ac93-4dcf-95c0-3ea4fc681c2c', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 12, 'SigningProviderURL', 'Signing Provider URL', 'Direct link to the document in the signing provider (PandaDoc). The fallback that works before any integration exists, and when a storage sync has broken.', 'nvarchar', 2000, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '5605ab79-a11a-4561-8b34-b7567a36f27a' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'EffectiveDate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('5605ab79-a11a-4561-8b34-b7567a36f27a', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 13, 'EffectiveDate', 'Effective Date', 'When the agreement takes effect.', 'date', 3, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '9ed4a8cc-e0b8-4880-945a-4bd6dd6368c6' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ExecutedDate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('9ed4a8cc-e0b8-4880-945a-4bd6dd6368c6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 14, 'ExecutedDate', 'Executed Date', 'When it was signed. May legitimately PRECEDE EffectiveDate — sign in December for a January start is the ordinary case. There is deliberately no constraint ordering the two; v1 had one and it rejected exactly the data a correct contract produces.', 'date', 3, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '343becbd-079b-443a-998c-2e7ddccd8a01' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'EndDate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('343becbd-079b-443a-998c-2e7ddccd8a01', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 15, 'EndDate', 'End Date', 'When the current term ends. This is what drives the renewal watchlist and every expiry projection.', 'date', 3, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd312f0c4-ad4d-4f0b-b54a-1051ec735464' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'TerminatedDate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d312f0c4-ad4d-4f0b-b54a-1051ec735464', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 16, 'TerminatedDate', 'Terminated Date', 'When the agreement ended early. Stored rather than derived: it is only recoverable from a successors effective date, and a contract can end with no successor at all when a customer simply leaves.', 'date', 3, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '8b3c517c-ff01-4121-a740-632df75f3c05' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'AutoRenew')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('8b3c517c-ff01-4121-a740-632df75f3c05', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 17, 'AutoRenew', 'Auto Renew', 'Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '573064ac-38a8-42a2-95b2-ccbd605004ea' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'RenewalNoticeDays')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('573064ac-38a8-42a2-95b2-ccbd605004ea', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 18, 'RenewalNoticeDays', 'Renewal Notice Days', 'Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.', 'int', 4, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'c6464adc-6683-4d4b-aa7a-64f9e052d225' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CancellationWindowDays')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('c6464adc-6683-4d4b-aa7a-64f9e052d225', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 19, 'CancellationWindowDays', 'Cancellation Window Days', 'Days of notice the customer owes to cancel without renewing.', 'int', 4, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '3b2625e1-c5ab-462c-aa7e-533c5f40646d' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'AnnualIncreasePercent')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('3b2625e1-c5ab-462c-aa7e-533c5f40646d', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 20, 'AnnualIncreasePercent', 'Annual Increase Percent', 'The negotiated year-over-year uplift. Exists here because it exists nowhere else: the orders schema has no escalation concept of any kind, which is why a two-year agreement stepping up 10% in year two is recorded in no other system.', 'decimal', 5, 7, 4, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'd54ddebd-615b-4d29-a995-246c3c0f7408' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'HasModifications')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('d54ddebd-615b-4d29-a995-246c3c0f7408', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 21, 'HasModifications', 'Has Modifications', 'Whether the standard agreement was changed for this customer. ASSERTED by a person, not derived — its job is to say "go read the PDF" BEFORE anyone has recorded the modifications, and a derived flag would read false for every contract nobody has processed yet. One direction IS enforced server-side: if modification rows exist this must be true. It is never cleared automatically.', 'bit', 1, 1, 0, FALSE, '(0)', FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '30b733e2-70e1-4d55-ba83-73fedba848fa' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'Description')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('30b733e2-70e1-4d55-ba83-73fedba848fa', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 22, 'Description', 'Description', NULL, 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '68e70227-d818-4f11-8fe4-553f5c84be53' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'Notes')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('68e70227-d818-4f11-8fe4-553f5c84be53', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 23, 'Notes', 'Notes', 'Free-text working notes for whoever is processing the contract.', 'nvarchar', -1, 0, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '7c14348e-69de-4f66-b62c-99c0a7e415af' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = '__mj_CreatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('7c14348e-69de-4f66-b62c-99c0a7e415af', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 24, '__mj_CreatedAt', 'Created At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0eba35ec-fb3d-4978-8650-fc6229a9180e' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = '__mj_UpdatedAt')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0eba35ec-fb3d-4978-8650-fc6229a9180e', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 25, '__mj_UpdatedAt', 'Updated At', NULL, 'datetimeoffset', 10, 34, 7, FALSE, 'getutcdate()', FALSE, FALSE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* SQL text to update existing entity fields from schema */
SELECT
  "__mj"."spUpdateExistingEntityFieldsFromSchema"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to set default column width where needed */
SELECT
  "__mj"."spSetDefaultColumnWidthWhereNeeded"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to insert entity field value with ID 217e9e49-0b4f-44c1-9f68-035f69e7a7bd */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '217e9e49-0b4f-44c1-9f68-035f69e7a7bd',
    '0E2AB42B-29F2-4151-A424-ABA78BBA163B',
    1,
    'Active',
    'Active',
    NOW(),
    NOW()
  );
/* SQL text to insert entity field value with ID 3ba9d65c-2cc4-4b0b-9be7-376aaab7234b */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '3ba9d65c-2cc4-4b0b-9be7-376aaab7234b',
    '0E2AB42B-29F2-4151-A424-ABA78BBA163B',
    2,
    'Inactive',
    'Inactive',
    NOW(),
    NOW()
  );
/* SQL text to update ValueListType for entity field ID 0E2AB42B-29F2-4151-A424-ABA78BBA163B */
UPDATE "__mj"."EntityField" SET "ValueListType" = 'List'
WHERE
  "ID" = '0E2AB42B-29F2-4151-A424-ABA78BBA163B';
/* SQL text to insert entity field value with ID 0b3ec358-4aec-4e2c-9361-94626326c8d6 */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '0b3ec358-4aec-4e2c-9361-94626326c8d6',
    'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B',
    1,
    'Draft',
    'Draft',
    NOW(),
    NOW()
  );
/* SQL text to insert entity field value with ID ad6ada75-99df-45c1-b852-5c3aebaf6220 */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    'ad6ada75-99df-45c1-b852-5c3aebaf6220',
    'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B',
    2,
    'Published',
    'Published',
    NOW(),
    NOW()
  );
/* SQL text to update ValueListType for entity field ID E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B */
UPDATE "__mj"."EntityField" SET "ValueListType" = 'List'
WHERE
  "ID" = 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B';
/* SQL text to insert entity field value with ID 6b1d3830-0e26-4457-b945-b8c05221c54e */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '6b1d3830-0e26-4457-b945-b8c05221c54e',
    '59601A28-9AED-4E62-8B3B-EA21B769B9EB',
    1,
    'Active',
    'Active',
    NOW(),
    NOW()
  );
/* SQL text to insert entity field value with ID 39fba98a-d6e1-4f28-bb74-5f40e0e43f3f */
INSERT INTO "__mj"."EntityFieldValue" (
  "ID",
  "EntityFieldID",
  "Sequence",
  "Value",
  "Code",
  "__mj_CreatedAt",
  "__mj_UpdatedAt"
)
VALUES
  (
    '39fba98a-d6e1-4f28-bb74-5f40e0e43f3f',
    '59601A28-9AED-4E62-8B3B-EA21B769B9EB',
    2,
    'Inactive',
    'Inactive',
    NOW(),
    NOW()
  );
/* SQL text to update ValueListType for entity field ID 59601A28-9AED-4E62-8B3B-EA21B769B9EB */
UPDATE "__mj"."EntityField" SET "ValueListType" = 'List'
WHERE
  "ID" = '59601A28-9AED-4E62-8B3B-EA21B769B9EB';
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Template Provisions -> MJ_BizApps_Contracts: Contract Template Modifications (One To Many via ContractTemplateProvisionID) */;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '82939a7c-51c9-4723-bcd7-3caecf976536') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('82939a7c-51c9-4723-bcd7-3caecf976536', '317DF592-8C20-473D-B097-2AB239877438', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'ContractTemplateProvisionID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'aa2aa995-a5fa-4565-8355-90e26f36365d') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('aa2aa995-a5fa-4565-8355-90e26f36365d', 'D4238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CompanyID', 'One To Many', TRUE, TRUE, 7, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '7fa39de0-72c9-4956-ad6c-476397a1aeac') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('7fa39de0-72c9-4956-ad6c-476397a1aeac', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CreatingEntityID', 'One To Many', TRUE, TRUE, 77, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'c674fabb-6df9-434e-90c0-99ec631f234b') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('c674fabb-6df9-434e-90c0-99ec631f234b', 'C70448F9-9792-41D7-A82C-784B66429D54', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'CustomerOrganizationID', 'One To Many', TRUE, TRUE, 5, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '05bfcb9a-898f-4d3b-9341-9c2a5fc9c996') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('05bfcb9a-898f-4d3b-9341-9c2a5fc9c996', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', '731F2890-1415-40DE-9073-D22EA23392B3', 'ContractTemplateTypeID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'e415e5bf-fcaa-49a6-bf33-ef3bc2d0d865') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e415e5bf-fcaa-49a6-bf33-ef3bc2d0d865', '731F2890-1415-40DE-9073-D22EA23392B3', '317DF592-8C20-473D-B097-2AB239877438', 'ContractTemplateID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '7790db07-7e7f-4f4a-a661-fac992fa5cf7') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('7790db07-7e7f-4f4a-a661-fac992fa5cf7', '731F2890-1415-40DE-9073-D22EA23392B3', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ContractTemplateID', 'One To Many', TRUE, TRUE, 2, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '6f16093e-ba7a-44c9-8e06-901f3383c7dc') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('6f16093e-ba7a-44c9-8e06-901f3383c7dc', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'PrimaryContactPersonID', 'One To Many', TRUE, TRUE, 4, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '37d5be77-a5a5-47f3-b217-e5ae72daafe9') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('37d5be77-a5a5-47f3-b217-e5ae72daafe9', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ContractTypeID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '0a972e9e-abaa-47fe-8dd7-90d1a60dc25d') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0a972e9e-abaa-47fe-8dd7-90d1a60dc25d', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'ContractID', 'One To Many', TRUE, TRUE, 1, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = '3b056bc8-b985-403a-9dcc-accef921c323') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('3b056bc8-b985-403a-9dcc-accef921c323', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'SupersededByContractID', 'One To Many', TRUE, TRUE, 2, NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityRelationship" WHERE "ID" = 'e45a646d-9a56-45e8-9c64-5583e38654c2') THEN
    INSERT INTO "__mj"."EntityRelationship" ("ID", "EntityID", "RelatedEntityID", "RelatedEntityJoinField", "Type", "BundleInAPI", "DisplayInForm", "Sequence", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e45a646d-9a56-45e8-9c64-5583e38654c2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'ParentContractID', 'One To Many', TRUE, TRUE, 3, NOW(), NOW());
  END IF;
END $$;

/* SQL text to sync schema info from database schemas */
SELECT
  "__mj"."spUpdateSchemaInfoFromDatabase"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'f56ab0cb-ec8f-429a-a33f-beddc6bb9f67' OR ("EntityID" = '317DF592-8C20-473D-B097-2AB239877438' AND "Name" = 'ContractTemplate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('f56ab0cb-ec8f-429a-a33f-beddc6bb9f67', '317DF592-8C20-473D-B097-2AB239877438' /* Entity: MJ_BizApps_Contracts: Contract Template Provisions */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438') + 10, 'ContractTemplate', 'Contract Template', NULL, 'nvarchar', 400, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '1e89d300-7f0d-4c94-9ba2-65f616951731' OR ("EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3' AND "Name" = 'ContractTemplateType')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('1e89d300-7f0d-4c94-9ba2-65f616951731', '731F2890-1415-40DE-9073-D22EA23392B3' /* Entity: MJ_BizApps_Contracts: Contract Templates */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3') + 11, 'ContractTemplateType', 'Contract Template Type', NULL, 'nvarchar', 200, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '14bda941-ce85-4a14-8fdc-3681b8c52418' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ContractType')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('14bda941-ce85-4a14-8fdc-3681b8c52418', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 26, 'ContractType', 'Contract Type', NULL, 'nvarchar', 200, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'a2b9a232-351c-4cf9-a050-6f059f146806' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'Company')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('a2b9a232-351c-4cf9-a050-6f059f146806', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 27, 'Company', 'Company', NULL, 'nvarchar', 100, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '8fbc1aac-1342-4584-991f-aab1c31ce673' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CustomerOrganization')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('8fbc1aac-1342-4584-991f-aab1c31ce673', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 28, 'CustomerOrganization', 'Customer Organization', NULL, 'nvarchar', 510, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '2999f51a-9170-4028-b142-2f33d7e056ed' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'PrimaryContactPerson')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('2999f51a-9170-4028-b142-2f33d7e056ed', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 29, 'PrimaryContactPerson', 'Primary Contact Person', NULL, 'nvarchar', 200, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '3df1fccc-6c4f-4cef-abec-836517ba655a' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'ContractTemplate')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('3df1fccc-6c4f-4cef-abec-836517ba655a', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 30, 'ContractTemplate', 'Contract Template', NULL, 'nvarchar', 400, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'b35327d2-0775-4cd2-9d4a-0fa1a2c98aa0' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'CreatingEntity')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('b35327d2-0775-4cd2-9d4a-0fa1a2c98aa0', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' /* Entity: MJ_BizApps_Contracts: Contracts */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2') + 31, 'CreatingEntity', 'Creating Entity', NULL, 'nvarchar', 510, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;


-- ============================================================================
-- Baseline: app-owned routines (B202608040001 section 6)
-- ============================================================================
-- =============================================================================
-- APP-OWNED PROGRAMMABLE OBJECTS (hand-written PL/pgSQL)
-- =============================================================================
-- CodeGen neither generates nor regenerates these.

---------------------------------------------------------------------------
-- spAssignNextContractNumber -- the only place a contract number is minted.
-- SQL Server has a procedure with one OUTPUT parameter; PostgreSQL has a
-- function of the same name that takes nothing and returns the number, called
-- as SELECT __mj_BizAppsContracts."spAssignNextContractNumber"().
-- nextval is atomic and never hands the same value to two callers.
-- lpad would TRUNCATE a number longer than six digits, so pad only when shorter.
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION __mj_bizappscontracts."spAssignNextContractNumber"()
RETURNS VARCHAR(50)
LANGUAGE plpgsql
AS $$
DECLARE
    v_next TEXT := nextval('__mj_bizappscontracts."seq_ContractNumber"')::TEXT;
BEGIN
    RETURN 'CTR-' || lpad(v_next, greatest(length(v_next), 6), '0');
END;
$$;

---------------------------------------------------------------------------
-- trg_ContractTemplateProvision_Immutability -- a PUBLISHED agreement version
-- neither gains, loses nor changes clauses (R-1).
--
-- RAISE EXCEPTION aborts the statement and its transaction, which covers what
-- THROW and ROLLBACK TRANSACTION do on SQL Server (there is no INSERT-EXEC
-- restriction to work around here). The UPDATE branch compares VALUES, so an
-- mj sync push that rewrites identical rows still passes. Description and
-- ProvisionSortKey stay outside the frozen set.
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION __mj_bizappscontracts."trg_ContractTemplateProvision_Immutability"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM __mj_bizappscontracts."ContractTemplate" t
                    WHERE t."ID" = NEW."ContractTemplateID" AND t."Status" = 'Published') THEN
            RAISE EXCEPTION 'A provision cannot be added to a PUBLISHED agreement version — that would silently grow the terms of every contract already referencing it. Publish a new version instead.'
                USING ERRCODE = 'P0001';
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM __mj_bizappscontracts."ContractTemplate" t
                    WHERE t."ID" = OLD."ContractTemplateID" AND t."Status" = 'Published') THEN
            RAISE EXCEPTION 'A provision cannot be deleted from a PUBLISHED agreement version — that would remove a clause from an agreement someone signed. Publish a new version instead; a published version is a historical record.'
                USING ERRCODE = 'P0001';
        END IF;
        RETURN OLD;
    ELSE
        IF EXISTS (SELECT 1 FROM __mj_bizappscontracts."ContractTemplate" t
                    WHERE t."ID" = OLD."ContractTemplateID" AND t."Status" = 'Published')
           AND (   NEW."ProvisionNumber"    IS DISTINCT FROM OLD."ProvisionNumber"
                OR NEW."Title"              IS DISTINCT FROM OLD."Title"
                OR NEW."ProvisionText"      IS DISTINCT FROM OLD."ProvisionText"
                OR NEW."ContractTemplateID" IS DISTINCT FROM OLD."ContractTemplateID") THEN
            RAISE EXCEPTION 'ProvisionNumber, Title, ProvisionText and the owning template cannot change on a PUBLISHED agreement version — editing one rewrites what a customer agreed to. Publish a new version instead. (Description remains editable.)'
                USING ERRCODE = 'P0001';
        END IF;
        RETURN NEW;
    END IF;
END;
$$;

CREATE TRIGGER "trg_ContractTemplateProvision_Immutability"
    AFTER INSERT OR UPDATE OR DELETE ON __mj_bizappscontracts."ContractTemplateProvision"
    FOR EACH ROW EXECUTE FUNCTION __mj_bizappscontracts."trg_ContractTemplateProvision_Immutability"();


-- ============================================================================
-- Baseline: CodeGen objects (native PG)
-- ============================================================================
-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:57.777Z
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_modification_contract_id"
    ON "__mj_bizappscontracts"."ContractTemplateModification" ("ContractID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_modification_contract_templa"
    ON "__mj_bizappscontracts"."ContractTemplateModification" ("ContractTemplateProvisionID");

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: vwContractTemplateModifications
-- Generated at: 2026-10-13T03:03:57.777Z
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Modifications
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplateModification
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplateModifications"
AS
SELECT
    c.*
FROM
    "__mj_bizappscontracts"."ContractTemplateModification" AS c
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
    AND tc.relname = 'vwContractTemplateModifications'
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
    AND tc.relname = 'vwContractTemplateModifications'
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
        AND tc.relname = 'vwContractTemplateModifications'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplateModifications" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spCreateContractTemplateModification
-- Generated at: 2026-10-13T03:03:57.795Z
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification"(
    p_id UUID DEFAULT NULL,
    p_contractid UUID DEFAULT NULL,
    p_contracttemplateprovisionid UUID DEFAULT NULL,
    p_modificationtext TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateModifications" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplateModification"
        (
            "ID",
            "ContractID",
                "ContractTemplateProvisionID",
                "ModificationText",
                "Notes"
        )
    VALUES
        (
            v_new_id,
            p_contractid,
                p_contracttemplateprovisionid,
                p_modificationtext,
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateModifications"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spUpdateContractTemplateModification
-- Generated at: 2026-10-13T03:03:57.796Z
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification"(
    p_id UUID,
    p_contractid UUID DEFAULT NULL,
    p_contracttemplateprovisionid UUID DEFAULT NULL,
    p_modificationtext TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateModifications" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplateModification"
    SET
        "ContractID" = COALESCE(p_contractid, "ContractID"),
        "ContractTemplateProvisionID" = COALESCE(p_contracttemplateprovisionid, "ContractTemplateProvisionID"),
        "ModificationText" = COALESCE(p_modificationtext, "ModificationText"),
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateModifications"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateModification table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_modification"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template_modification" ON "__mj_bizappscontracts"."ContractTemplateModification";

CREATE TRIGGER "trg_update_contract_template_modification"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplateModification"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_modification"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spDeleteContractTemplateModification
-- Generated at: 2026-10-13T03:03:57.797Z
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplateModification"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Permissions for vwContractTemplateModifications
-- Generated at: 2026-10-13T03:03:57.795Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Integration";


/* SQL text to update entity field related entity name field map for entity field ID fd673fee-72ab-4109-89b1-db5bcee9eb3e */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'fd673fee-72ab-4109-89b1-db5bcee9eb3e', p_RelatedEntityNameFieldMap => 'ContractTemplate');


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:57.838Z
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_provision_contract_template_"
    ON "__mj_bizappscontracts"."ContractTemplateProvision" ("ContractTemplateID");

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: vwContractTemplateProvisions
-- Generated at: 2026-10-13T03:03:57.838Z
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Provisions
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplateProvision
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplateProvisions"
AS
SELECT
    c.*,
    mjbizappscontractsContractTemplate_ContractTemplateID."Name" AS "ContractTemplate"
FROM
    "__mj_bizappscontracts"."ContractTemplateProvision" AS c
INNER JOIN
    "__mj_bizappscontracts"."ContractTemplate" AS mjbizappscontractsContractTemplate_ContractTemplateID
  ON
    "c"."ContractTemplateID" = mjbizappscontractsContractTemplate_ContractTemplateID."ID"
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
    AND tc.relname = 'vwContractTemplateProvisions'
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
    AND tc.relname = 'vwContractTemplateProvisions'
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
        AND tc.relname = 'vwContractTemplateProvisions'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplateProvisions" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spCreateContractTemplateProvision
-- Generated at: 2026-10-13T03:03:57.862Z
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplateProvision
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplateProvision'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateProvision"(
    p_id UUID DEFAULT NULL,
    p_contracttemplateid UUID DEFAULT NULL,
    p_provisionnumber varchar(20) DEFAULT NULL,
    p_title varchar(200) DEFAULT NULL,
    p_provisiontext TEXT DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateProvisions" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplateProvision"
        (
            "ID",
            "ContractTemplateID",
                "ProvisionNumber",
                "Title",
                "ProvisionText",
                "Description"
        )
    VALUES
        (
            v_new_id,
            p_contracttemplateid,
                p_provisionnumber,
                p_title,
                p_provisiontext,
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateProvisions"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateProvision" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spUpdateContractTemplateProvision
-- Generated at: 2026-10-13T03:03:57.862Z
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplateProvision
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplateProvision'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateProvision"(
    p_id UUID,
    p_contracttemplateid UUID DEFAULT NULL,
    p_provisionnumber varchar(20) DEFAULT NULL,
    p_title varchar(200) DEFAULT NULL,
    p_provisiontext TEXT DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateProvisions" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplateProvision"
    SET
        "ContractTemplateID" = COALESCE(p_contracttemplateid, "ContractTemplateID"),
        "ProvisionNumber" = COALESCE(p_provisionnumber, "ProvisionNumber"),
        "Title" = COALESCE(p_title, "Title"),
        "ProvisionText" = COALESCE(p_provisiontext, "ProvisionText"),
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateProvisions"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateProvision" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateProvision table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_provision"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template_provision" ON "__mj_bizappscontracts"."ContractTemplateProvision";

CREATE TRIGGER "trg_update_contract_template_provision"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplateProvision"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_provision"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: spDeleteContractTemplateProvision
-- Generated at: 2026-10-13T03:03:57.862Z
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplateProvision
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplateProvision'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateProvision"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplateProvision"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateProvision" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Provisions
-- Item: Permissions for vwContractTemplateProvisions
-- Generated at: 2026-10-13T03:03:57.861Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateProvisions" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateProvision" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateProvision" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateProvision" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateProvision" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:57.905Z
-- ============================================================


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: vwContractTemplateTypes
-- Generated at: 2026-10-13T03:03:57.905Z
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Types
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplateType
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplateTypes"
AS
SELECT
    c.*
FROM
    "__mj_bizappscontracts"."ContractTemplateType" AS c
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
    AND tc.relname = 'vwContractTemplateTypes'
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
    AND tc.relname = 'vwContractTemplateTypes'
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
        AND tc.relname = 'vwContractTemplateTypes'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplateTypes" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spCreateContractTemplateType
-- Generated at: 2026-10-13T03:03:57.909Z
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplateType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplateType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateType"(
    p_id UUID DEFAULT NULL,
    p_name varchar(100) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(10) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateTypes" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplateType"
        (
            "ID",
            "Name",
                "Description",
                "Status"
        )
    VALUES
        (
            v_new_id,
            p_name,
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END,
                COALESCE(p_status, 'Active')
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateTypes"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateType" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spUpdateContractTemplateType
-- Generated at: 2026-10-13T03:03:57.909Z
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplateType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplateType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateType"(
    p_id UUID,
    p_name varchar(100) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(10) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateTypes" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplateType"
    SET
        "Name" = COALESCE(p_name, "Name"),
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END,
        "Status" = COALESCE(p_status, "Status")
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateTypes"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateType" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateType table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_type"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template_type" ON "__mj_bizappscontracts"."ContractTemplateType";

CREATE TRIGGER "trg_update_contract_template_type"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplateType"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_type"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: spDeleteContractTemplateType
-- Generated at: 2026-10-13T03:03:57.909Z
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplateType
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplateType'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateType"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplateType"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateType" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Types
-- Item: Permissions for vwContractTemplateTypes
-- Generated at: 2026-10-13T03:03:57.908Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateTypes" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateType" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateType" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateType" TO "cdp_Integration";


/* SQL text to update entity field related entity name field map for entity field ID 7b8ec82e-cf52-4f4c-980d-47a15194ea12 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => '7b8ec82e-cf52-4f4c-980d-47a15194ea12', p_RelatedEntityNameFieldMap => 'ContractTemplateType');


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:57.936Z
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_contract_template_type_id"
    ON "__mj_bizappscontracts"."ContractTemplate" ("ContractTemplateTypeID");

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: vwContractTemplates
-- Generated at: 2026-10-13T03:03:57.936Z
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Templates
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplate
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplates"
AS
SELECT
    c.*,
    mjbizappscontractsContractTemplateType_ContractTemplateTypeID."Name" AS "ContractTemplateType"
FROM
    "__mj_bizappscontracts"."ContractTemplate" AS c
INNER JOIN
    "__mj_bizappscontracts"."ContractTemplateType" AS mjbizappscontractsContractTemplateType_ContractTemplateTypeID
  ON
    "c"."ContractTemplateTypeID" = mjbizappscontractsContractTemplateType_ContractTemplateTypeID."ID"
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
    AND tc.relname = 'vwContractTemplates'
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
    AND tc.relname = 'vwContractTemplates'
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
        AND tc.relname = 'vwContractTemplates'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplates" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spCreateContractTemplate
-- Generated at: 2026-10-13T03:03:57.955Z
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate"(
    p_id UUID DEFAULT NULL,
    p_name varchar(200) DEFAULT NULL,
    p_contracttemplatetypeid UUID DEFAULT NULL,
    p_versionlabel_clear boolean DEFAULT false,
    p_versionlabel varchar(50) DEFAULT NULL,
    p_introduceddate_clear boolean DEFAULT false,
    p_introduceddate date DEFAULT NULL,
    p_sourceurl_clear boolean DEFAULT false,
    p_sourceurl varchar(1000) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(20) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplates" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplate"
        (
            "ID",
            "Name",
                "ContractTemplateTypeID",
                "VersionLabel",
                "IntroducedDate",
                "SourceURL",
                "Description",
                "Status"
        )
    VALUES
        (
            v_new_id,
            p_name,
                p_contracttemplatetypeid,
                CASE WHEN p_versionlabel_clear = true THEN NULL ELSE COALESCE(p_versionlabel, NULL) END,
                CASE WHEN p_introduceddate_clear = true THEN NULL ELSE COALESCE(p_introduceddate, NULL) END,
                CASE WHEN p_sourceurl_clear = true THEN NULL ELSE COALESCE(p_sourceurl, NULL) END,
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END,
                COALESCE(p_status, 'Draft')
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplates"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spUpdateContractTemplate
-- Generated at: 2026-10-13T03:03:57.956Z
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate"(
    p_id UUID,
    p_name varchar(200) DEFAULT NULL,
    p_contracttemplatetypeid UUID DEFAULT NULL,
    p_versionlabel_clear boolean DEFAULT false,
    p_versionlabel varchar(50) DEFAULT NULL,
    p_introduceddate_clear boolean DEFAULT false,
    p_introduceddate date DEFAULT NULL,
    p_sourceurl_clear boolean DEFAULT false,
    p_sourceurl varchar(1000) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(20) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplates" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplate"
    SET
        "Name" = COALESCE(p_name, "Name"),
        "ContractTemplateTypeID" = COALESCE(p_contracttemplatetypeid, "ContractTemplateTypeID"),
        "VersionLabel" = CASE WHEN p_versionlabel_clear = true THEN NULL ELSE COALESCE(p_versionlabel, "VersionLabel") END,
        "IntroducedDate" = CASE WHEN p_introduceddate_clear = true THEN NULL ELSE COALESCE(p_introduceddate, "IntroducedDate") END,
        "SourceURL" = CASE WHEN p_sourceurl_clear = true THEN NULL ELSE COALESCE(p_sourceurl, "SourceURL") END,
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END,
        "Status" = COALESCE(p_status, "Status")
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplates"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplate table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template" ON "__mj_bizappscontracts"."ContractTemplate";

CREATE TRIGGER "trg_update_contract_template"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplate"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spDeleteContractTemplate
-- Generated at: 2026-10-13T03:03:57.956Z
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplate"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Permissions for vwContractTemplates
-- Generated at: 2026-10-13T03:03:57.955Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:57.986Z
-- ============================================================


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: vwContractTypes
-- Generated at: 2026-10-13T03:03:57.986Z
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
-- Generated at: 2026-10-13T03:03:57.996Z
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
    p_templaterequired BOOLEAN DEFAULT NULL
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
                "TemplateRequired"
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
                COALESCE(p_templaterequired, FALSE)
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
-- Generated at: 2026-10-13T03:03:57.996Z
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
    p_templaterequired BOOLEAN DEFAULT NULL
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
        "TemplateRequired" = COALESCE(p_templaterequired, "TemplateRequired")
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
-- Generated at: 2026-10-13T03:03:57.996Z
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
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Permissions for vwContractTypes
-- Generated at: 2026-10-13T03:03:57.996Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTypes" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractType" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractType" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractType" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractType" TO "cdp_Integration";


/* SQL text to update entity field related entity name field map for entity field ID df26a6b1-eb6c-42d8-b236-cd13f58c9b78 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'df26a6b1-eb6c-42d8-b236-cd13f58c9b78', p_RelatedEntityNameFieldMap => 'ContractType');

/* SQL text to update entity field related entity name field map for entity field ID bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'bad7aa2f-ee2b-430a-b182-b7e4b7e09f8a', p_RelatedEntityNameFieldMap => 'Company');

/* SQL text to update entity field related entity name field map for entity field ID f11c9543-f483-4bed-a9ce-3e7659d24011 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'f11c9543-f483-4bed-a9ce-3e7659d24011', p_RelatedEntityNameFieldMap => 'CustomerOrganization');

/* SQL text to update entity field related entity name field map for entity field ID d47233ed-0ebf-4329-b270-99f70589cd7f */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'd47233ed-0ebf-4329-b270-99f70589cd7f', p_RelatedEntityNameFieldMap => 'PrimaryContactPerson');

/* SQL text to update entity field related entity name field map for entity field ID b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => 'b4e3a6bf-a9c0-4005-b759-f7623fd5a7fa', p_RelatedEntityNameFieldMap => 'ContractTemplate');

/* SQL text to update entity field related entity name field map for entity field ID 316a9f07-54f1-4038-862a-c25a2084f274 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => '316a9f07-54f1-4038-862a-c25a2084f274', p_RelatedEntityNameFieldMap => 'CreatingEntity');


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:03:58.018Z
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
-- Item: vwContracts
-- Generated at: 2026-10-13T03:03:58.018Z
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contracts
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  Contract
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContracts"
AS
SELECT
    c.*,
    mjbizappscontractsContractType_ContractTypeID."Name" AS "ContractType",
    MJCompany_CompanyID."Name" AS "Company",
    mjBizAppsCommonOrganization_CustomerOrganizationID."Name" AS "CustomerOrganization",
    mjBizAppsCommonPerson_PrimaryContactPersonID."DisplayName" AS "PrimaryContactPerson",
    mjbizappscontractsContractTemplate_ContractTemplateID."Name" AS "ContractTemplate",
    MJEntity_CreatingEntityID."Name" AS "CreatingEntity"
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: spCreateContract
-- Generated at: 2026-10-13T03:03:58.114Z
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
    p_notes TEXT DEFAULT NULL
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
                "Notes"
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
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END
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
-- Generated at: 2026-10-13T03:03:58.114Z
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
    p_notes TEXT DEFAULT NULL
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
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END
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
-- Generated at: 2026-10-13T03:03:58.114Z
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


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
-- Generated at: 2026-10-13T03:03:58.114Z
-- ============================================================
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContracts" TO "cdp_Integration";

GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Integration";


-- ============================================================================
-- Baseline: CodeGen-captured metadata
-- ============================================================================
/* SQL text to update ValueListType for entity field ID 0E2AB42B-29F2-4151-A424-ABA78BBA163B */
UPDATE __mj."EntityField" SET "ValueListType"='List' WHERE "ID"='0E2AB42B-29F2-4151-A424-ABA78BBA163B';

/* SQL text to update ValueListType for entity field ID E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B */
UPDATE __mj."EntityField" SET "ValueListType"='List' WHERE "ID"='E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B';

/* SQL text to update ValueListType for entity field ID 59601A28-9AED-4E62-8B3B-EA21B769B9EB */
UPDATE __mj."EntityField" SET "ValueListType"='List' WHERE "ID"='59601A28-9AED-4E62-8B3B-EA21B769B9EB';

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '62AFA042-4658-4D78-B9C3-1BDD0B3997D4'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '59601A28-9AED-4E62-8B3B-EA21B769B9EB'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '444FC85A-BD7A-4967-8633-A4E1F8ACB4CE'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."Entity"
            SET "AllowUserSearchAPI" = FALSE
            WHERE "ID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'
            AND "AutoUpdateAllowUserSearchAPI" = TRUE;

/* Set field properties for entity */
UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '0E2AB42B-29F2-4151-A424-ABA78BBA163B'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."Entity"
            SET "AllowUserSearchAPI" = FALSE
            WHERE "ID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0'
            AND "AutoUpdateAllowUserSearchAPI" = TRUE;

/* Set field properties for entity */
UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '982E307B-667C-4955-99DE-F9A96FAB2CB2'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '0864CB7F-E532-402F-9F16-102EC14993C6'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."Entity"
            SET "AllowUserSearchAPI" = FALSE
            WHERE "ID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225'
            AND "AutoUpdateAllowUserSearchAPI" = TRUE;

/* Set field properties for entity */
UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'D20B1F02-4F4B-4A8E-894D-4D74F32A6282'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '1E89D300-7F0D-4C94-9BA2-65F616951731'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE __mj."EntityField"
               SET "UserSearchPredicateAPI" = 'BeginsWith'
               WHERE "ID" = '1FC39118-F7F8-4BA7-9940-F341E35F4FDB'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

UPDATE __mj."EntityField"
               SET "UserSearchPredicateAPI" = 'Exact'
               WHERE "ID" = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set field properties for entity */
UPDATE __mj."EntityField"
               SET "IsNameField" = TRUE
               WHERE "ID" = 'CFB7315F-8759-4728-BD30-FAAE93F97106'
               AND "AutoUpdateIsNameField" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'CFB7315F-8759-4728-BD30-FAAE93F97106'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'CE9CE69A-95CF-4CF0-BDA8-F5F5E661A40B'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = 'F56AB0CB-EC8F-429A-A33F-BEDDC6BB9F67'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."Entity"
            SET "AllowUserSearchAPI" = FALSE
            WHERE "ID" = '317DF592-8C20-473D-B097-2AB239877438'
            AND "AutoUpdateAllowUserSearchAPI" = TRUE;

/* Set categories for 6 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'B592F895-7E87-480A-8663-9D3C70F812D5' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'EECE216E-EC2B-4630-9E17-3FCDE668F32A' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '3EC31CA1-A410-4A25-BB23-1E668A16A125' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '0E2AB42B-29F2-4151-A424-ABA78BBA163B' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'E7D55020-C93E-46B9-89E5-19088CBEDB0A' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '26168480-7C59-4436-B954-4979F44F7014' AND "AutoUpdateCategory" = TRUE;

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0';

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('0b578442-b41f-484b-827e-d47e4013c7bb', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'FieldCategoryInfo', '{"Contract Template Details":{"icon":"fa fa-file-contract","description":"Information defining the specific type of contract template"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('1296ce7e-6406-4540-887c-dad2b35d435e', '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0', 'FieldCategoryIcons', '{"Contract Template Details":"fa fa-file-contract","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = FALSE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = '4E3F97BE-E196-4CC0-9B5D-CC50DE8967A0';

/* Set categories for 7 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '4796BC59-BF1A-41CF-83B5-29E8F8880C47' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Association',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '982E307B-667C-4955-99DE-F9A96FAB2CB2' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Association',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Template Provision',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '0864CB7F-E532-402F-9F16-102EC14993C6' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Modification Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '0D2FC779-82CA-4D68-A711-3D871A356164' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Modification Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '87BB27CB-98B7-4704-BDC5-7871F8F394EB' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '18518499-1DD3-4369-BD76-59B62EEBA5B8' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '54072096-C4E2-450C-97FA-BF162E2485D6' AND "AutoUpdateCategory" = TRUE;

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('7c40ba9f-d702-4e58-a74f-51e0db251f13', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'FieldCategoryInfo', '{"Contract Association":{"icon":"fa fa-link","description":"Links the modification to the parent contract and specific template provision."},"Modification Details":{"icon":"fa fa-edit","description":"The specific text changes and supporting notes for the contract modification."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields."}}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('0e258280-451a-4b0c-bcc4-19ae5309b564', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225', 'FieldCategoryIcons', '{"Contract Association":"fa fa-link","Modification Details":"fa fa-edit","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';

/* Set categories for 10 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '9C8643D3-2B82-41A6-80F6-D29ABB68D1CB' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Type Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '84119AD2-CBA8-466B-B20A-8A94C20FCE3F' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Type Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '46B195B4-EA25-41A4-BB78-83B2014A930C' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Type Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '59601A28-9AED-4E62-8B3B-EA21B769B9EB' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Configuration Rules',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '62AFA042-4658-4D78-B9C3-1BDD0B3997D4' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Configuration Rules',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D252CC6D-3196-4616-AAEF-93FFC7CE6887' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Configuration Rules',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '04BA23CD-EC7A-495B-81DF-47474EF8C0EB' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Configuration Rules',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '444FC85A-BD7A-4967-8633-A4E1F8ACB4CE' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '6A869A40-C89A-43F5-BC80-94A104E9FC46' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '68821111-317C-4AB8-922E-F1EC8AEA0973' AND "AutoUpdateCategory" = TRUE;

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262';

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('d2d62a86-3c4a-442a-bc2c-a0498b5f5632', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'FieldCategoryInfo', '{"Contract Type Details":{"icon":"fa fa-info-circle","description":"Basic identification and status information for the contract type"},"Configuration Rules":{"icon":"fa fa-cogs","description":"Business logic and constraints governing contract behavior and placement"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('14088b52-f54b-47e4-bc16-9c4f325c7450', 'C8909A57-6DDB-4585-BE00-E707C5B4F262', 'FieldCategoryIcons', '{"Contract Type Details":"fa fa-info-circle","Configuration Rules":"fa fa-cogs","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Set DefaultForNewUser=false for NEW entity (category: reference, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = FALSE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262';

/* Set categories for 10 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'DA55D974-F70E-42D0-A12A-04F2EFD46A85' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Association',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Template',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'FD673FEE-72AB-4109-89B1-DB5BCEE9EB3E' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Association',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Template Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'F56AB0CB-EC8F-429A-A33F-BEDDC6BB9F67' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provision Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'CFB7315F-8759-4728-BD30-FAAE93F97106' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provision Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'CE9CE69A-95CF-4CF0-BDA8-F5F5E661A40B' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provision Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D2CD9029-4DB4-4AD1-85A2-ABBFDA35EAFD' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provision Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '1BFDA475-470F-4F3C-8B5D-B0DBDCED2EE3' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Sort Key',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '2E082EBC-4A00-4C39-8F6D-F7B680F5B345' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '6B098C7F-9119-4C60-94B5-CA2ACA14309F' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '9F515EDD-BE69-4955-9C10-EB1819DDFD2C' AND "AutoUpdateCategory" = TRUE;

/* Set categories for 11 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'A8BF5461-4A41-4388-8761-50B79FC598B4' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '1FC39118-F7F8-4BA7-9940-F341E35F4FDB' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Template Type ID',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '7B8EC82E-CF52-4F4C-980D-47A15194EA12' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Template Type',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '1E89D300-7F0D-4C94-9BA2-65F616951731' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Template Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '7F9A6927-CA1D-441B-9682-7035C95393D8' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Lifecycle and Access',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D20B1F02-4F4B-4A8E-894D-4D74F32A6282' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Lifecycle and Access',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = 'URL',
   "CodeType" = NULL
WHERE 
   "ID" = '5F27FB9A-A089-46CE-A332-F7E7DE745BCF' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Lifecycle and Access',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'E84E1C35-41C9-4A59-8AD2-6D426FDB7E6B' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'E586DB3A-8FCA-424F-BB0F-AE34BE10C686' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'B0E8E57C-69A5-4A3F-BAD2-CCBF75F2FF30' AND "AutoUpdateCategory" = TRUE;

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = '731F2890-1415-40DE-9073-D22EA23392B3';

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = '317DF592-8C20-473D-B097-2AB239877438';

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('b676e178-ea28-4c40-b59e-a0cb7e1a6d4c', '731F2890-1415-40DE-9073-D22EA23392B3', 'FieldCategoryInfo', '{"Template Details":{"icon":"fa fa-info-circle","description":"Core identifying information and classification for the contract template"},"Lifecycle and Access":{"icon":"fa fa-history","description":"Information regarding template availability, publication status, and public access links"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking fields"}}', NOW(), NOW());

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('f09f4e8e-415b-49d6-8c5b-2f31320e2b2a', '317DF592-8C20-473D-B097-2AB239877438', 'FieldCategoryInfo', '{"Template Association":{"icon":"fa fa-link","description":"Links the provision to the specific contract template version"},"Provision Details":{"icon":"fa fa-align-left","description":"Core content, numbering, and descriptive information for the contract clause"},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit, sorting, and identification fields"}}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('04cd7a19-f678-4e64-a3a3-21af4d94c378', '317DF592-8C20-473D-B097-2AB239877438', 'FieldCategoryIcons', '{"Template Association":"fa fa-link","Provision Details":"fa fa-align-left","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('4fca29d1-19bb-45a4-ada3-2a2c25d24d78', '731F2890-1415-40DE-9073-D22EA23392B3', 'FieldCategoryIcons', '{"Template Details":"fa fa-info-circle","Lifecycle and Access":"fa fa-history","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = '731F2890-1415-40DE-9073-D22EA23392B3';

/* Set DefaultForNewUser=true for NEW entity (category: supporting, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = '317DF592-8C20-473D-B097-2AB239877438';

/* Set field properties for entity */
UPDATE __mj."EntityField"
               SET "IsNameField" = TRUE
               WHERE "ID" = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND "AutoUpdateIsNameField" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '5605AB79-A11A-4561-8B34-B7567A36F27A'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '343BECBD-079B-443A-998C-2E7DDCCD8A01'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '14BDA941-CE85-4A14-8FDC-3681B8C52418'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "DefaultInView" = TRUE
               WHERE "ID" = '8FBC1AAC-1342-4584-991F-AAB1C31CE673'
               AND "AutoUpdateDefaultInView" = TRUE;

UPDATE __mj."EntityField"
               SET "IncludeInUserSearchAPI" = TRUE
               WHERE "ID" = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND "AutoUpdateIncludeInUserSearchAPI" = TRUE;

UPDATE __mj."EntityField"
               SET "UserSearchPredicateAPI" = 'Exact'
               WHERE "ID" = '8677055B-2482-4250-98C1-AFC3DAE57393'
               AND "AutoUpdateUserSearchPredicate" = TRUE;

/* Set categories for 31 fields */
UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '04E8AA9D-C2DC-489D-B081-75C4E6DDFA6B' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '8677055B-2482-4250-98C1-AFC3DAE57393' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Type',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'DF26A6B1-EB6C-42D8-B236-CD13F58C9B78' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Type Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '14BDA941-CE85-4A14-8FDC-3681B8C52418' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Selling Company',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'BAD7AA2F-EE2B-430A-B182-B7E4B7E09F8A' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Company Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'A2B9A232-351C-4CF9-A050-6F059F146806' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Customer Organization',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'F11C9543-F483-4BED-A9CE-3E7659D24011' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Customer Organization Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '8FBC1AAC-1342-4584-991F-AAB1C31CE673' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Primary Contact Person',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D47233ED-0EBF-4329-B270-99F70589CD7F' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Stakeholders',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Primary Contact Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '2999F51A-9170-4028-B142-2F33D7E056ED' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Template',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'B4E3A6BF-A9C0-4005-B759-F7623FD5A7FA' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Contract Template Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '3DF1FCCC-6C4F-4CEF-ABEC-836517BA655A' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provenance',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Creating Entity',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '316A9F07-54F1-4038-862A-C25A2084F274' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provenance',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Creating Entity Name',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'B35327D2-0775-4CD2-9D4A-0FA1A2C98AA0' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Provenance',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '611650F5-BFC3-4809-B9B1-80AC9979B450' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Lifecycle',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Parent Contract',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '6DB0692A-42CD-4AC5-A43B-49ECC81EF370' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Lifecycle',
   "GeneratedFormSection" = 'Category',
   "DisplayName" = 'Superseded By',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '44BC44EF-A6F2-4630-A899-487CE0E3CC56' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = 'URL',
   "CodeType" = NULL
WHERE 
   "ID" = '131CE82F-AC93-4DCF-95C0-3EA4FC681C2C' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Dates and Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '5605AB79-A11A-4561-8B34-B7567A36F27A' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Dates and Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '9ED4A8CC-E0B8-4880-945A-4BD6DD6368C6' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Dates and Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '343BECBD-079B-443A-998C-2E7DDCCD8A01' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Dates and Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D312F0C4-AD4D-4F0B-B54A-1051EC735464' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Renewal Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '8B3C517C-FF01-4121-A740-632DF75F3C05' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Renewal Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '573064AC-38A8-42A2-95B2-CCBD605004EA' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Renewal Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'C6464ADC-6683-4D4B-AA7A-64F9E052D225' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Renewal Terms',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '3B2625E1-C5AB-462C-AA7E-533C5F40646D' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Contract Details',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = 'D54DDEBD-615B-4D29-A995-246C3C0F7408' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Notes and Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '30B733E2-70E1-4D55-BA83-73FEDBA848FA' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'Notes and Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '68E70227-D818-4F11-8FE4-553F5C84BE53' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '7C14348E-69DE-4F66-B62C-99C0A7E415AF' AND "AutoUpdateCategory" = TRUE;

UPDATE __mj."EntityField"
SET 
   "Category" = 'System Metadata',
   "GeneratedFormSection" = 'Category',
   "ExtendedType" = NULL,
   "CodeType" = NULL
WHERE 
   "ID" = '0EBA35EC-FB3D-4978-8650-FC6229A9180E' AND "AutoUpdateCategory" = TRUE;

/* Set entity icon to fa fa-file-contract */
UPDATE __mj."Entity"
               SET "Icon" = 'fa fa-file-contract', "__mj_UpdatedAt" = NOW()
               WHERE "ID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';

/* Insert FieldCategoryInfo setting for entity */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('9921cd66-81de-40a8-b6ad-2e814ffc09b9', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'FieldCategoryInfo', '{"Contract Details":{"icon":"fa fa-file-contract","description":"Core information regarding the contract agreement, type, and document links."},"Stakeholders":{"icon":"fa fa-users","description":"Entities and individuals involved in the contract."},"Provenance":{"icon":"fa fa-project-diagram","description":"References to the source records that created this contract."},"Contract Lifecycle":{"icon":"fa fa-sync","description":"Relationships defining amendments and contract replacements."},"Dates and Terms":{"icon":"fa fa-calendar-alt","description":"Key dates governing the contract term and execution."},"Renewal Terms":{"icon":"fa fa-redo","description":"Renewal conditions, notice periods, and price adjustments."},"Notes and Metadata":{"icon":"fa fa-align-left","description":"Additional context and internal notes."},"System Metadata":{"icon":"fa fa-cog","description":"System-managed audit and tracking information."}}', NOW(), NOW());

/* Insert FieldCategoryIcons setting (legacy) */
INSERT INTO __mj."EntitySetting" ("ID", "EntityID", "Name", "Value", "__mj_CreatedAt", "__mj_UpdatedAt")
               VALUES ('710847a6-de1d-4884-81db-bde4530e9a74', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', 'FieldCategoryIcons', '{"Contract Details":"fa fa-file-contract","Stakeholders":"fa fa-users","Provenance":"fa fa-project-diagram","Contract Lifecycle":"fa fa-sync","Dates and Terms":"fa fa-calendar-alt","Renewal Terms":"fa fa-redo","Notes and Metadata":"fa fa-align-left","System Metadata":"fa fa-cog"}', NOW(), NOW());

/* Set DefaultForNewUser=true for NEW entity (category: primary, confidence: high) */
UPDATE __mj."ApplicationEntity"
         SET "DefaultForNewUser" = TRUE, "__mj_UpdatedAt" = NOW()
         WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Template Modifications */
INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '(LENGTH(ltrim(rtrim([ModificationText])))>(0))', 'public ValidateModificationTextNotEmpty(result: ValidationResult) {
	if (this.ModificationText == null || this.ModificationText.trim().length === 0) {
		result.Errors.push(new ValidationErrorInfo(
			"ModificationText",
			"Modification text cannot be empty or contain only whitespace.",
			this.ModificationText,
			ValidationErrorType.Failure
		));
	}
}', 'The modification text must contain actual text and cannot be empty or consist only of spaces.', 'ValidateModificationTextNotEmpty', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '0D2FC779-82CA-4D68-A711-3D871A356164');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Template Provisions */
INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '(LENGTH(ltrim(rtrim([ProvisionText])))>(0))', 'public ValidateProvisionTextNotEmpty(result: ValidationResult) {
	if (this.ProvisionText === undefined || this.ProvisionText === null || this.ProvisionText.trim().length === 0) {
		result.Errors.push(new ValidationErrorInfo(
			"ProvisionText",
			"Provision text cannot be empty or consist only of spaces.",
			this.ProvisionText,
			ValidationErrorType.Failure
		));
	}
}', 'The provision text cannot be empty or consist only of spaces. It must contain actual text content.', 'ValidateProvisionTextNotEmpty', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'D2CD9029-4DB4-4AD1-85A2-ABBFDA35EAFD');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contract Types */
INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '(NOT ([MustBeRoot]=TRUE AND [MustBeChild]=TRUE))', 'public ValidateRootAndChildExclusivity(result: ValidationResult) {
	if (this.MustBeRoot && this.MustBeChild) {
		result.Errors.push(new ValidationErrorInfo(
			"MustBeRoot",
			"An entity cannot be designated as both a root and a child at the same time.",
			this.MustBeRoot,
			ValidationErrorType.Failure
		));
	}
}', 'An entity cannot be designated as both a root and a child at the same time.', 'ValidateRootAndChildExclusivity', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', 'C8909A57-6DDB-4585-BE00-E707C5B4F262');

/* Generated Validation Functions for MJ_BizApps_Contracts: Contracts */
INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([AnnualIncreasePercent] IS NULL OR [AnnualIncreasePercent]>=(0))', 'public ValidateAnnualIncreasePercentNonNegative(result: ValidationResult) {
	if (this.AnnualIncreasePercent != null && this.AnnualIncreasePercent < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"AnnualIncreasePercent",
			"Annual increase percentage must be greater than or equal to 0.",
			this.AnnualIncreasePercent,
			ValidationErrorType.Failure
		));
	}
}', 'The annual increase percentage must be greater than or equal to zero, ensuring that contract rates do not decrease automatically.', 'ValidateAnnualIncreasePercentNonNegative', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '3B2625E1-C5AB-462C-AA7E-533C5F40646D');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([CancellationWindowDays] IS NULL OR [CancellationWindowDays]>=(0))', 'public ValidateCancellationWindowDaysGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.CancellationWindowDays != null && this.CancellationWindowDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"CancellationWindowDays",
			"Cancellation window days must be 0 or a positive number.",
			this.CancellationWindowDays,
			ValidationErrorType.Failure
		));
	}
}', 'The cancellation window days must be zero or a positive number, ensuring that we do not record a negative number of days for the contract cancellation period.', 'ValidateCancellationWindowDaysGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', 'C6464ADC-6683-4D4B-AA7A-64F9E052D225');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([RenewalNoticeDays] IS NULL OR [RenewalNoticeDays]>=(0))', 'public ValidateRenewalNoticeDaysGreaterThanOrEqualToZero(result: ValidationResult) {
	if (this.RenewalNoticeDays != null && this.RenewalNoticeDays < 0) {
		result.Errors.push(new ValidationErrorInfo(
			"RenewalNoticeDays",
			"Renewal notice days must be 0 or greater.",
			this.RenewalNoticeDays,
			ValidationErrorType.Failure
		));
	}
}', 'Renewal notice days must be 0 or greater, if specified.', 'ValidateRenewalNoticeDaysGreaterThanOrEqualToZero', 'DF238F34-2837-EF11-86D4-6045BDEE16E6', '573064AC-38A8-42A2-95B2-CCBD605004EA');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([CreatingEntityID] IS NULL AND [CreatingRecordID] IS NULL OR [CreatingEntityID] IS NOT NULL AND [CreatingRecordID] IS NOT NULL)', 'public ValidateCreatingEntityAndRecordCoexistence(result: ValidationResult) {
	const hasEntity = this.CreatingEntityID != null;
	const hasRecord = this.CreatingRecordID != null && this.CreatingRecordID !== "";

	if (hasEntity !== hasRecord) {
		result.Errors.push(new ValidationErrorInfo(
			"CreatingEntityID",
			"Creating Entity ID and Creating Record ID must either both be specified or both be empty.",
			this.CreatingEntityID,
			ValidationErrorType.Failure
		));
	}
}', 'Both Creating Entity ID and Creating Record ID must be provided together, or both must be left empty, to ensure consistent tracking of the source entity and record.', 'ValidateCreatingEntityAndRecordCoexistence', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([EndDate] IS NULL OR [EffectiveDate] IS NULL OR [EndDate]>=[EffectiveDate])', 'public ValidateEndDateAfterOrEqualToEffectiveDate(result: ValidationResult) {
    if (this.EndDate != null && this.EffectiveDate != null) {
        if (this.EndDate < this.EffectiveDate) {
            result.Errors.push(new ValidationErrorInfo(
                "EndDate",
                "The contract End Date must be on or after the Effective Date.",
                this.EndDate,
                ValidationErrorType.Failure
            ));
        }
    }
}', 'The contract end date must be on or after the effective date to ensure logical date ordering.', 'ValidateEndDateAfterOrEqualToEffectiveDate', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([ParentContractID] IS NULL OR [ParentContractID]<>[ID])', 'public ValidateParentContractIDNotEqualToID(result: ValidationResult) {
	if (this.ParentContractID != null && this.ParentContractID === this.ID) {
		result.Errors.push(new ValidationErrorInfo(
			"ParentContractID",
			"A contract cannot be its own parent contract.",
			this.ParentContractID,
			ValidationErrorType.Failure
		));
	}
}', 'A contract cannot be its own parent contract to prevent circular references in the contract hierarchy.', 'ValidateParentContractIDNotEqualToID', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');

INSERT INTO __mj."GeneratedCode" ("CategoryID", "GeneratedByModelID", "GeneratedAt", "Language", "Status", "Source", "Code", "Description", "Name", "LinkedEntityID", "LinkedRecordPrimaryKey")
                      VALUES ((SELECT "ID" FROM __mj."vwGeneratedCodeCategories" WHERE "Name"='CodeGen: Validators'), 'C43229F6-4CC8-4838-9D04-03419A2DA191', NOW(), 'TypeScript', 'Approved', '([SupersededByContractID] IS NULL OR [SupersededByContractID]<>[ID])', 'public ValidateSupersededByContractIDNotEqualToID(result: ValidationResult) {
	if (this.SupersededByContractID != null && this.SupersededByContractID === this.ID) {
		result.Errors.push(new ValidationErrorInfo(
			"SupersededByContractID",
			"A contract cannot be superseded by itself. Please select a different contract.",
			this.SupersededByContractID,
			ValidationErrorType.Failure
		));
	}
}', 'A contract cannot be superseded by itself. The superseding contract must be a different contract record.', 'ValidateSupersededByContractIDNotEqualToID', 'E0238F34-2837-EF11-86D4-6045BDEE16E6', '5DEB0B11-ED6C-48B3-9200-F4441396C5E2');


-- ============================================================================
-- V202608240100__v0.1.x__Layered_base_view_flags
-- ============================================================================
-- ============================================================================
-- MemberJunction PostgreSQL Migration — V202608240100__v0.1.x__Layered_base_view_flags.sql
-- Split-and-regenerate with INLINE NATIVE CodeGen baking: hand-written DDL transpiled
-- (AST dialect), metadata DML inline, and CodeGen objects (views/sprocs/triggers/grants)
-- baked natively from `mj codegen`. Applies standalone via `mj migrate` — no deploy codegen.
-- ============================================================================


/* ============================================================================= */
/* V202608240100 — the two layered base views: hand CodeGen a PRIVATE name. */
/* ============================================================================= */
/* Contracts and Contract Templates use MJ's layered base views (MJ#3419): CodeGen */
/* owns a generated inner view under GeneratedBaseViewName, and the APPLICATION owns */
/* the public BaseView as a thin wrapper adding derived columns. This file sets the */
/* flags and carries the regenerated inner views; the NEXT file creates the wrappers. */
/* WHY THIS IS NOT IN THE BASELINE, given that everything else was folded into it. */
/* The layering is a SEQUENCE, not a state, and the ordering is forced twice over: */
/*   1. The flags live on __mj.Entity rows that DO NOT EXIST until the baseline's own */
/*      CodeGen capture inserts them. An UPDATE placed anywhere in the baseline is a */
/*      no-op against a row that is not there yet. */
/*   2. A wrapper view cannot be created before the view it selects FROM. SQL Server */
/*      has deferred name resolution for procedure bodies but NOT for views, so the */
/*      generated inner view has to exist first — which is why the wrappers are a */
/*      third file rather than the tail of this one. */
/* WHY THE FLAGS SHIP AS A MIGRATION AT ALL, rather than only in metadata/entities/. */
/* A fresh environment runs migrate -> codegen -> sync push. That FIRST codegen, seeing */
/* BaseViewGenerated = 1, resolves its target to the PUBLIC name and DROP/CREATEs */
/* vwContracts as a plain generated view — silently destroying the wrapper. Shipping the */
/* flags here means every environment that migrates has them before any codegen can run. */
/* Keyed by entity NAME, never by ID: entity IDs are minted at first registration, so a */
/* hardcoded UUID stops matching the first time a database is rebuilt from zero. Both */
/* UPDATEs skip cleanly when the row is absent. */
/* ⚠ THE CAPTURE BELOW EXISTS BECAUSE CODEGEN'S LOG AND ITS EXECUTION DISAGREE. CodeGen */
/* writes an object to its SQL output only for entities it considers MODIFIED, and */
/* flipping BaseViewGenerated does not count as a modification — but it still CREATEs */
/* vwContractsGenerated / vwContractTemplatesGenerated in the database it is pointed at. */
/* So a plain post-flag codegen run produces a capture with the two generated views */
/* MISSING, and the omission is invisible until a fresh install reaches the wrapper and */
/* fails on an object nothing ever created. The capture below was taken with */
/* forceRegeneration.baseViews scoped to these two entities, which is what makes it */
/* complete. If you ever re-capture this file, force base-view regeneration or check by */
/* name that both *Generated views are present. */
/* ============================================================================= */
UPDATE "__mj"."Entity" SET "BaseViewGenerated" = FALSE, "GeneratedBaseViewName" = 'vwContractsGenerated'
WHERE
  "Name" = 'MJ_BizApps_Contracts: Contracts'
  AND (
    "BaseViewGenerated" <> FALSE
    OR "GeneratedBaseViewName" IS NULL
    OR "GeneratedBaseViewName" <> 'vwContractsGenerated'
  );

UPDATE "__mj"."Entity" SET "BaseViewGenerated" = FALSE, "GeneratedBaseViewName" = 'vwContractTemplatesGenerated'
WHERE
  "Name" = 'MJ_BizApps_Contracts: Contract Templates'
  AND (
    "BaseViewGenerated" <> FALSE
    OR "GeneratedBaseViewName" IS NULL
    OR "GeneratedBaseViewName" <> 'vwContractTemplatesGenerated'
  );

/* SQL text to update existing entities from schema */
SELECT
  "__mj"."spUpdateExistingEntitiesFromSchema"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to update entity field related entity name field map for entity field ID 6DB0692A-42CD-4AC5-A43B-49ECC81EF370 */
SELECT
  "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"('6DB0692A-42CD-4AC5-A43B-49ECC81EF370', 'ParentContract');
/* SQL text to update entity field related entity name field map for entity field ID 44BC44EF-A6F2-4630-A899-487CE0E3CC56 */
SELECT
  "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"('44BC44EF-A6F2-4630-A899-487CE0E3CC56', 'SupersededByContract');
/* SQL text to update existing entity fields from schema */
SELECT
  "__mj"."spUpdateExistingEntityFieldsFromSchema"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to set default column width where needed */
SELECT
  "__mj"."spSetDefaultColumnWidthWhereNeeded"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to sync schema info from database schemas */
SELECT
  "__mj"."spUpdateSchemaInfoFromDatabase"(
    'sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks,__mj_BizAppsAccounting,__mj_BizAppsOrders,__mj'
  );
/* SQL text to update entity field related entity name field map for entity field ID 982E307B-667C-4955-99DE-F9A96FAB2CB2 */
SELECT
  "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"('982E307B-667C-4955-99DE-F9A96FAB2CB2', 'Contract');

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '98336d4e-6f80-4f25-bfec-827d94128191' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'Contract')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('98336d4e-6f80-4f25-bfec-827d94128191', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 8, 'Contract', 'Contract', NULL, 'nvarchar', 100, 0, 0, TRUE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '9c030856-2774-4c96-801f-e31e5f76edbb' OR ("EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' AND "Name" = 'ContractTemplateProvision')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('9c030856-2774-4c96-801f-e31e5f76edbb', 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225' /* Entity: MJ_BizApps_Contracts: Contract Template Modifications */, (SELECT COALESCE(MAX("Sequence"), 0) FROM "__mj"."EntityField" WHERE "EntityID" = 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225') + 9, 'ContractTemplateProvision', 'Contract Template Provision', NULL, 'nvarchar', 40, 0, 0, FALSE, NULL, FALSE, FALSE, TRUE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

-- ===================== CodeGen (native PG, baked) =====================

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Index for Foreign Keys
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_contract_template_type_id"
    ON "__mj_bizappscontracts"."ContractTemplate" ("ContractTemplateTypeID");

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: vwContractTemplatesGenerated
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Templates
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplate
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplatesGenerated"
AS
SELECT
    c.*,
    mjbizappscontractsContractTemplateType_ContractTemplateTypeID."Name" AS "ContractTemplateType"
FROM
    "__mj_bizappscontracts"."ContractTemplate" AS c
INNER JOIN
    "__mj_bizappscontracts"."ContractTemplateType" AS mjbizappscontractsContractTemplateType_ContractTemplateTypeID
  ON
    "c"."ContractTemplateTypeID" = mjbizappscontractsContractTemplateType_ContractTemplateTypeID."ID"
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
    AND tc.relname = 'vwContractTemplatesGenerated'
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
    AND tc.relname = 'vwContractTemplatesGenerated'
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
        AND tc.relname = 'vwContractTemplatesGenerated'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplatesGenerated" CASCADE;
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
  IF to_regclass('"__mj_bizappscontracts"."vwContractTemplates"') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Integration";';
  END IF;
END
$if_view_exists$;


DO $if_view_exists$
BEGIN
  IF to_regclass('"__mj_bizappscontracts"."vwContractTemplates"') IS NOT NULL THEN
    EXECUTE 'SELECT "__mj"."spRebindLayeredOuterView"(''__mj_bizappscontracts'', ''vwContractTemplates'', ''vwContractTemplatesGenerated'');';
  END IF;
END
$if_view_exists$;


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: Permissions for vwContractTemplates
-- ============================================================
DO $if_view_exists$
BEGIN
  IF to_regclass('"__mj_bizappscontracts"."vwContractTemplates"') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplates" TO "cdp_Integration";';
  END IF;
END
$if_view_exists$;


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spCreateContractTemplate
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate"(
    p_id UUID DEFAULT NULL,
    p_name varchar(200) DEFAULT NULL,
    p_contracttemplatetypeid UUID DEFAULT NULL,
    p_versionlabel_clear boolean DEFAULT false,
    p_versionlabel varchar(50) DEFAULT NULL,
    p_introduceddate_clear boolean DEFAULT false,
    p_introduceddate date DEFAULT NULL,
    p_sourceurl_clear boolean DEFAULT false,
    p_sourceurl varchar(1000) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(20) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplates" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplate"
        (
            "ID",
            "Name",
                "ContractTemplateTypeID",
                "VersionLabel",
                "IntroducedDate",
                "SourceURL",
                "Description",
                "Status"
        )
    VALUES
        (
            v_new_id,
            p_name,
                p_contracttemplatetypeid,
                CASE WHEN p_versionlabel_clear = true THEN NULL ELSE COALESCE(p_versionlabel, NULL) END,
                CASE WHEN p_introduceddate_clear = true THEN NULL ELSE COALESCE(p_introduceddate, NULL) END,
                CASE WHEN p_sourceurl_clear = true THEN NULL ELSE COALESCE(p_sourceurl, NULL) END,
                CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, NULL) END,
                COALESCE(p_status, 'Draft')
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplates"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplate" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spUpdateContractTemplate
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate"(
    p_id UUID,
    p_name varchar(200) DEFAULT NULL,
    p_contracttemplatetypeid UUID DEFAULT NULL,
    p_versionlabel_clear boolean DEFAULT false,
    p_versionlabel varchar(50) DEFAULT NULL,
    p_introduceddate_clear boolean DEFAULT false,
    p_introduceddate date DEFAULT NULL,
    p_sourceurl_clear boolean DEFAULT false,
    p_sourceurl varchar(1000) DEFAULT NULL,
    p_description_clear boolean DEFAULT false,
    p_description TEXT DEFAULT NULL,
    p_status varchar(20) DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplates" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplate"
    SET
        "Name" = COALESCE(p_name, "Name"),
        "ContractTemplateTypeID" = COALESCE(p_contracttemplatetypeid, "ContractTemplateTypeID"),
        "VersionLabel" = CASE WHEN p_versionlabel_clear = true THEN NULL ELSE COALESCE(p_versionlabel, "VersionLabel") END,
        "IntroducedDate" = CASE WHEN p_introduceddate_clear = true THEN NULL ELSE COALESCE(p_introduceddate, "IntroducedDate") END,
        "SourceURL" = CASE WHEN p_sourceurl_clear = true THEN NULL ELSE COALESCE(p_sourceurl, "SourceURL") END,
        "Description" = CASE WHEN p_description_clear = true THEN NULL ELSE COALESCE(p_description, "Description") END,
        "Status" = COALESCE(p_status, "Status")
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplates"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplate" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplate table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template" ON "__mj_bizappscontracts"."ContractTemplate";

CREATE TRIGGER "trg_update_contract_template"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplate"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Templates
-- Item: spDeleteContractTemplate
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplate
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplate'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplate"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplate" TO "cdp_Integration";

/* SQL text to update entity field related entity name field map for entity field ID 0864cb7f-e532-402f-9f16-102ec14993c6 */
SELECT * FROM "__mj"."spUpdateEntityFieldRelatedEntityNameFieldMap"(p_EntityFieldID => '0864cb7f-e532-402f-9f16-102ec14993c6', p_RelatedEntityNameFieldMap => 'ContractTemplateProvision');


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: Index for Foreign Keys
-- ============================================================
CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_modification_contract_id"
    ON "__mj_bizappscontracts"."ContractTemplateModification" ("ContractID");

CREATE INDEX IF NOT EXISTS "idx_auto_mj_fkey_contract_template_modification_contract_templa"
    ON "__mj_bizappscontracts"."ContractTemplateModification" ("ContractTemplateProvisionID");

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: vwContractTemplateModifications
-- ============================================================

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Template Modifications
-----               SCHEMA:      __mj_bizappscontracts
-----               BASE TABLE:  ContractTemplateModification
-----               PRIMARY KEY: ID
------------------------------------------------------------
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW "__mj_bizappscontracts"."vwContractTemplateModifications"
AS
SELECT
    c.*,
    mjbizappscontractsContract_ContractID."ContractNumber" AS "Contract",
    mjbizappscontractsContractTemplateProvision_ContractTemplateProvisionID."ProvisionNumber" AS "ContractTemplateProvision"
FROM
    "__mj_bizappscontracts"."ContractTemplateModification" AS c
INNER JOIN
    "__mj_bizappscontracts"."Contract" AS mjbizappscontractsContract_ContractID
  ON
    "c"."ContractID" = mjbizappscontractsContract_ContractID."ID"
INNER JOIN
    "__mj_bizappscontracts"."ContractTemplateProvision" AS mjbizappscontractsContractTemplateProvision_ContractTemplateProvisionID
  ON
    "c"."ContractTemplateProvisionID" = mjbizappscontractsContractTemplateProvision_ContractTemplateProvisionID."ID"
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
    AND tc.relname = 'vwContractTemplateModifications'
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
    AND tc.relname = 'vwContractTemplateModifications'
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
        AND tc.relname = 'vwContractTemplateModifications'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplateModifications" CASCADE;
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
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_UI";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Developer";
GRANT SELECT ON "__mj_bizappscontracts"."vwContractTemplateModifications" TO "cdp_Integration";

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spCreateContractTemplateModification
-- ============================================================

------------------------------------------------------------
----- CREATE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spCreateContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification"(
    p_id UUID DEFAULT NULL,
    p_contractid UUID DEFAULT NULL,
    p_contracttemplateprovisionid UUID DEFAULT NULL,
    p_modificationtext TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateModifications" AS $$
DECLARE
    v_new_id UUID;
BEGIN
    v_new_id := COALESCE(p_id, gen_random_uuid());
    INSERT INTO "__mj_bizappscontracts"."ContractTemplateModification"
        (
            "ID",
            "ContractID",
                "ContractTemplateProvisionID",
                "ModificationText",
                "Notes"
        )
    VALUES
        (
            v_new_id,
            p_contractid,
                p_contracttemplateprovisionid,
                p_modificationtext,
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END
        )
    ;

    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateModifications"
    WHERE "ID" = v_new_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContractTemplateModification" TO "cdp_Integration";


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spUpdateContractTemplateModification
-- ============================================================

------------------------------------------------------------
----- UPDATE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spUpdateContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification"(
    p_id UUID,
    p_contractid UUID DEFAULT NULL,
    p_contracttemplateprovisionid UUID DEFAULT NULL,
    p_modificationtext TEXT DEFAULT NULL,
    p_notes_clear boolean DEFAULT false,
    p_notes TEXT DEFAULT NULL
) RETURNS SETOF "__mj_bizappscontracts"."vwContractTemplateModifications" AS $$
DECLARE
    v_updated_count INTEGER;
BEGIN
    UPDATE "__mj_bizappscontracts"."ContractTemplateModification"
    SET
        "ContractID" = COALESCE(p_contractid, "ContractID"),
        "ContractTemplateProvisionID" = COALESCE(p_contracttemplateprovisionid, "ContractTemplateProvisionID"),
        "ModificationText" = COALESCE(p_modificationtext, "ModificationText"),
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END
    WHERE
        "ID" = p_id;

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    IF v_updated_count = 0 THEN
        -- Nothing was updated, return empty result set
        RETURN;
    END IF;

    -- Return the updated record from the base view
    RETURN QUERY
    SELECT * FROM "__mj_bizappscontracts"."vwContractTemplateModifications"
    WHERE "ID" = p_id;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContractTemplateModification" TO "cdp_Integration";


------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateModification table
------------------------------------------------------------
CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_modification"()
RETURNS TRIGGER AS $$
BEGIN
    NEW."__mj_UpdatedAt" := NOW() AT TIME ZONE 'UTC';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "trg_update_contract_template_modification" ON "__mj_bizappscontracts"."ContractTemplateModification";

CREATE TRIGGER "trg_update_contract_template_modification"
BEFORE UPDATE ON "__mj_bizappscontracts"."ContractTemplateModification"
FOR EACH ROW
EXECUTE FUNCTION "__mj_bizappscontracts"."fn_trg_update_contract_template_modification"();


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contract Template Modifications
-- Item: spDeleteContractTemplateModification
-- ============================================================

------------------------------------------------------------
----- DELETE FUNCTION FOR ContractTemplateModification
------------------------------------------------------------
DO $do$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT oid::regprocedure AS sig
             FROM pg_proc
             WHERE proname = 'spDeleteContractTemplateModification'
               AND pronamespace = '__mj_bizappscontracts'::regnamespace
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig::text;
    END LOOP;
END
$do$;

CREATE OR REPLACE FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification"(
    p_id UUID
) RETURNS TABLE("ID" UUID) AS $$
#variable_conflict use_column
DECLARE
    v_affected_count INTEGER;
BEGIN

    DELETE FROM "__mj_bizappscontracts"."ContractTemplateModification"
    WHERE "ID" = p_id;

    GET DIAGNOSTICS v_affected_count = ROW_COUNT;

    IF v_affected_count = 0 THEN
        RETURN QUERY SELECT NULL::UUID AS "ID";
    ELSE
        RETURN QUERY SELECT p_id AS "ID";
    END IF;
END;
$$ LANGUAGE plpgsql;
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContractTemplateModification" TO "cdp_Integration";

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
    p_notes TEXT DEFAULT NULL
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
                "Notes"
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
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END
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
    p_notes TEXT DEFAULT NULL
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
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END
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


-- ============================================================================
-- V202608240200__v0.1.x__Layered_base_views_and_derived_fields
-- ============================================================================
-- ---------------------------------------------------------------------------
-- From V202608240200: the application-owned wrapper views, and the columns they
-- add registered as virtual EntityFields (Sequence computed at apply time).
-- ParentContract and SupersededByContract are the joined name columns of the
-- generated inner view, registered here because no CodeGen run follows.
-- ---------------------------------------------------------------------------
-- vwContracts: the application-owned wrapper over CodeGen's vwContractsGenerated.
-- Replaced through CodeGen's dependency-safe block: the CRUD functions return this view's row type.
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
AS
SELECT
    g.*,
    CASE
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Active'
        WHEN g."ExecutedDate" IS NOT NULL THEN 'Executed'
        ELSE 'Draft'
    END AS "State",
    CASE
        WHEN ct."RequiresExecutedDocument" = TRUE
         AND NOT EXISTS (
                SELECT 1
                  FROM __mj."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM __mj."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts')
                   AND lower(fl."RecordID") = g."ID"::text
             )
        THEN TRUE ELSE FALSE
    END AS "IsAwaitingDocument",
    CASE WHEN g."EndDate" IS NULL THEN NULL
         ELSE (g."EndDate" - (NOW() AT TIME ZONE 'UTC')::date) END AS "DaysToEnd",
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE (g."EndDate" - g."RenewalNoticeDays") END AS "RenewalNoticeDeadline",
    CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND (NOW() AT TIME ZONE 'UTC')::date >= (g."EndDate" - g."CancellationWindowDays")
         AND (NOW() AT TIME ZONE 'UTC')::date <= g."EndDate"
        THEN TRUE ELSE FALSE
    END AS "IsInCancellationWindow"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID"$vsql$;
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";

-- vwContractTemplates: the application-owned wrapper adding IsUsable (a URL, or an attached file).
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContractTemplates"
AS
SELECT
    g.*,
    CASE
        WHEN g."SourceURL" IS NOT NULL AND length(btrim(g."SourceURL")) > 0 THEN TRUE
        WHEN EXISTS (
                SELECT 1
                  FROM __mj."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM __mj."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contract Templates')
                   AND lower(fl."RecordID") = g."ID"::text
             ) THEN TRUE
        ELSE FALSE
    END AS "IsUsable"
FROM
    __mj_bizappscontracts."vwContractTemplatesGenerated" AS g$vsql$;
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
    AND tc.relname = 'vwContractTemplates'
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
    AND tc.relname = 'vwContractTemplates'
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
        AND tc.relname = 'vwContractTemplates'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContractTemplates" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContractTemplates" TO "cdp_UI", "cdp_Developer", "cdp_Integration";

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'State', 'State', NULL, 'varchar', 10, 0, 0,
       FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'IsAwaitingDocument', 'Is Awaiting Document', NULL, 'bit', 1, 1, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'DaysToEnd', 'Days To End', NULL, 'int', 4, 10, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'RenewalNoticeDeadline', 'Renewal Notice Deadline', NULL, 'date', 3, 10, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'IsInCancellationWindow', 'Is In Cancellation Window', NULL, 'bit', 1, 1, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'IsUsable', 'Is Usable', 'Whether the standard terms this version names can actually be READ: it records a SourceURL, or a file is attached to it. Derived in vwContractTemplates — a tem', 'bit', 1, NULL, NULL,
       FALSE, TRUE, TRUE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contract Templates';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'ParentContract', 'Parent Contract', NULL, 'nvarchar', 100, 0, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';

INSERT INTO __mj."EntityField"
    ("EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length",
     "Precision", "Scale", "AllowsNull", "IsVirtual", "DefaultInView", "AllowUpdateAPI",
     "IncludeInGeneratedForm", "IsPrimaryKey", "IsUnique")
SELECT e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'SupersededByContract', 'Superseded By Contract', NULL, 'nvarchar', 100, 0, 0,
       TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, FALSE
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts';


-- ============================================================================
-- V202608240300__v0.1.x__Metadata_Sync
-- ============================================================================
-- ============================================================================
-- MemberJunction PostgreSQL Migration
-- Converted from SQL Server using TypeScript conversion pipeline
-- ============================================================================

-- Extensions

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


-- Ensure backslashes in string literals are treated literally (not as escape sequences)

-- NOTE: Earlier converter versions made INTEGER to BOOLEAN cast implicit by
-- modifying the system catalog so SS-style INSERT INTO bool_col VALUES (1)
-- would work. That modification required pg_catalog write privileges, which
-- managed PG (RDS, Aurora, Cloud SQL, Azure) does not grant. As of v5.30 all
-- bulk INSERTs are emitted with native TRUE/FALSE values directly, so the
-- cast modification is no longer needed. Removed to support managed-PG
-- installs out of the box.


-- ===================== Data (INSERT/UPDATE/DELETE) =====================

-- =============================================================================
-- V202608240300 — the reference vocabulary, as a migration.
-- =============================================================================
-- The seed data `mj sync push` writes from metadata/, captured so a FRESH INSTALL
-- gets it. This is the file whose absence made the old train produce bare tables:
-- an install runs migrations and NOTHING ELSE -- it never runs `sync push` -- so
-- vocabulary that only ever existed in metadata/ never arrived. metadata/ stays the
-- authoring source of record; this is how it reaches a database that will never run
-- the tool. Same convention (and same origin) as bizapps-common's and bizapps-tasks'
-- `__Metadata_Sync.sql`: the SQL logger's own output, committed.
--
-- WHAT IT SEEDS: 2 template types, 4 contract types, the entity/field/relationship
-- metadata the app declares (layered-view flags, form chrome, collection
-- declarations), and the Contracts application row. That is vocabulary and
-- structure -- nothing that belongs to a particular organisation.
--
-- ⚠ WHAT IT DELIBERATELY DOES NOT SEED, as of 2026-08-24. An earlier version of this
-- file carried a ContractTemplate and its 71 provisions -- Blue Cypress's actual Master
-- Services Agreement, verbatim. metadata/ is the INSTALL seed, so that shipped one
-- company's contract terms into every consumer's database as reference data. The
-- template and its provisions now live in `demo-data/`, pushed only when someone asks
-- for them (see demo-data/README.md, and plans/QUESTIONS.md Q-5 for the ruling). The
-- line: a KIND of contract is vocabulary and ships; a particular company's AGREEMENT is
-- content and does not.
--
-- REGENERATING IT: `sqlLogging` is enabled in metadata/.mj-sync.json (committed). Apply
-- the three schema migrations to an EMPTY database -- NOT this one, or the push has
-- nothing to do -- run `mj sync push --dir metadata`, then re-apply the two corrections
-- below. Do not hand-edit the statements.
--
-- ⚠ CORRECTION 1 -- THE PLACEHOLDERS COME OUT INVERTED, AND THE FILE IS DEAD WITHOUT
-- THIS FIX. `formatAsMigration` substitutes `__mj_bizappscontracts` for the MJ CORE
-- schema, which is right for a migration inside MJ itself and exactly wrong inside an
-- open app: here `__mj_bizappscontracts` resolves to __mj_bizappscontracts, so every
-- core call (spCreateApplication, spUpdateEntity, spUpdateEntityField,
-- spUpdateEntityRelationship) would look for a procedure in the app's own schema and
-- fail. The app's OWN calls were left as a literal schema name, which works but is not
-- portable. Both directions are swapped here: core -> `__mj`, app ->
-- `__mj_bizappscontracts`. bizapps-common hit the identical trap and documents it in
-- V202608140800__v5.34.x__Metadata_Sync.sql; filed upstream.
--
-- ⚠ CORRECTION 2 -- THE `MJ: User Applications` ROWS ARE REMOVED, deliberately. The push
-- enumerates the users that happen to exist in the database it is pointed at and writes
-- one row per user with a freshly-minted random ID. Neither half survives a move: the row
-- IDs are not reproducible across captures, and a hardcoded @UserID that does not exist
-- on the target install fails the foreign key. Granting a user access to the app is an
-- administrative act, not something a migration can know. The `MJ: Applications` row
-- itself IS kept -- that one is the app's own nav registration and is environment-
-- independent.
-- =============================================================================

-- SQL Logging Session
-- Session ID: d1c3204d-5a28-4007-96df-2cdc3d478801
-- Started: 2026-08-24T02:34:06.800Z
-- Description: MetadataSync push operation
-- Format: Migration-ready with Flyway schema placeholders
-- Generated by MemberJunction

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_91bee356 UUID;
  p_Name_91bee356 VARCHAR(255);
  p_NameSuffix_91bee356 VARCHAR(255);
  p_Description_91bee356 TEXT;
  p_AutoUpdateDescription_91bee356 BOOLEAN;
  p_BaseView_91bee356 VARCHAR(255);
  p_BaseViewGenerated_91bee356 BOOLEAN;
  p_VirtualEntity_91bee356 BOOLEAN;
  p_TrackRecordChanges_91bee356 BOOLEAN;
  p_AuditRecordAccess_91bee356 BOOLEAN;
  p_AuditViewRuns_91bee356 BOOLEAN;
  p_IncludeInAPI_91bee356 BOOLEAN;
  p_AllowAllRowsAPI_91bee356 BOOLEAN;
  p_AllowUpdateAPI_91bee356 BOOLEAN;
  p_AllowCreateAPI_91bee356 BOOLEAN;
  p_AllowDeleteAPI_91bee356 BOOLEAN;
  p_CustomResolverAPI_91bee356 BOOLEAN;
  p_AllowUserSearchAPI_91bee356 BOOLEAN;
  p_FullTextSearchEnabled_91bee356 BOOLEAN;
  p_FullTextCatalog_91bee356 VARCHAR(255);
  p_FullTextCatalogGenerated_91bee356 BOOLEAN;
  p_FullTextIndex_91bee356 VARCHAR(255);
  p_FullTextIndexGenerated_91bee356 BOOLEAN;
  p_FullTextSearchFunction_91bee356 VARCHAR(255);
  p_FullTextSearchFunctionGenerated_91bee356 BOOLEAN;
  p_UserViewMaxRows_91bee356 INTEGER;
  p_spCreate_91bee356 VARCHAR(255);
  p_spUpdate_91bee356 VARCHAR(255);
  p_spDelete_91bee356 VARCHAR(255);
  p_spCreateGenerated_91bee356 BOOLEAN;
  p_spUpdateGenerated_91bee356 BOOLEAN;
  p_spDeleteGenerated_91bee356 BOOLEAN;
  p_CascadeDeletes_91bee356 BOOLEAN;
  p_DeleteType_91bee356 VARCHAR(10);
  p_AllowRecordMerge_91bee356 BOOLEAN;
  p_spMatch_91bee356 VARCHAR(255);
  p_RelationshipDefaultDisplayType_91bee356 VARCHAR(20);
  p_UserFormGenerated_91bee356 BOOLEAN;
  p_EntityObjectSubclassName_91bee356 VARCHAR(255);
  p_EntityObjectSubclassImport_91bee356 VARCHAR(255);
  p_PreferredCommunicationField_91bee356 VARCHAR(255);
  p_Icon_91bee356 VARCHAR(500);
  p_ScopeDefault_91bee356 VARCHAR(100);
  p_RowsToPackWithSchema_91bee356 VARCHAR(20);
  p_RowsToPackSampleMethod_91bee356 VARCHAR(20);
  p_RowsToPackSampleCount_91bee356 INTEGER;
  p_RowsToPackSampleOrder_91bee356 TEXT;
  p_AutoRowCountFrequency_91bee356 INTEGER;
  p_RowCount_91bee356 BIGINT;
  p_RowCountRunAt_91bee356 TIMESTAMPTZ;
  p_Status_91bee356 VARCHAR(25);
  p_DisplayName_91bee356 VARCHAR(255);
  p_AllowMultipleSubtypes_91bee356 BOOLEAN;
  p_AutoUpdateFullTextSearch_91bee356 BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_91bee356 BOOLEAN;
  p_TrustServerCacheCompletely_91bee356 BOOLEAN;
  p_SupportsGeoCoding_91bee356 BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_91bee356 BOOLEAN;
  p_AllowCaching_91bee356 BOOLEAN;
  p_DetectExternalChanges_91bee356 BOOLEAN;
  p_ExternalDataSourceID_91bee356 UUID;
  p_ExternalObjectName_91bee356 VARCHAR(255);
  p_GeneratedBaseViewName_91bee356 VARCHAR(255);
  p_AllowDirectSQLInsert_91bee356 BOOLEAN;
  p_AllowDirectSQLUpdate_91bee356 BOOLEAN;
  p_AllowDirectSQLDelete_91bee356 BOOLEAN;
  p_Configuration_91bee356 TEXT;
  p_ID_91bee356 UUID;
BEGIN
  p_Name_91bee356 := 'MJ_BizApps_Contracts: Contract Templates';
  p_Description_91bee356 := 'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.';
  p_AutoUpdateDescription_91bee356 := TRUE;
  p_BaseView_91bee356 := 'vwContractTemplates';
  p_BaseViewGenerated_91bee356 := FALSE;
  p_VirtualEntity_91bee356 := FALSE;
  p_TrackRecordChanges_91bee356 := TRUE;
  p_AuditRecordAccess_91bee356 := FALSE;
  p_AuditViewRuns_91bee356 := FALSE;
  p_IncludeInAPI_91bee356 := TRUE;
  p_AllowAllRowsAPI_91bee356 := FALSE;
  p_AllowUpdateAPI_91bee356 := TRUE;
  p_AllowCreateAPI_91bee356 := TRUE;
  p_AllowDeleteAPI_91bee356 := TRUE;
  p_CustomResolverAPI_91bee356 := FALSE;
  p_AllowUserSearchAPI_91bee356 := TRUE;
  p_FullTextSearchEnabled_91bee356 := FALSE;
  p_FullTextCatalogGenerated_91bee356 := TRUE;
  p_FullTextIndexGenerated_91bee356 := TRUE;
  p_FullTextSearchFunctionGenerated_91bee356 := TRUE;
  p_UserViewMaxRows_91bee356 := 1000;
  p_spCreateGenerated_91bee356 := TRUE;
  p_spUpdateGenerated_91bee356 := TRUE;
  p_spDeleteGenerated_91bee356 := TRUE;
  p_CascadeDeletes_91bee356 := FALSE;
  p_DeleteType_91bee356 := 'Hard';
  p_AllowRecordMerge_91bee356 := FALSE;
  p_RelationshipDefaultDisplayType_91bee356 := 'Search';
  p_UserFormGenerated_91bee356 := TRUE;
  p_Icon_91bee356 := 'fa fa-file-contract';
  p_RowsToPackWithSchema_91bee356 := 'None';
  p_RowsToPackSampleMethod_91bee356 := 'random';
  p_RowsToPackSampleCount_91bee356 := 0;
  p_Status_91bee356 := 'Active';
  p_DisplayName_91bee356 := 'Contract Templates';
  p_AllowMultipleSubtypes_91bee356 := FALSE;
  p_AutoUpdateFullTextSearch_91bee356 := TRUE;
  p_AutoUpdateAllowUserSearchAPI_91bee356 := TRUE;
  p_TrustServerCacheCompletely_91bee356 := TRUE;
  p_SupportsGeoCoding_91bee356 := FALSE;
  p_AutoUpdateSupportsGeoCoding_91bee356 := TRUE;
  p_AllowCaching_91bee356 := FALSE;
  p_DetectExternalChanges_91bee356 := FALSE;
  p_GeneratedBaseViewName_91bee356 := 'vwContractTemplatesGenerated';
  p_AllowDirectSQLInsert_91bee356 := FALSE;
  p_AllowDirectSQLUpdate_91bee356 := FALSE;
  p_AllowDirectSQLDelete_91bee356 := FALSE;
  p_Configuration_91bee356 := '{
  "UI": {
    "Form": {
      "Layout": "left-nav",
      "RelatedRolePolicy": "smart",
      "PrimaryRelatedBudget": 4
    }
  }
}';
  p_ID_91bee356 := '731F2890-1415-40DE-9073-D22EA23392B3';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntity'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_91bee356,
    'Name', p_Name_91bee356,
    'NameSuffix', p_NameSuffix_91bee356,
    'Description', p_Description_91bee356,
    'AutoUpdateDescription', p_AutoUpdateDescription_91bee356,
    'BaseView', p_BaseView_91bee356,
    'BaseViewGenerated', p_BaseViewGenerated_91bee356,
    'VirtualEntity', p_VirtualEntity_91bee356,
    'TrackRecordChanges', p_TrackRecordChanges_91bee356,
    'AuditRecordAccess', p_AuditRecordAccess_91bee356,
    'AuditViewRuns', p_AuditViewRuns_91bee356,
    'IncludeInAPI', p_IncludeInAPI_91bee356,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_91bee356,
    'AllowUpdateAPI', p_AllowUpdateAPI_91bee356,
    'AllowCreateAPI', p_AllowCreateAPI_91bee356,
    'AllowDeleteAPI', p_AllowDeleteAPI_91bee356,
    'CustomResolverAPI', p_CustomResolverAPI_91bee356,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_91bee356,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_91bee356,
    'FullTextCatalog', p_FullTextCatalog_91bee356,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_91bee356,
    'FullTextIndex', p_FullTextIndex_91bee356,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_91bee356,
    'FullTextSearchFunction', p_FullTextSearchFunction_91bee356,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_91bee356,
    'UserViewMaxRows', p_UserViewMaxRows_91bee356,
    'spCreate', p_spCreate_91bee356,
    'spUpdate', p_spUpdate_91bee356,
    'spDelete', p_spDelete_91bee356,
    'spCreateGenerated', p_spCreateGenerated_91bee356,
    'spUpdateGenerated', p_spUpdateGenerated_91bee356,
    'spDeleteGenerated', p_spDeleteGenerated_91bee356,
    'CascadeDeletes', p_CascadeDeletes_91bee356,
    'DeleteType', p_DeleteType_91bee356,
    'AllowRecordMerge', p_AllowRecordMerge_91bee356,
    'spMatch', p_spMatch_91bee356,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_91bee356,
    'UserFormGenerated', p_UserFormGenerated_91bee356,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_91bee356,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_91bee356,
    'PreferredCommunicationField', p_PreferredCommunicationField_91bee356,
    'Icon', p_Icon_91bee356,
    'ScopeDefault', p_ScopeDefault_91bee356,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_91bee356,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_91bee356,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_91bee356,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_91bee356,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_91bee356,
    'RowCount', p_RowCount_91bee356,
    'RowCountRunAt', p_RowCountRunAt_91bee356
  ) ||
  jsonb_build_object(
    'Status', p_Status_91bee356,
    'DisplayName', p_DisplayName_91bee356,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_91bee356,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_91bee356,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_91bee356,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_91bee356,
    'SupportsGeoCoding', p_SupportsGeoCoding_91bee356,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_91bee356,
    'AllowCaching', p_AllowCaching_91bee356,
    'DetectExternalChanges', p_DetectExternalChanges_91bee356,
    'ExternalDataSourceID', p_ExternalDataSourceID_91bee356,
    'ExternalObjectName', p_ExternalObjectName_91bee356,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_91bee356,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_91bee356,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_91bee356,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_91bee356,
    'Configuration', p_Configuration_91bee356,
    'ID', p_ID_91bee356
  ));
  ELSE
    PERFORM __mj."spUpdateEntity"(p_ParentID := p_ParentID_91bee356, p_ParentID_Clear := TRUE, p_Name := p_Name_91bee356, p_NameSuffix := p_NameSuffix_91bee356, p_NameSuffix_Clear := TRUE, p_Description := p_Description_91bee356, p_AutoUpdateDescription := p_AutoUpdateDescription_91bee356, p_BaseView := p_BaseView_91bee356, p_BaseViewGenerated := p_BaseViewGenerated_91bee356, p_VirtualEntity := p_VirtualEntity_91bee356, p_TrackRecordChanges := p_TrackRecordChanges_91bee356, p_AuditRecordAccess := p_AuditRecordAccess_91bee356, p_AuditViewRuns := p_AuditViewRuns_91bee356, p_IncludeInAPI := p_IncludeInAPI_91bee356, p_AllowAllRowsAPI := p_AllowAllRowsAPI_91bee356, p_AllowUpdateAPI := p_AllowUpdateAPI_91bee356, p_AllowCreateAPI := p_AllowCreateAPI_91bee356, p_AllowDeleteAPI := p_AllowDeleteAPI_91bee356, p_CustomResolverAPI := p_CustomResolverAPI_91bee356, p_AllowUserSearchAPI := p_AllowUserSearchAPI_91bee356, p_FullTextSearchEnabled := p_FullTextSearchEnabled_91bee356, p_FullTextCatalog := p_FullTextCatalog_91bee356, p_FullTextCatalog_Clear := TRUE, p_FullTextCatalogGenerated := p_FullTextCatalogGenerated_91bee356, p_FullTextIndex := p_FullTextIndex_91bee356, p_FullTextIndex_Clear := TRUE, p_FullTextIndexGenerated := p_FullTextIndexGenerated_91bee356, p_FullTextSearchFunction := p_FullTextSearchFunction_91bee356, p_FullTextSearchFunction_Clear := TRUE, p_FullTextSearchFunctionGenerated := p_FullTextSearchFunctionGenerated_91bee356, p_UserViewMaxRows := p_UserViewMaxRows_91bee356, p_spCreate := p_spCreate_91bee356, p_spCreate_Clear := TRUE, p_spUpdate := p_spUpdate_91bee356, p_spUpdate_Clear := TRUE, p_spDelete := p_spDelete_91bee356, p_spDelete_Clear := TRUE, p_spCreateGenerated := p_spCreateGenerated_91bee356, p_spUpdateGenerated := p_spUpdateGenerated_91bee356, p_spDeleteGenerated := p_spDeleteGenerated_91bee356, p_CascadeDeletes := p_CascadeDeletes_91bee356, p_DeleteType := p_DeleteType_91bee356, p_AllowRecordMerge := p_AllowRecordMerge_91bee356, p_spMatch := p_spMatch_91bee356, p_spMatch_Clear := TRUE, p_RelationshipDefaultDisplayType := p_RelationshipDefaultDisplayType_91bee356, p_UserFormGenerated := p_UserFormGenerated_91bee356, p_EntityObjectSubclassName := p_EntityObjectSubclassName_91bee356, p_EntityObjectSubclassName_Clear := TRUE, p_EntityObjectSubclassImport := p_EntityObjectSubclassImport_91bee356, p_EntityObjectSubclassImport_Clear := TRUE, p_PreferredCommunicationField := p_PreferredCommunicationField_91bee356, p_PreferredCommunicationField_Clear := TRUE, p_Icon := p_Icon_91bee356, p_ScopeDefault := p_ScopeDefault_91bee356, p_ScopeDefault_Clear := TRUE, p_RowsToPackWithSchema := p_RowsToPackWithSchema_91bee356, p_RowsToPackSampleMethod := p_RowsToPackSampleMethod_91bee356, p_RowsToPackSampleCount := p_RowsToPackSampleCount_91bee356, p_RowsToPackSampleOrder := p_RowsToPackSampleOrder_91bee356, p_RowsToPackSampleOrder_Clear := TRUE, p_AutoRowCountFrequency := p_AutoRowCountFrequency_91bee356, p_AutoRowCountFrequency_Clear := TRUE, p_RowCount := p_RowCount_91bee356, p_RowCount_Clear := TRUE, p_RowCountRunAt := p_RowCountRunAt_91bee356, p_RowCountRunAt_Clear := TRUE, p_Status := p_Status_91bee356, p_DisplayName := p_DisplayName_91bee356, p_AllowMultipleSubtypes := p_AllowMultipleSubtypes_91bee356, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_91bee356, p_AutoUpdateAllowUserSearchAPI := p_AutoUpdateAllowUserSearchAPI_91bee356, p_TrustServerCacheCompletely := p_TrustServerCacheCompletely_91bee356, p_SupportsGeoCoding := p_SupportsGeoCoding_91bee356, p_AutoUpdateSupportsGeoCoding := p_AutoUpdateSupportsGeoCoding_91bee356, p_AllowCaching := p_AllowCaching_91bee356, p_DetectExternalChanges := p_DetectExternalChanges_91bee356, p_ExternalDataSourceID := p_ExternalDataSourceID_91bee356, p_ExternalDataSourceID_Clear := TRUE, p_ExternalObjectName := p_ExternalObjectName_91bee356, p_ExternalObjectName_Clear := TRUE, p_GeneratedBaseViewName := p_GeneratedBaseViewName_91bee356, p_AllowDirectSQLInsert := p_AllowDirectSQLInsert_91bee356, p_AllowDirectSQLUpdate := p_AllowDirectSQLUpdate_91bee356, p_AllowDirectSQLDelete := p_AllowDirectSQLDelete_91bee356, p_Configuration := p_Configuration_91bee356, p_ID := p_ID_91bee356);
  END IF;
END $mj$;

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_38ee20b2 UUID;
  p_Name_38ee20b2 VARCHAR(255);
  p_NameSuffix_38ee20b2 VARCHAR(255);
  p_Description_38ee20b2 TEXT;
  p_AutoUpdateDescription_38ee20b2 BOOLEAN;
  p_BaseView_38ee20b2 VARCHAR(255);
  p_BaseViewGenerated_38ee20b2 BOOLEAN;
  p_VirtualEntity_38ee20b2 BOOLEAN;
  p_TrackRecordChanges_38ee20b2 BOOLEAN;
  p_AuditRecordAccess_38ee20b2 BOOLEAN;
  p_AuditViewRuns_38ee20b2 BOOLEAN;
  p_IncludeInAPI_38ee20b2 BOOLEAN;
  p_AllowAllRowsAPI_38ee20b2 BOOLEAN;
  p_AllowUpdateAPI_38ee20b2 BOOLEAN;
  p_AllowCreateAPI_38ee20b2 BOOLEAN;
  p_AllowDeleteAPI_38ee20b2 BOOLEAN;
  p_CustomResolverAPI_38ee20b2 BOOLEAN;
  p_AllowUserSearchAPI_38ee20b2 BOOLEAN;
  p_FullTextSearchEnabled_38ee20b2 BOOLEAN;
  p_FullTextCatalog_38ee20b2 VARCHAR(255);
  p_FullTextCatalogGenerated_38ee20b2 BOOLEAN;
  p_FullTextIndex_38ee20b2 VARCHAR(255);
  p_FullTextIndexGenerated_38ee20b2 BOOLEAN;
  p_FullTextSearchFunction_38ee20b2 VARCHAR(255);
  p_FullTextSearchFunctionGenerated_38ee20b2 BOOLEAN;
  p_UserViewMaxRows_38ee20b2 INTEGER;
  p_spCreate_38ee20b2 VARCHAR(255);
  p_spUpdate_38ee20b2 VARCHAR(255);
  p_spDelete_38ee20b2 VARCHAR(255);
  p_spCreateGenerated_38ee20b2 BOOLEAN;
  p_spUpdateGenerated_38ee20b2 BOOLEAN;
  p_spDeleteGenerated_38ee20b2 BOOLEAN;
  p_CascadeDeletes_38ee20b2 BOOLEAN;
  p_DeleteType_38ee20b2 VARCHAR(10);
  p_AllowRecordMerge_38ee20b2 BOOLEAN;
  p_spMatch_38ee20b2 VARCHAR(255);
  p_RelationshipDefaultDisplayType_38ee20b2 VARCHAR(20);
  p_UserFormGenerated_38ee20b2 BOOLEAN;
  p_EntityObjectSubclassName_38ee20b2 VARCHAR(255);
  p_EntityObjectSubclassImport_38ee20b2 VARCHAR(255);
  p_PreferredCommunicationField_38ee20b2 VARCHAR(255);
  p_Icon_38ee20b2 VARCHAR(500);
  p_ScopeDefault_38ee20b2 VARCHAR(100);
  p_RowsToPackWithSchema_38ee20b2 VARCHAR(20);
  p_RowsToPackSampleMethod_38ee20b2 VARCHAR(20);
  p_RowsToPackSampleCount_38ee20b2 INTEGER;
  p_RowsToPackSampleOrder_38ee20b2 TEXT;
  p_AutoRowCountFrequency_38ee20b2 INTEGER;
  p_RowCount_38ee20b2 BIGINT;
  p_RowCountRunAt_38ee20b2 TIMESTAMPTZ;
  p_Status_38ee20b2 VARCHAR(25);
  p_DisplayName_38ee20b2 VARCHAR(255);
  p_AllowMultipleSubtypes_38ee20b2 BOOLEAN;
  p_AutoUpdateFullTextSearch_38ee20b2 BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_38ee20b2 BOOLEAN;
  p_TrustServerCacheCompletely_38ee20b2 BOOLEAN;
  p_SupportsGeoCoding_38ee20b2 BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_38ee20b2 BOOLEAN;
  p_AllowCaching_38ee20b2 BOOLEAN;
  p_DetectExternalChanges_38ee20b2 BOOLEAN;
  p_ExternalDataSourceID_38ee20b2 UUID;
  p_ExternalObjectName_38ee20b2 VARCHAR(255);
  p_GeneratedBaseViewName_38ee20b2 VARCHAR(255);
  p_AllowDirectSQLInsert_38ee20b2 BOOLEAN;
  p_AllowDirectSQLUpdate_38ee20b2 BOOLEAN;
  p_AllowDirectSQLDelete_38ee20b2 BOOLEAN;
  p_Configuration_38ee20b2 TEXT;
  p_ID_38ee20b2 UUID;
BEGIN
  p_Name_38ee20b2 := 'MJ_BizApps_Contracts: Contracts';
  p_Description_38ee20b2 := 'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.';
  p_AutoUpdateDescription_38ee20b2 := TRUE;
  p_BaseView_38ee20b2 := 'vwContracts';
  p_BaseViewGenerated_38ee20b2 := FALSE;
  p_VirtualEntity_38ee20b2 := FALSE;
  p_TrackRecordChanges_38ee20b2 := TRUE;
  p_AuditRecordAccess_38ee20b2 := FALSE;
  p_AuditViewRuns_38ee20b2 := FALSE;
  p_IncludeInAPI_38ee20b2 := TRUE;
  p_AllowAllRowsAPI_38ee20b2 := FALSE;
  p_AllowUpdateAPI_38ee20b2 := TRUE;
  p_AllowCreateAPI_38ee20b2 := TRUE;
  p_AllowDeleteAPI_38ee20b2 := TRUE;
  p_CustomResolverAPI_38ee20b2 := FALSE;
  p_AllowUserSearchAPI_38ee20b2 := TRUE;
  p_FullTextSearchEnabled_38ee20b2 := FALSE;
  p_FullTextCatalogGenerated_38ee20b2 := TRUE;
  p_FullTextIndexGenerated_38ee20b2 := TRUE;
  p_FullTextSearchFunctionGenerated_38ee20b2 := TRUE;
  p_UserViewMaxRows_38ee20b2 := 1000;
  p_spCreateGenerated_38ee20b2 := TRUE;
  p_spUpdateGenerated_38ee20b2 := TRUE;
  p_spDeleteGenerated_38ee20b2 := TRUE;
  p_CascadeDeletes_38ee20b2 := FALSE;
  p_DeleteType_38ee20b2 := 'Hard';
  p_AllowRecordMerge_38ee20b2 := FALSE;
  p_RelationshipDefaultDisplayType_38ee20b2 := 'Search';
  p_UserFormGenerated_38ee20b2 := TRUE;
  p_Icon_38ee20b2 := 'fa fa-file-contract';
  p_RowsToPackWithSchema_38ee20b2 := 'None';
  p_RowsToPackSampleMethod_38ee20b2 := 'random';
  p_RowsToPackSampleCount_38ee20b2 := 0;
  p_Status_38ee20b2 := 'Active';
  p_DisplayName_38ee20b2 := 'Contracts';
  p_AllowMultipleSubtypes_38ee20b2 := FALSE;
  p_AutoUpdateFullTextSearch_38ee20b2 := TRUE;
  p_AutoUpdateAllowUserSearchAPI_38ee20b2 := TRUE;
  p_TrustServerCacheCompletely_38ee20b2 := TRUE;
  p_SupportsGeoCoding_38ee20b2 := FALSE;
  p_AutoUpdateSupportsGeoCoding_38ee20b2 := TRUE;
  p_AllowCaching_38ee20b2 := FALSE;
  p_DetectExternalChanges_38ee20b2 := FALSE;
  p_GeneratedBaseViewName_38ee20b2 := 'vwContractsGenerated';
  p_AllowDirectSQLInsert_38ee20b2 := FALSE;
  p_AllowDirectSQLUpdate_38ee20b2 := FALSE;
  p_AllowDirectSQLDelete_38ee20b2 := FALSE;
  p_Configuration_38ee20b2 := '{
  "UI": {
    "Form": {
      "Layout": "left-nav",
      "RelatedRolePolicy": "smart",
      "PrimaryRelatedBudget": 6
    }
  }
}';
  p_ID_38ee20b2 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntity'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_38ee20b2,
    'Name', p_Name_38ee20b2,
    'NameSuffix', p_NameSuffix_38ee20b2,
    'Description', p_Description_38ee20b2,
    'AutoUpdateDescription', p_AutoUpdateDescription_38ee20b2,
    'BaseView', p_BaseView_38ee20b2,
    'BaseViewGenerated', p_BaseViewGenerated_38ee20b2,
    'VirtualEntity', p_VirtualEntity_38ee20b2,
    'TrackRecordChanges', p_TrackRecordChanges_38ee20b2,
    'AuditRecordAccess', p_AuditRecordAccess_38ee20b2,
    'AuditViewRuns', p_AuditViewRuns_38ee20b2,
    'IncludeInAPI', p_IncludeInAPI_38ee20b2,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_38ee20b2,
    'AllowUpdateAPI', p_AllowUpdateAPI_38ee20b2,
    'AllowCreateAPI', p_AllowCreateAPI_38ee20b2,
    'AllowDeleteAPI', p_AllowDeleteAPI_38ee20b2,
    'CustomResolverAPI', p_CustomResolverAPI_38ee20b2,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_38ee20b2,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_38ee20b2,
    'FullTextCatalog', p_FullTextCatalog_38ee20b2,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_38ee20b2,
    'FullTextIndex', p_FullTextIndex_38ee20b2,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_38ee20b2,
    'FullTextSearchFunction', p_FullTextSearchFunction_38ee20b2,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_38ee20b2,
    'UserViewMaxRows', p_UserViewMaxRows_38ee20b2,
    'spCreate', p_spCreate_38ee20b2,
    'spUpdate', p_spUpdate_38ee20b2,
    'spDelete', p_spDelete_38ee20b2,
    'spCreateGenerated', p_spCreateGenerated_38ee20b2,
    'spUpdateGenerated', p_spUpdateGenerated_38ee20b2,
    'spDeleteGenerated', p_spDeleteGenerated_38ee20b2,
    'CascadeDeletes', p_CascadeDeletes_38ee20b2,
    'DeleteType', p_DeleteType_38ee20b2,
    'AllowRecordMerge', p_AllowRecordMerge_38ee20b2,
    'spMatch', p_spMatch_38ee20b2,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_38ee20b2,
    'UserFormGenerated', p_UserFormGenerated_38ee20b2,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_38ee20b2,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_38ee20b2,
    'PreferredCommunicationField', p_PreferredCommunicationField_38ee20b2,
    'Icon', p_Icon_38ee20b2,
    'ScopeDefault', p_ScopeDefault_38ee20b2,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_38ee20b2,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_38ee20b2,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_38ee20b2,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_38ee20b2,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_38ee20b2,
    'RowCount', p_RowCount_38ee20b2,
    'RowCountRunAt', p_RowCountRunAt_38ee20b2
  ) ||
  jsonb_build_object(
    'Status', p_Status_38ee20b2,
    'DisplayName', p_DisplayName_38ee20b2,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_38ee20b2,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_38ee20b2,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_38ee20b2,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_38ee20b2,
    'SupportsGeoCoding', p_SupportsGeoCoding_38ee20b2,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_38ee20b2,
    'AllowCaching', p_AllowCaching_38ee20b2,
    'DetectExternalChanges', p_DetectExternalChanges_38ee20b2,
    'ExternalDataSourceID', p_ExternalDataSourceID_38ee20b2,
    'ExternalObjectName', p_ExternalObjectName_38ee20b2,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_38ee20b2,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_38ee20b2,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_38ee20b2,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_38ee20b2,
    'Configuration', p_Configuration_38ee20b2,
    'ID', p_ID_38ee20b2
  ));
  ELSE
    PERFORM __mj."spUpdateEntity"(p_ParentID := p_ParentID_38ee20b2, p_ParentID_Clear := TRUE, p_Name := p_Name_38ee20b2, p_NameSuffix := p_NameSuffix_38ee20b2, p_NameSuffix_Clear := TRUE, p_Description := p_Description_38ee20b2, p_AutoUpdateDescription := p_AutoUpdateDescription_38ee20b2, p_BaseView := p_BaseView_38ee20b2, p_BaseViewGenerated := p_BaseViewGenerated_38ee20b2, p_VirtualEntity := p_VirtualEntity_38ee20b2, p_TrackRecordChanges := p_TrackRecordChanges_38ee20b2, p_AuditRecordAccess := p_AuditRecordAccess_38ee20b2, p_AuditViewRuns := p_AuditViewRuns_38ee20b2, p_IncludeInAPI := p_IncludeInAPI_38ee20b2, p_AllowAllRowsAPI := p_AllowAllRowsAPI_38ee20b2, p_AllowUpdateAPI := p_AllowUpdateAPI_38ee20b2, p_AllowCreateAPI := p_AllowCreateAPI_38ee20b2, p_AllowDeleteAPI := p_AllowDeleteAPI_38ee20b2, p_CustomResolverAPI := p_CustomResolverAPI_38ee20b2, p_AllowUserSearchAPI := p_AllowUserSearchAPI_38ee20b2, p_FullTextSearchEnabled := p_FullTextSearchEnabled_38ee20b2, p_FullTextCatalog := p_FullTextCatalog_38ee20b2, p_FullTextCatalog_Clear := TRUE, p_FullTextCatalogGenerated := p_FullTextCatalogGenerated_38ee20b2, p_FullTextIndex := p_FullTextIndex_38ee20b2, p_FullTextIndex_Clear := TRUE, p_FullTextIndexGenerated := p_FullTextIndexGenerated_38ee20b2, p_FullTextSearchFunction := p_FullTextSearchFunction_38ee20b2, p_FullTextSearchFunction_Clear := TRUE, p_FullTextSearchFunctionGenerated := p_FullTextSearchFunctionGenerated_38ee20b2, p_UserViewMaxRows := p_UserViewMaxRows_38ee20b2, p_spCreate := p_spCreate_38ee20b2, p_spCreate_Clear := TRUE, p_spUpdate := p_spUpdate_38ee20b2, p_spUpdate_Clear := TRUE, p_spDelete := p_spDelete_38ee20b2, p_spDelete_Clear := TRUE, p_spCreateGenerated := p_spCreateGenerated_38ee20b2, p_spUpdateGenerated := p_spUpdateGenerated_38ee20b2, p_spDeleteGenerated := p_spDeleteGenerated_38ee20b2, p_CascadeDeletes := p_CascadeDeletes_38ee20b2, p_DeleteType := p_DeleteType_38ee20b2, p_AllowRecordMerge := p_AllowRecordMerge_38ee20b2, p_spMatch := p_spMatch_38ee20b2, p_spMatch_Clear := TRUE, p_RelationshipDefaultDisplayType := p_RelationshipDefaultDisplayType_38ee20b2, p_UserFormGenerated := p_UserFormGenerated_38ee20b2, p_EntityObjectSubclassName := p_EntityObjectSubclassName_38ee20b2, p_EntityObjectSubclassName_Clear := TRUE, p_EntityObjectSubclassImport := p_EntityObjectSubclassImport_38ee20b2, p_EntityObjectSubclassImport_Clear := TRUE, p_PreferredCommunicationField := p_PreferredCommunicationField_38ee20b2, p_PreferredCommunicationField_Clear := TRUE, p_Icon := p_Icon_38ee20b2, p_ScopeDefault := p_ScopeDefault_38ee20b2, p_ScopeDefault_Clear := TRUE, p_RowsToPackWithSchema := p_RowsToPackWithSchema_38ee20b2, p_RowsToPackSampleMethod := p_RowsToPackSampleMethod_38ee20b2, p_RowsToPackSampleCount := p_RowsToPackSampleCount_38ee20b2, p_RowsToPackSampleOrder := p_RowsToPackSampleOrder_38ee20b2, p_RowsToPackSampleOrder_Clear := TRUE, p_AutoRowCountFrequency := p_AutoRowCountFrequency_38ee20b2, p_AutoRowCountFrequency_Clear := TRUE, p_RowCount := p_RowCount_38ee20b2, p_RowCount_Clear := TRUE, p_RowCountRunAt := p_RowCountRunAt_38ee20b2, p_RowCountRunAt_Clear := TRUE, p_Status := p_Status_38ee20b2, p_DisplayName := p_DisplayName_38ee20b2, p_AllowMultipleSubtypes := p_AllowMultipleSubtypes_38ee20b2, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_38ee20b2, p_AutoUpdateAllowUserSearchAPI := p_AutoUpdateAllowUserSearchAPI_38ee20b2, p_TrustServerCacheCompletely := p_TrustServerCacheCompletely_38ee20b2, p_SupportsGeoCoding := p_SupportsGeoCoding_38ee20b2, p_AutoUpdateSupportsGeoCoding := p_AutoUpdateSupportsGeoCoding_38ee20b2, p_AllowCaching := p_AllowCaching_38ee20b2, p_DetectExternalChanges := p_DetectExternalChanges_38ee20b2, p_ExternalDataSourceID := p_ExternalDataSourceID_38ee20b2, p_ExternalDataSourceID_Clear := TRUE, p_ExternalObjectName := p_ExternalObjectName_38ee20b2, p_ExternalObjectName_Clear := TRUE, p_GeneratedBaseViewName := p_GeneratedBaseViewName_38ee20b2, p_AllowDirectSQLInsert := p_AllowDirectSQLInsert_38ee20b2, p_AllowDirectSQLUpdate := p_AllowDirectSQLUpdate_38ee20b2, p_AllowDirectSQLDelete := p_AllowDirectSQLDelete_38ee20b2, p_Configuration := p_Configuration_38ee20b2, p_ID := p_ID_38ee20b2);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_6c00d32f VARCHAR(255);
  p_Description_6c00d32f TEXT;
  p_AutoUpdateDescription_6c00d32f BOOLEAN;
  p_IsPrimaryKey_6c00d32f BOOLEAN;
  p_IsUnique_6c00d32f BOOLEAN;
  p_Category_6c00d32f VARCHAR(255);
  p_ValueListType_6c00d32f VARCHAR(20);
  p_ExtendedType_6c00d32f VARCHAR(50);
  p_CodeType_6c00d32f VARCHAR(50);
  p_DefaultInView_6c00d32f BOOLEAN;
  p_ViewCellTemplate_6c00d32f TEXT;
  p_DefaultColumnWidth_6c00d32f INTEGER;
  p_AllowUpdateAPI_6c00d32f BOOLEAN;
  p_AllowUpdateInView_6c00d32f BOOLEAN;
  p_IncludeInUserSearchAPI_6c00d32f BOOLEAN;
  p_FullTextSearchEnabled_6c00d32f BOOLEAN;
  p_UserSearchParamFormatAPI_6c00d32f VARCHAR(500);
  p_IncludeInGeneratedForm_6c00d32f BOOLEAN;
  p_GeneratedFormSection_6c00d32f VARCHAR(10);
  p_IsNameField_6c00d32f BOOLEAN;
  p_RelatedEntityID_6c00d32f UUID;
  p_RelatedEntityFieldName_6c00d32f VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_6c00d32f BOOLEAN;
  p_RelatedEntityNameFieldMap_6c00d32f VARCHAR(255);
  p_RelatedEntityDisplayType_6c00d32f VARCHAR(20);
  p_EntityIDFieldName_6c00d32f VARCHAR(100);
  p_ScopeDefault_6c00d32f VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_6c00d32f BOOLEAN;
  p_ValuesToPackWithSchema_6c00d32f VARCHAR(10);
  p_Status_6c00d32f VARCHAR(25);
  p_AutoUpdateIsNameField_6c00d32f BOOLEAN;
  p_AutoUpdateDefaultInView_6c00d32f BOOLEAN;
  p_AutoUpdateCategory_6c00d32f BOOLEAN;
  p_AutoUpdateDisplayName_6c00d32f BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_6c00d32f BOOLEAN;
  p_Encrypt_6c00d32f BOOLEAN;
  p_EncryptionKeyID_6c00d32f UUID;
  p_AllowDecryptInAPI_6c00d32f BOOLEAN;
  p_SendEncryptedValue_6c00d32f BOOLEAN;
  p_IsSoftPrimaryKey_6c00d32f BOOLEAN;
  p_IsSoftForeignKey_6c00d32f BOOLEAN;
  p_RelatedEntityJoinFields_6c00d32f TEXT;
  p_JSONType_6c00d32f VARCHAR(255);
  p_JSONTypeIsArray_6c00d32f BOOLEAN;
  p_JSONTypeDefinition_6c00d32f TEXT;
  p_UserSearchPredicateAPI_6c00d32f VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_6c00d32f BOOLEAN;
  p_AutoUpdateFullTextSearch_6c00d32f BOOLEAN;
  p_AutoUpdateExtendedType_6c00d32f BOOLEAN;
  p_IsComputed_6c00d32f BOOLEAN;
  p_EmbeddedRecord_6c00d32f TEXT;
  p_Configuration_6c00d32f TEXT;
  p_ID_6c00d32f UUID;
BEGIN
  p_DisplayName_6c00d32f := 'State';
  p_AutoUpdateDescription_6c00d32f := TRUE;
  p_IsPrimaryKey_6c00d32f := FALSE;
  p_IsUnique_6c00d32f := FALSE;
  p_ValueListType_6c00d32f := 'None';
  p_DefaultInView_6c00d32f := TRUE;
  p_AllowUpdateAPI_6c00d32f := FALSE;
  p_AllowUpdateInView_6c00d32f := TRUE;
  p_IncludeInUserSearchAPI_6c00d32f := FALSE;
  p_FullTextSearchEnabled_6c00d32f := FALSE;
  p_IncludeInGeneratedForm_6c00d32f := FALSE;
  p_GeneratedFormSection_6c00d32f := 'Details';
  p_IsNameField_6c00d32f := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_6c00d32f := TRUE;
  p_RelatedEntityDisplayType_6c00d32f := 'Search';
  p_AutoUpdateRelatedEntityInfo_6c00d32f := TRUE;
  p_ValuesToPackWithSchema_6c00d32f := 'Auto';
  p_Status_6c00d32f := 'Active';
  p_AutoUpdateIsNameField_6c00d32f := TRUE;
  p_AutoUpdateDefaultInView_6c00d32f := TRUE;
  p_AutoUpdateCategory_6c00d32f := TRUE;
  p_AutoUpdateDisplayName_6c00d32f := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_6c00d32f := TRUE;
  p_Encrypt_6c00d32f := FALSE;
  p_AllowDecryptInAPI_6c00d32f := FALSE;
  p_SendEncryptedValue_6c00d32f := FALSE;
  p_IsSoftPrimaryKey_6c00d32f := FALSE;
  p_IsSoftForeignKey_6c00d32f := FALSE;
  p_JSONTypeIsArray_6c00d32f := FALSE;
  p_UserSearchPredicateAPI_6c00d32f := 'Contains';
  p_AutoUpdateUserSearchPredicate_6c00d32f := TRUE;
  p_AutoUpdateFullTextSearch_6c00d32f := TRUE;
  p_AutoUpdateExtendedType_6c00d32f := TRUE;
  p_IsComputed_6c00d32f := FALSE;
  p_ID_6c00d32f := 'EBA74B3E-F36B-1410-8A4E-0066522E4B7A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_6c00d32f,
    'Description', p_Description_6c00d32f,
    'AutoUpdateDescription', p_AutoUpdateDescription_6c00d32f,
    'IsPrimaryKey', p_IsPrimaryKey_6c00d32f,
    'IsUnique', p_IsUnique_6c00d32f,
    'Category', p_Category_6c00d32f,
    'ValueListType', p_ValueListType_6c00d32f,
    'ExtendedType', p_ExtendedType_6c00d32f,
    'CodeType', p_CodeType_6c00d32f,
    'DefaultInView', p_DefaultInView_6c00d32f,
    'ViewCellTemplate', p_ViewCellTemplate_6c00d32f,
    'DefaultColumnWidth', p_DefaultColumnWidth_6c00d32f,
    'AllowUpdateAPI', p_AllowUpdateAPI_6c00d32f,
    'AllowUpdateInView', p_AllowUpdateInView_6c00d32f,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_6c00d32f,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_6c00d32f,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_6c00d32f,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_6c00d32f,
    'GeneratedFormSection', p_GeneratedFormSection_6c00d32f,
    'IsNameField', p_IsNameField_6c00d32f,
    'RelatedEntityID', p_RelatedEntityID_6c00d32f,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_6c00d32f,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_6c00d32f,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_6c00d32f,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_6c00d32f,
    'EntityIDFieldName', p_EntityIDFieldName_6c00d32f,
    'ScopeDefault', p_ScopeDefault_6c00d32f,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_6c00d32f,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_6c00d32f,
    'Status', p_Status_6c00d32f,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_6c00d32f,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_6c00d32f,
    'AutoUpdateCategory', p_AutoUpdateCategory_6c00d32f,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_6c00d32f,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_6c00d32f,
    'Encrypt', p_Encrypt_6c00d32f,
    'EncryptionKeyID', p_EncryptionKeyID_6c00d32f,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_6c00d32f,
    'SendEncryptedValue', p_SendEncryptedValue_6c00d32f,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_6c00d32f,
    'IsSoftForeignKey', p_IsSoftForeignKey_6c00d32f,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_6c00d32f,
    'JSONType', p_JSONType_6c00d32f,
    'JSONTypeIsArray', p_JSONTypeIsArray_6c00d32f,
    'JSONTypeDefinition', p_JSONTypeDefinition_6c00d32f,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_6c00d32f,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_6c00d32f,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_6c00d32f,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_6c00d32f,
    'IsComputed', p_IsComputed_6c00d32f
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_6c00d32f,
    'Configuration', p_Configuration_6c00d32f,
    'ID', p_ID_6c00d32f
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_6c00d32f, p_Description := p_Description_6c00d32f, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_6c00d32f, p_IsPrimaryKey := p_IsPrimaryKey_6c00d32f, p_IsUnique := p_IsUnique_6c00d32f, p_Category := p_Category_6c00d32f, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_6c00d32f, p_ExtendedType := p_ExtendedType_6c00d32f, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_6c00d32f, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_6c00d32f, p_ViewCellTemplate := p_ViewCellTemplate_6c00d32f, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_6c00d32f, p_DefaultColumnWidth_Clear := TRUE, p_AllowUpdateAPI := p_AllowUpdateAPI_6c00d32f, p_AllowUpdateInView := p_AllowUpdateInView_6c00d32f, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_6c00d32f, p_FullTextSearchEnabled := p_FullTextSearchEnabled_6c00d32f, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_6c00d32f, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_6c00d32f, p_GeneratedFormSection := p_GeneratedFormSection_6c00d32f, p_IsNameField := p_IsNameField_6c00d32f, p_RelatedEntityID := p_RelatedEntityID_6c00d32f, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_6c00d32f, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_6c00d32f, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_6c00d32f, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_6c00d32f, p_EntityIDFieldName := p_EntityIDFieldName_6c00d32f, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_6c00d32f, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_6c00d32f, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_6c00d32f, p_Status := p_Status_6c00d32f, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_6c00d32f, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_6c00d32f, p_AutoUpdateCategory := p_AutoUpdateCategory_6c00d32f, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_6c00d32f, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_6c00d32f, p_Encrypt := p_Encrypt_6c00d32f, p_EncryptionKeyID := p_EncryptionKeyID_6c00d32f, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_6c00d32f, p_SendEncryptedValue := p_SendEncryptedValue_6c00d32f, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_6c00d32f, p_IsSoftForeignKey := p_IsSoftForeignKey_6c00d32f, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_6c00d32f, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_6c00d32f, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_6c00d32f, p_JSONTypeDefinition := p_JSONTypeDefinition_6c00d32f, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_6c00d32f, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_6c00d32f, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_6c00d32f, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_6c00d32f, p_IsComputed := p_IsComputed_6c00d32f, p_EmbeddedRecord := p_EmbeddedRecord_6c00d32f, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_6c00d32f, p_Configuration_Clear := TRUE, p_ID := p_ID_6c00d32f);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_05d95f3e VARCHAR(255);
  p_Description_05d95f3e TEXT;
  p_AutoUpdateDescription_05d95f3e BOOLEAN;
  p_IsPrimaryKey_05d95f3e BOOLEAN;
  p_IsUnique_05d95f3e BOOLEAN;
  p_Category_05d95f3e VARCHAR(255);
  p_ValueListType_05d95f3e VARCHAR(20);
  p_ExtendedType_05d95f3e VARCHAR(50);
  p_CodeType_05d95f3e VARCHAR(50);
  p_DefaultInView_05d95f3e BOOLEAN;
  p_ViewCellTemplate_05d95f3e TEXT;
  p_DefaultColumnWidth_05d95f3e INTEGER;
  p_AllowUpdateAPI_05d95f3e BOOLEAN;
  p_AllowUpdateInView_05d95f3e BOOLEAN;
  p_IncludeInUserSearchAPI_05d95f3e BOOLEAN;
  p_FullTextSearchEnabled_05d95f3e BOOLEAN;
  p_UserSearchParamFormatAPI_05d95f3e VARCHAR(500);
  p_IncludeInGeneratedForm_05d95f3e BOOLEAN;
  p_GeneratedFormSection_05d95f3e VARCHAR(10);
  p_IsNameField_05d95f3e BOOLEAN;
  p_RelatedEntityID_05d95f3e UUID;
  p_RelatedEntityFieldName_05d95f3e VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_05d95f3e BOOLEAN;
  p_RelatedEntityNameFieldMap_05d95f3e VARCHAR(255);
  p_RelatedEntityDisplayType_05d95f3e VARCHAR(20);
  p_EntityIDFieldName_05d95f3e VARCHAR(100);
  p_ScopeDefault_05d95f3e VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_05d95f3e BOOLEAN;
  p_ValuesToPackWithSchema_05d95f3e VARCHAR(10);
  p_Status_05d95f3e VARCHAR(25);
  p_AutoUpdateIsNameField_05d95f3e BOOLEAN;
  p_AutoUpdateDefaultInView_05d95f3e BOOLEAN;
  p_AutoUpdateCategory_05d95f3e BOOLEAN;
  p_AutoUpdateDisplayName_05d95f3e BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_05d95f3e BOOLEAN;
  p_Encrypt_05d95f3e BOOLEAN;
  p_EncryptionKeyID_05d95f3e UUID;
  p_AllowDecryptInAPI_05d95f3e BOOLEAN;
  p_SendEncryptedValue_05d95f3e BOOLEAN;
  p_IsSoftPrimaryKey_05d95f3e BOOLEAN;
  p_IsSoftForeignKey_05d95f3e BOOLEAN;
  p_RelatedEntityJoinFields_05d95f3e TEXT;
  p_JSONType_05d95f3e VARCHAR(255);
  p_JSONTypeIsArray_05d95f3e BOOLEAN;
  p_JSONTypeDefinition_05d95f3e TEXT;
  p_UserSearchPredicateAPI_05d95f3e VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_05d95f3e BOOLEAN;
  p_AutoUpdateFullTextSearch_05d95f3e BOOLEAN;
  p_AutoUpdateExtendedType_05d95f3e BOOLEAN;
  p_IsComputed_05d95f3e BOOLEAN;
  p_EmbeddedRecord_05d95f3e TEXT;
  p_Configuration_05d95f3e TEXT;
  p_ID_05d95f3e UUID;
BEGIN
  p_DisplayName_05d95f3e := 'Is Awaiting Document';
  p_AutoUpdateDescription_05d95f3e := TRUE;
  p_IsPrimaryKey_05d95f3e := FALSE;
  p_IsUnique_05d95f3e := FALSE;
  p_ValueListType_05d95f3e := 'None';
  p_DefaultInView_05d95f3e := FALSE;
  p_AllowUpdateAPI_05d95f3e := FALSE;
  p_AllowUpdateInView_05d95f3e := TRUE;
  p_IncludeInUserSearchAPI_05d95f3e := FALSE;
  p_FullTextSearchEnabled_05d95f3e := FALSE;
  p_IncludeInGeneratedForm_05d95f3e := FALSE;
  p_GeneratedFormSection_05d95f3e := 'Details';
  p_IsNameField_05d95f3e := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_05d95f3e := TRUE;
  p_RelatedEntityDisplayType_05d95f3e := 'Search';
  p_AutoUpdateRelatedEntityInfo_05d95f3e := TRUE;
  p_ValuesToPackWithSchema_05d95f3e := 'Auto';
  p_Status_05d95f3e := 'Active';
  p_AutoUpdateIsNameField_05d95f3e := TRUE;
  p_AutoUpdateDefaultInView_05d95f3e := TRUE;
  p_AutoUpdateCategory_05d95f3e := TRUE;
  p_AutoUpdateDisplayName_05d95f3e := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_05d95f3e := TRUE;
  p_Encrypt_05d95f3e := FALSE;
  p_AllowDecryptInAPI_05d95f3e := FALSE;
  p_SendEncryptedValue_05d95f3e := FALSE;
  p_IsSoftPrimaryKey_05d95f3e := FALSE;
  p_IsSoftForeignKey_05d95f3e := FALSE;
  p_JSONTypeIsArray_05d95f3e := FALSE;
  p_UserSearchPredicateAPI_05d95f3e := 'Contains';
  p_AutoUpdateUserSearchPredicate_05d95f3e := TRUE;
  p_AutoUpdateFullTextSearch_05d95f3e := TRUE;
  p_AutoUpdateExtendedType_05d95f3e := TRUE;
  p_IsComputed_05d95f3e := FALSE;
  p_ID_05d95f3e := 'EFA74B3E-F36B-1410-8A4E-0066522E4B7A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_05d95f3e,
    'Description', p_Description_05d95f3e,
    'AutoUpdateDescription', p_AutoUpdateDescription_05d95f3e,
    'IsPrimaryKey', p_IsPrimaryKey_05d95f3e,
    'IsUnique', p_IsUnique_05d95f3e,
    'Category', p_Category_05d95f3e,
    'ValueListType', p_ValueListType_05d95f3e,
    'ExtendedType', p_ExtendedType_05d95f3e,
    'CodeType', p_CodeType_05d95f3e,
    'DefaultInView', p_DefaultInView_05d95f3e,
    'ViewCellTemplate', p_ViewCellTemplate_05d95f3e,
    'DefaultColumnWidth', p_DefaultColumnWidth_05d95f3e,
    'AllowUpdateAPI', p_AllowUpdateAPI_05d95f3e,
    'AllowUpdateInView', p_AllowUpdateInView_05d95f3e,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_05d95f3e,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_05d95f3e,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_05d95f3e,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_05d95f3e,
    'GeneratedFormSection', p_GeneratedFormSection_05d95f3e,
    'IsNameField', p_IsNameField_05d95f3e,
    'RelatedEntityID', p_RelatedEntityID_05d95f3e,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_05d95f3e,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_05d95f3e,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_05d95f3e,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_05d95f3e,
    'EntityIDFieldName', p_EntityIDFieldName_05d95f3e,
    'ScopeDefault', p_ScopeDefault_05d95f3e,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_05d95f3e,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_05d95f3e,
    'Status', p_Status_05d95f3e,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_05d95f3e,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_05d95f3e,
    'AutoUpdateCategory', p_AutoUpdateCategory_05d95f3e,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_05d95f3e,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_05d95f3e,
    'Encrypt', p_Encrypt_05d95f3e,
    'EncryptionKeyID', p_EncryptionKeyID_05d95f3e,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_05d95f3e,
    'SendEncryptedValue', p_SendEncryptedValue_05d95f3e,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_05d95f3e,
    'IsSoftForeignKey', p_IsSoftForeignKey_05d95f3e,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_05d95f3e,
    'JSONType', p_JSONType_05d95f3e,
    'JSONTypeIsArray', p_JSONTypeIsArray_05d95f3e,
    'JSONTypeDefinition', p_JSONTypeDefinition_05d95f3e,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_05d95f3e,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_05d95f3e,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_05d95f3e,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_05d95f3e,
    'IsComputed', p_IsComputed_05d95f3e
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_05d95f3e,
    'Configuration', p_Configuration_05d95f3e,
    'ID', p_ID_05d95f3e
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_05d95f3e, p_Description := p_Description_05d95f3e, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_05d95f3e, p_IsPrimaryKey := p_IsPrimaryKey_05d95f3e, p_IsUnique := p_IsUnique_05d95f3e, p_Category := p_Category_05d95f3e, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_05d95f3e, p_ExtendedType := p_ExtendedType_05d95f3e, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_05d95f3e, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_05d95f3e, p_ViewCellTemplate := p_ViewCellTemplate_05d95f3e, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_05d95f3e, p_DefaultColumnWidth_Clear := TRUE, p_AllowUpdateAPI := p_AllowUpdateAPI_05d95f3e, p_AllowUpdateInView := p_AllowUpdateInView_05d95f3e, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_05d95f3e, p_FullTextSearchEnabled := p_FullTextSearchEnabled_05d95f3e, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_05d95f3e, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_05d95f3e, p_GeneratedFormSection := p_GeneratedFormSection_05d95f3e, p_IsNameField := p_IsNameField_05d95f3e, p_RelatedEntityID := p_RelatedEntityID_05d95f3e, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_05d95f3e, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_05d95f3e, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_05d95f3e, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_05d95f3e, p_EntityIDFieldName := p_EntityIDFieldName_05d95f3e, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_05d95f3e, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_05d95f3e, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_05d95f3e, p_Status := p_Status_05d95f3e, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_05d95f3e, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_05d95f3e, p_AutoUpdateCategory := p_AutoUpdateCategory_05d95f3e, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_05d95f3e, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_05d95f3e, p_Encrypt := p_Encrypt_05d95f3e, p_EncryptionKeyID := p_EncryptionKeyID_05d95f3e, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_05d95f3e, p_SendEncryptedValue := p_SendEncryptedValue_05d95f3e, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_05d95f3e, p_IsSoftForeignKey := p_IsSoftForeignKey_05d95f3e, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_05d95f3e, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_05d95f3e, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_05d95f3e, p_JSONTypeDefinition := p_JSONTypeDefinition_05d95f3e, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_05d95f3e, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_05d95f3e, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_05d95f3e, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_05d95f3e, p_IsComputed := p_IsComputed_05d95f3e, p_EmbeddedRecord := p_EmbeddedRecord_05d95f3e, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_05d95f3e, p_Configuration_Clear := TRUE, p_ID := p_ID_05d95f3e);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_14dd0c0f VARCHAR(255);
  p_Description_14dd0c0f TEXT;
  p_AutoUpdateDescription_14dd0c0f BOOLEAN;
  p_IsPrimaryKey_14dd0c0f BOOLEAN;
  p_IsUnique_14dd0c0f BOOLEAN;
  p_Category_14dd0c0f VARCHAR(255);
  p_ValueListType_14dd0c0f VARCHAR(20);
  p_ExtendedType_14dd0c0f VARCHAR(50);
  p_CodeType_14dd0c0f VARCHAR(50);
  p_DefaultInView_14dd0c0f BOOLEAN;
  p_ViewCellTemplate_14dd0c0f TEXT;
  p_DefaultColumnWidth_14dd0c0f INTEGER;
  p_AllowUpdateAPI_14dd0c0f BOOLEAN;
  p_AllowUpdateInView_14dd0c0f BOOLEAN;
  p_IncludeInUserSearchAPI_14dd0c0f BOOLEAN;
  p_FullTextSearchEnabled_14dd0c0f BOOLEAN;
  p_UserSearchParamFormatAPI_14dd0c0f VARCHAR(500);
  p_IncludeInGeneratedForm_14dd0c0f BOOLEAN;
  p_GeneratedFormSection_14dd0c0f VARCHAR(10);
  p_IsNameField_14dd0c0f BOOLEAN;
  p_RelatedEntityID_14dd0c0f UUID;
  p_RelatedEntityFieldName_14dd0c0f VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_14dd0c0f BOOLEAN;
  p_RelatedEntityNameFieldMap_14dd0c0f VARCHAR(255);
  p_RelatedEntityDisplayType_14dd0c0f VARCHAR(20);
  p_EntityIDFieldName_14dd0c0f VARCHAR(100);
  p_ScopeDefault_14dd0c0f VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_14dd0c0f BOOLEAN;
  p_ValuesToPackWithSchema_14dd0c0f VARCHAR(10);
  p_Status_14dd0c0f VARCHAR(25);
  p_AutoUpdateIsNameField_14dd0c0f BOOLEAN;
  p_AutoUpdateDefaultInView_14dd0c0f BOOLEAN;
  p_AutoUpdateCategory_14dd0c0f BOOLEAN;
  p_AutoUpdateDisplayName_14dd0c0f BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_14dd0c0f BOOLEAN;
  p_Encrypt_14dd0c0f BOOLEAN;
  p_EncryptionKeyID_14dd0c0f UUID;
  p_AllowDecryptInAPI_14dd0c0f BOOLEAN;
  p_SendEncryptedValue_14dd0c0f BOOLEAN;
  p_IsSoftPrimaryKey_14dd0c0f BOOLEAN;
  p_IsSoftForeignKey_14dd0c0f BOOLEAN;
  p_RelatedEntityJoinFields_14dd0c0f TEXT;
  p_JSONType_14dd0c0f VARCHAR(255);
  p_JSONTypeIsArray_14dd0c0f BOOLEAN;
  p_JSONTypeDefinition_14dd0c0f TEXT;
  p_UserSearchPredicateAPI_14dd0c0f VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_14dd0c0f BOOLEAN;
  p_AutoUpdateFullTextSearch_14dd0c0f BOOLEAN;
  p_AutoUpdateExtendedType_14dd0c0f BOOLEAN;
  p_IsComputed_14dd0c0f BOOLEAN;
  p_EmbeddedRecord_14dd0c0f TEXT;
  p_Configuration_14dd0c0f TEXT;
  p_ID_14dd0c0f UUID;
BEGIN
  p_DisplayName_14dd0c0f := 'Renewal Notice Deadline';
  p_AutoUpdateDescription_14dd0c0f := TRUE;
  p_IsPrimaryKey_14dd0c0f := FALSE;
  p_IsUnique_14dd0c0f := FALSE;
  p_ValueListType_14dd0c0f := 'None';
  p_DefaultInView_14dd0c0f := FALSE;
  p_AllowUpdateAPI_14dd0c0f := FALSE;
  p_AllowUpdateInView_14dd0c0f := TRUE;
  p_IncludeInUserSearchAPI_14dd0c0f := FALSE;
  p_FullTextSearchEnabled_14dd0c0f := FALSE;
  p_IncludeInGeneratedForm_14dd0c0f := FALSE;
  p_GeneratedFormSection_14dd0c0f := 'Details';
  p_IsNameField_14dd0c0f := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_14dd0c0f := TRUE;
  p_RelatedEntityDisplayType_14dd0c0f := 'Search';
  p_AutoUpdateRelatedEntityInfo_14dd0c0f := TRUE;
  p_ValuesToPackWithSchema_14dd0c0f := 'Auto';
  p_Status_14dd0c0f := 'Active';
  p_AutoUpdateIsNameField_14dd0c0f := TRUE;
  p_AutoUpdateDefaultInView_14dd0c0f := TRUE;
  p_AutoUpdateCategory_14dd0c0f := TRUE;
  p_AutoUpdateDisplayName_14dd0c0f := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_14dd0c0f := TRUE;
  p_Encrypt_14dd0c0f := FALSE;
  p_AllowDecryptInAPI_14dd0c0f := FALSE;
  p_SendEncryptedValue_14dd0c0f := FALSE;
  p_IsSoftPrimaryKey_14dd0c0f := FALSE;
  p_IsSoftForeignKey_14dd0c0f := FALSE;
  p_JSONTypeIsArray_14dd0c0f := FALSE;
  p_UserSearchPredicateAPI_14dd0c0f := 'Contains';
  p_AutoUpdateUserSearchPredicate_14dd0c0f := TRUE;
  p_AutoUpdateFullTextSearch_14dd0c0f := TRUE;
  p_AutoUpdateExtendedType_14dd0c0f := TRUE;
  p_IsComputed_14dd0c0f := FALSE;
  p_ID_14dd0c0f := 'F7A74B3E-F36B-1410-8A4E-0066522E4B7A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_14dd0c0f,
    'Description', p_Description_14dd0c0f,
    'AutoUpdateDescription', p_AutoUpdateDescription_14dd0c0f,
    'IsPrimaryKey', p_IsPrimaryKey_14dd0c0f,
    'IsUnique', p_IsUnique_14dd0c0f,
    'Category', p_Category_14dd0c0f,
    'ValueListType', p_ValueListType_14dd0c0f,
    'ExtendedType', p_ExtendedType_14dd0c0f,
    'CodeType', p_CodeType_14dd0c0f,
    'DefaultInView', p_DefaultInView_14dd0c0f,
    'ViewCellTemplate', p_ViewCellTemplate_14dd0c0f,
    'DefaultColumnWidth', p_DefaultColumnWidth_14dd0c0f,
    'AllowUpdateAPI', p_AllowUpdateAPI_14dd0c0f,
    'AllowUpdateInView', p_AllowUpdateInView_14dd0c0f,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_14dd0c0f,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_14dd0c0f,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_14dd0c0f,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_14dd0c0f,
    'GeneratedFormSection', p_GeneratedFormSection_14dd0c0f,
    'IsNameField', p_IsNameField_14dd0c0f,
    'RelatedEntityID', p_RelatedEntityID_14dd0c0f,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_14dd0c0f,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_14dd0c0f,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_14dd0c0f,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_14dd0c0f,
    'EntityIDFieldName', p_EntityIDFieldName_14dd0c0f,
    'ScopeDefault', p_ScopeDefault_14dd0c0f,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_14dd0c0f,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_14dd0c0f,
    'Status', p_Status_14dd0c0f,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_14dd0c0f,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_14dd0c0f,
    'AutoUpdateCategory', p_AutoUpdateCategory_14dd0c0f,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_14dd0c0f,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_14dd0c0f,
    'Encrypt', p_Encrypt_14dd0c0f,
    'EncryptionKeyID', p_EncryptionKeyID_14dd0c0f,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_14dd0c0f,
    'SendEncryptedValue', p_SendEncryptedValue_14dd0c0f,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_14dd0c0f,
    'IsSoftForeignKey', p_IsSoftForeignKey_14dd0c0f,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_14dd0c0f,
    'JSONType', p_JSONType_14dd0c0f,
    'JSONTypeIsArray', p_JSONTypeIsArray_14dd0c0f,
    'JSONTypeDefinition', p_JSONTypeDefinition_14dd0c0f,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_14dd0c0f,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_14dd0c0f,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_14dd0c0f,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_14dd0c0f,
    'IsComputed', p_IsComputed_14dd0c0f
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_14dd0c0f,
    'Configuration', p_Configuration_14dd0c0f,
    'ID', p_ID_14dd0c0f
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_14dd0c0f, p_Description := p_Description_14dd0c0f, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_14dd0c0f, p_IsPrimaryKey := p_IsPrimaryKey_14dd0c0f, p_IsUnique := p_IsUnique_14dd0c0f, p_Category := p_Category_14dd0c0f, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_14dd0c0f, p_ExtendedType := p_ExtendedType_14dd0c0f, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_14dd0c0f, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_14dd0c0f, p_ViewCellTemplate := p_ViewCellTemplate_14dd0c0f, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_14dd0c0f, p_DefaultColumnWidth_Clear := TRUE, p_AllowUpdateAPI := p_AllowUpdateAPI_14dd0c0f, p_AllowUpdateInView := p_AllowUpdateInView_14dd0c0f, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_14dd0c0f, p_FullTextSearchEnabled := p_FullTextSearchEnabled_14dd0c0f, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_14dd0c0f, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_14dd0c0f, p_GeneratedFormSection := p_GeneratedFormSection_14dd0c0f, p_IsNameField := p_IsNameField_14dd0c0f, p_RelatedEntityID := p_RelatedEntityID_14dd0c0f, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_14dd0c0f, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_14dd0c0f, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_14dd0c0f, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_14dd0c0f, p_EntityIDFieldName := p_EntityIDFieldName_14dd0c0f, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_14dd0c0f, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_14dd0c0f, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_14dd0c0f, p_Status := p_Status_14dd0c0f, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_14dd0c0f, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_14dd0c0f, p_AutoUpdateCategory := p_AutoUpdateCategory_14dd0c0f, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_14dd0c0f, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_14dd0c0f, p_Encrypt := p_Encrypt_14dd0c0f, p_EncryptionKeyID := p_EncryptionKeyID_14dd0c0f, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_14dd0c0f, p_SendEncryptedValue := p_SendEncryptedValue_14dd0c0f, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_14dd0c0f, p_IsSoftForeignKey := p_IsSoftForeignKey_14dd0c0f, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_14dd0c0f, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_14dd0c0f, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_14dd0c0f, p_JSONTypeDefinition := p_JSONTypeDefinition_14dd0c0f, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_14dd0c0f, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_14dd0c0f, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_14dd0c0f, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_14dd0c0f, p_IsComputed := p_IsComputed_14dd0c0f, p_EmbeddedRecord := p_EmbeddedRecord_14dd0c0f, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_14dd0c0f, p_Configuration_Clear := TRUE, p_ID := p_ID_14dd0c0f);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_5219bab1 VARCHAR(255);
  p_Description_5219bab1 TEXT;
  p_AutoUpdateDescription_5219bab1 BOOLEAN;
  p_IsPrimaryKey_5219bab1 BOOLEAN;
  p_IsUnique_5219bab1 BOOLEAN;
  p_Category_5219bab1 VARCHAR(255);
  p_ValueListType_5219bab1 VARCHAR(20);
  p_ExtendedType_5219bab1 VARCHAR(50);
  p_CodeType_5219bab1 VARCHAR(50);
  p_DefaultInView_5219bab1 BOOLEAN;
  p_ViewCellTemplate_5219bab1 TEXT;
  p_DefaultColumnWidth_5219bab1 INTEGER;
  p_AllowUpdateAPI_5219bab1 BOOLEAN;
  p_AllowUpdateInView_5219bab1 BOOLEAN;
  p_IncludeInUserSearchAPI_5219bab1 BOOLEAN;
  p_FullTextSearchEnabled_5219bab1 BOOLEAN;
  p_UserSearchParamFormatAPI_5219bab1 VARCHAR(500);
  p_IncludeInGeneratedForm_5219bab1 BOOLEAN;
  p_GeneratedFormSection_5219bab1 VARCHAR(10);
  p_IsNameField_5219bab1 BOOLEAN;
  p_RelatedEntityID_5219bab1 UUID;
  p_RelatedEntityFieldName_5219bab1 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_5219bab1 BOOLEAN;
  p_RelatedEntityNameFieldMap_5219bab1 VARCHAR(255);
  p_RelatedEntityDisplayType_5219bab1 VARCHAR(20);
  p_EntityIDFieldName_5219bab1 VARCHAR(100);
  p_ScopeDefault_5219bab1 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_5219bab1 BOOLEAN;
  p_ValuesToPackWithSchema_5219bab1 VARCHAR(10);
  p_Status_5219bab1 VARCHAR(25);
  p_AutoUpdateIsNameField_5219bab1 BOOLEAN;
  p_AutoUpdateDefaultInView_5219bab1 BOOLEAN;
  p_AutoUpdateCategory_5219bab1 BOOLEAN;
  p_AutoUpdateDisplayName_5219bab1 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_5219bab1 BOOLEAN;
  p_Encrypt_5219bab1 BOOLEAN;
  p_EncryptionKeyID_5219bab1 UUID;
  p_AllowDecryptInAPI_5219bab1 BOOLEAN;
  p_SendEncryptedValue_5219bab1 BOOLEAN;
  p_IsSoftPrimaryKey_5219bab1 BOOLEAN;
  p_IsSoftForeignKey_5219bab1 BOOLEAN;
  p_RelatedEntityJoinFields_5219bab1 TEXT;
  p_JSONType_5219bab1 VARCHAR(255);
  p_JSONTypeIsArray_5219bab1 BOOLEAN;
  p_JSONTypeDefinition_5219bab1 TEXT;
  p_UserSearchPredicateAPI_5219bab1 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_5219bab1 BOOLEAN;
  p_AutoUpdateFullTextSearch_5219bab1 BOOLEAN;
  p_AutoUpdateExtendedType_5219bab1 BOOLEAN;
  p_IsComputed_5219bab1 BOOLEAN;
  p_EmbeddedRecord_5219bab1 TEXT;
  p_Configuration_5219bab1 TEXT;
  p_ID_5219bab1 UUID;
BEGIN
  p_DisplayName_5219bab1 := 'Is In Cancellation Window';
  p_AutoUpdateDescription_5219bab1 := TRUE;
  p_IsPrimaryKey_5219bab1 := FALSE;
  p_IsUnique_5219bab1 := FALSE;
  p_ValueListType_5219bab1 := 'None';
  p_DefaultInView_5219bab1 := FALSE;
  p_AllowUpdateAPI_5219bab1 := FALSE;
  p_AllowUpdateInView_5219bab1 := TRUE;
  p_IncludeInUserSearchAPI_5219bab1 := FALSE;
  p_FullTextSearchEnabled_5219bab1 := FALSE;
  p_IncludeInGeneratedForm_5219bab1 := FALSE;
  p_GeneratedFormSection_5219bab1 := 'Details';
  p_IsNameField_5219bab1 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_5219bab1 := TRUE;
  p_RelatedEntityDisplayType_5219bab1 := 'Search';
  p_AutoUpdateRelatedEntityInfo_5219bab1 := TRUE;
  p_ValuesToPackWithSchema_5219bab1 := 'Auto';
  p_Status_5219bab1 := 'Active';
  p_AutoUpdateIsNameField_5219bab1 := TRUE;
  p_AutoUpdateDefaultInView_5219bab1 := TRUE;
  p_AutoUpdateCategory_5219bab1 := TRUE;
  p_AutoUpdateDisplayName_5219bab1 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_5219bab1 := TRUE;
  p_Encrypt_5219bab1 := FALSE;
  p_AllowDecryptInAPI_5219bab1 := FALSE;
  p_SendEncryptedValue_5219bab1 := FALSE;
  p_IsSoftPrimaryKey_5219bab1 := FALSE;
  p_IsSoftForeignKey_5219bab1 := FALSE;
  p_JSONTypeIsArray_5219bab1 := FALSE;
  p_UserSearchPredicateAPI_5219bab1 := 'Contains';
  p_AutoUpdateUserSearchPredicate_5219bab1 := TRUE;
  p_AutoUpdateFullTextSearch_5219bab1 := TRUE;
  p_AutoUpdateExtendedType_5219bab1 := TRUE;
  p_IsComputed_5219bab1 := FALSE;
  p_ID_5219bab1 := 'FBA74B3E-F36B-1410-8A4E-0066522E4B7A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_5219bab1,
    'Description', p_Description_5219bab1,
    'AutoUpdateDescription', p_AutoUpdateDescription_5219bab1,
    'IsPrimaryKey', p_IsPrimaryKey_5219bab1,
    'IsUnique', p_IsUnique_5219bab1,
    'Category', p_Category_5219bab1,
    'ValueListType', p_ValueListType_5219bab1,
    'ExtendedType', p_ExtendedType_5219bab1,
    'CodeType', p_CodeType_5219bab1,
    'DefaultInView', p_DefaultInView_5219bab1,
    'ViewCellTemplate', p_ViewCellTemplate_5219bab1,
    'DefaultColumnWidth', p_DefaultColumnWidth_5219bab1,
    'AllowUpdateAPI', p_AllowUpdateAPI_5219bab1,
    'AllowUpdateInView', p_AllowUpdateInView_5219bab1,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_5219bab1,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_5219bab1,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_5219bab1,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_5219bab1,
    'GeneratedFormSection', p_GeneratedFormSection_5219bab1,
    'IsNameField', p_IsNameField_5219bab1,
    'RelatedEntityID', p_RelatedEntityID_5219bab1,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_5219bab1,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_5219bab1,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_5219bab1,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_5219bab1,
    'EntityIDFieldName', p_EntityIDFieldName_5219bab1,
    'ScopeDefault', p_ScopeDefault_5219bab1,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_5219bab1,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_5219bab1,
    'Status', p_Status_5219bab1,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_5219bab1,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_5219bab1,
    'AutoUpdateCategory', p_AutoUpdateCategory_5219bab1,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_5219bab1,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_5219bab1,
    'Encrypt', p_Encrypt_5219bab1,
    'EncryptionKeyID', p_EncryptionKeyID_5219bab1,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_5219bab1,
    'SendEncryptedValue', p_SendEncryptedValue_5219bab1,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_5219bab1,
    'IsSoftForeignKey', p_IsSoftForeignKey_5219bab1,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_5219bab1,
    'JSONType', p_JSONType_5219bab1,
    'JSONTypeIsArray', p_JSONTypeIsArray_5219bab1,
    'JSONTypeDefinition', p_JSONTypeDefinition_5219bab1,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_5219bab1,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_5219bab1,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_5219bab1,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_5219bab1,
    'IsComputed', p_IsComputed_5219bab1
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_5219bab1,
    'Configuration', p_Configuration_5219bab1,
    'ID', p_ID_5219bab1
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_5219bab1, p_Description := p_Description_5219bab1, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_5219bab1, p_IsPrimaryKey := p_IsPrimaryKey_5219bab1, p_IsUnique := p_IsUnique_5219bab1, p_Category := p_Category_5219bab1, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_5219bab1, p_ExtendedType := p_ExtendedType_5219bab1, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_5219bab1, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_5219bab1, p_ViewCellTemplate := p_ViewCellTemplate_5219bab1, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_5219bab1, p_DefaultColumnWidth_Clear := TRUE, p_AllowUpdateAPI := p_AllowUpdateAPI_5219bab1, p_AllowUpdateInView := p_AllowUpdateInView_5219bab1, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_5219bab1, p_FullTextSearchEnabled := p_FullTextSearchEnabled_5219bab1, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_5219bab1, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_5219bab1, p_GeneratedFormSection := p_GeneratedFormSection_5219bab1, p_IsNameField := p_IsNameField_5219bab1, p_RelatedEntityID := p_RelatedEntityID_5219bab1, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_5219bab1, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_5219bab1, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_5219bab1, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_5219bab1, p_EntityIDFieldName := p_EntityIDFieldName_5219bab1, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_5219bab1, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_5219bab1, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_5219bab1, p_Status := p_Status_5219bab1, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_5219bab1, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_5219bab1, p_AutoUpdateCategory := p_AutoUpdateCategory_5219bab1, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_5219bab1, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_5219bab1, p_Encrypt := p_Encrypt_5219bab1, p_EncryptionKeyID := p_EncryptionKeyID_5219bab1, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_5219bab1, p_SendEncryptedValue := p_SendEncryptedValue_5219bab1, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_5219bab1, p_IsSoftForeignKey := p_IsSoftForeignKey_5219bab1, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_5219bab1, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_5219bab1, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_5219bab1, p_JSONTypeDefinition := p_JSONTypeDefinition_5219bab1, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_5219bab1, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_5219bab1, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_5219bab1, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_5219bab1, p_IsComputed := p_IsComputed_5219bab1, p_EmbeddedRecord := p_EmbeddedRecord_5219bab1, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_5219bab1, p_Configuration_Clear := TRUE, p_ID := p_ID_5219bab1);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_af0dbca9 VARCHAR(255);
  p_Description_af0dbca9 TEXT;
  p_AutoUpdateDescription_af0dbca9 BOOLEAN;
  p_IsPrimaryKey_af0dbca9 BOOLEAN;
  p_IsUnique_af0dbca9 BOOLEAN;
  p_Category_af0dbca9 VARCHAR(255);
  p_ValueListType_af0dbca9 VARCHAR(20);
  p_ExtendedType_af0dbca9 VARCHAR(50);
  p_CodeType_af0dbca9 VARCHAR(50);
  p_DefaultInView_af0dbca9 BOOLEAN;
  p_ViewCellTemplate_af0dbca9 TEXT;
  p_DefaultColumnWidth_af0dbca9 INTEGER;
  p_AllowUpdateAPI_af0dbca9 BOOLEAN;
  p_AllowUpdateInView_af0dbca9 BOOLEAN;
  p_IncludeInUserSearchAPI_af0dbca9 BOOLEAN;
  p_FullTextSearchEnabled_af0dbca9 BOOLEAN;
  p_UserSearchParamFormatAPI_af0dbca9 VARCHAR(500);
  p_IncludeInGeneratedForm_af0dbca9 BOOLEAN;
  p_GeneratedFormSection_af0dbca9 VARCHAR(10);
  p_IsNameField_af0dbca9 BOOLEAN;
  p_RelatedEntityID_af0dbca9 UUID;
  p_RelatedEntityFieldName_af0dbca9 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_af0dbca9 BOOLEAN;
  p_RelatedEntityNameFieldMap_af0dbca9 VARCHAR(255);
  p_RelatedEntityDisplayType_af0dbca9 VARCHAR(20);
  p_EntityIDFieldName_af0dbca9 VARCHAR(100);
  p_ScopeDefault_af0dbca9 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_af0dbca9 BOOLEAN;
  p_ValuesToPackWithSchema_af0dbca9 VARCHAR(10);
  p_Status_af0dbca9 VARCHAR(25);
  p_AutoUpdateIsNameField_af0dbca9 BOOLEAN;
  p_AutoUpdateDefaultInView_af0dbca9 BOOLEAN;
  p_AutoUpdateCategory_af0dbca9 BOOLEAN;
  p_AutoUpdateDisplayName_af0dbca9 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_af0dbca9 BOOLEAN;
  p_Encrypt_af0dbca9 BOOLEAN;
  p_EncryptionKeyID_af0dbca9 UUID;
  p_AllowDecryptInAPI_af0dbca9 BOOLEAN;
  p_SendEncryptedValue_af0dbca9 BOOLEAN;
  p_IsSoftPrimaryKey_af0dbca9 BOOLEAN;
  p_IsSoftForeignKey_af0dbca9 BOOLEAN;
  p_RelatedEntityJoinFields_af0dbca9 TEXT;
  p_JSONType_af0dbca9 VARCHAR(255);
  p_JSONTypeIsArray_af0dbca9 BOOLEAN;
  p_JSONTypeDefinition_af0dbca9 TEXT;
  p_UserSearchPredicateAPI_af0dbca9 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_af0dbca9 BOOLEAN;
  p_AutoUpdateFullTextSearch_af0dbca9 BOOLEAN;
  p_AutoUpdateExtendedType_af0dbca9 BOOLEAN;
  p_IsComputed_af0dbca9 BOOLEAN;
  p_EmbeddedRecord_af0dbca9 TEXT;
  p_Configuration_af0dbca9 TEXT;
  p_ID_af0dbca9 UUID;
BEGIN
  p_DisplayName_af0dbca9 := 'Days To End';
  p_AutoUpdateDescription_af0dbca9 := TRUE;
  p_IsPrimaryKey_af0dbca9 := FALSE;
  p_IsUnique_af0dbca9 := FALSE;
  p_ValueListType_af0dbca9 := 'None';
  p_DefaultInView_af0dbca9 := FALSE;
  p_AllowUpdateAPI_af0dbca9 := FALSE;
  p_AllowUpdateInView_af0dbca9 := TRUE;
  p_IncludeInUserSearchAPI_af0dbca9 := FALSE;
  p_FullTextSearchEnabled_af0dbca9 := FALSE;
  p_IncludeInGeneratedForm_af0dbca9 := FALSE;
  p_GeneratedFormSection_af0dbca9 := 'Details';
  p_IsNameField_af0dbca9 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_af0dbca9 := TRUE;
  p_RelatedEntityDisplayType_af0dbca9 := 'Search';
  p_AutoUpdateRelatedEntityInfo_af0dbca9 := TRUE;
  p_ValuesToPackWithSchema_af0dbca9 := 'Auto';
  p_Status_af0dbca9 := 'Active';
  p_AutoUpdateIsNameField_af0dbca9 := TRUE;
  p_AutoUpdateDefaultInView_af0dbca9 := TRUE;
  p_AutoUpdateCategory_af0dbca9 := TRUE;
  p_AutoUpdateDisplayName_af0dbca9 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_af0dbca9 := TRUE;
  p_Encrypt_af0dbca9 := FALSE;
  p_AllowDecryptInAPI_af0dbca9 := FALSE;
  p_SendEncryptedValue_af0dbca9 := FALSE;
  p_IsSoftPrimaryKey_af0dbca9 := FALSE;
  p_IsSoftForeignKey_af0dbca9 := FALSE;
  p_JSONTypeIsArray_af0dbca9 := FALSE;
  p_UserSearchPredicateAPI_af0dbca9 := 'Contains';
  p_AutoUpdateUserSearchPredicate_af0dbca9 := TRUE;
  p_AutoUpdateFullTextSearch_af0dbca9 := TRUE;
  p_AutoUpdateExtendedType_af0dbca9 := TRUE;
  p_IsComputed_af0dbca9 := FALSE;
  p_ID_af0dbca9 := 'F3A74B3E-F36B-1410-8A4E-0066522E4B7A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_af0dbca9,
    'Description', p_Description_af0dbca9,
    'AutoUpdateDescription', p_AutoUpdateDescription_af0dbca9,
    'IsPrimaryKey', p_IsPrimaryKey_af0dbca9,
    'IsUnique', p_IsUnique_af0dbca9,
    'Category', p_Category_af0dbca9,
    'ValueListType', p_ValueListType_af0dbca9,
    'ExtendedType', p_ExtendedType_af0dbca9,
    'CodeType', p_CodeType_af0dbca9,
    'DefaultInView', p_DefaultInView_af0dbca9,
    'ViewCellTemplate', p_ViewCellTemplate_af0dbca9,
    'DefaultColumnWidth', p_DefaultColumnWidth_af0dbca9,
    'AllowUpdateAPI', p_AllowUpdateAPI_af0dbca9,
    'AllowUpdateInView', p_AllowUpdateInView_af0dbca9,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_af0dbca9,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_af0dbca9,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_af0dbca9,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_af0dbca9,
    'GeneratedFormSection', p_GeneratedFormSection_af0dbca9,
    'IsNameField', p_IsNameField_af0dbca9,
    'RelatedEntityID', p_RelatedEntityID_af0dbca9,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_af0dbca9,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_af0dbca9,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_af0dbca9,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_af0dbca9,
    'EntityIDFieldName', p_EntityIDFieldName_af0dbca9,
    'ScopeDefault', p_ScopeDefault_af0dbca9,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_af0dbca9,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_af0dbca9,
    'Status', p_Status_af0dbca9,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_af0dbca9,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_af0dbca9,
    'AutoUpdateCategory', p_AutoUpdateCategory_af0dbca9,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_af0dbca9,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_af0dbca9,
    'Encrypt', p_Encrypt_af0dbca9,
    'EncryptionKeyID', p_EncryptionKeyID_af0dbca9,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_af0dbca9,
    'SendEncryptedValue', p_SendEncryptedValue_af0dbca9,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_af0dbca9,
    'IsSoftForeignKey', p_IsSoftForeignKey_af0dbca9,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_af0dbca9,
    'JSONType', p_JSONType_af0dbca9,
    'JSONTypeIsArray', p_JSONTypeIsArray_af0dbca9,
    'JSONTypeDefinition', p_JSONTypeDefinition_af0dbca9,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_af0dbca9,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_af0dbca9,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_af0dbca9,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_af0dbca9,
    'IsComputed', p_IsComputed_af0dbca9
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_af0dbca9,
    'Configuration', p_Configuration_af0dbca9,
    'ID', p_ID_af0dbca9
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_af0dbca9, p_Description := p_Description_af0dbca9, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_af0dbca9, p_IsPrimaryKey := p_IsPrimaryKey_af0dbca9, p_IsUnique := p_IsUnique_af0dbca9, p_Category := p_Category_af0dbca9, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_af0dbca9, p_ExtendedType := p_ExtendedType_af0dbca9, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_af0dbca9, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_af0dbca9, p_ViewCellTemplate := p_ViewCellTemplate_af0dbca9, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_af0dbca9, p_DefaultColumnWidth_Clear := TRUE, p_AllowUpdateAPI := p_AllowUpdateAPI_af0dbca9, p_AllowUpdateInView := p_AllowUpdateInView_af0dbca9, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_af0dbca9, p_FullTextSearchEnabled := p_FullTextSearchEnabled_af0dbca9, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_af0dbca9, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_af0dbca9, p_GeneratedFormSection := p_GeneratedFormSection_af0dbca9, p_IsNameField := p_IsNameField_af0dbca9, p_RelatedEntityID := p_RelatedEntityID_af0dbca9, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_af0dbca9, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_af0dbca9, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_af0dbca9, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_af0dbca9, p_EntityIDFieldName := p_EntityIDFieldName_af0dbca9, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_af0dbca9, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_af0dbca9, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_af0dbca9, p_Status := p_Status_af0dbca9, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_af0dbca9, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_af0dbca9, p_AutoUpdateCategory := p_AutoUpdateCategory_af0dbca9, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_af0dbca9, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_af0dbca9, p_Encrypt := p_Encrypt_af0dbca9, p_EncryptionKeyID := p_EncryptionKeyID_af0dbca9, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_af0dbca9, p_SendEncryptedValue := p_SendEncryptedValue_af0dbca9, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_af0dbca9, p_IsSoftForeignKey := p_IsSoftForeignKey_af0dbca9, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_af0dbca9, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_af0dbca9, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_af0dbca9, p_JSONTypeDefinition := p_JSONTypeDefinition_af0dbca9, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_af0dbca9, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_af0dbca9, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_af0dbca9, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_af0dbca9, p_IsComputed := p_IsComputed_af0dbca9, p_EmbeddedRecord := p_EmbeddedRecord_af0dbca9, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_af0dbca9, p_Configuration_Clear := TRUE, p_ID := p_ID_af0dbca9);
  END IF;
END $mj$;

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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractTemplateType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractTemplateType"(p_data := jsonb_build_object(
    'ID', p_ID_b0d4fcb3,
    'Name', p_Name_b0d4fcb3,
    'Description', p_Description_b0d4fcb3,
    'Status', p_Status_b0d4fcb3
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractTemplateType"(p_ID := p_ID_b0d4fcb3, p_Name := p_Name_b0d4fcb3, p_Description := p_Description_b0d4fcb3, p_Status := p_Status_b0d4fcb3);
  END IF;
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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractTemplateType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractTemplateType"(p_data := jsonb_build_object(
    'ID', p_ID_a5b7685c,
    'Name', p_Name_a5b7685c,
    'Description', p_Description_a5b7685c,
    'Status', p_Status_a5b7685c
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractTemplateType"(p_ID := p_ID_a5b7685c, p_Name := p_Name_a5b7685c, p_Description := p_Description_a5b7685c, p_Status := p_Status_a5b7685c);
  END IF;
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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_data := jsonb_build_object(
    'ID', p_ID_5574320d,
    'Name', p_Name_5574320d,
    'Description', p_Description_5574320d,
    'RequiresExecutedDocument', p_RequiresExecutedDocument_5574320d,
    'Status', p_Status_5574320d,
    'MustBeRoot', p_MustBeRoot_5574320d,
    'MustBeChild', p_MustBeChild_5574320d,
    'TemplateRequired', p_TemplateRequired_5574320d
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_ID := p_ID_5574320d, p_Name := p_Name_5574320d, p_Description := p_Description_5574320d, p_RequiresExecutedDocument := p_RequiresExecutedDocument_5574320d, p_Status := p_Status_5574320d, p_MustBeRoot := p_MustBeRoot_5574320d, p_MustBeChild := p_MustBeChild_5574320d, p_TemplateRequired := p_TemplateRequired_5574320d);
  END IF;
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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_data := jsonb_build_object(
    'ID', p_ID_9e472895,
    'Name', p_Name_9e472895,
    'Description', p_Description_9e472895,
    'RequiresExecutedDocument', p_RequiresExecutedDocument_9e472895,
    'Status', p_Status_9e472895,
    'MustBeRoot', p_MustBeRoot_9e472895,
    'MustBeChild', p_MustBeChild_9e472895,
    'TemplateRequired', p_TemplateRequired_9e472895
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_ID := p_ID_9e472895, p_Name := p_Name_9e472895, p_Description := p_Description_9e472895, p_RequiresExecutedDocument := p_RequiresExecutedDocument_9e472895, p_Status := p_Status_9e472895, p_MustBeRoot := p_MustBeRoot_9e472895, p_MustBeChild := p_MustBeChild_9e472895, p_TemplateRequired := p_TemplateRequired_9e472895);
  END IF;
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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_data := jsonb_build_object(
    'ID', p_ID_8b89bf80,
    'Name', p_Name_8b89bf80,
    'Description', p_Description_8b89bf80,
    'RequiresExecutedDocument', p_RequiresExecutedDocument_8b89bf80,
    'Status', p_Status_8b89bf80,
    'MustBeRoot', p_MustBeRoot_8b89bf80,
    'MustBeChild', p_MustBeChild_8b89bf80,
    'TemplateRequired', p_TemplateRequired_8b89bf80
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_ID := p_ID_8b89bf80, p_Name := p_Name_8b89bf80, p_Description := p_Description_8b89bf80, p_RequiresExecutedDocument := p_RequiresExecutedDocument_8b89bf80, p_Status := p_Status_8b89bf80, p_MustBeRoot := p_MustBeRoot_8b89bf80, p_MustBeChild := p_MustBeChild_8b89bf80, p_TemplateRequired := p_TemplateRequired_8b89bf80);
  END IF;
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
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spCreateContractType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_data := jsonb_build_object(
    'ID', p_ID_d32186e0,
    'Name', p_Name_d32186e0,
    'Description', p_Description_d32186e0,
    'RequiresExecutedDocument', p_RequiresExecutedDocument_d32186e0,
    'Status', p_Status_d32186e0,
    'MustBeRoot', p_MustBeRoot_d32186e0,
    'MustBeChild', p_MustBeChild_d32186e0,
    'TemplateRequired', p_TemplateRequired_d32186e0
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spCreateContractType"(p_ID := p_ID_d32186e0, p_Name := p_Name_d32186e0, p_Description := p_Description_d32186e0, p_RequiresExecutedDocument := p_RequiresExecutedDocument_d32186e0, p_Status := p_Status_d32186e0, p_MustBeRoot := p_MustBeRoot_d32186e0, p_MustBeChild := p_MustBeChild_d32186e0, p_TemplateRequired := p_TemplateRequired_d32186e0);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_c4aabc10 UUID;
  p_Sequence_c4aabc10 INTEGER;
  p_RelatedEntityID_c4aabc10 UUID;
  p_BundleInAPI_c4aabc10 BOOLEAN;
  p_IncludeInParentAllQuery_c4aabc10 BOOLEAN;
  p_Type_c4aabc10 CHAR(20);
  p_EntityKeyField_c4aabc10 VARCHAR(255);
  p_RelatedEntityJoinField_c4aabc10 VARCHAR(255);
  p_JoinView_c4aabc10 VARCHAR(255);
  p_JoinEntityJoinField_c4aabc10 VARCHAR(255);
  p_JoinEntityInverseJoinField_c4aabc10 VARCHAR(255);
  p_DisplayInForm_c4aabc10 BOOLEAN;
  p_DisplayLocation_c4aabc10 VARCHAR(50);
  p_DisplayName_c4aabc10 VARCHAR(255);
  p_DisplayIconType_c4aabc10 VARCHAR(50);
  p_DisplayIcon_c4aabc10 VARCHAR(255);
  p_DisplayComponentID_c4aabc10 UUID;
  p_DisplayComponentConfiguration_c4aabc10 TEXT;
  p_AutoUpdateFromSchema_c4aabc10 BOOLEAN;
  p_AdditionalFieldsToInclude_c4aabc10 TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_c4aabc10 BOOLEAN;
  p_RelatedRecordCollection_c4aabc10 TEXT;
  p_Configuration_c4aabc10 TEXT;
  p_ID_c4aabc10 UUID;
BEGIN
  p_EntityID_c4aabc10 := '731F2890-1415-40DE-9073-D22EA23392B3';
  p_Sequence_c4aabc10 := 1;
  p_RelatedEntityID_c4aabc10 := '317DF592-8C20-473D-B097-2AB239877438';
  p_BundleInAPI_c4aabc10 := TRUE;
  p_IncludeInParentAllQuery_c4aabc10 := FALSE;
  p_Type_c4aabc10 := 'One To Many';
  p_RelatedEntityJoinField_c4aabc10 := 'ContractTemplateID';
  p_DisplayInForm_c4aabc10 := TRUE;
  p_DisplayLocation_c4aabc10 := 'After Field Tabs';
  p_DisplayIconType_c4aabc10 := 'Related Entity Icon';
  p_AutoUpdateFromSchema_c4aabc10 := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_c4aabc10 := TRUE;
  p_RelatedRecordCollection_c4aabc10 := '{"Name":"Provisions","Source":"database","Load":"explicit","OnRemove":"delete","OrderBy":"ProvisionSortKey ASC","ClearAfterSave":false}';
  p_ID_c4aabc10 := 'E415E5BF-FCAA-49A6-BF33-EF3BC2D0D865';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_c4aabc10,
    'Sequence', p_Sequence_c4aabc10,
    'RelatedEntityID', p_RelatedEntityID_c4aabc10,
    'BundleInAPI', p_BundleInAPI_c4aabc10,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_c4aabc10,
    'Type', p_Type_c4aabc10,
    'EntityKeyField', p_EntityKeyField_c4aabc10,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_c4aabc10,
    'JoinView', p_JoinView_c4aabc10,
    'JoinEntityJoinField', p_JoinEntityJoinField_c4aabc10,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_c4aabc10,
    'DisplayInForm', p_DisplayInForm_c4aabc10,
    'DisplayLocation', p_DisplayLocation_c4aabc10,
    'DisplayName', p_DisplayName_c4aabc10,
    'DisplayIconType', p_DisplayIconType_c4aabc10,
    'DisplayIcon', p_DisplayIcon_c4aabc10,
    'DisplayComponentID', p_DisplayComponentID_c4aabc10,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_c4aabc10,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_c4aabc10,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_c4aabc10,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_c4aabc10,
    'RelatedRecordCollection', p_RelatedRecordCollection_c4aabc10,
    'Configuration', p_Configuration_c4aabc10,
    'ID', p_ID_c4aabc10
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_c4aabc10, p_Sequence := p_Sequence_c4aabc10, p_RelatedEntityID := p_RelatedEntityID_c4aabc10, p_BundleInAPI := p_BundleInAPI_c4aabc10, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_c4aabc10, p_Type := p_Type_c4aabc10, p_EntityKeyField := p_EntityKeyField_c4aabc10, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_c4aabc10, p_JoinView := p_JoinView_c4aabc10, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_c4aabc10, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_c4aabc10, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_c4aabc10, p_DisplayLocation := p_DisplayLocation_c4aabc10, p_DisplayName := p_DisplayName_c4aabc10, p_DisplayName_Clear := TRUE, p_DisplayIconType := p_DisplayIconType_c4aabc10, p_DisplayIcon := p_DisplayIcon_c4aabc10, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_c4aabc10, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_c4aabc10, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_c4aabc10, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_c4aabc10, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_c4aabc10, p_RelatedRecordCollection := p_RelatedRecordCollection_c4aabc10, p_Configuration := p_Configuration_c4aabc10, p_Configuration_Clear := TRUE, p_ID := p_ID_c4aabc10);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_fb6d0f3b UUID;
  p_Sequence_fb6d0f3b INTEGER;
  p_RelatedEntityID_fb6d0f3b UUID;
  p_BundleInAPI_fb6d0f3b BOOLEAN;
  p_IncludeInParentAllQuery_fb6d0f3b BOOLEAN;
  p_Type_fb6d0f3b CHAR(20);
  p_EntityKeyField_fb6d0f3b VARCHAR(255);
  p_RelatedEntityJoinField_fb6d0f3b VARCHAR(255);
  p_JoinView_fb6d0f3b VARCHAR(255);
  p_JoinEntityJoinField_fb6d0f3b VARCHAR(255);
  p_JoinEntityInverseJoinField_fb6d0f3b VARCHAR(255);
  p_DisplayInForm_fb6d0f3b BOOLEAN;
  p_DisplayLocation_fb6d0f3b VARCHAR(50);
  p_DisplayName_fb6d0f3b VARCHAR(255);
  p_DisplayIconType_fb6d0f3b VARCHAR(50);
  p_DisplayIcon_fb6d0f3b VARCHAR(255);
  p_DisplayComponentID_fb6d0f3b UUID;
  p_DisplayComponentConfiguration_fb6d0f3b TEXT;
  p_AutoUpdateFromSchema_fb6d0f3b BOOLEAN;
  p_AdditionalFieldsToInclude_fb6d0f3b TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_fb6d0f3b BOOLEAN;
  p_RelatedRecordCollection_fb6d0f3b TEXT;
  p_Configuration_fb6d0f3b TEXT;
  p_ID_fb6d0f3b UUID;
BEGIN
  p_EntityID_fb6d0f3b := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_Sequence_fb6d0f3b := 1;
  p_RelatedEntityID_fb6d0f3b := 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';
  p_BundleInAPI_fb6d0f3b := TRUE;
  p_IncludeInParentAllQuery_fb6d0f3b := FALSE;
  p_Type_fb6d0f3b := 'One To Many';
  p_RelatedEntityJoinField_fb6d0f3b := 'ContractID';
  p_DisplayInForm_fb6d0f3b := TRUE;
  p_DisplayLocation_fb6d0f3b := 'After Field Tabs';
  p_DisplayIconType_fb6d0f3b := 'Related Entity Icon';
  p_AutoUpdateFromSchema_fb6d0f3b := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_fb6d0f3b := TRUE;
  p_RelatedRecordCollection_fb6d0f3b := '{"Name":"Modifications","Source":"database","Load":"explicit","OnRemove":"delete","OrderBy":"__mj_CreatedAt ASC","ClearAfterSave":false}';
  p_ID_fb6d0f3b := '0A972E9E-ABAA-47FE-8DD7-90D1A60DC25D';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_fb6d0f3b,
    'Sequence', p_Sequence_fb6d0f3b,
    'RelatedEntityID', p_RelatedEntityID_fb6d0f3b,
    'BundleInAPI', p_BundleInAPI_fb6d0f3b,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_fb6d0f3b,
    'Type', p_Type_fb6d0f3b,
    'EntityKeyField', p_EntityKeyField_fb6d0f3b,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_fb6d0f3b,
    'JoinView', p_JoinView_fb6d0f3b,
    'JoinEntityJoinField', p_JoinEntityJoinField_fb6d0f3b,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_fb6d0f3b,
    'DisplayInForm', p_DisplayInForm_fb6d0f3b,
    'DisplayLocation', p_DisplayLocation_fb6d0f3b,
    'DisplayName', p_DisplayName_fb6d0f3b,
    'DisplayIconType', p_DisplayIconType_fb6d0f3b,
    'DisplayIcon', p_DisplayIcon_fb6d0f3b,
    'DisplayComponentID', p_DisplayComponentID_fb6d0f3b,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_fb6d0f3b,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_fb6d0f3b,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_fb6d0f3b,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_fb6d0f3b,
    'RelatedRecordCollection', p_RelatedRecordCollection_fb6d0f3b,
    'Configuration', p_Configuration_fb6d0f3b,
    'ID', p_ID_fb6d0f3b
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_fb6d0f3b, p_Sequence := p_Sequence_fb6d0f3b, p_RelatedEntityID := p_RelatedEntityID_fb6d0f3b, p_BundleInAPI := p_BundleInAPI_fb6d0f3b, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_fb6d0f3b, p_Type := p_Type_fb6d0f3b, p_EntityKeyField := p_EntityKeyField_fb6d0f3b, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_fb6d0f3b, p_JoinView := p_JoinView_fb6d0f3b, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_fb6d0f3b, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_fb6d0f3b, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_fb6d0f3b, p_DisplayLocation := p_DisplayLocation_fb6d0f3b, p_DisplayName := p_DisplayName_fb6d0f3b, p_DisplayName_Clear := TRUE, p_DisplayIconType := p_DisplayIconType_fb6d0f3b, p_DisplayIcon := p_DisplayIcon_fb6d0f3b, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_fb6d0f3b, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_fb6d0f3b, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_fb6d0f3b, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_fb6d0f3b, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_fb6d0f3b, p_RelatedRecordCollection := p_RelatedRecordCollection_fb6d0f3b, p_Configuration := p_Configuration_fb6d0f3b, p_Configuration_Clear := TRUE, p_ID := p_ID_fb6d0f3b);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_9a5ada02 UUID;
  p_Sequence_9a5ada02 INTEGER;
  p_RelatedEntityID_9a5ada02 UUID;
  p_BundleInAPI_9a5ada02 BOOLEAN;
  p_IncludeInParentAllQuery_9a5ada02 BOOLEAN;
  p_Type_9a5ada02 CHAR(20);
  p_EntityKeyField_9a5ada02 VARCHAR(255);
  p_RelatedEntityJoinField_9a5ada02 VARCHAR(255);
  p_JoinView_9a5ada02 VARCHAR(255);
  p_JoinEntityJoinField_9a5ada02 VARCHAR(255);
  p_JoinEntityInverseJoinField_9a5ada02 VARCHAR(255);
  p_DisplayInForm_9a5ada02 BOOLEAN;
  p_DisplayLocation_9a5ada02 VARCHAR(50);
  p_DisplayName_9a5ada02 VARCHAR(255);
  p_DisplayIconType_9a5ada02 VARCHAR(50);
  p_DisplayIcon_9a5ada02 VARCHAR(255);
  p_DisplayComponentID_9a5ada02 UUID;
  p_DisplayComponentConfiguration_9a5ada02 TEXT;
  p_AutoUpdateFromSchema_9a5ada02 BOOLEAN;
  p_AdditionalFieldsToInclude_9a5ada02 TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_9a5ada02 BOOLEAN;
  p_RelatedRecordCollection_9a5ada02 TEXT;
  p_Configuration_9a5ada02 TEXT;
  p_ID_9a5ada02 UUID;
BEGIN
  p_EntityID_9a5ada02 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_Sequence_9a5ada02 := 1;
  p_RelatedEntityID_9a5ada02 := 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';
  p_BundleInAPI_9a5ada02 := TRUE;
  p_IncludeInParentAllQuery_9a5ada02 := FALSE;
  p_Type_9a5ada02 := 'One To Many';
  p_RelatedEntityJoinField_9a5ada02 := 'ContractID';
  p_DisplayInForm_9a5ada02 := TRUE;
  p_DisplayLocation_9a5ada02 := 'After Field Tabs';
  p_DisplayName_9a5ada02 := 'Modifications';
  p_DisplayIconType_9a5ada02 := 'Related Entity Icon';
  p_AutoUpdateFromSchema_9a5ada02 := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_9a5ada02 := TRUE;
  p_RelatedRecordCollection_9a5ada02 := '{"Name":"Modifications","Source":"database","Load":"explicit","OnRemove":"delete","OrderBy":"__mj_CreatedAt ASC","ClearAfterSave":false}';
  p_Configuration_9a5ada02 := '{
  "UI": {
    "inclusion": "Primary"
  }
}';
  p_ID_9a5ada02 := '0A972E9E-ABAA-47FE-8DD7-90D1A60DC25D';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_9a5ada02,
    'Sequence', p_Sequence_9a5ada02,
    'RelatedEntityID', p_RelatedEntityID_9a5ada02,
    'BundleInAPI', p_BundleInAPI_9a5ada02,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_9a5ada02,
    'Type', p_Type_9a5ada02,
    'EntityKeyField', p_EntityKeyField_9a5ada02,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_9a5ada02,
    'JoinView', p_JoinView_9a5ada02,
    'JoinEntityJoinField', p_JoinEntityJoinField_9a5ada02,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_9a5ada02,
    'DisplayInForm', p_DisplayInForm_9a5ada02,
    'DisplayLocation', p_DisplayLocation_9a5ada02,
    'DisplayName', p_DisplayName_9a5ada02,
    'DisplayIconType', p_DisplayIconType_9a5ada02,
    'DisplayIcon', p_DisplayIcon_9a5ada02,
    'DisplayComponentID', p_DisplayComponentID_9a5ada02,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_9a5ada02,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_9a5ada02,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_9a5ada02,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_9a5ada02,
    'RelatedRecordCollection', p_RelatedRecordCollection_9a5ada02,
    'Configuration', p_Configuration_9a5ada02,
    'ID', p_ID_9a5ada02
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_9a5ada02, p_Sequence := p_Sequence_9a5ada02, p_RelatedEntityID := p_RelatedEntityID_9a5ada02, p_BundleInAPI := p_BundleInAPI_9a5ada02, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_9a5ada02, p_Type := p_Type_9a5ada02, p_EntityKeyField := p_EntityKeyField_9a5ada02, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_9a5ada02, p_JoinView := p_JoinView_9a5ada02, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_9a5ada02, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_9a5ada02, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_9a5ada02, p_DisplayLocation := p_DisplayLocation_9a5ada02, p_DisplayName := p_DisplayName_9a5ada02, p_DisplayIconType := p_DisplayIconType_9a5ada02, p_DisplayIcon := p_DisplayIcon_9a5ada02, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_9a5ada02, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_9a5ada02, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_9a5ada02, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_9a5ada02, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_9a5ada02, p_RelatedRecordCollection := p_RelatedRecordCollection_9a5ada02, p_Configuration := p_Configuration_9a5ada02, p_ID := p_ID_9a5ada02);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_a775608f UUID;
  p_Sequence_a775608f INTEGER;
  p_RelatedEntityID_a775608f UUID;
  p_BundleInAPI_a775608f BOOLEAN;
  p_IncludeInParentAllQuery_a775608f BOOLEAN;
  p_Type_a775608f CHAR(20);
  p_EntityKeyField_a775608f VARCHAR(255);
  p_RelatedEntityJoinField_a775608f VARCHAR(255);
  p_JoinView_a775608f VARCHAR(255);
  p_JoinEntityJoinField_a775608f VARCHAR(255);
  p_JoinEntityInverseJoinField_a775608f VARCHAR(255);
  p_DisplayInForm_a775608f BOOLEAN;
  p_DisplayLocation_a775608f VARCHAR(50);
  p_DisplayName_a775608f VARCHAR(255);
  p_DisplayIconType_a775608f VARCHAR(50);
  p_DisplayIcon_a775608f VARCHAR(255);
  p_DisplayComponentID_a775608f UUID;
  p_DisplayComponentConfiguration_a775608f TEXT;
  p_AutoUpdateFromSchema_a775608f BOOLEAN;
  p_AdditionalFieldsToInclude_a775608f TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_a775608f BOOLEAN;
  p_RelatedRecordCollection_a775608f TEXT;
  p_Configuration_a775608f TEXT;
  p_ID_a775608f UUID;
BEGIN
  p_EntityID_a775608f := '731F2890-1415-40DE-9073-D22EA23392B3';
  p_Sequence_a775608f := 1;
  p_RelatedEntityID_a775608f := '317DF592-8C20-473D-B097-2AB239877438';
  p_BundleInAPI_a775608f := TRUE;
  p_IncludeInParentAllQuery_a775608f := FALSE;
  p_Type_a775608f := 'One To Many';
  p_RelatedEntityJoinField_a775608f := 'ContractTemplateID';
  p_DisplayInForm_a775608f := TRUE;
  p_DisplayLocation_a775608f := 'After Field Tabs';
  p_DisplayName_a775608f := 'Provisions';
  p_DisplayIconType_a775608f := 'Related Entity Icon';
  p_AutoUpdateFromSchema_a775608f := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_a775608f := TRUE;
  p_RelatedRecordCollection_a775608f := '{"Name":"Provisions","Source":"database","Load":"explicit","OnRemove":"delete","OrderBy":"ProvisionSortKey ASC","ClearAfterSave":false}';
  p_Configuration_a775608f := '{
  "UI": {
    "inclusion": "Primary"
  }
}';
  p_ID_a775608f := 'E415E5BF-FCAA-49A6-BF33-EF3BC2D0D865';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_a775608f,
    'Sequence', p_Sequence_a775608f,
    'RelatedEntityID', p_RelatedEntityID_a775608f,
    'BundleInAPI', p_BundleInAPI_a775608f,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_a775608f,
    'Type', p_Type_a775608f,
    'EntityKeyField', p_EntityKeyField_a775608f,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_a775608f,
    'JoinView', p_JoinView_a775608f,
    'JoinEntityJoinField', p_JoinEntityJoinField_a775608f,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_a775608f,
    'DisplayInForm', p_DisplayInForm_a775608f,
    'DisplayLocation', p_DisplayLocation_a775608f,
    'DisplayName', p_DisplayName_a775608f,
    'DisplayIconType', p_DisplayIconType_a775608f,
    'DisplayIcon', p_DisplayIcon_a775608f,
    'DisplayComponentID', p_DisplayComponentID_a775608f,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_a775608f,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_a775608f,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_a775608f,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_a775608f,
    'RelatedRecordCollection', p_RelatedRecordCollection_a775608f,
    'Configuration', p_Configuration_a775608f,
    'ID', p_ID_a775608f
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_a775608f, p_Sequence := p_Sequence_a775608f, p_RelatedEntityID := p_RelatedEntityID_a775608f, p_BundleInAPI := p_BundleInAPI_a775608f, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_a775608f, p_Type := p_Type_a775608f, p_EntityKeyField := p_EntityKeyField_a775608f, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_a775608f, p_JoinView := p_JoinView_a775608f, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_a775608f, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_a775608f, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_a775608f, p_DisplayLocation := p_DisplayLocation_a775608f, p_DisplayName := p_DisplayName_a775608f, p_DisplayIconType := p_DisplayIconType_a775608f, p_DisplayIcon := p_DisplayIcon_a775608f, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_a775608f, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_a775608f, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_a775608f, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_a775608f, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_a775608f, p_RelatedRecordCollection := p_RelatedRecordCollection_a775608f, p_Configuration := p_Configuration_a775608f, p_ID := p_ID_a775608f);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_a8608b08 UUID;
  p_Sequence_a8608b08 INTEGER;
  p_RelatedEntityID_a8608b08 UUID;
  p_BundleInAPI_a8608b08 BOOLEAN;
  p_IncludeInParentAllQuery_a8608b08 BOOLEAN;
  p_Type_a8608b08 CHAR(20);
  p_EntityKeyField_a8608b08 VARCHAR(255);
  p_RelatedEntityJoinField_a8608b08 VARCHAR(255);
  p_JoinView_a8608b08 VARCHAR(255);
  p_JoinEntityJoinField_a8608b08 VARCHAR(255);
  p_JoinEntityInverseJoinField_a8608b08 VARCHAR(255);
  p_DisplayInForm_a8608b08 BOOLEAN;
  p_DisplayLocation_a8608b08 VARCHAR(50);
  p_DisplayName_a8608b08 VARCHAR(255);
  p_DisplayIconType_a8608b08 VARCHAR(50);
  p_DisplayIcon_a8608b08 VARCHAR(255);
  p_DisplayComponentID_a8608b08 UUID;
  p_DisplayComponentConfiguration_a8608b08 TEXT;
  p_AutoUpdateFromSchema_a8608b08 BOOLEAN;
  p_AdditionalFieldsToInclude_a8608b08 TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_a8608b08 BOOLEAN;
  p_RelatedRecordCollection_a8608b08 TEXT;
  p_Configuration_a8608b08 TEXT;
  p_ID_a8608b08 UUID;
BEGIN
  p_EntityID_a8608b08 := 'C70448F9-9792-41D7-A82C-784B66429D54';
  p_Sequence_a8608b08 := 5;
  p_RelatedEntityID_a8608b08 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_a8608b08 := TRUE;
  p_IncludeInParentAllQuery_a8608b08 := FALSE;
  p_Type_a8608b08 := 'One To Many';
  p_RelatedEntityJoinField_a8608b08 := 'CustomerOrganizationID';
  p_DisplayInForm_a8608b08 := TRUE;
  p_DisplayLocation_a8608b08 := 'After Field Tabs';
  p_DisplayName_a8608b08 := 'Agreements';
  p_DisplayIconType_a8608b08 := 'Related Entity Icon';
  p_AutoUpdateFromSchema_a8608b08 := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_a8608b08 := TRUE;
  p_Configuration_a8608b08 := '{
  "UI": {
    "inclusion": "Primary"
  }
}';
  p_ID_a8608b08 := 'C674FABB-6DF9-434E-90C0-99EC631F234B';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_a8608b08,
    'Sequence', p_Sequence_a8608b08,
    'RelatedEntityID', p_RelatedEntityID_a8608b08,
    'BundleInAPI', p_BundleInAPI_a8608b08,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_a8608b08,
    'Type', p_Type_a8608b08,
    'EntityKeyField', p_EntityKeyField_a8608b08,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_a8608b08,
    'JoinView', p_JoinView_a8608b08,
    'JoinEntityJoinField', p_JoinEntityJoinField_a8608b08,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_a8608b08,
    'DisplayInForm', p_DisplayInForm_a8608b08,
    'DisplayLocation', p_DisplayLocation_a8608b08,
    'DisplayName', p_DisplayName_a8608b08,
    'DisplayIconType', p_DisplayIconType_a8608b08,
    'DisplayIcon', p_DisplayIcon_a8608b08,
    'DisplayComponentID', p_DisplayComponentID_a8608b08,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_a8608b08,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_a8608b08,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_a8608b08,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_a8608b08,
    'RelatedRecordCollection', p_RelatedRecordCollection_a8608b08,
    'Configuration', p_Configuration_a8608b08,
    'ID', p_ID_a8608b08
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_a8608b08, p_Sequence := p_Sequence_a8608b08, p_RelatedEntityID := p_RelatedEntityID_a8608b08, p_BundleInAPI := p_BundleInAPI_a8608b08, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_a8608b08, p_Type := p_Type_a8608b08, p_EntityKeyField := p_EntityKeyField_a8608b08, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_a8608b08, p_JoinView := p_JoinView_a8608b08, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_a8608b08, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_a8608b08, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_a8608b08, p_DisplayLocation := p_DisplayLocation_a8608b08, p_DisplayName := p_DisplayName_a8608b08, p_DisplayIconType := p_DisplayIconType_a8608b08, p_DisplayIcon := p_DisplayIcon_a8608b08, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_a8608b08, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_a8608b08, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_a8608b08, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_a8608b08, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_a8608b08, p_RelatedRecordCollection := p_RelatedRecordCollection_a8608b08, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_a8608b08, p_ID := p_ID_a8608b08);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_3a6e513b UUID;
  p_Sequence_3a6e513b INTEGER;
  p_RelatedEntityID_3a6e513b UUID;
  p_BundleInAPI_3a6e513b BOOLEAN;
  p_IncludeInParentAllQuery_3a6e513b BOOLEAN;
  p_Type_3a6e513b CHAR(20);
  p_EntityKeyField_3a6e513b VARCHAR(255);
  p_RelatedEntityJoinField_3a6e513b VARCHAR(255);
  p_JoinView_3a6e513b VARCHAR(255);
  p_JoinEntityJoinField_3a6e513b VARCHAR(255);
  p_JoinEntityInverseJoinField_3a6e513b VARCHAR(255);
  p_DisplayInForm_3a6e513b BOOLEAN;
  p_DisplayLocation_3a6e513b VARCHAR(50);
  p_DisplayName_3a6e513b VARCHAR(255);
  p_DisplayIconType_3a6e513b VARCHAR(50);
  p_DisplayIcon_3a6e513b VARCHAR(255);
  p_DisplayComponentID_3a6e513b UUID;
  p_DisplayComponentConfiguration_3a6e513b TEXT;
  p_AutoUpdateFromSchema_3a6e513b BOOLEAN;
  p_AdditionalFieldsToInclude_3a6e513b TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_3a6e513b BOOLEAN;
  p_RelatedRecordCollection_3a6e513b TEXT;
  p_Configuration_3a6e513b TEXT;
  p_ID_3a6e513b UUID;
BEGIN
  p_EntityID_3a6e513b := 'D4238F34-2837-EF11-86D4-6045BDEE16E6';
  p_Sequence_3a6e513b := 7;
  p_RelatedEntityID_3a6e513b := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_3a6e513b := TRUE;
  p_IncludeInParentAllQuery_3a6e513b := FALSE;
  p_Type_3a6e513b := 'One To Many';
  p_RelatedEntityJoinField_3a6e513b := 'CompanyID';
  p_DisplayInForm_3a6e513b := FALSE;
  p_DisplayLocation_3a6e513b := 'After Field Tabs';
  p_DisplayIconType_3a6e513b := 'Related Entity Icon';
  p_AutoUpdateFromSchema_3a6e513b := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_3a6e513b := TRUE;
  p_Configuration_3a6e513b := '{
  "UI": {
    "inclusion": "None"
  }
}';
  p_ID_3a6e513b := 'AA2AA995-A5FA-4565-8355-90E26F36365D';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_3a6e513b,
    'Sequence', p_Sequence_3a6e513b,
    'RelatedEntityID', p_RelatedEntityID_3a6e513b,
    'BundleInAPI', p_BundleInAPI_3a6e513b,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_3a6e513b,
    'Type', p_Type_3a6e513b,
    'EntityKeyField', p_EntityKeyField_3a6e513b,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_3a6e513b,
    'JoinView', p_JoinView_3a6e513b,
    'JoinEntityJoinField', p_JoinEntityJoinField_3a6e513b,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_3a6e513b,
    'DisplayInForm', p_DisplayInForm_3a6e513b,
    'DisplayLocation', p_DisplayLocation_3a6e513b,
    'DisplayName', p_DisplayName_3a6e513b,
    'DisplayIconType', p_DisplayIconType_3a6e513b,
    'DisplayIcon', p_DisplayIcon_3a6e513b,
    'DisplayComponentID', p_DisplayComponentID_3a6e513b,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_3a6e513b,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_3a6e513b,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_3a6e513b,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_3a6e513b,
    'RelatedRecordCollection', p_RelatedRecordCollection_3a6e513b,
    'Configuration', p_Configuration_3a6e513b,
    'ID', p_ID_3a6e513b
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_3a6e513b, p_Sequence := p_Sequence_3a6e513b, p_RelatedEntityID := p_RelatedEntityID_3a6e513b, p_BundleInAPI := p_BundleInAPI_3a6e513b, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_3a6e513b, p_Type := p_Type_3a6e513b, p_EntityKeyField := p_EntityKeyField_3a6e513b, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_3a6e513b, p_JoinView := p_JoinView_3a6e513b, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_3a6e513b, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_3a6e513b, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_3a6e513b, p_DisplayLocation := p_DisplayLocation_3a6e513b, p_DisplayName := p_DisplayName_3a6e513b, p_DisplayName_Clear := TRUE, p_DisplayIconType := p_DisplayIconType_3a6e513b, p_DisplayIcon := p_DisplayIcon_3a6e513b, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_3a6e513b, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_3a6e513b, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_3a6e513b, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_3a6e513b, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_3a6e513b, p_RelatedRecordCollection := p_RelatedRecordCollection_3a6e513b, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_3a6e513b, p_ID := p_ID_3a6e513b);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_a33b8232 UUID;
  p_Sequence_a33b8232 INTEGER;
  p_RelatedEntityID_a33b8232 UUID;
  p_BundleInAPI_a33b8232 BOOLEAN;
  p_IncludeInParentAllQuery_a33b8232 BOOLEAN;
  p_Type_a33b8232 CHAR(20);
  p_EntityKeyField_a33b8232 VARCHAR(255);
  p_RelatedEntityJoinField_a33b8232 VARCHAR(255);
  p_JoinView_a33b8232 VARCHAR(255);
  p_JoinEntityJoinField_a33b8232 VARCHAR(255);
  p_JoinEntityInverseJoinField_a33b8232 VARCHAR(255);
  p_DisplayInForm_a33b8232 BOOLEAN;
  p_DisplayLocation_a33b8232 VARCHAR(50);
  p_DisplayName_a33b8232 VARCHAR(255);
  p_DisplayIconType_a33b8232 VARCHAR(50);
  p_DisplayIcon_a33b8232 VARCHAR(255);
  p_DisplayComponentID_a33b8232 UUID;
  p_DisplayComponentConfiguration_a33b8232 TEXT;
  p_AutoUpdateFromSchema_a33b8232 BOOLEAN;
  p_AdditionalFieldsToInclude_a33b8232 TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_a33b8232 BOOLEAN;
  p_RelatedRecordCollection_a33b8232 TEXT;
  p_Configuration_a33b8232 TEXT;
  p_ID_a33b8232 UUID;
BEGIN
  p_EntityID_a33b8232 := '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F';
  p_Sequence_a33b8232 := 4;
  p_RelatedEntityID_a33b8232 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_a33b8232 := TRUE;
  p_IncludeInParentAllQuery_a33b8232 := FALSE;
  p_Type_a33b8232 := 'One To Many';
  p_RelatedEntityJoinField_a33b8232 := 'PrimaryContactPersonID';
  p_DisplayInForm_a33b8232 := TRUE;
  p_DisplayLocation_a33b8232 := 'After Field Tabs';
  p_DisplayName_a33b8232 := 'Agreements';
  p_DisplayIconType_a33b8232 := 'Related Entity Icon';
  p_AutoUpdateFromSchema_a33b8232 := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_a33b8232 := TRUE;
  p_Configuration_a33b8232 := '{
  "UI": {
    "inclusion": "More"
  }
}';
  p_ID_a33b8232 := '6F16093E-BA7A-44C9-8E06-901F3383C7DC';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_a33b8232,
    'Sequence', p_Sequence_a33b8232,
    'RelatedEntityID', p_RelatedEntityID_a33b8232,
    'BundleInAPI', p_BundleInAPI_a33b8232,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_a33b8232,
    'Type', p_Type_a33b8232,
    'EntityKeyField', p_EntityKeyField_a33b8232,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_a33b8232,
    'JoinView', p_JoinView_a33b8232,
    'JoinEntityJoinField', p_JoinEntityJoinField_a33b8232,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_a33b8232,
    'DisplayInForm', p_DisplayInForm_a33b8232,
    'DisplayLocation', p_DisplayLocation_a33b8232,
    'DisplayName', p_DisplayName_a33b8232,
    'DisplayIconType', p_DisplayIconType_a33b8232,
    'DisplayIcon', p_DisplayIcon_a33b8232,
    'DisplayComponentID', p_DisplayComponentID_a33b8232,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_a33b8232,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_a33b8232,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_a33b8232,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_a33b8232,
    'RelatedRecordCollection', p_RelatedRecordCollection_a33b8232,
    'Configuration', p_Configuration_a33b8232,
    'ID', p_ID_a33b8232
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_a33b8232, p_Sequence := p_Sequence_a33b8232, p_RelatedEntityID := p_RelatedEntityID_a33b8232, p_BundleInAPI := p_BundleInAPI_a33b8232, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_a33b8232, p_Type := p_Type_a33b8232, p_EntityKeyField := p_EntityKeyField_a33b8232, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_a33b8232, p_JoinView := p_JoinView_a33b8232, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_a33b8232, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_a33b8232, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_a33b8232, p_DisplayLocation := p_DisplayLocation_a33b8232, p_DisplayName := p_DisplayName_a33b8232, p_DisplayIconType := p_DisplayIconType_a33b8232, p_DisplayIcon := p_DisplayIcon_a33b8232, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_a33b8232, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_a33b8232, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_a33b8232, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_a33b8232, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_a33b8232, p_RelatedRecordCollection := p_RelatedRecordCollection_a33b8232, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_a33b8232, p_ID := p_ID_a33b8232);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_857da0cf UUID;
  p_Sequence_857da0cf INTEGER;
  p_RelatedEntityID_857da0cf UUID;
  p_BundleInAPI_857da0cf BOOLEAN;
  p_IncludeInParentAllQuery_857da0cf BOOLEAN;
  p_Type_857da0cf CHAR(20);
  p_EntityKeyField_857da0cf VARCHAR(255);
  p_RelatedEntityJoinField_857da0cf VARCHAR(255);
  p_JoinView_857da0cf VARCHAR(255);
  p_JoinEntityJoinField_857da0cf VARCHAR(255);
  p_JoinEntityInverseJoinField_857da0cf VARCHAR(255);
  p_DisplayInForm_857da0cf BOOLEAN;
  p_DisplayLocation_857da0cf VARCHAR(50);
  p_DisplayName_857da0cf VARCHAR(255);
  p_DisplayIconType_857da0cf VARCHAR(50);
  p_DisplayIcon_857da0cf VARCHAR(255);
  p_DisplayComponentID_857da0cf UUID;
  p_DisplayComponentConfiguration_857da0cf TEXT;
  p_AutoUpdateFromSchema_857da0cf BOOLEAN;
  p_AdditionalFieldsToInclude_857da0cf TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_857da0cf BOOLEAN;
  p_RelatedRecordCollection_857da0cf TEXT;
  p_Configuration_857da0cf TEXT;
  p_ID_857da0cf UUID;
BEGIN
  p_EntityID_857da0cf := 'E0238F34-2837-EF11-86D4-6045BDEE16E6';
  p_Sequence_857da0cf := 77;
  p_RelatedEntityID_857da0cf := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_857da0cf := TRUE;
  p_IncludeInParentAllQuery_857da0cf := FALSE;
  p_Type_857da0cf := 'One To Many';
  p_RelatedEntityJoinField_857da0cf := 'CreatingEntityID';
  p_DisplayInForm_857da0cf := FALSE;
  p_DisplayLocation_857da0cf := 'After Field Tabs';
  p_DisplayIconType_857da0cf := 'Related Entity Icon';
  p_AutoUpdateFromSchema_857da0cf := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_857da0cf := TRUE;
  p_Configuration_857da0cf := '{
  "UI": {
    "inclusion": "None"
  }
}';
  p_ID_857da0cf := '7FA39DE0-72C9-4956-AD6C-476397A1AEAC';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_857da0cf,
    'Sequence', p_Sequence_857da0cf,
    'RelatedEntityID', p_RelatedEntityID_857da0cf,
    'BundleInAPI', p_BundleInAPI_857da0cf,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_857da0cf,
    'Type', p_Type_857da0cf,
    'EntityKeyField', p_EntityKeyField_857da0cf,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_857da0cf,
    'JoinView', p_JoinView_857da0cf,
    'JoinEntityJoinField', p_JoinEntityJoinField_857da0cf,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_857da0cf,
    'DisplayInForm', p_DisplayInForm_857da0cf,
    'DisplayLocation', p_DisplayLocation_857da0cf,
    'DisplayName', p_DisplayName_857da0cf,
    'DisplayIconType', p_DisplayIconType_857da0cf,
    'DisplayIcon', p_DisplayIcon_857da0cf,
    'DisplayComponentID', p_DisplayComponentID_857da0cf,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_857da0cf,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_857da0cf,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_857da0cf,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_857da0cf,
    'RelatedRecordCollection', p_RelatedRecordCollection_857da0cf,
    'Configuration', p_Configuration_857da0cf,
    'ID', p_ID_857da0cf
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_857da0cf, p_Sequence := p_Sequence_857da0cf, p_RelatedEntityID := p_RelatedEntityID_857da0cf, p_BundleInAPI := p_BundleInAPI_857da0cf, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_857da0cf, p_Type := p_Type_857da0cf, p_EntityKeyField := p_EntityKeyField_857da0cf, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_857da0cf, p_JoinView := p_JoinView_857da0cf, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_857da0cf, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_857da0cf, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_857da0cf, p_DisplayLocation := p_DisplayLocation_857da0cf, p_DisplayName := p_DisplayName_857da0cf, p_DisplayName_Clear := TRUE, p_DisplayIconType := p_DisplayIconType_857da0cf, p_DisplayIcon := p_DisplayIcon_857da0cf, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_857da0cf, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_857da0cf, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_857da0cf, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_857da0cf, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_857da0cf, p_RelatedRecordCollection := p_RelatedRecordCollection_857da0cf, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_857da0cf, p_ID := p_ID_857da0cf);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_340b4a93 UUID;
  p_Sequence_340b4a93 INTEGER;
  p_RelatedEntityID_340b4a93 UUID;
  p_BundleInAPI_340b4a93 BOOLEAN;
  p_IncludeInParentAllQuery_340b4a93 BOOLEAN;
  p_Type_340b4a93 CHAR(20);
  p_EntityKeyField_340b4a93 VARCHAR(255);
  p_RelatedEntityJoinField_340b4a93 VARCHAR(255);
  p_JoinView_340b4a93 VARCHAR(255);
  p_JoinEntityJoinField_340b4a93 VARCHAR(255);
  p_JoinEntityInverseJoinField_340b4a93 VARCHAR(255);
  p_DisplayInForm_340b4a93 BOOLEAN;
  p_DisplayLocation_340b4a93 VARCHAR(50);
  p_DisplayName_340b4a93 VARCHAR(255);
  p_DisplayIconType_340b4a93 VARCHAR(50);
  p_DisplayIcon_340b4a93 VARCHAR(255);
  p_DisplayComponentID_340b4a93 UUID;
  p_DisplayComponentConfiguration_340b4a93 TEXT;
  p_AutoUpdateFromSchema_340b4a93 BOOLEAN;
  p_AdditionalFieldsToInclude_340b4a93 TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_340b4a93 BOOLEAN;
  p_RelatedRecordCollection_340b4a93 TEXT;
  p_Configuration_340b4a93 TEXT;
  p_ID_340b4a93 UUID;
BEGIN
  p_EntityID_340b4a93 := '317DF592-8C20-473D-B097-2AB239877438';
  p_Sequence_340b4a93 := 1;
  p_RelatedEntityID_340b4a93 := 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';
  p_BundleInAPI_340b4a93 := TRUE;
  p_IncludeInParentAllQuery_340b4a93 := FALSE;
  p_Type_340b4a93 := 'One To Many';
  p_RelatedEntityJoinField_340b4a93 := 'ContractTemplateProvisionID';
  p_DisplayInForm_340b4a93 := FALSE;
  p_DisplayLocation_340b4a93 := 'After Field Tabs';
  p_DisplayIconType_340b4a93 := 'Related Entity Icon';
  p_AutoUpdateFromSchema_340b4a93 := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_340b4a93 := TRUE;
  p_Configuration_340b4a93 := '{
  "UI": {
    "inclusion": "None"
  }
}';
  p_ID_340b4a93 := '82939A7C-51C9-4723-BCD7-3CAECF976536';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_340b4a93,
    'Sequence', p_Sequence_340b4a93,
    'RelatedEntityID', p_RelatedEntityID_340b4a93,
    'BundleInAPI', p_BundleInAPI_340b4a93,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_340b4a93,
    'Type', p_Type_340b4a93,
    'EntityKeyField', p_EntityKeyField_340b4a93,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_340b4a93,
    'JoinView', p_JoinView_340b4a93,
    'JoinEntityJoinField', p_JoinEntityJoinField_340b4a93,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_340b4a93,
    'DisplayInForm', p_DisplayInForm_340b4a93,
    'DisplayLocation', p_DisplayLocation_340b4a93,
    'DisplayName', p_DisplayName_340b4a93,
    'DisplayIconType', p_DisplayIconType_340b4a93,
    'DisplayIcon', p_DisplayIcon_340b4a93,
    'DisplayComponentID', p_DisplayComponentID_340b4a93,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_340b4a93,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_340b4a93,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_340b4a93,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_340b4a93,
    'RelatedRecordCollection', p_RelatedRecordCollection_340b4a93,
    'Configuration', p_Configuration_340b4a93,
    'ID', p_ID_340b4a93
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_340b4a93, p_Sequence := p_Sequence_340b4a93, p_RelatedEntityID := p_RelatedEntityID_340b4a93, p_BundleInAPI := p_BundleInAPI_340b4a93, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_340b4a93, p_Type := p_Type_340b4a93, p_EntityKeyField := p_EntityKeyField_340b4a93, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_340b4a93, p_JoinView := p_JoinView_340b4a93, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_340b4a93, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_340b4a93, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_340b4a93, p_DisplayLocation := p_DisplayLocation_340b4a93, p_DisplayName := p_DisplayName_340b4a93, p_DisplayName_Clear := TRUE, p_DisplayIconType := p_DisplayIconType_340b4a93, p_DisplayIcon := p_DisplayIcon_340b4a93, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_340b4a93, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_340b4a93, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_340b4a93, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_340b4a93, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_340b4a93, p_RelatedRecordCollection := p_RelatedRecordCollection_340b4a93, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_340b4a93, p_ID := p_ID_340b4a93);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_b4742e6a UUID;
  p_Sequence_b4742e6a INTEGER;
  p_RelatedEntityID_b4742e6a UUID;
  p_BundleInAPI_b4742e6a BOOLEAN;
  p_IncludeInParentAllQuery_b4742e6a BOOLEAN;
  p_Type_b4742e6a CHAR(20);
  p_EntityKeyField_b4742e6a VARCHAR(255);
  p_RelatedEntityJoinField_b4742e6a VARCHAR(255);
  p_JoinView_b4742e6a VARCHAR(255);
  p_JoinEntityJoinField_b4742e6a VARCHAR(255);
  p_JoinEntityInverseJoinField_b4742e6a VARCHAR(255);
  p_DisplayInForm_b4742e6a BOOLEAN;
  p_DisplayLocation_b4742e6a VARCHAR(50);
  p_DisplayName_b4742e6a VARCHAR(255);
  p_DisplayIconType_b4742e6a VARCHAR(50);
  p_DisplayIcon_b4742e6a VARCHAR(255);
  p_DisplayComponentID_b4742e6a UUID;
  p_DisplayComponentConfiguration_b4742e6a TEXT;
  p_AutoUpdateFromSchema_b4742e6a BOOLEAN;
  p_AdditionalFieldsToInclude_b4742e6a TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_b4742e6a BOOLEAN;
  p_RelatedRecordCollection_b4742e6a TEXT;
  p_Configuration_b4742e6a TEXT;
  p_ID_b4742e6a UUID;
BEGIN
  p_EntityID_b4742e6a := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_Sequence_b4742e6a := 2;
  p_RelatedEntityID_b4742e6a := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_b4742e6a := TRUE;
  p_IncludeInParentAllQuery_b4742e6a := FALSE;
  p_Type_b4742e6a := 'One To Many';
  p_RelatedEntityJoinField_b4742e6a := 'SupersededByContractID';
  p_DisplayInForm_b4742e6a := TRUE;
  p_DisplayLocation_b4742e6a := 'After Field Tabs';
  p_DisplayName_b4742e6a := 'Supersedes';
  p_DisplayIconType_b4742e6a := 'Related Entity Icon';
  p_AutoUpdateFromSchema_b4742e6a := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_b4742e6a := TRUE;
  p_Configuration_b4742e6a := '{
  "UI": {
    "inclusion": "Primary"
  }
}';
  p_ID_b4742e6a := '3B056BC8-B985-403A-9DCC-ACCEF921C323';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_b4742e6a,
    'Sequence', p_Sequence_b4742e6a,
    'RelatedEntityID', p_RelatedEntityID_b4742e6a,
    'BundleInAPI', p_BundleInAPI_b4742e6a,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_b4742e6a,
    'Type', p_Type_b4742e6a,
    'EntityKeyField', p_EntityKeyField_b4742e6a,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_b4742e6a,
    'JoinView', p_JoinView_b4742e6a,
    'JoinEntityJoinField', p_JoinEntityJoinField_b4742e6a,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_b4742e6a,
    'DisplayInForm', p_DisplayInForm_b4742e6a,
    'DisplayLocation', p_DisplayLocation_b4742e6a,
    'DisplayName', p_DisplayName_b4742e6a,
    'DisplayIconType', p_DisplayIconType_b4742e6a,
    'DisplayIcon', p_DisplayIcon_b4742e6a,
    'DisplayComponentID', p_DisplayComponentID_b4742e6a,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_b4742e6a,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_b4742e6a,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_b4742e6a,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_b4742e6a,
    'RelatedRecordCollection', p_RelatedRecordCollection_b4742e6a,
    'Configuration', p_Configuration_b4742e6a,
    'ID', p_ID_b4742e6a
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_b4742e6a, p_Sequence := p_Sequence_b4742e6a, p_RelatedEntityID := p_RelatedEntityID_b4742e6a, p_BundleInAPI := p_BundleInAPI_b4742e6a, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_b4742e6a, p_Type := p_Type_b4742e6a, p_EntityKeyField := p_EntityKeyField_b4742e6a, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_b4742e6a, p_JoinView := p_JoinView_b4742e6a, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_b4742e6a, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_b4742e6a, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_b4742e6a, p_DisplayLocation := p_DisplayLocation_b4742e6a, p_DisplayName := p_DisplayName_b4742e6a, p_DisplayIconType := p_DisplayIconType_b4742e6a, p_DisplayIcon := p_DisplayIcon_b4742e6a, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_b4742e6a, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_b4742e6a, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_b4742e6a, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_b4742e6a, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_b4742e6a, p_RelatedRecordCollection := p_RelatedRecordCollection_b4742e6a, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_b4742e6a, p_ID := p_ID_b4742e6a);
  END IF;
END $mj$;

-- Save MJ: Entity Relationships (core SP call only)
DO $mj$
DECLARE
  p_EntityID_01eb08fb UUID;
  p_Sequence_01eb08fb INTEGER;
  p_RelatedEntityID_01eb08fb UUID;
  p_BundleInAPI_01eb08fb BOOLEAN;
  p_IncludeInParentAllQuery_01eb08fb BOOLEAN;
  p_Type_01eb08fb CHAR(20);
  p_EntityKeyField_01eb08fb VARCHAR(255);
  p_RelatedEntityJoinField_01eb08fb VARCHAR(255);
  p_JoinView_01eb08fb VARCHAR(255);
  p_JoinEntityJoinField_01eb08fb VARCHAR(255);
  p_JoinEntityInverseJoinField_01eb08fb VARCHAR(255);
  p_DisplayInForm_01eb08fb BOOLEAN;
  p_DisplayLocation_01eb08fb VARCHAR(50);
  p_DisplayName_01eb08fb VARCHAR(255);
  p_DisplayIconType_01eb08fb VARCHAR(50);
  p_DisplayIcon_01eb08fb VARCHAR(255);
  p_DisplayComponentID_01eb08fb UUID;
  p_DisplayComponentConfiguration_01eb08fb TEXT;
  p_AutoUpdateFromSchema_01eb08fb BOOLEAN;
  p_AdditionalFieldsToInclude_01eb08fb TEXT;
  p_AutoUpdateAdditionalFieldsToInclude_01eb08fb BOOLEAN;
  p_RelatedRecordCollection_01eb08fb TEXT;
  p_Configuration_01eb08fb TEXT;
  p_ID_01eb08fb UUID;
BEGIN
  p_EntityID_01eb08fb := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_Sequence_01eb08fb := 3;
  p_RelatedEntityID_01eb08fb := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_BundleInAPI_01eb08fb := TRUE;
  p_IncludeInParentAllQuery_01eb08fb := FALSE;
  p_Type_01eb08fb := 'One To Many';
  p_RelatedEntityJoinField_01eb08fb := 'ParentContractID';
  p_DisplayInForm_01eb08fb := TRUE;
  p_DisplayLocation_01eb08fb := 'After Field Tabs';
  p_DisplayName_01eb08fb := 'Lineage';
  p_DisplayIconType_01eb08fb := 'Related Entity Icon';
  p_AutoUpdateFromSchema_01eb08fb := TRUE;
  p_AutoUpdateAdditionalFieldsToInclude_01eb08fb := TRUE;
  p_Configuration_01eb08fb := '{
  "UI": {
    "inclusion": "Primary"
  }
}';
  p_ID_01eb08fb := 'E45A646D-9A56-45E8-9C64-5583E38654C2';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityRelationship'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityRelationship"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_01eb08fb,
    'Sequence', p_Sequence_01eb08fb,
    'RelatedEntityID', p_RelatedEntityID_01eb08fb,
    'BundleInAPI', p_BundleInAPI_01eb08fb,
    'IncludeInParentAllQuery', p_IncludeInParentAllQuery_01eb08fb,
    'Type', p_Type_01eb08fb,
    'EntityKeyField', p_EntityKeyField_01eb08fb,
    'RelatedEntityJoinField', p_RelatedEntityJoinField_01eb08fb,
    'JoinView', p_JoinView_01eb08fb,
    'JoinEntityJoinField', p_JoinEntityJoinField_01eb08fb,
    'JoinEntityInverseJoinField', p_JoinEntityInverseJoinField_01eb08fb,
    'DisplayInForm', p_DisplayInForm_01eb08fb,
    'DisplayLocation', p_DisplayLocation_01eb08fb,
    'DisplayName', p_DisplayName_01eb08fb,
    'DisplayIconType', p_DisplayIconType_01eb08fb,
    'DisplayIcon', p_DisplayIcon_01eb08fb,
    'DisplayComponentID', p_DisplayComponentID_01eb08fb,
    'DisplayComponentConfiguration', p_DisplayComponentConfiguration_01eb08fb,
    'AutoUpdateFromSchema', p_AutoUpdateFromSchema_01eb08fb,
    'AdditionalFieldsToInclude', p_AdditionalFieldsToInclude_01eb08fb,
    'AutoUpdateAdditionalFieldsToInclude', p_AutoUpdateAdditionalFieldsToInclude_01eb08fb,
    'RelatedRecordCollection', p_RelatedRecordCollection_01eb08fb,
    'Configuration', p_Configuration_01eb08fb,
    'ID', p_ID_01eb08fb
  ));
  ELSE
    PERFORM __mj."spUpdateEntityRelationship"(p_EntityID := p_EntityID_01eb08fb, p_Sequence := p_Sequence_01eb08fb, p_RelatedEntityID := p_RelatedEntityID_01eb08fb, p_BundleInAPI := p_BundleInAPI_01eb08fb, p_IncludeInParentAllQuery := p_IncludeInParentAllQuery_01eb08fb, p_Type := p_Type_01eb08fb, p_EntityKeyField := p_EntityKeyField_01eb08fb, p_EntityKeyField_Clear := TRUE, p_RelatedEntityJoinField := p_RelatedEntityJoinField_01eb08fb, p_JoinView := p_JoinView_01eb08fb, p_JoinView_Clear := TRUE, p_JoinEntityJoinField := p_JoinEntityJoinField_01eb08fb, p_JoinEntityJoinField_Clear := TRUE, p_JoinEntityInverseJoinField := p_JoinEntityInverseJoinField_01eb08fb, p_JoinEntityInverseJoinField_Clear := TRUE, p_DisplayInForm := p_DisplayInForm_01eb08fb, p_DisplayLocation := p_DisplayLocation_01eb08fb, p_DisplayName := p_DisplayName_01eb08fb, p_DisplayIconType := p_DisplayIconType_01eb08fb, p_DisplayIcon := p_DisplayIcon_01eb08fb, p_DisplayIcon_Clear := TRUE, p_DisplayComponentID := p_DisplayComponentID_01eb08fb, p_DisplayComponentID_Clear := TRUE, p_DisplayComponentConfiguration := p_DisplayComponentConfiguration_01eb08fb, p_DisplayComponentConfiguration_Clear := TRUE, p_AutoUpdateFromSchema := p_AutoUpdateFromSchema_01eb08fb, p_AdditionalFieldsToInclude := p_AdditionalFieldsToInclude_01eb08fb, p_AdditionalFieldsToInclude_Clear := TRUE, p_AutoUpdateAdditionalFieldsToInclude := p_AutoUpdateAdditionalFieldsToInclude_01eb08fb, p_RelatedRecordCollection := p_RelatedRecordCollection_01eb08fb, p_RelatedRecordCollection_Clear := TRUE, p_Configuration := p_Configuration_01eb08fb, p_ID := p_ID_01eb08fb);
  END IF;
END $mj$;

-- Save MJ: Applications (core SP call only)
DO $mj$
DECLARE
  p_ID_61e7f6e6 UUID;
  p_Name_61e7f6e6 VARCHAR(100);
  p_Description_61e7f6e6 TEXT;
  p_Icon_61e7f6e6 VARCHAR(500);
  p_DefaultForNewUser_61e7f6e6 BOOLEAN;
  p_SchemaAutoAddNewEntities_61e7f6e6 TEXT;
  p_Color_61e7f6e6 VARCHAR(20);
  p_DefaultNavItems_61e7f6e6 TEXT;
  p_ClassName_61e7f6e6 VARCHAR(255);
  p_DefaultSequence_61e7f6e6 INTEGER;
  p_Status_61e7f6e6 VARCHAR(20);
  p_NavigationStyle_61e7f6e6 VARCHAR(20);
  p_TopNavLocation_61e7f6e6 VARCHAR(30);
  p_HideNavBarIconWhenActive_61e7f6e6 BOOLEAN;
  p_Path_61e7f6e6 VARCHAR(100);
  p_AutoUpdatePath_61e7f6e6 BOOLEAN;
  p_AgentSettings_61e7f6e6 TEXT;
BEGIN
  p_ID_61e7f6e6 := '7C1D2E3F-4A5B-4C6D-8E9F-0A1B2C3D4E5F';
  p_Name_61e7f6e6 := 'Contracts';
  p_Description_61e7f6e6 := 'The record of what we agreed: every agreement, the standard terms it incorporates, the provisions negotiated away from those terms, and the executed paper. Contracts tracks obligations and documents; orders bills, and sales sells.';
  p_Icon_61e7f6e6 := 'fa-solid fa-file-signature';
  p_DefaultForNewUser_61e7f6e6 := TRUE;
  p_DefaultNavItems_61e7f6e6 := '[
  {
    "Label": "Contracts",
    "Icon": "fa-solid fa-file-signature",
    "ResourceType": "Custom",
    "DriverClass": "ContractsSectionResource",
    "isDefault": true
  },
  {
    "Label": "Templates",
    "Icon": "fa-solid fa-file-lines",
    "ResourceType": "Custom",
    "DriverClass": "ContractsTemplatesSectionResource",
    "isDefault": false
  },
  {
    "Label": "Configuration",
    "Icon": "fa-solid fa-sliders",
    "ResourceType": "Custom",
    "DriverClass": "ContractsConfigurationSectionResource",
    "isDefault": false
  }
]';
  p_DefaultSequence_61e7f6e6 := 100;
  p_Status_61e7f6e6 := 'Active';
  p_NavigationStyle_61e7f6e6 := 'App Switcher';
  p_HideNavBarIconWhenActive_61e7f6e6 := FALSE;
  p_Path_61e7f6e6 := 'contracts';
  p_AutoUpdatePath_61e7f6e6 := TRUE;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spCreateApplication'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spCreateApplication"(p_data := jsonb_build_object(
    'ID', p_ID_61e7f6e6,
    'Name', p_Name_61e7f6e6,
    'Description', p_Description_61e7f6e6,
    'Icon', p_Icon_61e7f6e6,
    'DefaultForNewUser', p_DefaultForNewUser_61e7f6e6,
    'SchemaAutoAddNewEntities', p_SchemaAutoAddNewEntities_61e7f6e6,
    'Color', p_Color_61e7f6e6,
    'DefaultNavItems', p_DefaultNavItems_61e7f6e6,
    'ClassName', p_ClassName_61e7f6e6,
    'DefaultSequence', p_DefaultSequence_61e7f6e6,
    'Status', p_Status_61e7f6e6,
    'NavigationStyle', p_NavigationStyle_61e7f6e6,
    'TopNavLocation', p_TopNavLocation_61e7f6e6,
    'HideNavBarIconWhenActive', p_HideNavBarIconWhenActive_61e7f6e6,
    'Path', p_Path_61e7f6e6,
    'AutoUpdatePath', p_AutoUpdatePath_61e7f6e6,
    'AgentSettings', p_AgentSettings_61e7f6e6
  ));
  ELSE
    PERFORM __mj."spCreateApplication"(p_ID := p_ID_61e7f6e6, p_Name := p_Name_61e7f6e6, p_Description := p_Description_61e7f6e6, p_Icon := p_Icon_61e7f6e6, p_DefaultForNewUser := p_DefaultForNewUser_61e7f6e6, p_SchemaAutoAddNewEntities := p_SchemaAutoAddNewEntities_61e7f6e6, p_SchemaAutoAddNewEntities_Clear := TRUE, p_Color := p_Color_61e7f6e6, p_Color_Clear := TRUE, p_DefaultNavItems := p_DefaultNavItems_61e7f6e6, p_ClassName := p_ClassName_61e7f6e6, p_ClassName_Clear := TRUE, p_DefaultSequence := p_DefaultSequence_61e7f6e6, p_Status := p_Status_61e7f6e6, p_NavigationStyle := p_NavigationStyle_61e7f6e6, p_TopNavLocation := p_TopNavLocation_61e7f6e6, p_TopNavLocation_Clear := TRUE, p_HideNavBarIconWhenActive := p_HideNavBarIconWhenActive_61e7f6e6, p_Path := p_Path_61e7f6e6, p_AutoUpdatePath := p_AutoUpdatePath_61e7f6e6, p_AgentSettings := p_AgentSettings_61e7f6e6, p_AgentSettings_Clear := TRUE);
  END IF;
END $mj$;


-- ===================== Other =====================

-- End of SQL Logging Session
-- Session ID: d1c3204d-5a28-4007-96df-2cdc3d478801
-- Completed: 2026-08-24T02:34:23.408Z
-- Duration: 16608ms
-- Total Statements: 27


-- ============================================================================
-- V202608300100__v0.1.x__Terminated_date_is_inclusive
-- ============================================================================
-- From V202608300100: a TerminatedDate of today reads Terminated (end-of-day is in force).
-- vwContracts: the application-owned wrapper over CodeGen's vwContractsGenerated.
-- Replaced through CodeGen's dependency-safe block: the CRUD functions return this view's row type.
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
AS
SELECT
    g.*,
    CASE
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Active'
        WHEN g."ExecutedDate" IS NOT NULL THEN 'Executed'
        ELSE 'Draft'
    END AS "State",
    CASE
        WHEN ct."RequiresExecutedDocument" = TRUE
         AND NOT EXISTS (
                SELECT 1
                  FROM __mj."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM __mj."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts')
                   AND lower(fl."RecordID") = g."ID"::text
             )
        THEN TRUE ELSE FALSE
    END AS "IsAwaitingDocument",
    CASE WHEN g."EndDate" IS NULL THEN NULL
         ELSE (g."EndDate" - (NOW() AT TIME ZONE 'UTC')::date) END AS "DaysToEnd",
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE (g."EndDate" - g."RenewalNoticeDays") END AS "RenewalNoticeDeadline",
    CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND (NOW() AT TIME ZONE 'UTC')::date >= (g."EndDate" - g."CancellationWindowDays")
         AND (NOW() AT TIME ZONE 'UTC')::date <= g."EndDate"
        THEN TRUE ELSE FALSE
    END AS "IsInCancellationWindow"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID"$vsql$;
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";


-- ============================================================================
-- V202609010100__v0.2.x__IsAwaitingDocument_executed_agreement
-- ============================================================================
-- From V202609010100: the "Executed Agreement" file category, and IsAwaitingDocument
-- counting only a file in that category as the executed paper.
INSERT INTO __mj."FileCategory" ("ID", "Name", "Description")
SELECT gen_random_uuid(), 'Executed Agreement',
       'The signed contract itself, as opposed to an exhibit, a draft or a countersigned amendment. Contracts'' IsAwaitingDocument reports a contract as awaiting paper until a file in this category is linked to it.'
 WHERE NOT EXISTS (SELECT 1 FROM __mj."FileCategory" WHERE "Name" = 'Executed Agreement');

-- vwContracts: the application-owned wrapper over CodeGen's vwContractsGenerated.
-- Replaced through CodeGen's dependency-safe block: the CRUD functions return this view's row type.
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
AS
SELECT
    g.*,
    CASE
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Active'
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
         ELSE (g."EndDate" - (NOW() AT TIME ZONE 'UTC')::date) END AS "DaysToEnd",
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE (g."EndDate" - g."RenewalNoticeDays") END AS "RenewalNoticeDeadline",
    CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND (NOW() AT TIME ZONE 'UTC')::date >= (g."EndDate" - g."CancellationWindowDays")
         AND (NOW() AT TIME ZONE 'UTC')::date <= g."EndDate"
        THEN TRUE ELSE FALSE
    END AS "IsInCancellationWindow"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID"$vsql$;
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";


-- ============================================================================
-- V202609140100__v0.2.x__Contract_type_renewal_defaults
-- ============================================================================
-- ============================================================================
-- MemberJunction PostgreSQL Migration — V202609140100__v0.2.x__Contract_type_renewal_defaults.sql
-- Split-and-regenerate with INLINE NATIVE CodeGen baking: hand-written DDL transpiled
-- (AST dialect), metadata DML inline, and CodeGen objects (views/sprocs/triggers/grants)
-- baked natively from `mj codegen`. Applies standalone via `mj migrate` — no deploy codegen.
-- ============================================================================


ALTER TABLE __mj_bizappscontracts."ContractType"
  ADD COLUMN "DefaultAutoRenew" BOOLEAN NULL,
  ADD COLUMN "DefaultRenewalNoticeDays" INT NULL,
  ADD COLUMN "DefaultCancellationWindowDays" INT NULL,
  ADD COLUMN "DefaultAnnualIncreasePercent" DECIMAL(7, 4) NULL,
  ADD CONSTRAINT "CK_ContractType_DefaultRenewalNoticeDays" CHECK ("DefaultRenewalNoticeDays" IS NULL OR "DefaultRenewalNoticeDays" >= 0),
  ADD CONSTRAINT "CK_ContractType_DefaultCancellationWindow" CHECK ("DefaultCancellationWindowDays" IS NULL OR "DefaultCancellationWindowDays" >= 0),
  ADD CONSTRAINT "CK_ContractType_DefaultAnnualIncrease" CHECK ("DefaultAnnualIncreasePercent" IS NULL OR "DefaultAnnualIncreasePercent" >= 0)
 /* ============================================================================= */ /* V202609140100 — renewal-obligation DEFAULTS on ContractType. */ /* ============================================================================= */ /* Golive #217 (story C-US1, #99). C-US1 says the renewal-obligation fields on a */ /* new contract are seeded from the selected Contract Type, and re-seeded when the */ /* type is changed before saving. Nothing implemented it: ContractType carried no */ /* default columns at all, so finance typed all four fields by hand on every */ /* contract, including the ones where the type already determines the answer. */ /* These four columns are a STARTING POINT, NOT A RULE, and the distinction is the */ /* whole design. Nothing reads them at save time; no validation consults them; a */ /* contract may state anything the paper states. They are copied into the contract */ /* ONCE, at the moment a type is picked on an UNSAVED record, and from then on the */ /* contract's own values are the only ones that matter. That is what separates */ /* them from the type's three existing RULE columns (MustBeRoot, MustBeChild, */ /* TemplateRequired), which ContractEntityServer enforces on every save. */ /* WHY THIS IS NOT A REVERSAL OF THE v2 REBUILD. v1 seeded six types with fourteen */ /* columns of billing defaults — term months, billing frequency, escalation */ /* percents, renewal mode, coterm — and the rebuild deleted all of it because v2 */ /* does not bill and does not renew on a schedule (see the note in */ /* metadata/contract-types/.contract-types.json). The deletion was about the */ /* system DECIDING things from a type. Pre-filling a form the user then edits */ /* decides nothing, and the four seeded types ship with these columns NULL, so an */ /* install that never touches the Configuration page behaves exactly as it does */ /* today. */ /* DefaultAutoRenew IS NULLABLE, unlike Contract.AutoRenew which it seeds. A bit */ /* has two values and the type needs three answers: renews, does not renew, and NO */ /* OPINION — leave whatever the contract already says. A NOT NULL default would */ /* have made every type assert something about auto-renewal whether or not anyone */ /* had considered it, and "0 because nobody set it" is indistinguishable from "0 */ /* because a Payment Link genuinely never renews". NULL means this column does not */ /* participate in seeding; that is the state every existing row starts in. */ /* The three numeric defaults mirror their Contract counterparts exactly — INT, */ /* DECIMAL(7,4), and the same >= 0 CHECKs — because a value that is legal on the */ /* type and illegal on the contract would seed a record that cannot be saved. */ /* ============================================================================= */ /* ------------------------------------------------------------------------- */ /* The columns, in ONE statement with their constraints. */ /* No IF guards anywhere in this file, and that is the convention rather than */ /* an oversight: migrations always run in order and exactly once, so a script */ /* never has to defend itself against a database that already has its changes. */ /* Guards are noise, and they make the PostgreSQL conversion harder. */ /* The three numeric floors mirror CK_Contract_* on the columns these seed. A */ /* negative notice period is not a shorter one, it is a data entry error, and */ /* catching it on the TYPE means catching it once rather than on every contract */ /* the type seeds. */ /* ------------------------------------------------------------------------- */;

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."DefaultAutoRenew" IS 'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."DefaultRenewalNoticeDays" IS 'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."DefaultCancellationWindowDays" IS 'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.';

COMMENT ON COLUMN __mj_bizappscontracts."ContractType"."DefaultAnnualIncreasePercent" IS 'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.';

/* ============================================================================= */
/* CodeGen capture — everything below this line is GENERATED. Replace it wholesale */
/* on regeneration; see docs/database-migrations.md § the 50-blank-line rule. */
/* Captured from a FROM-ZERO replay: the whole contracts train applied to a clean */
/* database carrying MJ core + bizapps-common, then `mj sync push --dir metadata`, */
/* then `mj codegen` — in that order. The push has to land before CodeGen runs, */
/* or CodeGen reads settings that are not there yet and regenerates without them. */
/* Note what is NOT here, and why. CodeGen emits no `Update FieldCategory…` */
/* statements any more: the field-category setting lives in */
/* `metadata/entity-settings/` and was already in the database when this ran, so */
/* there was nothing for CodeGen to generate. An earlier draft of this migration */
/* hand-wrote that setting as SQL, which is exactly what the metadata folder is */
/* for. The four fields' `Category` is metadata for the same reason and lives in */
/* `metadata/entity-fields/.default-contract-terms-category.json`; a host receives */
/* both through the release-time Metadata_Sync, not through this file. */
/* ============================================================================= */
/* SQL text to update existing entities from schema */
SELECT
  "__mj"."spUpdateExistingEntitiesFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');
/* SQL text to insert 4 new entity field(s) */;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '0e84b4a9-1d67-4563-a5a0-ef4f75c80694' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'DefaultAutoRenew')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('0e84b4a9-1d67-4563-a5a0-ef4f75c80694', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'DefaultAutoRenew', 'Default Auto Renew', 'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.', 'bit', 1, 1, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'e9a6cb34-2b1c-44a9-8260-d7e14c7b1f49' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'DefaultRenewalNoticeDays')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('e9a6cb34-2b1c-44a9-8260-d7e14c7b1f49', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'DefaultRenewalNoticeDays', 'Default Renewal Notice Days', 'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.', 'int', 4, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = '111cfb1b-1efb-4e60-a79d-41a391ef596a' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'DefaultCancellationWindowDays')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('111cfb1b-1efb-4e60-a79d-41a391ef596a', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'DefaultCancellationWindowDays', 'Default Cancellation Window Days', 'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.', 'int', 4, 10, 0, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM "__mj"."EntityField" WHERE "ID" = 'da53b111-bc39-49f6-bcfb-55380e260227' OR ("EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262' AND "Name" = 'DefaultAnnualIncreasePercent')) THEN
    INSERT INTO "__mj"."EntityField" ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale", "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed", "RelatedEntityID", "RelatedEntityFieldName", "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView", "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt") VALUES ('da53b111-bc39-49f6-bcfb-55380e260227', 'C8909A57-6DDB-4585-BE00-E707C5B4F262' /* Entity: MJ_BizApps_Contracts: Contract Types */, (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM "__mj"."EntityField" WHERE "EntityID" = 'C8909A57-6DDB-4585-BE00-E707C5B4F262'), 'DefaultAnnualIncreasePercent', 'Default Annual Increase Percent', 'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.', 'decimal', 5, 7, 4, TRUE, NULL, FALSE, TRUE, FALSE, FALSE, NULL, NULL, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW());
  END IF;
END $$;

/* SQL text to update existing entity fields from schema */
SELECT
  "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');
/* SQL text to set default column width where needed */
SELECT
  "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');
/* SQL text to sync schema info from database schemas */
SELECT
  "__mj"."spUpdateSchemaInfoFromDatabase"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

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
    p_defaultannualincreasepercent decimal(7, 4) DEFAULT NULL
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
                "DefaultAnnualIncreasePercent"
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
                CASE WHEN p_defaultannualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_defaultannualincreasepercent, NULL) END
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
    p_defaultannualincreasepercent decimal(7, 4) DEFAULT NULL
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
        "DefaultAnnualIncreasePercent" = CASE WHEN p_defaultannualincreasepercent_clear = true THEN NULL ELSE COALESCE(p_defaultannualincreasepercent, "DefaultAnnualIncreasePercent") END
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
    p_notes TEXT DEFAULT NULL
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
                "Notes"
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
                CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, NULL) END
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
    p_notes TEXT DEFAULT NULL
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
        "Notes" = CASE WHEN p_notes_clear = true THEN NULL ELSE COALESCE(p_notes, "Notes") END
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


-- ============================================================================
-- V202609202354__v0.3.0__Predictive_Contract_Renewal_Fields
-- ============================================================================
-- From V202609202354: materialized prediction write-back columns on Contract, their
-- EntityField rows (IDs as shipped on SQL Server), and the engineered features the
-- vwContracts wrapper derives, registered as virtual fields.
ALTER TABLE __mj_bizappscontracts."Contract"
  ADD COLUMN "PredictedNonRenewalRisk" DECIMAL(5, 4) NULL,
  ADD COLUMN "PredictedRenewalRiskBand" VARCHAR(20) NULL,
  ADD COLUMN "PredictedRenewalScoredAt" TIMESTAMPTZ NULL,
  ADD CONSTRAINT "CK_Contract_PredictedRenewalRiskBand"
      CHECK ("PredictedRenewalRiskBand" IS NULL OR "PredictedRenewalRiskBand" IN ('Low', 'Medium', 'High', 'Critical'));

COMMENT ON COLUMN __mj_bizappscontracts."Contract"."PredictedNonRenewalRisk" IS 'Predicted probability (0.0000 to 1.0000) that this commercial agreement will fail to renew prior to the required notice deadline.';
COMMENT ON COLUMN __mj_bizappscontracts."Contract"."PredictedRenewalRiskBand" IS 'Derived operational risk band classifying renewal risk: Low (<20%), Medium (20-50%), High (50-80%), Critical (>=80%).';
COMMENT ON COLUMN __mj_bizappscontracts."Contract"."PredictedRenewalScoredAt" IS 'Timestamp of the most recent predictive model scoring execution for this contract.';

INSERT INTO __mj."EntityField"
    ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale",
     "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed",
     "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView",
     "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT '1de502c3-42f6-4246-b7a0-90f61c38d586', e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'PredictedNonRenewalRisk', 'Predicted Non Renewal Risk', 'Predicted probability (0.0000 to 1.0000) that this commercial agreement will fail to renew prior to the required notice deadline.', 'decimal', 5, 5, 4,
       TRUE, NULL, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW()
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts'
   AND NOT EXISTS (SELECT 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID" AND ef."Name" = 'PredictedNonRenewalRisk');

INSERT INTO __mj."EntityField"
    ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale",
     "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed",
     "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView",
     "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT 'e25c8e07-f5dc-4d15-9ef4-56f51111575e', e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'PredictedRenewalRiskBand', 'Predicted Renewal Risk Band', 'Derived operational risk band classifying renewal risk: Low (<20%), Medium (20-50%), High (50-80%), Critical (>=80%).', 'nvarchar', 40, 0, 0,
       TRUE, NULL, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW()
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts'
   AND NOT EXISTS (SELECT 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID" AND ef."Name" = 'PredictedRenewalRiskBand');

INSERT INTO __mj."EntityField"
    ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale",
     "AllowsNull", "DefaultValue", "AutoIncrement", "AllowUpdateAPI", "IsVirtual", "IsComputed",
     "IsNameField", "IncludeInUserSearchAPI", "IncludeRelatedEntityNameFieldInBaseView", "DefaultInView",
     "IsPrimaryKey", "IsUnique", "RelatedEntityDisplayType", "__mj_CreatedAt", "__mj_UpdatedAt")
SELECT 'e2e2a570-28ca-4b84-b2c7-aa09d546fd72', e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) + 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID"),
       'PredictedRenewalScoredAt', 'Predicted Renewal Scored At', 'Timestamp of the most recent predictive model scoring execution for this contract.', 'datetimeoffset', 10, 34, 7,
       TRUE, NULL, FALSE, TRUE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, 'Search', NOW(), NOW()
  FROM __mj."Entity" e
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts'
   AND NOT EXISTS (SELECT 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID" AND ef."Name" = 'PredictedRenewalScoredAt');

INSERT INTO __mj."EntityField"
    ("ID", "EntityID", "Sequence", "Name", "DisplayName", "Description", "Type", "Length", "Precision", "Scale",
     "AllowsNull", "DefaultInView", "IsVirtual", "AllowUpdateAPI", "Status")
SELECT gen_random_uuid(), e."ID",
       (SELECT COALESCE(MAX(ef."Sequence"), 0) FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID")
         + ROW_NUMBER() OVER (ORDER BY f.name),
       f.name, f.display_name, f.description, f.type, f.length, f.precision, f.scale,
       TRUE, FALSE, TRUE, FALSE, 'Active'
  FROM __mj."Entity" e
 CROSS JOIN (VALUES
    ('NonRenewalOutcome', 'Non Renewal Outcome', 'int', 4, 10, 0, 'Binary outcome: 1 if contract reached conclusion without renewal (terminated or expired), 0 if superseded/renewed, NULL if active/in-flight.'),
    ('TermLengthDays', 'Term Length Days', 'int', 4, 10, 0, 'Duration of contract term in days between effective date and end date.'),
    ('DaysUntilNoticeDeadline', 'Days Until Notice Deadline', 'int', 4, 10, 0, 'Days remaining until the required non-renewal notice deadline.'),
    ('HasModificationsFlag', 'Has Modifications Flag', 'int', 4, 10, 0, 'Flag indicating whether the agreement contains custom modifications or clause deviations.'),
    ('AutoRenewFlag', 'Auto Renew Flag', 'int', 4, 10, 0, 'Flag indicating whether auto-renewal is enabled.'),
    ('HasParentContract', 'Has Parent Contract', 'int', 4, 10, 0, 'Flag indicating whether this agreement is an amendment or child contract.'),
    ('HasCancellationWindow', 'Has Cancellation Window', 'int', 4, 10, 0, 'Flag indicating whether a cancellation window is configured.'),
    ('HasAnnualIncrease', 'Has Annual Increase', 'int', 4, 10, 0, 'Flag indicating whether annual percentage increases apply.')
 ) AS f(name, display_name, type, length, precision, scale, description)
 WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts'
   AND NOT EXISTS (SELECT 1 FROM __mj."EntityField" ef WHERE ef."EntityID" = e."ID" AND ef."Name" = f.name);

-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
-- Generated at: 2026-10-13T03:21:01.695Z
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
-- Generated at: 2026-10-13T03:21:01.695Z
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
-- Generated at: 2026-10-13T03:21:01.706Z
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
-- Generated at: 2026-10-13T03:21:01.706Z
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
-- Generated at: 2026-10-13T03:21:01.708Z
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
-- Generated at: 2026-10-13T03:21:01.708Z
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


-- ============================================================
-- PostgreSQL Generated SQL for Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
-- Generated at: 2026-10-13T03:21:01.706Z
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


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spCreateContract" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spUpdateContract" TO "cdp_Integration";


GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Developer";
GRANT EXECUTE ON FUNCTION "__mj_bizappscontracts"."spDeleteContract" TO "cdp_Integration";


-- vwContracts: the application-owned wrapper over CodeGen's vwContractsGenerated.
-- Replaced through CodeGen's dependency-safe block: the CRUD functions return this view's row type.
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
AS
SELECT
    g.*,
    CASE
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Terminated'
        WHEN g."SupersededByContractID" IS NOT NULL THEN 'Superseded'
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 'Expired'
        WHEN g."EffectiveDate" IS NOT NULL AND g."EffectiveDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 'Active'
        WHEN g."ExecutedDate" IS NOT NULL THEN 'Executed'
        ELSE 'Draft'
    END AS "State",
    CASE
        WHEN ct."RequiresExecutedDocument" = TRUE
         AND NOT EXISTS (
                SELECT 1
                  FROM __mj."FileEntityRecordLink" fl
                 WHERE fl."EntityID" = (SELECT e."ID" FROM __mj."Entity" e
                                         WHERE e."Name" = 'MJ_BizApps_Contracts: Contracts')
                   AND lower(fl."RecordID") = g."ID"::text
             )
        THEN TRUE ELSE FALSE
    END AS "IsAwaitingDocument",
    CASE WHEN g."EndDate" IS NULL THEN NULL
         ELSE (g."EndDate" - (NOW() AT TIME ZONE 'UTC')::date) END AS "DaysToEnd",
    CASE WHEN g."EndDate" IS NULL OR g."RenewalNoticeDays" IS NULL THEN NULL
         ELSE (g."EndDate" - g."RenewalNoticeDays") END AS "RenewalNoticeDeadline",
    CASE
        WHEN g."EndDate" IS NOT NULL AND g."CancellationWindowDays" IS NOT NULL
         AND (NOW() AT TIME ZONE 'UTC')::date >= (g."EndDate" - g."CancellationWindowDays")
         AND (NOW() AT TIME ZONE 'UTC')::date <= g."EndDate"
        THEN TRUE ELSE FALSE
    END AS "IsInCancellationWindow",
    CASE
        WHEN g."SupersededByContractID" IS NOT NULL THEN 0
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= (NOW() AT TIME ZONE 'UTC')::date THEN 1
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < (NOW() AT TIME ZONE 'UTC')::date THEN 1
        ELSE NULL
    END AS "NonRenewalOutcome",
    CASE WHEN g."EffectiveDate" IS NOT NULL AND g."EndDate" IS NOT NULL THEN (g."EndDate" - g."EffectiveDate") ELSE NULL END AS "TermLengthDays",
    CASE WHEN g."EndDate" IS NOT NULL AND g."RenewalNoticeDays" IS NOT NULL THEN ((g."EndDate" - g."RenewalNoticeDays") - (NOW() AT TIME ZONE 'UTC')::date) ELSE NULL END AS "DaysUntilNoticeDeadline",
    CASE WHEN g."HasModifications" = TRUE THEN 1 ELSE 0 END AS "HasModificationsFlag",
    CASE WHEN g."AutoRenew" = TRUE THEN 1 ELSE 0 END AS "AutoRenewFlag",
    CASE WHEN g."ParentContractID" IS NOT NULL THEN 1 ELSE 0 END AS "HasParentContract",
    CASE WHEN g."CancellationWindowDays" > 0 THEN 1 ELSE 0 END AS "HasCancellationWindow",
    CASE WHEN g."AnnualIncreasePercent" > 0 THEN 1 ELSE 0 END AS "HasAnnualIncrease"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID"$vsql$;
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";


-- ============================================================================
-- V202609211200__v0.7.x__vwContracts_business_today
-- ============================================================================
-- From V202609211200: vwContracts derives 'today' from bizapps-common's fnBusinessToday() (the business time zone), not UTC.
-- vwContracts: the application-owned wrapper over CodeGen's vwContractsGenerated.
-- Replaced through CodeGen's dependency-safe block: the CRUD functions return this view's row type.
DO $vw_regen$
DECLARE
  vsql CONSTANT TEXT := $vsql$CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
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
    CASE
        WHEN g."SupersededByContractID" IS NOT NULL THEN 0
        WHEN g."TerminatedDate" IS NOT NULL AND g."TerminatedDate" <= bt."Today" THEN 1
        WHEN g."EndDate" IS NOT NULL AND g."EndDate" < bt."Today" THEN 1
        ELSE NULL
    END AS "NonRenewalOutcome",
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
    g."ContractTypeID" = ct."ID"$vsql$;
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
    AND tc.relname = 'vwContracts'
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
    AND tc.relname = 'vwContracts'
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
        AND tc.relname = 'vwContracts'
        AND tc.relkind IN ('v', 'm')
  );

  DROP VIEW IF EXISTS "__mj_bizappscontracts"."vwContracts" CASCADE;
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

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";
