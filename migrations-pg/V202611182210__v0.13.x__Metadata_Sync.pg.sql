-- =============================================================================================
-- PostgreSQL counterpart of V202611182210__v0.13.x__Metadata_Sync.sql
-- =============================================================================================
-- Same records, same values as the T-SQL file; see its header for what ships and why.
--
-- HOW IT WAS MADE: `mj sql-convert --from tsql --to postgres` (MJ CLI 6.2.1) on each block of the
-- push log, one block per run (the converter merges a multi-block log into one). Each block's
-- guard is then widened to match the T-SQL file (ID, or the natural key) and its update branch
-- removed, so every record is create-only. The action's category is looked up by its own ID
-- first, then by name, as in the T-SQL file. String values are copied verbatim from the T-SQL
-- file. Core references use ${mjSchema}.
-- =============================================================================================

-- Save MJ: Actions (core SP call only)
DO $mj$
DECLARE
  p_ID_b6467477b45d UUID;
  p_CategoryID_b6467477b45d UUID;
  p_Name_b6467477b45d VARCHAR(425);
  p_Description_b6467477b45d TEXT;
  p_Type_b6467477b45d VARCHAR(20);
  p_UserPrompt_b6467477b45d TEXT;
  p_UserComments_b6467477b45d TEXT;
  p_Code_b6467477b45d TEXT;
  p_CodeComments_b6467477b45d TEXT;
  p_CodeApprovalStatus_b6467477b45d VARCHAR(20);
  p_CodeApprovalComments_b6467477b45d TEXT;
  p_CodeApprovedByUserID_b6467477b45d UUID;
  p_CodeApprovedAt_b6467477b45d TIMESTAMPTZ;
  p_CodeLocked_b6467477b45d BOOLEAN;
  p_ForceCodeGeneration_b6467477b45d BOOLEAN;
  p_RetentionPeriod_b6467477b45d INTEGER;
  p_Status_b6467477b45d VARCHAR(20);
  p_DriverClass_b6467477b45d VARCHAR(255);
  p_ParentID_b6467477b45d UUID;
  p_IconClass_b6467477b45d VARCHAR(100);
  p_DefaultCompactPromptID_b6467477b45d UUID;
  p_Config_b6467477b45d TEXT;
  p_RuntimeActionConfiguration_b6467477b45d TEXT;
  p_MaxExecutionTimeMS_b6467477b45d INTEGER;
  p_CreatedByAgentID_b6467477b45d UUID;
