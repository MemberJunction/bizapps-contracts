-- =============================================================================================
-- PostgreSQL counterpart of V202611101325__v0.12.x__Metadata_Sync.sql
-- =============================================================================================
-- Same records, same values as the T-SQL file; see its header for what ships and why.
--
-- HOW IT WAS MADE: `mj sql-convert --from tsql --to postgres` (MJ CLI 6.2.1) on each block of the
-- push log, one block per run (the converter merges a multi-block log into one). Each block's
-- guard is then widened to match the T-SQL file (ID, or the natural key) and its update branch
-- removed, so every record is create-only. Core references use ${mjSchema}.
-- =============================================================================================

-- Save MJ: Action Categories (core SP call only)
DO $mj$
DECLARE
  p_ID_0d0de5202a60 UUID;
  p_Name_0d0de5202a60 VARCHAR(255);
  p_Description_0d0de5202a60 TEXT;
  p_ParentID_0d0de5202a60 UUID;
  p_Status_0d0de5202a60 VARCHAR(20);
BEGIN
  p_ID_0d0de5202a60 := 'F7307A18-6C08-4EF6-97A1-D4F568868D36';
  p_Name_0d0de5202a60 := 'Contracts';
  p_Description_0d0de5202a60 := 'Actions belonging to the BizApps Contracts app.';
  p_Status_0d0de5202a60 := 'Active';
  IF NOT EXISTS (SELECT 1 FROM "${mjSchema}"."ActionCategory"
                 WHERE "ID" = p_ID_0d0de5202a60
                    OR ("Name" = p_Name_0d0de5202a60 AND "ParentID" IS NOT DISTINCT FROM p_ParentID_0d0de5202a60)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateActionCategory'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM "${mjSchema}"."spCreateActionCategory"(p_data := jsonb_build_object(
    'ID', p_ID_0d0de5202a60,
    'Name', p_Name_0d0de5202a60,
    'Description', p_Description_0d0de5202a60,
    'ParentID', p_ParentID_0d0de5202a60,
    'Status', p_Status_0d0de5202a60
  ));
    ELSE
      PERFORM "${mjSchema}"."spCreateActionCategory"(p_ID := p_ID_0d0de5202a60, p_Name := p_Name_0d0de5202a60, p_Description := p_Description_0d0de5202a60, p_ParentID := p_ParentID_0d0de5202a60, p_ParentID_Clear := TRUE, p_Status := p_Status_0d0de5202a60);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Actions (core SP call only)
DO $mj$
DECLARE
  p_ID_178304fa149d UUID;
  p_CategoryID_178304fa149d UUID;
  p_Name_178304fa149d VARCHAR(425);
  p_Description_178304fa149d TEXT;
  p_Type_178304fa149d VARCHAR(20);
  p_UserPrompt_178304fa149d TEXT;
  p_UserComments_178304fa149d TEXT;
  p_Code_178304fa149d TEXT;
  p_CodeComments_178304fa149d TEXT;
  p_CodeApprovalStatus_178304fa149d VARCHAR(20);
  p_CodeApprovalComments_178304fa149d TEXT;
  p_CodeApprovedByUserID_178304fa149d UUID;
  p_CodeApprovedAt_178304fa149d TIMESTAMPTZ;
  p_CodeLocked_178304fa149d BOOLEAN;
  p_ForceCodeGeneration_178304fa149d BOOLEAN;
  p_RetentionPeriod_178304fa149d INTEGER;
  p_Status_178304fa149d VARCHAR(20);
  p_DriverClass_178304fa149d VARCHAR(255);
  p_ParentID_178304fa149d UUID;
  p_IconClass_178304fa149d VARCHAR(100);
  p_DefaultCompactPromptID_178304fa149d UUID;
  p_Config_178304fa149d TEXT;
  p_RuntimeActionConfiguration_178304fa149d TEXT;
  p_MaxExecutionTimeMS_178304fa149d INTEGER;
  p_CreatedByAgentID_178304fa149d UUID;
