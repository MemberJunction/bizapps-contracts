-- =============================================================================
-- BizApps Contracts — Tables and Objects (v0.1.0)
-- =============================================================================
-- Ten tables. The nine from plan 02 §3, plus ContractSequence for CTR-{seq}
-- numbering (the same singleton-counter shape orders uses for ORD-/PAY-).
--
-- Read B...__Schema_and_Types.sql first — it carries the cross-app FK policy,
-- the install-order dependency, and the L-15 prohibition on Contract.DealID.
--
-- CONFIGURATION AS DATA. ContractType carries the DEFAULTS for a class of
-- agreement and the engine READS them; it does not branch on a type string.
-- DriverClass is nullable and optional, following SubscriptionType's pattern
-- rather than RevenueRecognitionType's: the columns ARE the rules, a base
-- behaviour class reads them, and a driver is supplied only when a customer needs
-- something the columns cannot express. A driver-only model would force a class
-- per permutation of term x cadence x renewal x escalation.
--
-- Seed rows for ContractType ship via metadata/contract-types/ with hardcoded
-- UUIDs (the bizapps-common address-types pattern). NEVER as INSERTs here.
-- ContractSequence is the one exception: it is a singleton counter, not
-- vocabulary, and it must exist before the first contract is written.
-- =============================================================================

-- =============================================================================
-- 3. TABLES
-- =============================================================================

---------------------------------------------------------------------------
-- 3.1 ContractType — the rules for a class of agreement.
--     Seeded: Standard, MSA, SOW, Membership, Evergreen, Pilot (via metadata/).
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractType (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Code NVARCHAR(50) NOT NULL,
    Name NVARCHAR(100) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    DefaultTermMonths INT NULL,
    DefaultBillingFrequency NVARCHAR(20) NULL,
    DefaultAutoRenew BIT NOT NULL DEFAULT 0,
    RequiresSignature BIT NOT NULL DEFAULT 1,
    DefaultEscalationPercent DECIMAL(7,4) NULL,
    -- The ceiling on a renewal increase. 'ListPrice' escalation without a cap is the single most
    -- disputed clause in a B2B renewal ("increases shall not exceed 5%"), and there was nowhere
    -- to record the number the contract actually says.
    DefaultMaxEscalationPercent DECIMAL(7,4) NULL,
    -- Written notice required before a renewal price change. NOT the same thing as the
    -- cancellation window below, though many agreements set them equal — conflating them silently
    -- is how a notice obligation gets missed.
    DefaultRenewalNoticeDays INT NULL,
    DefaultCancellationWindowDays INT NULL,
    RenewalMode NVARCHAR(20) NOT NULL DEFAULT 'Deal',
    AllowsCoterm BIT NOT NULL DEFAULT 1,
    DriverClass NVARCHAR(255) NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_ContractType PRIMARY KEY (ID),
    CONSTRAINT CK_ContractType_BillingFrequency CHECK (DefaultBillingFrequency IS NULL OR DefaultBillingFrequency IN ('Monthly','Quarterly','SemiAnnual','Annual','Milestone','Custom')),
    -- 'Deal'   — a renewal is a deal (L-18): sales calls Contracts.RenewTerm when a
    --            renewal deal closes, so renewal gets its own pipeline and win-rate.
    -- 'Auto'   — the Scheduled Job calls the same operation with no deal. For evergreen
    --            and B2C, where a renewal pipeline would be theatre.
    -- 'Manual' — a human triggers it. No automation, no deal.
    CONSTRAINT CK_ContractType_RenewalMode CHECK (RenewalMode IN ('Deal','Auto','Manual')),
    CONSTRAINT CK_ContractType_TermMonths CHECK (DefaultTermMonths IS NULL OR DefaultTermMonths > 0),
    CONSTRAINT CK_ContractType_EscalationPercent CHECK (DefaultEscalationPercent IS NULL OR DefaultEscalationPercent >= 0),
    CONSTRAINT CK_ContractType_CancellationWindow CHECK (DefaultCancellationWindowDays IS NULL OR DefaultCancellationWindowDays >= 0)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_ContractType_Code
    ON __mj_BizAppsContracts.ContractType (Code);
GO

---------------------------------------------------------------------------
-- 3.2 ContractSequence — singleton counter for gap-conscious CTR-{seq}.
--     Same shape as orders' OrderSequence/PaymentSequence.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractSequence (
    ID INT NOT NULL DEFAULT 1,
    NextSequenceNumber INT NOT NULL DEFAULT 1,
    CONSTRAINT PK_ContractSequence PRIMARY KEY (ID),
    CONSTRAINT CK_ContractSequence_Singleton CHECK (ID = 1),
    CONSTRAINT CK_ContractSequence_NextSeq CHECK (NextSequenceNumber > 0)
);
GO

INSERT INTO __mj_BizAppsContracts.ContractSequence (ID, NextSequenceNumber) VALUES (1, 1);
GO