BEGIN
  p_ID_b6467477b45d := 'B8818305-AB67-4BDC-BDA3-7539F009DB1C';
  -- The Contracts action category this app ships (v0.12 seed), found by name with its own ID first:
  -- a database can hold more than one category named Contracts.
  p_CategoryID_b6467477b45d := COALESCE((SELECT "ID" FROM "${mjSchema}"."ActionCategory" WHERE LOWER("Name") = LOWER('Contracts') ORDER BY CASE WHEN "ID" = 'F7307A18-6C08-4EF6-97A1-D4F568868D36' THEN 0 ELSE 1 END LIMIT 1), 'F7307A18-6C08-4EF6-97A1-D4F568868D36');
  p_Name_b6467477b45d := 'Sweep Contract Renewal Terms';
  p_Description_b6467477b45d := 'Copy every linked contract''s annual increase (when stated) and carry-discount flag to the subscriptions its orders created. Subscriptions already carrying the terms are left alone.';
  p_Type_b6467477b45d := 'Custom';
  p_UserPrompt_b6467477b45d := 'Copy contract renewal terms to the subscriptions of their linked orders.';
  p_CodeApprovalStatus_b6467477b45d := 'Approved';
  p_CodeLocked_b6467477b45d := FALSE;
  p_ForceCodeGeneration_b6467477b45d := FALSE;
  p_Status_b6467477b45d := 'Active';
  p_DriverClass_b6467477b45d := 'Contracts.SweepRenewalTerms';
  p_IconClass_b6467477b45d := 'fa-solid fa-arrows-rotate';
  IF NOT EXISTS (SELECT 1 FROM "${mjSchema}"."Action"
                 WHERE "ID" = p_ID_b6467477b45d
                    OR ("Name" = p_Name_b6467477b45d AND "CategoryID" = p_CategoryID_b6467477b45d)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateAction'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM "${mjSchema}"."spCreateAction"(p_data := jsonb_build_object(
    'ID', p_ID_b6467477b45d,
    'CategoryID', p_CategoryID_b6467477b45d,
    'Name', p_Name_b6467477b45d,
    'Description', p_Description_b6467477b45d,
    'Type', p_Type_b6467477b45d,
    'UserPrompt', p_UserPrompt_b6467477b45d,
    'UserComments', p_UserComments_b6467477b45d,
    'Code', p_Code_b6467477b45d,
    'CodeComments', p_CodeComments_b6467477b45d,
    'CodeApprovalStatus', p_CodeApprovalStatus_b6467477b45d,
    'CodeApprovalComments', p_CodeApprovalComments_b6467477b45d,
    'CodeApprovedByUserID', p_CodeApprovedByUserID_b6467477b45d,
    'CodeApprovedAt', p_CodeApprovedAt_b6467477b45d,
    'CodeLocked', p_CodeLocked_b6467477b45d,
    'ForceCodeGeneration', p_ForceCodeGeneration_b6467477b45d,
    'RetentionPeriod', p_RetentionPeriod_b6467477b45d,
    'Status', p_Status_b6467477b45d,
    'DriverClass', p_DriverClass_b6467477b45d,
    'ParentID', p_ParentID_b6467477b45d,
    'IconClass', p_IconClass_b6467477b45d,
    'DefaultCompactPromptID', p_DefaultCompactPromptID_b6467477b45d,
    'Config', p_Config_b6467477b45d,
    'RuntimeActionConfiguration', p_RuntimeActionConfiguration_b6467477b45d,
    'MaxExecutionTimeMS', p_MaxExecutionTimeMS_b6467477b45d,
    'CreatedByAgentID', p_CreatedByAgentID_b6467477b45d
  ));
    ELSE
      PERFORM "${mjSchema}"."spCreateAction"(p_ID := p_ID_b6467477b45d, p_CategoryID := p_CategoryID_b6467477b45d, p_Name := p_Name_b6467477b45d, p_Description := p_Description_b6467477b45d, p_Type := p_Type_b6467477b45d, p_UserPrompt := p_UserPrompt_b6467477b45d, p_UserComments := p_UserComments_b6467477b45d, p_UserComments_Clear := TRUE, p_Code := p_Code_b6467477b45d, p_Code_Clear := TRUE, p_CodeComments := p_CodeComments_b6467477b45d, p_CodeComments_Clear := TRUE, p_CodeApprovalStatus := p_CodeApprovalStatus_b6467477b45d, p_CodeApprovalComments := p_CodeApprovalComments_b6467477b45d, p_CodeApprovalComments_Clear := TRUE, p_CodeApprovedByUserID := p_CodeApprovedByUserID_b6467477b45d, p_CodeApprovedByUserID_Clear := TRUE, p_CodeApprovedAt := p_CodeApprovedAt_b6467477b45d, p_CodeApprovedAt_Clear := TRUE, p_CodeLocked := p_CodeLocked_b6467477b45d, p_ForceCodeGeneration := p_ForceCodeGeneration_b6467477b45d, p_RetentionPeriod := p_RetentionPeriod_b6467477b45d, p_RetentionPeriod_Clear := TRUE, p_Status := p_Status_b6467477b45d, p_DriverClass := p_DriverClass_b6467477b45d, p_ParentID := p_ParentID_b6467477b45d, p_ParentID_Clear := TRUE, p_IconClass := p_IconClass_b6467477b45d, p_DefaultCompactPromptID := p_DefaultCompactPromptID_b6467477b45d, p_DefaultCompactPromptID_Clear := TRUE, p_Config := p_Config_b6467477b45d, p_Config_Clear := TRUE, p_RuntimeActionConfiguration := p_RuntimeActionConfiguration_b6467477b45d, p_RuntimeActionConfiguration_Clear := TRUE, p_MaxExecutionTimeMS := p_MaxExecutionTimeMS_b6467477b45d, p_MaxExecutionTimeMS_Clear := TRUE, p_CreatedByAgentID := p_CreatedByAgentID_b6467477b45d, p_CreatedByAgentID_Clear := TRUE);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Scheduled Jobs (core SP call only)
