-- =============================================================================
-- Wave 4.3b: Single-write __mj_UpdatedAt backfill
--   1. Sets [__mj_UpdatedAt] = GETUTCDATE() directly inside spUpdate* procedures
--      so BaseEntity.Save() performs a single write to the base table.
--   2. Wraps trgUpdate* __mj_UpdatedAt triggers in IF NOT UPDATE([__mj_UpdatedAt])
--      so direct SQL UPDATEs that omit __mj_UpdatedAt still get stamped, while
--      spUpdate* (and explicit callers) skip the redundant second write.
-- =============================================================================























































------------------------------------------------------------
----- UPDATE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContract]
    @ID uniqueidentifier,
    @ContractNumber_Clear bit = 0,
    @ContractNumber nvarchar(50) = NULL,
    @ContractTypeID uniqueidentifier = NULL,
    @CompanyID uniqueidentifier = NULL,
    @CustomerOrganizationID uniqueidentifier = NULL,
    @PrimaryContactPersonID_Clear bit = 0,
    @PrimaryContactPersonID uniqueidentifier = NULL,
    @ContractTemplateID_Clear bit = 0,
    @ContractTemplateID uniqueidentifier = NULL,
    @CreatingEntityID_Clear bit = 0,
    @CreatingEntityID uniqueidentifier = NULL,
    @CreatingRecordID_Clear bit = 0,
    @CreatingRecordID nvarchar(450) = NULL,
    @ParentContractID_Clear bit = 0,
    @ParentContractID uniqueidentifier = NULL,
    @SupersededByContractID_Clear bit = 0,
    @SupersededByContractID uniqueidentifier = NULL,
    @SigningProviderURL_Clear bit = 0,
    @SigningProviderURL nvarchar(1000) = NULL,
    @EffectiveDate_Clear bit = 0,
    @EffectiveDate date = NULL,
    @ExecutedDate_Clear bit = 0,
    @ExecutedDate date = NULL,
    @EndDate_Clear bit = 0,
    @EndDate date = NULL,
    @TerminatedDate_Clear bit = 0,
    @TerminatedDate date = NULL,
    @AutoRenew bit = NULL,
    @RenewalNoticeDays_Clear bit = 0,
    @RenewalNoticeDays int = NULL,
    @CancellationWindowDays_Clear bit = 0,
    @CancellationWindowDays int = NULL,
    @AnnualIncreasePercent_Clear bit = 0,
    @AnnualIncreasePercent decimal(7, 4) = NULL,
    @HasModifications bit = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL,
    @PredictedNonRenewalRisk_Clear bit = 0,
    @PredictedNonRenewalRisk decimal(5, 4) = NULL,
    @PredictedRenewalRiskBand_Clear bit = 0,
    @PredictedRenewalRiskBand nvarchar(20) = NULL,
    @PredictedRenewalScoredAt_Clear bit = 0,
    @PredictedRenewalScoredAt datetimeoffset = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[Contract]
    SET
        [ContractNumber] = CASE WHEN @ContractNumber_Clear = 1 THEN NULL ELSE ISNULL(@ContractNumber, [ContractNumber]) END,
        [ContractTypeID] = ISNULL(@ContractTypeID, [ContractTypeID]),
        [CompanyID] = ISNULL(@CompanyID, [CompanyID]),
        [CustomerOrganizationID] = ISNULL(@CustomerOrganizationID, [CustomerOrganizationID]),
        [PrimaryContactPersonID] = CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, [PrimaryContactPersonID]) END,
        [ContractTemplateID] = CASE WHEN @ContractTemplateID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateID, [ContractTemplateID]) END,
        [CreatingEntityID] = CASE WHEN @CreatingEntityID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingEntityID, [CreatingEntityID]) END,
        [CreatingRecordID] = CASE WHEN @CreatingRecordID_Clear = 1 THEN NULL ELSE ISNULL(@CreatingRecordID, [CreatingRecordID]) END,
        [ParentContractID] = CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, [ParentContractID]) END,
        [SupersededByContractID] = CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, [SupersededByContractID]) END,
        [SigningProviderURL] = CASE WHEN @SigningProviderURL_Clear = 1 THEN NULL ELSE ISNULL(@SigningProviderURL, [SigningProviderURL]) END,
        [EffectiveDate] = CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, [EffectiveDate]) END,
        [ExecutedDate] = CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, [ExecutedDate]) END,
        [EndDate] = CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, [EndDate]) END,
        [TerminatedDate] = CASE WHEN @TerminatedDate_Clear = 1 THEN NULL ELSE ISNULL(@TerminatedDate, [TerminatedDate]) END,
        [AutoRenew] = ISNULL(@AutoRenew, [AutoRenew]),
        [RenewalNoticeDays] = CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, [RenewalNoticeDays]) END,
        [CancellationWindowDays] = CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, [CancellationWindowDays]) END,
        [AnnualIncreasePercent] = CASE WHEN @AnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@AnnualIncreasePercent, [AnnualIncreasePercent]) END,
        [HasModifications] = ISNULL(@HasModifications, [HasModifications]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END,
        [PredictedNonRenewalRisk] = CASE WHEN @PredictedNonRenewalRisk_Clear = 1 THEN NULL ELSE ISNULL(@PredictedNonRenewalRisk, [PredictedNonRenewalRisk]) END,
        [PredictedRenewalRiskBand] = CASE WHEN @PredictedRenewalRiskBand_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalRiskBand, [PredictedRenewalRiskBand]) END,
        [PredictedRenewalScoredAt] = CASE WHEN @PredictedRenewalScoredAt_Clear = 1 THEN NULL ELSE ISNULL(@PredictedRenewalScoredAt, [PredictedRenewalScoredAt]) END,
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContracts] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContracts]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the Contract table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContract]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContract];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContract
ON [${flyway:defaultSchema}].[Contract]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[Contract]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[Contract] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplate
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplate]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplate];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplate]
    @ID uniqueidentifier,
    @Name nvarchar(200) = NULL,
    @ContractTemplateTypeID uniqueidentifier = NULL,
    @VersionLabel_Clear bit = 0,
    @VersionLabel nvarchar(50) = NULL,
    @IntroducedDate_Clear bit = 0,
    @IntroducedDate date = NULL,
    @SourceURL_Clear bit = 0,
    @SourceURL nvarchar(1000) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplate]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [ContractTemplateTypeID] = ISNULL(@ContractTemplateTypeID, [ContractTemplateTypeID]),
        [VersionLabel] = CASE WHEN @VersionLabel_Clear = 1 THEN NULL ELSE ISNULL(@VersionLabel, [VersionLabel]) END,
        [IntroducedDate] = CASE WHEN @IntroducedDate_Clear = 1 THEN NULL ELSE ISNULL(@IntroducedDate, [IntroducedDate]) END,
        [SourceURL] = CASE WHEN @SourceURL_Clear = 1 THEN NULL ELSE ISNULL(@SourceURL, [SourceURL]) END,
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Status] = ISNULL(@Status, [Status]),
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplates] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplates]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplate] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplate] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplate table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplate]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplate];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplate
ON [${flyway:defaultSchema}].[ContractTemplate]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[ContractTemplate]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[ContractTemplate] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateModification
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateModification]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateModification];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateModification]
    @ID uniqueidentifier,
    @ContractID uniqueidentifier = NULL,
    @ContractTemplateProvisionID uniqueidentifier = NULL,
    @ModificationText nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateModification]
    SET
        [ContractID] = ISNULL(@ContractID, [ContractID]),
        [ContractTemplateProvisionID] = ISNULL(@ContractTemplateProvisionID, [ContractTemplateProvisionID]),
        [ModificationText] = ISNULL(@ModificationText, [ModificationText]),
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END,
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateModifications] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateModifications]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateModification] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateModification] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateModification table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateModification]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateModification];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateModification
ON [${flyway:defaultSchema}].[ContractTemplateModification]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[ContractTemplateModification]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[ContractTemplateModification] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateProvision
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateProvision]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateProvision];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateProvision]
    @ID uniqueidentifier,
    @ContractTemplateID uniqueidentifier = NULL,
    @ProvisionNumber nvarchar(20) = NULL,
    @Title nvarchar(200) = NULL,
    @ProvisionText nvarchar(MAX) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateProvision]
    SET
        [ContractTemplateID] = ISNULL(@ContractTemplateID, [ContractTemplateID]),
        [ProvisionNumber] = ISNULL(@ProvisionNumber, [ProvisionNumber]),
        [Title] = ISNULL(@Title, [Title]),
        [ProvisionText] = ISNULL(@ProvisionText, [ProvisionText]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateProvisions] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateProvisions]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateProvision] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateProvision table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateProvision]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateProvision];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateProvision
ON [${flyway:defaultSchema}].[ContractTemplateProvision]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[ContractTemplateProvision]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[ContractTemplateProvision] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTemplateType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTemplateType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTemplateType]
    @ID uniqueidentifier,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTemplateType]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Status] = ISNULL(@Status, [Status]),
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTemplateTypes] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTemplateTypes]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateType] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTemplateType] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTemplateType table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTemplateType]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTemplateType];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTemplateType
ON [${flyway:defaultSchema}].[ContractTemplateType]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[ContractTemplateType]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[ContractTemplateType] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType]
    @ID uniqueidentifier,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @RequiresExecutedDocument bit = NULL,
    @Status nvarchar(10) = NULL,
    @MustBeRoot bit = NULL,
    @MustBeChild bit = NULL,
    @TemplateRequired bit = NULL,
    @DefaultAutoRenew_Clear bit = 0,
    @DefaultAutoRenew bit = NULL,
    @DefaultRenewalNoticeDays_Clear bit = 0,
    @DefaultRenewalNoticeDays int = NULL,
    @DefaultCancellationWindowDays_Clear bit = 0,
    @DefaultCancellationWindowDays int = NULL,
    @DefaultAnnualIncreasePercent_Clear bit = 0,
    @DefaultAnnualIncreasePercent decimal(7, 4) = NULL,
    @Code nvarchar(50) = NULL,
    @ContractTemplateTypeID_Clear bit = 0,
    @ContractTemplateTypeID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [RequiresExecutedDocument] = ISNULL(@RequiresExecutedDocument, [RequiresExecutedDocument]),
        [Status] = ISNULL(@Status, [Status]),
        [MustBeRoot] = ISNULL(@MustBeRoot, [MustBeRoot]),
        [MustBeChild] = ISNULL(@MustBeChild, [MustBeChild]),
        [TemplateRequired] = ISNULL(@TemplateRequired, [TemplateRequired]),
        [DefaultAutoRenew] = CASE WHEN @DefaultAutoRenew_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAutoRenew, [DefaultAutoRenew]) END,
        [DefaultRenewalNoticeDays] = CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, [DefaultRenewalNoticeDays]) END,
        [DefaultCancellationWindowDays] = CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, [DefaultCancellationWindowDays]) END,
        [DefaultAnnualIncreasePercent] = CASE WHEN @DefaultAnnualIncreasePercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultAnnualIncreasePercent, [DefaultAnnualIncreasePercent]) END,
        [Code] = ISNULL(@Code, [Code]),
        [ContractTemplateTypeID] = CASE WHEN @ContractTemplateTypeID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTemplateTypeID, [ContractTemplateTypeID]) END,
        [__mj_UpdatedAt] = GETUTCDATE()
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTypes]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration]
GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration];
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractType table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractType]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractType];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractType
ON [${flyway:defaultSchema}].[ContractType]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE([__mj_UpdatedAt])
    BEGIN
        UPDATE
            [${flyway:defaultSchema}].[ContractType]
        SET
            __mj_UpdatedAt = GETUTCDATE()
        FROM
            [${flyway:defaultSchema}].[ContractType] AS _organicTable
        INNER JOIN
            INSERTED AS I ON
            _organicTable.[ID] = I.[ID];
    END
END;
GO