---------------------------------------------------------------------------
-- 3.3 Contract — the agreement.
--     ParentContractID is the MSA -> SOW nesting (D-5: deferred as a self-FK
--     rather than promoted to a distinct Agreement entity until the two
--     genuinely diverge).
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.Contract (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractNumber NVARCHAR(50) NOT NULL,
    ContractTypeID UNIQUEIDENTIFIER NOT NULL,
    CompanyID UNIQUEIDENTIFIER NOT NULL,
    CustomerOrganizationID UNIQUEIDENTIFIER NULL,
    CustomerPersonID UNIQUEIDENTIFIER NULL,
    PrimaryContactPersonID UNIQUEIDENTIFIER NULL,
    OwnerUserID UNIQUEIDENTIFIER NULL,
    ParentContractID UNIQUEIDENTIFIER NULL,
    -- The successor when Status='Superseded'. Status already carried that value with no way to
    -- name what replaced the contract, while ContractTerm had RenewalOfTermID for the renewal
    -- chain — so continuity was navigable at the term level and rupture was not at the contract
    -- level. This is the re-papered-each-period case: professional services, public-sector
    -- re-bid, or any renegotiation that produces wholly new paper rather than a new term.
    SupersededByContractID UNIQUEIDENTIFIER NULL,
    Status NVARCHAR(30) NOT NULL DEFAULT 'Draft',
    Description NVARCHAR(MAX) NULL,
    EffectiveDate DATE NULL,
    ExecutedDate DATE NULL,
    DocumentFileID UNIQUEIDENTIFIER NULL,
    AutoRenew BIT NOT NULL DEFAULT 0,
    CancellationWindowDays INT NULL,
    TerminationPolicy NVARCHAR(MAX) NULL,
    ExternalReferenceID NVARCHAR(255) NULL,
    CONSTRAINT PK_Contract PRIMARY KEY (ID),
    CONSTRAINT CK_Contract_Status CHECK (Status IN ('Draft','PendingSignature','Active','Expired','Terminated','Superseded')),
    -- Exactly one customer, organization XOR person — the idiom common.ContactMethod
    -- and Relationship already use. Each column is named ONCE: CodeGen derives the
    -- generated validation method name from the constraint expression, and repeating a
    -- column makes it emit a call to a method it never defined (a build break in
    -- generated code that orders hit and documented).
    CONSTRAINT CK_Contract_CustomerXor CHECK (
        (CASE WHEN CustomerOrganizationID IS NULL THEN 0 ELSE 1 END)
      + (CASE WHEN CustomerPersonID IS NULL THEN 0 ELSE 1 END) = 1
    ),
    -- A contract cannot be its own parent. Deeper cycles are the engine's problem;
    -- this catches the one a UI produces by accident.
    CONSTRAINT CK_Contract_ParentNotSelf CHECK (ParentContractID IS NULL OR ParentContractID <> ID),
    CONSTRAINT CK_Contract_SupersededNotSelf CHECK (SupersededByContractID IS NULL OR SupersededByContractID <> ID),
    CONSTRAINT CK_Contract_ExecutedAfterEffective CHECK (ExecutedDate IS NULL OR EffectiveDate IS NULL OR ExecutedDate >= EffectiveDate),
    CONSTRAINT CK_Contract_CancellationWindow CHECK (CancellationWindowDays IS NULL OR CancellationWindowDays >= 0)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_Contract_ContractNumber
    ON __mj_BizAppsContracts.Contract (ContractNumber);
GO

---------------------------------------------------------------------------
-- 3.4 ContractTerm — the period.
--     RenewalOfTermID chains back through prior terms, which is what makes the
--     renewal history navigable without a separate lineage table.
--     RenewalProbability earns its place: it is what a renewal forecast in
--     bizapps-sales reads.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractTerm (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractID UNIQUEIDENTIFIER NOT NULL,
    TermNumber INT NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Pending',
    RenewalOfTermID UNIQUEIDENTIFIER NULL,
    CommittedAmount DECIMAL(19,4) NULL,
    EscalationPercent DECIMAL(7,4) NULL,
    EscalationBasis NVARCHAR(20) NULL,
    MaxEscalationPercent DECIMAL(7,4) NULL,
    -- Required when EscalationBasis='Index'. The basis was in the value list with no way to say
    -- WHICH index, which made the option unimplementable as written.
    EscalationIndexCode NVARCHAR(50) NULL,
    RenewalNoticeDays INT NULL,
    BillingFrequency NVARCHAR(20) NOT NULL,
    BillingAnchorMonth TINYINT NULL,
    BillingAnchorDay TINYINT NULL,
    PaymentTermsTypeID UNIQUEIDENTIFIER NULL,
    CurrencyID UNIQUEIDENTIFIER NULL,
    EarlyTerminationDate DATE NULL,
    RenewalProbability DECIMAL(5,4) NULL,
    -- A TERM is separately executed whenever the renewal produces new paper. The contract carried
    -- ExecutedDate/DocumentFileID and the term carried neither, while ContractAmendment DID have a
    -- document — so the model said amendments get signed and renewals do not, which is backwards on
    -- commercial significance. It also silently assumed the evergreen pattern (one signed document,
    -- many periods); these two columns let the same schema express the re-papered pattern too.
    -- Both stay NULLable: an auto-renewing term legitimately has no paper of its own.
    ExecutedDate DATE NULL,
    DocumentFileID UNIQUEIDENTIFIER NULL,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractTerm PRIMARY KEY (ID),
    CONSTRAINT CK_ContractTerm_Status CHECK (Status IN ('Pending','PendingSignature','Active','Completed','Terminated')),
    CONSTRAINT CK_ContractTerm_Dates CHECK (EndDate >= StartDate),
    CONSTRAINT CK_ContractTerm_TermNumber CHECK (TermNumber > 0),
    CONSTRAINT CK_ContractTerm_EscalationBasis CHECK (EscalationBasis IS NULL OR EscalationBasis IN ('PriorTerm','ListPrice','Index')),
    CONSTRAINT CK_ContractTerm_BillingFrequency CHECK (BillingFrequency IN ('Monthly','Quarterly','SemiAnnual','Annual','Milestone','Custom')),
    CONSTRAINT CK_ContractTerm_AnchorMonth CHECK (BillingAnchorMonth IS NULL OR BillingAnchorMonth BETWEEN 1 AND 12),
    CONSTRAINT CK_ContractTerm_AnchorDay CHECK (BillingAnchorDay IS NULL OR BillingAnchorDay BETWEEN 1 AND 31),
    CONSTRAINT CK_ContractTerm_RenewalProbability CHECK (RenewalProbability IS NULL OR (RenewalProbability >= 0 AND RenewalProbability <= 1)),
    CONSTRAINT CK_ContractTerm_CommittedAmount CHECK (CommittedAmount IS NULL OR CommittedAmount >= 0),
    CONSTRAINT CK_ContractTerm_MaxEscalationPercent CHECK (MaxEscalationPercent IS NULL OR MaxEscalationPercent >= 0),
    CONSTRAINT CK_ContractTerm_RenewalNoticeDays CHECK (RenewalNoticeDays IS NULL OR RenewalNoticeDays >= 0),
    -- An 'Index' basis with no index named cannot be executed by the engine.
    CONSTRAINT CK_ContractTerm_IndexNeedsCode CHECK (EscalationBasis <> 'Index' OR EscalationIndexCode IS NOT NULL),
    CONSTRAINT CK_ContractTerm_RenewalNotSelf CHECK (RenewalOfTermID IS NULL OR RenewalOfTermID <> ID)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_ContractTerm_Contract_TermNumber
    ON __mj_BizAppsContracts.ContractTerm (ContractID, TermNumber);
GO

---------------------------------------------------------------------------
-- 3.5 ContractLine — what is covered.
--     LineType is what makes ONE table serve subscriptions, one-time fees,
--     milestone draws, usage true-ups and minimum commitments. The billing
--     engine reads it; nothing else branches on it.
--
--     ContractedUnitPrice is NULLABLE and null means RESOLVE NORMALLY — the line
--     is covered by the agreement but priced from the catalog. A non-null value
--     is what ContractPriceResolver returns, with escalation applied from the
--     term's rules at billing time rather than baked in here where it goes stale.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractLine (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTermID UNIQUEIDENTIFIER NOT NULL,
    ProductID UNIQUEIDENTIFIER NOT NULL,
    LineType NVARCHAR(20) NOT NULL,
    Quantity DECIMAL(18,4) NOT NULL DEFAULT 1,
    ContractedUnitPrice DECIMAL(19,4) NULL,
    DiscountPct DECIMAL(7,4) NULL,
    StartDate DATE NULL,
    EndDate DATE NULL,
    SubscriptionID UNIQUEIDENTIFIER NULL,
    -- The rate in force for THIS term, stamped when the term activates.
    --
    -- ContractedUnitPrice NULL means "resolve from the catalog", and orders' pricing walk is gated
    -- on the AsOf it is handed — so without a stamp, (a) a null-priced line can silently re-price
    -- mid-term if the engine passes the bill date, and (b) EscalationBasis='PriorTerm' has no prior
    -- number to escalate FROM, since nothing recorded what the line actually cost last term.
    --
    -- This does NOT contradict "not baked in here where it goes stale": that rule is right for a
    -- CONTRACT-level price, which is meant to track something that moves. A TERM-level rate is
    -- supposed to be frozen for the life of the term — freezing it is the feature, not the staleness.
    ResolvedUnitPrice DECIMAL(19,4) NULL,
    ResolvedAt DATETIMEOFFSET NULL,
    Description NVARCHAR(MAX) NULL,
    DisplayOrder INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_ContractLine PRIMARY KEY (ID),
    -- 'Usage' is in the value list deliberately even though usage metering is OUT
    -- OF V1 (orders defers the metering engine). Keeping it here means the schema
    -- does not change when metering arrives.
    CONSTRAINT CK_ContractLine_LineType CHECK (LineType IN ('Subscription','OneTime','Milestone','Usage','Minimum')),
    CONSTRAINT CK_ContractLine_Quantity CHECK (Quantity >= 0),
    CONSTRAINT CK_ContractLine_ContractedUnitPrice CHECK (ContractedUnitPrice IS NULL OR ContractedUnitPrice >= 0),
    CONSTRAINT CK_ContractLine_ResolvedUnitPrice CHECK (ResolvedUnitPrice IS NULL OR ResolvedUnitPrice >= 0),
    CONSTRAINT CK_ContractLine_DiscountPct CHECK (DiscountPct IS NULL OR (DiscountPct >= 0 AND DiscountPct <= 1)),
    -- Co-term stubs live here: a line added mid-term starts at the amendment date
    -- and ends at the TERM's end date, so the stub period prorates on the next
    -- billing event. That is the capability standalone subscriptions cannot provide.
    CONSTRAINT CK_ContractLine_Dates CHECK (StartDate IS NULL OR EndDate IS NULL OR EndDate >= StartDate),
    -- A subscription may only be attached to a line that is actually a subscription.
    CONSTRAINT CK_ContractLine_SubscriptionOnlyOnSubscriptionLine CHECK (SubscriptionID IS NULL OR LineType = 'Subscription')
);
GO

---------------------------------------------------------------------------
-- 3.6 ContractBillingSchedule — the plan.
--     One term may carry MORE THAN ONE schedule: a quarterly subscription
--     cadence AND a milestone schedule for the attached SOW.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractBillingSchedule (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTermID UNIQUEIDENTIFIER NOT NULL,
    ScheduleType NVARCHAR(20) NOT NULL,
    Frequency NVARCHAR(20) NULL,
    AnchorDate DATE NULL,
    IsActive BIT NOT NULL DEFAULT 1,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractBillingSchedule PRIMARY KEY (ID),
    CONSTRAINT CK_ContractBillingSchedule_ScheduleType CHECK (ScheduleType IN ('Cadence','Milestone','Custom')),
    CONSTRAINT CK_ContractBillingSchedule_Frequency CHECK (Frequency IS NULL OR Frequency IN ('Monthly','Quarterly','SemiAnnual','Annual','Milestone','Custom')),
    -- A cadence schedule without a frequency has nothing to iterate.
    CONSTRAINT CK_ContractBillingSchedule_CadenceNeedsFrequency CHECK (ScheduleType <> 'Cadence' OR Frequency IS NOT NULL)
);
GO

---------------------------------------------------------------------------
-- 3.7 ContractBillingEvent — each occurrence, AND the audit trail.
--     This is the record that answers "why did the customer get this bill on
--     this date, and what produced it".
--
--     A failed generation stays Failed WITH A REASON rather than silently
--     retrying into a duplicate. Duplicate billing is the kind of defect a
--     customer discovers before we do.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractBillingEvent (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractBillingScheduleID UNIQUEIDENTIFIER NULL,
    ContractTermID UNIQUEIDENTIFIER NOT NULL,
    ScheduledDate DATE NOT NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Scheduled',
    OrderID UNIQUEIDENTIFIER NULL,
    ComputedAmount DECIMAL(19,4) NULL,
    GeneratedAt DATETIMEOFFSET NULL,
    FailureReason NVARCHAR(MAX) NULL,
    Notes NVARCHAR(MAX) NULL,
    CONSTRAINT PK_ContractBillingEvent PRIMARY KEY (ID),
    CONSTRAINT CK_ContractBillingEvent_Status CHECK (Status IN ('Scheduled','Generated','Skipped','Failed')),
    -- A Generated event MUST name the order it produced. This is the invariant that
    -- makes the status transition a real idempotency guard rather than a label: the
    -- scheduled driver re-running over a Generated row must be unable to bill again,
    -- and it can only trust that if Generated implies an order exists.
    CONSTRAINT CK_ContractBillingEvent_GeneratedHasOrder CHECK (Status <> 'Generated' OR OrderID IS NOT NULL),
    -- Symmetrically, a Failed event must say why. "Failed" with no reason is a
    -- support ticket nobody can answer.
    CONSTRAINT CK_ContractBillingEvent_FailedHasReason CHECK (Status <> 'Failed' OR LEN(LTRIM(ISNULL(FailureReason, ''))) > 0),
    CONSTRAINT CK_ContractBillingEvent_ComputedAmount CHECK (ComputedAmount IS NULL OR ComputedAmount >= 0)
);
GO

-- One order per billing event, enforced. Filtered so the many NULLs (Scheduled,
-- Skipped, Failed rows) do not collide with each other.
CREATE UNIQUE NONCLUSTERED INDEX UQ_ContractBillingEvent_Order
    ON __mj_BizAppsContracts.ContractBillingEvent (OrderID)
    WHERE OrderID IS NOT NULL;
GO

-- The scheduled driver's access path: Status='Scheduled' AND ScheduledDate <= today.
CREATE NONCLUSTERED INDEX IX_ContractBillingEvent_Due
    ON __mj_BizAppsContracts.ContractBillingEvent (Status, ScheduledDate)
    INCLUDE (ContractTermID);
GO

---------------------------------------------------------------------------
-- 3.8 ContractCommitment — minimums, prepaid draws, true-ups.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractCommitment (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTermID UNIQUEIDENTIFIER NOT NULL,
    CommitmentType NVARCHAR(20) NOT NULL,
    CommittedAmount DECIMAL(19,4) NOT NULL,
    ConsumedAmount DECIMAL(19,4) NOT NULL DEFAULT 0,
    PeriodStart DATE NULL,
    PeriodEnd DATE NULL,
    TrueUpPolicy NVARCHAR(20) NOT NULL DEFAULT 'BillShortfall',
    Status NVARCHAR(20) NOT NULL DEFAULT 'Open',
    CONSTRAINT PK_ContractCommitment PRIMARY KEY (ID),
    CONSTRAINT CK_ContractCommitment_CommitmentType CHECK (CommitmentType IN ('Minimum','Prepaid','Draw')),
    CONSTRAINT CK_ContractCommitment_TrueUpPolicy CHECK (TrueUpPolicy IN ('BillShortfall','Forfeit','Rollover')),
    CONSTRAINT CK_ContractCommitment_Status CHECK (Status IN ('Open','Closed','TruedUp','Forfeited')),
    CONSTRAINT CK_ContractCommitment_CommittedAmount CHECK (CommittedAmount >= 0),
    -- ConsumedAmount is NOT capped at CommittedAmount on purpose: over-consumption
    -- against a minimum is a real state the engine must be able to record and report,
    -- not an error to reject at write time.
    CONSTRAINT CK_ContractCommitment_ConsumedAmount CHECK (ConsumedAmount >= 0),
    CONSTRAINT CK_ContractCommitment_Period CHECK (PeriodStart IS NULL OR PeriodEnd IS NULL OR PeriodEnd >= PeriodStart)
);
GO

---------------------------------------------------------------------------
-- 3.9 ContractAmendment — mid-term change.
--     Amendments change a LIVE term. Renewals start a NEW one (see
--     Contracts.RenewTerm and ContractTerm.RenewalOfTermID). Conflating the two
--     is the single most common contract-model mistake.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractAmendment (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractTermID UNIQUEIDENTIFIER NOT NULL,
    AmendmentNumber INT NOT NULL,
    EffectiveDate DATE NOT NULL,
    AmendmentType NVARCHAR(30) NOT NULL,
    Description NVARCHAR(MAX) NULL,
    DocumentFileID UNIQUEIDENTIFIER NULL,
    Status NVARCHAR(20) NOT NULL DEFAULT 'Draft',
    -- Hard FK -> bizapps-tasks (§4.A). Approvals for non-standard terms, discounts
    -- beyond a rep's SalesAuthority, and early-termination waivers all route through it.
    ApprovalTaskID UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_ContractAmendment PRIMARY KEY (ID),
    CONSTRAINT CK_ContractAmendment_AmendmentType CHECK (AmendmentType IN ('AddProduct','ChangeQuantity','ChangePrice','Coterm','PartialTerminate','Other')),
    CONSTRAINT CK_ContractAmendment_Status CHECK (Status IN ('Draft','PendingApproval','Approved','Rejected','Applied','Cancelled')),
    CONSTRAINT CK_ContractAmendment_AmendmentNumber CHECK (AmendmentNumber > 0)
);
GO

CREATE UNIQUE NONCLUSTERED INDEX UQ_ContractAmendment_Term_Number
    ON __mj_BizAppsContracts.ContractAmendment (ContractTermID, AmendmentNumber);
GO

---------------------------------------------------------------------------
-- 3.10 ContractEvent — immutable lifecycle log.
--      Mirrors orders' SubscriptionEvent. Never edited, never deleted.
--
--      This is the SYSTEM record. Customer-visible contract events (executed,
--      renewed, terminated) ALSO write a common.Activity row via
--      Common.LogActivity, so the agreement appears on the account timeline.
--      They are not the same thing and neither replaces the other.
---------------------------------------------------------------------------
CREATE TABLE __mj_BizAppsContracts.ContractEvent (
    ID UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContractID UNIQUEIDENTIFIER NOT NULL,
    ContractTermID UNIQUEIDENTIFIER NULL,
    EventType NVARCHAR(50) NOT NULL,
    EventDate DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
    Payload NVARCHAR(MAX) NULL,
    PerformedByUserID UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_ContractEvent PRIMARY KEY (ID)
);
GO

-- The contract timeline read path.
CREATE NONCLUSTERED INDEX IX_ContractEvent_Contract_Date
    ON __mj_BizAppsContracts.ContractEvent (ContractID, EventDate DESC);
GO

-- =============================================================================
-- 4. FOREIGN KEYS
-- =============================================================================
-- No cascades anywhere in this schema, matching orders. A contract is financial
-- provenance: deleting a term must fail loudly against its lines rather than
-- quietly taking them with it.
-- =============================================================================

---------------------------------------------------------------------------
-- 4.1 Within __mj_BizAppsContracts
---------------------------------------------------------------------------
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_ContractType
    FOREIGN KEY (ContractTypeID) REFERENCES __mj_BizAppsContracts.ContractType(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_ParentContract
    FOREIGN KEY (ParentContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

-- The supersession chain, the contract-level counterpart to ContractTerm.RenewalOfTermID.
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_SupersededByContract
    FOREIGN KEY (SupersededByContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractTerm
    ADD CONSTRAINT FK_ContractTerm_Contract
    FOREIGN KEY (ContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractTerm
    ADD CONSTRAINT FK_ContractTerm_RenewalOfTerm
    FOREIGN KEY (RenewalOfTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractLine
    ADD CONSTRAINT FK_ContractLine_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractBillingSchedule
    ADD CONSTRAINT FK_ContractBillingSchedule_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractBillingEvent
    ADD CONSTRAINT FK_ContractBillingEvent_ContractBillingSchedule
    FOREIGN KEY (ContractBillingScheduleID) REFERENCES __mj_BizAppsContracts.ContractBillingSchedule(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractBillingEvent
    ADD CONSTRAINT FK_ContractBillingEvent_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractCommitment
    ADD CONSTRAINT FK_ContractCommitment_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractAmendment
    ADD CONSTRAINT FK_ContractAmendment_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractEvent
    ADD CONSTRAINT FK_ContractEvent_Contract
    FOREIGN KEY (ContractID) REFERENCES __mj_BizAppsContracts.Contract(ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractEvent
    ADD CONSTRAINT FK_ContractEvent_ContractTerm
    FOREIGN KEY (ContractTermID) REFERENCES __mj_BizAppsContracts.ContractTerm(ID);
GO

---------------------------------------------------------------------------
-- 4.A CROSS-APP FOREIGN KEYS — real constraints, not soft UUID columns.
--
--     These are the dependency check. If bizapps-common, bizapps-accounting or
--     bizapps-orders has not been installed, this section fails and the migration
--     stops — which is the correct outcome, loudly, rather than a schema that
--     looks installed and dangles.
---------------------------------------------------------------------------

-- -> __mj (core)
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_Company
    FOREIGN KEY (CompanyID) REFERENCES __mj.Company(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_OwnerUser
    FOREIGN KEY (OwnerUserID) REFERENCES __mj.[User](ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_DocumentFile
    FOREIGN KEY (DocumentFileID) REFERENCES __mj.[File](ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractAmendment
    ADD CONSTRAINT FK_ContractAmendment_DocumentFile
    FOREIGN KEY (DocumentFileID) REFERENCES __mj.[File](ID);
GO

-- A separately-executed renewal term's own paper.
ALTER TABLE __mj_BizAppsContracts.ContractTerm
    ADD CONSTRAINT FK_ContractTerm_DocumentFile
    FOREIGN KEY (DocumentFileID) REFERENCES __mj.[File](ID);
GO

ALTER TABLE __mj_BizAppsContracts.ContractEvent
    ADD CONSTRAINT FK_ContractEvent_PerformedByUser
    FOREIGN KEY (PerformedByUserID) REFERENCES __mj.[User](ID);
GO

-- -> __mj_BizAppsCommon (the customer master)
ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_CustomerOrganization
    FOREIGN KEY (CustomerOrganizationID) REFERENCES __mj_BizAppsCommon.Organization(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_CustomerPerson
    FOREIGN KEY (CustomerPersonID) REFERENCES __mj_BizAppsCommon.Person(ID);
GO

ALTER TABLE __mj_BizAppsContracts.Contract
    ADD CONSTRAINT FK_Contract_PrimaryContactPerson
    FOREIGN KEY (PrimaryContactPersonID) REFERENCES __mj_BizAppsCommon.Person(ID);
GO

-- -> __mj_BizAppsOrders (the catalog, the subscription, the receivable)
ALTER TABLE __mj_BizAppsContracts.ContractLine
    ADD CONSTRAINT FK_ContractLine_Product
    FOREIGN KEY (ProductID) REFERENCES __mj_BizAppsOrders.Product(ID);
GO

-- The materialized subscription for a LineType='Subscription' line. This is the
-- linkage that lives HERE and points UP the graph — orders never learns the word
-- "contract"; it only learns that a subscription's BillingMode is 'External'.
ALTER TABLE __mj_BizAppsContracts.ContractLine
    ADD CONSTRAINT FK_ContractLine_Subscription
    FOREIGN KEY (SubscriptionID) REFERENCES __mj_BizAppsOrders.Subscription(ID);
GO

-- The consolidated order a billing event produced. A legal DOWNWARD reference:
-- contracts sits above orders, so this points down the graph.
ALTER TABLE __mj_BizAppsContracts.ContractBillingEvent
    ADD CONSTRAINT FK_ContractBillingEvent_Order
    FOREIGN KEY (OrderID) REFERENCES __mj_BizAppsOrders.OrderHeader(ID);
GO

-- -> __mj_BizAppsTasks
-- The approval gate. Tasks is the state machine for long-arc human review across the
-- BizApps family — the same substrate accounting uses for batch approval and sales uses
-- for close-won routing. TaskType OnComplete/OnReject Action hooks call back into
-- contracts to advance or reject the amendment.
ALTER TABLE __mj_BizAppsContracts.ContractAmendment
    ADD CONSTRAINT FK_ContractAmendment_ApprovalTask
    FOREIGN KEY (ApprovalTaskID) REFERENCES __mj_BizAppsTasks.Task(ID);
GO

-- Orders owns payment terms; accounting delegates to it and so do we.
ALTER TABLE __mj_BizAppsContracts.ContractTerm
    ADD CONSTRAINT FK_ContractTerm_PaymentTermsType
    FOREIGN KEY (PaymentTermsTypeID) REFERENCES __mj_BizAppsOrders.PaymentTermsType(ID);
GO

-- -> __mj_BizAppsAccounting
-- Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in
-- this app converts between currencies. The column exists so that when multi-currency
-- arrives the term already says which currency it was written in, rather than the
-- answer having to be inferred from the selling company years later.
ALTER TABLE __mj_BizAppsContracts.ContractTerm
    ADD CONSTRAINT FK_ContractTerm_Currency
    FOREIGN KEY (CurrencyID) REFERENCES __mj_BizAppsAccounting.Currency(ID);
GO

-- =============================================================================
-- 5. EXTENDED PROPERTIES
-- =============================================================================
-- CodeGen reads these into entity/field descriptions, so they are the documentation
-- an adopter actually sees in Explorer. Written for the reader who is about to get
-- something wrong, not as a restatement of the column name.
-- =============================================================================

-- ContractType
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Named defaults for a class of agreement (Standard, MSA, SOW, Membership, Evergreen, Pilot). Configuration as data: the engine READS these columns rather than branching on the type name.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Stable machine key, unique. Referenced by CloseWonPolicy in bizapps-sales, so renaming Name is safe and changing Code is not.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'Code';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'How a term of this type renews. Deal = a renewal is a deal (L-18); bizapps-sales calls Contracts.RenewTerm when a renewal deal closes, so renewal gets its own pipeline and win-rate. Auto = the Scheduled Job renews with no deal, for evergreen and B2C. Manual = a human triggers it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'RenewalMode';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'OPTIONAL ClassFactory key for a behaviour subclass, following SubscriptionType rather than RevenueRecognitionType: the columns ARE the rules and a base class reads them. Supply a driver only when a customer needs something the columns cannot express.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'DriverClass';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Whether a term of this type may absorb a mid-term addition aligned to the term end date (co-terming).', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractType', @level2type=N'COLUMN', @level2name=N'AllowsCoterm';
GO

-- Contract
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The agreement. Deliberately carries NO reference to a Deal (L-15): sales sits above contracts so a reference upward inverts the dependency graph, and the cardinality is one contract to MANY deals (the original sale, every renewal, every expansion). The reverse lookup lives in sales as Deal.ContractID and returns a set.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'CTR-{seq} from ContractSequence. Unique.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ContractNumber';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The SELLING company (__mj.Company) — which of our entities holds this agreement. Not the customer.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CompanyID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The customer, when the customer is an organization. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CustomerOrganizationID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The customer, when the customer is an individual. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'CustomerPersonID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Self-FK for MSA -> SOW nesting (D-5). Modelled as a self-reference rather than a distinct Agreement entity until the two genuinely diverge.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'Contract', @level2type=N'COLUMN', @level2name=N'ParentContractID';
GO

-- ContractTerm
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'One period of an agreement. A RENEWAL creates a NEW term with RenewalOfTermID set; a mid-term change is a ContractAmendment against the existing one. Conflating those two is the most common contract-model mistake.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTerm';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Self-FK chaining back to the term this one renewed, making the renewal history navigable without a separate lineage table.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTerm', @level2type=N'COLUMN', @level2name=N'RenewalOfTermID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The rate increase applied at renewal, per EscalationBasis. Applied BY THE RESOLVER at billing time from the term rules — never baked into stored line prices, which then go stale.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTerm', @level2type=N'COLUMN', @level2name=N'EscalationPercent';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'0..1 likelihood this term renews. Exists because a renewal forecast in bizapps-sales reads it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTerm', @level2type=N'COLUMN', @level2name=N'RenewalProbability';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in this app converts between currencies. It exists so a term states the currency it was written in, rather than that being inferred from the selling company years later.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractTerm', @level2type=N'COLUMN', @level2name=N'CurrencyID';
GO

-- ContractLine
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'What the agreement covers. LineType is what lets ONE table serve subscriptions, one-time fees, milestone draws, usage true-ups and minimum commitments — the billing engine reads it and nothing else branches on it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractLine';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Subscription | OneTime | Milestone | Usage | Minimum. Usage is present in the value list although usage metering is out of v1, so the schema need not change when metering arrives.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractLine', @level2type=N'COLUMN', @level2name=N'LineType';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The negotiated per-unit price. NULL means RESOLVE NORMALLY — the line is covered by the agreement but priced from the catalog. A non-null value is what ContractPriceResolver returns into orders'' pricing walk; escalation is applied by the resolver at billing time, not stored here.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractLine', @level2type=N'COLUMN', @level2name=N'ContractedUnitPrice';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The materialized orders Subscription for a LineType=Subscription line. This linkage lives HERE and points up the graph: orders never learns the word "contract", only that the subscription''s BillingMode is External so SpawnRenewals skips it.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractLine', @level2type=N'COLUMN', @level2name=N'SubscriptionID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Co-term stubs live here: a line added mid-term starts at the amendment date and ends at the TERM''s end date, so the stub prorates on the next billing event. This is the capability standalone subscriptions structurally cannot provide, and the reason the contract owns the calendar.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractLine', @level2type=N'COLUMN', @level2name=N'EndDate';
GO

-- ContractBillingSchedule
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'How a term produces bills. One term may carry MORE THAN ONE schedule — a quarterly subscription cadence AND a milestone schedule for an attached SOW.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractBillingSchedule';
GO

-- ContractBillingEvent
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Each billing occurrence AND the audit trail: the record that answers "why did the customer get this bill on this date, and what produced it". A failure stays Failed with a reason rather than retrying into a duplicate — duplicate billing is the kind of defect a customer finds before we do.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractBillingEvent';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The ONE consolidated order this event produced, via Orders.CreateOrderInState. A legal downward reference: contracts sits above orders. Status=Generated requires it, which is what makes the status transition a real idempotency guard.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractBillingEvent', @level2type=N'COLUMN', @level2name=N'OrderID';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'A STAMP of the total Orders.PreviewOrder returned — never a figure computed in this app. Contracts decides WHAT to bill and never what it costs.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractBillingEvent', @level2type=N'COLUMN', @level2name=N'ComputedAmount';
GO

-- ContractCommitment
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Minimums, prepaid draws and true-ups. ConsumedAmount is deliberately NOT capped at CommittedAmount: over-consumption against a minimum is a real state to record and report, not an error to reject at write time.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractCommitment';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'What happens to an unconsumed minimum at period end: BillShortfall adds the gap to the next bill, Forfeit drops it, Rollover carries it forward.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractCommitment', @level2type=N'COLUMN', @level2name=N'TrueUpPolicy';
GO

-- ContractAmendment
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'A mid-term change to a LIVE term. Renewals do NOT come through here — they start a new ContractTerm with RenewalOfTermID set.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractAmendment';
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'The bizapps-tasks Task gating this amendment. Raised for non-standard terms, discounts beyond a rep''s SalesAuthority, and early-termination waivers; TaskType OnComplete/OnReject hooks call back into contracts to advance or reject.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractAmendment', @level2type=N'COLUMN', @level2name=N'ApprovalTaskID';
GO

-- ContractEvent
EXEC sp_addextendedproperty @name=N'MS_Description', @value=N'Immutable lifecycle log, mirroring orders'' SubscriptionEvent. Never edited, never deleted. This is the SYSTEM record; customer-visible events also write a common.Activity row so the agreement appears on the account timeline. Neither replaces the other.', @level0type=N'SCHEMA', @level0name=N'__mj_BizAppsContracts', @level1type=N'TABLE', @level1name=N'ContractEvent';
GO

-- =============================================================================
-- CODEGEN OUTPUT — GENERATED CODE BELOW THIS LINE
-- =============================================================================
-- Everything below this banner is produced by `npm run mj:codegen` and folded in
-- by scripts/append-codegen.sh: entity/field metadata, base views, CRUD procedures
-- and permissions. It is what makes a fresh `mj migrate` produce a WORKING database
-- rather than bare tables.
--
-- NOTHING HAS BEEN APPENDED YET. This baseline carries the hand-authored DDL only.
-- The generated half lands after the first successful run of:
--     scripts/rebuild-db.sh
--     npm run mj:codegen
--     scripts/append-codegen.sh
-- =============================================================================