DO $mj$
DECLARE
  p_ID_ce459cd07fdf UUID;
  p_JobTypeID_ce459cd07fdf UUID;
  p_Name_ce459cd07fdf VARCHAR(200);
  p_Description_ce459cd07fdf TEXT;
  p_CronExpression_ce459cd07fdf VARCHAR(120);
  p_Timezone_ce459cd07fdf VARCHAR(64);
  p_StartAt_ce459cd07fdf TIMESTAMPTZ;
  p_EndAt_ce459cd07fdf TIMESTAMPTZ;
  p_Status_ce459cd07fdf VARCHAR(20);
  p_Configuration_ce459cd07fdf TEXT;
  p_OwnerUserID_ce459cd07fdf UUID;
  p_LastRunAt_ce459cd07fdf TIMESTAMPTZ;
  p_NextRunAt_ce459cd07fdf TIMESTAMPTZ;
  p_RunCount_ce459cd07fdf INTEGER;
  p_SuccessCount_ce459cd07fdf INTEGER;
  p_FailureCount_ce459cd07fdf INTEGER;
  p_NotifyOnSuccess_ce459cd07fdf BOOLEAN;
  p_NotifyOnFailure_ce459cd07fdf BOOLEAN;
  p_NotifyUserID_ce459cd07fdf UUID;
  p_NotifyViaEmail_ce459cd07fdf BOOLEAN;
  p_NotifyViaInApp_ce459cd07fdf BOOLEAN;
  p_LockToken_ce459cd07fdf UUID;
  p_LockedAt_ce459cd07fdf TIMESTAMPTZ;
  p_LockedByInstance_ce459cd07fdf VARCHAR(255);
  p_ExpectedCompletionAt_ce459cd07fdf TIMESTAMPTZ;
  p_ConcurrencyMode_ce459cd07fdf VARCHAR(20);
  p_RunImmediatelyIfNeverRun_ce459cd07fdf BOOLEAN;
  p_MaxRuntimeMinutes_ce459cd07fdf INTEGER;
  p_MissedRunPolicy_ce459cd07fdf VARCHAR(20);
