-- =============================================================================================
-- PostgreSQL counterpart of V202610200101__v0.8.x__Metadata_Sync.sql -- BizApps Contracts v0.8.x,
-- second Metadata_Sync
-- =============================================================================================
-- Same 2 records, same values, same order as the T-SQL file; see its header for what ships and
-- why (Statement of Work TemplateRequired = 0; ContractType.Code ExtendedType and CodeType
-- cleared).
--
-- HOW IT WAS MADE: as V202610092210.pg.sql.
--   * `mj sql-convert --from tsql --to postgres` (MJ CLI 6.1.6) on the T-SQL file, with the
--     schema placeholders written as `__mj` and `__mj_bizappscontracts` first, because the
--     converter skips every batch whose procedure call names the schema by placeholder. Each
--     record is a DO block that calls the procedure in whichever signature the host has (jsonb
--     or named parameters).
--   * Every value is taken verbatim from the T-SQL SET statements (strings unchanged, BIT 1/0 as
--     TRUE/FALSE), because the converter drops BIT and number assignments.
--   * Schemas are written `__mj` and `__mj_bizappscontracts`, as in this app's PostgreSQL
--     baseline.
-- =============================================================================================

SET standard_conforming_strings = on;

-- Save MJ: Entity Fields (core SP call only)
DO $mj$
DECLARE
  p_DisplayName_93d720b28fc6 VARCHAR(255);
  p_Description_93d720b28fc6 TEXT;
  p_AutoUpdateDescription_93d720b28fc6 BOOLEAN;
  p_IsPrimaryKey_93d720b28fc6 BOOLEAN;
  p_IsUnique_93d720b28fc6 BOOLEAN;
  p_Category_93d720b28fc6 VARCHAR(255);
  p_ValueListType_93d720b28fc6 VARCHAR(20);
  p_ExtendedType_93d720b28fc6 VARCHAR(50);
  p_CodeType_93d720b28fc6 VARCHAR(50);
  p_DefaultInView_93d720b28fc6 BOOLEAN;
  p_ViewCellTemplate_93d720b28fc6 TEXT;
  p_DefaultColumnWidth_93d720b28fc6 INTEGER;
  p_AllowUpdateAPI_93d720b28fc6 BOOLEAN;
  p_AllowUpdateInView_93d720b28fc6 BOOLEAN;
  p_IncludeInUserSearchAPI_93d720b28fc6 BOOLEAN;
  p_FullTextSearchEnabled_93d720b28fc6 BOOLEAN;
  p_UserSearchParamFormatAPI_93d720b28fc6 VARCHAR(500);
  p_IncludeInGeneratedForm_93d720b28fc6 BOOLEAN;
  p_GeneratedFormSection_93d720b28fc6 VARCHAR(10);
  p_IsNameField_93d720b28fc6 BOOLEAN;
  p_RelatedEntityID_93d720b28fc6 UUID;
  p_RelatedEntityFieldName_93d720b28fc6 VARCHAR(255);
  p_IncludeRelatedEntityNameFieldInBaseView_93d720b28fc6 BOOLEAN;
  p_RelatedEntityNameFieldMap_93d720b28fc6 VARCHAR(255);
  p_RelatedEntityDisplayType_93d720b28fc6 VARCHAR(20);
  p_EntityIDFieldName_93d720b28fc6 VARCHAR(100);
  p_ScopeDefault_93d720b28fc6 VARCHAR(100);
  p_AutoUpdateRelatedEntityInfo_93d720b28fc6 BOOLEAN;
  p_ValuesToPackWithSchema_93d720b28fc6 VARCHAR(10);
  p_Status_93d720b28fc6 VARCHAR(25);
  p_AutoUpdateIsNameField_93d720b28fc6 BOOLEAN;
  p_AutoUpdateDefaultInView_93d720b28fc6 BOOLEAN;
  p_AutoUpdateCategory_93d720b28fc6 BOOLEAN;
  p_AutoUpdateDisplayName_93d720b28fc6 BOOLEAN;
  p_AutoUpdateIncludeInUserSearchAPI_93d720b28fc6 BOOLEAN;
  p_Encrypt_93d720b28fc6 BOOLEAN;
  p_EncryptionKeyID_93d720b28fc6 UUID;
  p_AllowDecryptInAPI_93d720b28fc6 BOOLEAN;
  p_SendEncryptedValue_93d720b28fc6 BOOLEAN;
  p_IsSoftPrimaryKey_93d720b28fc6 BOOLEAN;
  p_IsSoftForeignKey_93d720b28fc6 BOOLEAN;
  p_RelatedEntityJoinFields_93d720b28fc6 TEXT;
  p_JSONType_93d720b28fc6 VARCHAR(255);
  p_JSONTypeIsArray_93d720b28fc6 BOOLEAN;
  p_JSONTypeDefinition_93d720b28fc6 TEXT;
  p_UserSearchPredicateAPI_93d720b28fc6 VARCHAR(20);
  p_AutoUpdateUserSearchPredicate_93d720b28fc6 BOOLEAN;
  p_AutoUpdateFullTextSearch_93d720b28fc6 BOOLEAN;
  p_AutoUpdateExtendedType_93d720b28fc6 BOOLEAN;
  p_IsComputed_93d720b28fc6 BOOLEAN;
  p_EmbeddedRecord_93d720b28fc6 TEXT;
  p_Configuration_93d720b28fc6 TEXT;
  p_ID_93d720b28fc6 UUID;
