-- =============================================================================================
-- PostgreSQL counterpart of V202610092210__v0.8.x__Metadata_Sync.sql -- BizApps Contracts v0.8.x
-- Metadata_Sync
-- =============================================================================================
-- Same 34 records, same values, same order as the T-SQL file; see its header for what ships and
-- why (3 created, 27 updated; record-processes and the ML folders left out).
--
-- HOW IT WAS MADE
--   * `mj sql-convert --from tsql --to postgres` (MJ CLI 6.1.6) on the T-SQL file, with
--     `${mjSchema}` written as `__mj` first, because the converter skips every batch whose
--     procedure call names the schema by placeholder. Each record is a DO block that calls the
--     core procedure in whichever signature the host has (jsonb or named parameters).
--   * The converter keeps only the string assignments of a block and drops the BIT and number
--     ones, and it rewrites T-SQL inside string literals. So every value here is taken verbatim
--     from the T-SQL SET statements instead: strings unchanged, BIT 1/0 as TRUE/FALSE.
--   * The guards and the five virtual-field lookups are written by hand from the T-SQL ones:
--     IF NOT EXISTS (...) EXEC ... becomes IF NOT EXISTS (...) THEN <call> END IF, and
--     SELECT @ID = [ID] FROM ... becomes SELECT "ID" INTO ... FROM ....
--   * Placeholders inside string values (`${mjSchema}` in one field description,
--     `${flyway:defaultSchema}` in the stored query's SQL) are kept, as in the T-SQL file.
--     Outside strings the core schema is written `__mj`, as in this app's PostgreSQL baseline.
-- =============================================================================================

SET standard_conforming_strings = on;

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_b31387f095b6 UUID;
  p_Name_b31387f095b6 VARCHAR(255);
  p_NameSuffix_b31387f095b6 VARCHAR(255);
  p_Description_b31387f095b6 TEXT;
  p_AutoUpdateDescription_b31387f095b6 BOOLEAN;
  p_BaseView_b31387f095b6 VARCHAR(255);
  p_BaseViewGenerated_b31387f095b6 BOOLEAN;
  p_VirtualEntity_b31387f095b6 BOOLEAN;
  p_TrackRecordChanges_b31387f095b6 BOOLEAN;
  p_AuditRecordAccess_b31387f095b6 BOOLEAN;
  p_AuditViewRuns_b31387f095b6 BOOLEAN;
  p_IncludeInAPI_b31387f095b6 BOOLEAN;
  p_AllowAllRowsAPI_b31387f095b6 BOOLEAN;
  p_AllowUpdateAPI_b31387f095b6 BOOLEAN;
  p_AllowCreateAPI_b31387f095b6 BOOLEAN;
  p_AllowDeleteAPI_b31387f095b6 BOOLEAN;
  p_CustomResolverAPI_b31387f095b6 BOOLEAN;
  p_AllowUserSearchAPI_b31387f095b6 BOOLEAN;
  p_FullTextSearchEnabled_b31387f095b6 BOOLEAN;
  p_FullTextCatalog_b31387f095b6 VARCHAR(255);
  p_FullTextCatalogGenerated_b31387f095b6 BOOLEAN;
  p_FullTextIndex_b31387f095b6 VARCHAR(255);
  p_FullTextIndexGenerated_b31387f095b6 BOOLEAN;
  p_FullTextSearchFunction_b31387f095b6 VARCHAR(255);
  p_FullTextSearchFunctionGenerated_b31387f095b6 BOOLEAN;
  p_UserViewMaxRows_b31387f095b6 INTEGER;
  p_spCreate_b31387f095b6 VARCHAR(255);
  p_spUpdate_b31387f095b6 VARCHAR(255);
  p_spDelete_b31387f095b6 VARCHAR(255);
  p_spCreateGenerated_b31387f095b6 BOOLEAN;
  p_spUpdateGenerated_b31387f095b6 BOOLEAN;
  p_spDeleteGenerated_b31387f095b6 BOOLEAN;
  p_CascadeDeletes_b31387f095b6 BOOLEAN;
  p_DeleteType_b31387f095b6 VARCHAR(10);
  p_AllowRecordMerge_b31387f095b6 BOOLEAN;
  p_spMatch_b31387f095b6 VARCHAR(255);
  p_RelationshipDefaultDisplayType_b31387f095b6 VARCHAR(20);
  p_UserFormGenerated_b31387f095b6 BOOLEAN;
  p_EntityObjectSubclassName_b31387f095b6 VARCHAR(255);
  p_EntityObjectSubclassImport_b31387f095b6 VARCHAR(255);
  p_PreferredCommunicationField_b31387f095b6 VARCHAR(255);
  p_Icon_b31387f095b6 VARCHAR(500);
  p_ScopeDefault_b31387f095b6 VARCHAR(100);
  p_RowsToPackWithSchema_b31387f095b6 VARCHAR(20);
  p_RowsToPackSampleMethod_b31387f095b6 VARCHAR(20);
  p_RowsToPackSampleCount_b31387f095b6 INTEGER;
  p_RowsToPackSampleOrder_b31387f095b6 TEXT;
  p_AutoRowCountFrequency_b31387f095b6 INTEGER;
  p_RowCount_b31387f095b6 BIGINT;
  p_RowCountRunAt_b31387f095b6 TIMESTAMPTZ;
  p_Status_b31387f095b6 VARCHAR(25);
  p_DisplayName_b31387f095b6 VARCHAR(255);
  p_AllowMultipleSubtypes_b31387f095b6 BOOLEAN;
  p_AutoUpdateFullTextSearch_b31387f095b6 BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_b31387f095b6 BOOLEAN;
  p_TrustServerCacheCompletely_b31387f095b6 BOOLEAN;
  p_SupportsGeoCoding_b31387f095b6 BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_b31387f095b6 BOOLEAN;
  p_AllowCaching_b31387f095b6 BOOLEAN;
  p_DetectExternalChanges_b31387f095b6 BOOLEAN;
  p_ExternalDataSourceID_b31387f095b6 UUID;
  p_ExternalObjectName_b31387f095b6 VARCHAR(255);
  p_GeneratedBaseViewName_b31387f095b6 VARCHAR(255);
  p_AllowDirectSQLInsert_b31387f095b6 BOOLEAN;
  p_AllowDirectSQLUpdate_b31387f095b6 BOOLEAN;
  p_AllowDirectSQLDelete_b31387f095b6 BOOLEAN;
  p_Configuration_b31387f095b6 TEXT;
  p_SubtypeSelector_b31387f095b6 TEXT;
  p_EnableFieldLevelSecurity_b31387f095b6 BOOLEAN;
  p_ID_b31387f095b6 UUID;
BEGIN
  p_Name_b31387f095b6 := 'MJ_BizApps_Contracts: Contracts';
  p_Description_b31387f095b6 := 'The signed agreement — one row per piece of signed (or implied) paper, and the centre of the app. Carries NO hard reference to a Deal: sales creates contracts, so sales depends on this app and a reference upward would invert the dependency graph. The link is the typed polymorphic pair CreatingEntityID + CreatingRecordID.';
  p_AutoUpdateDescription_b31387f095b6 := TRUE;
  p_BaseView_b31387f095b6 := 'vwContracts';
  p_BaseViewGenerated_b31387f095b6 := FALSE;
  p_VirtualEntity_b31387f095b6 := FALSE;
  p_TrackRecordChanges_b31387f095b6 := TRUE;
  p_AuditRecordAccess_b31387f095b6 := FALSE;
  p_AuditViewRuns_b31387f095b6 := FALSE;
  p_IncludeInAPI_b31387f095b6 := TRUE;
  p_AllowAllRowsAPI_b31387f095b6 := FALSE;
  p_AllowUpdateAPI_b31387f095b6 := TRUE;
  p_AllowCreateAPI_b31387f095b6 := TRUE;
  p_AllowDeleteAPI_b31387f095b6 := TRUE;
  p_CustomResolverAPI_b31387f095b6 := FALSE;
  p_AllowUserSearchAPI_b31387f095b6 := TRUE;
  p_FullTextSearchEnabled_b31387f095b6 := FALSE;
  p_FullTextCatalogGenerated_b31387f095b6 := TRUE;
  p_FullTextIndexGenerated_b31387f095b6 := TRUE;
  p_FullTextSearchFunctionGenerated_b31387f095b6 := TRUE;
  p_UserViewMaxRows_b31387f095b6 := 1000;
  p_spCreateGenerated_b31387f095b6 := TRUE;
  p_spUpdateGenerated_b31387f095b6 := TRUE;
  p_spDeleteGenerated_b31387f095b6 := TRUE;
  p_CascadeDeletes_b31387f095b6 := FALSE;
  p_DeleteType_b31387f095b6 := 'Hard';
  p_AllowRecordMerge_b31387f095b6 := FALSE;
  p_RelationshipDefaultDisplayType_b31387f095b6 := 'Search';
  p_UserFormGenerated_b31387f095b6 := TRUE;
  p_Icon_b31387f095b6 := 'fa fa-file-contract';
  p_RowsToPackWithSchema_b31387f095b6 := 'None';
  p_RowsToPackSampleMethod_b31387f095b6 := 'random';
  p_RowsToPackSampleCount_b31387f095b6 := 0;
  p_Status_b31387f095b6 := 'Active';
  p_DisplayName_b31387f095b6 := 'Contracts';
  p_AllowMultipleSubtypes_b31387f095b6 := FALSE;
  p_AutoUpdateFullTextSearch_b31387f095b6 := TRUE;
  p_AutoUpdateAllowUserSearchAPI_b31387f095b6 := FALSE;
  p_TrustServerCacheCompletely_b31387f095b6 := TRUE;
  p_SupportsGeoCoding_b31387f095b6 := FALSE;
  p_AutoUpdateSupportsGeoCoding_b31387f095b6 := TRUE;
  p_AllowCaching_b31387f095b6 := FALSE;
  p_DetectExternalChanges_b31387f095b6 := FALSE;
  p_GeneratedBaseViewName_b31387f095b6 := 'vwContractsGenerated';
  p_AllowDirectSQLInsert_b31387f095b6 := FALSE;
  p_AllowDirectSQLUpdate_b31387f095b6 := FALSE;
  p_AllowDirectSQLDelete_b31387f095b6 := FALSE;
  p_Configuration_b31387f095b6 := '{
  "UI": {
    "Form": {
      "Layout": "left-nav",
      "RelatedRolePolicy": "smart",
      "PrimaryRelatedBudget": 6
    }
  }
}';
  p_EnableFieldLevelSecurity_b31387f095b6 := FALSE;
  p_ID_b31387f095b6 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntity'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_b31387f095b6,
    'Name', p_Name_b31387f095b6,
    'NameSuffix', p_NameSuffix_b31387f095b6,
    'Description', p_Description_b31387f095b6,
    'AutoUpdateDescription', p_AutoUpdateDescription_b31387f095b6,
    'BaseView', p_BaseView_b31387f095b6,
    'BaseViewGenerated', p_BaseViewGenerated_b31387f095b6,
    'VirtualEntity', p_VirtualEntity_b31387f095b6,
    'TrackRecordChanges', p_TrackRecordChanges_b31387f095b6,
    'AuditRecordAccess', p_AuditRecordAccess_b31387f095b6,
    'AuditViewRuns', p_AuditViewRuns_b31387f095b6,
    'IncludeInAPI', p_IncludeInAPI_b31387f095b6,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_b31387f095b6,
    'AllowUpdateAPI', p_AllowUpdateAPI_b31387f095b6,
    'AllowCreateAPI', p_AllowCreateAPI_b31387f095b6,
    'AllowDeleteAPI', p_AllowDeleteAPI_b31387f095b6,
    'CustomResolverAPI', p_CustomResolverAPI_b31387f095b6,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_b31387f095b6,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_b31387f095b6,
    'FullTextCatalog', p_FullTextCatalog_b31387f095b6,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_b31387f095b6,
    'FullTextIndex', p_FullTextIndex_b31387f095b6,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_b31387f095b6,
    'FullTextSearchFunction', p_FullTextSearchFunction_b31387f095b6,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_b31387f095b6,
    'UserViewMaxRows', p_UserViewMaxRows_b31387f095b6,
    'spCreate', p_spCreate_b31387f095b6,
    'spUpdate', p_spUpdate_b31387f095b6,
    'spDelete', p_spDelete_b31387f095b6,
    'spCreateGenerated', p_spCreateGenerated_b31387f095b6,
    'spUpdateGenerated', p_spUpdateGenerated_b31387f095b6,
    'spDeleteGenerated', p_spDeleteGenerated_b31387f095b6,
    'CascadeDeletes', p_CascadeDeletes_b31387f095b6,
    'DeleteType', p_DeleteType_b31387f095b6,
    'AllowRecordMerge', p_AllowRecordMerge_b31387f095b6,
    'spMatch', p_spMatch_b31387f095b6,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_b31387f095b6,
    'UserFormGenerated', p_UserFormGenerated_b31387f095b6,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_b31387f095b6,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_b31387f095b6,
    'PreferredCommunicationField', p_PreferredCommunicationField_b31387f095b6,
    'Icon', p_Icon_b31387f095b6,
    'ScopeDefault', p_ScopeDefault_b31387f095b6,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_b31387f095b6,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_b31387f095b6,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_b31387f095b6,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_b31387f095b6,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_b31387f095b6,
    'RowCount', p_RowCount_b31387f095b6,
    'RowCountRunAt', p_RowCountRunAt_b31387f095b6
  ) ||
  jsonb_build_object(
    'Status', p_Status_b31387f095b6,
    'DisplayName', p_DisplayName_b31387f095b6,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_b31387f095b6,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_b31387f095b6,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_b31387f095b6,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_b31387f095b6,
    'SupportsGeoCoding', p_SupportsGeoCoding_b31387f095b6,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_b31387f095b6,
    'AllowCaching', p_AllowCaching_b31387f095b6,
    'DetectExternalChanges', p_DetectExternalChanges_b31387f095b6,
    'ExternalDataSourceID', p_ExternalDataSourceID_b31387f095b6,
    'ExternalObjectName', p_ExternalObjectName_b31387f095b6,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_b31387f095b6,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_b31387f095b6,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_b31387f095b6,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_b31387f095b6,
    'Configuration', p_Configuration_b31387f095b6,
    'SubtypeSelector', p_SubtypeSelector_b31387f095b6,
    'EnableFieldLevelSecurity', p_EnableFieldLevelSecurity_b31387f095b6,
    'ID', p_ID_b31387f095b6
  ));
  ELSE
    PERFORM __mj."spUpdateEntity"(p_ParentID := p_ParentID_b31387f095b6, p_ParentID_Clear := TRUE, p_Name := p_Name_b31387f095b6, p_NameSuffix := p_NameSuffix_b31387f095b6, p_NameSuffix_Clear := TRUE, p_Description := p_Description_b31387f095b6, p_AutoUpdateDescription := p_AutoUpdateDescription_b31387f095b6, p_BaseView := p_BaseView_b31387f095b6, p_BaseViewGenerated := p_BaseViewGenerated_b31387f095b6, p_VirtualEntity := p_VirtualEntity_b31387f095b6, p_TrackRecordChanges := p_TrackRecordChanges_b31387f095b6, p_AuditRecordAccess := p_AuditRecordAccess_b31387f095b6, p_AuditViewRuns := p_AuditViewRuns_b31387f095b6, p_IncludeInAPI := p_IncludeInAPI_b31387f095b6, p_AllowAllRowsAPI := p_AllowAllRowsAPI_b31387f095b6, p_AllowUpdateAPI := p_AllowUpdateAPI_b31387f095b6, p_AllowCreateAPI := p_AllowCreateAPI_b31387f095b6, p_AllowDeleteAPI := p_AllowDeleteAPI_b31387f095b6, p_CustomResolverAPI := p_CustomResolverAPI_b31387f095b6, p_AllowUserSearchAPI := p_AllowUserSearchAPI_b31387f095b6, p_FullTextSearchEnabled := p_FullTextSearchEnabled_b31387f095b6, p_FullTextCatalog := p_FullTextCatalog_b31387f095b6, p_FullTextCatalog_Clear := TRUE, p_FullTextCatalogGenerated := p_FullTextCatalogGenerated_b31387f095b6, p_FullTextIndex := p_FullTextIndex_b31387f095b6, p_FullTextIndex_Clear := TRUE, p_FullTextIndexGenerated := p_FullTextIndexGenerated_b31387f095b6, p_FullTextSearchFunction := p_FullTextSearchFunction_b31387f095b6, p_FullTextSearchFunction_Clear := TRUE, p_FullTextSearchFunctionGenerated := p_FullTextSearchFunctionGenerated_b31387f095b6, p_UserViewMaxRows := p_UserViewMaxRows_b31387f095b6, p_spCreate := p_spCreate_b31387f095b6, p_spCreate_Clear := TRUE, p_spUpdate := p_spUpdate_b31387f095b6, p_spUpdate_Clear := TRUE, p_spDelete := p_spDelete_b31387f095b6, p_spDelete_Clear := TRUE, p_spCreateGenerated := p_spCreateGenerated_b31387f095b6, p_spUpdateGenerated := p_spUpdateGenerated_b31387f095b6, p_spDeleteGenerated := p_spDeleteGenerated_b31387f095b6, p_CascadeDeletes := p_CascadeDeletes_b31387f095b6, p_DeleteType := p_DeleteType_b31387f095b6, p_AllowRecordMerge := p_AllowRecordMerge_b31387f095b6, p_spMatch := p_spMatch_b31387f095b6, p_spMatch_Clear := TRUE, p_RelationshipDefaultDisplayType := p_RelationshipDefaultDisplayType_b31387f095b6, p_UserFormGenerated := p_UserFormGenerated_b31387f095b6, p_EntityObjectSubclassName := p_EntityObjectSubclassName_b31387f095b6, p_EntityObjectSubclassName_Clear := TRUE, p_EntityObjectSubclassImport := p_EntityObjectSubclassImport_b31387f095b6, p_EntityObjectSubclassImport_Clear := TRUE, p_PreferredCommunicationField := p_PreferredCommunicationField_b31387f095b6, p_PreferredCommunicationField_Clear := TRUE, p_Icon := p_Icon_b31387f095b6, p_ScopeDefault := p_ScopeDefault_b31387f095b6, p_ScopeDefault_Clear := TRUE, p_RowsToPackWithSchema := p_RowsToPackWithSchema_b31387f095b6, p_RowsToPackSampleMethod := p_RowsToPackSampleMethod_b31387f095b6, p_RowsToPackSampleCount := p_RowsToPackSampleCount_b31387f095b6, p_RowsToPackSampleOrder := p_RowsToPackSampleOrder_b31387f095b6, p_RowsToPackSampleOrder_Clear := TRUE, p_AutoRowCountFrequency := p_AutoRowCountFrequency_b31387f095b6, p_AutoRowCountFrequency_Clear := TRUE, p_RowCount := p_RowCount_b31387f095b6, p_RowCount_Clear := TRUE, p_RowCountRunAt := p_RowCountRunAt_b31387f095b6, p_RowCountRunAt_Clear := TRUE, p_Status := p_Status_b31387f095b6, p_DisplayName := p_DisplayName_b31387f095b6, p_AllowMultipleSubtypes := p_AllowMultipleSubtypes_b31387f095b6, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_b31387f095b6, p_AutoUpdateAllowUserSearchAPI := p_AutoUpdateAllowUserSearchAPI_b31387f095b6, p_TrustServerCacheCompletely := p_TrustServerCacheCompletely_b31387f095b6, p_SupportsGeoCoding := p_SupportsGeoCoding_b31387f095b6, p_AutoUpdateSupportsGeoCoding := p_AutoUpdateSupportsGeoCoding_b31387f095b6, p_AllowCaching := p_AllowCaching_b31387f095b6, p_DetectExternalChanges := p_DetectExternalChanges_b31387f095b6, p_ExternalDataSourceID := p_ExternalDataSourceID_b31387f095b6, p_ExternalDataSourceID_Clear := TRUE, p_ExternalObjectName := p_ExternalObjectName_b31387f095b6, p_ExternalObjectName_Clear := TRUE, p_GeneratedBaseViewName := p_GeneratedBaseViewName_b31387f095b6, p_AllowDirectSQLInsert := p_AllowDirectSQLInsert_b31387f095b6, p_AllowDirectSQLUpdate := p_AllowDirectSQLUpdate_b31387f095b6, p_AllowDirectSQLDelete := p_AllowDirectSQLDelete_b31387f095b6, p_Configuration := p_Configuration_b31387f095b6, p_SubtypeSelector := p_SubtypeSelector_b31387f095b6, p_SubtypeSelector_Clear := TRUE, p_EnableFieldLevelSecurity := p_EnableFieldLevelSecurity_b31387f095b6, p_ID := p_ID_b31387f095b6);
  END IF;
END $mj$;

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_17bcf0af9ffc UUID;
  p_Name_17bcf0af9ffc VARCHAR(255);
  p_NameSuffix_17bcf0af9ffc VARCHAR(255);
  p_Description_17bcf0af9ffc TEXT;
  p_AutoUpdateDescription_17bcf0af9ffc BOOLEAN;
  p_BaseView_17bcf0af9ffc VARCHAR(255);
  p_BaseViewGenerated_17bcf0af9ffc BOOLEAN;
  p_VirtualEntity_17bcf0af9ffc BOOLEAN;
  p_TrackRecordChanges_17bcf0af9ffc BOOLEAN;
  p_AuditRecordAccess_17bcf0af9ffc BOOLEAN;
  p_AuditViewRuns_17bcf0af9ffc BOOLEAN;
  p_IncludeInAPI_17bcf0af9ffc BOOLEAN;
  p_AllowAllRowsAPI_17bcf0af9ffc BOOLEAN;
  p_AllowUpdateAPI_17bcf0af9ffc BOOLEAN;
  p_AllowCreateAPI_17bcf0af9ffc BOOLEAN;
  p_AllowDeleteAPI_17bcf0af9ffc BOOLEAN;
  p_CustomResolverAPI_17bcf0af9ffc BOOLEAN;
  p_AllowUserSearchAPI_17bcf0af9ffc BOOLEAN;
  p_FullTextSearchEnabled_17bcf0af9ffc BOOLEAN;
  p_FullTextCatalog_17bcf0af9ffc VARCHAR(255);
  p_FullTextCatalogGenerated_17bcf0af9ffc BOOLEAN;
  p_FullTextIndex_17bcf0af9ffc VARCHAR(255);
  p_FullTextIndexGenerated_17bcf0af9ffc BOOLEAN;
  p_FullTextSearchFunction_17bcf0af9ffc VARCHAR(255);
  p_FullTextSearchFunctionGenerated_17bcf0af9ffc BOOLEAN;
  p_UserViewMaxRows_17bcf0af9ffc INTEGER;
  p_spCreate_17bcf0af9ffc VARCHAR(255);
  p_spUpdate_17bcf0af9ffc VARCHAR(255);
  p_spDelete_17bcf0af9ffc VARCHAR(255);
  p_spCreateGenerated_17bcf0af9ffc BOOLEAN;
  p_spUpdateGenerated_17bcf0af9ffc BOOLEAN;
  p_spDeleteGenerated_17bcf0af9ffc BOOLEAN;
  p_CascadeDeletes_17bcf0af9ffc BOOLEAN;
  p_DeleteType_17bcf0af9ffc VARCHAR(10);
  p_AllowRecordMerge_17bcf0af9ffc BOOLEAN;
  p_spMatch_17bcf0af9ffc VARCHAR(255);
  p_RelationshipDefaultDisplayType_17bcf0af9ffc VARCHAR(20);
  p_UserFormGenerated_17bcf0af9ffc BOOLEAN;
  p_EntityObjectSubclassName_17bcf0af9ffc VARCHAR(255);
  p_EntityObjectSubclassImport_17bcf0af9ffc VARCHAR(255);
  p_PreferredCommunicationField_17bcf0af9ffc VARCHAR(255);
  p_Icon_17bcf0af9ffc VARCHAR(500);
  p_ScopeDefault_17bcf0af9ffc VARCHAR(100);
  p_RowsToPackWithSchema_17bcf0af9ffc VARCHAR(20);
  p_RowsToPackSampleMethod_17bcf0af9ffc VARCHAR(20);
  p_RowsToPackSampleCount_17bcf0af9ffc INTEGER;
  p_RowsToPackSampleOrder_17bcf0af9ffc TEXT;
  p_AutoRowCountFrequency_17bcf0af9ffc INTEGER;
  p_RowCount_17bcf0af9ffc BIGINT;
  p_RowCountRunAt_17bcf0af9ffc TIMESTAMPTZ;
  p_Status_17bcf0af9ffc VARCHAR(25);
  p_DisplayName_17bcf0af9ffc VARCHAR(255);
  p_AllowMultipleSubtypes_17bcf0af9ffc BOOLEAN;
  p_AutoUpdateFullTextSearch_17bcf0af9ffc BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_17bcf0af9ffc BOOLEAN;
  p_TrustServerCacheCompletely_17bcf0af9ffc BOOLEAN;
  p_SupportsGeoCoding_17bcf0af9ffc BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_17bcf0af9ffc BOOLEAN;
  p_AllowCaching_17bcf0af9ffc BOOLEAN;
  p_DetectExternalChanges_17bcf0af9ffc BOOLEAN;
  p_ExternalDataSourceID_17bcf0af9ffc UUID;
  p_ExternalObjectName_17bcf0af9ffc VARCHAR(255);
  p_GeneratedBaseViewName_17bcf0af9ffc VARCHAR(255);
  p_AllowDirectSQLInsert_17bcf0af9ffc BOOLEAN;
  p_AllowDirectSQLUpdate_17bcf0af9ffc BOOLEAN;
  p_AllowDirectSQLDelete_17bcf0af9ffc BOOLEAN;
  p_Configuration_17bcf0af9ffc TEXT;
  p_SubtypeSelector_17bcf0af9ffc TEXT;
  p_EnableFieldLevelSecurity_17bcf0af9ffc BOOLEAN;
  p_ID_17bcf0af9ffc UUID;
BEGIN
  p_Name_17bcf0af9ffc := 'MJ_BizApps_Contracts: Contract Templates';
  p_Description_17bcf0af9ffc := 'One VERSION of a standard agreement — in practice the Master Agreement. Versions matter because each is published at its own dated URL that never goes away, so a customer stays bound to the text they signed. Carries no prose of its own: every clauses standard wording lives on its ContractTemplateProvision row.';
  p_AutoUpdateDescription_17bcf0af9ffc := TRUE;
  p_BaseView_17bcf0af9ffc := 'vwContractTemplates';
  p_BaseViewGenerated_17bcf0af9ffc := FALSE;
  p_VirtualEntity_17bcf0af9ffc := FALSE;
  p_TrackRecordChanges_17bcf0af9ffc := TRUE;
  p_AuditRecordAccess_17bcf0af9ffc := FALSE;
  p_AuditViewRuns_17bcf0af9ffc := FALSE;
  p_IncludeInAPI_17bcf0af9ffc := TRUE;
  p_AllowAllRowsAPI_17bcf0af9ffc := FALSE;
  p_AllowUpdateAPI_17bcf0af9ffc := TRUE;
  p_AllowCreateAPI_17bcf0af9ffc := TRUE;
  p_AllowDeleteAPI_17bcf0af9ffc := TRUE;
  p_CustomResolverAPI_17bcf0af9ffc := FALSE;
  p_AllowUserSearchAPI_17bcf0af9ffc := TRUE;
  p_FullTextSearchEnabled_17bcf0af9ffc := FALSE;
  p_FullTextCatalogGenerated_17bcf0af9ffc := TRUE;
  p_FullTextIndexGenerated_17bcf0af9ffc := TRUE;
  p_FullTextSearchFunctionGenerated_17bcf0af9ffc := TRUE;
  p_UserViewMaxRows_17bcf0af9ffc := 1000;
  p_spCreateGenerated_17bcf0af9ffc := TRUE;
  p_spUpdateGenerated_17bcf0af9ffc := TRUE;
  p_spDeleteGenerated_17bcf0af9ffc := TRUE;
  p_CascadeDeletes_17bcf0af9ffc := FALSE;
  p_DeleteType_17bcf0af9ffc := 'Hard';
  p_AllowRecordMerge_17bcf0af9ffc := FALSE;
  p_RelationshipDefaultDisplayType_17bcf0af9ffc := 'Search';
  p_UserFormGenerated_17bcf0af9ffc := TRUE;
  p_Icon_17bcf0af9ffc := 'fa fa-file-contract';
  p_RowsToPackWithSchema_17bcf0af9ffc := 'None';
  p_RowsToPackSampleMethod_17bcf0af9ffc := 'random';
  p_RowsToPackSampleCount_17bcf0af9ffc := 0;
  p_Status_17bcf0af9ffc := 'Active';
  p_DisplayName_17bcf0af9ffc := 'Contract Templates';
  p_AllowMultipleSubtypes_17bcf0af9ffc := FALSE;
  p_AutoUpdateFullTextSearch_17bcf0af9ffc := TRUE;
  p_AutoUpdateAllowUserSearchAPI_17bcf0af9ffc := FALSE;
  p_TrustServerCacheCompletely_17bcf0af9ffc := TRUE;
  p_SupportsGeoCoding_17bcf0af9ffc := FALSE;
  p_AutoUpdateSupportsGeoCoding_17bcf0af9ffc := TRUE;
  p_AllowCaching_17bcf0af9ffc := FALSE;
  p_DetectExternalChanges_17bcf0af9ffc := FALSE;
  p_GeneratedBaseViewName_17bcf0af9ffc := 'vwContractTemplatesGenerated';
  p_AllowDirectSQLInsert_17bcf0af9ffc := FALSE;
  p_AllowDirectSQLUpdate_17bcf0af9ffc := FALSE;
  p_AllowDirectSQLDelete_17bcf0af9ffc := FALSE;
  p_Configuration_17bcf0af9ffc := '{
  "UI": {
    "Form": {
      "Layout": "left-nav",
      "RelatedRolePolicy": "smart",
      "PrimaryRelatedBudget": 4
    }
  }
}';
  p_EnableFieldLevelSecurity_17bcf0af9ffc := FALSE;
  p_ID_17bcf0af9ffc := '731F2890-1415-40DE-9073-D22EA23392B3';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntity'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_17bcf0af9ffc,
    'Name', p_Name_17bcf0af9ffc,
    'NameSuffix', p_NameSuffix_17bcf0af9ffc,
    'Description', p_Description_17bcf0af9ffc,
    'AutoUpdateDescription', p_AutoUpdateDescription_17bcf0af9ffc,
    'BaseView', p_BaseView_17bcf0af9ffc,
    'BaseViewGenerated', p_BaseViewGenerated_17bcf0af9ffc,
    'VirtualEntity', p_VirtualEntity_17bcf0af9ffc,
    'TrackRecordChanges', p_TrackRecordChanges_17bcf0af9ffc,
    'AuditRecordAccess', p_AuditRecordAccess_17bcf0af9ffc,
    'AuditViewRuns', p_AuditViewRuns_17bcf0af9ffc,
    'IncludeInAPI', p_IncludeInAPI_17bcf0af9ffc,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_17bcf0af9ffc,
    'AllowUpdateAPI', p_AllowUpdateAPI_17bcf0af9ffc,
    'AllowCreateAPI', p_AllowCreateAPI_17bcf0af9ffc,
    'AllowDeleteAPI', p_AllowDeleteAPI_17bcf0af9ffc,
    'CustomResolverAPI', p_CustomResolverAPI_17bcf0af9ffc,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_17bcf0af9ffc,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_17bcf0af9ffc,
    'FullTextCatalog', p_FullTextCatalog_17bcf0af9ffc,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_17bcf0af9ffc,
    'FullTextIndex', p_FullTextIndex_17bcf0af9ffc,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_17bcf0af9ffc,
    'FullTextSearchFunction', p_FullTextSearchFunction_17bcf0af9ffc,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_17bcf0af9ffc,
    'UserViewMaxRows', p_UserViewMaxRows_17bcf0af9ffc,
    'spCreate', p_spCreate_17bcf0af9ffc,
    'spUpdate', p_spUpdate_17bcf0af9ffc,
    'spDelete', p_spDelete_17bcf0af9ffc,
    'spCreateGenerated', p_spCreateGenerated_17bcf0af9ffc,
    'spUpdateGenerated', p_spUpdateGenerated_17bcf0af9ffc,
    'spDeleteGenerated', p_spDeleteGenerated_17bcf0af9ffc,
    'CascadeDeletes', p_CascadeDeletes_17bcf0af9ffc,
    'DeleteType', p_DeleteType_17bcf0af9ffc,
    'AllowRecordMerge', p_AllowRecordMerge_17bcf0af9ffc,
    'spMatch', p_spMatch_17bcf0af9ffc,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_17bcf0af9ffc,
    'UserFormGenerated', p_UserFormGenerated_17bcf0af9ffc,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_17bcf0af9ffc,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_17bcf0af9ffc,
    'PreferredCommunicationField', p_PreferredCommunicationField_17bcf0af9ffc,
    'Icon', p_Icon_17bcf0af9ffc,
    'ScopeDefault', p_ScopeDefault_17bcf0af9ffc,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_17bcf0af9ffc,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_17bcf0af9ffc,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_17bcf0af9ffc,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_17bcf0af9ffc,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_17bcf0af9ffc,
    'RowCount', p_RowCount_17bcf0af9ffc,
    'RowCountRunAt', p_RowCountRunAt_17bcf0af9ffc
  ) ||
  jsonb_build_object(
    'Status', p_Status_17bcf0af9ffc,
    'DisplayName', p_DisplayName_17bcf0af9ffc,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_17bcf0af9ffc,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_17bcf0af9ffc,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_17bcf0af9ffc,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_17bcf0af9ffc,
    'SupportsGeoCoding', p_SupportsGeoCoding_17bcf0af9ffc,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_17bcf0af9ffc,
    'AllowCaching', p_AllowCaching_17bcf0af9ffc,
    'DetectExternalChanges', p_DetectExternalChanges_17bcf0af9ffc,
    'ExternalDataSourceID', p_ExternalDataSourceID_17bcf0af9ffc,
    'ExternalObjectName', p_ExternalObjectName_17bcf0af9ffc,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_17bcf0af9ffc,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_17bcf0af9ffc,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_17bcf0af9ffc,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_17bcf0af9ffc,
    'Configuration', p_Configuration_17bcf0af9ffc,
    'SubtypeSelector', p_SubtypeSelector_17bcf0af9ffc,
    'EnableFieldLevelSecurity', p_EnableFieldLevelSecurity_17bcf0af9ffc,
    'ID', p_ID_17bcf0af9ffc
  ));
  ELSE
    PERFORM __mj."spUpdateEntity"(p_ParentID := p_ParentID_17bcf0af9ffc, p_ParentID_Clear := TRUE, p_Name := p_Name_17bcf0af9ffc, p_NameSuffix := p_NameSuffix_17bcf0af9ffc, p_NameSuffix_Clear := TRUE, p_Description := p_Description_17bcf0af9ffc, p_AutoUpdateDescription := p_AutoUpdateDescription_17bcf0af9ffc, p_BaseView := p_BaseView_17bcf0af9ffc, p_BaseViewGenerated := p_BaseViewGenerated_17bcf0af9ffc, p_VirtualEntity := p_VirtualEntity_17bcf0af9ffc, p_TrackRecordChanges := p_TrackRecordChanges_17bcf0af9ffc, p_AuditRecordAccess := p_AuditRecordAccess_17bcf0af9ffc, p_AuditViewRuns := p_AuditViewRuns_17bcf0af9ffc, p_IncludeInAPI := p_IncludeInAPI_17bcf0af9ffc, p_AllowAllRowsAPI := p_AllowAllRowsAPI_17bcf0af9ffc, p_AllowUpdateAPI := p_AllowUpdateAPI_17bcf0af9ffc, p_AllowCreateAPI := p_AllowCreateAPI_17bcf0af9ffc, p_AllowDeleteAPI := p_AllowDeleteAPI_17bcf0af9ffc, p_CustomResolverAPI := p_CustomResolverAPI_17bcf0af9ffc, p_AllowUserSearchAPI := p_AllowUserSearchAPI_17bcf0af9ffc, p_FullTextSearchEnabled := p_FullTextSearchEnabled_17bcf0af9ffc, p_FullTextCatalog := p_FullTextCatalog_17bcf0af9ffc, p_FullTextCatalog_Clear := TRUE, p_FullTextCatalogGenerated := p_FullTextCatalogGenerated_17bcf0af9ffc, p_FullTextIndex := p_FullTextIndex_17bcf0af9ffc, p_FullTextIndex_Clear := TRUE, p_FullTextIndexGenerated := p_FullTextIndexGenerated_17bcf0af9ffc, p_FullTextSearchFunction := p_FullTextSearchFunction_17bcf0af9ffc, p_FullTextSearchFunction_Clear := TRUE, p_FullTextSearchFunctionGenerated := p_FullTextSearchFunctionGenerated_17bcf0af9ffc, p_UserViewMaxRows := p_UserViewMaxRows_17bcf0af9ffc, p_spCreate := p_spCreate_17bcf0af9ffc, p_spCreate_Clear := TRUE, p_spUpdate := p_spUpdate_17bcf0af9ffc, p_spUpdate_Clear := TRUE, p_spDelete := p_spDelete_17bcf0af9ffc, p_spDelete_Clear := TRUE, p_spCreateGenerated := p_spCreateGenerated_17bcf0af9ffc, p_spUpdateGenerated := p_spUpdateGenerated_17bcf0af9ffc, p_spDeleteGenerated := p_spDeleteGenerated_17bcf0af9ffc, p_CascadeDeletes := p_CascadeDeletes_17bcf0af9ffc, p_DeleteType := p_DeleteType_17bcf0af9ffc, p_AllowRecordMerge := p_AllowRecordMerge_17bcf0af9ffc, p_spMatch := p_spMatch_17bcf0af9ffc, p_spMatch_Clear := TRUE, p_RelationshipDefaultDisplayType := p_RelationshipDefaultDisplayType_17bcf0af9ffc, p_UserFormGenerated := p_UserFormGenerated_17bcf0af9ffc, p_EntityObjectSubclassName := p_EntityObjectSubclassName_17bcf0af9ffc, p_EntityObjectSubclassName_Clear := TRUE, p_EntityObjectSubclassImport := p_EntityObjectSubclassImport_17bcf0af9ffc, p_EntityObjectSubclassImport_Clear := TRUE, p_PreferredCommunicationField := p_PreferredCommunicationField_17bcf0af9ffc, p_PreferredCommunicationField_Clear := TRUE, p_Icon := p_Icon_17bcf0af9ffc, p_ScopeDefault := p_ScopeDefault_17bcf0af9ffc, p_ScopeDefault_Clear := TRUE, p_RowsToPackWithSchema := p_RowsToPackWithSchema_17bcf0af9ffc, p_RowsToPackSampleMethod := p_RowsToPackSampleMethod_17bcf0af9ffc, p_RowsToPackSampleCount := p_RowsToPackSampleCount_17bcf0af9ffc, p_RowsToPackSampleOrder := p_RowsToPackSampleOrder_17bcf0af9ffc, p_RowsToPackSampleOrder_Clear := TRUE, p_AutoRowCountFrequency := p_AutoRowCountFrequency_17bcf0af9ffc, p_AutoRowCountFrequency_Clear := TRUE, p_RowCount := p_RowCount_17bcf0af9ffc, p_RowCount_Clear := TRUE, p_RowCountRunAt := p_RowCountRunAt_17bcf0af9ffc, p_RowCountRunAt_Clear := TRUE, p_Status := p_Status_17bcf0af9ffc, p_DisplayName := p_DisplayName_17bcf0af9ffc, p_AllowMultipleSubtypes := p_AllowMultipleSubtypes_17bcf0af9ffc, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_17bcf0af9ffc, p_AutoUpdateAllowUserSearchAPI := p_AutoUpdateAllowUserSearchAPI_17bcf0af9ffc, p_TrustServerCacheCompletely := p_TrustServerCacheCompletely_17bcf0af9ffc, p_SupportsGeoCoding := p_SupportsGeoCoding_17bcf0af9ffc, p_AutoUpdateSupportsGeoCoding := p_AutoUpdateSupportsGeoCoding_17bcf0af9ffc, p_AllowCaching := p_AllowCaching_17bcf0af9ffc, p_DetectExternalChanges := p_DetectExternalChanges_17bcf0af9ffc, p_ExternalDataSourceID := p_ExternalDataSourceID_17bcf0af9ffc, p_ExternalDataSourceID_Clear := TRUE, p_ExternalObjectName := p_ExternalObjectName_17bcf0af9ffc, p_ExternalObjectName_Clear := TRUE, p_GeneratedBaseViewName := p_GeneratedBaseViewName_17bcf0af9ffc, p_AllowDirectSQLInsert := p_AllowDirectSQLInsert_17bcf0af9ffc, p_AllowDirectSQLUpdate := p_AllowDirectSQLUpdate_17bcf0af9ffc, p_AllowDirectSQLDelete := p_AllowDirectSQLDelete_17bcf0af9ffc, p_Configuration := p_Configuration_17bcf0af9ffc, p_SubtypeSelector := p_SubtypeSelector_17bcf0af9ffc, p_SubtypeSelector_Clear := TRUE, p_EnableFieldLevelSecurity := p_EnableFieldLevelSecurity_17bcf0af9ffc, p_ID := p_ID_17bcf0af9ffc);
  END IF;
END $mj$;

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_8dca982f8ff0 UUID;
  p_Name_8dca982f8ff0 VARCHAR(255);
  p_NameSuffix_8dca982f8ff0 VARCHAR(255);
  p_Description_8dca982f8ff0 TEXT;
  p_AutoUpdateDescription_8dca982f8ff0 BOOLEAN;
  p_BaseView_8dca982f8ff0 VARCHAR(255);
  p_BaseViewGenerated_8dca982f8ff0 BOOLEAN;
  p_VirtualEntity_8dca982f8ff0 BOOLEAN;
  p_TrackRecordChanges_8dca982f8ff0 BOOLEAN;
  p_AuditRecordAccess_8dca982f8ff0 BOOLEAN;
  p_AuditViewRuns_8dca982f8ff0 BOOLEAN;
  p_IncludeInAPI_8dca982f8ff0 BOOLEAN;
  p_AllowAllRowsAPI_8dca982f8ff0 BOOLEAN;
  p_AllowUpdateAPI_8dca982f8ff0 BOOLEAN;
  p_AllowCreateAPI_8dca982f8ff0 BOOLEAN;
  p_AllowDeleteAPI_8dca982f8ff0 BOOLEAN;
  p_CustomResolverAPI_8dca982f8ff0 BOOLEAN;
  p_AllowUserSearchAPI_8dca982f8ff0 BOOLEAN;
  p_FullTextSearchEnabled_8dca982f8ff0 BOOLEAN;
  p_FullTextCatalog_8dca982f8ff0 VARCHAR(255);
  p_FullTextCatalogGenerated_8dca982f8ff0 BOOLEAN;
  p_FullTextIndex_8dca982f8ff0 VARCHAR(255);
  p_FullTextIndexGenerated_8dca982f8ff0 BOOLEAN;
  p_FullTextSearchFunction_8dca982f8ff0 VARCHAR(255);
  p_FullTextSearchFunctionGenerated_8dca982f8ff0 BOOLEAN;
  p_UserViewMaxRows_8dca982f8ff0 INTEGER;
  p_spCreate_8dca982f8ff0 VARCHAR(255);
  p_spUpdate_8dca982f8ff0 VARCHAR(255);
  p_spDelete_8dca982f8ff0 VARCHAR(255);
  p_spCreateGenerated_8dca982f8ff0 BOOLEAN;
  p_spUpdateGenerated_8dca982f8ff0 BOOLEAN;
  p_spDeleteGenerated_8dca982f8ff0 BOOLEAN;
  p_CascadeDeletes_8dca982f8ff0 BOOLEAN;
  p_DeleteType_8dca982f8ff0 VARCHAR(10);
  p_AllowRecordMerge_8dca982f8ff0 BOOLEAN;
  p_spMatch_8dca982f8ff0 VARCHAR(255);
  p_RelationshipDefaultDisplayType_8dca982f8ff0 VARCHAR(20);
  p_UserFormGenerated_8dca982f8ff0 BOOLEAN;
  p_EntityObjectSubclassName_8dca982f8ff0 VARCHAR(255);
  p_EntityObjectSubclassImport_8dca982f8ff0 VARCHAR(255);
  p_PreferredCommunicationField_8dca982f8ff0 VARCHAR(255);
  p_Icon_8dca982f8ff0 VARCHAR(500);
  p_ScopeDefault_8dca982f8ff0 VARCHAR(100);
  p_RowsToPackWithSchema_8dca982f8ff0 VARCHAR(20);
  p_RowsToPackSampleMethod_8dca982f8ff0 VARCHAR(20);
  p_RowsToPackSampleCount_8dca982f8ff0 INTEGER;
  p_RowsToPackSampleOrder_8dca982f8ff0 TEXT;
  p_AutoRowCountFrequency_8dca982f8ff0 INTEGER;
  p_RowCount_8dca982f8ff0 BIGINT;
  p_RowCountRunAt_8dca982f8ff0 TIMESTAMPTZ;
  p_Status_8dca982f8ff0 VARCHAR(25);
  p_DisplayName_8dca982f8ff0 VARCHAR(255);
  p_AllowMultipleSubtypes_8dca982f8ff0 BOOLEAN;
  p_AutoUpdateFullTextSearch_8dca982f8ff0 BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_8dca982f8ff0 BOOLEAN;
  p_TrustServerCacheCompletely_8dca982f8ff0 BOOLEAN;
  p_SupportsGeoCoding_8dca982f8ff0 BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_8dca982f8ff0 BOOLEAN;
  p_AllowCaching_8dca982f8ff0 BOOLEAN;
  p_DetectExternalChanges_8dca982f8ff0 BOOLEAN;
  p_ExternalDataSourceID_8dca982f8ff0 UUID;
  p_ExternalObjectName_8dca982f8ff0 VARCHAR(255);
  p_GeneratedBaseViewName_8dca982f8ff0 VARCHAR(255);
  p_AllowDirectSQLInsert_8dca982f8ff0 BOOLEAN;
  p_AllowDirectSQLUpdate_8dca982f8ff0 BOOLEAN;
  p_AllowDirectSQLDelete_8dca982f8ff0 BOOLEAN;
  p_Configuration_8dca982f8ff0 TEXT;
  p_SubtypeSelector_8dca982f8ff0 TEXT;
  p_EnableFieldLevelSecurity_8dca982f8ff0 BOOLEAN;
  p_ID_8dca982f8ff0 UUID;
BEGIN
  p_Name_8dca982f8ff0 := 'MJ_BizApps_Contracts: Contract Template Provisions';
  p_Description_8dca982f8ff0 := 'The numbered clause list of a template version, and the home of all standard contract text. Hangs off ContractTemplate rather than standing alone because provision numbering belongs to a VERSION — the moment a new version renumbers, a single global list is wrong.';
  p_AutoUpdateDescription_8dca982f8ff0 := TRUE;
  p_BaseView_8dca982f8ff0 := 'vwContractTemplateProvisions';
  p_BaseViewGenerated_8dca982f8ff0 := TRUE;
  p_VirtualEntity_8dca982f8ff0 := FALSE;
  p_TrackRecordChanges_8dca982f8ff0 := TRUE;
  p_AuditRecordAccess_8dca982f8ff0 := FALSE;
  p_AuditViewRuns_8dca982f8ff0 := FALSE;
  p_IncludeInAPI_8dca982f8ff0 := TRUE;
  p_AllowAllRowsAPI_8dca982f8ff0 := FALSE;
  p_AllowUpdateAPI_8dca982f8ff0 := TRUE;
  p_AllowCreateAPI_8dca982f8ff0 := TRUE;
  p_AllowDeleteAPI_8dca982f8ff0 := TRUE;
  p_CustomResolverAPI_8dca982f8ff0 := FALSE;
  p_AllowUserSearchAPI_8dca982f8ff0 := FALSE;
  p_FullTextSearchEnabled_8dca982f8ff0 := FALSE;
  p_FullTextCatalogGenerated_8dca982f8ff0 := TRUE;
  p_FullTextIndexGenerated_8dca982f8ff0 := TRUE;
  p_FullTextSearchFunctionGenerated_8dca982f8ff0 := TRUE;
  p_UserViewMaxRows_8dca982f8ff0 := 1000;
  p_spCreateGenerated_8dca982f8ff0 := TRUE;
  p_spUpdateGenerated_8dca982f8ff0 := TRUE;
  p_spDeleteGenerated_8dca982f8ff0 := TRUE;
  p_CascadeDeletes_8dca982f8ff0 := FALSE;
  p_DeleteType_8dca982f8ff0 := 'Hard';
  p_AllowRecordMerge_8dca982f8ff0 := FALSE;
  p_RelationshipDefaultDisplayType_8dca982f8ff0 := 'Search';
  p_UserFormGenerated_8dca982f8ff0 := TRUE;
  p_Icon_8dca982f8ff0 := 'fa fa-file-contract';
  p_RowsToPackWithSchema_8dca982f8ff0 := 'None';
  p_RowsToPackSampleMethod_8dca982f8ff0 := 'random';
  p_RowsToPackSampleCount_8dca982f8ff0 := 0;
  p_Status_8dca982f8ff0 := 'Active';
  p_DisplayName_8dca982f8ff0 := 'Contract Template Provisions';
  p_AllowMultipleSubtypes_8dca982f8ff0 := FALSE;
  p_AutoUpdateFullTextSearch_8dca982f8ff0 := TRUE;
  p_AutoUpdateAllowUserSearchAPI_8dca982f8ff0 := FALSE;
  p_TrustServerCacheCompletely_8dca982f8ff0 := TRUE;
  p_SupportsGeoCoding_8dca982f8ff0 := FALSE;
  p_AutoUpdateSupportsGeoCoding_8dca982f8ff0 := TRUE;
  p_AllowCaching_8dca982f8ff0 := FALSE;
  p_DetectExternalChanges_8dca982f8ff0 := FALSE;
  p_AllowDirectSQLInsert_8dca982f8ff0 := FALSE;
  p_AllowDirectSQLUpdate_8dca982f8ff0 := FALSE;
  p_AllowDirectSQLDelete_8dca982f8ff0 := FALSE;
  p_EnableFieldLevelSecurity_8dca982f8ff0 := FALSE;
  p_ID_8dca982f8ff0 := '317DF592-8C20-473D-B097-2AB239877438';
  PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_8dca982f8ff0,
    'Name', p_Name_8dca982f8ff0,
    'NameSuffix', p_NameSuffix_8dca982f8ff0,
    'Description', p_Description_8dca982f8ff0,
    'AutoUpdateDescription', p_AutoUpdateDescription_8dca982f8ff0,
    'BaseView', p_BaseView_8dca982f8ff0,
    'BaseViewGenerated', p_BaseViewGenerated_8dca982f8ff0,
    'VirtualEntity', p_VirtualEntity_8dca982f8ff0,
    'TrackRecordChanges', p_TrackRecordChanges_8dca982f8ff0,
    'AuditRecordAccess', p_AuditRecordAccess_8dca982f8ff0,
    'AuditViewRuns', p_AuditViewRuns_8dca982f8ff0,
    'IncludeInAPI', p_IncludeInAPI_8dca982f8ff0,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_8dca982f8ff0,
    'AllowUpdateAPI', p_AllowUpdateAPI_8dca982f8ff0,
    'AllowCreateAPI', p_AllowCreateAPI_8dca982f8ff0,
    'AllowDeleteAPI', p_AllowDeleteAPI_8dca982f8ff0,
    'CustomResolverAPI', p_CustomResolverAPI_8dca982f8ff0,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_8dca982f8ff0,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_8dca982f8ff0,
    'FullTextCatalog', p_FullTextCatalog_8dca982f8ff0,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_8dca982f8ff0,
    'FullTextIndex', p_FullTextIndex_8dca982f8ff0,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_8dca982f8ff0,
    'FullTextSearchFunction', p_FullTextSearchFunction_8dca982f8ff0,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_8dca982f8ff0,
    'UserViewMaxRows', p_UserViewMaxRows_8dca982f8ff0,
    'spCreate', p_spCreate_8dca982f8ff0,
    'spUpdate', p_spUpdate_8dca982f8ff0,
    'spDelete', p_spDelete_8dca982f8ff0,
    'spCreateGenerated', p_spCreateGenerated_8dca982f8ff0,
    'spUpdateGenerated', p_spUpdateGenerated_8dca982f8ff0,
    'spDeleteGenerated', p_spDeleteGenerated_8dca982f8ff0,
    'CascadeDeletes', p_CascadeDeletes_8dca982f8ff0,
    'DeleteType', p_DeleteType_8dca982f8ff0,
    'AllowRecordMerge', p_AllowRecordMerge_8dca982f8ff0,
    'spMatch', p_spMatch_8dca982f8ff0,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_8dca982f8ff0,
    'UserFormGenerated', p_UserFormGenerated_8dca982f8ff0,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_8dca982f8ff0,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_8dca982f8ff0,
    'PreferredCommunicationField', p_PreferredCommunicationField_8dca982f8ff0,
    'Icon', p_Icon_8dca982f8ff0,
    'ScopeDefault', p_ScopeDefault_8dca982f8ff0,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_8dca982f8ff0,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_8dca982f8ff0,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_8dca982f8ff0,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_8dca982f8ff0,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_8dca982f8ff0,
    'RowCount', p_RowCount_8dca982f8ff0,
    'RowCountRunAt', p_RowCountRunAt_8dca982f8ff0
  ) ||
  jsonb_build_object(
    'Status', p_Status_8dca982f8ff0,
    'DisplayName', p_DisplayName_8dca982f8ff0,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_8dca982f8ff0,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_8dca982f8ff0,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_8dca982f8ff0,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_8dca982f8ff0,
    'SupportsGeoCoding', p_SupportsGeoCoding_8dca982f8ff0,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_8dca982f8ff0,
    'AllowCaching', p_AllowCaching_8dca982f8ff0,
    'DetectExternalChanges', p_DetectExternalChanges_8dca982f8ff0,
    'ExternalDataSourceID', p_ExternalDataSourceID_8dca982f8ff0,
    'ExternalObjectName', p_ExternalObjectName_8dca982f8ff0,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_8dca982f8ff0,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_8dca982f8ff0,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_8dca982f8ff0,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_8dca982f8ff0,
    'Configuration', p_Configuration_8dca982f8ff0,
    'SubtypeSelector', p_SubtypeSelector_8dca982f8ff0,
    'EnableFieldLevelSecurity', p_EnableFieldLevelSecurity_8dca982f8ff0,
    'ID', p_ID_8dca982f8ff0
  ));
END $mj$;

-- Save MJ: Entities (core SP call only)
DO $mj$
DECLARE
  p_ParentID_067ca7cad756 UUID;
  p_Name_067ca7cad756 VARCHAR(255);
  p_NameSuffix_067ca7cad756 VARCHAR(255);
  p_Description_067ca7cad756 TEXT;
  p_AutoUpdateDescription_067ca7cad756 BOOLEAN;
  p_BaseView_067ca7cad756 VARCHAR(255);
  p_BaseViewGenerated_067ca7cad756 BOOLEAN;
  p_VirtualEntity_067ca7cad756 BOOLEAN;
  p_TrackRecordChanges_067ca7cad756 BOOLEAN;
  p_AuditRecordAccess_067ca7cad756 BOOLEAN;
  p_AuditViewRuns_067ca7cad756 BOOLEAN;
  p_IncludeInAPI_067ca7cad756 BOOLEAN;
  p_AllowAllRowsAPI_067ca7cad756 BOOLEAN;
  p_AllowUpdateAPI_067ca7cad756 BOOLEAN;
  p_AllowCreateAPI_067ca7cad756 BOOLEAN;
  p_AllowDeleteAPI_067ca7cad756 BOOLEAN;
  p_CustomResolverAPI_067ca7cad756 BOOLEAN;
  p_AllowUserSearchAPI_067ca7cad756 BOOLEAN;
  p_FullTextSearchEnabled_067ca7cad756 BOOLEAN;
  p_FullTextCatalog_067ca7cad756 VARCHAR(255);
  p_FullTextCatalogGenerated_067ca7cad756 BOOLEAN;
  p_FullTextIndex_067ca7cad756 VARCHAR(255);
  p_FullTextIndexGenerated_067ca7cad756 BOOLEAN;
  p_FullTextSearchFunction_067ca7cad756 VARCHAR(255);
  p_FullTextSearchFunctionGenerated_067ca7cad756 BOOLEAN;
  p_UserViewMaxRows_067ca7cad756 INTEGER;
  p_spCreate_067ca7cad756 VARCHAR(255);
  p_spUpdate_067ca7cad756 VARCHAR(255);
  p_spDelete_067ca7cad756 VARCHAR(255);
  p_spCreateGenerated_067ca7cad756 BOOLEAN;
  p_spUpdateGenerated_067ca7cad756 BOOLEAN;
  p_spDeleteGenerated_067ca7cad756 BOOLEAN;
  p_CascadeDeletes_067ca7cad756 BOOLEAN;
  p_DeleteType_067ca7cad756 VARCHAR(10);
  p_AllowRecordMerge_067ca7cad756 BOOLEAN;
  p_spMatch_067ca7cad756 VARCHAR(255);
  p_RelationshipDefaultDisplayType_067ca7cad756 VARCHAR(20);
  p_UserFormGenerated_067ca7cad756 BOOLEAN;
  p_EntityObjectSubclassName_067ca7cad756 VARCHAR(255);
  p_EntityObjectSubclassImport_067ca7cad756 VARCHAR(255);
  p_PreferredCommunicationField_067ca7cad756 VARCHAR(255);
  p_Icon_067ca7cad756 VARCHAR(500);
  p_ScopeDefault_067ca7cad756 VARCHAR(100);
  p_RowsToPackWithSchema_067ca7cad756 VARCHAR(20);
  p_RowsToPackSampleMethod_067ca7cad756 VARCHAR(20);
  p_RowsToPackSampleCount_067ca7cad756 INTEGER;
  p_RowsToPackSampleOrder_067ca7cad756 TEXT;
  p_AutoRowCountFrequency_067ca7cad756 INTEGER;
  p_RowCount_067ca7cad756 BIGINT;
  p_RowCountRunAt_067ca7cad756 TIMESTAMPTZ;
  p_Status_067ca7cad756 VARCHAR(25);
  p_DisplayName_067ca7cad756 VARCHAR(255);
  p_AllowMultipleSubtypes_067ca7cad756 BOOLEAN;
  p_AutoUpdateFullTextSearch_067ca7cad756 BOOLEAN;
  p_AutoUpdateAllowUserSearchAPI_067ca7cad756 BOOLEAN;
  p_TrustServerCacheCompletely_067ca7cad756 BOOLEAN;
  p_SupportsGeoCoding_067ca7cad756 BOOLEAN;
  p_AutoUpdateSupportsGeoCoding_067ca7cad756 BOOLEAN;
  p_AllowCaching_067ca7cad756 BOOLEAN;
  p_DetectExternalChanges_067ca7cad756 BOOLEAN;
  p_ExternalDataSourceID_067ca7cad756 UUID;
  p_ExternalObjectName_067ca7cad756 VARCHAR(255);
  p_GeneratedBaseViewName_067ca7cad756 VARCHAR(255);
  p_AllowDirectSQLInsert_067ca7cad756 BOOLEAN;
  p_AllowDirectSQLUpdate_067ca7cad756 BOOLEAN;
  p_AllowDirectSQLDelete_067ca7cad756 BOOLEAN;
  p_Configuration_067ca7cad756 TEXT;
  p_SubtypeSelector_067ca7cad756 TEXT;
  p_EnableFieldLevelSecurity_067ca7cad756 BOOLEAN;
  p_ID_067ca7cad756 UUID;
BEGIN
  p_Name_067ca7cad756 := 'MJ_BizApps_Contracts: Contract Template Modifications';
  p_Description_067ca7cad756 := 'What THIS contract changed about the standard agreement. Deliberately lean: it names a provision and carries what the contract says instead. Carries no ContractTemplateID — the provision belongs to exactly one template in every future, so the template derives through the provision, and a stored copy of a derivation can only agree or lie.';
  p_AutoUpdateDescription_067ca7cad756 := TRUE;
  p_BaseView_067ca7cad756 := 'vwContractTemplateModifications';
  p_BaseViewGenerated_067ca7cad756 := TRUE;
  p_VirtualEntity_067ca7cad756 := FALSE;
  p_TrackRecordChanges_067ca7cad756 := TRUE;
  p_AuditRecordAccess_067ca7cad756 := FALSE;
  p_AuditViewRuns_067ca7cad756 := FALSE;
  p_IncludeInAPI_067ca7cad756 := TRUE;
  p_AllowAllRowsAPI_067ca7cad756 := FALSE;
  p_AllowUpdateAPI_067ca7cad756 := TRUE;
  p_AllowCreateAPI_067ca7cad756 := TRUE;
  p_AllowDeleteAPI_067ca7cad756 := TRUE;
  p_CustomResolverAPI_067ca7cad756 := FALSE;
  p_AllowUserSearchAPI_067ca7cad756 := FALSE;
  p_FullTextSearchEnabled_067ca7cad756 := FALSE;
  p_FullTextCatalogGenerated_067ca7cad756 := TRUE;
  p_FullTextIndexGenerated_067ca7cad756 := TRUE;
  p_FullTextSearchFunctionGenerated_067ca7cad756 := TRUE;
  p_UserViewMaxRows_067ca7cad756 := 1000;
  p_spCreateGenerated_067ca7cad756 := TRUE;
  p_spUpdateGenerated_067ca7cad756 := TRUE;
  p_spDeleteGenerated_067ca7cad756 := TRUE;
  p_CascadeDeletes_067ca7cad756 := FALSE;
  p_DeleteType_067ca7cad756 := 'Hard';
  p_AllowRecordMerge_067ca7cad756 := FALSE;
  p_RelationshipDefaultDisplayType_067ca7cad756 := 'Search';
  p_UserFormGenerated_067ca7cad756 := TRUE;
  p_Icon_067ca7cad756 := 'fa fa-file-contract';
  p_RowsToPackWithSchema_067ca7cad756 := 'None';
  p_RowsToPackSampleMethod_067ca7cad756 := 'random';
  p_RowsToPackSampleCount_067ca7cad756 := 0;
  p_Status_067ca7cad756 := 'Active';
  p_DisplayName_067ca7cad756 := 'Contract Template Modifications';
  p_AllowMultipleSubtypes_067ca7cad756 := FALSE;
  p_AutoUpdateFullTextSearch_067ca7cad756 := TRUE;
  p_AutoUpdateAllowUserSearchAPI_067ca7cad756 := FALSE;
  p_TrustServerCacheCompletely_067ca7cad756 := TRUE;
  p_SupportsGeoCoding_067ca7cad756 := FALSE;
  p_AutoUpdateSupportsGeoCoding_067ca7cad756 := TRUE;
  p_AllowCaching_067ca7cad756 := FALSE;
  p_DetectExternalChanges_067ca7cad756 := FALSE;
  p_AllowDirectSQLInsert_067ca7cad756 := FALSE;
  p_AllowDirectSQLUpdate_067ca7cad756 := FALSE;
  p_AllowDirectSQLDelete_067ca7cad756 := FALSE;
  p_EnableFieldLevelSecurity_067ca7cad756 := FALSE;
  p_ID_067ca7cad756 := 'B05A480F-F7C5-4D45-8EA3-C90E9A14F225';
  PERFORM __mj."spUpdateEntity"(p_data := jsonb_build_object(
    'ParentID', p_ParentID_067ca7cad756,
    'Name', p_Name_067ca7cad756,
    'NameSuffix', p_NameSuffix_067ca7cad756,
    'Description', p_Description_067ca7cad756,
    'AutoUpdateDescription', p_AutoUpdateDescription_067ca7cad756,
    'BaseView', p_BaseView_067ca7cad756,
    'BaseViewGenerated', p_BaseViewGenerated_067ca7cad756,
    'VirtualEntity', p_VirtualEntity_067ca7cad756,
    'TrackRecordChanges', p_TrackRecordChanges_067ca7cad756,
    'AuditRecordAccess', p_AuditRecordAccess_067ca7cad756,
    'AuditViewRuns', p_AuditViewRuns_067ca7cad756,
    'IncludeInAPI', p_IncludeInAPI_067ca7cad756,
    'AllowAllRowsAPI', p_AllowAllRowsAPI_067ca7cad756,
    'AllowUpdateAPI', p_AllowUpdateAPI_067ca7cad756,
    'AllowCreateAPI', p_AllowCreateAPI_067ca7cad756,
    'AllowDeleteAPI', p_AllowDeleteAPI_067ca7cad756,
    'CustomResolverAPI', p_CustomResolverAPI_067ca7cad756,
    'AllowUserSearchAPI', p_AllowUserSearchAPI_067ca7cad756,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_067ca7cad756,
    'FullTextCatalog', p_FullTextCatalog_067ca7cad756,
    'FullTextCatalogGenerated', p_FullTextCatalogGenerated_067ca7cad756,
    'FullTextIndex', p_FullTextIndex_067ca7cad756,
    'FullTextIndexGenerated', p_FullTextIndexGenerated_067ca7cad756,
    'FullTextSearchFunction', p_FullTextSearchFunction_067ca7cad756,
    'FullTextSearchFunctionGenerated', p_FullTextSearchFunctionGenerated_067ca7cad756,
    'UserViewMaxRows', p_UserViewMaxRows_067ca7cad756,
    'spCreate', p_spCreate_067ca7cad756,
    'spUpdate', p_spUpdate_067ca7cad756,
    'spDelete', p_spDelete_067ca7cad756,
    'spCreateGenerated', p_spCreateGenerated_067ca7cad756,
    'spUpdateGenerated', p_spUpdateGenerated_067ca7cad756,
    'spDeleteGenerated', p_spDeleteGenerated_067ca7cad756,
    'CascadeDeletes', p_CascadeDeletes_067ca7cad756,
    'DeleteType', p_DeleteType_067ca7cad756,
    'AllowRecordMerge', p_AllowRecordMerge_067ca7cad756,
    'spMatch', p_spMatch_067ca7cad756,
    'RelationshipDefaultDisplayType', p_RelationshipDefaultDisplayType_067ca7cad756,
    'UserFormGenerated', p_UserFormGenerated_067ca7cad756,
    'EntityObjectSubclassName', p_EntityObjectSubclassName_067ca7cad756,
    'EntityObjectSubclassImport', p_EntityObjectSubclassImport_067ca7cad756,
    'PreferredCommunicationField', p_PreferredCommunicationField_067ca7cad756,
    'Icon', p_Icon_067ca7cad756,
    'ScopeDefault', p_ScopeDefault_067ca7cad756,
    'RowsToPackWithSchema', p_RowsToPackWithSchema_067ca7cad756,
    'RowsToPackSampleMethod', p_RowsToPackSampleMethod_067ca7cad756,
    'RowsToPackSampleCount', p_RowsToPackSampleCount_067ca7cad756,
    'RowsToPackSampleOrder', p_RowsToPackSampleOrder_067ca7cad756,
    'AutoRowCountFrequency', p_AutoRowCountFrequency_067ca7cad756,
    'RowCount', p_RowCount_067ca7cad756,
    'RowCountRunAt', p_RowCountRunAt_067ca7cad756
  ) ||
  jsonb_build_object(
    'Status', p_Status_067ca7cad756,
    'DisplayName', p_DisplayName_067ca7cad756,
    'AllowMultipleSubtypes', p_AllowMultipleSubtypes_067ca7cad756,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_067ca7cad756,
    'AutoUpdateAllowUserSearchAPI', p_AutoUpdateAllowUserSearchAPI_067ca7cad756,
    'TrustServerCacheCompletely', p_TrustServerCacheCompletely_067ca7cad756,
    'SupportsGeoCoding', p_SupportsGeoCoding_067ca7cad756,
    'AutoUpdateSupportsGeoCoding', p_AutoUpdateSupportsGeoCoding_067ca7cad756,
    'AllowCaching', p_AllowCaching_067ca7cad756,
    'DetectExternalChanges', p_DetectExternalChanges_067ca7cad756,
    'ExternalDataSourceID', p_ExternalDataSourceID_067ca7cad756,
    'ExternalObjectName', p_ExternalObjectName_067ca7cad756,
    'GeneratedBaseViewName', p_GeneratedBaseViewName_067ca7cad756,
    'AllowDirectSQLInsert', p_AllowDirectSQLInsert_067ca7cad756,
    'AllowDirectSQLUpdate', p_AllowDirectSQLUpdate_067ca7cad756,
    'AllowDirectSQLDelete', p_AllowDirectSQLDelete_067ca7cad756,
    'Configuration', p_Configuration_067ca7cad756,
    'SubtypeSelector', p_SubtypeSelector_067ca7cad756,
    'EnableFieldLevelSecurity', p_EnableFieldLevelSecurity_067ca7cad756,
    'ID', p_ID_067ca7cad756
  ));
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_beede271f89e VARCHAR(255);
  p_Description_beede271f89e TEXT;
  p_AutoUpdateDescription_beede271f89e BOOLEAN;
  p_IsPrimaryKey_beede271f89e BOOLEAN;
  p_IsUnique_beede271f89e BOOLEAN;
  p_Category_beede271f89e VARCHAR(255);
  p_ValueListType_beede271f89e VARCHAR(20);
  p_ExtendedType_beede271f89e VARCHAR(50);
  p_CodeType_beede271f89e VARCHAR(50);
  p_DefaultInView_beede271f89e BOOLEAN;
  p_ViewCellTemplate_beede271f89e TEXT;
  p_DefaultColumnWidth_beede271f89e INTEGER;
  p_AllowUpdateAPI_beede271f89e BOOLEAN;
  p_AllowUpdateInView_beede271f89e BOOLEAN;
  p_IncludeInUserSearchAPI_beede271f89e BOOLEAN;
  p_FullTextSearchEnabled_beede271f89e BOOLEAN;
  p_UserSearchParamFormatAPI_beede271f89e VARCHAR(500);
  p_IncludeInGeneratedForm_beede271f89e BOOLEAN;
  p_GeneratedFormSection_beede271f89e VARCHAR(10);
  p_IsNameField_beede271f89e BOOLEAN;
  p_RelatedEntityID_beede271f89e UUID;
  p_RelatedEntityFieldName_beede271f89e VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_beede271f89e BOOLEAN;
  p_RelatedEntityNameFieldMap_beede271f89e VARCHAR(255);
  p_RelatedEntityDisplayType_beede271f89e VARCHAR(20);
  p_EntityIDFieldName_beede271f89e VARCHAR(100);
  p_ScopeDefault_beede271f89e VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_beede271f89e BOOLEAN;
  p_ValuesToPackWithSchema_beede271f89e VARCHAR(10);
  p_Status_beede271f89e VARCHAR(25);
  p_AutoUpdateIsNameField_beede271f89e BOOLEAN;
  p_AutoUpdateDefaultInView_beede271f89e BOOLEAN;
  p_AutoUpdateCategory_beede271f89e BOOLEAN;
  p_AutoUpdateDisplayName_beede271f89e BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_beede271f89e BOOLEAN;
  p_Encrypt_beede271f89e BOOLEAN;
  p_EncryptionKeyID_beede271f89e UUID;
  p_AllowDecryptInAPI_beede271f89e BOOLEAN;
  p_SendEncryptedValue_beede271f89e BOOLEAN;
  p_IsSoftPrimaryKey_beede271f89e BOOLEAN;
  p_IsSoftForeignKey_beede271f89e BOOLEAN;
  p_RelatedEntityJoinFields_beede271f89e TEXT;
  p_JSONType_beede271f89e VARCHAR(255);
  p_JSONTypeIsArray_beede271f89e BOOLEAN;
  p_JSONTypeDefinition_beede271f89e TEXT;
  p_UserSearchPredicateAPI_beede271f89e VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_beede271f89e BOOLEAN;
  p_AutoUpdateFullTextSearch_beede271f89e BOOLEAN;
  p_AutoUpdateExtendedType_beede271f89e BOOLEAN;
  p_IsComputed_beede271f89e BOOLEAN;
  p_EmbeddedRecord_beede271f89e TEXT;
  p_Configuration_beede271f89e TEXT;
  p_ID_beede271f89e UUID;
BEGIN
  p_DisplayName_beede271f89e := 'Contract Number';
  p_Description_beede271f89e := 'CTR-000001, minted by spAssignNextContractNumber from the seq_ContractNumber database SEQUENCE. Unique. NULLABLE at the schema level because MJ cannot express ''NOT NULL, assigned by the server on insert'' -- ContractEntityServer.Save() is what guarantees every contract has one. Gaps are normal and are not to be ''fixed'': a save that fails after taking a number leaves one behind, and UQ_Contract_ContractNumber is what guarantees no two contracts share a number.';
  p_AutoUpdateDescription_beede271f89e := TRUE;
  p_IsPrimaryKey_beede271f89e := FALSE;
  p_IsUnique_beede271f89e := TRUE;
  p_Category_beede271f89e := 'Contract Details';
  p_ValueListType_beede271f89e := 'None';
  p_DefaultInView_beede271f89e := TRUE;
  p_DefaultColumnWidth_beede271f89e := 150;
  p_AllowUpdateAPI_beede271f89e := TRUE;
  p_AllowUpdateInView_beede271f89e := TRUE;
  p_IncludeInUserSearchAPI_beede271f89e := TRUE;
  p_FullTextSearchEnabled_beede271f89e := FALSE;
  p_IncludeInGeneratedForm_beede271f89e := TRUE;
  p_GeneratedFormSection_beede271f89e := 'Category';
  p_IsNameField_beede271f89e := TRUE;
  p_IncludeRelatedEntityNameFieldInBaseView_beede271f89e := FALSE;
  p_RelatedEntityDisplayType_beede271f89e := 'Search';
  p_AutoUpdateRelatedEntityInfo_beede271f89e := TRUE;
  p_ValuesToPackWithSchema_beede271f89e := 'Auto';
  p_Status_beede271f89e := 'Active';
  p_AutoUpdateIsNameField_beede271f89e := TRUE;
  p_AutoUpdateDefaultInView_beede271f89e := TRUE;
  p_AutoUpdateCategory_beede271f89e := TRUE;
  p_AutoUpdateDisplayName_beede271f89e := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_beede271f89e := FALSE;
  p_Encrypt_beede271f89e := FALSE;
  p_AllowDecryptInAPI_beede271f89e := FALSE;
  p_SendEncryptedValue_beede271f89e := FALSE;
  p_IsSoftPrimaryKey_beede271f89e := FALSE;
  p_IsSoftForeignKey_beede271f89e := FALSE;
  p_JSONTypeIsArray_beede271f89e := FALSE;
  p_UserSearchPredicateAPI_beede271f89e := 'Exact';
  p_AutoUpdateUserSearchPredicate_beede271f89e := TRUE;
  p_AutoUpdateFullTextSearch_beede271f89e := TRUE;
  p_AutoUpdateExtendedType_beede271f89e := TRUE;
  p_IsComputed_beede271f89e := FALSE;
  p_ID_beede271f89e := '8677055B-2482-4250-98C1-AFC3DAE57393';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_beede271f89e,
    'Description', p_Description_beede271f89e,
    'AutoUpdateDescription', p_AutoUpdateDescription_beede271f89e,
    'IsPrimaryKey', p_IsPrimaryKey_beede271f89e,
    'IsUnique', p_IsUnique_beede271f89e,
    'Category', p_Category_beede271f89e,
    'ValueListType', p_ValueListType_beede271f89e,
    'ExtendedType', p_ExtendedType_beede271f89e,
    'CodeType', p_CodeType_beede271f89e,
    'DefaultInView', p_DefaultInView_beede271f89e,
    'ViewCellTemplate', p_ViewCellTemplate_beede271f89e,
    'DefaultColumnWidth', p_DefaultColumnWidth_beede271f89e,
    'AllowUpdateAPI', p_AllowUpdateAPI_beede271f89e,
    'AllowUpdateInView', p_AllowUpdateInView_beede271f89e,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_beede271f89e,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_beede271f89e,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_beede271f89e,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_beede271f89e,
    'GeneratedFormSection', p_GeneratedFormSection_beede271f89e,
    'IsNameField', p_IsNameField_beede271f89e,
    'RelatedEntityID', p_RelatedEntityID_beede271f89e,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_beede271f89e,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_beede271f89e,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_beede271f89e,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_beede271f89e,
    'EntityIDFieldName', p_EntityIDFieldName_beede271f89e,
    'ScopeDefault', p_ScopeDefault_beede271f89e,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_beede271f89e,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_beede271f89e,
    'Status', p_Status_beede271f89e,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_beede271f89e,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_beede271f89e,
    'AutoUpdateCategory', p_AutoUpdateCategory_beede271f89e,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_beede271f89e,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_beede271f89e,
    'Encrypt', p_Encrypt_beede271f89e,
    'EncryptionKeyID', p_EncryptionKeyID_beede271f89e,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_beede271f89e,
    'SendEncryptedValue', p_SendEncryptedValue_beede271f89e,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_beede271f89e,
    'IsSoftForeignKey', p_IsSoftForeignKey_beede271f89e,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_beede271f89e,
    'JSONType', p_JSONType_beede271f89e,
    'JSONTypeIsArray', p_JSONTypeIsArray_beede271f89e,
    'JSONTypeDefinition', p_JSONTypeDefinition_beede271f89e,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_beede271f89e,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_beede271f89e,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_beede271f89e,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_beede271f89e,
    'IsComputed', p_IsComputed_beede271f89e
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_beede271f89e,
    'Configuration', p_Configuration_beede271f89e,
    'ID', p_ID_beede271f89e
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_beede271f89e, p_Description := p_Description_beede271f89e, p_AutoUpdateDescription := p_AutoUpdateDescription_beede271f89e, p_IsPrimaryKey := p_IsPrimaryKey_beede271f89e, p_IsUnique := p_IsUnique_beede271f89e, p_Category := p_Category_beede271f89e, p_ValueListType := p_ValueListType_beede271f89e, p_ExtendedType := p_ExtendedType_beede271f89e, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_beede271f89e, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_beede271f89e, p_ViewCellTemplate := p_ViewCellTemplate_beede271f89e, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_beede271f89e, p_AllowUpdateAPI := p_AllowUpdateAPI_beede271f89e, p_AllowUpdateInView := p_AllowUpdateInView_beede271f89e, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_beede271f89e, p_FullTextSearchEnabled := p_FullTextSearchEnabled_beede271f89e, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_beede271f89e, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_beede271f89e, p_GeneratedFormSection := p_GeneratedFormSection_beede271f89e, p_IsNameField := p_IsNameField_beede271f89e, p_RelatedEntityID := p_RelatedEntityID_beede271f89e, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_beede271f89e, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_beede271f89e, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_beede271f89e, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_beede271f89e, p_EntityIDFieldName := p_EntityIDFieldName_beede271f89e, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_beede271f89e, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_beede271f89e, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_beede271f89e, p_Status := p_Status_beede271f89e, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_beede271f89e, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_beede271f89e, p_AutoUpdateCategory := p_AutoUpdateCategory_beede271f89e, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_beede271f89e, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_beede271f89e, p_Encrypt := p_Encrypt_beede271f89e, p_EncryptionKeyID := p_EncryptionKeyID_beede271f89e, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_beede271f89e, p_SendEncryptedValue := p_SendEncryptedValue_beede271f89e, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_beede271f89e, p_IsSoftForeignKey := p_IsSoftForeignKey_beede271f89e, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_beede271f89e, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_beede271f89e, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_beede271f89e, p_JSONTypeDefinition := p_JSONTypeDefinition_beede271f89e, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_beede271f89e, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_beede271f89e, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_beede271f89e, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_beede271f89e, p_IsComputed := p_IsComputed_beede271f89e, p_EmbeddedRecord := p_EmbeddedRecord_beede271f89e, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_beede271f89e, p_Configuration_Clear := TRUE, p_ID := p_ID_beede271f89e);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_b48ee17bcf62 VARCHAR(255);
  p_Description_b48ee17bcf62 TEXT;
  p_AutoUpdateDescription_b48ee17bcf62 BOOLEAN;
  p_IsPrimaryKey_b48ee17bcf62 BOOLEAN;
  p_IsUnique_b48ee17bcf62 BOOLEAN;
  p_Category_b48ee17bcf62 VARCHAR(255);
  p_ValueListType_b48ee17bcf62 VARCHAR(20);
  p_ExtendedType_b48ee17bcf62 VARCHAR(50);
  p_CodeType_b48ee17bcf62 VARCHAR(50);
  p_DefaultInView_b48ee17bcf62 BOOLEAN;
  p_ViewCellTemplate_b48ee17bcf62 TEXT;
  p_DefaultColumnWidth_b48ee17bcf62 INTEGER;
  p_AllowUpdateAPI_b48ee17bcf62 BOOLEAN;
  p_AllowUpdateInView_b48ee17bcf62 BOOLEAN;
  p_IncludeInUserSearchAPI_b48ee17bcf62 BOOLEAN;
  p_FullTextSearchEnabled_b48ee17bcf62 BOOLEAN;
  p_UserSearchParamFormatAPI_b48ee17bcf62 VARCHAR(500);
  p_IncludeInGeneratedForm_b48ee17bcf62 BOOLEAN;
  p_GeneratedFormSection_b48ee17bcf62 VARCHAR(10);
  p_IsNameField_b48ee17bcf62 BOOLEAN;
  p_RelatedEntityID_b48ee17bcf62 UUID;
  p_RelatedEntityFieldName_b48ee17bcf62 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_b48ee17bcf62 BOOLEAN;
  p_RelatedEntityNameFieldMap_b48ee17bcf62 VARCHAR(255);
  p_RelatedEntityDisplayType_b48ee17bcf62 VARCHAR(20);
  p_EntityIDFieldName_b48ee17bcf62 VARCHAR(100);
  p_ScopeDefault_b48ee17bcf62 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_b48ee17bcf62 BOOLEAN;
  p_ValuesToPackWithSchema_b48ee17bcf62 VARCHAR(10);
  p_Status_b48ee17bcf62 VARCHAR(25);
  p_AutoUpdateIsNameField_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateDefaultInView_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateCategory_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateDisplayName_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_b48ee17bcf62 BOOLEAN;
  p_Encrypt_b48ee17bcf62 BOOLEAN;
  p_EncryptionKeyID_b48ee17bcf62 UUID;
  p_AllowDecryptInAPI_b48ee17bcf62 BOOLEAN;
  p_SendEncryptedValue_b48ee17bcf62 BOOLEAN;
  p_IsSoftPrimaryKey_b48ee17bcf62 BOOLEAN;
  p_IsSoftForeignKey_b48ee17bcf62 BOOLEAN;
  p_RelatedEntityJoinFields_b48ee17bcf62 TEXT;
  p_JSONType_b48ee17bcf62 VARCHAR(255);
  p_JSONTypeIsArray_b48ee17bcf62 BOOLEAN;
  p_JSONTypeDefinition_b48ee17bcf62 TEXT;
  p_UserSearchPredicateAPI_b48ee17bcf62 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateFullTextSearch_b48ee17bcf62 BOOLEAN;
  p_AutoUpdateExtendedType_b48ee17bcf62 BOOLEAN;
  p_IsComputed_b48ee17bcf62 BOOLEAN;
  p_EmbeddedRecord_b48ee17bcf62 TEXT;
  p_Configuration_b48ee17bcf62 TEXT;
  p_ID_b48ee17bcf62 UUID;
BEGIN
  p_DisplayName_b48ee17bcf62 := 'ID';
  p_AutoUpdateDescription_b48ee17bcf62 := TRUE;
  p_IsPrimaryKey_b48ee17bcf62 := TRUE;
  p_IsUnique_b48ee17bcf62 := TRUE;
  p_Category_b48ee17bcf62 := 'System Metadata';
  p_ValueListType_b48ee17bcf62 := 'None';
  p_DefaultInView_b48ee17bcf62 := FALSE;
  p_DefaultColumnWidth_b48ee17bcf62 := 150;
  p_AllowUpdateAPI_b48ee17bcf62 := FALSE;
  p_AllowUpdateInView_b48ee17bcf62 := TRUE;
  p_IncludeInUserSearchAPI_b48ee17bcf62 := FALSE;
  p_FullTextSearchEnabled_b48ee17bcf62 := FALSE;
  p_IncludeInGeneratedForm_b48ee17bcf62 := TRUE;
  p_GeneratedFormSection_b48ee17bcf62 := 'Category';
  p_IsNameField_b48ee17bcf62 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_b48ee17bcf62 := FALSE;
  p_RelatedEntityDisplayType_b48ee17bcf62 := 'Search';
  p_AutoUpdateRelatedEntityInfo_b48ee17bcf62 := TRUE;
  p_ValuesToPackWithSchema_b48ee17bcf62 := 'Auto';
  p_Status_b48ee17bcf62 := 'Active';
  p_AutoUpdateIsNameField_b48ee17bcf62 := TRUE;
  p_AutoUpdateDefaultInView_b48ee17bcf62 := TRUE;
  p_AutoUpdateCategory_b48ee17bcf62 := TRUE;
  p_AutoUpdateDisplayName_b48ee17bcf62 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_b48ee17bcf62 := FALSE;
  p_Encrypt_b48ee17bcf62 := FALSE;
  p_AllowDecryptInAPI_b48ee17bcf62 := FALSE;
  p_SendEncryptedValue_b48ee17bcf62 := FALSE;
  p_IsSoftPrimaryKey_b48ee17bcf62 := FALSE;
  p_IsSoftForeignKey_b48ee17bcf62 := FALSE;
  p_JSONTypeIsArray_b48ee17bcf62 := FALSE;
  p_UserSearchPredicateAPI_b48ee17bcf62 := 'Contains';
  p_AutoUpdateUserSearchPredicate_b48ee17bcf62 := TRUE;
  p_AutoUpdateFullTextSearch_b48ee17bcf62 := TRUE;
  p_AutoUpdateExtendedType_b48ee17bcf62 := TRUE;
  p_IsComputed_b48ee17bcf62 := FALSE;
  p_ID_b48ee17bcf62 := '04E8AA9D-C2DC-489D-B081-75C4E6DDFA6B';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_b48ee17bcf62,
    'Description', p_Description_b48ee17bcf62,
    'AutoUpdateDescription', p_AutoUpdateDescription_b48ee17bcf62,
    'IsPrimaryKey', p_IsPrimaryKey_b48ee17bcf62,
    'IsUnique', p_IsUnique_b48ee17bcf62,
    'Category', p_Category_b48ee17bcf62,
    'ValueListType', p_ValueListType_b48ee17bcf62,
    'ExtendedType', p_ExtendedType_b48ee17bcf62,
    'CodeType', p_CodeType_b48ee17bcf62,
    'DefaultInView', p_DefaultInView_b48ee17bcf62,
    'ViewCellTemplate', p_ViewCellTemplate_b48ee17bcf62,
    'DefaultColumnWidth', p_DefaultColumnWidth_b48ee17bcf62,
    'AllowUpdateAPI', p_AllowUpdateAPI_b48ee17bcf62,
    'AllowUpdateInView', p_AllowUpdateInView_b48ee17bcf62,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_b48ee17bcf62,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_b48ee17bcf62,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_b48ee17bcf62,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_b48ee17bcf62,
    'GeneratedFormSection', p_GeneratedFormSection_b48ee17bcf62,
    'IsNameField', p_IsNameField_b48ee17bcf62,
    'RelatedEntityID', p_RelatedEntityID_b48ee17bcf62,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_b48ee17bcf62,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_b48ee17bcf62,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_b48ee17bcf62,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_b48ee17bcf62,
    'EntityIDFieldName', p_EntityIDFieldName_b48ee17bcf62,
    'ScopeDefault', p_ScopeDefault_b48ee17bcf62,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_b48ee17bcf62,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_b48ee17bcf62,
    'Status', p_Status_b48ee17bcf62,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_b48ee17bcf62,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_b48ee17bcf62,
    'AutoUpdateCategory', p_AutoUpdateCategory_b48ee17bcf62,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_b48ee17bcf62,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_b48ee17bcf62,
    'Encrypt', p_Encrypt_b48ee17bcf62,
    'EncryptionKeyID', p_EncryptionKeyID_b48ee17bcf62,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_b48ee17bcf62,
    'SendEncryptedValue', p_SendEncryptedValue_b48ee17bcf62,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_b48ee17bcf62,
    'IsSoftForeignKey', p_IsSoftForeignKey_b48ee17bcf62,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_b48ee17bcf62,
    'JSONType', p_JSONType_b48ee17bcf62,
    'JSONTypeIsArray', p_JSONTypeIsArray_b48ee17bcf62,
    'JSONTypeDefinition', p_JSONTypeDefinition_b48ee17bcf62,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_b48ee17bcf62,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_b48ee17bcf62,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_b48ee17bcf62,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_b48ee17bcf62,
    'IsComputed', p_IsComputed_b48ee17bcf62
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_b48ee17bcf62,
    'Configuration', p_Configuration_b48ee17bcf62,
    'ID', p_ID_b48ee17bcf62
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_b48ee17bcf62, p_Description := p_Description_b48ee17bcf62, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_b48ee17bcf62, p_IsPrimaryKey := p_IsPrimaryKey_b48ee17bcf62, p_IsUnique := p_IsUnique_b48ee17bcf62, p_Category := p_Category_b48ee17bcf62, p_ValueListType := p_ValueListType_b48ee17bcf62, p_ExtendedType := p_ExtendedType_b48ee17bcf62, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_b48ee17bcf62, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_b48ee17bcf62, p_ViewCellTemplate := p_ViewCellTemplate_b48ee17bcf62, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_b48ee17bcf62, p_AllowUpdateAPI := p_AllowUpdateAPI_b48ee17bcf62, p_AllowUpdateInView := p_AllowUpdateInView_b48ee17bcf62, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_b48ee17bcf62, p_FullTextSearchEnabled := p_FullTextSearchEnabled_b48ee17bcf62, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_b48ee17bcf62, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_b48ee17bcf62, p_GeneratedFormSection := p_GeneratedFormSection_b48ee17bcf62, p_IsNameField := p_IsNameField_b48ee17bcf62, p_RelatedEntityID := p_RelatedEntityID_b48ee17bcf62, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_b48ee17bcf62, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_b48ee17bcf62, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_b48ee17bcf62, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_b48ee17bcf62, p_EntityIDFieldName := p_EntityIDFieldName_b48ee17bcf62, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_b48ee17bcf62, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_b48ee17bcf62, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_b48ee17bcf62, p_Status := p_Status_b48ee17bcf62, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_b48ee17bcf62, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_b48ee17bcf62, p_AutoUpdateCategory := p_AutoUpdateCategory_b48ee17bcf62, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_b48ee17bcf62, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_b48ee17bcf62, p_Encrypt := p_Encrypt_b48ee17bcf62, p_EncryptionKeyID := p_EncryptionKeyID_b48ee17bcf62, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_b48ee17bcf62, p_SendEncryptedValue := p_SendEncryptedValue_b48ee17bcf62, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_b48ee17bcf62, p_IsSoftForeignKey := p_IsSoftForeignKey_b48ee17bcf62, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_b48ee17bcf62, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_b48ee17bcf62, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_b48ee17bcf62, p_JSONTypeDefinition := p_JSONTypeDefinition_b48ee17bcf62, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_b48ee17bcf62, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_b48ee17bcf62, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_b48ee17bcf62, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_b48ee17bcf62, p_IsComputed := p_IsComputed_b48ee17bcf62, p_EmbeddedRecord := p_EmbeddedRecord_b48ee17bcf62, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_b48ee17bcf62, p_Configuration_Clear := TRUE, p_ID := p_ID_b48ee17bcf62);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_dfa7ac97e9a1 VARCHAR(255);
  p_Description_dfa7ac97e9a1 TEXT;
  p_AutoUpdateDescription_dfa7ac97e9a1 BOOLEAN;
  p_IsPrimaryKey_dfa7ac97e9a1 BOOLEAN;
  p_IsUnique_dfa7ac97e9a1 BOOLEAN;
  p_Category_dfa7ac97e9a1 VARCHAR(255);
  p_ValueListType_dfa7ac97e9a1 VARCHAR(20);
  p_ExtendedType_dfa7ac97e9a1 VARCHAR(50);
  p_CodeType_dfa7ac97e9a1 VARCHAR(50);
  p_DefaultInView_dfa7ac97e9a1 BOOLEAN;
  p_ViewCellTemplate_dfa7ac97e9a1 TEXT;
  p_DefaultColumnWidth_dfa7ac97e9a1 INTEGER;
  p_AllowUpdateAPI_dfa7ac97e9a1 BOOLEAN;
  p_AllowUpdateInView_dfa7ac97e9a1 BOOLEAN;
  p_IncludeInUserSearchAPI_dfa7ac97e9a1 BOOLEAN;
  p_FullTextSearchEnabled_dfa7ac97e9a1 BOOLEAN;
  p_UserSearchParamFormatAPI_dfa7ac97e9a1 VARCHAR(500);
  p_IncludeInGeneratedForm_dfa7ac97e9a1 BOOLEAN;
  p_GeneratedFormSection_dfa7ac97e9a1 VARCHAR(10);
  p_IsNameField_dfa7ac97e9a1 BOOLEAN;
  p_RelatedEntityID_dfa7ac97e9a1 UUID;
  p_RelatedEntityFieldName_dfa7ac97e9a1 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_dfa7ac97e9a1 BOOLEAN;
  p_RelatedEntityNameFieldMap_dfa7ac97e9a1 VARCHAR(255);
  p_RelatedEntityDisplayType_dfa7ac97e9a1 VARCHAR(20);
  p_EntityIDFieldName_dfa7ac97e9a1 VARCHAR(100);
  p_ScopeDefault_dfa7ac97e9a1 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_dfa7ac97e9a1 BOOLEAN;
  p_ValuesToPackWithSchema_dfa7ac97e9a1 VARCHAR(10);
  p_Status_dfa7ac97e9a1 VARCHAR(25);
  p_AutoUpdateIsNameField_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateDefaultInView_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateCategory_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateDisplayName_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_dfa7ac97e9a1 BOOLEAN;
  p_Encrypt_dfa7ac97e9a1 BOOLEAN;
  p_EncryptionKeyID_dfa7ac97e9a1 UUID;
  p_AllowDecryptInAPI_dfa7ac97e9a1 BOOLEAN;
  p_SendEncryptedValue_dfa7ac97e9a1 BOOLEAN;
  p_IsSoftPrimaryKey_dfa7ac97e9a1 BOOLEAN;
  p_IsSoftForeignKey_dfa7ac97e9a1 BOOLEAN;
  p_RelatedEntityJoinFields_dfa7ac97e9a1 TEXT;
  p_JSONType_dfa7ac97e9a1 VARCHAR(255);
  p_JSONTypeIsArray_dfa7ac97e9a1 BOOLEAN;
  p_JSONTypeDefinition_dfa7ac97e9a1 TEXT;
  p_UserSearchPredicateAPI_dfa7ac97e9a1 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateFullTextSearch_dfa7ac97e9a1 BOOLEAN;
  p_AutoUpdateExtendedType_dfa7ac97e9a1 BOOLEAN;
  p_IsComputed_dfa7ac97e9a1 BOOLEAN;
  p_EmbeddedRecord_dfa7ac97e9a1 TEXT;
  p_Configuration_dfa7ac97e9a1 TEXT;
  p_ID_dfa7ac97e9a1 UUID;
BEGIN
  p_DisplayName_dfa7ac97e9a1 := 'Name';
  p_AutoUpdateDescription_dfa7ac97e9a1 := TRUE;
  p_IsPrimaryKey_dfa7ac97e9a1 := FALSE;
  p_IsUnique_dfa7ac97e9a1 := TRUE;
  p_Category_dfa7ac97e9a1 := 'Template Details';
  p_ValueListType_dfa7ac97e9a1 := 'None';
  p_DefaultInView_dfa7ac97e9a1 := TRUE;
  p_DefaultColumnWidth_dfa7ac97e9a1 := 150;
  p_AllowUpdateAPI_dfa7ac97e9a1 := TRUE;
  p_AllowUpdateInView_dfa7ac97e9a1 := TRUE;
  p_IncludeInUserSearchAPI_dfa7ac97e9a1 := TRUE;
  p_FullTextSearchEnabled_dfa7ac97e9a1 := FALSE;
  p_IncludeInGeneratedForm_dfa7ac97e9a1 := TRUE;
  p_GeneratedFormSection_dfa7ac97e9a1 := 'Category';
  p_IsNameField_dfa7ac97e9a1 := TRUE;
  p_IncludeRelatedEntityNameFieldInBaseView_dfa7ac97e9a1 := FALSE;
  p_RelatedEntityDisplayType_dfa7ac97e9a1 := 'Search';
  p_AutoUpdateRelatedEntityInfo_dfa7ac97e9a1 := TRUE;
  p_ValuesToPackWithSchema_dfa7ac97e9a1 := 'Auto';
  p_Status_dfa7ac97e9a1 := 'Active';
  p_AutoUpdateIsNameField_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateDefaultInView_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateCategory_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateDisplayName_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_dfa7ac97e9a1 := FALSE;
  p_Encrypt_dfa7ac97e9a1 := FALSE;
  p_AllowDecryptInAPI_dfa7ac97e9a1 := FALSE;
  p_SendEncryptedValue_dfa7ac97e9a1 := FALSE;
  p_IsSoftPrimaryKey_dfa7ac97e9a1 := FALSE;
  p_IsSoftForeignKey_dfa7ac97e9a1 := FALSE;
  p_JSONTypeIsArray_dfa7ac97e9a1 := FALSE;
  p_UserSearchPredicateAPI_dfa7ac97e9a1 := 'BeginsWith';
  p_AutoUpdateUserSearchPredicate_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateFullTextSearch_dfa7ac97e9a1 := TRUE;
  p_AutoUpdateExtendedType_dfa7ac97e9a1 := TRUE;
  p_IsComputed_dfa7ac97e9a1 := FALSE;
  p_ID_dfa7ac97e9a1 := '1FC39118-F7F8-4BA7-9940-F341E35F4FDB';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_dfa7ac97e9a1,
    'Description', p_Description_dfa7ac97e9a1,
    'AutoUpdateDescription', p_AutoUpdateDescription_dfa7ac97e9a1,
    'IsPrimaryKey', p_IsPrimaryKey_dfa7ac97e9a1,
    'IsUnique', p_IsUnique_dfa7ac97e9a1,
    'Category', p_Category_dfa7ac97e9a1,
    'ValueListType', p_ValueListType_dfa7ac97e9a1,
    'ExtendedType', p_ExtendedType_dfa7ac97e9a1,
    'CodeType', p_CodeType_dfa7ac97e9a1,
    'DefaultInView', p_DefaultInView_dfa7ac97e9a1,
    'ViewCellTemplate', p_ViewCellTemplate_dfa7ac97e9a1,
    'DefaultColumnWidth', p_DefaultColumnWidth_dfa7ac97e9a1,
    'AllowUpdateAPI', p_AllowUpdateAPI_dfa7ac97e9a1,
    'AllowUpdateInView', p_AllowUpdateInView_dfa7ac97e9a1,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_dfa7ac97e9a1,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_dfa7ac97e9a1,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_dfa7ac97e9a1,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_dfa7ac97e9a1,
    'GeneratedFormSection', p_GeneratedFormSection_dfa7ac97e9a1,
    'IsNameField', p_IsNameField_dfa7ac97e9a1,
    'RelatedEntityID', p_RelatedEntityID_dfa7ac97e9a1,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_dfa7ac97e9a1,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_dfa7ac97e9a1,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_dfa7ac97e9a1,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_dfa7ac97e9a1,
    'EntityIDFieldName', p_EntityIDFieldName_dfa7ac97e9a1,
    'ScopeDefault', p_ScopeDefault_dfa7ac97e9a1,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_dfa7ac97e9a1,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_dfa7ac97e9a1,
    'Status', p_Status_dfa7ac97e9a1,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_dfa7ac97e9a1,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_dfa7ac97e9a1,
    'AutoUpdateCategory', p_AutoUpdateCategory_dfa7ac97e9a1,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_dfa7ac97e9a1,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_dfa7ac97e9a1,
    'Encrypt', p_Encrypt_dfa7ac97e9a1,
    'EncryptionKeyID', p_EncryptionKeyID_dfa7ac97e9a1,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_dfa7ac97e9a1,
    'SendEncryptedValue', p_SendEncryptedValue_dfa7ac97e9a1,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_dfa7ac97e9a1,
    'IsSoftForeignKey', p_IsSoftForeignKey_dfa7ac97e9a1,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_dfa7ac97e9a1,
    'JSONType', p_JSONType_dfa7ac97e9a1,
    'JSONTypeIsArray', p_JSONTypeIsArray_dfa7ac97e9a1,
    'JSONTypeDefinition', p_JSONTypeDefinition_dfa7ac97e9a1,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_dfa7ac97e9a1,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_dfa7ac97e9a1,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_dfa7ac97e9a1,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_dfa7ac97e9a1,
    'IsComputed', p_IsComputed_dfa7ac97e9a1
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_dfa7ac97e9a1,
    'Configuration', p_Configuration_dfa7ac97e9a1,
    'ID', p_ID_dfa7ac97e9a1
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_dfa7ac97e9a1, p_Description := p_Description_dfa7ac97e9a1, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_dfa7ac97e9a1, p_IsPrimaryKey := p_IsPrimaryKey_dfa7ac97e9a1, p_IsUnique := p_IsUnique_dfa7ac97e9a1, p_Category := p_Category_dfa7ac97e9a1, p_ValueListType := p_ValueListType_dfa7ac97e9a1, p_ExtendedType := p_ExtendedType_dfa7ac97e9a1, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_dfa7ac97e9a1, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_dfa7ac97e9a1, p_ViewCellTemplate := p_ViewCellTemplate_dfa7ac97e9a1, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_dfa7ac97e9a1, p_AllowUpdateAPI := p_AllowUpdateAPI_dfa7ac97e9a1, p_AllowUpdateInView := p_AllowUpdateInView_dfa7ac97e9a1, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_dfa7ac97e9a1, p_FullTextSearchEnabled := p_FullTextSearchEnabled_dfa7ac97e9a1, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_dfa7ac97e9a1, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_dfa7ac97e9a1, p_GeneratedFormSection := p_GeneratedFormSection_dfa7ac97e9a1, p_IsNameField := p_IsNameField_dfa7ac97e9a1, p_RelatedEntityID := p_RelatedEntityID_dfa7ac97e9a1, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_dfa7ac97e9a1, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_dfa7ac97e9a1, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_dfa7ac97e9a1, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_dfa7ac97e9a1, p_EntityIDFieldName := p_EntityIDFieldName_dfa7ac97e9a1, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_dfa7ac97e9a1, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_dfa7ac97e9a1, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_dfa7ac97e9a1, p_Status := p_Status_dfa7ac97e9a1, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_dfa7ac97e9a1, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_dfa7ac97e9a1, p_AutoUpdateCategory := p_AutoUpdateCategory_dfa7ac97e9a1, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_dfa7ac97e9a1, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_dfa7ac97e9a1, p_Encrypt := p_Encrypt_dfa7ac97e9a1, p_EncryptionKeyID := p_EncryptionKeyID_dfa7ac97e9a1, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_dfa7ac97e9a1, p_SendEncryptedValue := p_SendEncryptedValue_dfa7ac97e9a1, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_dfa7ac97e9a1, p_IsSoftForeignKey := p_IsSoftForeignKey_dfa7ac97e9a1, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_dfa7ac97e9a1, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_dfa7ac97e9a1, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_dfa7ac97e9a1, p_JSONTypeDefinition := p_JSONTypeDefinition_dfa7ac97e9a1, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_dfa7ac97e9a1, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_dfa7ac97e9a1, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_dfa7ac97e9a1, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_dfa7ac97e9a1, p_IsComputed := p_IsComputed_dfa7ac97e9a1, p_EmbeddedRecord := p_EmbeddedRecord_dfa7ac97e9a1, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_dfa7ac97e9a1, p_Configuration_Clear := TRUE, p_ID := p_ID_dfa7ac97e9a1);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_58a77dcdb955 VARCHAR(255);
  p_Description_58a77dcdb955 TEXT;
  p_AutoUpdateDescription_58a77dcdb955 BOOLEAN;
  p_IsPrimaryKey_58a77dcdb955 BOOLEAN;
  p_IsUnique_58a77dcdb955 BOOLEAN;
  p_Category_58a77dcdb955 VARCHAR(255);
  p_ValueListType_58a77dcdb955 VARCHAR(20);
  p_ExtendedType_58a77dcdb955 VARCHAR(50);
  p_CodeType_58a77dcdb955 VARCHAR(50);
  p_DefaultInView_58a77dcdb955 BOOLEAN;
  p_ViewCellTemplate_58a77dcdb955 TEXT;
  p_DefaultColumnWidth_58a77dcdb955 INTEGER;
  p_AllowUpdateAPI_58a77dcdb955 BOOLEAN;
  p_AllowUpdateInView_58a77dcdb955 BOOLEAN;
  p_IncludeInUserSearchAPI_58a77dcdb955 BOOLEAN;
  p_FullTextSearchEnabled_58a77dcdb955 BOOLEAN;
  p_UserSearchParamFormatAPI_58a77dcdb955 VARCHAR(500);
  p_IncludeInGeneratedForm_58a77dcdb955 BOOLEAN;
  p_GeneratedFormSection_58a77dcdb955 VARCHAR(10);
  p_IsNameField_58a77dcdb955 BOOLEAN;
  p_RelatedEntityID_58a77dcdb955 UUID;
  p_RelatedEntityFieldName_58a77dcdb955 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_58a77dcdb955 BOOLEAN;
  p_RelatedEntityNameFieldMap_58a77dcdb955 VARCHAR(255);
  p_RelatedEntityDisplayType_58a77dcdb955 VARCHAR(20);
  p_EntityIDFieldName_58a77dcdb955 VARCHAR(100);
  p_ScopeDefault_58a77dcdb955 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_58a77dcdb955 BOOLEAN;
  p_ValuesToPackWithSchema_58a77dcdb955 VARCHAR(10);
  p_Status_58a77dcdb955 VARCHAR(25);
  p_AutoUpdateIsNameField_58a77dcdb955 BOOLEAN;
  p_AutoUpdateDefaultInView_58a77dcdb955 BOOLEAN;
  p_AutoUpdateCategory_58a77dcdb955 BOOLEAN;
  p_AutoUpdateDisplayName_58a77dcdb955 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_58a77dcdb955 BOOLEAN;
  p_Encrypt_58a77dcdb955 BOOLEAN;
  p_EncryptionKeyID_58a77dcdb955 UUID;
  p_AllowDecryptInAPI_58a77dcdb955 BOOLEAN;
  p_SendEncryptedValue_58a77dcdb955 BOOLEAN;
  p_IsSoftPrimaryKey_58a77dcdb955 BOOLEAN;
  p_IsSoftForeignKey_58a77dcdb955 BOOLEAN;
  p_RelatedEntityJoinFields_58a77dcdb955 TEXT;
  p_JSONType_58a77dcdb955 VARCHAR(255);
  p_JSONTypeIsArray_58a77dcdb955 BOOLEAN;
  p_JSONTypeDefinition_58a77dcdb955 TEXT;
  p_UserSearchPredicateAPI_58a77dcdb955 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_58a77dcdb955 BOOLEAN;
  p_AutoUpdateFullTextSearch_58a77dcdb955 BOOLEAN;
  p_AutoUpdateExtendedType_58a77dcdb955 BOOLEAN;
  p_IsComputed_58a77dcdb955 BOOLEAN;
  p_EmbeddedRecord_58a77dcdb955 TEXT;
  p_Configuration_58a77dcdb955 TEXT;
  p_ID_58a77dcdb955 UUID;
BEGIN
  p_DisplayName_58a77dcdb955 := 'Version Label';
  p_Description_58a77dcdb955 := 'The version the document names itself, e.g. "v6". Free text, because it is the documents own label rather than something we derive.';
  p_AutoUpdateDescription_58a77dcdb955 := TRUE;
  p_IsPrimaryKey_58a77dcdb955 := FALSE;
  p_IsUnique_58a77dcdb955 := FALSE;
  p_Category_58a77dcdb955 := 'Template Details';
  p_ValueListType_58a77dcdb955 := 'None';
  p_DefaultInView_58a77dcdb955 := TRUE;
  p_DefaultColumnWidth_58a77dcdb955 := 150;
  p_AllowUpdateAPI_58a77dcdb955 := TRUE;
  p_AllowUpdateInView_58a77dcdb955 := TRUE;
  p_IncludeInUserSearchAPI_58a77dcdb955 := TRUE;
  p_FullTextSearchEnabled_58a77dcdb955 := FALSE;
  p_IncludeInGeneratedForm_58a77dcdb955 := TRUE;
  p_GeneratedFormSection_58a77dcdb955 := 'Category';
  p_IsNameField_58a77dcdb955 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_58a77dcdb955 := FALSE;
  p_RelatedEntityDisplayType_58a77dcdb955 := 'Search';
  p_AutoUpdateRelatedEntityInfo_58a77dcdb955 := TRUE;
  p_ValuesToPackWithSchema_58a77dcdb955 := 'Auto';
  p_Status_58a77dcdb955 := 'Active';
  p_AutoUpdateIsNameField_58a77dcdb955 := TRUE;
  p_AutoUpdateDefaultInView_58a77dcdb955 := TRUE;
  p_AutoUpdateCategory_58a77dcdb955 := TRUE;
  p_AutoUpdateDisplayName_58a77dcdb955 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_58a77dcdb955 := FALSE;
  p_Encrypt_58a77dcdb955 := FALSE;
  p_AllowDecryptInAPI_58a77dcdb955 := FALSE;
  p_SendEncryptedValue_58a77dcdb955 := FALSE;
  p_IsSoftPrimaryKey_58a77dcdb955 := FALSE;
  p_IsSoftForeignKey_58a77dcdb955 := FALSE;
  p_JSONTypeIsArray_58a77dcdb955 := FALSE;
  p_UserSearchPredicateAPI_58a77dcdb955 := 'Exact';
  p_AutoUpdateUserSearchPredicate_58a77dcdb955 := TRUE;
  p_AutoUpdateFullTextSearch_58a77dcdb955 := TRUE;
  p_AutoUpdateExtendedType_58a77dcdb955 := TRUE;
  p_IsComputed_58a77dcdb955 := FALSE;
  p_ID_58a77dcdb955 := 'D4E48FFF-2F10-4E2E-A036-4D98BDAFCA99';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_58a77dcdb955,
    'Description', p_Description_58a77dcdb955,
    'AutoUpdateDescription', p_AutoUpdateDescription_58a77dcdb955,
    'IsPrimaryKey', p_IsPrimaryKey_58a77dcdb955,
    'IsUnique', p_IsUnique_58a77dcdb955,
    'Category', p_Category_58a77dcdb955,
    'ValueListType', p_ValueListType_58a77dcdb955,
    'ExtendedType', p_ExtendedType_58a77dcdb955,
    'CodeType', p_CodeType_58a77dcdb955,
    'DefaultInView', p_DefaultInView_58a77dcdb955,
    'ViewCellTemplate', p_ViewCellTemplate_58a77dcdb955,
    'DefaultColumnWidth', p_DefaultColumnWidth_58a77dcdb955,
    'AllowUpdateAPI', p_AllowUpdateAPI_58a77dcdb955,
    'AllowUpdateInView', p_AllowUpdateInView_58a77dcdb955,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_58a77dcdb955,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_58a77dcdb955,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_58a77dcdb955,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_58a77dcdb955,
    'GeneratedFormSection', p_GeneratedFormSection_58a77dcdb955,
    'IsNameField', p_IsNameField_58a77dcdb955,
    'RelatedEntityID', p_RelatedEntityID_58a77dcdb955,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_58a77dcdb955,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_58a77dcdb955,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_58a77dcdb955,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_58a77dcdb955,
    'EntityIDFieldName', p_EntityIDFieldName_58a77dcdb955,
    'ScopeDefault', p_ScopeDefault_58a77dcdb955,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_58a77dcdb955,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_58a77dcdb955,
    'Status', p_Status_58a77dcdb955,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_58a77dcdb955,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_58a77dcdb955,
    'AutoUpdateCategory', p_AutoUpdateCategory_58a77dcdb955,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_58a77dcdb955,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_58a77dcdb955,
    'Encrypt', p_Encrypt_58a77dcdb955,
    'EncryptionKeyID', p_EncryptionKeyID_58a77dcdb955,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_58a77dcdb955,
    'SendEncryptedValue', p_SendEncryptedValue_58a77dcdb955,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_58a77dcdb955,
    'IsSoftForeignKey', p_IsSoftForeignKey_58a77dcdb955,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_58a77dcdb955,
    'JSONType', p_JSONType_58a77dcdb955,
    'JSONTypeIsArray', p_JSONTypeIsArray_58a77dcdb955,
    'JSONTypeDefinition', p_JSONTypeDefinition_58a77dcdb955,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_58a77dcdb955,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_58a77dcdb955,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_58a77dcdb955,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_58a77dcdb955,
    'IsComputed', p_IsComputed_58a77dcdb955
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_58a77dcdb955,
    'Configuration', p_Configuration_58a77dcdb955,
    'ID', p_ID_58a77dcdb955
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_58a77dcdb955, p_Description := p_Description_58a77dcdb955, p_AutoUpdateDescription := p_AutoUpdateDescription_58a77dcdb955, p_IsPrimaryKey := p_IsPrimaryKey_58a77dcdb955, p_IsUnique := p_IsUnique_58a77dcdb955, p_Category := p_Category_58a77dcdb955, p_ValueListType := p_ValueListType_58a77dcdb955, p_ExtendedType := p_ExtendedType_58a77dcdb955, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_58a77dcdb955, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_58a77dcdb955, p_ViewCellTemplate := p_ViewCellTemplate_58a77dcdb955, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_58a77dcdb955, p_AllowUpdateAPI := p_AllowUpdateAPI_58a77dcdb955, p_AllowUpdateInView := p_AllowUpdateInView_58a77dcdb955, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_58a77dcdb955, p_FullTextSearchEnabled := p_FullTextSearchEnabled_58a77dcdb955, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_58a77dcdb955, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_58a77dcdb955, p_GeneratedFormSection := p_GeneratedFormSection_58a77dcdb955, p_IsNameField := p_IsNameField_58a77dcdb955, p_RelatedEntityID := p_RelatedEntityID_58a77dcdb955, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_58a77dcdb955, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_58a77dcdb955, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_58a77dcdb955, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_58a77dcdb955, p_EntityIDFieldName := p_EntityIDFieldName_58a77dcdb955, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_58a77dcdb955, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_58a77dcdb955, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_58a77dcdb955, p_Status := p_Status_58a77dcdb955, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_58a77dcdb955, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_58a77dcdb955, p_AutoUpdateCategory := p_AutoUpdateCategory_58a77dcdb955, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_58a77dcdb955, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_58a77dcdb955, p_Encrypt := p_Encrypt_58a77dcdb955, p_EncryptionKeyID := p_EncryptionKeyID_58a77dcdb955, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_58a77dcdb955, p_SendEncryptedValue := p_SendEncryptedValue_58a77dcdb955, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_58a77dcdb955, p_IsSoftForeignKey := p_IsSoftForeignKey_58a77dcdb955, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_58a77dcdb955, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_58a77dcdb955, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_58a77dcdb955, p_JSONTypeDefinition := p_JSONTypeDefinition_58a77dcdb955, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_58a77dcdb955, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_58a77dcdb955, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_58a77dcdb955, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_58a77dcdb955, p_IsComputed := p_IsComputed_58a77dcdb955, p_EmbeddedRecord := p_EmbeddedRecord_58a77dcdb955, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_58a77dcdb955, p_Configuration_Clear := TRUE, p_ID := p_ID_58a77dcdb955);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_fb3b09c79250 VARCHAR(255);
  p_Description_fb3b09c79250 TEXT;
  p_AutoUpdateDescription_fb3b09c79250 BOOLEAN;
  p_IsPrimaryKey_fb3b09c79250 BOOLEAN;
  p_IsUnique_fb3b09c79250 BOOLEAN;
  p_Category_fb3b09c79250 VARCHAR(255);
  p_ValueListType_fb3b09c79250 VARCHAR(20);
  p_ExtendedType_fb3b09c79250 VARCHAR(50);
  p_CodeType_fb3b09c79250 VARCHAR(50);
  p_DefaultInView_fb3b09c79250 BOOLEAN;
  p_ViewCellTemplate_fb3b09c79250 TEXT;
  p_DefaultColumnWidth_fb3b09c79250 INTEGER;
  p_AllowUpdateAPI_fb3b09c79250 BOOLEAN;
  p_AllowUpdateInView_fb3b09c79250 BOOLEAN;
  p_IncludeInUserSearchAPI_fb3b09c79250 BOOLEAN;
  p_FullTextSearchEnabled_fb3b09c79250 BOOLEAN;
  p_UserSearchParamFormatAPI_fb3b09c79250 VARCHAR(500);
  p_IncludeInGeneratedForm_fb3b09c79250 BOOLEAN;
  p_GeneratedFormSection_fb3b09c79250 VARCHAR(10);
  p_IsNameField_fb3b09c79250 BOOLEAN;
  p_RelatedEntityID_fb3b09c79250 UUID;
  p_RelatedEntityFieldName_fb3b09c79250 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_fb3b09c79250 BOOLEAN;
  p_RelatedEntityNameFieldMap_fb3b09c79250 VARCHAR(255);
  p_RelatedEntityDisplayType_fb3b09c79250 VARCHAR(20);
  p_EntityIDFieldName_fb3b09c79250 VARCHAR(100);
  p_ScopeDefault_fb3b09c79250 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_fb3b09c79250 BOOLEAN;
  p_ValuesToPackWithSchema_fb3b09c79250 VARCHAR(10);
  p_Status_fb3b09c79250 VARCHAR(25);
  p_AutoUpdateIsNameField_fb3b09c79250 BOOLEAN;
  p_AutoUpdateDefaultInView_fb3b09c79250 BOOLEAN;
  p_AutoUpdateCategory_fb3b09c79250 BOOLEAN;
  p_AutoUpdateDisplayName_fb3b09c79250 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_fb3b09c79250 BOOLEAN;
  p_Encrypt_fb3b09c79250 BOOLEAN;
  p_EncryptionKeyID_fb3b09c79250 UUID;
  p_AllowDecryptInAPI_fb3b09c79250 BOOLEAN;
  p_SendEncryptedValue_fb3b09c79250 BOOLEAN;
  p_IsSoftPrimaryKey_fb3b09c79250 BOOLEAN;
  p_IsSoftForeignKey_fb3b09c79250 BOOLEAN;
  p_RelatedEntityJoinFields_fb3b09c79250 TEXT;
  p_JSONType_fb3b09c79250 VARCHAR(255);
  p_JSONTypeIsArray_fb3b09c79250 BOOLEAN;
  p_JSONTypeDefinition_fb3b09c79250 TEXT;
  p_UserSearchPredicateAPI_fb3b09c79250 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_fb3b09c79250 BOOLEAN;
  p_AutoUpdateFullTextSearch_fb3b09c79250 BOOLEAN;
  p_AutoUpdateExtendedType_fb3b09c79250 BOOLEAN;
  p_IsComputed_fb3b09c79250 BOOLEAN;
  p_EmbeddedRecord_fb3b09c79250 TEXT;
  p_Configuration_fb3b09c79250 TEXT;
  p_ID_fb3b09c79250 UUID;
BEGIN
  p_DisplayName_fb3b09c79250 := 'ID';
  p_AutoUpdateDescription_fb3b09c79250 := TRUE;
  p_IsPrimaryKey_fb3b09c79250 := TRUE;
  p_IsUnique_fb3b09c79250 := TRUE;
  p_Category_fb3b09c79250 := 'System Metadata';
  p_ValueListType_fb3b09c79250 := 'None';
  p_DefaultInView_fb3b09c79250 := FALSE;
  p_DefaultColumnWidth_fb3b09c79250 := 150;
  p_AllowUpdateAPI_fb3b09c79250 := FALSE;
  p_AllowUpdateInView_fb3b09c79250 := TRUE;
  p_IncludeInUserSearchAPI_fb3b09c79250 := FALSE;
  p_FullTextSearchEnabled_fb3b09c79250 := FALSE;
  p_IncludeInGeneratedForm_fb3b09c79250 := TRUE;
  p_GeneratedFormSection_fb3b09c79250 := 'Category';
  p_IsNameField_fb3b09c79250 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_fb3b09c79250 := FALSE;
  p_RelatedEntityDisplayType_fb3b09c79250 := 'Search';
  p_AutoUpdateRelatedEntityInfo_fb3b09c79250 := TRUE;
  p_ValuesToPackWithSchema_fb3b09c79250 := 'Auto';
  p_Status_fb3b09c79250 := 'Active';
  p_AutoUpdateIsNameField_fb3b09c79250 := TRUE;
  p_AutoUpdateDefaultInView_fb3b09c79250 := TRUE;
  p_AutoUpdateCategory_fb3b09c79250 := TRUE;
  p_AutoUpdateDisplayName_fb3b09c79250 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_fb3b09c79250 := FALSE;
  p_Encrypt_fb3b09c79250 := FALSE;
  p_AllowDecryptInAPI_fb3b09c79250 := FALSE;
  p_SendEncryptedValue_fb3b09c79250 := FALSE;
  p_IsSoftPrimaryKey_fb3b09c79250 := FALSE;
  p_IsSoftForeignKey_fb3b09c79250 := FALSE;
  p_JSONTypeIsArray_fb3b09c79250 := FALSE;
  p_UserSearchPredicateAPI_fb3b09c79250 := 'Contains';
  p_AutoUpdateUserSearchPredicate_fb3b09c79250 := TRUE;
  p_AutoUpdateFullTextSearch_fb3b09c79250 := TRUE;
  p_AutoUpdateExtendedType_fb3b09c79250 := TRUE;
  p_IsComputed_fb3b09c79250 := FALSE;
  p_ID_fb3b09c79250 := 'A8BF5461-4A41-4388-8761-50B79FC598B4';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_fb3b09c79250,
    'Description', p_Description_fb3b09c79250,
    'AutoUpdateDescription', p_AutoUpdateDescription_fb3b09c79250,
    'IsPrimaryKey', p_IsPrimaryKey_fb3b09c79250,
    'IsUnique', p_IsUnique_fb3b09c79250,
    'Category', p_Category_fb3b09c79250,
    'ValueListType', p_ValueListType_fb3b09c79250,
    'ExtendedType', p_ExtendedType_fb3b09c79250,
    'CodeType', p_CodeType_fb3b09c79250,
    'DefaultInView', p_DefaultInView_fb3b09c79250,
    'ViewCellTemplate', p_ViewCellTemplate_fb3b09c79250,
    'DefaultColumnWidth', p_DefaultColumnWidth_fb3b09c79250,
    'AllowUpdateAPI', p_AllowUpdateAPI_fb3b09c79250,
    'AllowUpdateInView', p_AllowUpdateInView_fb3b09c79250,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_fb3b09c79250,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_fb3b09c79250,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_fb3b09c79250,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_fb3b09c79250,
    'GeneratedFormSection', p_GeneratedFormSection_fb3b09c79250,
    'IsNameField', p_IsNameField_fb3b09c79250,
    'RelatedEntityID', p_RelatedEntityID_fb3b09c79250,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_fb3b09c79250,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_fb3b09c79250,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_fb3b09c79250,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_fb3b09c79250,
    'EntityIDFieldName', p_EntityIDFieldName_fb3b09c79250,
    'ScopeDefault', p_ScopeDefault_fb3b09c79250,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_fb3b09c79250,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_fb3b09c79250,
    'Status', p_Status_fb3b09c79250,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_fb3b09c79250,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_fb3b09c79250,
    'AutoUpdateCategory', p_AutoUpdateCategory_fb3b09c79250,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_fb3b09c79250,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_fb3b09c79250,
    'Encrypt', p_Encrypt_fb3b09c79250,
    'EncryptionKeyID', p_EncryptionKeyID_fb3b09c79250,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_fb3b09c79250,
    'SendEncryptedValue', p_SendEncryptedValue_fb3b09c79250,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_fb3b09c79250,
    'IsSoftForeignKey', p_IsSoftForeignKey_fb3b09c79250,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_fb3b09c79250,
    'JSONType', p_JSONType_fb3b09c79250,
    'JSONTypeIsArray', p_JSONTypeIsArray_fb3b09c79250,
    'JSONTypeDefinition', p_JSONTypeDefinition_fb3b09c79250,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_fb3b09c79250,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_fb3b09c79250,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_fb3b09c79250,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_fb3b09c79250,
    'IsComputed', p_IsComputed_fb3b09c79250
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_fb3b09c79250,
    'Configuration', p_Configuration_fb3b09c79250,
    'ID', p_ID_fb3b09c79250
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_fb3b09c79250, p_Description := p_Description_fb3b09c79250, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_fb3b09c79250, p_IsPrimaryKey := p_IsPrimaryKey_fb3b09c79250, p_IsUnique := p_IsUnique_fb3b09c79250, p_Category := p_Category_fb3b09c79250, p_ValueListType := p_ValueListType_fb3b09c79250, p_ExtendedType := p_ExtendedType_fb3b09c79250, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_fb3b09c79250, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_fb3b09c79250, p_ViewCellTemplate := p_ViewCellTemplate_fb3b09c79250, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_fb3b09c79250, p_AllowUpdateAPI := p_AllowUpdateAPI_fb3b09c79250, p_AllowUpdateInView := p_AllowUpdateInView_fb3b09c79250, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_fb3b09c79250, p_FullTextSearchEnabled := p_FullTextSearchEnabled_fb3b09c79250, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_fb3b09c79250, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_fb3b09c79250, p_GeneratedFormSection := p_GeneratedFormSection_fb3b09c79250, p_IsNameField := p_IsNameField_fb3b09c79250, p_RelatedEntityID := p_RelatedEntityID_fb3b09c79250, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_fb3b09c79250, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_fb3b09c79250, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_fb3b09c79250, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_fb3b09c79250, p_EntityIDFieldName := p_EntityIDFieldName_fb3b09c79250, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_fb3b09c79250, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_fb3b09c79250, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_fb3b09c79250, p_Status := p_Status_fb3b09c79250, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_fb3b09c79250, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_fb3b09c79250, p_AutoUpdateCategory := p_AutoUpdateCategory_fb3b09c79250, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_fb3b09c79250, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_fb3b09c79250, p_Encrypt := p_Encrypt_fb3b09c79250, p_EncryptionKeyID := p_EncryptionKeyID_fb3b09c79250, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_fb3b09c79250, p_SendEncryptedValue := p_SendEncryptedValue_fb3b09c79250, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_fb3b09c79250, p_IsSoftForeignKey := p_IsSoftForeignKey_fb3b09c79250, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_fb3b09c79250, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_fb3b09c79250, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_fb3b09c79250, p_JSONTypeDefinition := p_JSONTypeDefinition_fb3b09c79250, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_fb3b09c79250, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_fb3b09c79250, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_fb3b09c79250, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_fb3b09c79250, p_IsComputed := p_IsComputed_fb3b09c79250, p_EmbeddedRecord := p_EmbeddedRecord_fb3b09c79250, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_fb3b09c79250, p_Configuration_Clear := TRUE, p_ID := p_ID_fb3b09c79250);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_f01c50ccec9f VARCHAR(255);
  p_Description_f01c50ccec9f TEXT;
  p_AutoUpdateDescription_f01c50ccec9f BOOLEAN;
  p_IsPrimaryKey_f01c50ccec9f BOOLEAN;
  p_IsUnique_f01c50ccec9f BOOLEAN;
  p_Category_f01c50ccec9f VARCHAR(255);
  p_ValueListType_f01c50ccec9f VARCHAR(20);
  p_ExtendedType_f01c50ccec9f VARCHAR(50);
  p_CodeType_f01c50ccec9f VARCHAR(50);
  p_DefaultInView_f01c50ccec9f BOOLEAN;
  p_ViewCellTemplate_f01c50ccec9f TEXT;
  p_DefaultColumnWidth_f01c50ccec9f INTEGER;
  p_AllowUpdateAPI_f01c50ccec9f BOOLEAN;
  p_AllowUpdateInView_f01c50ccec9f BOOLEAN;
  p_IncludeInUserSearchAPI_f01c50ccec9f BOOLEAN;
  p_FullTextSearchEnabled_f01c50ccec9f BOOLEAN;
  p_UserSearchParamFormatAPI_f01c50ccec9f VARCHAR(500);
  p_IncludeInGeneratedForm_f01c50ccec9f BOOLEAN;
  p_GeneratedFormSection_f01c50ccec9f VARCHAR(10);
  p_IsNameField_f01c50ccec9f BOOLEAN;
  p_RelatedEntityID_f01c50ccec9f UUID;
  p_RelatedEntityFieldName_f01c50ccec9f VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_f01c50ccec9f BOOLEAN;
  p_RelatedEntityNameFieldMap_f01c50ccec9f VARCHAR(255);
  p_RelatedEntityDisplayType_f01c50ccec9f VARCHAR(20);
  p_EntityIDFieldName_f01c50ccec9f VARCHAR(100);
  p_ScopeDefault_f01c50ccec9f VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_f01c50ccec9f BOOLEAN;
  p_ValuesToPackWithSchema_f01c50ccec9f VARCHAR(10);
  p_Status_f01c50ccec9f VARCHAR(25);
  p_AutoUpdateIsNameField_f01c50ccec9f BOOLEAN;
  p_AutoUpdateDefaultInView_f01c50ccec9f BOOLEAN;
  p_AutoUpdateCategory_f01c50ccec9f BOOLEAN;
  p_AutoUpdateDisplayName_f01c50ccec9f BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_f01c50ccec9f BOOLEAN;
  p_Encrypt_f01c50ccec9f BOOLEAN;
  p_EncryptionKeyID_f01c50ccec9f UUID;
  p_AllowDecryptInAPI_f01c50ccec9f BOOLEAN;
  p_SendEncryptedValue_f01c50ccec9f BOOLEAN;
  p_IsSoftPrimaryKey_f01c50ccec9f BOOLEAN;
  p_IsSoftForeignKey_f01c50ccec9f BOOLEAN;
  p_RelatedEntityJoinFields_f01c50ccec9f TEXT;
  p_JSONType_f01c50ccec9f VARCHAR(255);
  p_JSONTypeIsArray_f01c50ccec9f BOOLEAN;
  p_JSONTypeDefinition_f01c50ccec9f TEXT;
  p_UserSearchPredicateAPI_f01c50ccec9f VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_f01c50ccec9f BOOLEAN;
  p_AutoUpdateFullTextSearch_f01c50ccec9f BOOLEAN;
  p_AutoUpdateExtendedType_f01c50ccec9f BOOLEAN;
  p_IsComputed_f01c50ccec9f BOOLEAN;
  p_EmbeddedRecord_f01c50ccec9f TEXT;
  p_Configuration_f01c50ccec9f TEXT;
  p_ID_f01c50ccec9f UUID;
BEGIN
  p_DisplayName_f01c50ccec9f := 'Default Auto Renew';
  p_Description_f01c50ccec9f := 'Seeds Contract.AutoRenew when a new contract picks this type. NULL means the type has no opinion and the contract is left alone — which is why this is nullable where the contract''s own column is not. Copied once, on an unsaved contract; never consulted afterwards and never enforced.';
  p_AutoUpdateDescription_f01c50ccec9f := TRUE;
  p_IsPrimaryKey_f01c50ccec9f := FALSE;
  p_IsUnique_f01c50ccec9f := FALSE;
  p_Category_f01c50ccec9f := 'Default Contract Terms';
  p_ValueListType_f01c50ccec9f := 'None';
  p_DefaultInView_f01c50ccec9f := FALSE;
  p_DefaultColumnWidth_f01c50ccec9f := 150;
  p_AllowUpdateAPI_f01c50ccec9f := TRUE;
  p_AllowUpdateInView_f01c50ccec9f := TRUE;
  p_IncludeInUserSearchAPI_f01c50ccec9f := FALSE;
  p_FullTextSearchEnabled_f01c50ccec9f := FALSE;
  p_IncludeInGeneratedForm_f01c50ccec9f := TRUE;
  p_GeneratedFormSection_f01c50ccec9f := 'Category';
  p_IsNameField_f01c50ccec9f := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_f01c50ccec9f := FALSE;
  p_RelatedEntityDisplayType_f01c50ccec9f := 'Search';
  p_AutoUpdateRelatedEntityInfo_f01c50ccec9f := TRUE;
  p_ValuesToPackWithSchema_f01c50ccec9f := 'Auto';
  p_Status_f01c50ccec9f := 'Active';
  p_AutoUpdateIsNameField_f01c50ccec9f := TRUE;
  p_AutoUpdateDefaultInView_f01c50ccec9f := TRUE;
  p_AutoUpdateCategory_f01c50ccec9f := TRUE;
  p_AutoUpdateDisplayName_f01c50ccec9f := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_f01c50ccec9f := TRUE;
  p_Encrypt_f01c50ccec9f := FALSE;
  p_AllowDecryptInAPI_f01c50ccec9f := FALSE;
  p_SendEncryptedValue_f01c50ccec9f := FALSE;
  p_IsSoftPrimaryKey_f01c50ccec9f := FALSE;
  p_IsSoftForeignKey_f01c50ccec9f := FALSE;
  p_JSONTypeIsArray_f01c50ccec9f := FALSE;
  p_UserSearchPredicateAPI_f01c50ccec9f := 'Contains';
  p_AutoUpdateUserSearchPredicate_f01c50ccec9f := TRUE;
  p_AutoUpdateFullTextSearch_f01c50ccec9f := TRUE;
  p_AutoUpdateExtendedType_f01c50ccec9f := TRUE;
  p_IsComputed_f01c50ccec9f := FALSE;
  p_ID_f01c50ccec9f := '0E84B4A9-1D67-4563-A5A0-EF4F75C80694';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_f01c50ccec9f,
    'Description', p_Description_f01c50ccec9f,
    'AutoUpdateDescription', p_AutoUpdateDescription_f01c50ccec9f,
    'IsPrimaryKey', p_IsPrimaryKey_f01c50ccec9f,
    'IsUnique', p_IsUnique_f01c50ccec9f,
    'Category', p_Category_f01c50ccec9f,
    'ValueListType', p_ValueListType_f01c50ccec9f,
    'ExtendedType', p_ExtendedType_f01c50ccec9f,
    'CodeType', p_CodeType_f01c50ccec9f,
    'DefaultInView', p_DefaultInView_f01c50ccec9f,
    'ViewCellTemplate', p_ViewCellTemplate_f01c50ccec9f,
    'DefaultColumnWidth', p_DefaultColumnWidth_f01c50ccec9f,
    'AllowUpdateAPI', p_AllowUpdateAPI_f01c50ccec9f,
    'AllowUpdateInView', p_AllowUpdateInView_f01c50ccec9f,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_f01c50ccec9f,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_f01c50ccec9f,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_f01c50ccec9f,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_f01c50ccec9f,
    'GeneratedFormSection', p_GeneratedFormSection_f01c50ccec9f,
    'IsNameField', p_IsNameField_f01c50ccec9f,
    'RelatedEntityID', p_RelatedEntityID_f01c50ccec9f,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_f01c50ccec9f,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_f01c50ccec9f,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_f01c50ccec9f,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_f01c50ccec9f,
    'EntityIDFieldName', p_EntityIDFieldName_f01c50ccec9f,
    'ScopeDefault', p_ScopeDefault_f01c50ccec9f,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_f01c50ccec9f,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_f01c50ccec9f,
    'Status', p_Status_f01c50ccec9f,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_f01c50ccec9f,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_f01c50ccec9f,
    'AutoUpdateCategory', p_AutoUpdateCategory_f01c50ccec9f,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_f01c50ccec9f,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_f01c50ccec9f,
    'Encrypt', p_Encrypt_f01c50ccec9f,
    'EncryptionKeyID', p_EncryptionKeyID_f01c50ccec9f,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_f01c50ccec9f,
    'SendEncryptedValue', p_SendEncryptedValue_f01c50ccec9f,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_f01c50ccec9f,
    'IsSoftForeignKey', p_IsSoftForeignKey_f01c50ccec9f,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_f01c50ccec9f,
    'JSONType', p_JSONType_f01c50ccec9f,
    'JSONTypeIsArray', p_JSONTypeIsArray_f01c50ccec9f,
    'JSONTypeDefinition', p_JSONTypeDefinition_f01c50ccec9f,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_f01c50ccec9f,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_f01c50ccec9f,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_f01c50ccec9f,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_f01c50ccec9f,
    'IsComputed', p_IsComputed_f01c50ccec9f
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_f01c50ccec9f,
    'Configuration', p_Configuration_f01c50ccec9f,
    'ID', p_ID_f01c50ccec9f
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_f01c50ccec9f, p_Description := p_Description_f01c50ccec9f, p_AutoUpdateDescription := p_AutoUpdateDescription_f01c50ccec9f, p_IsPrimaryKey := p_IsPrimaryKey_f01c50ccec9f, p_IsUnique := p_IsUnique_f01c50ccec9f, p_Category := p_Category_f01c50ccec9f, p_ValueListType := p_ValueListType_f01c50ccec9f, p_ExtendedType := p_ExtendedType_f01c50ccec9f, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_f01c50ccec9f, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_f01c50ccec9f, p_ViewCellTemplate := p_ViewCellTemplate_f01c50ccec9f, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_f01c50ccec9f, p_AllowUpdateAPI := p_AllowUpdateAPI_f01c50ccec9f, p_AllowUpdateInView := p_AllowUpdateInView_f01c50ccec9f, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_f01c50ccec9f, p_FullTextSearchEnabled := p_FullTextSearchEnabled_f01c50ccec9f, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_f01c50ccec9f, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_f01c50ccec9f, p_GeneratedFormSection := p_GeneratedFormSection_f01c50ccec9f, p_IsNameField := p_IsNameField_f01c50ccec9f, p_RelatedEntityID := p_RelatedEntityID_f01c50ccec9f, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_f01c50ccec9f, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_f01c50ccec9f, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_f01c50ccec9f, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_f01c50ccec9f, p_EntityIDFieldName := p_EntityIDFieldName_f01c50ccec9f, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_f01c50ccec9f, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_f01c50ccec9f, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_f01c50ccec9f, p_Status := p_Status_f01c50ccec9f, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_f01c50ccec9f, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_f01c50ccec9f, p_AutoUpdateCategory := p_AutoUpdateCategory_f01c50ccec9f, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_f01c50ccec9f, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_f01c50ccec9f, p_Encrypt := p_Encrypt_f01c50ccec9f, p_EncryptionKeyID := p_EncryptionKeyID_f01c50ccec9f, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_f01c50ccec9f, p_SendEncryptedValue := p_SendEncryptedValue_f01c50ccec9f, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_f01c50ccec9f, p_IsSoftForeignKey := p_IsSoftForeignKey_f01c50ccec9f, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_f01c50ccec9f, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_f01c50ccec9f, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_f01c50ccec9f, p_JSONTypeDefinition := p_JSONTypeDefinition_f01c50ccec9f, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_f01c50ccec9f, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_f01c50ccec9f, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_f01c50ccec9f, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_f01c50ccec9f, p_IsComputed := p_IsComputed_f01c50ccec9f, p_EmbeddedRecord := p_EmbeddedRecord_f01c50ccec9f, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_f01c50ccec9f, p_Configuration_Clear := TRUE, p_ID := p_ID_f01c50ccec9f);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_abe68a48cece VARCHAR(255);
  p_Description_abe68a48cece TEXT;
  p_AutoUpdateDescription_abe68a48cece BOOLEAN;
  p_IsPrimaryKey_abe68a48cece BOOLEAN;
  p_IsUnique_abe68a48cece BOOLEAN;
  p_Category_abe68a48cece VARCHAR(255);
  p_ValueListType_abe68a48cece VARCHAR(20);
  p_ExtendedType_abe68a48cece VARCHAR(50);
  p_CodeType_abe68a48cece VARCHAR(50);
  p_DefaultInView_abe68a48cece BOOLEAN;
  p_ViewCellTemplate_abe68a48cece TEXT;
  p_DefaultColumnWidth_abe68a48cece INTEGER;
  p_AllowUpdateAPI_abe68a48cece BOOLEAN;
  p_AllowUpdateInView_abe68a48cece BOOLEAN;
  p_IncludeInUserSearchAPI_abe68a48cece BOOLEAN;
  p_FullTextSearchEnabled_abe68a48cece BOOLEAN;
  p_UserSearchParamFormatAPI_abe68a48cece VARCHAR(500);
  p_IncludeInGeneratedForm_abe68a48cece BOOLEAN;
  p_GeneratedFormSection_abe68a48cece VARCHAR(10);
  p_IsNameField_abe68a48cece BOOLEAN;
  p_RelatedEntityID_abe68a48cece UUID;
  p_RelatedEntityFieldName_abe68a48cece VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_abe68a48cece BOOLEAN;
  p_RelatedEntityNameFieldMap_abe68a48cece VARCHAR(255);
  p_RelatedEntityDisplayType_abe68a48cece VARCHAR(20);
  p_EntityIDFieldName_abe68a48cece VARCHAR(100);
  p_ScopeDefault_abe68a48cece VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_abe68a48cece BOOLEAN;
  p_ValuesToPackWithSchema_abe68a48cece VARCHAR(10);
  p_Status_abe68a48cece VARCHAR(25);
  p_AutoUpdateIsNameField_abe68a48cece BOOLEAN;
  p_AutoUpdateDefaultInView_abe68a48cece BOOLEAN;
  p_AutoUpdateCategory_abe68a48cece BOOLEAN;
  p_AutoUpdateDisplayName_abe68a48cece BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_abe68a48cece BOOLEAN;
  p_Encrypt_abe68a48cece BOOLEAN;
  p_EncryptionKeyID_abe68a48cece UUID;
  p_AllowDecryptInAPI_abe68a48cece BOOLEAN;
  p_SendEncryptedValue_abe68a48cece BOOLEAN;
  p_IsSoftPrimaryKey_abe68a48cece BOOLEAN;
  p_IsSoftForeignKey_abe68a48cece BOOLEAN;
  p_RelatedEntityJoinFields_abe68a48cece TEXT;
  p_JSONType_abe68a48cece VARCHAR(255);
  p_JSONTypeIsArray_abe68a48cece BOOLEAN;
  p_JSONTypeDefinition_abe68a48cece TEXT;
  p_UserSearchPredicateAPI_abe68a48cece VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_abe68a48cece BOOLEAN;
  p_AutoUpdateFullTextSearch_abe68a48cece BOOLEAN;
  p_AutoUpdateExtendedType_abe68a48cece BOOLEAN;
  p_IsComputed_abe68a48cece BOOLEAN;
  p_EmbeddedRecord_abe68a48cece TEXT;
  p_Configuration_abe68a48cece TEXT;
  p_ID_abe68a48cece UUID;
BEGIN
  p_DisplayName_abe68a48cece := 'Default Renewal Notice Days';
  p_Description_abe68a48cece := 'Seeds Contract.RenewalNoticeDays — the notice WE owe the customer before a renewal price change. NULL means no default. A starting point for whoever reads the paper, not a term of any agreement.';
  p_AutoUpdateDescription_abe68a48cece := TRUE;
  p_IsPrimaryKey_abe68a48cece := FALSE;
  p_IsUnique_abe68a48cece := FALSE;
  p_Category_abe68a48cece := 'Default Contract Terms';
  p_ValueListType_abe68a48cece := 'None';
  p_DefaultInView_abe68a48cece := FALSE;
  p_DefaultColumnWidth_abe68a48cece := 50;
  p_AllowUpdateAPI_abe68a48cece := TRUE;
  p_AllowUpdateInView_abe68a48cece := TRUE;
  p_IncludeInUserSearchAPI_abe68a48cece := FALSE;
  p_FullTextSearchEnabled_abe68a48cece := FALSE;
  p_IncludeInGeneratedForm_abe68a48cece := TRUE;
  p_GeneratedFormSection_abe68a48cece := 'Category';
  p_IsNameField_abe68a48cece := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_abe68a48cece := FALSE;
  p_RelatedEntityDisplayType_abe68a48cece := 'Search';
  p_AutoUpdateRelatedEntityInfo_abe68a48cece := TRUE;
  p_ValuesToPackWithSchema_abe68a48cece := 'Auto';
  p_Status_abe68a48cece := 'Active';
  p_AutoUpdateIsNameField_abe68a48cece := TRUE;
  p_AutoUpdateDefaultInView_abe68a48cece := TRUE;
  p_AutoUpdateCategory_abe68a48cece := TRUE;
  p_AutoUpdateDisplayName_abe68a48cece := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_abe68a48cece := TRUE;
  p_Encrypt_abe68a48cece := FALSE;
  p_AllowDecryptInAPI_abe68a48cece := FALSE;
  p_SendEncryptedValue_abe68a48cece := FALSE;
  p_IsSoftPrimaryKey_abe68a48cece := FALSE;
  p_IsSoftForeignKey_abe68a48cece := FALSE;
  p_JSONTypeIsArray_abe68a48cece := FALSE;
  p_UserSearchPredicateAPI_abe68a48cece := 'Contains';
  p_AutoUpdateUserSearchPredicate_abe68a48cece := TRUE;
  p_AutoUpdateFullTextSearch_abe68a48cece := TRUE;
  p_AutoUpdateExtendedType_abe68a48cece := TRUE;
  p_IsComputed_abe68a48cece := FALSE;
  p_ID_abe68a48cece := 'E9A6CB34-2B1C-44A9-8260-D7E14C7B1F49';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_abe68a48cece,
    'Description', p_Description_abe68a48cece,
    'AutoUpdateDescription', p_AutoUpdateDescription_abe68a48cece,
    'IsPrimaryKey', p_IsPrimaryKey_abe68a48cece,
    'IsUnique', p_IsUnique_abe68a48cece,
    'Category', p_Category_abe68a48cece,
    'ValueListType', p_ValueListType_abe68a48cece,
    'ExtendedType', p_ExtendedType_abe68a48cece,
    'CodeType', p_CodeType_abe68a48cece,
    'DefaultInView', p_DefaultInView_abe68a48cece,
    'ViewCellTemplate', p_ViewCellTemplate_abe68a48cece,
    'DefaultColumnWidth', p_DefaultColumnWidth_abe68a48cece,
    'AllowUpdateAPI', p_AllowUpdateAPI_abe68a48cece,
    'AllowUpdateInView', p_AllowUpdateInView_abe68a48cece,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_abe68a48cece,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_abe68a48cece,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_abe68a48cece,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_abe68a48cece,
    'GeneratedFormSection', p_GeneratedFormSection_abe68a48cece,
    'IsNameField', p_IsNameField_abe68a48cece,
    'RelatedEntityID', p_RelatedEntityID_abe68a48cece,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_abe68a48cece,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_abe68a48cece,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_abe68a48cece,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_abe68a48cece,
    'EntityIDFieldName', p_EntityIDFieldName_abe68a48cece,
    'ScopeDefault', p_ScopeDefault_abe68a48cece,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_abe68a48cece,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_abe68a48cece,
    'Status', p_Status_abe68a48cece,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_abe68a48cece,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_abe68a48cece,
    'AutoUpdateCategory', p_AutoUpdateCategory_abe68a48cece,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_abe68a48cece,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_abe68a48cece,
    'Encrypt', p_Encrypt_abe68a48cece,
    'EncryptionKeyID', p_EncryptionKeyID_abe68a48cece,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_abe68a48cece,
    'SendEncryptedValue', p_SendEncryptedValue_abe68a48cece,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_abe68a48cece,
    'IsSoftForeignKey', p_IsSoftForeignKey_abe68a48cece,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_abe68a48cece,
    'JSONType', p_JSONType_abe68a48cece,
    'JSONTypeIsArray', p_JSONTypeIsArray_abe68a48cece,
    'JSONTypeDefinition', p_JSONTypeDefinition_abe68a48cece,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_abe68a48cece,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_abe68a48cece,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_abe68a48cece,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_abe68a48cece,
    'IsComputed', p_IsComputed_abe68a48cece
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_abe68a48cece,
    'Configuration', p_Configuration_abe68a48cece,
    'ID', p_ID_abe68a48cece
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_abe68a48cece, p_Description := p_Description_abe68a48cece, p_AutoUpdateDescription := p_AutoUpdateDescription_abe68a48cece, p_IsPrimaryKey := p_IsPrimaryKey_abe68a48cece, p_IsUnique := p_IsUnique_abe68a48cece, p_Category := p_Category_abe68a48cece, p_ValueListType := p_ValueListType_abe68a48cece, p_ExtendedType := p_ExtendedType_abe68a48cece, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_abe68a48cece, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_abe68a48cece, p_ViewCellTemplate := p_ViewCellTemplate_abe68a48cece, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_abe68a48cece, p_AllowUpdateAPI := p_AllowUpdateAPI_abe68a48cece, p_AllowUpdateInView := p_AllowUpdateInView_abe68a48cece, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_abe68a48cece, p_FullTextSearchEnabled := p_FullTextSearchEnabled_abe68a48cece, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_abe68a48cece, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_abe68a48cece, p_GeneratedFormSection := p_GeneratedFormSection_abe68a48cece, p_IsNameField := p_IsNameField_abe68a48cece, p_RelatedEntityID := p_RelatedEntityID_abe68a48cece, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_abe68a48cece, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_abe68a48cece, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_abe68a48cece, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_abe68a48cece, p_EntityIDFieldName := p_EntityIDFieldName_abe68a48cece, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_abe68a48cece, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_abe68a48cece, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_abe68a48cece, p_Status := p_Status_abe68a48cece, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_abe68a48cece, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_abe68a48cece, p_AutoUpdateCategory := p_AutoUpdateCategory_abe68a48cece, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_abe68a48cece, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_abe68a48cece, p_Encrypt := p_Encrypt_abe68a48cece, p_EncryptionKeyID := p_EncryptionKeyID_abe68a48cece, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_abe68a48cece, p_SendEncryptedValue := p_SendEncryptedValue_abe68a48cece, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_abe68a48cece, p_IsSoftForeignKey := p_IsSoftForeignKey_abe68a48cece, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_abe68a48cece, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_abe68a48cece, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_abe68a48cece, p_JSONTypeDefinition := p_JSONTypeDefinition_abe68a48cece, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_abe68a48cece, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_abe68a48cece, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_abe68a48cece, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_abe68a48cece, p_IsComputed := p_IsComputed_abe68a48cece, p_EmbeddedRecord := p_EmbeddedRecord_abe68a48cece, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_abe68a48cece, p_Configuration_Clear := TRUE, p_ID := p_ID_abe68a48cece);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_7f1b9799079c VARCHAR(255);
  p_Description_7f1b9799079c TEXT;
  p_AutoUpdateDescription_7f1b9799079c BOOLEAN;
  p_IsPrimaryKey_7f1b9799079c BOOLEAN;
  p_IsUnique_7f1b9799079c BOOLEAN;
  p_Category_7f1b9799079c VARCHAR(255);
  p_ValueListType_7f1b9799079c VARCHAR(20);
  p_ExtendedType_7f1b9799079c VARCHAR(50);
  p_CodeType_7f1b9799079c VARCHAR(50);
  p_DefaultInView_7f1b9799079c BOOLEAN;
  p_ViewCellTemplate_7f1b9799079c TEXT;
  p_DefaultColumnWidth_7f1b9799079c INTEGER;
  p_AllowUpdateAPI_7f1b9799079c BOOLEAN;
  p_AllowUpdateInView_7f1b9799079c BOOLEAN;
  p_IncludeInUserSearchAPI_7f1b9799079c BOOLEAN;
  p_FullTextSearchEnabled_7f1b9799079c BOOLEAN;
  p_UserSearchParamFormatAPI_7f1b9799079c VARCHAR(500);
  p_IncludeInGeneratedForm_7f1b9799079c BOOLEAN;
  p_GeneratedFormSection_7f1b9799079c VARCHAR(10);
  p_IsNameField_7f1b9799079c BOOLEAN;
  p_RelatedEntityID_7f1b9799079c UUID;
  p_RelatedEntityFieldName_7f1b9799079c VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_7f1b9799079c BOOLEAN;
  p_RelatedEntityNameFieldMap_7f1b9799079c VARCHAR(255);
  p_RelatedEntityDisplayType_7f1b9799079c VARCHAR(20);
  p_EntityIDFieldName_7f1b9799079c VARCHAR(100);
  p_ScopeDefault_7f1b9799079c VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_7f1b9799079c BOOLEAN;
  p_ValuesToPackWithSchema_7f1b9799079c VARCHAR(10);
  p_Status_7f1b9799079c VARCHAR(25);
  p_AutoUpdateIsNameField_7f1b9799079c BOOLEAN;
  p_AutoUpdateDefaultInView_7f1b9799079c BOOLEAN;
  p_AutoUpdateCategory_7f1b9799079c BOOLEAN;
  p_AutoUpdateDisplayName_7f1b9799079c BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_7f1b9799079c BOOLEAN;
  p_Encrypt_7f1b9799079c BOOLEAN;
  p_EncryptionKeyID_7f1b9799079c UUID;
  p_AllowDecryptInAPI_7f1b9799079c BOOLEAN;
  p_SendEncryptedValue_7f1b9799079c BOOLEAN;
  p_IsSoftPrimaryKey_7f1b9799079c BOOLEAN;
  p_IsSoftForeignKey_7f1b9799079c BOOLEAN;
  p_RelatedEntityJoinFields_7f1b9799079c TEXT;
  p_JSONType_7f1b9799079c VARCHAR(255);
  p_JSONTypeIsArray_7f1b9799079c BOOLEAN;
  p_JSONTypeDefinition_7f1b9799079c TEXT;
  p_UserSearchPredicateAPI_7f1b9799079c VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_7f1b9799079c BOOLEAN;
  p_AutoUpdateFullTextSearch_7f1b9799079c BOOLEAN;
  p_AutoUpdateExtendedType_7f1b9799079c BOOLEAN;
  p_IsComputed_7f1b9799079c BOOLEAN;
  p_EmbeddedRecord_7f1b9799079c TEXT;
  p_Configuration_7f1b9799079c TEXT;
  p_ID_7f1b9799079c UUID;
BEGIN
  p_DisplayName_7f1b9799079c := 'Default Cancellation Window Days';
  p_Description_7f1b9799079c := 'Seeds Contract.CancellationWindowDays — the notice the CUSTOMER owes us to cancel. Deliberately a separate default from the renewal notice even where a type sets them equal: one obligation is ours and the other theirs, and a single default would hide that.';
  p_AutoUpdateDescription_7f1b9799079c := TRUE;
  p_IsPrimaryKey_7f1b9799079c := FALSE;
  p_IsUnique_7f1b9799079c := FALSE;
  p_Category_7f1b9799079c := 'Default Contract Terms';
  p_ValueListType_7f1b9799079c := 'None';
  p_DefaultInView_7f1b9799079c := FALSE;
  p_DefaultColumnWidth_7f1b9799079c := 50;
  p_AllowUpdateAPI_7f1b9799079c := TRUE;
  p_AllowUpdateInView_7f1b9799079c := TRUE;
  p_IncludeInUserSearchAPI_7f1b9799079c := FALSE;
  p_FullTextSearchEnabled_7f1b9799079c := FALSE;
  p_IncludeInGeneratedForm_7f1b9799079c := TRUE;
  p_GeneratedFormSection_7f1b9799079c := 'Category';
  p_IsNameField_7f1b9799079c := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_7f1b9799079c := FALSE;
  p_RelatedEntityDisplayType_7f1b9799079c := 'Search';
  p_AutoUpdateRelatedEntityInfo_7f1b9799079c := TRUE;
  p_ValuesToPackWithSchema_7f1b9799079c := 'Auto';
  p_Status_7f1b9799079c := 'Active';
  p_AutoUpdateIsNameField_7f1b9799079c := TRUE;
  p_AutoUpdateDefaultInView_7f1b9799079c := TRUE;
  p_AutoUpdateCategory_7f1b9799079c := TRUE;
  p_AutoUpdateDisplayName_7f1b9799079c := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_7f1b9799079c := TRUE;
  p_Encrypt_7f1b9799079c := FALSE;
  p_AllowDecryptInAPI_7f1b9799079c := FALSE;
  p_SendEncryptedValue_7f1b9799079c := FALSE;
  p_IsSoftPrimaryKey_7f1b9799079c := FALSE;
  p_IsSoftForeignKey_7f1b9799079c := FALSE;
  p_JSONTypeIsArray_7f1b9799079c := FALSE;
  p_UserSearchPredicateAPI_7f1b9799079c := 'Contains';
  p_AutoUpdateUserSearchPredicate_7f1b9799079c := TRUE;
  p_AutoUpdateFullTextSearch_7f1b9799079c := TRUE;
  p_AutoUpdateExtendedType_7f1b9799079c := TRUE;
  p_IsComputed_7f1b9799079c := FALSE;
  p_ID_7f1b9799079c := '111CFB1B-1EFB-4E60-A79D-41A391EF596A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_7f1b9799079c,
    'Description', p_Description_7f1b9799079c,
    'AutoUpdateDescription', p_AutoUpdateDescription_7f1b9799079c,
    'IsPrimaryKey', p_IsPrimaryKey_7f1b9799079c,
    'IsUnique', p_IsUnique_7f1b9799079c,
    'Category', p_Category_7f1b9799079c,
    'ValueListType', p_ValueListType_7f1b9799079c,
    'ExtendedType', p_ExtendedType_7f1b9799079c,
    'CodeType', p_CodeType_7f1b9799079c,
    'DefaultInView', p_DefaultInView_7f1b9799079c,
    'ViewCellTemplate', p_ViewCellTemplate_7f1b9799079c,
    'DefaultColumnWidth', p_DefaultColumnWidth_7f1b9799079c,
    'AllowUpdateAPI', p_AllowUpdateAPI_7f1b9799079c,
    'AllowUpdateInView', p_AllowUpdateInView_7f1b9799079c,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_7f1b9799079c,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_7f1b9799079c,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_7f1b9799079c,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_7f1b9799079c,
    'GeneratedFormSection', p_GeneratedFormSection_7f1b9799079c,
    'IsNameField', p_IsNameField_7f1b9799079c,
    'RelatedEntityID', p_RelatedEntityID_7f1b9799079c,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_7f1b9799079c,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_7f1b9799079c,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_7f1b9799079c,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_7f1b9799079c,
    'EntityIDFieldName', p_EntityIDFieldName_7f1b9799079c,
    'ScopeDefault', p_ScopeDefault_7f1b9799079c,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_7f1b9799079c,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_7f1b9799079c,
    'Status', p_Status_7f1b9799079c,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_7f1b9799079c,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_7f1b9799079c,
    'AutoUpdateCategory', p_AutoUpdateCategory_7f1b9799079c,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_7f1b9799079c,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_7f1b9799079c,
    'Encrypt', p_Encrypt_7f1b9799079c,
    'EncryptionKeyID', p_EncryptionKeyID_7f1b9799079c,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_7f1b9799079c,
    'SendEncryptedValue', p_SendEncryptedValue_7f1b9799079c,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_7f1b9799079c,
    'IsSoftForeignKey', p_IsSoftForeignKey_7f1b9799079c,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_7f1b9799079c,
    'JSONType', p_JSONType_7f1b9799079c,
    'JSONTypeIsArray', p_JSONTypeIsArray_7f1b9799079c,
    'JSONTypeDefinition', p_JSONTypeDefinition_7f1b9799079c,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_7f1b9799079c,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_7f1b9799079c,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_7f1b9799079c,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_7f1b9799079c,
    'IsComputed', p_IsComputed_7f1b9799079c
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_7f1b9799079c,
    'Configuration', p_Configuration_7f1b9799079c,
    'ID', p_ID_7f1b9799079c
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_7f1b9799079c, p_Description := p_Description_7f1b9799079c, p_AutoUpdateDescription := p_AutoUpdateDescription_7f1b9799079c, p_IsPrimaryKey := p_IsPrimaryKey_7f1b9799079c, p_IsUnique := p_IsUnique_7f1b9799079c, p_Category := p_Category_7f1b9799079c, p_ValueListType := p_ValueListType_7f1b9799079c, p_ExtendedType := p_ExtendedType_7f1b9799079c, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_7f1b9799079c, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_7f1b9799079c, p_ViewCellTemplate := p_ViewCellTemplate_7f1b9799079c, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_7f1b9799079c, p_AllowUpdateAPI := p_AllowUpdateAPI_7f1b9799079c, p_AllowUpdateInView := p_AllowUpdateInView_7f1b9799079c, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_7f1b9799079c, p_FullTextSearchEnabled := p_FullTextSearchEnabled_7f1b9799079c, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_7f1b9799079c, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_7f1b9799079c, p_GeneratedFormSection := p_GeneratedFormSection_7f1b9799079c, p_IsNameField := p_IsNameField_7f1b9799079c, p_RelatedEntityID := p_RelatedEntityID_7f1b9799079c, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_7f1b9799079c, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_7f1b9799079c, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_7f1b9799079c, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_7f1b9799079c, p_EntityIDFieldName := p_EntityIDFieldName_7f1b9799079c, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_7f1b9799079c, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_7f1b9799079c, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_7f1b9799079c, p_Status := p_Status_7f1b9799079c, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_7f1b9799079c, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_7f1b9799079c, p_AutoUpdateCategory := p_AutoUpdateCategory_7f1b9799079c, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_7f1b9799079c, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_7f1b9799079c, p_Encrypt := p_Encrypt_7f1b9799079c, p_EncryptionKeyID := p_EncryptionKeyID_7f1b9799079c, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_7f1b9799079c, p_SendEncryptedValue := p_SendEncryptedValue_7f1b9799079c, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_7f1b9799079c, p_IsSoftForeignKey := p_IsSoftForeignKey_7f1b9799079c, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_7f1b9799079c, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_7f1b9799079c, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_7f1b9799079c, p_JSONTypeDefinition := p_JSONTypeDefinition_7f1b9799079c, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_7f1b9799079c, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_7f1b9799079c, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_7f1b9799079c, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_7f1b9799079c, p_IsComputed := p_IsComputed_7f1b9799079c, p_EmbeddedRecord := p_EmbeddedRecord_7f1b9799079c, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_7f1b9799079c, p_Configuration_Clear := TRUE, p_ID := p_ID_7f1b9799079c);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_d064d7c44c9b VARCHAR(255);
  p_Description_d064d7c44c9b TEXT;
  p_AutoUpdateDescription_d064d7c44c9b BOOLEAN;
  p_IsPrimaryKey_d064d7c44c9b BOOLEAN;
  p_IsUnique_d064d7c44c9b BOOLEAN;
  p_Category_d064d7c44c9b VARCHAR(255);
  p_ValueListType_d064d7c44c9b VARCHAR(20);
  p_ExtendedType_d064d7c44c9b VARCHAR(50);
  p_CodeType_d064d7c44c9b VARCHAR(50);
  p_DefaultInView_d064d7c44c9b BOOLEAN;
  p_ViewCellTemplate_d064d7c44c9b TEXT;
  p_DefaultColumnWidth_d064d7c44c9b INTEGER;
  p_AllowUpdateAPI_d064d7c44c9b BOOLEAN;
  p_AllowUpdateInView_d064d7c44c9b BOOLEAN;
  p_IncludeInUserSearchAPI_d064d7c44c9b BOOLEAN;
  p_FullTextSearchEnabled_d064d7c44c9b BOOLEAN;
  p_UserSearchParamFormatAPI_d064d7c44c9b VARCHAR(500);
  p_IncludeInGeneratedForm_d064d7c44c9b BOOLEAN;
  p_GeneratedFormSection_d064d7c44c9b VARCHAR(10);
  p_IsNameField_d064d7c44c9b BOOLEAN;
  p_RelatedEntityID_d064d7c44c9b UUID;
  p_RelatedEntityFieldName_d064d7c44c9b VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_d064d7c44c9b BOOLEAN;
  p_RelatedEntityNameFieldMap_d064d7c44c9b VARCHAR(255);
  p_RelatedEntityDisplayType_d064d7c44c9b VARCHAR(20);
  p_EntityIDFieldName_d064d7c44c9b VARCHAR(100);
  p_ScopeDefault_d064d7c44c9b VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_d064d7c44c9b BOOLEAN;
  p_ValuesToPackWithSchema_d064d7c44c9b VARCHAR(10);
  p_Status_d064d7c44c9b VARCHAR(25);
  p_AutoUpdateIsNameField_d064d7c44c9b BOOLEAN;
  p_AutoUpdateDefaultInView_d064d7c44c9b BOOLEAN;
  p_AutoUpdateCategory_d064d7c44c9b BOOLEAN;
  p_AutoUpdateDisplayName_d064d7c44c9b BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_d064d7c44c9b BOOLEAN;
  p_Encrypt_d064d7c44c9b BOOLEAN;
  p_EncryptionKeyID_d064d7c44c9b UUID;
  p_AllowDecryptInAPI_d064d7c44c9b BOOLEAN;
  p_SendEncryptedValue_d064d7c44c9b BOOLEAN;
  p_IsSoftPrimaryKey_d064d7c44c9b BOOLEAN;
  p_IsSoftForeignKey_d064d7c44c9b BOOLEAN;
  p_RelatedEntityJoinFields_d064d7c44c9b TEXT;
  p_JSONType_d064d7c44c9b VARCHAR(255);
  p_JSONTypeIsArray_d064d7c44c9b BOOLEAN;
  p_JSONTypeDefinition_d064d7c44c9b TEXT;
  p_UserSearchPredicateAPI_d064d7c44c9b VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_d064d7c44c9b BOOLEAN;
  p_AutoUpdateFullTextSearch_d064d7c44c9b BOOLEAN;
  p_AutoUpdateExtendedType_d064d7c44c9b BOOLEAN;
  p_IsComputed_d064d7c44c9b BOOLEAN;
  p_EmbeddedRecord_d064d7c44c9b TEXT;
  p_Configuration_d064d7c44c9b TEXT;
  p_ID_d064d7c44c9b UUID;
BEGIN
  p_DisplayName_d064d7c44c9b := 'Default Annual Increase Percent';
  p_Description_d064d7c44c9b := 'Seeds Contract.AnnualIncreasePercent — the year-over-year uplift this kind of agreement usually carries. NULL means no default. Same precision as the column it seeds, so a legal default can never seed an unsaveable contract.';
  p_AutoUpdateDescription_d064d7c44c9b := TRUE;
  p_IsPrimaryKey_d064d7c44c9b := FALSE;
  p_IsUnique_d064d7c44c9b := FALSE;
  p_Category_d064d7c44c9b := 'Default Contract Terms';
  p_ValueListType_d064d7c44c9b := 'None';
  p_DefaultInView_d064d7c44c9b := FALSE;
  p_DefaultColumnWidth_d064d7c44c9b := 150;
  p_AllowUpdateAPI_d064d7c44c9b := TRUE;
  p_AllowUpdateInView_d064d7c44c9b := TRUE;
  p_IncludeInUserSearchAPI_d064d7c44c9b := FALSE;
  p_FullTextSearchEnabled_d064d7c44c9b := FALSE;
  p_IncludeInGeneratedForm_d064d7c44c9b := TRUE;
  p_GeneratedFormSection_d064d7c44c9b := 'Category';
  p_IsNameField_d064d7c44c9b := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_d064d7c44c9b := FALSE;
  p_RelatedEntityDisplayType_d064d7c44c9b := 'Search';
  p_AutoUpdateRelatedEntityInfo_d064d7c44c9b := TRUE;
  p_ValuesToPackWithSchema_d064d7c44c9b := 'Auto';
  p_Status_d064d7c44c9b := 'Active';
  p_AutoUpdateIsNameField_d064d7c44c9b := TRUE;
  p_AutoUpdateDefaultInView_d064d7c44c9b := TRUE;
  p_AutoUpdateCategory_d064d7c44c9b := TRUE;
  p_AutoUpdateDisplayName_d064d7c44c9b := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_d064d7c44c9b := TRUE;
  p_Encrypt_d064d7c44c9b := FALSE;
  p_AllowDecryptInAPI_d064d7c44c9b := FALSE;
  p_SendEncryptedValue_d064d7c44c9b := FALSE;
  p_IsSoftPrimaryKey_d064d7c44c9b := FALSE;
  p_IsSoftForeignKey_d064d7c44c9b := FALSE;
  p_JSONTypeIsArray_d064d7c44c9b := FALSE;
  p_UserSearchPredicateAPI_d064d7c44c9b := 'Contains';
  p_AutoUpdateUserSearchPredicate_d064d7c44c9b := TRUE;
  p_AutoUpdateFullTextSearch_d064d7c44c9b := TRUE;
  p_AutoUpdateExtendedType_d064d7c44c9b := TRUE;
  p_IsComputed_d064d7c44c9b := FALSE;
  p_ID_d064d7c44c9b := 'DA53B111-BC39-49F6-BCFB-55380E260227';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_d064d7c44c9b,
    'Description', p_Description_d064d7c44c9b,
    'AutoUpdateDescription', p_AutoUpdateDescription_d064d7c44c9b,
    'IsPrimaryKey', p_IsPrimaryKey_d064d7c44c9b,
    'IsUnique', p_IsUnique_d064d7c44c9b,
    'Category', p_Category_d064d7c44c9b,
    'ValueListType', p_ValueListType_d064d7c44c9b,
    'ExtendedType', p_ExtendedType_d064d7c44c9b,
    'CodeType', p_CodeType_d064d7c44c9b,
    'DefaultInView', p_DefaultInView_d064d7c44c9b,
    'ViewCellTemplate', p_ViewCellTemplate_d064d7c44c9b,
    'DefaultColumnWidth', p_DefaultColumnWidth_d064d7c44c9b,
    'AllowUpdateAPI', p_AllowUpdateAPI_d064d7c44c9b,
    'AllowUpdateInView', p_AllowUpdateInView_d064d7c44c9b,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_d064d7c44c9b,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_d064d7c44c9b,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_d064d7c44c9b,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_d064d7c44c9b,
    'GeneratedFormSection', p_GeneratedFormSection_d064d7c44c9b,
    'IsNameField', p_IsNameField_d064d7c44c9b,
    'RelatedEntityID', p_RelatedEntityID_d064d7c44c9b,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_d064d7c44c9b,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_d064d7c44c9b,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_d064d7c44c9b,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_d064d7c44c9b,
    'EntityIDFieldName', p_EntityIDFieldName_d064d7c44c9b,
    'ScopeDefault', p_ScopeDefault_d064d7c44c9b,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_d064d7c44c9b,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_d064d7c44c9b,
    'Status', p_Status_d064d7c44c9b,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_d064d7c44c9b,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_d064d7c44c9b,
    'AutoUpdateCategory', p_AutoUpdateCategory_d064d7c44c9b,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_d064d7c44c9b,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_d064d7c44c9b,
    'Encrypt', p_Encrypt_d064d7c44c9b,
    'EncryptionKeyID', p_EncryptionKeyID_d064d7c44c9b,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_d064d7c44c9b,
    'SendEncryptedValue', p_SendEncryptedValue_d064d7c44c9b,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_d064d7c44c9b,
    'IsSoftForeignKey', p_IsSoftForeignKey_d064d7c44c9b,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_d064d7c44c9b,
    'JSONType', p_JSONType_d064d7c44c9b,
    'JSONTypeIsArray', p_JSONTypeIsArray_d064d7c44c9b,
    'JSONTypeDefinition', p_JSONTypeDefinition_d064d7c44c9b,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_d064d7c44c9b,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_d064d7c44c9b,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_d064d7c44c9b,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_d064d7c44c9b,
    'IsComputed', p_IsComputed_d064d7c44c9b
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_d064d7c44c9b,
    'Configuration', p_Configuration_d064d7c44c9b,
    'ID', p_ID_d064d7c44c9b
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_d064d7c44c9b, p_Description := p_Description_d064d7c44c9b, p_AutoUpdateDescription := p_AutoUpdateDescription_d064d7c44c9b, p_IsPrimaryKey := p_IsPrimaryKey_d064d7c44c9b, p_IsUnique := p_IsUnique_d064d7c44c9b, p_Category := p_Category_d064d7c44c9b, p_ValueListType := p_ValueListType_d064d7c44c9b, p_ExtendedType := p_ExtendedType_d064d7c44c9b, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_d064d7c44c9b, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_d064d7c44c9b, p_ViewCellTemplate := p_ViewCellTemplate_d064d7c44c9b, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_d064d7c44c9b, p_AllowUpdateAPI := p_AllowUpdateAPI_d064d7c44c9b, p_AllowUpdateInView := p_AllowUpdateInView_d064d7c44c9b, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_d064d7c44c9b, p_FullTextSearchEnabled := p_FullTextSearchEnabled_d064d7c44c9b, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_d064d7c44c9b, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_d064d7c44c9b, p_GeneratedFormSection := p_GeneratedFormSection_d064d7c44c9b, p_IsNameField := p_IsNameField_d064d7c44c9b, p_RelatedEntityID := p_RelatedEntityID_d064d7c44c9b, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_d064d7c44c9b, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_d064d7c44c9b, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_d064d7c44c9b, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_d064d7c44c9b, p_EntityIDFieldName := p_EntityIDFieldName_d064d7c44c9b, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_d064d7c44c9b, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_d064d7c44c9b, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_d064d7c44c9b, p_Status := p_Status_d064d7c44c9b, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_d064d7c44c9b, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_d064d7c44c9b, p_AutoUpdateCategory := p_AutoUpdateCategory_d064d7c44c9b, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_d064d7c44c9b, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_d064d7c44c9b, p_Encrypt := p_Encrypt_d064d7c44c9b, p_EncryptionKeyID := p_EncryptionKeyID_d064d7c44c9b, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_d064d7c44c9b, p_SendEncryptedValue := p_SendEncryptedValue_d064d7c44c9b, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_d064d7c44c9b, p_IsSoftForeignKey := p_IsSoftForeignKey_d064d7c44c9b, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_d064d7c44c9b, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_d064d7c44c9b, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_d064d7c44c9b, p_JSONTypeDefinition := p_JSONTypeDefinition_d064d7c44c9b, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_d064d7c44c9b, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_d064d7c44c9b, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_d064d7c44c9b, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_d064d7c44c9b, p_IsComputed := p_IsComputed_d064d7c44c9b, p_EmbeddedRecord := p_EmbeddedRecord_d064d7c44c9b, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_d064d7c44c9b, p_Configuration_Clear := TRUE, p_ID := p_ID_d064d7c44c9b);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_2837efd99615 VARCHAR(255);
  p_Description_2837efd99615 TEXT;
  p_AutoUpdateDescription_2837efd99615 BOOLEAN;
  p_IsPrimaryKey_2837efd99615 BOOLEAN;
  p_IsUnique_2837efd99615 BOOLEAN;
  p_Category_2837efd99615 VARCHAR(255);
  p_ValueListType_2837efd99615 VARCHAR(20);
  p_ExtendedType_2837efd99615 VARCHAR(50);
  p_CodeType_2837efd99615 VARCHAR(50);
  p_DefaultInView_2837efd99615 BOOLEAN;
  p_ViewCellTemplate_2837efd99615 TEXT;
  p_DefaultColumnWidth_2837efd99615 INTEGER;
  p_AllowUpdateAPI_2837efd99615 BOOLEAN;
  p_AllowUpdateInView_2837efd99615 BOOLEAN;
  p_IncludeInUserSearchAPI_2837efd99615 BOOLEAN;
  p_FullTextSearchEnabled_2837efd99615 BOOLEAN;
  p_UserSearchParamFormatAPI_2837efd99615 VARCHAR(500);
  p_IncludeInGeneratedForm_2837efd99615 BOOLEAN;
  p_GeneratedFormSection_2837efd99615 VARCHAR(10);
  p_IsNameField_2837efd99615 BOOLEAN;
  p_RelatedEntityID_2837efd99615 UUID;
  p_RelatedEntityFieldName_2837efd99615 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_2837efd99615 BOOLEAN;
  p_RelatedEntityNameFieldMap_2837efd99615 VARCHAR(255);
  p_RelatedEntityDisplayType_2837efd99615 VARCHAR(20);
  p_EntityIDFieldName_2837efd99615 VARCHAR(100);
  p_ScopeDefault_2837efd99615 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_2837efd99615 BOOLEAN;
  p_ValuesToPackWithSchema_2837efd99615 VARCHAR(10);
  p_Status_2837efd99615 VARCHAR(25);
  p_AutoUpdateIsNameField_2837efd99615 BOOLEAN;
  p_AutoUpdateDefaultInView_2837efd99615 BOOLEAN;
  p_AutoUpdateCategory_2837efd99615 BOOLEAN;
  p_AutoUpdateDisplayName_2837efd99615 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_2837efd99615 BOOLEAN;
  p_Encrypt_2837efd99615 BOOLEAN;
  p_EncryptionKeyID_2837efd99615 UUID;
  p_AllowDecryptInAPI_2837efd99615 BOOLEAN;
  p_SendEncryptedValue_2837efd99615 BOOLEAN;
  p_IsSoftPrimaryKey_2837efd99615 BOOLEAN;
  p_IsSoftForeignKey_2837efd99615 BOOLEAN;
  p_RelatedEntityJoinFields_2837efd99615 TEXT;
  p_JSONType_2837efd99615 VARCHAR(255);
  p_JSONTypeIsArray_2837efd99615 BOOLEAN;
  p_JSONTypeDefinition_2837efd99615 TEXT;
  p_UserSearchPredicateAPI_2837efd99615 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_2837efd99615 BOOLEAN;
  p_AutoUpdateFullTextSearch_2837efd99615 BOOLEAN;
  p_AutoUpdateExtendedType_2837efd99615 BOOLEAN;
  p_IsComputed_2837efd99615 BOOLEAN;
  p_EmbeddedRecord_2837efd99615 TEXT;
  p_Configuration_2837efd99615 TEXT;
  p_ID_2837efd99615 UUID;
BEGIN
  p_DisplayName_2837efd99615 := 'Company Name';
  p_AutoUpdateDescription_2837efd99615 := TRUE;
  p_IsPrimaryKey_2837efd99615 := FALSE;
  p_IsUnique_2837efd99615 := FALSE;
  p_Category_2837efd99615 := 'Stakeholders';
  p_ValueListType_2837efd99615 := 'None';
  p_DefaultInView_2837efd99615 := TRUE;
  p_DefaultColumnWidth_2837efd99615 := 150;
  p_AllowUpdateAPI_2837efd99615 := FALSE;
  p_AllowUpdateInView_2837efd99615 := TRUE;
  p_IncludeInUserSearchAPI_2837efd99615 := FALSE;
  p_FullTextSearchEnabled_2837efd99615 := FALSE;
  p_IncludeInGeneratedForm_2837efd99615 := TRUE;
  p_GeneratedFormSection_2837efd99615 := 'Category';
  p_IsNameField_2837efd99615 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_2837efd99615 := FALSE;
  p_RelatedEntityDisplayType_2837efd99615 := 'Search';
  p_AutoUpdateRelatedEntityInfo_2837efd99615 := TRUE;
  p_ValuesToPackWithSchema_2837efd99615 := 'Auto';
  p_Status_2837efd99615 := 'Active';
  p_AutoUpdateIsNameField_2837efd99615 := TRUE;
  p_AutoUpdateDefaultInView_2837efd99615 := TRUE;
  p_AutoUpdateCategory_2837efd99615 := TRUE;
  p_AutoUpdateDisplayName_2837efd99615 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_2837efd99615 := TRUE;
  p_Encrypt_2837efd99615 := FALSE;
  p_AllowDecryptInAPI_2837efd99615 := FALSE;
  p_SendEncryptedValue_2837efd99615 := FALSE;
  p_IsSoftPrimaryKey_2837efd99615 := FALSE;
  p_IsSoftForeignKey_2837efd99615 := FALSE;
  p_JSONTypeIsArray_2837efd99615 := FALSE;
  p_UserSearchPredicateAPI_2837efd99615 := 'Contains';
  p_AutoUpdateUserSearchPredicate_2837efd99615 := TRUE;
  p_AutoUpdateFullTextSearch_2837efd99615 := TRUE;
  p_AutoUpdateExtendedType_2837efd99615 := TRUE;
  p_IsComputed_2837efd99615 := FALSE;
  p_ID_2837efd99615 := 'A2B9A232-351C-4CF9-A050-6F059F146806';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_2837efd99615,
    'Description', p_Description_2837efd99615,
    'AutoUpdateDescription', p_AutoUpdateDescription_2837efd99615,
    'IsPrimaryKey', p_IsPrimaryKey_2837efd99615,
    'IsUnique', p_IsUnique_2837efd99615,
    'Category', p_Category_2837efd99615,
    'ValueListType', p_ValueListType_2837efd99615,
    'ExtendedType', p_ExtendedType_2837efd99615,
    'CodeType', p_CodeType_2837efd99615,
    'DefaultInView', p_DefaultInView_2837efd99615,
    'ViewCellTemplate', p_ViewCellTemplate_2837efd99615,
    'DefaultColumnWidth', p_DefaultColumnWidth_2837efd99615,
    'AllowUpdateAPI', p_AllowUpdateAPI_2837efd99615,
    'AllowUpdateInView', p_AllowUpdateInView_2837efd99615,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_2837efd99615,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_2837efd99615,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_2837efd99615,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_2837efd99615,
    'GeneratedFormSection', p_GeneratedFormSection_2837efd99615,
    'IsNameField', p_IsNameField_2837efd99615,
    'RelatedEntityID', p_RelatedEntityID_2837efd99615,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_2837efd99615,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_2837efd99615,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_2837efd99615,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_2837efd99615,
    'EntityIDFieldName', p_EntityIDFieldName_2837efd99615,
    'ScopeDefault', p_ScopeDefault_2837efd99615,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_2837efd99615,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_2837efd99615,
    'Status', p_Status_2837efd99615,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_2837efd99615,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_2837efd99615,
    'AutoUpdateCategory', p_AutoUpdateCategory_2837efd99615,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_2837efd99615,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_2837efd99615,
    'Encrypt', p_Encrypt_2837efd99615,
    'EncryptionKeyID', p_EncryptionKeyID_2837efd99615,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_2837efd99615,
    'SendEncryptedValue', p_SendEncryptedValue_2837efd99615,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_2837efd99615,
    'IsSoftForeignKey', p_IsSoftForeignKey_2837efd99615,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_2837efd99615,
    'JSONType', p_JSONType_2837efd99615,
    'JSONTypeIsArray', p_JSONTypeIsArray_2837efd99615,
    'JSONTypeDefinition', p_JSONTypeDefinition_2837efd99615,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_2837efd99615,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_2837efd99615,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_2837efd99615,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_2837efd99615,
    'IsComputed', p_IsComputed_2837efd99615
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_2837efd99615,
    'Configuration', p_Configuration_2837efd99615,
    'ID', p_ID_2837efd99615
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_2837efd99615, p_Description := p_Description_2837efd99615, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_2837efd99615, p_IsPrimaryKey := p_IsPrimaryKey_2837efd99615, p_IsUnique := p_IsUnique_2837efd99615, p_Category := p_Category_2837efd99615, p_ValueListType := p_ValueListType_2837efd99615, p_ExtendedType := p_ExtendedType_2837efd99615, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_2837efd99615, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_2837efd99615, p_ViewCellTemplate := p_ViewCellTemplate_2837efd99615, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_2837efd99615, p_AllowUpdateAPI := p_AllowUpdateAPI_2837efd99615, p_AllowUpdateInView := p_AllowUpdateInView_2837efd99615, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_2837efd99615, p_FullTextSearchEnabled := p_FullTextSearchEnabled_2837efd99615, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_2837efd99615, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_2837efd99615, p_GeneratedFormSection := p_GeneratedFormSection_2837efd99615, p_IsNameField := p_IsNameField_2837efd99615, p_RelatedEntityID := p_RelatedEntityID_2837efd99615, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_2837efd99615, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_2837efd99615, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_2837efd99615, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_2837efd99615, p_EntityIDFieldName := p_EntityIDFieldName_2837efd99615, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_2837efd99615, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_2837efd99615, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_2837efd99615, p_Status := p_Status_2837efd99615, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_2837efd99615, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_2837efd99615, p_AutoUpdateCategory := p_AutoUpdateCategory_2837efd99615, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_2837efd99615, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_2837efd99615, p_Encrypt := p_Encrypt_2837efd99615, p_EncryptionKeyID := p_EncryptionKeyID_2837efd99615, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_2837efd99615, p_SendEncryptedValue := p_SendEncryptedValue_2837efd99615, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_2837efd99615, p_IsSoftForeignKey := p_IsSoftForeignKey_2837efd99615, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_2837efd99615, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_2837efd99615, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_2837efd99615, p_JSONTypeDefinition := p_JSONTypeDefinition_2837efd99615, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_2837efd99615, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_2837efd99615, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_2837efd99615, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_2837efd99615, p_IsComputed := p_IsComputed_2837efd99615, p_EmbeddedRecord := p_EmbeddedRecord_2837efd99615, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_2837efd99615, p_Configuration_Clear := TRUE, p_ID := p_ID_2837efd99615);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_13aa73a3e832 VARCHAR(255);
  p_Description_13aa73a3e832 TEXT;
  p_AutoUpdateDescription_13aa73a3e832 BOOLEAN;
  p_IsPrimaryKey_13aa73a3e832 BOOLEAN;
  p_IsUnique_13aa73a3e832 BOOLEAN;
  p_Category_13aa73a3e832 VARCHAR(255);
  p_ValueListType_13aa73a3e832 VARCHAR(20);
  p_ExtendedType_13aa73a3e832 VARCHAR(50);
  p_CodeType_13aa73a3e832 VARCHAR(50);
  p_DefaultInView_13aa73a3e832 BOOLEAN;
  p_ViewCellTemplate_13aa73a3e832 TEXT;
  p_DefaultColumnWidth_13aa73a3e832 INTEGER;
  p_AllowUpdateAPI_13aa73a3e832 BOOLEAN;
  p_AllowUpdateInView_13aa73a3e832 BOOLEAN;
  p_IncludeInUserSearchAPI_13aa73a3e832 BOOLEAN;
  p_FullTextSearchEnabled_13aa73a3e832 BOOLEAN;
  p_UserSearchParamFormatAPI_13aa73a3e832 VARCHAR(500);
  p_IncludeInGeneratedForm_13aa73a3e832 BOOLEAN;
  p_GeneratedFormSection_13aa73a3e832 VARCHAR(10);
  p_IsNameField_13aa73a3e832 BOOLEAN;
  p_RelatedEntityID_13aa73a3e832 UUID;
  p_RelatedEntityFieldName_13aa73a3e832 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832 BOOLEAN;
  p_RelatedEntityNameFieldMap_13aa73a3e832 VARCHAR(255);
  p_RelatedEntityDisplayType_13aa73a3e832 VARCHAR(20);
  p_EntityIDFieldName_13aa73a3e832 VARCHAR(100);
  p_ScopeDefault_13aa73a3e832 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_13aa73a3e832 BOOLEAN;
  p_ValuesToPackWithSchema_13aa73a3e832 VARCHAR(10);
  p_Status_13aa73a3e832 VARCHAR(25);
  p_AutoUpdateIsNameField_13aa73a3e832 BOOLEAN;
  p_AutoUpdateDefaultInView_13aa73a3e832 BOOLEAN;
  p_AutoUpdateCategory_13aa73a3e832 BOOLEAN;
  p_AutoUpdateDisplayName_13aa73a3e832 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832 BOOLEAN;
  p_Encrypt_13aa73a3e832 BOOLEAN;
  p_EncryptionKeyID_13aa73a3e832 UUID;
  p_AllowDecryptInAPI_13aa73a3e832 BOOLEAN;
  p_SendEncryptedValue_13aa73a3e832 BOOLEAN;
  p_IsSoftPrimaryKey_13aa73a3e832 BOOLEAN;
  p_IsSoftForeignKey_13aa73a3e832 BOOLEAN;
  p_RelatedEntityJoinFields_13aa73a3e832 TEXT;
  p_JSONType_13aa73a3e832 VARCHAR(255);
  p_JSONTypeIsArray_13aa73a3e832 BOOLEAN;
  p_JSONTypeDefinition_13aa73a3e832 TEXT;
  p_UserSearchPredicateAPI_13aa73a3e832 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_13aa73a3e832 BOOLEAN;
  p_AutoUpdateFullTextSearch_13aa73a3e832 BOOLEAN;
  p_AutoUpdateExtendedType_13aa73a3e832 BOOLEAN;
  p_IsComputed_13aa73a3e832 BOOLEAN;
  p_EmbeddedRecord_13aa73a3e832 TEXT;
  p_Configuration_13aa73a3e832 TEXT;
  p_ID_13aa73a3e832 UUID;
BEGIN
  p_DisplayName_13aa73a3e832 := 'Days To End';
  p_AutoUpdateDescription_13aa73a3e832 := TRUE;
  p_IsPrimaryKey_13aa73a3e832 := FALSE;
  p_IsUnique_13aa73a3e832 := FALSE;
  p_ValueListType_13aa73a3e832 := 'None';
  p_DefaultInView_13aa73a3e832 := TRUE;
  p_DefaultColumnWidth_13aa73a3e832 := 50;
  p_AllowUpdateAPI_13aa73a3e832 := FALSE;
  p_AllowUpdateInView_13aa73a3e832 := TRUE;
  p_IncludeInUserSearchAPI_13aa73a3e832 := FALSE;
  p_FullTextSearchEnabled_13aa73a3e832 := FALSE;
  p_IncludeInGeneratedForm_13aa73a3e832 := TRUE;
  p_GeneratedFormSection_13aa73a3e832 := 'Details';
  p_IsNameField_13aa73a3e832 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832 := TRUE;
  p_RelatedEntityDisplayType_13aa73a3e832 := 'Search';
  p_AutoUpdateRelatedEntityInfo_13aa73a3e832 := TRUE;
  p_ValuesToPackWithSchema_13aa73a3e832 := 'Auto';
  p_Status_13aa73a3e832 := 'Active';
  p_AutoUpdateIsNameField_13aa73a3e832 := TRUE;
  p_AutoUpdateDefaultInView_13aa73a3e832 := TRUE;
  p_AutoUpdateCategory_13aa73a3e832 := TRUE;
  p_AutoUpdateDisplayName_13aa73a3e832 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832 := TRUE;
  p_Encrypt_13aa73a3e832 := FALSE;
  p_AllowDecryptInAPI_13aa73a3e832 := FALSE;
  p_SendEncryptedValue_13aa73a3e832 := FALSE;
  p_IsSoftPrimaryKey_13aa73a3e832 := FALSE;
  p_IsSoftForeignKey_13aa73a3e832 := FALSE;
  p_JSONTypeIsArray_13aa73a3e832 := FALSE;
  p_UserSearchPredicateAPI_13aa73a3e832 := 'Contains';
  p_AutoUpdateUserSearchPredicate_13aa73a3e832 := TRUE;
  p_AutoUpdateFullTextSearch_13aa73a3e832 := TRUE;
  p_AutoUpdateExtendedType_13aa73a3e832 := TRUE;
  p_IsComputed_13aa73a3e832 := FALSE;
  SELECT "ID" INTO p_ID_13aa73a3e832 FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'DaysToEnd';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_13aa73a3e832,
    'Description', p_Description_13aa73a3e832,
    'AutoUpdateDescription', p_AutoUpdateDescription_13aa73a3e832,
    'IsPrimaryKey', p_IsPrimaryKey_13aa73a3e832,
    'IsUnique', p_IsUnique_13aa73a3e832,
    'Category', p_Category_13aa73a3e832,
    'ValueListType', p_ValueListType_13aa73a3e832,
    'ExtendedType', p_ExtendedType_13aa73a3e832,
    'CodeType', p_CodeType_13aa73a3e832,
    'DefaultInView', p_DefaultInView_13aa73a3e832,
    'ViewCellTemplate', p_ViewCellTemplate_13aa73a3e832,
    'DefaultColumnWidth', p_DefaultColumnWidth_13aa73a3e832,
    'AllowUpdateAPI', p_AllowUpdateAPI_13aa73a3e832,
    'AllowUpdateInView', p_AllowUpdateInView_13aa73a3e832,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_13aa73a3e832,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_13aa73a3e832,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_13aa73a3e832,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_13aa73a3e832,
    'GeneratedFormSection', p_GeneratedFormSection_13aa73a3e832,
    'IsNameField', p_IsNameField_13aa73a3e832,
    'RelatedEntityID', p_RelatedEntityID_13aa73a3e832,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_13aa73a3e832,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_13aa73a3e832,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_13aa73a3e832,
    'EntityIDFieldName', p_EntityIDFieldName_13aa73a3e832,
    'ScopeDefault', p_ScopeDefault_13aa73a3e832,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_13aa73a3e832,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_13aa73a3e832,
    'Status', p_Status_13aa73a3e832,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_13aa73a3e832,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_13aa73a3e832,
    'AutoUpdateCategory', p_AutoUpdateCategory_13aa73a3e832,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_13aa73a3e832,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832,
    'Encrypt', p_Encrypt_13aa73a3e832,
    'EncryptionKeyID', p_EncryptionKeyID_13aa73a3e832,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_13aa73a3e832,
    'SendEncryptedValue', p_SendEncryptedValue_13aa73a3e832,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_13aa73a3e832,
    'IsSoftForeignKey', p_IsSoftForeignKey_13aa73a3e832,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_13aa73a3e832,
    'JSONType', p_JSONType_13aa73a3e832,
    'JSONTypeIsArray', p_JSONTypeIsArray_13aa73a3e832,
    'JSONTypeDefinition', p_JSONTypeDefinition_13aa73a3e832,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_13aa73a3e832,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_13aa73a3e832,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_13aa73a3e832,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_13aa73a3e832,
    'IsComputed', p_IsComputed_13aa73a3e832
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_13aa73a3e832,
    'Configuration', p_Configuration_13aa73a3e832,
    'ID', p_ID_13aa73a3e832
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_13aa73a3e832, p_Description := p_Description_13aa73a3e832, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_13aa73a3e832, p_IsPrimaryKey := p_IsPrimaryKey_13aa73a3e832, p_IsUnique := p_IsUnique_13aa73a3e832, p_Category := p_Category_13aa73a3e832, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_13aa73a3e832, p_ExtendedType := p_ExtendedType_13aa73a3e832, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_13aa73a3e832, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_13aa73a3e832, p_ViewCellTemplate := p_ViewCellTemplate_13aa73a3e832, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_13aa73a3e832, p_AllowUpdateAPI := p_AllowUpdateAPI_13aa73a3e832, p_AllowUpdateInView := p_AllowUpdateInView_13aa73a3e832, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_13aa73a3e832, p_FullTextSearchEnabled := p_FullTextSearchEnabled_13aa73a3e832, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_13aa73a3e832, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_13aa73a3e832, p_GeneratedFormSection := p_GeneratedFormSection_13aa73a3e832, p_IsNameField := p_IsNameField_13aa73a3e832, p_RelatedEntityID := p_RelatedEntityID_13aa73a3e832, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_13aa73a3e832, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_13aa73a3e832, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_13aa73a3e832, p_EntityIDFieldName := p_EntityIDFieldName_13aa73a3e832, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_13aa73a3e832, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_13aa73a3e832, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_13aa73a3e832, p_Status := p_Status_13aa73a3e832, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_13aa73a3e832, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_13aa73a3e832, p_AutoUpdateCategory := p_AutoUpdateCategory_13aa73a3e832, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_13aa73a3e832, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832, p_Encrypt := p_Encrypt_13aa73a3e832, p_EncryptionKeyID := p_EncryptionKeyID_13aa73a3e832, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_13aa73a3e832, p_SendEncryptedValue := p_SendEncryptedValue_13aa73a3e832, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_13aa73a3e832, p_IsSoftForeignKey := p_IsSoftForeignKey_13aa73a3e832, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_13aa73a3e832, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_13aa73a3e832, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_13aa73a3e832, p_JSONTypeDefinition := p_JSONTypeDefinition_13aa73a3e832, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_13aa73a3e832, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_13aa73a3e832, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_13aa73a3e832, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_13aa73a3e832, p_IsComputed := p_IsComputed_13aa73a3e832, p_EmbeddedRecord := p_EmbeddedRecord_13aa73a3e832, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_13aa73a3e832, p_Configuration_Clear := TRUE, p_ID := p_ID_13aa73a3e832);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_23826996f557 VARCHAR(255);
  p_Description_23826996f557 TEXT;
  p_AutoUpdateDescription_23826996f557 BOOLEAN;
  p_IsPrimaryKey_23826996f557 BOOLEAN;
  p_IsUnique_23826996f557 BOOLEAN;
  p_Category_23826996f557 VARCHAR(255);
  p_ValueListType_23826996f557 VARCHAR(20);
  p_ExtendedType_23826996f557 VARCHAR(50);
  p_CodeType_23826996f557 VARCHAR(50);
  p_DefaultInView_23826996f557 BOOLEAN;
  p_ViewCellTemplate_23826996f557 TEXT;
  p_DefaultColumnWidth_23826996f557 INTEGER;
  p_AllowUpdateAPI_23826996f557 BOOLEAN;
  p_AllowUpdateInView_23826996f557 BOOLEAN;
  p_IncludeInUserSearchAPI_23826996f557 BOOLEAN;
  p_FullTextSearchEnabled_23826996f557 BOOLEAN;
  p_UserSearchParamFormatAPI_23826996f557 VARCHAR(500);
  p_IncludeInGeneratedForm_23826996f557 BOOLEAN;
  p_GeneratedFormSection_23826996f557 VARCHAR(10);
  p_IsNameField_23826996f557 BOOLEAN;
  p_RelatedEntityID_23826996f557 UUID;
  p_RelatedEntityFieldName_23826996f557 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_23826996f557 BOOLEAN;
  p_RelatedEntityNameFieldMap_23826996f557 VARCHAR(255);
  p_RelatedEntityDisplayType_23826996f557 VARCHAR(20);
  p_EntityIDFieldName_23826996f557 VARCHAR(100);
  p_ScopeDefault_23826996f557 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_23826996f557 BOOLEAN;
  p_ValuesToPackWithSchema_23826996f557 VARCHAR(10);
  p_Status_23826996f557 VARCHAR(25);
  p_AutoUpdateIsNameField_23826996f557 BOOLEAN;
  p_AutoUpdateDefaultInView_23826996f557 BOOLEAN;
  p_AutoUpdateCategory_23826996f557 BOOLEAN;
  p_AutoUpdateDisplayName_23826996f557 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_23826996f557 BOOLEAN;
  p_Encrypt_23826996f557 BOOLEAN;
  p_EncryptionKeyID_23826996f557 UUID;
  p_AllowDecryptInAPI_23826996f557 BOOLEAN;
  p_SendEncryptedValue_23826996f557 BOOLEAN;
  p_IsSoftPrimaryKey_23826996f557 BOOLEAN;
  p_IsSoftForeignKey_23826996f557 BOOLEAN;
  p_RelatedEntityJoinFields_23826996f557 TEXT;
  p_JSONType_23826996f557 VARCHAR(255);
  p_JSONTypeIsArray_23826996f557 BOOLEAN;
  p_JSONTypeDefinition_23826996f557 TEXT;
  p_UserSearchPredicateAPI_23826996f557 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_23826996f557 BOOLEAN;
  p_AutoUpdateFullTextSearch_23826996f557 BOOLEAN;
  p_AutoUpdateExtendedType_23826996f557 BOOLEAN;
  p_IsComputed_23826996f557 BOOLEAN;
  p_EmbeddedRecord_23826996f557 TEXT;
  p_Configuration_23826996f557 TEXT;
  p_ID_23826996f557 UUID;
BEGIN
  p_DisplayName_23826996f557 := 'Auto Renew';
  p_Description_23826996f557 := 'Whether the agreement auto-renews, AS THE PAPER STATES IT. True or false, no third state. Distinct from the subscriptions operational setting in orders, which someone can change later; when the two disagree that is a finding, not a bug.';
  p_AutoUpdateDescription_23826996f557 := TRUE;
  p_IsPrimaryKey_23826996f557 := FALSE;
  p_IsUnique_23826996f557 := FALSE;
  p_Category_23826996f557 := 'Renewal Terms';
  p_ValueListType_23826996f557 := 'None';
  p_DefaultInView_23826996f557 := TRUE;
  p_DefaultColumnWidth_23826996f557 := 150;
  p_AllowUpdateAPI_23826996f557 := TRUE;
  p_AllowUpdateInView_23826996f557 := TRUE;
  p_IncludeInUserSearchAPI_23826996f557 := FALSE;
  p_FullTextSearchEnabled_23826996f557 := FALSE;
  p_IncludeInGeneratedForm_23826996f557 := TRUE;
  p_GeneratedFormSection_23826996f557 := 'Category';
  p_IsNameField_23826996f557 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_23826996f557 := FALSE;
  p_RelatedEntityDisplayType_23826996f557 := 'Search';
  p_AutoUpdateRelatedEntityInfo_23826996f557 := TRUE;
  p_ValuesToPackWithSchema_23826996f557 := 'Auto';
  p_Status_23826996f557 := 'Active';
  p_AutoUpdateIsNameField_23826996f557 := TRUE;
  p_AutoUpdateDefaultInView_23826996f557 := TRUE;
  p_AutoUpdateCategory_23826996f557 := TRUE;
  p_AutoUpdateDisplayName_23826996f557 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_23826996f557 := TRUE;
  p_Encrypt_23826996f557 := FALSE;
  p_AllowDecryptInAPI_23826996f557 := FALSE;
  p_SendEncryptedValue_23826996f557 := FALSE;
  p_IsSoftPrimaryKey_23826996f557 := FALSE;
  p_IsSoftForeignKey_23826996f557 := FALSE;
  p_JSONTypeIsArray_23826996f557 := FALSE;
  p_UserSearchPredicateAPI_23826996f557 := 'Contains';
  p_AutoUpdateUserSearchPredicate_23826996f557 := TRUE;
  p_AutoUpdateFullTextSearch_23826996f557 := TRUE;
  p_AutoUpdateExtendedType_23826996f557 := TRUE;
  p_IsComputed_23826996f557 := FALSE;
  p_ID_23826996f557 := '8B3C517C-FF01-4121-A740-632DF75F3C05';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_23826996f557,
    'Description', p_Description_23826996f557,
    'AutoUpdateDescription', p_AutoUpdateDescription_23826996f557,
    'IsPrimaryKey', p_IsPrimaryKey_23826996f557,
    'IsUnique', p_IsUnique_23826996f557,
    'Category', p_Category_23826996f557,
    'ValueListType', p_ValueListType_23826996f557,
    'ExtendedType', p_ExtendedType_23826996f557,
    'CodeType', p_CodeType_23826996f557,
    'DefaultInView', p_DefaultInView_23826996f557,
    'ViewCellTemplate', p_ViewCellTemplate_23826996f557,
    'DefaultColumnWidth', p_DefaultColumnWidth_23826996f557,
    'AllowUpdateAPI', p_AllowUpdateAPI_23826996f557,
    'AllowUpdateInView', p_AllowUpdateInView_23826996f557,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_23826996f557,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_23826996f557,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_23826996f557,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_23826996f557,
    'GeneratedFormSection', p_GeneratedFormSection_23826996f557,
    'IsNameField', p_IsNameField_23826996f557,
    'RelatedEntityID', p_RelatedEntityID_23826996f557,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_23826996f557,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_23826996f557,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_23826996f557,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_23826996f557,
    'EntityIDFieldName', p_EntityIDFieldName_23826996f557,
    'ScopeDefault', p_ScopeDefault_23826996f557,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_23826996f557,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_23826996f557,
    'Status', p_Status_23826996f557,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_23826996f557,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_23826996f557,
    'AutoUpdateCategory', p_AutoUpdateCategory_23826996f557,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_23826996f557,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_23826996f557,
    'Encrypt', p_Encrypt_23826996f557,
    'EncryptionKeyID', p_EncryptionKeyID_23826996f557,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_23826996f557,
    'SendEncryptedValue', p_SendEncryptedValue_23826996f557,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_23826996f557,
    'IsSoftForeignKey', p_IsSoftForeignKey_23826996f557,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_23826996f557,
    'JSONType', p_JSONType_23826996f557,
    'JSONTypeIsArray', p_JSONTypeIsArray_23826996f557,
    'JSONTypeDefinition', p_JSONTypeDefinition_23826996f557,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_23826996f557,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_23826996f557,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_23826996f557,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_23826996f557,
    'IsComputed', p_IsComputed_23826996f557
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_23826996f557,
    'Configuration', p_Configuration_23826996f557,
    'ID', p_ID_23826996f557
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_23826996f557, p_Description := p_Description_23826996f557, p_AutoUpdateDescription := p_AutoUpdateDescription_23826996f557, p_IsPrimaryKey := p_IsPrimaryKey_23826996f557, p_IsUnique := p_IsUnique_23826996f557, p_Category := p_Category_23826996f557, p_ValueListType := p_ValueListType_23826996f557, p_ExtendedType := p_ExtendedType_23826996f557, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_23826996f557, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_23826996f557, p_ViewCellTemplate := p_ViewCellTemplate_23826996f557, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_23826996f557, p_AllowUpdateAPI := p_AllowUpdateAPI_23826996f557, p_AllowUpdateInView := p_AllowUpdateInView_23826996f557, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_23826996f557, p_FullTextSearchEnabled := p_FullTextSearchEnabled_23826996f557, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_23826996f557, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_23826996f557, p_GeneratedFormSection := p_GeneratedFormSection_23826996f557, p_IsNameField := p_IsNameField_23826996f557, p_RelatedEntityID := p_RelatedEntityID_23826996f557, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_23826996f557, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_23826996f557, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_23826996f557, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_23826996f557, p_EntityIDFieldName := p_EntityIDFieldName_23826996f557, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_23826996f557, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_23826996f557, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_23826996f557, p_Status := p_Status_23826996f557, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_23826996f557, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_23826996f557, p_AutoUpdateCategory := p_AutoUpdateCategory_23826996f557, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_23826996f557, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_23826996f557, p_Encrypt := p_Encrypt_23826996f557, p_EncryptionKeyID := p_EncryptionKeyID_23826996f557, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_23826996f557, p_SendEncryptedValue := p_SendEncryptedValue_23826996f557, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_23826996f557, p_IsSoftForeignKey := p_IsSoftForeignKey_23826996f557, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_23826996f557, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_23826996f557, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_23826996f557, p_JSONTypeDefinition := p_JSONTypeDefinition_23826996f557, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_23826996f557, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_23826996f557, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_23826996f557, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_23826996f557, p_IsComputed := p_IsComputed_23826996f557, p_EmbeddedRecord := p_EmbeddedRecord_23826996f557, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_23826996f557, p_Configuration_Clear := TRUE, p_ID := p_ID_23826996f557);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_a2df3cb6994d VARCHAR(255);
  p_Description_a2df3cb6994d TEXT;
  p_AutoUpdateDescription_a2df3cb6994d BOOLEAN;
  p_IsPrimaryKey_a2df3cb6994d BOOLEAN;
  p_IsUnique_a2df3cb6994d BOOLEAN;
  p_Category_a2df3cb6994d VARCHAR(255);
  p_ValueListType_a2df3cb6994d VARCHAR(20);
  p_ExtendedType_a2df3cb6994d VARCHAR(50);
  p_CodeType_a2df3cb6994d VARCHAR(50);
  p_DefaultInView_a2df3cb6994d BOOLEAN;
  p_ViewCellTemplate_a2df3cb6994d TEXT;
  p_DefaultColumnWidth_a2df3cb6994d INTEGER;
  p_AllowUpdateAPI_a2df3cb6994d BOOLEAN;
  p_AllowUpdateInView_a2df3cb6994d BOOLEAN;
  p_IncludeInUserSearchAPI_a2df3cb6994d BOOLEAN;
  p_FullTextSearchEnabled_a2df3cb6994d BOOLEAN;
  p_UserSearchParamFormatAPI_a2df3cb6994d VARCHAR(500);
  p_IncludeInGeneratedForm_a2df3cb6994d BOOLEAN;
  p_GeneratedFormSection_a2df3cb6994d VARCHAR(10);
  p_IsNameField_a2df3cb6994d BOOLEAN;
  p_RelatedEntityID_a2df3cb6994d UUID;
  p_RelatedEntityFieldName_a2df3cb6994d VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d BOOLEAN;
  p_RelatedEntityNameFieldMap_a2df3cb6994d VARCHAR(255);
  p_RelatedEntityDisplayType_a2df3cb6994d VARCHAR(20);
  p_EntityIDFieldName_a2df3cb6994d VARCHAR(100);
  p_ScopeDefault_a2df3cb6994d VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_a2df3cb6994d BOOLEAN;
  p_ValuesToPackWithSchema_a2df3cb6994d VARCHAR(10);
  p_Status_a2df3cb6994d VARCHAR(25);
  p_AutoUpdateIsNameField_a2df3cb6994d BOOLEAN;
  p_AutoUpdateDefaultInView_a2df3cb6994d BOOLEAN;
  p_AutoUpdateCategory_a2df3cb6994d BOOLEAN;
  p_AutoUpdateDisplayName_a2df3cb6994d BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d BOOLEAN;
  p_Encrypt_a2df3cb6994d BOOLEAN;
  p_EncryptionKeyID_a2df3cb6994d UUID;
  p_AllowDecryptInAPI_a2df3cb6994d BOOLEAN;
  p_SendEncryptedValue_a2df3cb6994d BOOLEAN;
  p_IsSoftPrimaryKey_a2df3cb6994d BOOLEAN;
  p_IsSoftForeignKey_a2df3cb6994d BOOLEAN;
  p_RelatedEntityJoinFields_a2df3cb6994d TEXT;
  p_JSONType_a2df3cb6994d VARCHAR(255);
  p_JSONTypeIsArray_a2df3cb6994d BOOLEAN;
  p_JSONTypeDefinition_a2df3cb6994d TEXT;
  p_UserSearchPredicateAPI_a2df3cb6994d VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_a2df3cb6994d BOOLEAN;
  p_AutoUpdateFullTextSearch_a2df3cb6994d BOOLEAN;
  p_AutoUpdateExtendedType_a2df3cb6994d BOOLEAN;
  p_IsComputed_a2df3cb6994d BOOLEAN;
  p_EmbeddedRecord_a2df3cb6994d TEXT;
  p_Configuration_a2df3cb6994d TEXT;
  p_ID_a2df3cb6994d UUID;
BEGIN
  p_DisplayName_a2df3cb6994d := 'Is Awaiting Document';
  p_AutoUpdateDescription_a2df3cb6994d := TRUE;
  p_IsPrimaryKey_a2df3cb6994d := FALSE;
  p_IsUnique_a2df3cb6994d := FALSE;
  p_ValueListType_a2df3cb6994d := 'None';
  p_DefaultInView_a2df3cb6994d := TRUE;
  p_DefaultColumnWidth_a2df3cb6994d := 150;
  p_AllowUpdateAPI_a2df3cb6994d := FALSE;
  p_AllowUpdateInView_a2df3cb6994d := TRUE;
  p_IncludeInUserSearchAPI_a2df3cb6994d := FALSE;
  p_FullTextSearchEnabled_a2df3cb6994d := FALSE;
  p_IncludeInGeneratedForm_a2df3cb6994d := TRUE;
  p_GeneratedFormSection_a2df3cb6994d := 'Details';
  p_IsNameField_a2df3cb6994d := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d := TRUE;
  p_RelatedEntityDisplayType_a2df3cb6994d := 'Search';
  p_AutoUpdateRelatedEntityInfo_a2df3cb6994d := TRUE;
  p_ValuesToPackWithSchema_a2df3cb6994d := 'Auto';
  p_Status_a2df3cb6994d := 'Active';
  p_AutoUpdateIsNameField_a2df3cb6994d := TRUE;
  p_AutoUpdateDefaultInView_a2df3cb6994d := TRUE;
  p_AutoUpdateCategory_a2df3cb6994d := TRUE;
  p_AutoUpdateDisplayName_a2df3cb6994d := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d := TRUE;
  p_Encrypt_a2df3cb6994d := FALSE;
  p_AllowDecryptInAPI_a2df3cb6994d := FALSE;
  p_SendEncryptedValue_a2df3cb6994d := FALSE;
  p_IsSoftPrimaryKey_a2df3cb6994d := FALSE;
  p_IsSoftForeignKey_a2df3cb6994d := FALSE;
  p_JSONTypeIsArray_a2df3cb6994d := FALSE;
  p_UserSearchPredicateAPI_a2df3cb6994d := 'Contains';
  p_AutoUpdateUserSearchPredicate_a2df3cb6994d := TRUE;
  p_AutoUpdateFullTextSearch_a2df3cb6994d := TRUE;
  p_AutoUpdateExtendedType_a2df3cb6994d := TRUE;
  p_IsComputed_a2df3cb6994d := FALSE;
  SELECT "ID" INTO p_ID_a2df3cb6994d FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'IsAwaitingDocument';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_a2df3cb6994d,
    'Description', p_Description_a2df3cb6994d,
    'AutoUpdateDescription', p_AutoUpdateDescription_a2df3cb6994d,
    'IsPrimaryKey', p_IsPrimaryKey_a2df3cb6994d,
    'IsUnique', p_IsUnique_a2df3cb6994d,
    'Category', p_Category_a2df3cb6994d,
    'ValueListType', p_ValueListType_a2df3cb6994d,
    'ExtendedType', p_ExtendedType_a2df3cb6994d,
    'CodeType', p_CodeType_a2df3cb6994d,
    'DefaultInView', p_DefaultInView_a2df3cb6994d,
    'ViewCellTemplate', p_ViewCellTemplate_a2df3cb6994d,
    'DefaultColumnWidth', p_DefaultColumnWidth_a2df3cb6994d,
    'AllowUpdateAPI', p_AllowUpdateAPI_a2df3cb6994d,
    'AllowUpdateInView', p_AllowUpdateInView_a2df3cb6994d,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_a2df3cb6994d,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_a2df3cb6994d,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_a2df3cb6994d,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_a2df3cb6994d,
    'GeneratedFormSection', p_GeneratedFormSection_a2df3cb6994d,
    'IsNameField', p_IsNameField_a2df3cb6994d,
    'RelatedEntityID', p_RelatedEntityID_a2df3cb6994d,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_a2df3cb6994d,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_a2df3cb6994d,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_a2df3cb6994d,
    'EntityIDFieldName', p_EntityIDFieldName_a2df3cb6994d,
    'ScopeDefault', p_ScopeDefault_a2df3cb6994d,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_a2df3cb6994d,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_a2df3cb6994d,
    'Status', p_Status_a2df3cb6994d,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_a2df3cb6994d,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_a2df3cb6994d,
    'AutoUpdateCategory', p_AutoUpdateCategory_a2df3cb6994d,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_a2df3cb6994d,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d,
    'Encrypt', p_Encrypt_a2df3cb6994d,
    'EncryptionKeyID', p_EncryptionKeyID_a2df3cb6994d,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_a2df3cb6994d,
    'SendEncryptedValue', p_SendEncryptedValue_a2df3cb6994d,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_a2df3cb6994d,
    'IsSoftForeignKey', p_IsSoftForeignKey_a2df3cb6994d,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_a2df3cb6994d,
    'JSONType', p_JSONType_a2df3cb6994d,
    'JSONTypeIsArray', p_JSONTypeIsArray_a2df3cb6994d,
    'JSONTypeDefinition', p_JSONTypeDefinition_a2df3cb6994d,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_a2df3cb6994d,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_a2df3cb6994d,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_a2df3cb6994d,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_a2df3cb6994d,
    'IsComputed', p_IsComputed_a2df3cb6994d
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_a2df3cb6994d,
    'Configuration', p_Configuration_a2df3cb6994d,
    'ID', p_ID_a2df3cb6994d
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_a2df3cb6994d, p_Description := p_Description_a2df3cb6994d, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_a2df3cb6994d, p_IsPrimaryKey := p_IsPrimaryKey_a2df3cb6994d, p_IsUnique := p_IsUnique_a2df3cb6994d, p_Category := p_Category_a2df3cb6994d, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_a2df3cb6994d, p_ExtendedType := p_ExtendedType_a2df3cb6994d, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_a2df3cb6994d, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_a2df3cb6994d, p_ViewCellTemplate := p_ViewCellTemplate_a2df3cb6994d, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_a2df3cb6994d, p_AllowUpdateAPI := p_AllowUpdateAPI_a2df3cb6994d, p_AllowUpdateInView := p_AllowUpdateInView_a2df3cb6994d, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_a2df3cb6994d, p_FullTextSearchEnabled := p_FullTextSearchEnabled_a2df3cb6994d, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_a2df3cb6994d, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_a2df3cb6994d, p_GeneratedFormSection := p_GeneratedFormSection_a2df3cb6994d, p_IsNameField := p_IsNameField_a2df3cb6994d, p_RelatedEntityID := p_RelatedEntityID_a2df3cb6994d, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_a2df3cb6994d, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_a2df3cb6994d, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_a2df3cb6994d, p_EntityIDFieldName := p_EntityIDFieldName_a2df3cb6994d, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_a2df3cb6994d, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_a2df3cb6994d, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_a2df3cb6994d, p_Status := p_Status_a2df3cb6994d, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_a2df3cb6994d, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_a2df3cb6994d, p_AutoUpdateCategory := p_AutoUpdateCategory_a2df3cb6994d, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_a2df3cb6994d, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d, p_Encrypt := p_Encrypt_a2df3cb6994d, p_EncryptionKeyID := p_EncryptionKeyID_a2df3cb6994d, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_a2df3cb6994d, p_SendEncryptedValue := p_SendEncryptedValue_a2df3cb6994d, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_a2df3cb6994d, p_IsSoftForeignKey := p_IsSoftForeignKey_a2df3cb6994d, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_a2df3cb6994d, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_a2df3cb6994d, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_a2df3cb6994d, p_JSONTypeDefinition := p_JSONTypeDefinition_a2df3cb6994d, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_a2df3cb6994d, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_a2df3cb6994d, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_a2df3cb6994d, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_a2df3cb6994d, p_IsComputed := p_IsComputed_a2df3cb6994d, p_EmbeddedRecord := p_EmbeddedRecord_a2df3cb6994d, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_a2df3cb6994d, p_Configuration_Clear := TRUE, p_ID := p_ID_a2df3cb6994d);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_8907ce35ffbe VARCHAR(255);
  p_Description_8907ce35ffbe TEXT;
  p_AutoUpdateDescription_8907ce35ffbe BOOLEAN;
  p_IsPrimaryKey_8907ce35ffbe BOOLEAN;
  p_IsUnique_8907ce35ffbe BOOLEAN;
  p_Category_8907ce35ffbe VARCHAR(255);
  p_ValueListType_8907ce35ffbe VARCHAR(20);
  p_ExtendedType_8907ce35ffbe VARCHAR(50);
  p_CodeType_8907ce35ffbe VARCHAR(50);
  p_DefaultInView_8907ce35ffbe BOOLEAN;
  p_ViewCellTemplate_8907ce35ffbe TEXT;
  p_DefaultColumnWidth_8907ce35ffbe INTEGER;
  p_AllowUpdateAPI_8907ce35ffbe BOOLEAN;
  p_AllowUpdateInView_8907ce35ffbe BOOLEAN;
  p_IncludeInUserSearchAPI_8907ce35ffbe BOOLEAN;
  p_FullTextSearchEnabled_8907ce35ffbe BOOLEAN;
  p_UserSearchParamFormatAPI_8907ce35ffbe VARCHAR(500);
  p_IncludeInGeneratedForm_8907ce35ffbe BOOLEAN;
  p_GeneratedFormSection_8907ce35ffbe VARCHAR(10);
  p_IsNameField_8907ce35ffbe BOOLEAN;
  p_RelatedEntityID_8907ce35ffbe UUID;
  p_RelatedEntityFieldName_8907ce35ffbe VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_8907ce35ffbe BOOLEAN;
  p_RelatedEntityNameFieldMap_8907ce35ffbe VARCHAR(255);
  p_RelatedEntityDisplayType_8907ce35ffbe VARCHAR(20);
  p_EntityIDFieldName_8907ce35ffbe VARCHAR(100);
  p_ScopeDefault_8907ce35ffbe VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_8907ce35ffbe BOOLEAN;
  p_ValuesToPackWithSchema_8907ce35ffbe VARCHAR(10);
  p_Status_8907ce35ffbe VARCHAR(25);
  p_AutoUpdateIsNameField_8907ce35ffbe BOOLEAN;
  p_AutoUpdateDefaultInView_8907ce35ffbe BOOLEAN;
  p_AutoUpdateCategory_8907ce35ffbe BOOLEAN;
  p_AutoUpdateDisplayName_8907ce35ffbe BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_8907ce35ffbe BOOLEAN;
  p_Encrypt_8907ce35ffbe BOOLEAN;
  p_EncryptionKeyID_8907ce35ffbe UUID;
  p_AllowDecryptInAPI_8907ce35ffbe BOOLEAN;
  p_SendEncryptedValue_8907ce35ffbe BOOLEAN;
  p_IsSoftPrimaryKey_8907ce35ffbe BOOLEAN;
  p_IsSoftForeignKey_8907ce35ffbe BOOLEAN;
  p_RelatedEntityJoinFields_8907ce35ffbe TEXT;
  p_JSONType_8907ce35ffbe VARCHAR(255);
  p_JSONTypeIsArray_8907ce35ffbe BOOLEAN;
  p_JSONTypeDefinition_8907ce35ffbe TEXT;
  p_UserSearchPredicateAPI_8907ce35ffbe VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_8907ce35ffbe BOOLEAN;
  p_AutoUpdateFullTextSearch_8907ce35ffbe BOOLEAN;
  p_AutoUpdateExtendedType_8907ce35ffbe BOOLEAN;
  p_IsComputed_8907ce35ffbe BOOLEAN;
  p_EmbeddedRecord_8907ce35ffbe TEXT;
  p_Configuration_8907ce35ffbe TEXT;
  p_ID_8907ce35ffbe UUID;
BEGIN
  p_DisplayName_8907ce35ffbe := 'Primary Contact Name';
  p_AutoUpdateDescription_8907ce35ffbe := TRUE;
  p_IsPrimaryKey_8907ce35ffbe := FALSE;
  p_IsUnique_8907ce35ffbe := FALSE;
  p_Category_8907ce35ffbe := 'Stakeholders';
  p_ValueListType_8907ce35ffbe := 'None';
  p_DefaultInView_8907ce35ffbe := TRUE;
  p_DefaultColumnWidth_8907ce35ffbe := 150;
  p_AllowUpdateAPI_8907ce35ffbe := FALSE;
  p_AllowUpdateInView_8907ce35ffbe := TRUE;
  p_IncludeInUserSearchAPI_8907ce35ffbe := FALSE;
  p_FullTextSearchEnabled_8907ce35ffbe := FALSE;
  p_IncludeInGeneratedForm_8907ce35ffbe := TRUE;
  p_GeneratedFormSection_8907ce35ffbe := 'Category';
  p_IsNameField_8907ce35ffbe := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_8907ce35ffbe := FALSE;
  p_RelatedEntityDisplayType_8907ce35ffbe := 'Search';
  p_AutoUpdateRelatedEntityInfo_8907ce35ffbe := TRUE;
  p_ValuesToPackWithSchema_8907ce35ffbe := 'Auto';
  p_Status_8907ce35ffbe := 'Active';
  p_AutoUpdateIsNameField_8907ce35ffbe := TRUE;
  p_AutoUpdateDefaultInView_8907ce35ffbe := TRUE;
  p_AutoUpdateCategory_8907ce35ffbe := TRUE;
  p_AutoUpdateDisplayName_8907ce35ffbe := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_8907ce35ffbe := TRUE;
  p_Encrypt_8907ce35ffbe := FALSE;
  p_AllowDecryptInAPI_8907ce35ffbe := FALSE;
  p_SendEncryptedValue_8907ce35ffbe := FALSE;
  p_IsSoftPrimaryKey_8907ce35ffbe := FALSE;
  p_IsSoftForeignKey_8907ce35ffbe := FALSE;
  p_JSONTypeIsArray_8907ce35ffbe := FALSE;
  p_UserSearchPredicateAPI_8907ce35ffbe := 'Contains';
  p_AutoUpdateUserSearchPredicate_8907ce35ffbe := TRUE;
  p_AutoUpdateFullTextSearch_8907ce35ffbe := TRUE;
  p_AutoUpdateExtendedType_8907ce35ffbe := TRUE;
  p_IsComputed_8907ce35ffbe := FALSE;
  p_ID_8907ce35ffbe := '2999F51A-9170-4028-B142-2F33D7E056ED';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_8907ce35ffbe,
    'Description', p_Description_8907ce35ffbe,
    'AutoUpdateDescription', p_AutoUpdateDescription_8907ce35ffbe,
    'IsPrimaryKey', p_IsPrimaryKey_8907ce35ffbe,
    'IsUnique', p_IsUnique_8907ce35ffbe,
    'Category', p_Category_8907ce35ffbe,
    'ValueListType', p_ValueListType_8907ce35ffbe,
    'ExtendedType', p_ExtendedType_8907ce35ffbe,
    'CodeType', p_CodeType_8907ce35ffbe,
    'DefaultInView', p_DefaultInView_8907ce35ffbe,
    'ViewCellTemplate', p_ViewCellTemplate_8907ce35ffbe,
    'DefaultColumnWidth', p_DefaultColumnWidth_8907ce35ffbe,
    'AllowUpdateAPI', p_AllowUpdateAPI_8907ce35ffbe,
    'AllowUpdateInView', p_AllowUpdateInView_8907ce35ffbe,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_8907ce35ffbe,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_8907ce35ffbe,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_8907ce35ffbe,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_8907ce35ffbe,
    'GeneratedFormSection', p_GeneratedFormSection_8907ce35ffbe,
    'IsNameField', p_IsNameField_8907ce35ffbe,
    'RelatedEntityID', p_RelatedEntityID_8907ce35ffbe,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_8907ce35ffbe,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_8907ce35ffbe,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_8907ce35ffbe,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_8907ce35ffbe,
    'EntityIDFieldName', p_EntityIDFieldName_8907ce35ffbe,
    'ScopeDefault', p_ScopeDefault_8907ce35ffbe,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_8907ce35ffbe,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_8907ce35ffbe,
    'Status', p_Status_8907ce35ffbe,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_8907ce35ffbe,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_8907ce35ffbe,
    'AutoUpdateCategory', p_AutoUpdateCategory_8907ce35ffbe,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_8907ce35ffbe,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_8907ce35ffbe,
    'Encrypt', p_Encrypt_8907ce35ffbe,
    'EncryptionKeyID', p_EncryptionKeyID_8907ce35ffbe,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_8907ce35ffbe,
    'SendEncryptedValue', p_SendEncryptedValue_8907ce35ffbe,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_8907ce35ffbe,
    'IsSoftForeignKey', p_IsSoftForeignKey_8907ce35ffbe,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_8907ce35ffbe,
    'JSONType', p_JSONType_8907ce35ffbe,
    'JSONTypeIsArray', p_JSONTypeIsArray_8907ce35ffbe,
    'JSONTypeDefinition', p_JSONTypeDefinition_8907ce35ffbe,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_8907ce35ffbe,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_8907ce35ffbe,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_8907ce35ffbe,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_8907ce35ffbe,
    'IsComputed', p_IsComputed_8907ce35ffbe
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_8907ce35ffbe,
    'Configuration', p_Configuration_8907ce35ffbe,
    'ID', p_ID_8907ce35ffbe
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_8907ce35ffbe, p_Description := p_Description_8907ce35ffbe, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_8907ce35ffbe, p_IsPrimaryKey := p_IsPrimaryKey_8907ce35ffbe, p_IsUnique := p_IsUnique_8907ce35ffbe, p_Category := p_Category_8907ce35ffbe, p_ValueListType := p_ValueListType_8907ce35ffbe, p_ExtendedType := p_ExtendedType_8907ce35ffbe, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_8907ce35ffbe, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_8907ce35ffbe, p_ViewCellTemplate := p_ViewCellTemplate_8907ce35ffbe, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_8907ce35ffbe, p_AllowUpdateAPI := p_AllowUpdateAPI_8907ce35ffbe, p_AllowUpdateInView := p_AllowUpdateInView_8907ce35ffbe, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_8907ce35ffbe, p_FullTextSearchEnabled := p_FullTextSearchEnabled_8907ce35ffbe, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_8907ce35ffbe, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_8907ce35ffbe, p_GeneratedFormSection := p_GeneratedFormSection_8907ce35ffbe, p_IsNameField := p_IsNameField_8907ce35ffbe, p_RelatedEntityID := p_RelatedEntityID_8907ce35ffbe, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_8907ce35ffbe, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_8907ce35ffbe, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_8907ce35ffbe, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_8907ce35ffbe, p_EntityIDFieldName := p_EntityIDFieldName_8907ce35ffbe, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_8907ce35ffbe, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_8907ce35ffbe, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_8907ce35ffbe, p_Status := p_Status_8907ce35ffbe, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_8907ce35ffbe, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_8907ce35ffbe, p_AutoUpdateCategory := p_AutoUpdateCategory_8907ce35ffbe, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_8907ce35ffbe, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_8907ce35ffbe, p_Encrypt := p_Encrypt_8907ce35ffbe, p_EncryptionKeyID := p_EncryptionKeyID_8907ce35ffbe, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_8907ce35ffbe, p_SendEncryptedValue := p_SendEncryptedValue_8907ce35ffbe, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_8907ce35ffbe, p_IsSoftForeignKey := p_IsSoftForeignKey_8907ce35ffbe, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_8907ce35ffbe, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_8907ce35ffbe, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_8907ce35ffbe, p_JSONTypeDefinition := p_JSONTypeDefinition_8907ce35ffbe, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_8907ce35ffbe, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_8907ce35ffbe, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_8907ce35ffbe, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_8907ce35ffbe, p_IsComputed := p_IsComputed_8907ce35ffbe, p_EmbeddedRecord := p_EmbeddedRecord_8907ce35ffbe, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_8907ce35ffbe, p_Configuration_Clear := TRUE, p_ID := p_ID_8907ce35ffbe);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_20932574819f VARCHAR(255);
  p_Description_20932574819f TEXT;
  p_AutoUpdateDescription_20932574819f BOOLEAN;
  p_IsPrimaryKey_20932574819f BOOLEAN;
  p_IsUnique_20932574819f BOOLEAN;
  p_Category_20932574819f VARCHAR(255);
  p_ValueListType_20932574819f VARCHAR(20);
  p_ExtendedType_20932574819f VARCHAR(50);
  p_CodeType_20932574819f VARCHAR(50);
  p_DefaultInView_20932574819f BOOLEAN;
  p_ViewCellTemplate_20932574819f TEXT;
  p_DefaultColumnWidth_20932574819f INTEGER;
  p_AllowUpdateAPI_20932574819f BOOLEAN;
  p_AllowUpdateInView_20932574819f BOOLEAN;
  p_IncludeInUserSearchAPI_20932574819f BOOLEAN;
  p_FullTextSearchEnabled_20932574819f BOOLEAN;
  p_UserSearchParamFormatAPI_20932574819f VARCHAR(500);
  p_IncludeInGeneratedForm_20932574819f BOOLEAN;
  p_GeneratedFormSection_20932574819f VARCHAR(10);
  p_IsNameField_20932574819f BOOLEAN;
  p_RelatedEntityID_20932574819f UUID;
  p_RelatedEntityFieldName_20932574819f VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_20932574819f BOOLEAN;
  p_RelatedEntityNameFieldMap_20932574819f VARCHAR(255);
  p_RelatedEntityDisplayType_20932574819f VARCHAR(20);
  p_EntityIDFieldName_20932574819f VARCHAR(100);
  p_ScopeDefault_20932574819f VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_20932574819f BOOLEAN;
  p_ValuesToPackWithSchema_20932574819f VARCHAR(10);
  p_Status_20932574819f VARCHAR(25);
  p_AutoUpdateIsNameField_20932574819f BOOLEAN;
  p_AutoUpdateDefaultInView_20932574819f BOOLEAN;
  p_AutoUpdateCategory_20932574819f BOOLEAN;
  p_AutoUpdateDisplayName_20932574819f BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_20932574819f BOOLEAN;
  p_Encrypt_20932574819f BOOLEAN;
  p_EncryptionKeyID_20932574819f UUID;
  p_AllowDecryptInAPI_20932574819f BOOLEAN;
  p_SendEncryptedValue_20932574819f BOOLEAN;
  p_IsSoftPrimaryKey_20932574819f BOOLEAN;
  p_IsSoftForeignKey_20932574819f BOOLEAN;
  p_RelatedEntityJoinFields_20932574819f TEXT;
  p_JSONType_20932574819f VARCHAR(255);
  p_JSONTypeIsArray_20932574819f BOOLEAN;
  p_JSONTypeDefinition_20932574819f TEXT;
  p_UserSearchPredicateAPI_20932574819f VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_20932574819f BOOLEAN;
  p_AutoUpdateFullTextSearch_20932574819f BOOLEAN;
  p_AutoUpdateExtendedType_20932574819f BOOLEAN;
  p_IsComputed_20932574819f BOOLEAN;
  p_EmbeddedRecord_20932574819f TEXT;
  p_Configuration_20932574819f TEXT;
  p_ID_20932574819f UUID;
BEGIN
  p_DisplayName_20932574819f := 'State';
  p_AutoUpdateDescription_20932574819f := TRUE;
  p_IsPrimaryKey_20932574819f := FALSE;
  p_IsUnique_20932574819f := FALSE;
  p_ValueListType_20932574819f := 'None';
  p_DefaultInView_20932574819f := TRUE;
  p_DefaultColumnWidth_20932574819f := 150;
  p_AllowUpdateAPI_20932574819f := FALSE;
  p_AllowUpdateInView_20932574819f := TRUE;
  p_IncludeInUserSearchAPI_20932574819f := FALSE;
  p_FullTextSearchEnabled_20932574819f := FALSE;
  p_IncludeInGeneratedForm_20932574819f := FALSE;
  p_GeneratedFormSection_20932574819f := 'Details';
  p_IsNameField_20932574819f := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_20932574819f := TRUE;
  p_RelatedEntityDisplayType_20932574819f := 'Search';
  p_AutoUpdateRelatedEntityInfo_20932574819f := TRUE;
  p_ValuesToPackWithSchema_20932574819f := 'Auto';
  p_Status_20932574819f := 'Active';
  p_AutoUpdateIsNameField_20932574819f := TRUE;
  p_AutoUpdateDefaultInView_20932574819f := TRUE;
  p_AutoUpdateCategory_20932574819f := TRUE;
  p_AutoUpdateDisplayName_20932574819f := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_20932574819f := TRUE;
  p_Encrypt_20932574819f := FALSE;
  p_AllowDecryptInAPI_20932574819f := FALSE;
  p_SendEncryptedValue_20932574819f := FALSE;
  p_IsSoftPrimaryKey_20932574819f := FALSE;
  p_IsSoftForeignKey_20932574819f := FALSE;
  p_JSONTypeIsArray_20932574819f := FALSE;
  p_UserSearchPredicateAPI_20932574819f := 'Contains';
  p_AutoUpdateUserSearchPredicate_20932574819f := TRUE;
  p_AutoUpdateFullTextSearch_20932574819f := TRUE;
  p_AutoUpdateExtendedType_20932574819f := TRUE;
  p_IsComputed_20932574819f := FALSE;
  SELECT "ID" INTO p_ID_20932574819f FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'State';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_20932574819f,
    'Description', p_Description_20932574819f,
    'AutoUpdateDescription', p_AutoUpdateDescription_20932574819f,
    'IsPrimaryKey', p_IsPrimaryKey_20932574819f,
    'IsUnique', p_IsUnique_20932574819f,
    'Category', p_Category_20932574819f,
    'ValueListType', p_ValueListType_20932574819f,
    'ExtendedType', p_ExtendedType_20932574819f,
    'CodeType', p_CodeType_20932574819f,
    'DefaultInView', p_DefaultInView_20932574819f,
    'ViewCellTemplate', p_ViewCellTemplate_20932574819f,
    'DefaultColumnWidth', p_DefaultColumnWidth_20932574819f,
    'AllowUpdateAPI', p_AllowUpdateAPI_20932574819f,
    'AllowUpdateInView', p_AllowUpdateInView_20932574819f,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_20932574819f,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_20932574819f,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_20932574819f,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_20932574819f,
    'GeneratedFormSection', p_GeneratedFormSection_20932574819f,
    'IsNameField', p_IsNameField_20932574819f,
    'RelatedEntityID', p_RelatedEntityID_20932574819f,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_20932574819f,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_20932574819f,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_20932574819f,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_20932574819f,
    'EntityIDFieldName', p_EntityIDFieldName_20932574819f,
    'ScopeDefault', p_ScopeDefault_20932574819f,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_20932574819f,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_20932574819f,
    'Status', p_Status_20932574819f,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_20932574819f,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_20932574819f,
    'AutoUpdateCategory', p_AutoUpdateCategory_20932574819f,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_20932574819f,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_20932574819f,
    'Encrypt', p_Encrypt_20932574819f,
    'EncryptionKeyID', p_EncryptionKeyID_20932574819f,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_20932574819f,
    'SendEncryptedValue', p_SendEncryptedValue_20932574819f,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_20932574819f,
    'IsSoftForeignKey', p_IsSoftForeignKey_20932574819f,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_20932574819f,
    'JSONType', p_JSONType_20932574819f,
    'JSONTypeIsArray', p_JSONTypeIsArray_20932574819f,
    'JSONTypeDefinition', p_JSONTypeDefinition_20932574819f,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_20932574819f,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_20932574819f,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_20932574819f,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_20932574819f,
    'IsComputed', p_IsComputed_20932574819f
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_20932574819f,
    'Configuration', p_Configuration_20932574819f,
    'ID', p_ID_20932574819f
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_20932574819f, p_Description := p_Description_20932574819f, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_20932574819f, p_IsPrimaryKey := p_IsPrimaryKey_20932574819f, p_IsUnique := p_IsUnique_20932574819f, p_Category := p_Category_20932574819f, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_20932574819f, p_ExtendedType := p_ExtendedType_20932574819f, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_20932574819f, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_20932574819f, p_ViewCellTemplate := p_ViewCellTemplate_20932574819f, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_20932574819f, p_AllowUpdateAPI := p_AllowUpdateAPI_20932574819f, p_AllowUpdateInView := p_AllowUpdateInView_20932574819f, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_20932574819f, p_FullTextSearchEnabled := p_FullTextSearchEnabled_20932574819f, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_20932574819f, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_20932574819f, p_GeneratedFormSection := p_GeneratedFormSection_20932574819f, p_IsNameField := p_IsNameField_20932574819f, p_RelatedEntityID := p_RelatedEntityID_20932574819f, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_20932574819f, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_20932574819f, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_20932574819f, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_20932574819f, p_EntityIDFieldName := p_EntityIDFieldName_20932574819f, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_20932574819f, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_20932574819f, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_20932574819f, p_Status := p_Status_20932574819f, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_20932574819f, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_20932574819f, p_AutoUpdateCategory := p_AutoUpdateCategory_20932574819f, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_20932574819f, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_20932574819f, p_Encrypt := p_Encrypt_20932574819f, p_EncryptionKeyID := p_EncryptionKeyID_20932574819f, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_20932574819f, p_SendEncryptedValue := p_SendEncryptedValue_20932574819f, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_20932574819f, p_IsSoftForeignKey := p_IsSoftForeignKey_20932574819f, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_20932574819f, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_20932574819f, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_20932574819f, p_JSONTypeDefinition := p_JSONTypeDefinition_20932574819f, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_20932574819f, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_20932574819f, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_20932574819f, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_20932574819f, p_IsComputed := p_IsComputed_20932574819f, p_EmbeddedRecord := p_EmbeddedRecord_20932574819f, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_20932574819f, p_Configuration_Clear := TRUE, p_ID := p_ID_20932574819f);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_a2df3cb6994d VARCHAR(255);
  p_Description_a2df3cb6994d TEXT;
  p_AutoUpdateDescription_a2df3cb6994d BOOLEAN;
  p_IsPrimaryKey_a2df3cb6994d BOOLEAN;
  p_IsUnique_a2df3cb6994d BOOLEAN;
  p_Category_a2df3cb6994d VARCHAR(255);
  p_ValueListType_a2df3cb6994d VARCHAR(20);
  p_ExtendedType_a2df3cb6994d VARCHAR(50);
  p_CodeType_a2df3cb6994d VARCHAR(50);
  p_DefaultInView_a2df3cb6994d BOOLEAN;
  p_ViewCellTemplate_a2df3cb6994d TEXT;
  p_DefaultColumnWidth_a2df3cb6994d INTEGER;
  p_AllowUpdateAPI_a2df3cb6994d BOOLEAN;
  p_AllowUpdateInView_a2df3cb6994d BOOLEAN;
  p_IncludeInUserSearchAPI_a2df3cb6994d BOOLEAN;
  p_FullTextSearchEnabled_a2df3cb6994d BOOLEAN;
  p_UserSearchParamFormatAPI_a2df3cb6994d VARCHAR(500);
  p_IncludeInGeneratedForm_a2df3cb6994d BOOLEAN;
  p_GeneratedFormSection_a2df3cb6994d VARCHAR(10);
  p_IsNameField_a2df3cb6994d BOOLEAN;
  p_RelatedEntityID_a2df3cb6994d UUID;
  p_RelatedEntityFieldName_a2df3cb6994d VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d BOOLEAN;
  p_RelatedEntityNameFieldMap_a2df3cb6994d VARCHAR(255);
  p_RelatedEntityDisplayType_a2df3cb6994d VARCHAR(20);
  p_EntityIDFieldName_a2df3cb6994d VARCHAR(100);
  p_ScopeDefault_a2df3cb6994d VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_a2df3cb6994d BOOLEAN;
  p_ValuesToPackWithSchema_a2df3cb6994d VARCHAR(10);
  p_Status_a2df3cb6994d VARCHAR(25);
  p_AutoUpdateIsNameField_a2df3cb6994d BOOLEAN;
  p_AutoUpdateDefaultInView_a2df3cb6994d BOOLEAN;
  p_AutoUpdateCategory_a2df3cb6994d BOOLEAN;
  p_AutoUpdateDisplayName_a2df3cb6994d BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d BOOLEAN;
  p_Encrypt_a2df3cb6994d BOOLEAN;
  p_EncryptionKeyID_a2df3cb6994d UUID;
  p_AllowDecryptInAPI_a2df3cb6994d BOOLEAN;
  p_SendEncryptedValue_a2df3cb6994d BOOLEAN;
  p_IsSoftPrimaryKey_a2df3cb6994d BOOLEAN;
  p_IsSoftForeignKey_a2df3cb6994d BOOLEAN;
  p_RelatedEntityJoinFields_a2df3cb6994d TEXT;
  p_JSONType_a2df3cb6994d VARCHAR(255);
  p_JSONTypeIsArray_a2df3cb6994d BOOLEAN;
  p_JSONTypeDefinition_a2df3cb6994d TEXT;
  p_UserSearchPredicateAPI_a2df3cb6994d VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_a2df3cb6994d BOOLEAN;
  p_AutoUpdateFullTextSearch_a2df3cb6994d BOOLEAN;
  p_AutoUpdateExtendedType_a2df3cb6994d BOOLEAN;
  p_IsComputed_a2df3cb6994d BOOLEAN;
  p_EmbeddedRecord_a2df3cb6994d TEXT;
  p_Configuration_a2df3cb6994d TEXT;
  p_ID_a2df3cb6994d UUID;
BEGIN
  p_DisplayName_a2df3cb6994d := 'Is Awaiting Document';
  p_AutoUpdateDescription_a2df3cb6994d := TRUE;
  p_IsPrimaryKey_a2df3cb6994d := FALSE;
  p_IsUnique_a2df3cb6994d := FALSE;
  p_ValueListType_a2df3cb6994d := 'None';
  p_DefaultInView_a2df3cb6994d := TRUE;
  p_DefaultColumnWidth_a2df3cb6994d := 150;
  p_AllowUpdateAPI_a2df3cb6994d := FALSE;
  p_AllowUpdateInView_a2df3cb6994d := TRUE;
  p_IncludeInUserSearchAPI_a2df3cb6994d := FALSE;
  p_FullTextSearchEnabled_a2df3cb6994d := FALSE;
  p_IncludeInGeneratedForm_a2df3cb6994d := FALSE;
  p_GeneratedFormSection_a2df3cb6994d := 'Details';
  p_IsNameField_a2df3cb6994d := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d := TRUE;
  p_RelatedEntityDisplayType_a2df3cb6994d := 'Search';
  p_AutoUpdateRelatedEntityInfo_a2df3cb6994d := TRUE;
  p_ValuesToPackWithSchema_a2df3cb6994d := 'Auto';
  p_Status_a2df3cb6994d := 'Active';
  p_AutoUpdateIsNameField_a2df3cb6994d := TRUE;
  p_AutoUpdateDefaultInView_a2df3cb6994d := TRUE;
  p_AutoUpdateCategory_a2df3cb6994d := TRUE;
  p_AutoUpdateDisplayName_a2df3cb6994d := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d := TRUE;
  p_Encrypt_a2df3cb6994d := FALSE;
  p_AllowDecryptInAPI_a2df3cb6994d := FALSE;
  p_SendEncryptedValue_a2df3cb6994d := FALSE;
  p_IsSoftPrimaryKey_a2df3cb6994d := FALSE;
  p_IsSoftForeignKey_a2df3cb6994d := FALSE;
  p_JSONTypeIsArray_a2df3cb6994d := FALSE;
  p_UserSearchPredicateAPI_a2df3cb6994d := 'Contains';
  p_AutoUpdateUserSearchPredicate_a2df3cb6994d := TRUE;
  p_AutoUpdateFullTextSearch_a2df3cb6994d := TRUE;
  p_AutoUpdateExtendedType_a2df3cb6994d := TRUE;
  p_IsComputed_a2df3cb6994d := FALSE;
  SELECT "ID" INTO p_ID_a2df3cb6994d FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'IsAwaitingDocument';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_a2df3cb6994d,
    'Description', p_Description_a2df3cb6994d,
    'AutoUpdateDescription', p_AutoUpdateDescription_a2df3cb6994d,
    'IsPrimaryKey', p_IsPrimaryKey_a2df3cb6994d,
    'IsUnique', p_IsUnique_a2df3cb6994d,
    'Category', p_Category_a2df3cb6994d,
    'ValueListType', p_ValueListType_a2df3cb6994d,
    'ExtendedType', p_ExtendedType_a2df3cb6994d,
    'CodeType', p_CodeType_a2df3cb6994d,
    'DefaultInView', p_DefaultInView_a2df3cb6994d,
    'ViewCellTemplate', p_ViewCellTemplate_a2df3cb6994d,
    'DefaultColumnWidth', p_DefaultColumnWidth_a2df3cb6994d,
    'AllowUpdateAPI', p_AllowUpdateAPI_a2df3cb6994d,
    'AllowUpdateInView', p_AllowUpdateInView_a2df3cb6994d,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_a2df3cb6994d,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_a2df3cb6994d,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_a2df3cb6994d,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_a2df3cb6994d,
    'GeneratedFormSection', p_GeneratedFormSection_a2df3cb6994d,
    'IsNameField', p_IsNameField_a2df3cb6994d,
    'RelatedEntityID', p_RelatedEntityID_a2df3cb6994d,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_a2df3cb6994d,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_a2df3cb6994d,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_a2df3cb6994d,
    'EntityIDFieldName', p_EntityIDFieldName_a2df3cb6994d,
    'ScopeDefault', p_ScopeDefault_a2df3cb6994d,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_a2df3cb6994d,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_a2df3cb6994d,
    'Status', p_Status_a2df3cb6994d,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_a2df3cb6994d,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_a2df3cb6994d,
    'AutoUpdateCategory', p_AutoUpdateCategory_a2df3cb6994d,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_a2df3cb6994d,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d,
    'Encrypt', p_Encrypt_a2df3cb6994d,
    'EncryptionKeyID', p_EncryptionKeyID_a2df3cb6994d,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_a2df3cb6994d,
    'SendEncryptedValue', p_SendEncryptedValue_a2df3cb6994d,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_a2df3cb6994d,
    'IsSoftForeignKey', p_IsSoftForeignKey_a2df3cb6994d,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_a2df3cb6994d,
    'JSONType', p_JSONType_a2df3cb6994d,
    'JSONTypeIsArray', p_JSONTypeIsArray_a2df3cb6994d,
    'JSONTypeDefinition', p_JSONTypeDefinition_a2df3cb6994d,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_a2df3cb6994d,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_a2df3cb6994d,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_a2df3cb6994d,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_a2df3cb6994d,
    'IsComputed', p_IsComputed_a2df3cb6994d
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_a2df3cb6994d,
    'Configuration', p_Configuration_a2df3cb6994d,
    'ID', p_ID_a2df3cb6994d
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_a2df3cb6994d, p_Description := p_Description_a2df3cb6994d, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_a2df3cb6994d, p_IsPrimaryKey := p_IsPrimaryKey_a2df3cb6994d, p_IsUnique := p_IsUnique_a2df3cb6994d, p_Category := p_Category_a2df3cb6994d, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_a2df3cb6994d, p_ExtendedType := p_ExtendedType_a2df3cb6994d, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_a2df3cb6994d, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_a2df3cb6994d, p_ViewCellTemplate := p_ViewCellTemplate_a2df3cb6994d, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_a2df3cb6994d, p_AllowUpdateAPI := p_AllowUpdateAPI_a2df3cb6994d, p_AllowUpdateInView := p_AllowUpdateInView_a2df3cb6994d, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_a2df3cb6994d, p_FullTextSearchEnabled := p_FullTextSearchEnabled_a2df3cb6994d, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_a2df3cb6994d, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_a2df3cb6994d, p_GeneratedFormSection := p_GeneratedFormSection_a2df3cb6994d, p_IsNameField := p_IsNameField_a2df3cb6994d, p_RelatedEntityID := p_RelatedEntityID_a2df3cb6994d, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_a2df3cb6994d, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_a2df3cb6994d, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_a2df3cb6994d, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_a2df3cb6994d, p_EntityIDFieldName := p_EntityIDFieldName_a2df3cb6994d, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_a2df3cb6994d, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_a2df3cb6994d, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_a2df3cb6994d, p_Status := p_Status_a2df3cb6994d, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_a2df3cb6994d, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_a2df3cb6994d, p_AutoUpdateCategory := p_AutoUpdateCategory_a2df3cb6994d, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_a2df3cb6994d, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_a2df3cb6994d, p_Encrypt := p_Encrypt_a2df3cb6994d, p_EncryptionKeyID := p_EncryptionKeyID_a2df3cb6994d, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_a2df3cb6994d, p_SendEncryptedValue := p_SendEncryptedValue_a2df3cb6994d, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_a2df3cb6994d, p_IsSoftForeignKey := p_IsSoftForeignKey_a2df3cb6994d, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_a2df3cb6994d, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_a2df3cb6994d, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_a2df3cb6994d, p_JSONTypeDefinition := p_JSONTypeDefinition_a2df3cb6994d, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_a2df3cb6994d, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_a2df3cb6994d, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_a2df3cb6994d, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_a2df3cb6994d, p_IsComputed := p_IsComputed_a2df3cb6994d, p_EmbeddedRecord := p_EmbeddedRecord_a2df3cb6994d, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_a2df3cb6994d, p_Configuration_Clear := TRUE, p_ID := p_ID_a2df3cb6994d);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_13aa73a3e832 VARCHAR(255);
  p_Description_13aa73a3e832 TEXT;
  p_AutoUpdateDescription_13aa73a3e832 BOOLEAN;
  p_IsPrimaryKey_13aa73a3e832 BOOLEAN;
  p_IsUnique_13aa73a3e832 BOOLEAN;
  p_Category_13aa73a3e832 VARCHAR(255);
  p_ValueListType_13aa73a3e832 VARCHAR(20);
  p_ExtendedType_13aa73a3e832 VARCHAR(50);
  p_CodeType_13aa73a3e832 VARCHAR(50);
  p_DefaultInView_13aa73a3e832 BOOLEAN;
  p_ViewCellTemplate_13aa73a3e832 TEXT;
  p_DefaultColumnWidth_13aa73a3e832 INTEGER;
  p_AllowUpdateAPI_13aa73a3e832 BOOLEAN;
  p_AllowUpdateInView_13aa73a3e832 BOOLEAN;
  p_IncludeInUserSearchAPI_13aa73a3e832 BOOLEAN;
  p_FullTextSearchEnabled_13aa73a3e832 BOOLEAN;
  p_UserSearchParamFormatAPI_13aa73a3e832 VARCHAR(500);
  p_IncludeInGeneratedForm_13aa73a3e832 BOOLEAN;
  p_GeneratedFormSection_13aa73a3e832 VARCHAR(10);
  p_IsNameField_13aa73a3e832 BOOLEAN;
  p_RelatedEntityID_13aa73a3e832 UUID;
  p_RelatedEntityFieldName_13aa73a3e832 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832 BOOLEAN;
  p_RelatedEntityNameFieldMap_13aa73a3e832 VARCHAR(255);
  p_RelatedEntityDisplayType_13aa73a3e832 VARCHAR(20);
  p_EntityIDFieldName_13aa73a3e832 VARCHAR(100);
  p_ScopeDefault_13aa73a3e832 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_13aa73a3e832 BOOLEAN;
  p_ValuesToPackWithSchema_13aa73a3e832 VARCHAR(10);
  p_Status_13aa73a3e832 VARCHAR(25);
  p_AutoUpdateIsNameField_13aa73a3e832 BOOLEAN;
  p_AutoUpdateDefaultInView_13aa73a3e832 BOOLEAN;
  p_AutoUpdateCategory_13aa73a3e832 BOOLEAN;
  p_AutoUpdateDisplayName_13aa73a3e832 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832 BOOLEAN;
  p_Encrypt_13aa73a3e832 BOOLEAN;
  p_EncryptionKeyID_13aa73a3e832 UUID;
  p_AllowDecryptInAPI_13aa73a3e832 BOOLEAN;
  p_SendEncryptedValue_13aa73a3e832 BOOLEAN;
  p_IsSoftPrimaryKey_13aa73a3e832 BOOLEAN;
  p_IsSoftForeignKey_13aa73a3e832 BOOLEAN;
  p_RelatedEntityJoinFields_13aa73a3e832 TEXT;
  p_JSONType_13aa73a3e832 VARCHAR(255);
  p_JSONTypeIsArray_13aa73a3e832 BOOLEAN;
  p_JSONTypeDefinition_13aa73a3e832 TEXT;
  p_UserSearchPredicateAPI_13aa73a3e832 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_13aa73a3e832 BOOLEAN;
  p_AutoUpdateFullTextSearch_13aa73a3e832 BOOLEAN;
  p_AutoUpdateExtendedType_13aa73a3e832 BOOLEAN;
  p_IsComputed_13aa73a3e832 BOOLEAN;
  p_EmbeddedRecord_13aa73a3e832 TEXT;
  p_Configuration_13aa73a3e832 TEXT;
  p_ID_13aa73a3e832 UUID;
BEGIN
  p_DisplayName_13aa73a3e832 := 'Days To End';
  p_AutoUpdateDescription_13aa73a3e832 := TRUE;
  p_IsPrimaryKey_13aa73a3e832 := FALSE;
  p_IsUnique_13aa73a3e832 := FALSE;
  p_ValueListType_13aa73a3e832 := 'None';
  p_DefaultInView_13aa73a3e832 := TRUE;
  p_DefaultColumnWidth_13aa73a3e832 := 50;
  p_AllowUpdateAPI_13aa73a3e832 := FALSE;
  p_AllowUpdateInView_13aa73a3e832 := TRUE;
  p_IncludeInUserSearchAPI_13aa73a3e832 := FALSE;
  p_FullTextSearchEnabled_13aa73a3e832 := FALSE;
  p_IncludeInGeneratedForm_13aa73a3e832 := FALSE;
  p_GeneratedFormSection_13aa73a3e832 := 'Details';
  p_IsNameField_13aa73a3e832 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832 := TRUE;
  p_RelatedEntityDisplayType_13aa73a3e832 := 'Search';
  p_AutoUpdateRelatedEntityInfo_13aa73a3e832 := TRUE;
  p_ValuesToPackWithSchema_13aa73a3e832 := 'Auto';
  p_Status_13aa73a3e832 := 'Active';
  p_AutoUpdateIsNameField_13aa73a3e832 := TRUE;
  p_AutoUpdateDefaultInView_13aa73a3e832 := TRUE;
  p_AutoUpdateCategory_13aa73a3e832 := TRUE;
  p_AutoUpdateDisplayName_13aa73a3e832 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832 := TRUE;
  p_Encrypt_13aa73a3e832 := FALSE;
  p_AllowDecryptInAPI_13aa73a3e832 := FALSE;
  p_SendEncryptedValue_13aa73a3e832 := FALSE;
  p_IsSoftPrimaryKey_13aa73a3e832 := FALSE;
  p_IsSoftForeignKey_13aa73a3e832 := FALSE;
  p_JSONTypeIsArray_13aa73a3e832 := FALSE;
  p_UserSearchPredicateAPI_13aa73a3e832 := 'Contains';
  p_AutoUpdateUserSearchPredicate_13aa73a3e832 := TRUE;
  p_AutoUpdateFullTextSearch_13aa73a3e832 := TRUE;
  p_AutoUpdateExtendedType_13aa73a3e832 := TRUE;
  p_IsComputed_13aa73a3e832 := FALSE;
  SELECT "ID" INTO p_ID_13aa73a3e832 FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'DaysToEnd';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_13aa73a3e832,
    'Description', p_Description_13aa73a3e832,
    'AutoUpdateDescription', p_AutoUpdateDescription_13aa73a3e832,
    'IsPrimaryKey', p_IsPrimaryKey_13aa73a3e832,
    'IsUnique', p_IsUnique_13aa73a3e832,
    'Category', p_Category_13aa73a3e832,
    'ValueListType', p_ValueListType_13aa73a3e832,
    'ExtendedType', p_ExtendedType_13aa73a3e832,
    'CodeType', p_CodeType_13aa73a3e832,
    'DefaultInView', p_DefaultInView_13aa73a3e832,
    'ViewCellTemplate', p_ViewCellTemplate_13aa73a3e832,
    'DefaultColumnWidth', p_DefaultColumnWidth_13aa73a3e832,
    'AllowUpdateAPI', p_AllowUpdateAPI_13aa73a3e832,
    'AllowUpdateInView', p_AllowUpdateInView_13aa73a3e832,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_13aa73a3e832,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_13aa73a3e832,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_13aa73a3e832,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_13aa73a3e832,
    'GeneratedFormSection', p_GeneratedFormSection_13aa73a3e832,
    'IsNameField', p_IsNameField_13aa73a3e832,
    'RelatedEntityID', p_RelatedEntityID_13aa73a3e832,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_13aa73a3e832,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_13aa73a3e832,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_13aa73a3e832,
    'EntityIDFieldName', p_EntityIDFieldName_13aa73a3e832,
    'ScopeDefault', p_ScopeDefault_13aa73a3e832,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_13aa73a3e832,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_13aa73a3e832,
    'Status', p_Status_13aa73a3e832,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_13aa73a3e832,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_13aa73a3e832,
    'AutoUpdateCategory', p_AutoUpdateCategory_13aa73a3e832,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_13aa73a3e832,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832,
    'Encrypt', p_Encrypt_13aa73a3e832,
    'EncryptionKeyID', p_EncryptionKeyID_13aa73a3e832,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_13aa73a3e832,
    'SendEncryptedValue', p_SendEncryptedValue_13aa73a3e832,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_13aa73a3e832,
    'IsSoftForeignKey', p_IsSoftForeignKey_13aa73a3e832,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_13aa73a3e832,
    'JSONType', p_JSONType_13aa73a3e832,
    'JSONTypeIsArray', p_JSONTypeIsArray_13aa73a3e832,
    'JSONTypeDefinition', p_JSONTypeDefinition_13aa73a3e832,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_13aa73a3e832,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_13aa73a3e832,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_13aa73a3e832,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_13aa73a3e832,
    'IsComputed', p_IsComputed_13aa73a3e832
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_13aa73a3e832,
    'Configuration', p_Configuration_13aa73a3e832,
    'ID', p_ID_13aa73a3e832
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_13aa73a3e832, p_Description := p_Description_13aa73a3e832, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_13aa73a3e832, p_IsPrimaryKey := p_IsPrimaryKey_13aa73a3e832, p_IsUnique := p_IsUnique_13aa73a3e832, p_Category := p_Category_13aa73a3e832, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_13aa73a3e832, p_ExtendedType := p_ExtendedType_13aa73a3e832, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_13aa73a3e832, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_13aa73a3e832, p_ViewCellTemplate := p_ViewCellTemplate_13aa73a3e832, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_13aa73a3e832, p_AllowUpdateAPI := p_AllowUpdateAPI_13aa73a3e832, p_AllowUpdateInView := p_AllowUpdateInView_13aa73a3e832, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_13aa73a3e832, p_FullTextSearchEnabled := p_FullTextSearchEnabled_13aa73a3e832, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_13aa73a3e832, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_13aa73a3e832, p_GeneratedFormSection := p_GeneratedFormSection_13aa73a3e832, p_IsNameField := p_IsNameField_13aa73a3e832, p_RelatedEntityID := p_RelatedEntityID_13aa73a3e832, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_13aa73a3e832, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_13aa73a3e832, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_13aa73a3e832, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_13aa73a3e832, p_EntityIDFieldName := p_EntityIDFieldName_13aa73a3e832, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_13aa73a3e832, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_13aa73a3e832, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_13aa73a3e832, p_Status := p_Status_13aa73a3e832, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_13aa73a3e832, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_13aa73a3e832, p_AutoUpdateCategory := p_AutoUpdateCategory_13aa73a3e832, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_13aa73a3e832, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_13aa73a3e832, p_Encrypt := p_Encrypt_13aa73a3e832, p_EncryptionKeyID := p_EncryptionKeyID_13aa73a3e832, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_13aa73a3e832, p_SendEncryptedValue := p_SendEncryptedValue_13aa73a3e832, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_13aa73a3e832, p_IsSoftForeignKey := p_IsSoftForeignKey_13aa73a3e832, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_13aa73a3e832, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_13aa73a3e832, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_13aa73a3e832, p_JSONTypeDefinition := p_JSONTypeDefinition_13aa73a3e832, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_13aa73a3e832, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_13aa73a3e832, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_13aa73a3e832, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_13aa73a3e832, p_IsComputed := p_IsComputed_13aa73a3e832, p_EmbeddedRecord := p_EmbeddedRecord_13aa73a3e832, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_13aa73a3e832, p_Configuration_Clear := TRUE, p_ID := p_ID_13aa73a3e832);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_eff4170f0fd1 VARCHAR(255);
  p_Description_eff4170f0fd1 TEXT;
  p_AutoUpdateDescription_eff4170f0fd1 BOOLEAN;
  p_IsPrimaryKey_eff4170f0fd1 BOOLEAN;
  p_IsUnique_eff4170f0fd1 BOOLEAN;
  p_Category_eff4170f0fd1 VARCHAR(255);
  p_ValueListType_eff4170f0fd1 VARCHAR(20);
  p_ExtendedType_eff4170f0fd1 VARCHAR(50);
  p_CodeType_eff4170f0fd1 VARCHAR(50);
  p_DefaultInView_eff4170f0fd1 BOOLEAN;
  p_ViewCellTemplate_eff4170f0fd1 TEXT;
  p_DefaultColumnWidth_eff4170f0fd1 INTEGER;
  p_AllowUpdateAPI_eff4170f0fd1 BOOLEAN;
  p_AllowUpdateInView_eff4170f0fd1 BOOLEAN;
  p_IncludeInUserSearchAPI_eff4170f0fd1 BOOLEAN;
  p_FullTextSearchEnabled_eff4170f0fd1 BOOLEAN;
  p_UserSearchParamFormatAPI_eff4170f0fd1 VARCHAR(500);
  p_IncludeInGeneratedForm_eff4170f0fd1 BOOLEAN;
  p_GeneratedFormSection_eff4170f0fd1 VARCHAR(10);
  p_IsNameField_eff4170f0fd1 BOOLEAN;
  p_RelatedEntityID_eff4170f0fd1 UUID;
  p_RelatedEntityFieldName_eff4170f0fd1 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_eff4170f0fd1 BOOLEAN;
  p_RelatedEntityNameFieldMap_eff4170f0fd1 VARCHAR(255);
  p_RelatedEntityDisplayType_eff4170f0fd1 VARCHAR(20);
  p_EntityIDFieldName_eff4170f0fd1 VARCHAR(100);
  p_ScopeDefault_eff4170f0fd1 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_eff4170f0fd1 BOOLEAN;
  p_ValuesToPackWithSchema_eff4170f0fd1 VARCHAR(10);
  p_Status_eff4170f0fd1 VARCHAR(25);
  p_AutoUpdateIsNameField_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateDefaultInView_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateCategory_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateDisplayName_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_eff4170f0fd1 BOOLEAN;
  p_Encrypt_eff4170f0fd1 BOOLEAN;
  p_EncryptionKeyID_eff4170f0fd1 UUID;
  p_AllowDecryptInAPI_eff4170f0fd1 BOOLEAN;
  p_SendEncryptedValue_eff4170f0fd1 BOOLEAN;
  p_IsSoftPrimaryKey_eff4170f0fd1 BOOLEAN;
  p_IsSoftForeignKey_eff4170f0fd1 BOOLEAN;
  p_RelatedEntityJoinFields_eff4170f0fd1 TEXT;
  p_JSONType_eff4170f0fd1 VARCHAR(255);
  p_JSONTypeIsArray_eff4170f0fd1 BOOLEAN;
  p_JSONTypeDefinition_eff4170f0fd1 TEXT;
  p_UserSearchPredicateAPI_eff4170f0fd1 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateFullTextSearch_eff4170f0fd1 BOOLEAN;
  p_AutoUpdateExtendedType_eff4170f0fd1 BOOLEAN;
  p_IsComputed_eff4170f0fd1 BOOLEAN;
  p_EmbeddedRecord_eff4170f0fd1 TEXT;
  p_Configuration_eff4170f0fd1 TEXT;
  p_ID_eff4170f0fd1 UUID;
BEGIN
  p_DisplayName_eff4170f0fd1 := 'Renewal Notice Deadline';
  p_AutoUpdateDescription_eff4170f0fd1 := TRUE;
  p_IsPrimaryKey_eff4170f0fd1 := FALSE;
  p_IsUnique_eff4170f0fd1 := FALSE;
  p_ValueListType_eff4170f0fd1 := 'None';
  p_DefaultInView_eff4170f0fd1 := FALSE;
  p_DefaultColumnWidth_eff4170f0fd1 := 150;
  p_AllowUpdateAPI_eff4170f0fd1 := FALSE;
  p_AllowUpdateInView_eff4170f0fd1 := TRUE;
  p_IncludeInUserSearchAPI_eff4170f0fd1 := FALSE;
  p_FullTextSearchEnabled_eff4170f0fd1 := FALSE;
  p_IncludeInGeneratedForm_eff4170f0fd1 := FALSE;
  p_GeneratedFormSection_eff4170f0fd1 := 'Details';
  p_IsNameField_eff4170f0fd1 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_eff4170f0fd1 := TRUE;
  p_RelatedEntityDisplayType_eff4170f0fd1 := 'Search';
  p_AutoUpdateRelatedEntityInfo_eff4170f0fd1 := TRUE;
  p_ValuesToPackWithSchema_eff4170f0fd1 := 'Auto';
  p_Status_eff4170f0fd1 := 'Active';
  p_AutoUpdateIsNameField_eff4170f0fd1 := TRUE;
  p_AutoUpdateDefaultInView_eff4170f0fd1 := TRUE;
  p_AutoUpdateCategory_eff4170f0fd1 := TRUE;
  p_AutoUpdateDisplayName_eff4170f0fd1 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_eff4170f0fd1 := TRUE;
  p_Encrypt_eff4170f0fd1 := FALSE;
  p_AllowDecryptInAPI_eff4170f0fd1 := FALSE;
  p_SendEncryptedValue_eff4170f0fd1 := FALSE;
  p_IsSoftPrimaryKey_eff4170f0fd1 := FALSE;
  p_IsSoftForeignKey_eff4170f0fd1 := FALSE;
  p_JSONTypeIsArray_eff4170f0fd1 := FALSE;
  p_UserSearchPredicateAPI_eff4170f0fd1 := 'Contains';
  p_AutoUpdateUserSearchPredicate_eff4170f0fd1 := TRUE;
  p_AutoUpdateFullTextSearch_eff4170f0fd1 := TRUE;
  p_AutoUpdateExtendedType_eff4170f0fd1 := TRUE;
  p_IsComputed_eff4170f0fd1 := FALSE;
  SELECT "ID" INTO p_ID_eff4170f0fd1 FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'RenewalNoticeDeadline';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_eff4170f0fd1,
    'Description', p_Description_eff4170f0fd1,
    'AutoUpdateDescription', p_AutoUpdateDescription_eff4170f0fd1,
    'IsPrimaryKey', p_IsPrimaryKey_eff4170f0fd1,
    'IsUnique', p_IsUnique_eff4170f0fd1,
    'Category', p_Category_eff4170f0fd1,
    'ValueListType', p_ValueListType_eff4170f0fd1,
    'ExtendedType', p_ExtendedType_eff4170f0fd1,
    'CodeType', p_CodeType_eff4170f0fd1,
    'DefaultInView', p_DefaultInView_eff4170f0fd1,
    'ViewCellTemplate', p_ViewCellTemplate_eff4170f0fd1,
    'DefaultColumnWidth', p_DefaultColumnWidth_eff4170f0fd1,
    'AllowUpdateAPI', p_AllowUpdateAPI_eff4170f0fd1,
    'AllowUpdateInView', p_AllowUpdateInView_eff4170f0fd1,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_eff4170f0fd1,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_eff4170f0fd1,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_eff4170f0fd1,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_eff4170f0fd1,
    'GeneratedFormSection', p_GeneratedFormSection_eff4170f0fd1,
    'IsNameField', p_IsNameField_eff4170f0fd1,
    'RelatedEntityID', p_RelatedEntityID_eff4170f0fd1,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_eff4170f0fd1,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_eff4170f0fd1,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_eff4170f0fd1,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_eff4170f0fd1,
    'EntityIDFieldName', p_EntityIDFieldName_eff4170f0fd1,
    'ScopeDefault', p_ScopeDefault_eff4170f0fd1,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_eff4170f0fd1,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_eff4170f0fd1,
    'Status', p_Status_eff4170f0fd1,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_eff4170f0fd1,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_eff4170f0fd1,
    'AutoUpdateCategory', p_AutoUpdateCategory_eff4170f0fd1,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_eff4170f0fd1,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_eff4170f0fd1,
    'Encrypt', p_Encrypt_eff4170f0fd1,
    'EncryptionKeyID', p_EncryptionKeyID_eff4170f0fd1,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_eff4170f0fd1,
    'SendEncryptedValue', p_SendEncryptedValue_eff4170f0fd1,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_eff4170f0fd1,
    'IsSoftForeignKey', p_IsSoftForeignKey_eff4170f0fd1,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_eff4170f0fd1,
    'JSONType', p_JSONType_eff4170f0fd1,
    'JSONTypeIsArray', p_JSONTypeIsArray_eff4170f0fd1,
    'JSONTypeDefinition', p_JSONTypeDefinition_eff4170f0fd1,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_eff4170f0fd1,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_eff4170f0fd1,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_eff4170f0fd1,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_eff4170f0fd1,
    'IsComputed', p_IsComputed_eff4170f0fd1
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_eff4170f0fd1,
    'Configuration', p_Configuration_eff4170f0fd1,
    'ID', p_ID_eff4170f0fd1
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_eff4170f0fd1, p_Description := p_Description_eff4170f0fd1, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_eff4170f0fd1, p_IsPrimaryKey := p_IsPrimaryKey_eff4170f0fd1, p_IsUnique := p_IsUnique_eff4170f0fd1, p_Category := p_Category_eff4170f0fd1, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_eff4170f0fd1, p_ExtendedType := p_ExtendedType_eff4170f0fd1, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_eff4170f0fd1, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_eff4170f0fd1, p_ViewCellTemplate := p_ViewCellTemplate_eff4170f0fd1, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_eff4170f0fd1, p_AllowUpdateAPI := p_AllowUpdateAPI_eff4170f0fd1, p_AllowUpdateInView := p_AllowUpdateInView_eff4170f0fd1, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_eff4170f0fd1, p_FullTextSearchEnabled := p_FullTextSearchEnabled_eff4170f0fd1, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_eff4170f0fd1, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_eff4170f0fd1, p_GeneratedFormSection := p_GeneratedFormSection_eff4170f0fd1, p_IsNameField := p_IsNameField_eff4170f0fd1, p_RelatedEntityID := p_RelatedEntityID_eff4170f0fd1, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_eff4170f0fd1, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_eff4170f0fd1, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_eff4170f0fd1, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_eff4170f0fd1, p_EntityIDFieldName := p_EntityIDFieldName_eff4170f0fd1, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_eff4170f0fd1, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_eff4170f0fd1, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_eff4170f0fd1, p_Status := p_Status_eff4170f0fd1, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_eff4170f0fd1, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_eff4170f0fd1, p_AutoUpdateCategory := p_AutoUpdateCategory_eff4170f0fd1, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_eff4170f0fd1, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_eff4170f0fd1, p_Encrypt := p_Encrypt_eff4170f0fd1, p_EncryptionKeyID := p_EncryptionKeyID_eff4170f0fd1, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_eff4170f0fd1, p_SendEncryptedValue := p_SendEncryptedValue_eff4170f0fd1, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_eff4170f0fd1, p_IsSoftForeignKey := p_IsSoftForeignKey_eff4170f0fd1, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_eff4170f0fd1, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_eff4170f0fd1, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_eff4170f0fd1, p_JSONTypeDefinition := p_JSONTypeDefinition_eff4170f0fd1, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_eff4170f0fd1, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_eff4170f0fd1, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_eff4170f0fd1, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_eff4170f0fd1, p_IsComputed := p_IsComputed_eff4170f0fd1, p_EmbeddedRecord := p_EmbeddedRecord_eff4170f0fd1, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_eff4170f0fd1, p_Configuration_Clear := TRUE, p_ID := p_ID_eff4170f0fd1);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_3a0cfd364cb0 VARCHAR(255);
  p_Description_3a0cfd364cb0 TEXT;
  p_AutoUpdateDescription_3a0cfd364cb0 BOOLEAN;
  p_IsPrimaryKey_3a0cfd364cb0 BOOLEAN;
  p_IsUnique_3a0cfd364cb0 BOOLEAN;
  p_Category_3a0cfd364cb0 VARCHAR(255);
  p_ValueListType_3a0cfd364cb0 VARCHAR(20);
  p_ExtendedType_3a0cfd364cb0 VARCHAR(50);
  p_CodeType_3a0cfd364cb0 VARCHAR(50);
  p_DefaultInView_3a0cfd364cb0 BOOLEAN;
  p_ViewCellTemplate_3a0cfd364cb0 TEXT;
  p_DefaultColumnWidth_3a0cfd364cb0 INTEGER;
  p_AllowUpdateAPI_3a0cfd364cb0 BOOLEAN;
  p_AllowUpdateInView_3a0cfd364cb0 BOOLEAN;
  p_IncludeInUserSearchAPI_3a0cfd364cb0 BOOLEAN;
  p_FullTextSearchEnabled_3a0cfd364cb0 BOOLEAN;
  p_UserSearchParamFormatAPI_3a0cfd364cb0 VARCHAR(500);
  p_IncludeInGeneratedForm_3a0cfd364cb0 BOOLEAN;
  p_GeneratedFormSection_3a0cfd364cb0 VARCHAR(10);
  p_IsNameField_3a0cfd364cb0 BOOLEAN;
  p_RelatedEntityID_3a0cfd364cb0 UUID;
  p_RelatedEntityFieldName_3a0cfd364cb0 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_3a0cfd364cb0 BOOLEAN;
  p_RelatedEntityNameFieldMap_3a0cfd364cb0 VARCHAR(255);
  p_RelatedEntityDisplayType_3a0cfd364cb0 VARCHAR(20);
  p_EntityIDFieldName_3a0cfd364cb0 VARCHAR(100);
  p_ScopeDefault_3a0cfd364cb0 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_3a0cfd364cb0 BOOLEAN;
  p_ValuesToPackWithSchema_3a0cfd364cb0 VARCHAR(10);
  p_Status_3a0cfd364cb0 VARCHAR(25);
  p_AutoUpdateIsNameField_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateDefaultInView_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateCategory_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateDisplayName_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_3a0cfd364cb0 BOOLEAN;
  p_Encrypt_3a0cfd364cb0 BOOLEAN;
  p_EncryptionKeyID_3a0cfd364cb0 UUID;
  p_AllowDecryptInAPI_3a0cfd364cb0 BOOLEAN;
  p_SendEncryptedValue_3a0cfd364cb0 BOOLEAN;
  p_IsSoftPrimaryKey_3a0cfd364cb0 BOOLEAN;
  p_IsSoftForeignKey_3a0cfd364cb0 BOOLEAN;
  p_RelatedEntityJoinFields_3a0cfd364cb0 TEXT;
  p_JSONType_3a0cfd364cb0 VARCHAR(255);
  p_JSONTypeIsArray_3a0cfd364cb0 BOOLEAN;
  p_JSONTypeDefinition_3a0cfd364cb0 TEXT;
  p_UserSearchPredicateAPI_3a0cfd364cb0 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateFullTextSearch_3a0cfd364cb0 BOOLEAN;
  p_AutoUpdateExtendedType_3a0cfd364cb0 BOOLEAN;
  p_IsComputed_3a0cfd364cb0 BOOLEAN;
  p_EmbeddedRecord_3a0cfd364cb0 TEXT;
  p_Configuration_3a0cfd364cb0 TEXT;
  p_ID_3a0cfd364cb0 UUID;
BEGIN
  p_DisplayName_3a0cfd364cb0 := 'Is In Cancellation Window';
  p_AutoUpdateDescription_3a0cfd364cb0 := TRUE;
  p_IsPrimaryKey_3a0cfd364cb0 := FALSE;
  p_IsUnique_3a0cfd364cb0 := FALSE;
  p_ValueListType_3a0cfd364cb0 := 'None';
  p_DefaultInView_3a0cfd364cb0 := FALSE;
  p_DefaultColumnWidth_3a0cfd364cb0 := 150;
  p_AllowUpdateAPI_3a0cfd364cb0 := FALSE;
  p_AllowUpdateInView_3a0cfd364cb0 := TRUE;
  p_IncludeInUserSearchAPI_3a0cfd364cb0 := FALSE;
  p_FullTextSearchEnabled_3a0cfd364cb0 := FALSE;
  p_IncludeInGeneratedForm_3a0cfd364cb0 := FALSE;
  p_GeneratedFormSection_3a0cfd364cb0 := 'Details';
  p_IsNameField_3a0cfd364cb0 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_3a0cfd364cb0 := TRUE;
  p_RelatedEntityDisplayType_3a0cfd364cb0 := 'Search';
  p_AutoUpdateRelatedEntityInfo_3a0cfd364cb0 := TRUE;
  p_ValuesToPackWithSchema_3a0cfd364cb0 := 'Auto';
  p_Status_3a0cfd364cb0 := 'Active';
  p_AutoUpdateIsNameField_3a0cfd364cb0 := TRUE;
  p_AutoUpdateDefaultInView_3a0cfd364cb0 := TRUE;
  p_AutoUpdateCategory_3a0cfd364cb0 := TRUE;
  p_AutoUpdateDisplayName_3a0cfd364cb0 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_3a0cfd364cb0 := TRUE;
  p_Encrypt_3a0cfd364cb0 := FALSE;
  p_AllowDecryptInAPI_3a0cfd364cb0 := FALSE;
  p_SendEncryptedValue_3a0cfd364cb0 := FALSE;
  p_IsSoftPrimaryKey_3a0cfd364cb0 := FALSE;
  p_IsSoftForeignKey_3a0cfd364cb0 := FALSE;
  p_JSONTypeIsArray_3a0cfd364cb0 := FALSE;
  p_UserSearchPredicateAPI_3a0cfd364cb0 := 'Contains';
  p_AutoUpdateUserSearchPredicate_3a0cfd364cb0 := TRUE;
  p_AutoUpdateFullTextSearch_3a0cfd364cb0 := TRUE;
  p_AutoUpdateExtendedType_3a0cfd364cb0 := TRUE;
  p_IsComputed_3a0cfd364cb0 := FALSE;
  SELECT "ID" INTO p_ID_3a0cfd364cb0 FROM __mj."EntityField"
   WHERE "EntityID" = (SELECT "ID" FROM __mj."Entity" WHERE "Name" = 'MJ_BizApps_Contracts: Contracts') AND "Name" = 'IsInCancellationWindow';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_3a0cfd364cb0,
    'Description', p_Description_3a0cfd364cb0,
    'AutoUpdateDescription', p_AutoUpdateDescription_3a0cfd364cb0,
    'IsPrimaryKey', p_IsPrimaryKey_3a0cfd364cb0,
    'IsUnique', p_IsUnique_3a0cfd364cb0,
    'Category', p_Category_3a0cfd364cb0,
    'ValueListType', p_ValueListType_3a0cfd364cb0,
    'ExtendedType', p_ExtendedType_3a0cfd364cb0,
    'CodeType', p_CodeType_3a0cfd364cb0,
    'DefaultInView', p_DefaultInView_3a0cfd364cb0,
    'ViewCellTemplate', p_ViewCellTemplate_3a0cfd364cb0,
    'DefaultColumnWidth', p_DefaultColumnWidth_3a0cfd364cb0,
    'AllowUpdateAPI', p_AllowUpdateAPI_3a0cfd364cb0,
    'AllowUpdateInView', p_AllowUpdateInView_3a0cfd364cb0,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_3a0cfd364cb0,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_3a0cfd364cb0,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_3a0cfd364cb0,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_3a0cfd364cb0,
    'GeneratedFormSection', p_GeneratedFormSection_3a0cfd364cb0,
    'IsNameField', p_IsNameField_3a0cfd364cb0,
    'RelatedEntityID', p_RelatedEntityID_3a0cfd364cb0,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_3a0cfd364cb0,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_3a0cfd364cb0,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_3a0cfd364cb0,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_3a0cfd364cb0,
    'EntityIDFieldName', p_EntityIDFieldName_3a0cfd364cb0,
    'ScopeDefault', p_ScopeDefault_3a0cfd364cb0,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_3a0cfd364cb0,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_3a0cfd364cb0,
    'Status', p_Status_3a0cfd364cb0,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_3a0cfd364cb0,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_3a0cfd364cb0,
    'AutoUpdateCategory', p_AutoUpdateCategory_3a0cfd364cb0,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_3a0cfd364cb0,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_3a0cfd364cb0,
    'Encrypt', p_Encrypt_3a0cfd364cb0,
    'EncryptionKeyID', p_EncryptionKeyID_3a0cfd364cb0,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_3a0cfd364cb0,
    'SendEncryptedValue', p_SendEncryptedValue_3a0cfd364cb0,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_3a0cfd364cb0,
    'IsSoftForeignKey', p_IsSoftForeignKey_3a0cfd364cb0,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_3a0cfd364cb0,
    'JSONType', p_JSONType_3a0cfd364cb0,
    'JSONTypeIsArray', p_JSONTypeIsArray_3a0cfd364cb0,
    'JSONTypeDefinition', p_JSONTypeDefinition_3a0cfd364cb0,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_3a0cfd364cb0,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_3a0cfd364cb0,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_3a0cfd364cb0,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_3a0cfd364cb0,
    'IsComputed', p_IsComputed_3a0cfd364cb0
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_3a0cfd364cb0,
    'Configuration', p_Configuration_3a0cfd364cb0,
    'ID', p_ID_3a0cfd364cb0
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_3a0cfd364cb0, p_Description := p_Description_3a0cfd364cb0, p_Description_Clear := TRUE, p_AutoUpdateDescription := p_AutoUpdateDescription_3a0cfd364cb0, p_IsPrimaryKey := p_IsPrimaryKey_3a0cfd364cb0, p_IsUnique := p_IsUnique_3a0cfd364cb0, p_Category := p_Category_3a0cfd364cb0, p_Category_Clear := TRUE, p_ValueListType := p_ValueListType_3a0cfd364cb0, p_ExtendedType := p_ExtendedType_3a0cfd364cb0, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_3a0cfd364cb0, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_3a0cfd364cb0, p_ViewCellTemplate := p_ViewCellTemplate_3a0cfd364cb0, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_3a0cfd364cb0, p_AllowUpdateAPI := p_AllowUpdateAPI_3a0cfd364cb0, p_AllowUpdateInView := p_AllowUpdateInView_3a0cfd364cb0, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_3a0cfd364cb0, p_FullTextSearchEnabled := p_FullTextSearchEnabled_3a0cfd364cb0, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_3a0cfd364cb0, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_3a0cfd364cb0, p_GeneratedFormSection := p_GeneratedFormSection_3a0cfd364cb0, p_IsNameField := p_IsNameField_3a0cfd364cb0, p_RelatedEntityID := p_RelatedEntityID_3a0cfd364cb0, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_3a0cfd364cb0, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_3a0cfd364cb0, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_3a0cfd364cb0, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_3a0cfd364cb0, p_EntityIDFieldName := p_EntityIDFieldName_3a0cfd364cb0, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_3a0cfd364cb0, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_3a0cfd364cb0, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_3a0cfd364cb0, p_Status := p_Status_3a0cfd364cb0, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_3a0cfd364cb0, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_3a0cfd364cb0, p_AutoUpdateCategory := p_AutoUpdateCategory_3a0cfd364cb0, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_3a0cfd364cb0, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_3a0cfd364cb0, p_Encrypt := p_Encrypt_3a0cfd364cb0, p_EncryptionKeyID := p_EncryptionKeyID_3a0cfd364cb0, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_3a0cfd364cb0, p_SendEncryptedValue := p_SendEncryptedValue_3a0cfd364cb0, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_3a0cfd364cb0, p_IsSoftForeignKey := p_IsSoftForeignKey_3a0cfd364cb0, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_3a0cfd364cb0, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_3a0cfd364cb0, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_3a0cfd364cb0, p_JSONTypeDefinition := p_JSONTypeDefinition_3a0cfd364cb0, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_3a0cfd364cb0, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_3a0cfd364cb0, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_3a0cfd364cb0, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_3a0cfd364cb0, p_IsComputed := p_IsComputed_3a0cfd364cb0, p_EmbeddedRecord := p_EmbeddedRecord_3a0cfd364cb0, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_3a0cfd364cb0, p_Configuration_Clear := TRUE, p_ID := p_ID_3a0cfd364cb0);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_21e75a452ef4 VARCHAR(255);
  p_Description_21e75a452ef4 TEXT;
  p_AutoUpdateDescription_21e75a452ef4 BOOLEAN;
  p_IsPrimaryKey_21e75a452ef4 BOOLEAN;
  p_IsUnique_21e75a452ef4 BOOLEAN;
  p_Category_21e75a452ef4 VARCHAR(255);
  p_ValueListType_21e75a452ef4 VARCHAR(20);
  p_ExtendedType_21e75a452ef4 VARCHAR(50);
  p_CodeType_21e75a452ef4 VARCHAR(50);
  p_DefaultInView_21e75a452ef4 BOOLEAN;
  p_ViewCellTemplate_21e75a452ef4 TEXT;
  p_DefaultColumnWidth_21e75a452ef4 INTEGER;
  p_AllowUpdateAPI_21e75a452ef4 BOOLEAN;
  p_AllowUpdateInView_21e75a452ef4 BOOLEAN;
  p_IncludeInUserSearchAPI_21e75a452ef4 BOOLEAN;
  p_FullTextSearchEnabled_21e75a452ef4 BOOLEAN;
  p_UserSearchParamFormatAPI_21e75a452ef4 VARCHAR(500);
  p_IncludeInGeneratedForm_21e75a452ef4 BOOLEAN;
  p_GeneratedFormSection_21e75a452ef4 VARCHAR(10);
  p_IsNameField_21e75a452ef4 BOOLEAN;
  p_RelatedEntityID_21e75a452ef4 UUID;
  p_RelatedEntityFieldName_21e75a452ef4 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_21e75a452ef4 BOOLEAN;
  p_RelatedEntityNameFieldMap_21e75a452ef4 VARCHAR(255);
  p_RelatedEntityDisplayType_21e75a452ef4 VARCHAR(20);
  p_EntityIDFieldName_21e75a452ef4 VARCHAR(100);
  p_ScopeDefault_21e75a452ef4 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_21e75a452ef4 BOOLEAN;
  p_ValuesToPackWithSchema_21e75a452ef4 VARCHAR(10);
  p_Status_21e75a452ef4 VARCHAR(25);
  p_AutoUpdateIsNameField_21e75a452ef4 BOOLEAN;
  p_AutoUpdateDefaultInView_21e75a452ef4 BOOLEAN;
  p_AutoUpdateCategory_21e75a452ef4 BOOLEAN;
  p_AutoUpdateDisplayName_21e75a452ef4 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_21e75a452ef4 BOOLEAN;
  p_Encrypt_21e75a452ef4 BOOLEAN;
  p_EncryptionKeyID_21e75a452ef4 UUID;
  p_AllowDecryptInAPI_21e75a452ef4 BOOLEAN;
  p_SendEncryptedValue_21e75a452ef4 BOOLEAN;
  p_IsSoftPrimaryKey_21e75a452ef4 BOOLEAN;
  p_IsSoftForeignKey_21e75a452ef4 BOOLEAN;
  p_RelatedEntityJoinFields_21e75a452ef4 TEXT;
  p_JSONType_21e75a452ef4 VARCHAR(255);
  p_JSONTypeIsArray_21e75a452ef4 BOOLEAN;
  p_JSONTypeDefinition_21e75a452ef4 TEXT;
  p_UserSearchPredicateAPI_21e75a452ef4 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_21e75a452ef4 BOOLEAN;
  p_AutoUpdateFullTextSearch_21e75a452ef4 BOOLEAN;
  p_AutoUpdateExtendedType_21e75a452ef4 BOOLEAN;
  p_IsComputed_21e75a452ef4 BOOLEAN;
  p_EmbeddedRecord_21e75a452ef4 TEXT;
  p_Configuration_21e75a452ef4 TEXT;
  p_ID_21e75a452ef4 UUID;
BEGIN
  p_DisplayName_21e75a452ef4 := 'Renewal Notice (Days)';
  p_Description_21e75a452ef4 := 'Days of written notice we owe before a renewal price change, as stated in the agreement. NOT the same field as CancellationWindowDays even though many agreements set them equal — conflating them silently is how a notice obligation gets missed.';
  p_AutoUpdateDescription_21e75a452ef4 := TRUE;
  p_IsPrimaryKey_21e75a452ef4 := FALSE;
  p_IsUnique_21e75a452ef4 := FALSE;
  p_Category_21e75a452ef4 := 'Renewal Terms';
  p_ValueListType_21e75a452ef4 := 'None';
  p_DefaultInView_21e75a452ef4 := FALSE;
  p_DefaultColumnWidth_21e75a452ef4 := 50;
  p_AllowUpdateAPI_21e75a452ef4 := TRUE;
  p_AllowUpdateInView_21e75a452ef4 := TRUE;
  p_IncludeInUserSearchAPI_21e75a452ef4 := FALSE;
  p_FullTextSearchEnabled_21e75a452ef4 := FALSE;
  p_IncludeInGeneratedForm_21e75a452ef4 := TRUE;
  p_GeneratedFormSection_21e75a452ef4 := 'Category';
  p_IsNameField_21e75a452ef4 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_21e75a452ef4 := FALSE;
  p_RelatedEntityDisplayType_21e75a452ef4 := 'Search';
  p_AutoUpdateRelatedEntityInfo_21e75a452ef4 := TRUE;
  p_ValuesToPackWithSchema_21e75a452ef4 := 'Auto';
  p_Status_21e75a452ef4 := 'Active';
  p_AutoUpdateIsNameField_21e75a452ef4 := TRUE;
  p_AutoUpdateDefaultInView_21e75a452ef4 := TRUE;
  p_AutoUpdateCategory_21e75a452ef4 := TRUE;
  p_AutoUpdateDisplayName_21e75a452ef4 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_21e75a452ef4 := TRUE;
  p_Encrypt_21e75a452ef4 := FALSE;
  p_AllowDecryptInAPI_21e75a452ef4 := FALSE;
  p_SendEncryptedValue_21e75a452ef4 := FALSE;
  p_IsSoftPrimaryKey_21e75a452ef4 := FALSE;
  p_IsSoftForeignKey_21e75a452ef4 := FALSE;
  p_JSONTypeIsArray_21e75a452ef4 := FALSE;
  p_UserSearchPredicateAPI_21e75a452ef4 := 'Contains';
  p_AutoUpdateUserSearchPredicate_21e75a452ef4 := TRUE;
  p_AutoUpdateFullTextSearch_21e75a452ef4 := TRUE;
  p_AutoUpdateExtendedType_21e75a452ef4 := TRUE;
  p_IsComputed_21e75a452ef4 := FALSE;
  p_ID_21e75a452ef4 := '573064AC-38A8-42A2-95B2-CCBD605004EA';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_21e75a452ef4,
    'Description', p_Description_21e75a452ef4,
    'AutoUpdateDescription', p_AutoUpdateDescription_21e75a452ef4,
    'IsPrimaryKey', p_IsPrimaryKey_21e75a452ef4,
    'IsUnique', p_IsUnique_21e75a452ef4,
    'Category', p_Category_21e75a452ef4,
    'ValueListType', p_ValueListType_21e75a452ef4,
    'ExtendedType', p_ExtendedType_21e75a452ef4,
    'CodeType', p_CodeType_21e75a452ef4,
    'DefaultInView', p_DefaultInView_21e75a452ef4,
    'ViewCellTemplate', p_ViewCellTemplate_21e75a452ef4,
    'DefaultColumnWidth', p_DefaultColumnWidth_21e75a452ef4,
    'AllowUpdateAPI', p_AllowUpdateAPI_21e75a452ef4,
    'AllowUpdateInView', p_AllowUpdateInView_21e75a452ef4,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_21e75a452ef4,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_21e75a452ef4,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_21e75a452ef4,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_21e75a452ef4,
    'GeneratedFormSection', p_GeneratedFormSection_21e75a452ef4,
    'IsNameField', p_IsNameField_21e75a452ef4,
    'RelatedEntityID', p_RelatedEntityID_21e75a452ef4,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_21e75a452ef4,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_21e75a452ef4,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_21e75a452ef4,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_21e75a452ef4,
    'EntityIDFieldName', p_EntityIDFieldName_21e75a452ef4,
    'ScopeDefault', p_ScopeDefault_21e75a452ef4,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_21e75a452ef4,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_21e75a452ef4,
    'Status', p_Status_21e75a452ef4,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_21e75a452ef4,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_21e75a452ef4,
    'AutoUpdateCategory', p_AutoUpdateCategory_21e75a452ef4,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_21e75a452ef4,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_21e75a452ef4,
    'Encrypt', p_Encrypt_21e75a452ef4,
    'EncryptionKeyID', p_EncryptionKeyID_21e75a452ef4,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_21e75a452ef4,
    'SendEncryptedValue', p_SendEncryptedValue_21e75a452ef4,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_21e75a452ef4,
    'IsSoftForeignKey', p_IsSoftForeignKey_21e75a452ef4,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_21e75a452ef4,
    'JSONType', p_JSONType_21e75a452ef4,
    'JSONTypeIsArray', p_JSONTypeIsArray_21e75a452ef4,
    'JSONTypeDefinition', p_JSONTypeDefinition_21e75a452ef4,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_21e75a452ef4,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_21e75a452ef4,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_21e75a452ef4,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_21e75a452ef4,
    'IsComputed', p_IsComputed_21e75a452ef4
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_21e75a452ef4,
    'Configuration', p_Configuration_21e75a452ef4,
    'ID', p_ID_21e75a452ef4
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_21e75a452ef4, p_Description := p_Description_21e75a452ef4, p_AutoUpdateDescription := p_AutoUpdateDescription_21e75a452ef4, p_IsPrimaryKey := p_IsPrimaryKey_21e75a452ef4, p_IsUnique := p_IsUnique_21e75a452ef4, p_Category := p_Category_21e75a452ef4, p_ValueListType := p_ValueListType_21e75a452ef4, p_ExtendedType := p_ExtendedType_21e75a452ef4, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_21e75a452ef4, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_21e75a452ef4, p_ViewCellTemplate := p_ViewCellTemplate_21e75a452ef4, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_21e75a452ef4, p_AllowUpdateAPI := p_AllowUpdateAPI_21e75a452ef4, p_AllowUpdateInView := p_AllowUpdateInView_21e75a452ef4, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_21e75a452ef4, p_FullTextSearchEnabled := p_FullTextSearchEnabled_21e75a452ef4, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_21e75a452ef4, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_21e75a452ef4, p_GeneratedFormSection := p_GeneratedFormSection_21e75a452ef4, p_IsNameField := p_IsNameField_21e75a452ef4, p_RelatedEntityID := p_RelatedEntityID_21e75a452ef4, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_21e75a452ef4, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_21e75a452ef4, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_21e75a452ef4, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_21e75a452ef4, p_EntityIDFieldName := p_EntityIDFieldName_21e75a452ef4, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_21e75a452ef4, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_21e75a452ef4, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_21e75a452ef4, p_Status := p_Status_21e75a452ef4, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_21e75a452ef4, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_21e75a452ef4, p_AutoUpdateCategory := p_AutoUpdateCategory_21e75a452ef4, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_21e75a452ef4, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_21e75a452ef4, p_Encrypt := p_Encrypt_21e75a452ef4, p_EncryptionKeyID := p_EncryptionKeyID_21e75a452ef4, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_21e75a452ef4, p_SendEncryptedValue := p_SendEncryptedValue_21e75a452ef4, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_21e75a452ef4, p_IsSoftForeignKey := p_IsSoftForeignKey_21e75a452ef4, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_21e75a452ef4, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_21e75a452ef4, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_21e75a452ef4, p_JSONTypeDefinition := p_JSONTypeDefinition_21e75a452ef4, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_21e75a452ef4, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_21e75a452ef4, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_21e75a452ef4, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_21e75a452ef4, p_IsComputed := p_IsComputed_21e75a452ef4, p_EmbeddedRecord := p_EmbeddedRecord_21e75a452ef4, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_21e75a452ef4, p_Configuration_Clear := TRUE, p_ID := p_ID_21e75a452ef4);
  END IF;
END $mj$;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_a2a7be5afd90 VARCHAR(255);
  p_Description_a2a7be5afd90 TEXT;
  p_AutoUpdateDescription_a2a7be5afd90 BOOLEAN;
  p_IsPrimaryKey_a2a7be5afd90 BOOLEAN;
  p_IsUnique_a2a7be5afd90 BOOLEAN;
  p_Category_a2a7be5afd90 VARCHAR(255);
  p_ValueListType_a2a7be5afd90 VARCHAR(20);
  p_ExtendedType_a2a7be5afd90 VARCHAR(50);
  p_CodeType_a2a7be5afd90 VARCHAR(50);
  p_DefaultInView_a2a7be5afd90 BOOLEAN;
  p_ViewCellTemplate_a2a7be5afd90 TEXT;
  p_DefaultColumnWidth_a2a7be5afd90 INTEGER;
  p_AllowUpdateAPI_a2a7be5afd90 BOOLEAN;
  p_AllowUpdateInView_a2a7be5afd90 BOOLEAN;
  p_IncludeInUserSearchAPI_a2a7be5afd90 BOOLEAN;
  p_FullTextSearchEnabled_a2a7be5afd90 BOOLEAN;
  p_UserSearchParamFormatAPI_a2a7be5afd90 VARCHAR(500);
  p_IncludeInGeneratedForm_a2a7be5afd90 BOOLEAN;
  p_GeneratedFormSection_a2a7be5afd90 VARCHAR(10);
  p_IsNameField_a2a7be5afd90 BOOLEAN;
  p_RelatedEntityID_a2a7be5afd90 UUID;
  p_RelatedEntityFieldName_a2a7be5afd90 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_a2a7be5afd90 BOOLEAN;
  p_RelatedEntityNameFieldMap_a2a7be5afd90 VARCHAR(255);
  p_RelatedEntityDisplayType_a2a7be5afd90 VARCHAR(20);
  p_EntityIDFieldName_a2a7be5afd90 VARCHAR(100);
  p_ScopeDefault_a2a7be5afd90 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_a2a7be5afd90 BOOLEAN;
  p_ValuesToPackWithSchema_a2a7be5afd90 VARCHAR(10);
  p_Status_a2a7be5afd90 VARCHAR(25);
  p_AutoUpdateIsNameField_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateDefaultInView_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateCategory_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateDisplayName_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_a2a7be5afd90 BOOLEAN;
  p_Encrypt_a2a7be5afd90 BOOLEAN;
  p_EncryptionKeyID_a2a7be5afd90 UUID;
  p_AllowDecryptInAPI_a2a7be5afd90 BOOLEAN;
  p_SendEncryptedValue_a2a7be5afd90 BOOLEAN;
  p_IsSoftPrimaryKey_a2a7be5afd90 BOOLEAN;
  p_IsSoftForeignKey_a2a7be5afd90 BOOLEAN;
  p_RelatedEntityJoinFields_a2a7be5afd90 TEXT;
  p_JSONType_a2a7be5afd90 VARCHAR(255);
  p_JSONTypeIsArray_a2a7be5afd90 BOOLEAN;
  p_JSONTypeDefinition_a2a7be5afd90 TEXT;
  p_UserSearchPredicateAPI_a2a7be5afd90 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateFullTextSearch_a2a7be5afd90 BOOLEAN;
  p_AutoUpdateExtendedType_a2a7be5afd90 BOOLEAN;
  p_IsComputed_a2a7be5afd90 BOOLEAN;
  p_EmbeddedRecord_a2a7be5afd90 TEXT;
  p_Configuration_a2a7be5afd90 TEXT;
  p_ID_a2a7be5afd90 UUID;
BEGIN
  p_DisplayName_a2a7be5afd90 := 'Company';
  p_Description_a2a7be5afd90 := 'The SELLING company (${mjSchema}.Company) — which of OUR entities holds this agreement. Not the customer. Stored rather than derived because it is not reliably recoverable from the deal.';
  p_AutoUpdateDescription_a2a7be5afd90 := TRUE;
  p_IsPrimaryKey_a2a7be5afd90 := FALSE;
  p_IsUnique_a2a7be5afd90 := FALSE;
  p_Category_a2a7be5afd90 := 'Stakeholders';
  p_ValueListType_a2a7be5afd90 := 'None';
  p_DefaultInView_a2a7be5afd90 := FALSE;
  p_DefaultColumnWidth_a2a7be5afd90 := 150;
  p_AllowUpdateAPI_a2a7be5afd90 := TRUE;
  p_AllowUpdateInView_a2a7be5afd90 := TRUE;
  p_IncludeInUserSearchAPI_a2a7be5afd90 := FALSE;
  p_FullTextSearchEnabled_a2a7be5afd90 := FALSE;
  p_IncludeInGeneratedForm_a2a7be5afd90 := TRUE;
  p_GeneratedFormSection_a2a7be5afd90 := 'Category';
  p_IsNameField_a2a7be5afd90 := FALSE;
  p_RelatedEntityID_a2a7be5afd90 := 'D4238F34-2837-EF11-86D4-6045BDEE16E6';
  p_RelatedEntityFieldName_a2a7be5afd90 := 'ID';
  p_IncludeRelatedEntityNameFieldInBaseView_a2a7be5afd90 := TRUE;
  p_RelatedEntityNameFieldMap_a2a7be5afd90 := 'Company';
  p_RelatedEntityDisplayType_a2a7be5afd90 := 'Search';
  p_AutoUpdateRelatedEntityInfo_a2a7be5afd90 := TRUE;
  p_ValuesToPackWithSchema_a2a7be5afd90 := 'Auto';
  p_Status_a2a7be5afd90 := 'Active';
  p_AutoUpdateIsNameField_a2a7be5afd90 := TRUE;
  p_AutoUpdateDefaultInView_a2a7be5afd90 := TRUE;
  p_AutoUpdateCategory_a2a7be5afd90 := TRUE;
  p_AutoUpdateDisplayName_a2a7be5afd90 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_a2a7be5afd90 := TRUE;
  p_Encrypt_a2a7be5afd90 := FALSE;
  p_AllowDecryptInAPI_a2a7be5afd90 := FALSE;
  p_SendEncryptedValue_a2a7be5afd90 := FALSE;
  p_IsSoftPrimaryKey_a2a7be5afd90 := FALSE;
  p_IsSoftForeignKey_a2a7be5afd90 := FALSE;
  p_JSONTypeIsArray_a2a7be5afd90 := FALSE;
  p_UserSearchPredicateAPI_a2a7be5afd90 := 'Contains';
  p_AutoUpdateUserSearchPredicate_a2a7be5afd90 := TRUE;
  p_AutoUpdateFullTextSearch_a2a7be5afd90 := TRUE;
  p_AutoUpdateExtendedType_a2a7be5afd90 := TRUE;
  p_IsComputed_a2a7be5afd90 := FALSE;
  p_ID_a2a7be5afd90 := 'BAD7AA2F-EE2B-430A-B182-B7E4B7E09F8A';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_a2a7be5afd90,
    'Description', p_Description_a2a7be5afd90,
    'AutoUpdateDescription', p_AutoUpdateDescription_a2a7be5afd90,
    'IsPrimaryKey', p_IsPrimaryKey_a2a7be5afd90,
    'IsUnique', p_IsUnique_a2a7be5afd90,
    'Category', p_Category_a2a7be5afd90,
    'ValueListType', p_ValueListType_a2a7be5afd90,
    'ExtendedType', p_ExtendedType_a2a7be5afd90,
    'CodeType', p_CodeType_a2a7be5afd90,
    'DefaultInView', p_DefaultInView_a2a7be5afd90,
    'ViewCellTemplate', p_ViewCellTemplate_a2a7be5afd90,
    'DefaultColumnWidth', p_DefaultColumnWidth_a2a7be5afd90,
    'AllowUpdateAPI', p_AllowUpdateAPI_a2a7be5afd90,
    'AllowUpdateInView', p_AllowUpdateInView_a2a7be5afd90,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_a2a7be5afd90,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_a2a7be5afd90,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_a2a7be5afd90,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_a2a7be5afd90,
    'GeneratedFormSection', p_GeneratedFormSection_a2a7be5afd90,
    'IsNameField', p_IsNameField_a2a7be5afd90,
    'RelatedEntityID', p_RelatedEntityID_a2a7be5afd90,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_a2a7be5afd90,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_a2a7be5afd90,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_a2a7be5afd90,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_a2a7be5afd90,
    'EntityIDFieldName', p_EntityIDFieldName_a2a7be5afd90,
    'ScopeDefault', p_ScopeDefault_a2a7be5afd90,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_a2a7be5afd90,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_a2a7be5afd90,
    'Status', p_Status_a2a7be5afd90,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_a2a7be5afd90,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_a2a7be5afd90,
    'AutoUpdateCategory', p_AutoUpdateCategory_a2a7be5afd90,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_a2a7be5afd90,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_a2a7be5afd90,
    'Encrypt', p_Encrypt_a2a7be5afd90,
    'EncryptionKeyID', p_EncryptionKeyID_a2a7be5afd90,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_a2a7be5afd90,
    'SendEncryptedValue', p_SendEncryptedValue_a2a7be5afd90,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_a2a7be5afd90,
    'IsSoftForeignKey', p_IsSoftForeignKey_a2a7be5afd90,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_a2a7be5afd90,
    'JSONType', p_JSONType_a2a7be5afd90,
    'JSONTypeIsArray', p_JSONTypeIsArray_a2a7be5afd90,
    'JSONTypeDefinition', p_JSONTypeDefinition_a2a7be5afd90,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_a2a7be5afd90,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_a2a7be5afd90,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_a2a7be5afd90,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_a2a7be5afd90,
    'IsComputed', p_IsComputed_a2a7be5afd90
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_a2a7be5afd90,
    'Configuration', p_Configuration_a2a7be5afd90,
    'ID', p_ID_a2a7be5afd90
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_a2a7be5afd90, p_Description := p_Description_a2a7be5afd90, p_AutoUpdateDescription := p_AutoUpdateDescription_a2a7be5afd90, p_IsPrimaryKey := p_IsPrimaryKey_a2a7be5afd90, p_IsUnique := p_IsUnique_a2a7be5afd90, p_Category := p_Category_a2a7be5afd90, p_ValueListType := p_ValueListType_a2a7be5afd90, p_ExtendedType := p_ExtendedType_a2a7be5afd90, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_a2a7be5afd90, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_a2a7be5afd90, p_ViewCellTemplate := p_ViewCellTemplate_a2a7be5afd90, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_a2a7be5afd90, p_AllowUpdateAPI := p_AllowUpdateAPI_a2a7be5afd90, p_AllowUpdateInView := p_AllowUpdateInView_a2a7be5afd90, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_a2a7be5afd90, p_FullTextSearchEnabled := p_FullTextSearchEnabled_a2a7be5afd90, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_a2a7be5afd90, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_a2a7be5afd90, p_GeneratedFormSection := p_GeneratedFormSection_a2a7be5afd90, p_IsNameField := p_IsNameField_a2a7be5afd90, p_RelatedEntityID := p_RelatedEntityID_a2a7be5afd90, p_RelatedEntityFieldName := p_RelatedEntityFieldName_a2a7be5afd90, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_a2a7be5afd90, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_a2a7be5afd90, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_a2a7be5afd90, p_EntityIDFieldName := p_EntityIDFieldName_a2a7be5afd90, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_a2a7be5afd90, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_a2a7be5afd90, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_a2a7be5afd90, p_Status := p_Status_a2a7be5afd90, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_a2a7be5afd90, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_a2a7be5afd90, p_AutoUpdateCategory := p_AutoUpdateCategory_a2a7be5afd90, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_a2a7be5afd90, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_a2a7be5afd90, p_Encrypt := p_Encrypt_a2a7be5afd90, p_EncryptionKeyID := p_EncryptionKeyID_a2a7be5afd90, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_a2a7be5afd90, p_SendEncryptedValue := p_SendEncryptedValue_a2a7be5afd90, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_a2a7be5afd90, p_IsSoftForeignKey := p_IsSoftForeignKey_a2a7be5afd90, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_a2a7be5afd90, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_a2a7be5afd90, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_a2a7be5afd90, p_JSONTypeDefinition := p_JSONTypeDefinition_a2a7be5afd90, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_a2a7be5afd90, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_a2a7be5afd90, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_a2a7be5afd90, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_a2a7be5afd90, p_IsComputed := p_IsComputed_a2a7be5afd90, p_EmbeddedRecord := p_EmbeddedRecord_a2a7be5afd90, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_a2a7be5afd90, p_Configuration_Clear := TRUE, p_ID := p_ID_a2a7be5afd90);
  END IF;
END $mj$;

-- Save MJ: Entity Settings (core SP call only)
DO $mj$
DECLARE
  p_EntityID_a9be3c13c6a0 UUID;
  p_Name_a9be3c13c6a0 VARCHAR(100);
  p_Value_a9be3c13c6a0 TEXT;
  p_Comments_a9be3c13c6a0 TEXT;
  p_ID_a9be3c13c6a0 UUID;
BEGIN
  p_EntityID_a9be3c13c6a0 := 'C8909A57-6DDB-4585-BE00-E707C5B4F262';
  p_Name_a9be3c13c6a0 := 'FieldCategoryInfo';
  p_Value_a9be3c13c6a0 := '{
  "Contract Type Details": {
    "icon": "fa fa-info-circle",
    "description": "Basic identification and status information for the contract type"
  },
  "Configuration Rules": {
    "icon": "fa fa-cogs",
    "description": "Business logic and constraints governing contract behavior and placement"
  },
  "Default Contract Terms": {
    "icon": "fa fa-sliders-h",
    "description": "Default renewal terms copied onto a new contract of this type. A starting point the user may change, not a rule."
  },
  "System Metadata": {
    "icon": "fa fa-cog",
    "description": "System-managed audit and tracking fields"
  }
}';
  p_ID_a9be3c13c6a0 := 'D2D62A86-3C4A-442A-BC2C-A0498B5F5632';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntitySetting'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntitySetting"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_a9be3c13c6a0,
    'Name', p_Name_a9be3c13c6a0,
    'Value', p_Value_a9be3c13c6a0,
    'Comments', p_Comments_a9be3c13c6a0,
    'ID', p_ID_a9be3c13c6a0
  ));
  ELSE
    PERFORM __mj."spUpdateEntitySetting"(p_EntityID := p_EntityID_a9be3c13c6a0, p_Name := p_Name_a9be3c13c6a0, p_Value := p_Value_a9be3c13c6a0, p_Comments := p_Comments_a9be3c13c6a0, p_Comments_Clear := TRUE, p_ID := p_ID_a9be3c13c6a0);
  END IF;
END $mj$;

-- Save MJ: Entity Settings (core SP call only)
DO $mj$
DECLARE
  p_EntityID_c9dd3c9ed6ef UUID;
  p_Name_c9dd3c9ed6ef VARCHAR(100);
  p_Value_c9dd3c9ed6ef TEXT;
  p_Comments_c9dd3c9ed6ef TEXT;
  p_ID_c9dd3c9ed6ef UUID;
BEGIN
  p_EntityID_c9dd3c9ed6ef := 'C8909A57-6DDB-4585-BE00-E707C5B4F262';
  p_Name_c9dd3c9ed6ef := 'FieldCategoryIcons';
  p_Value_c9dd3c9ed6ef := '{
  "Contract Type Details": "fa fa-info-circle",
  "Configuration Rules": "fa fa-cogs",
  "Default Contract Terms": "fa fa-sliders-h",
  "System Metadata": "fa fa-cog"
}';
  p_ID_c9dd3c9ed6ef := '14088B52-F54B-47E4-BC16-9C4F325C7450';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntitySetting'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntitySetting"(p_data := jsonb_build_object(
    'EntityID', p_EntityID_c9dd3c9ed6ef,
    'Name', p_Name_c9dd3c9ed6ef,
    'Value', p_Value_c9dd3c9ed6ef,
    'Comments', p_Comments_c9dd3c9ed6ef,
    'ID', p_ID_c9dd3c9ed6ef
  ));
  ELSE
    PERFORM __mj."spUpdateEntitySetting"(p_EntityID := p_EntityID_c9dd3c9ed6ef, p_Name := p_Name_c9dd3c9ed6ef, p_Value := p_Value_c9dd3c9ed6ef, p_Comments := p_Comments_c9dd3c9ed6ef, p_Comments_Clear := TRUE, p_ID := p_ID_c9dd3c9ed6ef);
  END IF;
END $mj$;

-- Save MJ: Query Categories (core SP call only)
DO $mj$
DECLARE
  p_ID_67eed53f0f80 UUID;
  p_Name_67eed53f0f80 VARCHAR(50);
  p_ParentID_67eed53f0f80 UUID;
  p_Description_67eed53f0f80 TEXT;
  p_UserID_67eed53f0f80 UUID;
  p_DefaultCacheEnabled_67eed53f0f80 BOOLEAN;
  p_DefaultCacheTTLMinutes_67eed53f0f80 INTEGER;
  p_DefaultCacheMaxSize_67eed53f0f80 INTEGER;
  p_CacheInheritanceEnabled_67eed53f0f80 BOOLEAN;
BEGIN
  p_ID_67eed53f0f80 := '403FF34D-48C7-44BD-9870-9413FC121789';
  p_Name_67eed53f0f80 := 'Contracts';
  p_Description_67eed53f0f80 := 'BizApps Contracts stored queries — read-only aggregates the client cannot express as a RunView, such as distinct-customer counts.';
  p_UserID_67eed53f0f80 := 'ECAFCCEC-6A37-EF11-86D4-000D3A4E707E';
  p_DefaultCacheEnabled_67eed53f0f80 := FALSE;
  p_CacheInheritanceEnabled_67eed53f0f80 := TRUE;
  IF NOT EXISTS (SELECT 1 FROM __mj."QueryCategory" WHERE "ID" = p_ID_67eed53f0f80) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQueryCategory'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQueryCategory"(p_data := jsonb_build_object(
      'ID', p_ID_67eed53f0f80,
      'Name', p_Name_67eed53f0f80,
      'ParentID', p_ParentID_67eed53f0f80,
      'Description', p_Description_67eed53f0f80,
      'UserID', p_UserID_67eed53f0f80,
      'DefaultCacheEnabled', p_DefaultCacheEnabled_67eed53f0f80,
      'DefaultCacheTTLMinutes', p_DefaultCacheTTLMinutes_67eed53f0f80,
      'DefaultCacheMaxSize', p_DefaultCacheMaxSize_67eed53f0f80,
      'CacheInheritanceEnabled', p_CacheInheritanceEnabled_67eed53f0f80
    ));
    ELSE
      PERFORM __mj."spCreateQueryCategory"(p_ID := p_ID_67eed53f0f80, p_Name := p_Name_67eed53f0f80, p_ParentID := p_ParentID_67eed53f0f80, p_ParentID_Clear := TRUE, p_Description := p_Description_67eed53f0f80, p_UserID := p_UserID_67eed53f0f80, p_DefaultCacheEnabled := p_DefaultCacheEnabled_67eed53f0f80, p_DefaultCacheTTLMinutes := p_DefaultCacheTTLMinutes_67eed53f0f80, p_DefaultCacheTTLMinutes_Clear := TRUE, p_DefaultCacheMaxSize := p_DefaultCacheMaxSize_67eed53f0f80, p_DefaultCacheMaxSize_Clear := TRUE, p_CacheInheritanceEnabled := p_CacheInheritanceEnabled_67eed53f0f80);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Queries (core SP call only)
DO $mj$
DECLARE
  p_ID_a3ac463e54b5 UUID;
  p_Name_a3ac463e54b5 VARCHAR(255);
  p_CategoryID_a3ac463e54b5 UUID;
  p_UserQuestion_a3ac463e54b5 TEXT;
  p_Description_a3ac463e54b5 TEXT;
  p_SQL_a3ac463e54b5 TEXT;
  p_TechnicalDescription_a3ac463e54b5 TEXT;
  p_OriginalSQL_a3ac463e54b5 TEXT;
  p_Feedback_a3ac463e54b5 TEXT;
  p_Status_a3ac463e54b5 VARCHAR(15);
  p_QualityRank_a3ac463e54b5 INTEGER;
  p_ExecutionCostRank_a3ac463e54b5 INTEGER;
  p_UsesTemplate_a3ac463e54b5 BOOLEAN;
  p_AuditQueryRuns_a3ac463e54b5 BOOLEAN;
  p_CacheEnabled_a3ac463e54b5 BOOLEAN;
  p_CacheTTLMinutes_a3ac463e54b5 INTEGER;
  p_CacheMaxSize_a3ac463e54b5 INTEGER;
  p_EmbeddingVector_a3ac463e54b5 TEXT;
  p_EmbeddingModelID_a3ac463e54b5 UUID;
  p_CacheValidationSQL_a3ac463e54b5 TEXT;
  p_SQLDialectID_a3ac463e54b5 UUID;
  p_Reusable_a3ac463e54b5 BOOLEAN;
  p_ExternalDataSourceID_a3ac463e54b5 UUID;
  p_IsMaterialized_a3ac463e54b5 BOOLEAN;
BEGIN
  p_ID_a3ac463e54b5 := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_Name_a3ac463e54b5 := 'Contracts Special Terms';
  p_CategoryID_a3ac463e54b5 := '403FF34D-48C7-44BD-9870-9413FC121789';
  p_UserQuestion_a3ac463e54b5 := 'How many clients have contracts that deviate from our standard terms, and across how many contracts?';
  p_Description_a3ac463e54b5 := 'One row: the number of DISTINCT customers holding at least one Active or Executed contract with recorded modifications, and the number of such contracts. Drives the Contracts dashboard''s "Clients with special terms" tile and its "across N contracts" footnote — one read so the two figures cannot disagree.';
  p_SQL_a3ac463e54b5 := '-- Clients with special terms — the Contracts dashboard''s fourth tile.
--
-- Two figures in ONE row, because they are one statement on the screen: "3 clients, across 7
-- contracts". Read as two queries they could disagree by the width of a write landing between them,
-- and the footnote would quietly contradict the number above it.
--
-- WHY THIS IS A STORED QUERY. The tile counts CUSTOMERS, not contracts, and a distinct count is not
-- a shape RunView returns — counting client-side would mean paging every modified contract to the
-- browser just to de-duplicate an id. The set is small today and would still be the wrong shape.
--
-- Scope matches the tile''s own wording exactly — agreements IN FORCE that deviate from standard
-- terms. An expired contract that once carried modifications is history, not a live negotiation, so
-- ''Active'' and ''Executed'' are the only states that count.
--
-- ⚠ THE SAME PREDICATE IS WRITTEN ONCE MORE IN TYPESCRIPT, as the ''special-terms'' pill in
-- packages/Angular/src/lib/pages/contract-grid.page.ts — the list this tile CLICKS THROUGH TO. The
-- two cannot be collapsed: this one has to run server-side because it counts DISTINCT customers,
-- and that one is a client filter over the same view. Change either and change both, or the tile''s
-- "across N contracts" footnote stops matching the row count of the list it opens.
--
-- There is deliberately no test comparing the two strings. This repo mirrored a rule across
-- TypeScript and SQL once before, guarded it with a text comparison, and the renderings still
-- diverged semantically while looking alike (see packages/Entities/src/contract-state.ts). The
-- on-screen disagreement between footnote and row count is the better detector.
--
-- CompanyIDs is optional and arrives from the dashboard''s company chips. `sqlIn` quotes and escapes
-- every element, so no id reaches SQL text unescaped; an empty array is guarded by the `if` rather
-- than passed through, because `sqlIn` renders `(NULL)` for an empty list — which would match
-- nothing and silently turn "All companies" into "no companies".
--
-- ⚠ THE PARAMETER ROW IS OWNED BY EXTRACTION, NOT BY metadata/. There is deliberately no
-- `MJ: Query Parameters` entry in `.contracts-special-terms.json`, and adding one breaks the push.
-- `MJQueryEntityServer.Save` runs the query-extraction pipeline synchronously after the base save
-- whenever the query is new or its SQL is dirty, so the pipeline writes its own row — fresh GUID,
-- `DetectionMethod` ''AI'' — before MetadataSync gets to any declared child, and the declared row then
-- violates `UQ_QueryParameter_QueryID_Name`. Reordering alone would not settle it either:
-- `updateParameterIfChanged` forces `DetectionMethod` back to ''AI'' and overwrites Description and
-- SampleValue from the template on every SQL change, so a hand-declared row has no stable state.
--
-- The row still reaches a host, because `metadata/` ships exactly one way — inside the release
-- `V…__Metadata_Sync.sql`, which is the SQL logger''s output from an in-process push and therefore
-- captures extraction''s own `spCreateQueryParameter` call alongside the sync''s writes. That is the
-- whole guarantee: without a parameter row the processor rejects `CompanyIDs` as an unknown
-- parameter and the tile renders a dash rather than a count.
--
-- Making the declaration work needs MetadataSync to write sync-supplied parameters before the parent
-- save that triggers extraction, and extraction to yield to them: MemberJunction/MJ#4545.
SELECT
    COUNT(DISTINCT c.CustomerOrganizationID) AS CustomerCount,
    COUNT(*) AS ContractCount
FROM [${flyway:defaultSchema}].vwContracts c
WHERE c.HasModifications = 1
  AND c.State IN (N''Active'', N''Executed'')
  {% if CompanyIDs and CompanyIDs.length %}
  AND c.CompanyID IN {{ CompanyIDs | sqlIn }}
  {% endif %};
';
  p_TechnicalDescription_a3ac463e54b5 := 'Nunjucks-parameterized on CompanyIDs (optional array of Company UUIDs from the dashboard''s company chips, passed through the sqlIn filter; omitted entirely when empty, since sqlIn renders (NULL) for an empty array and would match nothing). Aggregates __mj_BizAppsContracts.vwContracts where HasModifications = 1 and State IN (''Active'',''Executed''). Always returns exactly one row, with zeros when nothing matches. The CompanyIDs parameter row is created by the server''s query-extraction pipeline rather than declared in metadata/, and reaches a host inside the release Metadata_Sync capture; see the header of SQL/contracts-special-terms.sql for why it cannot be declared.';
  p_Status_a3ac463e54b5 := 'Approved';
  p_QualityRank_a3ac463e54b5 := 8;
  p_ExecutionCostRank_a3ac463e54b5 := 1;
  p_UsesTemplate_a3ac463e54b5 := TRUE;
  p_AuditQueryRuns_a3ac463e54b5 := FALSE;
  p_CacheEnabled_a3ac463e54b5 := FALSE;
  p_EmbeddingVector_a3ac463e54b5 := '[0.022169385105371475,0.005596051458269358,0.00707455538213253,-0.05244947597384453,-0.009096862748265266,-0.024383973330259323,0.08000393211841583,-0.005529103800654411,0.007529127411544323,-0.0032233106903731823,0.014915124513208866,-0.029113534837961197,-0.01619553007185459,0.07359115779399872,-0.01015674602240324,-0.0037982005160301924,0.016345104202628136,-0.017016030848026276,-0.028358541429042816,-0.00887939054518938,-0.01686791516840458,0.01772463507950306,-0.009171180427074432,0.002504233503714204,-0.06349053978919983,-0.012876409105956554,0.044261135160923004,-0.009017065167427063,0.03235873579978943,-0.04959047585725784,0.043183811008930206,0.028205614537000656,0.0017018463695421815,0.008453664369881153,0.0000028584506708284607,-0.019826849922537804,-0.061082873493433,0.014387909322977066,-0.05390717461705208,0.05000590160489082,-0.006398857571184635,-0.04097217693924904,0.05677734687924385,-0.008292306214571,0.020543530583381653,0.03790561482310295,-0.013536023907363415,0.013222175650298595,0.007122803013771772,-0.015348095446825027,0.023619769141077995,-0.020274575799703598,-0.1499953269958496,-0.015623524785041809,0.013173725455999374,-0.05101878196001053,-0.0032626292668282986,-0.0629899874329567,0.020443502813577652,-0.07041527330875397,-0.020557114854454994,-0.0034942063502967358,0.025606445968151093,-0.027663307264447212,0.03248736262321472,0.0009960313327610493,-0.017493365332484245,0.00756263779476285,0.021119380369782448,0.02149268053472042,0.11761211603879929,0.05525708943605423,-0.0005063068820163608,-0.050826285034418106,-0.03713817894458771,-0.010577930137515068,-0.010906585492193699,0.053428951650857925,-0.0012750871246680617,-0.03282597288489342,-0.053586918860673904,0.07150513678789139,0.013782772235572338,-0.016924254596233368,-0.06037205830216408,-0.0169009231030941,0.013509687967598438,0.006324318703263998,-0.010952524840831757,-0.025333883240818977,-0.03874969109892845,0.001846349099650979,0.06945542246103287,-0.005009190179407597,-0.022993098944425583,0.010828890837728977,0.00003534513234626502,-0.05084502696990967,0.08003630489110947,-0.007562453858554363,0.04128032922744751,-0.035335417836904526,-0.08475714176893234,0.039335381239652634,-0.02701510488986969,-0.01436219085007906,-0.009969785809516907,-0.010050663724541664,-0.018617726862430573,0.014458179473876953,0.014377739280462265,-0.005177580751478672,-0.03543435037136078,0.035666950047016144,0.009604805149137974,-0.02996865287423134,-0.019293073564767838,0.05772398039698601,-0.0019183356780558825,0.06096620857715607,0.026758378371596336,-0.014364713802933693,-0.017655840143561363,-0.07777754962444305,0.032511092722415924,-0.03292962908744812,-0.035982731729745865,-0.005004841834306717,0.013731781393289566,-0.018522504717111588,0.007024089340120554,-0.05469201132655144,0.03577730432152748,-0.026933427900075912,-0.00976331252604723,-0.03861415013670921,0.04099811613559723,-0.0006730781751684844,0.000743659446015954,-0.023861296474933624,-0.007351317908614874,0.042907971888780594,-0.07384773343801498,0.011607884429395199,-0.041373297572135925,-0.04394599050283432,-0.02290395274758339,-0.049410540610551834,-0.0028755255043506622,-0.008997229859232903,0.010091724805533886,-0.027227571234107018,-0.07118628174066544,-0.007294065784662962,0.03516872599720955,0.037202388048172,0.04707961529493332,-0.025623850524425507,0.0037834285758435726,0.01832551881670952,0.031008891761302948,-0.008950223214924335,0.0026555550284683704,-0.03616147115826607,-0.0167497880756855,0.07350988686084747,0.008153424598276615,0.032222114503383636,0.01616765558719635,-0.05782749876379967,-0.014673116616904736,-0.016349246725440025,-0.017207074910402298,-0.05502162501215935,0.03337296470999718,0.0020959179382771254,-0.00938485562801361,0.05053844675421715,-0.036946918815374374,-0.022407501935958862,-0.017538143321871758,-0.026306694373488426,0.015341510064899921,0.030635764822363853,0.08310075104236603,-0.018620705232024193,-0.02726280316710472,-0.03240467607975006,-0.020190708339214325,-0.016683092340826988,-0.007255758158862591,0.005325342062860727,-0.010821648873388767,-0.027932751923799515,0.0003345876175444573,0.009747523814439774,0.00024358804512303323,0.00805099867284298,-0.008816412650048733,-0.013974254950881004,-0.015606249682605267,-0.010986275039613247,-0.023361193016171455,0.07361897826194763,-0.019200149923563004,-0.02304929867386818,-0.08841845393180847,0.027237651869654655,-0.019422953948378563,0.052863385528326035,0.05176978558301926,0.03678673505783081,-0.007061498239636421,0.034418754279613495,0.0021887188777327538,0.006503953132778406,0.023914821445941925,-0.0030101186130195856,-0.08298399299383163,-0.007991100661456585,0.009962692856788635,-0.047955479472875595,-0.0008209376828745008,0.008287700824439526,0.02977914549410343,-0.02572944574058056,0.03278277814388275,-0.001050121383741498,-0.03284531459212303,-0.02710714004933834,0.03147956356406212,-0.0116974962875247,0.039415143430233,0.004934616386890411,0.009653649292886257,0.023970458656549454,0.0053316159173846245,0.14022883772850037,0.007028308697044849,0.03570988401770592,-0.007549119181931019,-0.03567647188901901,-0.004920841194689274,0.019594362005591393,-0.017149392515420914,-0.03544354811310768,-0.0353890135884285,-0.006517826113849878,-0.023868897929787636,0.025959761813282967,0.016213560476899147,0.04610855132341385,-0.019709525629878044,-0.019753847271203995,-0.021636085584759712,-0.008519578725099564,-0.06806978583335876,0.06052474305033684,0.029367195442318916,-0.03328244015574455,-0.035475246608257294,-0.03621834143996239,0.00020115269580855966,-0.035148996859788895,0.009067626670002937,-0.02257612906396389,0.04615595191717148,-0.015414729714393616,0.023583099246025085,-0.0012201137142255902,-0.01841052621603012,0.01813328079879284,0.013341247104108334,-0.03161204978823662,-0.019759509712457657,0.004482808988541365,-0.10651630908250809,-0.04441368207335472,0.0019402398029342294,0.022778622806072235,0.0019539794884622097,-0.058816343545913696,-0.020860834047198296,-0.006090187467634678,0.01766030862927437,-0.003123215399682522,0.00018017104594036937,0.015495979227125645,-0.030414851382374763,-0.02983441762626171,-0.047384798526763916,-0.02802956849336624,-0.004015123471617699,-0.017034068703651428,-0.007035686634480953,0.020018035545945168,-0.06871455907821655,0.054956816136837006,0.01479257456958294,0.023527927696704865,-0.04294871911406517,0.0012021289439871907,0.011527559719979763,-0.024625418707728386,-0.0008141783182509243,-0.04360195994377136,0.005914669018238783,-0.002910192357376218,-0.005327431485056877,0.01546366699039936,-0.023545557633042336,-0.014135272242128849,-0.01435481384396553,-0.007744256407022476,0.0035563893616199493,-0.023442614823579788,0.03875891491770744,0.018432635813951492,-0.051545318216085434,0.0867273285984993,0.04541903734207153,0.01107476931065321,-0.0038319977466017008,0.03190724179148674,0.002586992457509041,0.007632806897163391,-0.018355615437030792,0.020076515153050423,0.010469641536474228,-0.05508098751306534,0.033732473850250244,-0.02314966544508934,-0.07207228988409042,0.0216359943151474,-0.060978490859270096,0.004958530887961388,-0.034941669553518295,0.054312463849782944,-0.010774107649922371,-0.0072104972787201405,-0.011178156360983849,0.022324752062559128,-0.009903078898787498,-0.04068371281027794,0.030013294890522957,0.02008434198796749,0.07013097405433655,0.026538068428635597,-0.009697986766695976,-0.016405640169978142,-0.03536592051386833,0.035944901406764984,0.045518964529037476,0.01008673943579197,-0.018893448635935783,-0.08751165866851807,-0.03445632383227348,0.007681200746446848,0.023824768140912056,-0.10582061111927032,-0.03653745725750923,0.030118927359580994,-0.050380054861307144,-0.005065574310719967,-0.0029386586975306273,0.007722891867160797,-0.03190251439809799,-0.055946234613657,0.004190526902675629,-0.001281558070331812,0.0045601120218634605,-0.040315888822078705,0.03820627182722092,-0.0011359027121216059,0.018000418320298195,0.03627784550189972,0.04764873906970024,0.012921859510242939,0.03345328941941261,0.006617405451834202,-0.011892743408679962,-0.11186417937278748,0.09503401070833206,-0.024252580478787422,0.019873328506946564,-0.0026418520137667656,-0.02095680870115757,-0.0870886892080307,0.026047194376587868,0.020080119371414185,0.004059688653796911,0.08064059913158417,0.07303876429796219,0.07518132030963898,0.03144436702132225,0.00923536904156208,0.011630005203187466,0.02888607047498226,-0.007039476186037064,0.017960358411073685,0.04348195716738701,0.002196436980739236,0.04229183867573738,-0.011618858203291893,0.006212660111486912,-0.03307446837425232,-0.02028707228600979,-0.04697908088564873,-0.013707827776670456,0.020517876371741295,-0.02502541057765484,0.0137689970433712,0.03175527602434158,0.01453112531453371,0.03940754756331444,0.035391516983509064,-0.03106280229985714,-0.03579472377896309,-0.05629339441657066,-0.08672016113996506,0.05531630292534828,-0.0011728674871847034,0.014070079661905766,-0.016419285908341408,-0.0021730114240199327,-0.00030219697509892285,-0.031664956361055374,-0.05137725546956062,-0.009139048866927624,-0.019474752247333527,-0.04986722394824028,0.0035541674587875605,-0.02068152464926243,0.00900829304009676,0.00631393026560545,0.06763923168182373,-0.018178366124629974,-0.03847174346446991,-0.07857311517000198,-0.016795780509710312,-0.022742411121726036,-0.009488793089985847,0.012718642130494118,0.008520357310771942,0.034210361540317535,0.055666401982307434,-0.03258265554904938,0.06313522160053253,-0.009869041852653027,-0.035576287657022476,0.026121824979782104,-0.008309177123010159,0.03131988272070885,-0.04196704551577568,0.03525083139538765,-0.042571183294057846,-0.09462857246398926,-0.0553380511701107,-0.024356365203857422,0.018458057194948196,-0.01646362990140915,0.02012258768081665,-0.058770082890987396,0.01704595237970352,0.028545603156089783,-0.11408727616071701,0.030008593574166298,-0.00830004457384348,0.012734889052808285,0.047625474631786346,-0.028424173593521118,-0.010278034955263138,-0.02824176475405693,0.015983538702130318,-0.002202538773417473,0.05345907062292099,-0.01638387143611908,-0.09181543439626694,0.03944714739918709,0.060559630393981934,0.0058951303362846375,-0.04384498670697212,0.005145764444023371,0.03593776747584343,-0.004730990156531334,0.013544328510761261,0.023901034146547318,0.013375293463468552,0.011535490863025188,0.0027811916079372168,0.03547505661845207,-0.010933654382824898,-0.04376771301031113,0.09514155238866806,0.0010256064124405384,0.059020645916461945,-0.004088800400495529,0.03002144768834114,0.00658367108553648,-0.056058213114738464,0.03179069608449936,0.026809528470039368,-0.037307243794202805,0.004552152007818222,0.00562630919739604,0.02608659118413925,0.013600068166851997,-0.00985212717205286,0.025348618626594543,0.019564682617783546,0.0028891500551253557,0.01443452388048172,0.040078409016132355,-0.09281613677740097,0.03776330500841141,0.016560789197683334,-0.03632049262523651,0.03239928558468819,-0.02390531823039055,0.008411295711994171,0.031488776206970215,-0.016773439943790436,0.020158620551228523,0.009640543721616268,0.022254880517721176,-0.043315339833498,0.010687482543289661,0.024319566786289215,-0.008905970491468906,0.06976456195116043,-0.021009352058172226,0.00043067042133770883,-0.05097405984997749,0.08329318463802338,0.028390899300575256,0.011669093742966652,0.015397611074149609,-0.002949243411421776,0.01787627302110195,0.0062421043403446674,-0.053271498531103134,-0.02935204841196537,0.06285812705755234,-0.04155200719833374,0.02042585052549839,0.0041284034959971905,0.029932355508208275,0.00839486625045538,0.012498155236244202,-0.05999038740992546,0.012742557562887669,-0.006710111163556576,0.039546284824609756,0.007667624857276678,-0.007611569482833147,-8.527902947948605e-33,-0.043077461421489716,-0.020064176991581917,-0.017418742179870605,-0.01709294691681862,-0.06533259153366089,-0.018347779288887978,-0.011628594249486923,0.014433092437684536,-0.00564126530662179,0.0088429506868124,-0.01974525675177574,0.05008401349186897,0.02494112029671669,-0.011968831531703472,0.05161447450518608,-0.01322048157453537,0.05581559240818024,0.00035053599276579916,0.03559941053390503,0.009357498958706856,-0.00829172320663929,0.012032248079776764,0.054849788546562195,-0.07134010642766953,0.057523079216480255,-0.041639115661382675,-0.02280358225107193,-0.05273034796118736,-0.021317554637789726,-0.0028477490413933992,0.022443203255534172,-0.02731822431087494,0.00798146054148674,-0.05035234987735748,-0.015366829000413418,-0.02349591813981533,0.03364059701561928,-0.011784517206251621,0.000971115892753005,0.012690579518675804,0.07509627938270569,-0.024239230901002884,0.037774115800857544,0.0010864274809136987,-0.05825082212686539,-0.04627794772386551,0.02465316280722618,-0.0019513979787006974,-0.0384150892496109,0.03634129464626312,0.027340823784470558,0.005705223418772221,-0.012965323403477669,0.09692320227622986,-0.03308757767081261,-0.03281649947166443,-0.00042837904766201973,0.022707851603627205,-0.05236991122364998,0.012961662374436855,0.004910388495773077,0.0061278510838747025,-0.009352787397801876,-0.06293677538633347,0.006301253568381071,-0.025276703760027885,-0.11223315447568893,0.037475939840078354,0.0019297368125990033,-0.028235746547579765,-0.04696536064147949,0.1505841761827469,-0.038462284952402115,-0.02815571241080761,0.04034297540783882,-0.040948543697595596,-0.00858616828918457,-0.04384233430027962,0.031901318579912186,-0.0028241933323442936,0.06910347938537598,0.017134785652160645,-0.003863117191940546,0.001610277220606804,-0.025636987760663033,0.015510809607803822,0.0120646758005023,-0.03192669525742531,0.01029429491609335,-0.017128493636846542,0.03931955620646477,0.03911084681749344,-0.020105673000216484,-0.002932389033958316,-0.060117028653621674,-0.05234469845890999,0.06969009339809418,0.01665554754436016,0.0007682493887841702,0.0036936996039003134,0.003455854021012783,0.034429728984832764,-0.0001916616893140599,-0.07123985886573792,-0.002243257826194167,0.03248182684183121,0.06222596392035484,-0.023866266012191772,-0.064041368663311,0.04759979248046875,0.03847381845116615,0.008592648431658745,0.017578180879354477,0.07598354667425156,0.025814851745963097,-0.049197256565093994,0.017773104831576347,0.03266669064760208,0.007204737514257431,-0.004751578439027071,-0.008284385316073895,0.009253299795091152,-0.03900120034813881,0.04286448284983635,-0.01034309808164835,0.012850453145802021,0.049044545739889145,-0.06395349651575089,0.04237962141633034,0.030703263357281685,0.019610660150647163,-0.0013192890910431743,3.5743491366702074e-7,0.013157111592590809,0.0304756797850132,-0.02814105898141861,-0.0016794956754893064,0.06245442107319832,0.032563187181949615,0.0020011693704873323,0.04625003784894943,-0.03638193756341934,-0.052654922008514404,0.020974135026335716,-0.028807634487748146,0.014380576089024544,0.0057230317033827305,0.0017922823317348957,0.003940548747777939,-0.059813905507326126,-0.033797696232795715,-0.020719638094305992,-0.011488432064652443,0.043075647205114365,-0.03688690438866615,0.005717157851904631,-0.007106938865035772,0.021076742559671402,-0.040303636342287064,0.016883783042430878,-0.05498650670051575,-0.00623386912047863,0.05829096585512161,0.028737623244524002,-0.030171167105436325,0.03509604185819626,-0.037359416484832764,-0.009484712034463882,0.022039642557501793,0.02234819531440735,0.050739213824272156,-0.00579058937728405,0.03888576477766037,0.016001950949430466,-0.0801243782043457,0.01762424223124981,0.0008890588651411235,-0.03242618218064308,0.07718399912118912,0.011273027397692204,-0.013788524083793163,-0.029842548072338104,-0.04539639130234718,0.03574712947010994,0.015481633134186268,0.03104265406727791,-0.022457541897892952,0.05791635066270828,0.027955498546361923,0.016808999702334404,-0.006985811982303858,0.030886288732290268,0.05850469693541527,-0.00904847215861082,0.030307935550808907,0.026347212493419647,0.05439453944563866,0.008995726704597473,0.04451170936226845,-0.02535109780728817,3.0781811903094166e-34,0.017820389941334724,0.0024380425456911325,-0.003480719169601798,0.0437672920525074,0.013563346117734909,-0.0028986309189349413,-0.03067971207201481,-0.029357105493545532,0.009288018569350243,0.005952227860689163,-0.00831421185284853]';
  p_EmbeddingModelID_a3ac463e54b5 := '1D45AA65-41EC-4572-9ECD-AB2826C9B059';
  p_Reusable_a3ac463e54b5 := FALSE;
  p_IsMaterialized_a3ac463e54b5 := FALSE;
  IF NOT EXISTS (SELECT 1 FROM __mj."Query" WHERE "ID" = p_ID_a3ac463e54b5) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQuery'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQuery"(p_data := jsonb_build_object(
      'ID', p_ID_a3ac463e54b5,
      'Name', p_Name_a3ac463e54b5,
      'CategoryID', p_CategoryID_a3ac463e54b5,
      'UserQuestion', p_UserQuestion_a3ac463e54b5,
      'Description', p_Description_a3ac463e54b5,
      'SQL', p_SQL_a3ac463e54b5,
      'TechnicalDescription', p_TechnicalDescription_a3ac463e54b5,
      'OriginalSQL', p_OriginalSQL_a3ac463e54b5,
      'Feedback', p_Feedback_a3ac463e54b5,
      'Status', p_Status_a3ac463e54b5,
      'QualityRank', p_QualityRank_a3ac463e54b5,
      'ExecutionCostRank', p_ExecutionCostRank_a3ac463e54b5,
      'UsesTemplate', p_UsesTemplate_a3ac463e54b5,
      'AuditQueryRuns', p_AuditQueryRuns_a3ac463e54b5,
      'CacheEnabled', p_CacheEnabled_a3ac463e54b5,
      'CacheTTLMinutes', p_CacheTTLMinutes_a3ac463e54b5,
      'CacheMaxSize', p_CacheMaxSize_a3ac463e54b5,
      'EmbeddingVector', p_EmbeddingVector_a3ac463e54b5,
      'EmbeddingModelID', p_EmbeddingModelID_a3ac463e54b5,
      'CacheValidationSQL', p_CacheValidationSQL_a3ac463e54b5,
      'SQLDialectID', p_SQLDialectID_a3ac463e54b5,
      'Reusable', p_Reusable_a3ac463e54b5,
      'ExternalDataSourceID', p_ExternalDataSourceID_a3ac463e54b5,
      'IsMaterialized', p_IsMaterialized_a3ac463e54b5
    ));
    ELSE
      PERFORM __mj."spCreateQuery"(p_ID := p_ID_a3ac463e54b5, p_Name := p_Name_a3ac463e54b5, p_CategoryID := p_CategoryID_a3ac463e54b5, p_UserQuestion := p_UserQuestion_a3ac463e54b5, p_Description := p_Description_a3ac463e54b5, p_SQL := p_SQL_a3ac463e54b5, p_TechnicalDescription := p_TechnicalDescription_a3ac463e54b5, p_OriginalSQL := p_OriginalSQL_a3ac463e54b5, p_OriginalSQL_Clear := TRUE, p_Feedback := p_Feedback_a3ac463e54b5, p_Feedback_Clear := TRUE, p_Status := p_Status_a3ac463e54b5, p_QualityRank := p_QualityRank_a3ac463e54b5, p_ExecutionCostRank := p_ExecutionCostRank_a3ac463e54b5, p_UsesTemplate := p_UsesTemplate_a3ac463e54b5, p_AuditQueryRuns := p_AuditQueryRuns_a3ac463e54b5, p_CacheEnabled := p_CacheEnabled_a3ac463e54b5, p_CacheTTLMinutes := p_CacheTTLMinutes_a3ac463e54b5, p_CacheTTLMinutes_Clear := TRUE, p_CacheMaxSize := p_CacheMaxSize_a3ac463e54b5, p_CacheMaxSize_Clear := TRUE, p_EmbeddingVector := p_EmbeddingVector_a3ac463e54b5, p_EmbeddingModelID := p_EmbeddingModelID_a3ac463e54b5, p_CacheValidationSQL := p_CacheValidationSQL_a3ac463e54b5, p_CacheValidationSQL_Clear := TRUE, p_SQLDialectID := p_SQLDialectID_a3ac463e54b5, p_Reusable := p_Reusable_a3ac463e54b5, p_ExternalDataSourceID := p_ExternalDataSourceID_a3ac463e54b5, p_ExternalDataSourceID_Clear := TRUE, p_IsMaterialized := p_IsMaterialized_a3ac463e54b5);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Query Parameters (core SP call only)
DO $mj$
DECLARE
  p_ID_66ccd7b9f6a5 UUID;
  p_QueryID_66ccd7b9f6a5 UUID;
  p_Name_66ccd7b9f6a5 VARCHAR(255);
  p_Type_66ccd7b9f6a5 VARCHAR(50);
  p_IsRequired_66ccd7b9f6a5 BOOLEAN;
  p_DefaultValue_66ccd7b9f6a5 TEXT;
  p_Description_66ccd7b9f6a5 TEXT;
  p_SampleValue_66ccd7b9f6a5 TEXT;
  p_ValidationFilters_66ccd7b9f6a5 TEXT;
  p_DetectionMethod_66ccd7b9f6a5 VARCHAR(50);
  p_AutoDetectConfidenceScore_66ccd7b9f6a5 NUMERIC(3,2);
BEGIN
  p_ID_66ccd7b9f6a5 := '83c76781-db5d-4967-850a-d7023a92b204';
  p_QueryID_66ccd7b9f6a5 := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_Name_66ccd7b9f6a5 := 'CompanyIDs';
  p_Type_66ccd7b9f6a5 := 'array';
  p_IsRequired_66ccd7b9f6a5 := FALSE;
  p_Description_66ccd7b9f6a5 := 'Optional list of values for Company I Ds';
  p_SampleValue_66ccd7b9f6a5 := 'Value1,Value2';
  p_DetectionMethod_66ccd7b9f6a5 := 'AI';
  IF NOT EXISTS (SELECT 1 FROM __mj."QueryParameter" WHERE "ID" = p_ID_66ccd7b9f6a5 OR ("QueryID" = p_QueryID_66ccd7b9f6a5 AND "Name" = p_Name_66ccd7b9f6a5)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQueryParameter'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQueryParameter"(p_data := jsonb_build_object(
      'ID', p_ID_66ccd7b9f6a5,
      'QueryID', p_QueryID_66ccd7b9f6a5,
      'Name', p_Name_66ccd7b9f6a5,
      'Type', p_Type_66ccd7b9f6a5,
      'IsRequired', p_IsRequired_66ccd7b9f6a5,
      'DefaultValue', p_DefaultValue_66ccd7b9f6a5,
      'Description', p_Description_66ccd7b9f6a5,
      'SampleValue', p_SampleValue_66ccd7b9f6a5,
      'ValidationFilters', p_ValidationFilters_66ccd7b9f6a5,
      'DetectionMethod', p_DetectionMethod_66ccd7b9f6a5,
      'AutoDetectConfidenceScore', p_AutoDetectConfidenceScore_66ccd7b9f6a5
    ));
    ELSE
      PERFORM __mj."spCreateQueryParameter"(p_ID := p_ID_66ccd7b9f6a5, p_QueryID := p_QueryID_66ccd7b9f6a5, p_Name := p_Name_66ccd7b9f6a5, p_Type := p_Type_66ccd7b9f6a5, p_IsRequired := p_IsRequired_66ccd7b9f6a5, p_DefaultValue := p_DefaultValue_66ccd7b9f6a5, p_DefaultValue_Clear := TRUE, p_Description := p_Description_66ccd7b9f6a5, p_SampleValue := p_SampleValue_66ccd7b9f6a5, p_ValidationFilters := p_ValidationFilters_66ccd7b9f6a5, p_ValidationFilters_Clear := TRUE, p_DetectionMethod := p_DetectionMethod_66ccd7b9f6a5, p_AutoDetectConfidenceScore := p_AutoDetectConfidenceScore_66ccd7b9f6a5, p_AutoDetectConfidenceScore_Clear := TRUE);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Query Fields (core SP call only)
DO $mj$
DECLARE
  p_ID_adf1a0a4fded UUID;
  p_QueryID_adf1a0a4fded UUID;
  p_Name_adf1a0a4fded VARCHAR(255);
  p_Description_adf1a0a4fded TEXT;
  p_Sequence_adf1a0a4fded INTEGER;
  p_SQLBaseType_adf1a0a4fded VARCHAR(50);
  p_SQLFullType_adf1a0a4fded VARCHAR(100);
  p_SourceEntityID_adf1a0a4fded UUID;
  p_SourceFieldName_adf1a0a4fded VARCHAR(255);
  p_IsComputed_adf1a0a4fded BOOLEAN;
  p_ComputationDescription_adf1a0a4fded TEXT;
  p_IsSummary_adf1a0a4fded BOOLEAN;
  p_SummaryDescription_adf1a0a4fded TEXT;
  p_DetectionMethod_adf1a0a4fded VARCHAR(50);
  p_AutoDetectConfidenceScore_adf1a0a4fded NUMERIC(3,2);
BEGIN
  p_ID_adf1a0a4fded := 'd4e03b09-a3e8-41b1-a3fb-5faa95911cdd';
  p_QueryID_adf1a0a4fded := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_Name_adf1a0a4fded := 'CustomerCount';
  p_Description_adf1a0a4fded := 'Computed column: CustomerCount';
  p_Sequence_adf1a0a4fded := 1;
  p_SQLBaseType_adf1a0a4fded := 'nvarchar';
  p_SQLFullType_adf1a0a4fded := 'nvarchar(MAX)';
  p_IsComputed_adf1a0a4fded := TRUE;
  p_IsSummary_adf1a0a4fded := FALSE;
  p_DetectionMethod_adf1a0a4fded := 'Manual';
  IF NOT EXISTS (SELECT 1 FROM __mj."QueryField" WHERE "ID" = p_ID_adf1a0a4fded OR ("QueryID" = p_QueryID_adf1a0a4fded AND "Name" = p_Name_adf1a0a4fded)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQueryField'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQueryField"(p_data := jsonb_build_object(
      'ID', p_ID_adf1a0a4fded,
      'QueryID', p_QueryID_adf1a0a4fded,
      'Name', p_Name_adf1a0a4fded,
      'Description', p_Description_adf1a0a4fded,
      'Sequence', p_Sequence_adf1a0a4fded,
      'SQLBaseType', p_SQLBaseType_adf1a0a4fded,
      'SQLFullType', p_SQLFullType_adf1a0a4fded,
      'SourceEntityID', p_SourceEntityID_adf1a0a4fded,
      'SourceFieldName', p_SourceFieldName_adf1a0a4fded,
      'IsComputed', p_IsComputed_adf1a0a4fded,
      'ComputationDescription', p_ComputationDescription_adf1a0a4fded,
      'IsSummary', p_IsSummary_adf1a0a4fded,
      'SummaryDescription', p_SummaryDescription_adf1a0a4fded,
      'DetectionMethod', p_DetectionMethod_adf1a0a4fded,
      'AutoDetectConfidenceScore', p_AutoDetectConfidenceScore_adf1a0a4fded
    ));
    ELSE
      PERFORM __mj."spCreateQueryField"(p_ID := p_ID_adf1a0a4fded, p_QueryID := p_QueryID_adf1a0a4fded, p_Name := p_Name_adf1a0a4fded, p_Description := p_Description_adf1a0a4fded, p_Sequence := p_Sequence_adf1a0a4fded, p_SQLBaseType := p_SQLBaseType_adf1a0a4fded, p_SQLFullType := p_SQLFullType_adf1a0a4fded, p_SourceEntityID := p_SourceEntityID_adf1a0a4fded, p_SourceEntityID_Clear := TRUE, p_SourceFieldName := p_SourceFieldName_adf1a0a4fded, p_SourceFieldName_Clear := TRUE, p_IsComputed := p_IsComputed_adf1a0a4fded, p_ComputationDescription := p_ComputationDescription_adf1a0a4fded, p_ComputationDescription_Clear := TRUE, p_IsSummary := p_IsSummary_adf1a0a4fded, p_SummaryDescription := p_SummaryDescription_adf1a0a4fded, p_SummaryDescription_Clear := TRUE, p_DetectionMethod := p_DetectionMethod_adf1a0a4fded, p_AutoDetectConfidenceScore := p_AutoDetectConfidenceScore_adf1a0a4fded, p_AutoDetectConfidenceScore_Clear := TRUE);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Query Fields (core SP call only)
DO $mj$
DECLARE
  p_ID_f5e974578116 UUID;
  p_QueryID_f5e974578116 UUID;
  p_Name_f5e974578116 VARCHAR(255);
  p_Description_f5e974578116 TEXT;
  p_Sequence_f5e974578116 INTEGER;
  p_SQLBaseType_f5e974578116 VARCHAR(50);
  p_SQLFullType_f5e974578116 VARCHAR(100);
  p_SourceEntityID_f5e974578116 UUID;
  p_SourceFieldName_f5e974578116 VARCHAR(255);
  p_IsComputed_f5e974578116 BOOLEAN;
  p_ComputationDescription_f5e974578116 TEXT;
  p_IsSummary_f5e974578116 BOOLEAN;
  p_SummaryDescription_f5e974578116 TEXT;
  p_DetectionMethod_f5e974578116 VARCHAR(50);
  p_AutoDetectConfidenceScore_f5e974578116 NUMERIC(3,2);
BEGIN
  p_ID_f5e974578116 := '2227330b-b312-4eac-bb96-ba5b39a0341d';
  p_QueryID_f5e974578116 := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_Name_f5e974578116 := 'ContractCount';
  p_Description_f5e974578116 := 'Computed column: ContractCount';
  p_Sequence_f5e974578116 := 2;
  p_SQLBaseType_f5e974578116 := 'nvarchar';
  p_SQLFullType_f5e974578116 := 'nvarchar(MAX)';
  p_IsComputed_f5e974578116 := TRUE;
  p_IsSummary_f5e974578116 := FALSE;
  p_DetectionMethod_f5e974578116 := 'Manual';
  IF NOT EXISTS (SELECT 1 FROM __mj."QueryField" WHERE "ID" = p_ID_f5e974578116 OR ("QueryID" = p_QueryID_f5e974578116 AND "Name" = p_Name_f5e974578116)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQueryField'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQueryField"(p_data := jsonb_build_object(
      'ID', p_ID_f5e974578116,
      'QueryID', p_QueryID_f5e974578116,
      'Name', p_Name_f5e974578116,
      'Description', p_Description_f5e974578116,
      'Sequence', p_Sequence_f5e974578116,
      'SQLBaseType', p_SQLBaseType_f5e974578116,
      'SQLFullType', p_SQLFullType_f5e974578116,
      'SourceEntityID', p_SourceEntityID_f5e974578116,
      'SourceFieldName', p_SourceFieldName_f5e974578116,
      'IsComputed', p_IsComputed_f5e974578116,
      'ComputationDescription', p_ComputationDescription_f5e974578116,
      'IsSummary', p_IsSummary_f5e974578116,
      'SummaryDescription', p_SummaryDescription_f5e974578116,
      'DetectionMethod', p_DetectionMethod_f5e974578116,
      'AutoDetectConfidenceScore', p_AutoDetectConfidenceScore_f5e974578116
    ));
    ELSE
      PERFORM __mj."spCreateQueryField"(p_ID := p_ID_f5e974578116, p_QueryID := p_QueryID_f5e974578116, p_Name := p_Name_f5e974578116, p_Description := p_Description_f5e974578116, p_Sequence := p_Sequence_f5e974578116, p_SQLBaseType := p_SQLBaseType_f5e974578116, p_SQLFullType := p_SQLFullType_f5e974578116, p_SourceEntityID := p_SourceEntityID_f5e974578116, p_SourceEntityID_Clear := TRUE, p_SourceFieldName := p_SourceFieldName_f5e974578116, p_SourceFieldName_Clear := TRUE, p_IsComputed := p_IsComputed_f5e974578116, p_ComputationDescription := p_ComputationDescription_f5e974578116, p_ComputationDescription_Clear := TRUE, p_IsSummary := p_IsSummary_f5e974578116, p_SummaryDescription := p_SummaryDescription_f5e974578116, p_SummaryDescription_Clear := TRUE, p_DetectionMethod := p_DetectionMethod_f5e974578116, p_AutoDetectConfidenceScore := p_AutoDetectConfidenceScore_f5e974578116, p_AutoDetectConfidenceScore_Clear := TRUE);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Query Entities (core SP call only)
DO $mj$
DECLARE
  p_ID_a0a9ecc71164 UUID;
  p_QueryID_a0a9ecc71164 UUID;
  p_EntityID_a0a9ecc71164 UUID;
  p_DetectionMethod_a0a9ecc71164 VARCHAR(50);
  p_AutoDetectConfidenceScore_a0a9ecc71164 NUMERIC(3,2);
BEGIN
  p_ID_a0a9ecc71164 := '16aa8dbf-db51-4f6b-9059-386dbeff6fef';
  p_QueryID_a0a9ecc71164 := 'A93597C0-100E-4059-ABC5-E08DD708E520';
  p_EntityID_a0a9ecc71164 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_DetectionMethod_a0a9ecc71164 := 'AI';
  p_AutoDetectConfidenceScore_a0a9ecc71164 := 1;
  IF NOT EXISTS (SELECT 1 FROM __mj."QueryEntity" WHERE "ID" = p_ID_a0a9ecc71164 OR ("QueryID" = p_QueryID_a0a9ecc71164 AND "EntityID" = p_EntityID_a0a9ecc71164)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateQueryEntity'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateQueryEntity"(p_data := jsonb_build_object(
      'ID', p_ID_a0a9ecc71164,
      'QueryID', p_QueryID_a0a9ecc71164,
      'EntityID', p_EntityID_a0a9ecc71164,
      'DetectionMethod', p_DetectionMethod_a0a9ecc71164,
      'AutoDetectConfidenceScore', p_AutoDetectConfidenceScore_a0a9ecc71164
    ));
    ELSE
      PERFORM __mj."spCreateQueryEntity"(p_ID := p_ID_a0a9ecc71164, p_QueryID := p_QueryID_a0a9ecc71164, p_EntityID := p_EntityID_a0a9ecc71164, p_DetectionMethod := p_DetectionMethod_a0a9ecc71164, p_AutoDetectConfidenceScore := p_AutoDetectConfidenceScore_a0a9ecc71164);
    END IF;
  END IF;
END $mj$;

-- Save MJ: User Views (core SP call only)
DO $mj$
DECLARE
  p_ID_856a987a0283 UUID;
  p_UserID_856a987a0283 UUID;
  p_EntityID_856a987a0283 UUID;
  p_Name_856a987a0283 VARCHAR(100);
  p_Description_856a987a0283 TEXT;
  p_CategoryID_856a987a0283 UUID;
  p_IsShared_856a987a0283 BOOLEAN;
  p_IsDefault_856a987a0283 BOOLEAN;
  p_GridState_856a987a0283 TEXT;
  p_FilterState_856a987a0283 TEXT;
  p_CustomFilterState_856a987a0283 BOOLEAN;
  p_SmartFilterEnabled_856a987a0283 BOOLEAN;
  p_SmartFilterPrompt_856a987a0283 TEXT;
  p_SmartFilterWhereClause_856a987a0283 TEXT;
  p_SmartFilterExplanation_856a987a0283 TEXT;
  p_WhereClause_856a987a0283 TEXT;
  p_CustomWhereClause_856a987a0283 BOOLEAN;
  p_SortState_856a987a0283 TEXT;
  p_Thumbnail_856a987a0283 TEXT;
  p_CardState_856a987a0283 TEXT;
  p_DisplayState_856a987a0283 TEXT;
  p_ViewTypeID_856a987a0283 UUID;
BEGIN
  p_ID_856a987a0283 := 'C0A7C7ED-0001-4C6D-8E9F-0A1B2C3D4E5F';
  p_UserID_856a987a0283 := 'ECAFCCEC-6A37-EF11-86D4-000D3A4E707E';
  p_EntityID_856a987a0283 := '5DEB0B11-ED6C-48B3-9200-F4441396C5E2';
  p_Name_856a987a0283 := 'Contracts: Watchlist';
  p_Description_856a987a0283 := 'Agreements with term, state, customer, auto-renew, and days-to-end — the scan an AE or exec actually does.';
  p_IsShared_856a987a0283 := TRUE;
  p_IsDefault_856a987a0283 := FALSE;
  p_GridState_856a987a0283 := '{"sortSettings":[{"field":"DaysToEnd","dir":"asc"}],"columnSettings":[{"Name":"ContractNumber","DisplayName":"Number","orderIndex":0,"width":120,"pinned":"left"},{"Name":"CustomerOrganization","DisplayName":"Customer","orderIndex":1,"width":200},{"Name":"ContractType","DisplayName":"Type","orderIndex":2,"width":130},{"Name":"State","DisplayName":"State","orderIndex":3,"width":110,"format":{"type":"text","conditionalRules":[{"condition":"equals","value":"Active","style":{"color":"#047857","backgroundColor":"#d1fae5","bold":true}},{"condition":"equals","value":"Executed","style":{"color":"#1d4ed8","backgroundColor":"#dbeafe"}},{"condition":"equals","value":"Terminated","style":{"color":"#b45309","backgroundColor":"#fef3c7"}}]}},{"Name":"EffectiveDate","DisplayName":"Effective","orderIndex":4,"width":120,"format":{"type":"date","dateFormat":"medium"}},{"Name":"EndDate","DisplayName":"Ends","orderIndex":5,"width":120,"format":{"type":"date","dateFormat":"medium"}},{"Name":"DaysToEnd","DisplayName":"Days left","orderIndex":6,"width":100,"format":{"type":"number","decimals":0,"align":"right","conditionalRules":[{"condition":"lessThan","value":0,"style":{"color":"#b45309","bold":true}},{"condition":"lessThanOrEqual","value":60,"style":{"color":"#b45309"}}]}},{"Name":"AutoRenew","DisplayName":"Auto-renew","orderIndex":7,"width":110,"format":{"type":"boolean","trueLabel":"Yes","falseLabel":"No"}},{"Name":"Company","DisplayName":"Selling as","orderIndex":8,"width":140}]}';
  p_FilterState_856a987a0283 := '{"logic":"and","filters":[]}';
  p_CustomFilterState_856a987a0283 := FALSE;
  p_SmartFilterEnabled_856a987a0283 := FALSE;
  p_WhereClause_856a987a0283 := '';
  p_CustomWhereClause_856a987a0283 := FALSE;
  IF NOT EXISTS (SELECT 1 FROM __mj."UserView" WHERE "ID" = p_ID_856a987a0283) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '__mj' AND p.proname = 'spCreateUserView'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM __mj."spCreateUserView"(p_data := jsonb_build_object(
      'ID', p_ID_856a987a0283,
      'UserID', p_UserID_856a987a0283,
      'EntityID', p_EntityID_856a987a0283,
      'Name', p_Name_856a987a0283,
      'Description', p_Description_856a987a0283,
      'CategoryID', p_CategoryID_856a987a0283,
      'IsShared', p_IsShared_856a987a0283,
      'IsDefault', p_IsDefault_856a987a0283,
      'GridState', p_GridState_856a987a0283,
      'FilterState', p_FilterState_856a987a0283,
      'CustomFilterState', p_CustomFilterState_856a987a0283,
      'SmartFilterEnabled', p_SmartFilterEnabled_856a987a0283,
      'SmartFilterPrompt', p_SmartFilterPrompt_856a987a0283,
      'SmartFilterWhereClause', p_SmartFilterWhereClause_856a987a0283,
      'SmartFilterExplanation', p_SmartFilterExplanation_856a987a0283,
      'WhereClause', p_WhereClause_856a987a0283,
      'CustomWhereClause', p_CustomWhereClause_856a987a0283,
      'SortState', p_SortState_856a987a0283,
      'Thumbnail', p_Thumbnail_856a987a0283,
      'CardState', p_CardState_856a987a0283,
      'DisplayState', p_DisplayState_856a987a0283,
      'ViewTypeID', p_ViewTypeID_856a987a0283
    ));
    ELSE
      PERFORM __mj."spCreateUserView"(p_ID := p_ID_856a987a0283, p_UserID := p_UserID_856a987a0283, p_EntityID := p_EntityID_856a987a0283, p_Name := p_Name_856a987a0283, p_Description := p_Description_856a987a0283, p_CategoryID := p_CategoryID_856a987a0283, p_CategoryID_Clear := TRUE, p_IsShared := p_IsShared_856a987a0283, p_IsDefault := p_IsDefault_856a987a0283, p_GridState := p_GridState_856a987a0283, p_FilterState := p_FilterState_856a987a0283, p_CustomFilterState := p_CustomFilterState_856a987a0283, p_SmartFilterEnabled := p_SmartFilterEnabled_856a987a0283, p_SmartFilterPrompt := p_SmartFilterPrompt_856a987a0283, p_SmartFilterPrompt_Clear := TRUE, p_SmartFilterWhereClause := p_SmartFilterWhereClause_856a987a0283, p_SmartFilterWhereClause_Clear := TRUE, p_SmartFilterExplanation := p_SmartFilterExplanation_856a987a0283, p_SmartFilterExplanation_Clear := TRUE, p_WhereClause := p_WhereClause_856a987a0283, p_CustomWhereClause := p_CustomWhereClause_856a987a0283, p_SortState := p_SortState_856a987a0283, p_SortState_Clear := TRUE, p_Thumbnail := p_Thumbnail_856a987a0283, p_Thumbnail_Clear := TRUE, p_CardState := p_CardState_856a987a0283, p_CardState_Clear := TRUE, p_DisplayState := p_DisplayState_856a987a0283, p_DisplayState_Clear := TRUE, p_ViewTypeID := p_ViewTypeID_856a987a0283, p_ViewTypeID_Clear := TRUE);
    END IF;
  END IF;
END $mj$;