BEGIN
  p_ID_178304fa149d := 'B830ACF2-62F7-44BC-85D4-17AEA0769FBE';
  p_CategoryID_178304fa149d := (
    SELECT
      "ID"
    FROM
      "${mjSchema}"."ActionCategory"
    WHERE
      LOWER("Name") = LOWER('Contracts')
  );
  p_Name_178304fa149d := 'Record Contract Renewal Outcomes';
  p_Description_178304fa149d := 'Record the renewal-risk label (NonRenewalOutcome) on every contract whose stored value no longer matches its dates, such as a contract whose end date has passed. Contracts already labelled correctly are left alone.';
  p_Type_178304fa149d := 'Custom';
  p_UserPrompt_178304fa149d := 'Record the renewal outcome on contracts that have concluded.';
  p_CodeApprovalStatus_178304fa149d := 'Approved';
  p_CodeLocked_178304fa149d := FALSE;
  p_ForceCodeGeneration_178304fa149d := FALSE;
  p_Status_178304fa149d := 'Active';
  p_DriverClass_178304fa149d := 'Contracts.RecordNonRenewalOutcomes';
  p_IconClass_178304fa149d := 'fa-solid fa-flag-checkered';
  IF NOT EXISTS (SELECT 1 FROM "${mjSchema}"."Action"
                 WHERE "ID" = p_ID_178304fa149d
                    OR ("Name" = p_Name_178304fa149d AND "CategoryID" = p_CategoryID_178304fa149d)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateAction'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM "${mjSchema}"."spCreateAction"(p_data := jsonb_build_object(
    'ID', p_ID_178304fa149d,
    'CategoryID', p_CategoryID_178304fa149d,
    'Name', p_Name_178304fa149d,
    'Description', p_Description_178304fa149d,
    'Type', p_Type_178304fa149d,
    'UserPrompt', p_UserPrompt_178304fa149d,
    'UserComments', p_UserComments_178304fa149d,
    'Code', p_Code_178304fa149d,
    'CodeComments', p_CodeComments_178304fa149d,
    'CodeApprovalStatus', p_CodeApprovalStatus_178304fa149d,
    'CodeApprovalComments', p_CodeApprovalComments_178304fa149d,
    'CodeApprovedByUserID', p_CodeApprovedByUserID_178304fa149d,
    'CodeApprovedAt', p_CodeApprovedAt_178304fa149d,
    'CodeLocked', p_CodeLocked_178304fa149d,
    'ForceCodeGeneration', p_ForceCodeGeneration_178304fa149d,
    'RetentionPeriod', p_RetentionPeriod_178304fa149d,
    'Status', p_Status_178304fa149d,
    'DriverClass', p_DriverClass_178304fa149d,
    'ParentID', p_ParentID_178304fa149d,
    'IconClass', p_IconClass_178304fa149d,
    'DefaultCompactPromptID', p_DefaultCompactPromptID_178304fa149d,
    'Config', p_Config_178304fa149d,
    'RuntimeActionConfiguration', p_RuntimeActionConfiguration_178304fa149d,
    'MaxExecutionTimeMS', p_MaxExecutionTimeMS_178304fa149d,
    'CreatedByAgentID', p_CreatedByAgentID_178304fa149d
  ));
    ELSE
      PERFORM "${mjSchema}"."spCreateAction"(p_ID := p_ID_178304fa149d, p_CategoryID := p_CategoryID_178304fa149d, p_Name := p_Name_178304fa149d, p_Description := p_Description_178304fa149d, p_Type := p_Type_178304fa149d, p_UserPrompt := p_UserPrompt_178304fa149d, p_UserComments := p_UserComments_178304fa149d, p_UserComments_Clear := TRUE, p_Code := p_Code_178304fa149d, p_Code_Clear := TRUE, p_CodeComments := p_CodeComments_178304fa149d, p_CodeComments_Clear := TRUE, p_CodeApprovalStatus := p_CodeApprovalStatus_178304fa149d, p_CodeApprovalComments := p_CodeApprovalComments_178304fa149d, p_CodeApprovalComments_Clear := TRUE, p_CodeApprovedByUserID := p_CodeApprovedByUserID_178304fa149d, p_CodeApprovedByUserID_Clear := TRUE, p_CodeApprovedAt := p_CodeApprovedAt_178304fa149d, p_CodeApprovedAt_Clear := TRUE, p_CodeLocked := p_CodeLocked_178304fa149d, p_ForceCodeGeneration := p_ForceCodeGeneration_178304fa149d, p_RetentionPeriod := p_RetentionPeriod_178304fa149d, p_RetentionPeriod_Clear := TRUE, p_Status := p_Status_178304fa149d, p_DriverClass := p_DriverClass_178304fa149d, p_ParentID := p_ParentID_178304fa149d, p_ParentID_Clear := TRUE, p_IconClass := p_IconClass_178304fa149d, p_DefaultCompactPromptID := p_DefaultCompactPromptID_178304fa149d, p_DefaultCompactPromptID_Clear := TRUE, p_Config := p_Config_178304fa149d, p_Config_Clear := TRUE, p_RuntimeActionConfiguration := p_RuntimeActionConfiguration_178304fa149d, p_RuntimeActionConfiguration_Clear := TRUE, p_MaxExecutionTimeMS := p_MaxExecutionTimeMS_178304fa149d, p_MaxExecutionTimeMS_Clear := TRUE, p_CreatedByAgentID := p_CreatedByAgentID_178304fa149d, p_CreatedByAgentID_Clear := TRUE);
    END IF;
  END IF;