BEGIN
  p_ID_ce459cd07fdf := '00FCEB90-D230-4DC5-A992-6356988224F6';
  p_JobTypeID_ce459cd07fdf := '3B94DD43-E961-4D85-B7F4-B6783D748766';
  p_Name_ce459cd07fdf := 'Contracts — Copy Renewal Terms to Subscriptions (daily)';
  p_Description_ce459cd07fdf := 'Copies each linked contract''s annual increase and carry-discount flag to the subscriptions its orders created, including subscriptions created after the link.';
  p_CronExpression_ce459cd07fdf := '0 30 1 * * *';
  p_Timezone_ce459cd07fdf := 'UTC';
  p_Status_ce459cd07fdf := 'Active';
  p_Configuration_ce459cd07fdf := '{"ActionID":"B8818305-AB67-4BDC-BDA3-7539F009DB1C","Params":[]}';
  p_RunCount_ce459cd07fdf := 0;
  p_SuccessCount_ce459cd07fdf := 0;
  p_FailureCount_ce459cd07fdf := 0;
  p_NotifyOnSuccess_ce459cd07fdf := FALSE;
  p_NotifyOnFailure_ce459cd07fdf := FALSE;
  p_NotifyViaEmail_ce459cd07fdf := FALSE;
  p_NotifyViaInApp_ce459cd07fdf := FALSE;
  p_ConcurrencyMode_ce459cd07fdf := 'Skip';
  p_RunImmediatelyIfNeverRun_ce459cd07fdf := FALSE;
  p_MaxRuntimeMinutes_ce459cd07fdf := 15;
  p_MissedRunPolicy_ce459cd07fdf := 'RunOnce';
  IF NOT EXISTS (SELECT 1 FROM "${mjSchema}"."ScheduledJob"
                 WHERE "ID" = p_ID_ce459cd07fdf
                    OR ("Name" = p_Name_ce459cd07fdf)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateScheduledJob'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM "${mjSchema}"."spCreateScheduledJob"(p_data := jsonb_build_object(
    'ID', p_ID_ce459cd07fdf,
    'JobTypeID', p_JobTypeID_ce459cd07fdf,
    'Name', p_Name_ce459cd07fdf,
    'Description', p_Description_ce459cd07fdf,
    'CronExpression', p_CronExpression_ce459cd07fdf,
    'Timezone', p_Timezone_ce459cd07fdf,
    'StartAt', p_StartAt_ce459cd07fdf,
    'EndAt', p_EndAt_ce459cd07fdf,
    'Status', p_Status_ce459cd07fdf,
    'Configuration', p_Configuration_ce459cd07fdf,
    'OwnerUserID', p_OwnerUserID_ce459cd07fdf,
    'LastRunAt', p_LastRunAt_ce459cd07fdf,
    'NextRunAt', p_NextRunAt_ce459cd07fdf,
    'RunCount', p_RunCount_ce459cd07fdf,
    'SuccessCount', p_SuccessCount_ce459cd07fdf,
    'FailureCount', p_FailureCount_ce459cd07fdf,
    'NotifyOnSuccess', p_NotifyOnSuccess_ce459cd07fdf,
    'NotifyOnFailure', p_NotifyOnFailure_ce459cd07fdf,
    'NotifyUserID', p_NotifyUserID_ce459cd07fdf,
    'NotifyViaEmail', p_NotifyViaEmail_ce459cd07fdf,
    'NotifyViaInApp', p_NotifyViaInApp_ce459cd07fdf,
    'LockToken', p_LockToken_ce459cd07fdf,
    'LockedAt', p_LockedAt_ce459cd07fdf,
    'LockedByInstance', p_LockedByInstance_ce459cd07fdf,
    'ExpectedCompletionAt', p_ExpectedCompletionAt_ce459cd07fdf,
    'ConcurrencyMode', p_ConcurrencyMode_ce459cd07fdf,
    'RunImmediatelyIfNeverRun', p_RunImmediatelyIfNeverRun_ce459cd07fdf,
    'MaxRuntimeMinutes', p_MaxRuntimeMinutes_ce459cd07fdf,
    'MissedRunPolicy', p_MissedRunPolicy_ce459cd07fdf
  ));
    ELSE
      PERFORM "${mjSchema}"."spCreateScheduledJob"(p_ID := p_ID_ce459cd07fdf, p_JobTypeID := p_JobTypeID_ce459cd07fdf, p_Name := p_Name_ce459cd07fdf, p_Description := p_Description_ce459cd07fdf, p_CronExpression := p_CronExpression_ce459cd07fdf, p_Timezone := p_Timezone_ce459cd07fdf, p_StartAt := p_StartAt_ce459cd07fdf, p_StartAt_Clear := TRUE, p_EndAt := p_EndAt_ce459cd07fdf, p_EndAt_Clear := TRUE, p_Status := p_Status_ce459cd07fdf, p_Configuration := p_Configuration_ce459cd07fdf, p_OwnerUserID := p_OwnerUserID_ce459cd07fdf, p_OwnerUserID_Clear := TRUE, p_LastRunAt := p_LastRunAt_ce459cd07fdf, p_LastRunAt_Clear := TRUE, p_NextRunAt := p_NextRunAt_ce459cd07fdf, p_NextRunAt_Clear := TRUE, p_RunCount := p_RunCount_ce459cd07fdf, p_SuccessCount := p_SuccessCount_ce459cd07fdf, p_FailureCount := p_FailureCount_ce459cd07fdf, p_NotifyOnSuccess := p_NotifyOnSuccess_ce459cd07fdf, p_NotifyOnFailure := p_NotifyOnFailure_ce459cd07fdf, p_NotifyUserID := p_NotifyUserID_ce459cd07fdf, p_NotifyUserID_Clear := TRUE, p_NotifyViaEmail := p_NotifyViaEmail_ce459cd07fdf, p_NotifyViaInApp := p_NotifyViaInApp_ce459cd07fdf, p_LockToken := p_LockToken_ce459cd07fdf, p_LockToken_Clear := TRUE, p_LockedAt := p_LockedAt_ce459cd07fdf, p_LockedAt_Clear := TRUE, p_LockedByInstance := p_LockedByInstance_ce459cd07fdf, p_LockedByInstance_Clear := TRUE, p_ExpectedCompletionAt := p_ExpectedCompletionAt_ce459cd07fdf, p_ExpectedCompletionAt_Clear := TRUE, p_ConcurrencyMode := p_ConcurrencyMode_ce459cd07fdf, p_RunImmediatelyIfNeverRun := p_RunImmediatelyIfNeverRun_ce459cd07fdf, p_MaxRuntimeMinutes := p_MaxRuntimeMinutes_ce459cd07fdf, p_MissedRunPolicy := p_MissedRunPolicy_ce459cd07fdf);
    END IF;
  END IF;
END $mj$;
