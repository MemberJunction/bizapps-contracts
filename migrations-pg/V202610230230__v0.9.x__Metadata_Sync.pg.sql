-- =============================================================================================
-- PostgreSQL counterpart of V202610230230__v0.9.x__Metadata_Sync.sql -- BizApps Contracts v0.9.x Metadata_Sync
-- =============================================================================================
-- Same record, same values as the T-SQL file; see its header for what ships and why.
--
-- HOW IT WAS MADE
--   * `mj sql-convert --from tsql --to postgres` (MJ CLI 6.1.6) on the push log, the core schema
--     written as `__mj` first so the converter does not skip the call. The record is a DO block that
--     calls the core function in whichever signature the host has (jsonb or named parameters).
--   * Core calls then use `${mjSchema}`, as the Common, Orders and Sales seeds do.
--   * Every value matches the T-SQL file (strings verbatim, BIT 1/0 as TRUE/FALSE); checked one by one.
--   * The block was checked to parse and compile on postgres:16.
-- =============================================================================================

SET standard_conforming_strings = on;
-- ===================== Data (INSERT/UPDATE/DELETE) =====================

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_f91524d0d02b VARCHAR(255);
  p_Description_f91524d0d02b TEXT;
  p_AutoUpdateDescription_f91524d0d02b BOOLEAN;
  p_IsPrimaryKey_f91524d0d02b BOOLEAN;
  p_IsUnique_f91524d0d02b BOOLEAN;
  p_Category_f91524d0d02b VARCHAR(255);
  p_ValueListType_f91524d0d02b VARCHAR(20);
  p_ExtendedType_f91524d0d02b VARCHAR(50);
  p_CodeType_f91524d0d02b VARCHAR(50);
  p_DefaultInView_f91524d0d02b BOOLEAN;
  p_ViewCellTemplate_f91524d0d02b TEXT;
  p_DefaultColumnWidth_f91524d0d02b INTEGER;
  p_AllowUpdateAPI_f91524d0d02b BOOLEAN;
  p_AllowUpdateInView_f91524d0d02b BOOLEAN;
  p_IncludeInUserSearchAPI_f91524d0d02b BOOLEAN;
  p_FullTextSearchEnabled_f91524d0d02b BOOLEAN;
  p_UserSearchParamFormatAPI_f91524d0d02b VARCHAR(500);
  p_IncludeInGeneratedForm_f91524d0d02b BOOLEAN;
  p_GeneratedFormSection_f91524d0d02b VARCHAR(10);
  p_IsNameField_f91524d0d02b BOOLEAN;
  p_RelatedEntityID_f91524d0d02b UUID;
  p_RelatedEntityFieldName_f91524d0d02b VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_f91524d0d02b BOOLEAN;
  p_RelatedEntityNameFieldMap_f91524d0d02b VARCHAR(255);
  p_RelatedEntityDisplayType_f91524d0d02b VARCHAR(20);
  p_EntityIDFieldName_f91524d0d02b VARCHAR(100);
  p_ScopeDefault_f91524d0d02b VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_f91524d0d02b BOOLEAN;
  p_ValuesToPackWithSchema_f91524d0d02b VARCHAR(10);
  p_Status_f91524d0d02b VARCHAR(25);
  p_AutoUpdateIsNameField_f91524d0d02b BOOLEAN;
  p_AutoUpdateDefaultInView_f91524d0d02b BOOLEAN;
  p_AutoUpdateCategory_f91524d0d02b BOOLEAN;
  p_AutoUpdateDisplayName_f91524d0d02b BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_f91524d0d02b BOOLEAN;
  p_Encrypt_f91524d0d02b BOOLEAN;
  p_EncryptionKeyID_f91524d0d02b UUID;
  p_AllowDecryptInAPI_f91524d0d02b BOOLEAN;
  p_SendEncryptedValue_f91524d0d02b BOOLEAN;
  p_IsSoftPrimaryKey_f91524d0d02b BOOLEAN;
  p_IsSoftForeignKey_f91524d0d02b BOOLEAN;
  p_RelatedEntityJoinFields_f91524d0d02b TEXT;
  p_JSONType_f91524d0d02b VARCHAR(255);
  p_JSONTypeIsArray_f91524d0d02b BOOLEAN;
  p_JSONTypeDefinition_f91524d0d02b TEXT;
  p_UserSearchPredicateAPI_f91524d0d02b VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_f91524d0d02b BOOLEAN;
  p_AutoUpdateFullTextSearch_f91524d0d02b BOOLEAN;
  p_AutoUpdateExtendedType_f91524d0d02b BOOLEAN;
  p_IsComputed_f91524d0d02b BOOLEAN;
  p_EmbeddedRecord_f91524d0d02b TEXT;
  p_Configuration_f91524d0d02b TEXT;
  p_ID_f91524d0d02b UUID;