END $mj$;

-- Save MJ: Scheduled Jobs (core SP call only)
DO $mj$
DECLARE
  p_ID_bbe937c26db5 UUID;
  p_JobTypeID_bbe937c26db5 UUID;
  p_Name_bbe937c26db5 VARCHAR(200);
  p_Description_bbe937c26db5 TEXT;
  p_CronExpression_bbe937c26db5 VARCHAR(120);
  p_Timezone_bbe937c26db5 VARCHAR(64);
  p_StartAt_bbe937c26db5 TIMESTAMPTZ;
  p_EndAt_bbe937c26db5 TIMESTAMPTZ;
  p_Status_bbe937c26db5 VARCHAR(20);
  p_Configuration_bbe937c26db5 TEXT;
  p_OwnerUserID_bbe937c26db5 UUID;
  p_LastRunAt_bbe937c26db5 TIMESTAMPTZ;
  p_NextRunAt_bbe937c26db5 TIMESTAMPTZ;
  p_RunCount_bbe937c26db5 INTEGER;
  p_SuccessCount_bbe937c26db5 INTEGER;
  p_FailureCount_bbe937c26db5 INTEGER;
  p_NotifyOnSuccess_bbe937c26db5 BOOLEAN;
  p_NotifyOnFailure_bbe937c26db5 BOOLEAN;
  p_NotifyUserID_bbe937c26db5 UUID;
  p_NotifyViaEmail_bbe937c26db5 BOOLEAN;
  p_NotifyViaInApp_bbe937c26db5 BOOLEAN;
  p_LockToken_bbe937c26db5 UUID;
  p_LockedAt_bbe937c26db5 TIMESTAMPTZ;
  p_LockedByInstance_bbe937c26db5 VARCHAR(255);
  p_ExpectedCompletionAt_bbe937c26db5 TIMESTAMPTZ;
  p_ConcurrencyMode_bbe937c26db5 VARCHAR(20);
  p_RunImmediatelyIfNeverRun_bbe937c26db5 BOOLEAN;
  p_MaxRuntimeMinutes_bbe937c26db5 INTEGER;
  p_MissedRunPolicy_bbe937c26db5 VARCHAR(20);