BEGIN
  p_DisplayName_93d720b28fc6 := 'Code';
  p_Description_93d720b28fc6 := 'Stable machine code other apps and metadata use to find this type (for example ORDER_FORM). Unique. Unlike Name, it is not a label: renaming the type leaves the Code alone, and changing the Code breaks every caller that names it.';
  p_AutoUpdateDescription_93d720b28fc6 := TRUE;
  p_IsPrimaryKey_93d720b28fc6 := FALSE;
  p_IsUnique_93d720b28fc6 := TRUE;
  p_Category_93d720b28fc6 := 'Contract Type Details';
  p_ValueListType_93d720b28fc6 := 'None';
  p_DefaultInView_93d720b28fc6 := TRUE;
  p_DefaultColumnWidth_93d720b28fc6 := 150;
  p_AllowUpdateAPI_93d720b28fc6 := TRUE;
  p_AllowUpdateInView_93d720b28fc6 := TRUE;
  p_IncludeInUserSearchAPI_93d720b28fc6 := FALSE;
  p_FullTextSearchEnabled_93d720b28fc6 := FALSE;
  p_IncludeInGeneratedForm_93d720b28fc6 := TRUE;
  p_GeneratedFormSection_93d720b28fc6 := 'Category';
  p_IsNameField_93d720b28fc6 := FALSE;
  p_IncludeRelatedEntityNameFieldInBaseView_93d720b28fc6 := FALSE;
  p_RelatedEntityDisplayType_93d720b28fc6 := 'Search';
  p_AutoUpdateRelatedEntityInfo_93d720b28fc6 := TRUE;
  p_ValuesToPackWithSchema_93d720b28fc6 := 'Auto';
  p_Status_93d720b28fc6 := 'Active';
  p_AutoUpdateIsNameField_93d720b28fc6 := TRUE;
  p_AutoUpdateDefaultInView_93d720b28fc6 := TRUE;
  p_AutoUpdateCategory_93d720b28fc6 := TRUE;
  p_AutoUpdateDisplayName_93d720b28fc6 := TRUE;
  p_AutoUpdateIncludeInUserSearchAPI_93d720b28fc6 := TRUE;
  p_Encrypt_93d720b28fc6 := FALSE;
  p_AllowDecryptInAPI_93d720b28fc6 := FALSE;
  p_SendEncryptedValue_93d720b28fc6 := FALSE;
  p_IsSoftPrimaryKey_93d720b28fc6 := FALSE;
  p_IsSoftForeignKey_93d720b28fc6 := FALSE;
  p_JSONTypeIsArray_93d720b28fc6 := FALSE;
  p_UserSearchPredicateAPI_93d720b28fc6 := 'Contains';
  p_AutoUpdateUserSearchPredicate_93d720b28fc6 := TRUE;
  p_AutoUpdateFullTextSearch_93d720b28fc6 := TRUE;
  p_AutoUpdateExtendedType_93d720b28fc6 := TRUE;
  p_IsComputed_93d720b28fc6 := FALSE;
  p_ID_93d720b28fc6 := '46976B91-EF82-4D60-A6EC-BF645EC8D56F';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj' AND p.proname = 'spUpdateEntityField'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj."spUpdateEntityField"(p_data := jsonb_build_object(
    'DisplayName', p_DisplayName_93d720b28fc6,
    'Description', p_Description_93d720b28fc6,
    'AutoUpdateDescription', p_AutoUpdateDescription_93d720b28fc6,
    'IsPrimaryKey', p_IsPrimaryKey_93d720b28fc6,
    'IsUnique', p_IsUnique_93d720b28fc6,
    'Category', p_Category_93d720b28fc6,
    'ValueListType', p_ValueListType_93d720b28fc6,
    'ExtendedType', p_ExtendedType_93d720b28fc6,
    'CodeType', p_CodeType_93d720b28fc6,
    'DefaultInView', p_DefaultInView_93d720b28fc6,
    'ViewCellTemplate', p_ViewCellTemplate_93d720b28fc6,
    'DefaultColumnWidth', p_DefaultColumnWidth_93d720b28fc6,
    'AllowUpdateAPI', p_AllowUpdateAPI_93d720b28fc6,
    'AllowUpdateInView', p_AllowUpdateInView_93d720b28fc6,
    'IncludeInUserSearchAPI', p_IncludeInUserSearchAPI_93d720b28fc6,
    'FullTextSearchEnabled', p_FullTextSearchEnabled_93d720b28fc6,
    'UserSearchParamFormatAPI', p_UserSearchParamFormatAPI_93d720b28fc6,
    'IncludeInGeneratedForm', p_IncludeInGeneratedForm_93d720b28fc6,
    'GeneratedFormSection', p_GeneratedFormSection_93d720b28fc6,
    'IsNameField', p_IsNameField_93d720b28fc6,
    'RelatedEntityID', p_RelatedEntityID_93d720b28fc6,
    'RelatedEntityFieldName', p_RelatedEntityFieldName_93d720b28fc6,
    'IncludeRelatedEntityNameFieldInBaseView', p_IncludeRelatedEntityNameFieldInBaseView_93d720b28fc6,
    'RelatedEntityNameFieldMap', p_RelatedEntityNameFieldMap_93d720b28fc6,
    'RelatedEntityDisplayType', p_RelatedEntityDisplayType_93d720b28fc6,
    'EntityIDFieldName', p_EntityIDFieldName_93d720b28fc6,
    'ScopeDefault', p_ScopeDefault_93d720b28fc6,
    'AutoUpdateRelatedEntityInfo', p_AutoUpdateRelatedEntityInfo_93d720b28fc6,
    'ValuesToPackWithSchema', p_ValuesToPackWithSchema_93d720b28fc6,
    'Status', p_Status_93d720b28fc6,
    'AutoUpdateIsNameField', p_AutoUpdateIsNameField_93d720b28fc6,
    'AutoUpdateDefaultInView', p_AutoUpdateDefaultInView_93d720b28fc6,
    'AutoUpdateCategory', p_AutoUpdateCategory_93d720b28fc6,
    'AutoUpdateDisplayName', p_AutoUpdateDisplayName_93d720b28fc6,
    'AutoUpdateIncludeInUserSearchAPI', p_AutoUpdateIncludeInUserSearchAPI_93d720b28fc6,
    'Encrypt', p_Encrypt_93d720b28fc6,
    'EncryptionKeyID', p_EncryptionKeyID_93d720b28fc6,
    'AllowDecryptInAPI', p_AllowDecryptInAPI_93d720b28fc6,
    'SendEncryptedValue', p_SendEncryptedValue_93d720b28fc6,
    'IsSoftPrimaryKey', p_IsSoftPrimaryKey_93d720b28fc6,
    'IsSoftForeignKey', p_IsSoftForeignKey_93d720b28fc6,
    'RelatedEntityJoinFields', p_RelatedEntityJoinFields_93d720b28fc6,
    'JSONType', p_JSONType_93d720b28fc6,
    'JSONTypeIsArray', p_JSONTypeIsArray_93d720b28fc6,
    'JSONTypeDefinition', p_JSONTypeDefinition_93d720b28fc6,
    'UserSearchPredicateAPI', p_UserSearchPredicateAPI_93d720b28fc6,
    'AutoUpdateUserSearchPredicate', p_AutoUpdateUserSearchPredicate_93d720b28fc6,
    'AutoUpdateFullTextSearch', p_AutoUpdateFullTextSearch_93d720b28fc6,
    'AutoUpdateExtendedType', p_AutoUpdateExtendedType_93d720b28fc6,
    'IsComputed', p_IsComputed_93d720b28fc6
  ) ||
  jsonb_build_object(
    'EmbeddedRecord', p_EmbeddedRecord_93d720b28fc6,
    'Configuration', p_Configuration_93d720b28fc6,
    'ID', p_ID_93d720b28fc6
  ));
  ELSE
    PERFORM __mj."spUpdateEntityField"(p_DisplayName := p_DisplayName_93d720b28fc6, p_Description := p_Description_93d720b28fc6, p_AutoUpdateDescription := p_AutoUpdateDescription_93d720b28fc6, p_IsPrimaryKey := p_IsPrimaryKey_93d720b28fc6, p_IsUnique := p_IsUnique_93d720b28fc6, p_Category := p_Category_93d720b28fc6, p_ValueListType := p_ValueListType_93d720b28fc6, p_ExtendedType := p_ExtendedType_93d720b28fc6, p_ExtendedType_Clear := TRUE, p_CodeType := p_CodeType_93d720b28fc6, p_CodeType_Clear := TRUE, p_DefaultInView := p_DefaultInView_93d720b28fc6, p_ViewCellTemplate := p_ViewCellTemplate_93d720b28fc6, p_ViewCellTemplate_Clear := TRUE, p_DefaultColumnWidth := p_DefaultColumnWidth_93d720b28fc6, p_AllowUpdateAPI := p_AllowUpdateAPI_93d720b28fc6, p_AllowUpdateInView := p_AllowUpdateInView_93d720b28fc6, p_IncludeInUserSearchAPI := p_IncludeInUserSearchAPI_93d720b28fc6, p_FullTextSearchEnabled := p_FullTextSearchEnabled_93d720b28fc6, p_UserSearchParamFormatAPI := p_UserSearchParamFormatAPI_93d720b28fc6, p_UserSearchParamFormatAPI_Clear := TRUE, p_IncludeInGeneratedForm := p_IncludeInGeneratedForm_93d720b28fc6, p_GeneratedFormSection := p_GeneratedFormSection_93d720b28fc6, p_IsNameField := p_IsNameField_93d720b28fc6, p_RelatedEntityID := p_RelatedEntityID_93d720b28fc6, p_RelatedEntityID_Clear := TRUE, p_RelatedEntityFieldName := p_RelatedEntityFieldName_93d720b28fc6, p_RelatedEntityFieldName_Clear := TRUE, p_IncludeRelatedEntityNameFieldInBaseView := p_IncludeRelatedEntityNameFieldInBaseView_93d720b28fc6, p_RelatedEntityNameFieldMap := p_RelatedEntityNameFieldMap_93d720b28fc6, p_RelatedEntityNameFieldMap_Clear := TRUE, p_RelatedEntityDisplayType := p_RelatedEntityDisplayType_93d720b28fc6, p_EntityIDFieldName := p_EntityIDFieldName_93d720b28fc6, p_EntityIDFieldName_Clear := TRUE, p_ScopeDefault := p_ScopeDefault_93d720b28fc6, p_ScopeDefault_Clear := TRUE, p_AutoUpdateRelatedEntityInfo := p_AutoUpdateRelatedEntityInfo_93d720b28fc6, p_ValuesToPackWithSchema := p_ValuesToPackWithSchema_93d720b28fc6, p_Status := p_Status_93d720b28fc6, p_AutoUpdateIsNameField := p_AutoUpdateIsNameField_93d720b28fc6, p_AutoUpdateDefaultInView := p_AutoUpdateDefaultInView_93d720b28fc6, p_AutoUpdateCategory := p_AutoUpdateCategory_93d720b28fc6, p_AutoUpdateDisplayName := p_AutoUpdateDisplayName_93d720b28fc6, p_AutoUpdateIncludeInUserSearchAPI := p_AutoUpdateIncludeInUserSearchAPI_93d720b28fc6, p_Encrypt := p_Encrypt_93d720b28fc6, p_EncryptionKeyID := p_EncryptionKeyID_93d720b28fc6, p_EncryptionKeyID_Clear := TRUE, p_AllowDecryptInAPI := p_AllowDecryptInAPI_93d720b28fc6, p_SendEncryptedValue := p_SendEncryptedValue_93d720b28fc6, p_IsSoftPrimaryKey := p_IsSoftPrimaryKey_93d720b28fc6, p_IsSoftForeignKey := p_IsSoftForeignKey_93d720b28fc6, p_RelatedEntityJoinFields := p_RelatedEntityJoinFields_93d720b28fc6, p_RelatedEntityJoinFields_Clear := TRUE, p_JSONType := p_JSONType_93d720b28fc6, p_JSONType_Clear := TRUE, p_JSONTypeIsArray := p_JSONTypeIsArray_93d720b28fc6, p_JSONTypeDefinition := p_JSONTypeDefinition_93d720b28fc6, p_JSONTypeDefinition_Clear := TRUE, p_UserSearchPredicateAPI := p_UserSearchPredicateAPI_93d720b28fc6, p_AutoUpdateUserSearchPredicate := p_AutoUpdateUserSearchPredicate_93d720b28fc6, p_AutoUpdateFullTextSearch := p_AutoUpdateFullTextSearch_93d720b28fc6, p_AutoUpdateExtendedType := p_AutoUpdateExtendedType_93d720b28fc6, p_IsComputed := p_IsComputed_93d720b28fc6, p_EmbeddedRecord := p_EmbeddedRecord_93d720b28fc6, p_EmbeddedRecord_Clear := TRUE, p_Configuration := p_Configuration_93d720b28fc6, p_Configuration_Clear := TRUE, p_ID := p_ID_93d720b28fc6);
  END IF;