BEGIN
  p_DisplayName_f91524d0d02b := 'Creating Record ID';
  p_Description_f91524d0d02b := 'Polymorphic reference part 2: the creating records id. Soft by nature — it points at a record owned by an app this repo has no knowledge of. Set together with CreatingEntityID or not at all.';
  p_AutoUpdateDescription_f91524d0d02b := TRUE;
  p_IsPrimaryKey_f91524d0d02b := FALSE;
  p_IsUnique_f91524d0d02b := FALSE;
  p_Category_f91524d0d02b := 'Provenance';
  p_ValueListType_f91524d0d02b := 'None';
  p_DefaultInView_f91524d0d02b := FALSE;
  p_DefaultColumnWidth_f91524d0d02b := 150;
  p_AllowUpdateAPI_f91524d0d02b := TRUE;
  p_AllowUpdateInView_f91524d0d02b := TRUE;
  p_IncludeInUserSearchAPI_f91524d0d02b := FALSE;
  p_FullTextSearchEnabled_f91524d0d02b := FALSE;
  p_IncludeInGeneratedForm_f91524d0d02b := TRUE;
  p_GeneratedFormSection_f91524d0d02b := 'Category';
  p_IsNameField_f91524d0d02b := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_f91524d0d02b := FALSE;
  p_RelatedEntityDisplayType_f91524d0d02b := 'Search';
  p_EntityIDFieldName_f91524d0d02b := 'CreatingEntityID';
  p_AutoUpdateRelatedEntityInfo_f91524d0d02b := TRUE;
  p_ValuesToPackWithSchema_f91524d0d02b := 'Auto';
  p_Status_f91524d0d02b := 'Active';
  p_AutoUpdateIsNameField_f91524d0d02b := TRUE;
  p_AutoUpdateDefaultInView_f91524d0d02b := TRUE;
  p_AutoUpdateCategory_f91524d0d02b := TRUE;
  p_AutoUpdateDisplayName_f91524d0d02b := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_f91524d0d02b := TRUE;
  p_Encrypt_f91524d0d02b := FALSE;
  p_AllowDecryptInAPI_f91524d0d02b := FALSE;
  p_SendEncryptedValue_f91524d0d02b := FALSE;
  p_IsSoftPrimaryKey_f91524d0d02b := FALSE;
  p_IsSoftForeignKey_f91524d0d02b := FALSE;
  p_JSONTypeIsArray_f91524d0d02b := FALSE;
  p_UserSearchPredicateAPI_f91524d0d02b := 'Contains';
  p_AutoUpdateUserSearchPredicate_f91524d0d02b := TRUE;
  p_AutoUpdateFullTextSearch_f91524d0d02b := TRUE;
  p_AutoUpdateExtendedType_f91524d0d02b := TRUE;
  p_IsComputed_f91524d0d02b := FALSE;
  p_ID_f91524d0d02b := '611650F5-BFC3-4809-B9B1-80AC9979B450';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '${mjSchema}' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM "${mjSchema}"."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_f91524d0d02b,
    'Description', p_Description_f91524d0d02b,
    'AutoUpdateDescription', p_AutoUpdateDescription_f91524d0d02b,
    'IsPrimaryKey', p_IsPrimaryKey_f91524d0d02b,
    'IsUnique', p_IsUnique_f91524d0d02b,
    'Category', p_Category_f91524d0d02b,
    'ValueListType', p_ValueListType_f91524d0d02b,
    'ExtendedType', p_ExtendedType_f91524d0d02b,
    'CodeType', p_CodeType_f91524d0d02b,
    'DefaultInView', p_DefaultInView_f91524d0d02b,
    'ViewCellTemplate', p_ViewCellTemplate_f91524d0d02b,
    'DefaultColumnWidth', p_DefaultColumnWidth_f91524d0d02b,
    'AllowUpdateAPI', p_AllowUpdateAPI_f91524d0d02b,
    'AllowUpdateInView', p_AllowUpdateInView_f91524d0d02b,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_f91524d0d02b,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_f91524d0d02b,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_f91524d0d02b,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_f91524d0d02b,
    'GeneratedFormSection', p_GeneratedFormSection_f91524d0d02b,
    'IsNameField', p_IsNameField_f91524d0d02b,
    'RelatedEntityID', p_RelatedEntityID_f91524d0d02b,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_f91524d0d02b,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_f91524d0d02b,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_f91524d0d02b,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_f91524d0d02b,
    'EntityIDFieldName', p_EntityIDFieldName_f91524d0d02b,
    'ScopeDefault', p_ScopeDefault_f91524d0d02b,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_f91524d0d02b,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_f91524d0d02b,
    'Status', p_Status_f91524d0d02b,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_f91524d0d02b,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_f91524d0d02b,
    'AutoUpdateCategory', p_AutoUpdateCategory_f91524d0d02b,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_f91524d0d02b,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_f91524d0d02b,
    'Encrypt', p_Encrypt_f91524d0d02b,
    'EncryptionKeyID', p_EncryptionKeyID_f91524d0d02b,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_f91524d0d02b,
    'SendEncryptedValue', p_SendEncryptedValue_f91524d0d02b,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_f91524d0d02b,
    'IsSoftForeignKey', p_IsSoftForeignKey_f91524d0d02b,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_f91524d0d02b,
    'JSONType', p_JSONType_f91524d0d02b,
    'JSONTypeIsArray', p_JSONTypeIsArray_f91524d0d02b,
    'JSONTypeDefinition', p_JSONTypeDefinition_f91524d0d02b,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_f91524d0d02b,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_f91524d0d02b,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_f91524d0d02b,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_f91524d0d02b,
    'IsComputed', p_IsComputed_f91524d0d02b
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_f91524d0d02b,
    'Configuration', p_Configuration_f91524d0d02b,
    'ID', p_ID_f91524d0d02b
  ));
  ELSE
    PERFORM "${mjSchema}"."spUpdateEntityField"(p_DisplayName := p_DisplayName_f91524d0d02b, p_Description := p_Description_f91524d0d02b, p_AutoUpdateDescription := p_AutoUpdateDescription_f91524d0d02b, p_IsPrimaryKey := p_IsPrimaryKey_f91524d0d02b, p_IsUnique := p_IsUnique_f91524d0d02b, p_Category := p_Category_f91524d0d02b, p_ValueListType := p_ValueListType_f91524d0d02b, p_ExtendedType := p_ExtendedType_f91524d0d02b, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_f91524d0d02b, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_f91524d0d02b, p_ViewCellTemplate := p_ViewCellTemplate_f91524d0d02b, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_f91524d0d02b, p_AllowUpdateAPI := p_AllowUpdateAPI_f91524d0d02b, p_AllowUpdateInView := p_AllowUpdateInView_f91524d0d02b, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_f91524d0d02b, p_FullTextSearchEnabled := p_FullTextSearchEnabled_f91524d0d02b, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_f91524d0d02b, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_f91524d0d02b, p_GeneratedFormSection := p_GeneratedFormSection_f91524d0d02b, p_IsNameField := p_IsNameField_f91524d0d02b, p_RelatedEntityID := p_RelatedEntityID_f91524d0d02b, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_f91524d0d02b, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_f91524d0d02b, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_f91524d0d02b, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_f91524d0d02b, p_EntityIDFieldName := p_EntityIDFieldName_f91524d0d02b, p_ScopeDefault := p_ScopeDefault_f91524d0d02b, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_f91524d0d02b, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_f91524d0d02b, p_Status := p_Status_f91524d0d02b, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_f91524d0d02b, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_f91524d0d02b, p_AutoUpdateCategory := p_AutoUpdateCategory_f91524d0d02b, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_f91524d0d02b, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_f91524d0d02b, p_Encrypt := p_Encrypt_f91524d0d02b, p_EncryptionKeyID := p_EncryptionKeyID_f91524d0d02b, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_f91524d0d02b, p_SendEncryptedValue := p_SendEncryptedValue_f91524d0d02b, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_f91524d0d02b, p_IsSoftForeignKey := p_IsSoftForeignKey_f91524d0d02b, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_f91524d0d02b, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_f91524d0d02b, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_f91524d0d02b, p_JSONTypeDefinition := p_JSONTypeDefinition_f91524d0d02b, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_f91524d0d02b, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_f91524d0d02b, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_f91524d0d02b, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_f91524d0d02b, p_IsComputed := p_IsComputed_f91524d0d02b, p_EmbeddedRecord := p_EmbeddedRecord_f91524d0d02b, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_f91524d0d02b, p_Configuration_Clear := TRUE, p_ID := p_ID_f91524d0d02b);
  END IF;
END $mj$;