BEGIN
  p_ID_bbe937c26db5 := '8177872B-5C9D-4654-85A1-2A62D1545055';
  p_JobTypeID_bbe937c26db5 := '3B94DD43-E961-4D85-B7F4-B6783D748766';
  p_Name_bbe937c26db5 := 'Contracts — Record Renewal Outcomes (hourly)';
  p_Description_bbe937c26db5 := 'Records NonRenewalOutcome on contracts whose end date has passed, so the renewal-risk label is stored rather than computed on every read.';
  p_CronExpression_bbe937c26db5 := '0 5 * * * *';
  p_Timezone_bbe937c26db5 := 'UTC';
  p_Status_bbe937c26db5 := 'Active';
  p_Configuration_bbe937c26db5 := '{"ActionID":"B830ACF2-62F7-44BC-85D4-17AEA0769FBE","Params":[]}';
  p_RunCount_bbe937c26db5 := 0;
  p_SuccessCount_bbe937c26db5 := 0;
  p_FailureCount_bbe937c26db5 := 0;
  p_NotifyOnSuccess_bbe937c26db5 := FALSE;
  p_NotifyOnFailure_bbe937c26db5 := FALSE;
  p_NotifyViaEmail_bbe937c26db5 := FALSE;
  p_NotifyViaInApp_bbe937c26db5 := FALSE;
  p_ConcurrencyMode_bbe937c26db5 := 'Skip';
  p_RunImmediatelyIfNeverRun_bbe937c26db5 := TRUE;
  p_MaxRuntimeMinutes_bbe937c26db5 := 15;
  p_MissedRunPolicy_bbe937c26db5 := 'RunOnce';
  IF NOT EXISTS (SELECT 1 FROM "${mjSchema}"."ScheduledJob"
                 WHERE "ID" = p_ID_bbe937c26db5
                    OR ("Name" = p_Name_bbe937c26db5)) THEN
    IF EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = '${mjSchema}' AND p.proname = 'spCreateScheduledJob'
         AND p.pronargs = 1 AND p.proargtypes[0] = 'jsonb'::regtype
    ) THEN
      PERFORM "${mjSchema}"."spCreateScheduledJob"(p_data := jsonb_build_object(
    'ID', p_ID_bbe937c26db5,
    'JobTypeID', p_JobTypeID_bbe937c26db5,
    'Name', p_Name_bbe937c26db5,
    'Description', p_Description_bbe937c26db5,
    'CronExpression', p_CronExpression_bbe937c26db5,
    'Timezone', p_Timezone_bbe937c26db5,
    'StartAt', p_StartAt_bbe937c26db5,
    'EndAt', p_EndAt_bbe937c26db5,
    'Status', p_Status_bbe937c26db5,
    'Configuration', p_Configuration_bbe937c26db5,
    'OwnerUserID', p_OwnerUserID_bbe937c26db5,
    'LastRunAt', p_LastRunAt_bbe937c26db5,
    'NextRunAt', p_NextRunAt_bbe937c26db5,
    'RunCount', p_RunCount_bbe937c26db5,
    'SuccessCount', p_SuccessCount_bbe937c26db5,
    'FailureCount', p_FailureCount_bbe937c26db5,
    'NotifyOnSuccess', p_NotifyOnSuccess_bbe937c26db5,
    'NotifyOnFailure', p_NotifyOnFailure_bbe937c26db5,
    'NotifyUserID', p_NotifyUserID_bbe937c26db5,
    'NotifyViaEmail', p_NotifyViaEmail_bbe937c26db5,
    'NotifyViaInApp', p_NotifyViaInApp_bbe937c26db5,
    'LockToken', p_LockToken_bbe937c26db5,
    'LockedAt', p_LockedAt_bbe937c26db5,
    'LockedByInstance', p_LockedByInstance_bbe937c26db5,
    'ExpectedCompletionAt', p_ExpectedCompletionAt_bbe937c26db5,
    'ConcurrencyMode', p_ConcurrencyMode_bbe937c26db5,
    'RunImmediatelyIfNeverRun', p_RunImmediatelyIfNeverRun_bbe937c26db5,
    'MaxRuntimeMinutes', p_MaxRuntimeMinutes_bbe937c26db5,
    'MissedRunPolicy', p_MissedRunPolicy_bbe937c26db5
  ));
    ELSE
      PERFORM "${mjSchema}"."spCreateScheduledJob"(p_ID := p_ID_bbe937c26db5, p_JobTypeID := p_JobTypeID_bbe937c26db5, p_Name := p_Name_bbe937c26db5, p_Description := p_Description_bbe937c26db5, p_CronExpression := p_CronExpression_bbe937c26db5, p_Timezone := p_Timezone_bbe937c26db5, p_StartAt := p_StartAt_bbe937c26db5, p_StartAt_Clear := TRUE, p_EndAt := p_EndAt_bbe937c26db5, p_EndAt_Clear := TRUE, p_Status := p_Status_bbe937c26db5, p_Configuration := p_Configuration_bbe937c26db5, p_OwnerUserID := p_OwnerUserID_bbe937c26db5, p_OwnerUserID_Clear := TRUE, p_LastRunAt := p_LastRunAt_bbe937c26db5, p_LastRunAt_Clear := TRUE, p_NextRunAt := p_NextRunAt_bbe937c26db5, p_NextRunAt_Clear := TRUE, p_RunCount := p_RunCount_bbe937c26db5, p_SuccessCount := p_SuccessCount_bbe937c26db5, p_FailureCount := p_FailureCount_bbe937c26db5, p_NotifyOnSuccess := p_NotifyOnSuccess_bbe937c26db5, p_NotifyOnFailure := p_NotifyOnFailure_bbe937c26db5, p_NotifyUserID := p_NotifyUserID_bbe937c26db5, p_NotifyUserID_Clear := TRUE, p_NotifyViaEmail := p_NotifyViaEmail_bbe937c26db5, p_NotifyViaInApp := p_NotifyViaInApp_bbe937c26db5, p_LockToken := p_LockToken_bbe937c26db5, p_LockToken_Clear := TRUE, p_LockedAt := p_LockedAt_bbe937c26db5, p_LockedAt_Clear := TRUE, p_LockedByInstance := p_LockedByInstance_bbe937c26db5, p_LockedByInstance_Clear := TRUE, p_ExpectedCompletionAt := p_ExpectedCompletionAt_bbe937c26db5, p_ExpectedCompletionAt_Clear := TRUE, p_ConcurrencyMode := p_ConcurrencyMode_bbe937c26db5, p_RunImmediatelyIfNeverRun := p_RunImmediatelyIfNeverRun_bbe937c26db5, p_MaxRuntimeMinutes := p_MaxRuntimeMinutes_bbe937c26db5, p_MissedRunPolicy := p_MissedRunPolicy_bbe937c26db5);
    END IF;
  END IF;
END $mj$;