END $mj$;

-- Save MJ_BizApps_Contracts: Contract Types (core SP call only)
DO $mj$
DECLARE
  p_Name_cd5091c009a9 VARCHAR(100);
  p_Description_cd5091c009a9 TEXT;
  p_RequiresExecutedDocument_cd5091c009a9 BOOLEAN;
  p_Status_cd5091c009a9 VARCHAR(10);
  p_MustBeRoot_cd5091c009a9 BOOLEAN;
  p_MustBeChild_cd5091c009a9 BOOLEAN;
  p_TemplateRequired_cd5091c009a9 BOOLEAN;
  p_DefaultAutoRenew_cd5091c009a9 BOOLEAN;
  p_DefaultRenewalNoticeDays_cd5091c009a9 INTEGER;
  p_DefaultCancellationWindowDays_cd5091c009a9 INTEGER;
  p_DefaultAnnualIncreasePercent_cd5091c009a9 NUMERIC(7,4);
  p_Code_cd5091c009a9 VARCHAR(50);
  p_ID_cd5091c009a9 UUID;
BEGIN
  p_Name_cd5091c009a9 := 'Statement of Work';
  p_Description_cd5091c009a9 := 'Scoped services with a defined end. Ruled 2026-08-18: SOWs have standard language but no versioned template — so an SOW contract may have no ContractTemplateID, and that is not a gap to fill. Paper is still expected.';
  p_RequiresExecutedDocument_cd5091c009a9 := TRUE;
  p_Status_cd5091c009a9 := 'Active';
  p_MustBeRoot_cd5091c009a9 := TRUE;
  p_MustBeChild_cd5091c009a9 := FALSE;
  p_TemplateRequired_cd5091c009a9 := FALSE;
  p_Code_cd5091c009a9 := 'STATEMENT_OF_WORK';
  p_ID_cd5091c009a9 := '33333333-0000-4000-8000-000000001002';
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = '__mj_bizappscontracts' AND p.proname = 'spUpdateContractType'
       AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
  ) THEN
    PERFORM __mj_bizappscontracts."spUpdateContractType"(p_data := jsonb_build_object(
    'Name', p_Name_cd5091c009a9,
    'Description', p_Description_cd5091c009a9,
    'RequiresExecutedDocument', p_RequiresExecutedDocument_cd5091c009a9,
    'Status', p_Status_cd5091c009a9,
    'MustBeRoot', p_MustBeRoot_cd5091c009a9,
    'MustBeChild', p_MustBeChild_cd5091c009a9,
    'TemplateRequired', p_TemplateRequired_cd5091c009a9,
    'DefaultAutoRenew', p_DefaultAutoRenew_cd5091c009a9,
    'DefaultRenewalNoticeDays', p_DefaultRenewalNoticeDays_cd5091c009a9,
    'DefaultCancellationWindowDays', p_DefaultCancellationWindowDays_cd5091c009a9,
    'DefaultAnnualIncreasePercent', p_DefaultAnnualIncreasePercent_cd5091c009a9,
    'Code', p_Code_cd5091c009a9,
    'ID', p_ID_cd5091c009a9
  ));
  ELSE
    PERFORM __mj_bizappscontracts."spUpdateContractType"(p_Name := p_Name_cd5091c009a9, p_Description := p_Description_cd5091c009a9, p_RequiresExecutedDocument := p_RequiresExecutedDocument_cd5091c009a9, p_Status := p_Status_cd5091c009a9, p_MustBeRoot := p_MustBeRoot_cd5091c009a9, p_MustBeChild := p_MustBeChild_cd5091c009a9, p_TemplateRequired := p_TemplateRequired_cd5091c009a9, p_DefaultAutoRenew := p_DefaultAutoRenew_cd5091c009a9, p_DefaultAutoRenew_Clear := TRUE, p_DefaultRenewalNoticeDays := p_DefaultRenewalNoticeDays_cd5091c009a9, p_DefaultRenewalNoticeDays_Clear := TRUE, p_DefaultCancellationWindowDays := p_DefaultCancellationWindowDays_cd5091c009a9, p_DefaultCancellationWindowDays_Clear := TRUE, p_DefaultAnnualIncreasePercent := p_DefaultAnnualIncreasePercent_cd5091c009a9, p_DefaultAnnualIncreasePercent_Clear := TRUE, p_Code := p_Code_cd5091c009a9, p_ID := p_ID_cd5091c009a9);
  END IF;
END $mj$;
