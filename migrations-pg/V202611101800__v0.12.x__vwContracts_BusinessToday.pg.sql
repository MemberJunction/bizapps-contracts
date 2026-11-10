-- =============================================================================
-- PostgreSQL counterpart of V202611101800__v0.12.x__vwContracts_BusinessToday.sql
-- vwContracts publishes the business day it computes against
-- =============================================================================
-- Same change as the T-SQL file; see its header for why. vwContracts gains one
-- column, "BusinessToday" (bt."Today"), appended last.
--
-- HOW IT WAS MADE.
--   * Hand-written DDL: vwContracts is V202611031700's PostgreSQL definition
--     with the column added. CREATE OR REPLACE suffices because the column goes
--     last and no existing column changes; spCreateContract and spUpdateContract
--     return SETOF the view's row type and SELECT * from it, so they pick the
--     column up without being recreated.
--   * CodeGen-captured metadata: the T-SQL capture's EntityField insert and
--     category for BusinessToday, converted with `mj sql-convert --from tsql
--     --to postgres` (MJ CLI 6.2.1), and the four schema-refresh calls in the
--     PostgreSQL form the earlier files use. The T-SQL capture's view, procedure
--     and permission objects are not repeated: PostgreSQL's CodeGen objects for
--     Contract do not change with a column on the outer view.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS __mj_bizappscontracts;
SET search_path TO __mj_bizappscontracts, public;
SET standard_conforming_strings = on;

-- ===================== Hand-written DDL =====================

CREATE OR REPLACE VIEW __mj_bizappscontracts."vwContracts"
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
    CASE WHEN g."AnnualIncreasePercent" > 0 THEN 1 ELSE 0 END AS "HasAnnualIncrease",
    bt."Today" AS "BusinessToday"
FROM
    __mj_bizappscontracts."vwContractsGenerated" g
CROSS JOIN
    __mj_bizappscommon."fnBusinessToday"() AS bt
LEFT OUTER JOIN
    __mj_bizappscontracts."ContractType" ct
  ON
    g."ContractTypeID" = ct."ID";

GRANT SELECT ON __mj_bizappscontracts."vwContracts" TO "cdp_UI", "cdp_Developer", "cdp_Integration";

-- ===================== CodeGen-captured metadata =====================

/* SQL text to update existing entities from schema */
SELECT "__mj"."spUpdateExistingEntitiesFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to insert 1 new entity field(s) */
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM __mj."EntityField" WHERE "ID" = 'f51dbfe9-1a43-472d-8964-c40f1650e104' OR ("EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2' AND "Name" = 'BusinessToday')
    ) THEN
        INSERT INTO __mj."EntityField"
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
        'f51dbfe9-1a43-472d-8964-c40f1650e104',
        '5DEB0B11-ED6C-48B3-9200-F4441396C5E2', -- "Entity": "MJ_BizApps_Contracts": "Contracts"
        (SELECT COALESCE(MAX("Sequence"), 0) + 1 FROM __mj."EntityField" WHERE "EntityID" = '5DEB0B11-ED6C-48B3-9200-F4441396C5E2'),
        'BusinessToday',
        'Business Today',
        NULL,
        'date',
        3,
        10,
        0,
        TRUE,
        NULL,
        FALSE,
        FALSE,
        TRUE,
        FALSE,
        NULL,
        NULL,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        FALSE,
        'Search',
        NOW(),
        NOW()
        );
    END IF;
END $$;

/* SQL text to update existing entity fields from schema */
SELECT "__mj"."spUpdateExistingEntityFieldsFromSchema"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to set default column width where needed */
SELECT "__mj"."spSetDefaultColumnWidthWhereNeeded"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

/* SQL text to sync schema info from database schemas */
SELECT "__mj"."spUpdateSchemaInfoFromDatabase"('sys,staging,dbo,__mj,__mj_bizappscommon,__mj_bizappstasks');

-- UPDATE Entity Field Category Info MJ_BizApps_Contracts: Contracts.BusinessToday
UPDATE __mj."EntityField"
SET
   "Category" = 'Dates and Terms',
   "GeneratedFormSection" = 'Category'
WHERE
   "ID" = 'F51DBFE9-1A43-472D-8964-C40F1650E104';
