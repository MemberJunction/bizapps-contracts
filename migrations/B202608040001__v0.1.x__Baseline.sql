-- =============================================================================
-- BizApps Contracts — THE BASELINE (v0.1.0)
-- =============================================================================
-- ONE FILE. Schema, SchemaInfo registration, all ten tables and their constraints,
-- and the CodeGen output that turns bare tables into a working app. Applying this
-- file to an empty database produces an installed contracts app; nothing else is
-- required before `mj sync push` seeds the reference vocabulary.
--
-- WHY IT IS ONE FILE AND NOT TWO. It used to be B...__Schema_and_Types.sql plus
-- V...__Tables_and_Objects.sql, split following bizapps-orders so that a
-- user-defined table type would be COMMITTED before any trigger declaring a
-- variable of it was compiled. That hazard is real — see the constraint note in
-- §2.A — but it does not apply here: THIS APP DECLARES NO TABLE TYPES. Carrying a
-- second file for a hazard the app does not have cost a reader one more hop and
-- gained nothing, so the baseline is flat.
--
-- IF THIS APP EVER ADDS A TABLE TYPE, split it back out. Read §2.A first: the
-- constraint is subtle, the failure is a `Msg 1205 ... deadlocked with another
-- process` at an innocent-looking CodeGen backfill hundreds of batches later, and
-- it reads as server instability rather than an ordering bug.
--
-- PRE-PRODUCTION PRACTICE. Nothing here is published, so schema changes EDIT THIS
-- FILE IN PLACE and the database is rebuilt from zero — no incremental fix-up
-- migrations. Switch to additive-only at first publish, after which an applied
-- migration is immutable. See migrations/_README.md.
--
-- Design source of truth is plans/bizapps-contracts-master.md in this repo, with
-- decisions L-10..L-12, L-15 and L-18 governing.
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
-- 1. SCHEMA
-- =============================================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = '__mj_BizAppsContracts')
    EXEC('CREATE SCHEMA __mj_BizAppsContracts');
GO

-- =============================================================================
-- 2. SCHEMA INFO — entity-name prefix for CodeGen (must match mj.config.cjs)
-- =============================================================================
INSERT INTO __mj.SchemaInfo
(
  ID,
  SchemaName,
  EntityIDMin, EntityIDMax,
  Comments,
  Description,
  EntityNamePrefix, EntityNameSuffix
)
VALUES
(
  '1A531C07-5F1A-448D-A2BF-B986801F4F1D',
  '__mj_BizAppsContracts',
  1, 1000000,
  NULL,
  'MemberJunction: BizApps Contracts — the agreement envelope and the billing event',
  'MJ_BizApps_Contracts: ', NULL
);
GO

-- =============================================================================
-- 2.A TYPES
-- =============================================================================
-- None yet. See the header for why this file exists regardless.
--
-- CONSTRAINT ON EVERY FUTURE CONSUMER: never touch a variable of a type declared here
-- inside the transaction that created it. A rollup trigger that declares such a variable
-- and fires during the migration deadlocks on the type's own metadata lock. Return early
-- on zero-row DML — which is exactly what CodeGen's __mj_CreatedAt backfills are.

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
    CONSTRAINT CK_ContractType_CancellationWindow CHECK (DefaultCancellationWindowDays IS NULL OR DefaultCancellationWindowDays >= 0),
    -- The two defaults below were the only percent/day columns on this table WITHOUT a bound, while
    -- their ContractTerm counterparts (CK_ContractTerm_MaxEscalationPercent,
    -- CK_ContractTerm_RenewalNoticeDays) and their own siblings above all had one. The inconsistency
    -- was accidental rather than intended (X.2).
    --
    -- It became load-bearing on 2026-08-05, when ContractsEngine started applying these defaults to
    -- every NEW term: a negative default here would now flow silently into terms where the same value
    -- typed directly would have been rejected. A bound at the source is the only place it can be
    -- caught before it spreads.
    CONSTRAINT CK_ContractType_MaxEscalationPercent CHECK (DefaultMaxEscalationPercent IS NULL OR DefaultMaxEscalationPercent >= 0),
    CONSTRAINT CK_ContractType_RenewalNoticeDays CHECK (DefaultRenewalNoticeDays IS NULL OR DefaultRenewalNoticeDays >= 0)
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
    -- AS-OF DATE FOR PRICING (Andrew, 2026-08-04). The price quoted when the deal was struck is
    -- the price that belongs in the contract, so prices must be resolved as of a MOMENT the
    -- business chooses — never "now".
    --
    -- On creation the UI shows the catalog price as of this date and LOCKS it into
    -- ContractLine.ContractedUnitPrice. That lock is the point: a manager who opens a contract,
    -- reviews the numbers and saves it must not have the value move underneath them because the
    -- catalog changed in between. Backdatable, because a contract signed last month can be entered
    -- today and must price as of when it was actually agreed.
    --
    -- Renewals: the FIRST renewal of a line whose ContractedUnitPrice is null resolves the catalog
    -- price as of PricedAt, applies the agreed escalation, and writes the result in. Every renewal
    -- after that escalates from the contract's own prior price and never re-reads the catalog —
    -- the agreement, once priced, is self-referential.
    PricedAt DATE NULL,
    AutoRenew BIT NOT NULL DEFAULT 0,
    CancellationWindowDays INT NULL,
    -- MOVED UP FROM ContractTerm (2026-08-05). Written notice before a renewal price change is a
    -- provision of the AGREEMENT, not of a period: it is negotiated once and does not change term by
    -- term, and holding it per-term meant every renewal copied it forward and every reader had to
    -- check whether some term had quietly diverged. The type still supplies the default
    -- (ContractType.DefaultRenewalNoticeDays); it now lands here.
    --
    -- NOT the same thing as CancellationWindowDays above, though many agreements set them equal —
    -- conflating them silently is how a notice obligation gets missed.
    RenewalNoticeDays INT NULL,
    TerminationPolicy NVARCHAR(MAX) NULL,
    ExternalReferenceID NVARCHAR(255) NULL,
    CONSTRAINT PK_Contract PRIMARY KEY (ID),
    CONSTRAINT CK_Contract_Status CHECK (Status IN ('Draft','PendingSignature','Active','Expired','Terminated','Superseded')),
    -- SupersededByContractID exists BECAUSE a superseded contract had no way to name its successor.
    -- Leaving it optional preserves the exact state the column was added to eliminate, and the
    -- successor chain the workspace walks then dead-ends with no explanation. (X.6)
    CONSTRAINT CK_Contract_SupersededHasSuccessor CHECK (Status <> 'Superseded' OR SupersededByContractID IS NOT NULL),
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
    -- REMOVED: a CHECK requiring ExecutedDate >= EffectiveDate. It has the real world backwards —
    -- agreements are routinely SIGNED BEFORE they take effect (sign in December, effective Jan 1),
    -- which is the ordinary case for an annual term, not an anomaly. The constraint rejected exactly
    -- the data a correct contract produces. Caught by seeding realistic demo data, 2026-08-04.
    -- An Active contract has been priced. Draft may not have been yet.
    -- EVERY state past Draft needs the pricing moment, not just Active (X.7). The narrow version
    -- let a contract reach Expired, Terminated or Superseded with a null PricedAt — including by
    -- leaving Active and THEN nulling it, which is the path that made the original constraint
    -- decorative. Renewal pricing reads `Contract.PricedAt` as the as-of for the one catalog lookup
    -- a line ever gets, and superseded/expired contracts are exactly the ones a renewal or a
    -- replacement reads back, so a null there is not a historical curiosity — it is a price that
    -- cannot be resolved.
    --
    -- Draft is deliberately still exempt: a contract being typed has not been priced yet, and
    -- demanding the date up front would mean guessing it. `ContractEntityServer.Save()` defaults it
    -- on the way in, so in practice the only rows without one are drafts nobody has saved.
    CONSTRAINT CK_Contract_PricedWhenActive CHECK (Status = 'Draft' OR PricedAt IS NOT NULL),
    CONSTRAINT CK_Contract_CancellationWindow CHECK (CancellationWindowDays IS NULL OR CancellationWindowDays >= 0),
    CONSTRAINT CK_Contract_RenewalNoticeDays CHECK (RenewalNoticeDays IS NULL OR RenewalNoticeDays >= 0)
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
    -- NOT NULL as of 2026-08-05. A term states what was committed for its period; a term that does
    -- not is a period nobody agreed a number for, and every consumer had to decide what a null meant
    -- (the roster summed it as zero, the renewal escalated from it, the commitment measured against
    -- it). Zero is a legitimate committed amount and says so explicitly; null said nothing.
    CommittedAmount DECIMAL(19,4) NOT NULL,
    EscalationPercent DECIMAL(7,4) NULL,
    EscalationBasis NVARCHAR(20) NULL,
    BillingFrequency NVARCHAR(20) NOT NULL,
    BillingAnchorMonth TINYINT NULL,
    BillingAnchorDay TINYINT NULL,
    PaymentTermsTypeID UNIQUEIDENTIFIER NULL,
    CurrencyID UNIQUEIDENTIFIER NULL,
    EarlyTerminationDate DATE NULL,
    RenewalProbability DECIMAL(5,4) NULL,
    -- REMOVED 2026-08-05: ContractTerm.ExecutedDate.
    --
    -- It was added to express the re-papered pattern (new signed paper per period) alongside the
    -- evergreen one, and the contract's own ExecutedDate now carries execution. Recorded here rather
    -- than deleted silently because the re-papering case is real — professional services,
    -- public-sector re-bid — and if it comes back, it comes back knowingly. The signed DOCUMENT was
    -- never a column either way: contracts, terms and amendments all attach paper through
    -- __mj.FileEntityRecordLink, so a per-term document survives this removal.
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
    CONSTRAINT CK_ContractTerm_CommittedAmount CHECK (CommittedAmount >= 0),
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
    -- Stored as a FRACTION (0.10 = 10%), matching orders' OrderLine.DiscountPct and
    -- SalesAuthority.MaxDiscountPct exactly — same shape, same name, deliberately.
    --
    -- SEMANTICS (Amith, 2026-08-04): a contract-level discount OVERRIDES the discounting that
    -- would otherwise apply beneath it in the order. It does not stack. Orders owns the discount
    -- MECHANICS; the contract states the negotiated intent that outranks them.
    DiscountPct DECIMAL(7,4) NULL,
    StartDate DATE NULL,
    EndDate DATE NULL,
    -- WHICH KIND of subscription this line will materialize, chosen on the CONTRACT before any
    -- subscription exists. orders.Subscription.SubscriptionTypeID is NOT NULL, so the billing engine
    -- cannot create one without this — and the choice (membership vs seat-based vs term licence, who
    -- may hold it, its renewal lead time) is a contract provision that gets negotiated, not an
    -- orders-side detail to be guessed at materialization time.
    SubscriptionTypeID UNIQUEIDENTIFIER NULL,
    -- Set AFTER materialization: the subscription this line actually produced.
    SubscriptionID UNIQUEIDENTIFIER NULL,
    Description NVARCHAR(MAX) NULL,
    DisplayOrder INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_ContractLine PRIMARY KEY (ID),
    -- 'Usage' is in the value list deliberately even though usage metering is OUT
    -- OF V1 (orders defers the metering engine). Keeping it here means the schema
    -- does not change when metering arrives.
    CONSTRAINT CK_ContractLine_LineType CHECK (LineType IN ('Subscription','OneTime','Milestone','Usage','Minimum')),
    CONSTRAINT CK_ContractLine_Quantity CHECK (Quantity >= 0),
    CONSTRAINT CK_ContractLine_ContractedUnitPrice CHECK (ContractedUnitPrice IS NULL OR ContractedUnitPrice >= 0),
    CONSTRAINT CK_ContractLine_DiscountPct CHECK (DiscountPct IS NULL OR (DiscountPct >= 0 AND DiscountPct <= 1)),
    -- Co-term stubs live here: a line added mid-term starts at the amendment date
    -- and ends at the TERM's end date, so the stub period prorates on the next
    -- billing event. That is the capability standalone subscriptions cannot provide.
    CONSTRAINT CK_ContractLine_Dates CHECK (StartDate IS NULL OR EndDate IS NULL OR EndDate >= StartDate),
    -- A subscription may only be attached to a line that is actually a subscription.
    CONSTRAINT CK_ContractLine_SubscriptionOnlyOnSubscriptionLine CHECK (SubscriptionID IS NULL OR LineType = 'Subscription'),
    CONSTRAINT CK_ContractLine_SubscriptionTypeOnlyOnSubscriptionLine CHECK (SubscriptionTypeID IS NULL OR LineType = 'Subscription'),
    -- The mirror of the constraint above, and the one that actually matters: nothing REQUIRED the
    -- type on a subscription line, so the row saved and the failure landed at BILLING time — a Failed
    -- event on a live contract — instead of at write time on a draft. orders.Subscription
    -- .SubscriptionTypeID is NOT NULL, so the engine cannot materialize without it. Same shape as
    -- CK_ContractBillingSchedule_CadenceNeedsFrequency one table over. (X.5)
    CONSTRAINT CK_ContractLine_SubscriptionNeedsType CHECK (LineType <> 'Subscription' OR SubscriptionTypeID IS NOT NULL)
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
    -- 'Cancelled' is distinct from 'Skipped': Skipped is one occurrence that did not bill, Cancelled
    -- is an occurrence killed because the agreement ended under it. Termination needs the second
    -- meaning — without it, cancelling a terminated contract's future events is indistinguishable
    -- from an operator skipping a single run.
    CONSTRAINT CK_ContractBillingEvent_Status CHECK (Status IN ('Scheduled','Generated','Skipped','Cancelled','Failed')),
    -- A Generated event MUST name the order it produced. This is the invariant that
    -- makes the status transition a real idempotency guard rather than a label: the
    -- scheduled driver re-running over a Generated row must be unable to bill again,
    -- and it can only trust that if Generated implies an order exists.
    CONSTRAINT CK_ContractBillingEvent_GeneratedHasOrder CHECK (Status <> 'Generated' OR OrderID IS NOT NULL),
    -- "When was this bill produced" was optional in the one status where it must exist. The engine
    -- stamps OrderID, ComputedAmount AND GeneratedAt together; only the first was enforced. (X.12)
    CONSTRAINT CK_ContractBillingEvent_GeneratedHasTimestamp CHECK (Status <> 'Generated' OR GeneratedAt IS NOT NULL),
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

-- ONE SUBSCRIPTION, ONE LINE. BillingMode='External' exists to make "exactly one thing spawns
-- orders for a subscription" true by construction (master §4.1). Two contract lines pointing at the
-- same orders.Subscription re-opens the duplicate-billing hole from the other side — the side the
-- BillingMode design does not cover. Filtered, exactly like UQ_ContractBillingEvent_Order above,
-- because the column is null until materialization. (X.9)
CREATE UNIQUE NONCLUSTERED INDEX UQ_ContractLine_Subscription
    ON __mj_BizAppsContracts.ContractLine (SubscriptionID)
    WHERE SubscriptionID IS NOT NULL;
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
    Status NVARCHAR(20) NOT NULL DEFAULT 'Draft',
    -- Hard FK -> bizapps-tasks (§4.A). Approvals for non-standard terms, discounts
    -- beyond a rep's SalesAuthority, and early-termination waivers all route through it.
    ApprovalTaskID UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_ContractAmendment PRIMARY KEY (ID),
    CONSTRAINT CK_ContractAmendment_AmendmentType CHECK (AmendmentType IN ('AddProduct','ChangeQuantity','ChangePrice','Coterm','PartialTerminate','Other')),
    CONSTRAINT CK_ContractAmendment_Status CHECK (Status IN ('Draft','PendingApproval','Approved','Rejected','Applied','Cancelled')),
    -- An amendment marked Approved with no ApprovalTaskID is an approval with no record — precisely
    -- what routing non-standard terms through an approval task exists to prevent (§6). Rejected is
    -- included: a rejection is equally a decision somebody made and must be traceable to it. (X.14)
    CONSTRAINT CK_ContractAmendment_ApprovedHasTask CHECK (Status NOT IN ('Approved','Rejected') OR ApprovalTaskID IS NOT NULL),
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
    CONSTRAINT PK_ContractEvent PRIMARY KEY (ID),
    -- A CLOSED VOCABULARY. This was the schema's only unconstrained value column — every other value
    -- list here is CHECK-enforced — so EventType='asdf' saved happily, the History tab could not
    -- render a known set, and no query could trust a type filter. It also let two conventions drift
    -- apart unnoticed: the demo seed was writing 'TermRenewed' while the renewal operation wrote
    -- 'Renewed', for the same event. Naming the set is what forced them back together. (X.15)
    --
    -- Note the prefix discipline: Contract* for things that happen to the agreement, Term* for things
    -- that happen to a period, BillingEvent* for things that happen to a scheduled bill. A reader can
    -- tell the subject of an event from its type alone.
    CONSTRAINT CK_ContractEvent_EventType CHECK (EventType IN (
        'ContractCreated','ContractExecuted','ContractTerminated','ContractSuperseded','ContractExpired',
        'SentForSignature','SignatureRejected',
        'TermActivated','TermRenewed','TermCompleted','TermTerminated',
        'AmendmentApplied',
        'BillingEventGenerated','BillingEventFailed'
    ))
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
    ADD CONSTRAINT FK_ContractLine_SubscriptionType
    FOREIGN KEY (SubscriptionTypeID) REFERENCES __mj_BizAppsOrders.SubscriptionType(ID);
GO

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























































-- CodeGen Output
/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Sequences */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'e2f30cea-cabb-490c-9fda-e0f89f1db655',
         'MJ_BizApps_Contracts: Contract Sequences',
         'Contract Sequences',
         NULL,
         NULL,
         'ContractSequence',
         'vwContractSequences',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to create new application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[Application] WHERE [ID] = '2ecbf684-1b0b-46a2-8095-32a486b7e038'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[Application] (ID, Name, Description, SchemaAutoAddNewEntities, Path, AutoUpdatePath, DefaultForNewUser)
                       VALUES ('2ecbf684-1b0b-46a2-8095-32a486b7e038', '${flyway:defaultSchema}', 'Generated for schema', '${flyway:defaultSchema}', 'mjbizappscontracts', 1, 0)
   END;

/* Adding role UI to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '2ecbf684-1b0b-46a2-8095-32a486b7e038' AND [RoleID] = 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('2ecbf684-1b0b-46a2-8095-32a486b7e038', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* Adding role Developer to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '2ecbf684-1b0b-46a2-8095-32a486b7e038' AND [RoleID] = 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('2ecbf684-1b0b-46a2-8095-32a486b7e038', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1)
   END;

/* Adding role Integration to application ${flyway:defaultSchema} */
IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[ApplicationRole] WHERE [ApplicationID] = '2ecbf684-1b0b-46a2-8095-32a486b7e038' AND [RoleID] = 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[ApplicationRole]
                                 ([ApplicationID], [RoleID], [CanAccess], [CanAdmin]) VALUES
                                 ('2ecbf684-1b0b-46a2-8095-32a486b7e038', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0)
   END;

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Sequences to application ID: '2ecbf684-1b0b-46a2-8095-32a486b7e038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ecbf684-1b0b-46a2-8095-32a486b7e038', 'e2f30cea-cabb-490c-9fda-e0f89f1db655', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ecbf684-1b0b-46a2-8095-32a486b7e038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('e2f30cea-cabb-490c-9fda-e0f89f1db655', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('e2f30cea-cabb-490c-9fda-e0f89f1db655', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Sequences for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('e2f30cea-cabb-490c-9fda-e0f89f1db655', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contracts */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '82943343-8584-4023-9b36-385482d5de51',
         'MJ_BizApps_Contracts: Contracts',
         'Contracts',
         'The agreement. Deliberately carries NO reference to a Deal (L-15): sales sits above contracts so a reference upward inverts the dependency graph, and the cardinality is one contract to MANY deals (the original sale, every renewal, every expansion). The reverse lookup lives in sales as Deal.ContractID and returns a set.',
         NULL,
         'Contract',
         'vwContracts',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contracts to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '82943343-8584-4023-9b36-385482d5de51', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('82943343-8584-4023-9b36-385482d5de51', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('82943343-8584-4023-9b36-385482d5de51', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contracts for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('82943343-8584-4023-9b36-385482d5de51', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Terms */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '317f4fd7-0cdd-4b17-973e-d55944d03dee',
         'MJ_BizApps_Contracts: Contract Terms',
         'Contract Terms',
         'One period of an agreement. A RENEWAL creates a NEW term with RenewalOfTermID set; a mid-term change is a ContractAmendment against the existing one. Conflating those two is the most common contract-model mistake.',
         NULL,
         'ContractTerm',
         'vwContractTerms',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Terms to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '317f4fd7-0cdd-4b17-973e-d55944d03dee', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Terms for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317f4fd7-0cdd-4b17-973e-d55944d03dee', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Terms for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317f4fd7-0cdd-4b17-973e-d55944d03dee', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Terms for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('317f4fd7-0cdd-4b17-973e-d55944d03dee', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Lines */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '5b88dafc-a8c4-4554-b1c9-be4f015140a9',
         'MJ_BizApps_Contracts: Contract Lines',
         'Contract Lines',
         'What the agreement covers. LineType is what lets ONE table serve subscriptions, one-time fees, milestone draws, usage true-ups and minimum commitments — the billing engine reads it and nothing else branches on it.',
         NULL,
         'ContractLine',
         'vwContractLines',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Lines to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '5b88dafc-a8c4-4554-b1c9-be4f015140a9', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Lines for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5b88dafc-a8c4-4554-b1c9-be4f015140a9', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Lines for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5b88dafc-a8c4-4554-b1c9-be4f015140a9', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Lines for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('5b88dafc-a8c4-4554-b1c9-be4f015140a9', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Billing Schedules */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '2458f4c0-c0ec-4b48-9e5f-2dd8afa4103f',
         'MJ_BizApps_Contracts: Contract Billing Schedules',
         'Contract Billing Schedules',
         'How a term produces bills. One term may carry MORE THAN ONE schedule — a quarterly subscription cadence AND a milestone schedule for an attached SOW.',
         NULL,
         'ContractBillingSchedule',
         'vwContractBillingSchedules',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Billing Schedules to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '2458f4c0-c0ec-4b48-9e5f-2dd8afa4103f', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Schedules for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2458f4c0-c0ec-4b48-9e5f-2dd8afa4103f', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Schedules for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2458f4c0-c0ec-4b48-9e5f-2dd8afa4103f', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Schedules for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('2458f4c0-c0ec-4b48-9e5f-2dd8afa4103f', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Billing Events */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '57f99c92-591b-4f35-82d9-83f6b330d8f1',
         'MJ_BizApps_Contracts: Contract Billing Events',
         'Contract Billing Events',
         'Each billing occurrence AND the audit trail: the record that answers "why did the customer get this bill on this date, and what produced it". A failure stays Failed with a reason rather than retrying into a duplicate — duplicate billing is the kind of defect a customer finds before we do.',
         NULL,
         'ContractBillingEvent',
         'vwContractBillingEvents',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Billing Events to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '57f99c92-591b-4f35-82d9-83f6b330d8f1', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Events for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('57f99c92-591b-4f35-82d9-83f6b330d8f1', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Events for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('57f99c92-591b-4f35-82d9-83f6b330d8f1', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Billing Events for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('57f99c92-591b-4f35-82d9-83f6b330d8f1', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Commitments */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '4342d779-6f68-4f94-9067-4f12c8e1d25b',
         'MJ_BizApps_Contracts: Contract Commitments',
         'Contract Commitments',
         'Minimums, prepaid draws and true-ups. ConsumedAmount is deliberately NOT capped at CommittedAmount: over-consumption against a minimum is a real state to record and report, not an error to reject at write time.',
         NULL,
         'ContractCommitment',
         'vwContractCommitments',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Commitments to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '4342d779-6f68-4f94-9067-4f12c8e1d25b', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Commitments for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4342d779-6f68-4f94-9067-4f12c8e1d25b', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Commitments for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4342d779-6f68-4f94-9067-4f12c8e1d25b', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Commitments for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('4342d779-6f68-4f94-9067-4f12c8e1d25b', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Amendments */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '39d1f825-0d1a-4292-a0f2-c168e145c210',
         'MJ_BizApps_Contracts: Contract Amendments',
         'Contract Amendments',
         'A mid-term change to a LIVE term. Renewals do NOT come through here — they start a new ContractTerm with RenewalOfTermID set.',
         NULL,
         'ContractAmendment',
         'vwContractAmendments',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Amendments to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '39d1f825-0d1a-4292-a0f2-c168e145c210', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Amendments for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('39d1f825-0d1a-4292-a0f2-c168e145c210', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Amendments for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('39d1f825-0d1a-4292-a0f2-c168e145c210', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Amendments for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('39d1f825-0d1a-4292-a0f2-c168e145c210', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Events */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         'f2dddc7e-a21c-4fca-96fe-0b73e2c6f2b6',
         'MJ_BizApps_Contracts: Contract Events',
         'Contract Events',
         'Immutable lifecycle log, mirroring orders'' SubscriptionEvent. Never edited, never deleted. This is the SYSTEM record; customer-visible events also write a common.Activity row so the agreement appears on the account timeline. Neither replaces the other.',
         NULL,
         'ContractEvent',
         'vwContractEvents',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Events to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', 'f2dddc7e-a21c-4fca-96fe-0b73e2c6f2b6', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Events for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('f2dddc7e-a21c-4fca-96fe-0b73e2c6f2b6', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Events for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('f2dddc7e-a21c-4fca-96fe-0b73e2c6f2b6', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Events for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('f2dddc7e-a21c-4fca-96fe-0b73e2c6f2b6', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to create new entity MJ_BizApps_Contracts: Contract Types */

      INSERT INTO [${mjSchema}].[Entity] (
         [ID],
         [Name],
         [DisplayName],
         [Description],
         [NameSuffix],
         [BaseTable],
         [BaseView],
         [SchemaName],
         [IncludeInAPI],
         [AllowUserSearchAPI],
         [AllowCaching]
         , [TrackRecordChanges]
         , [AuditRecordAccess]
         , [AuditViewRuns]
         , [AllowAllRowsAPI]
         , [AllowCreateAPI]
         , [AllowUpdateAPI]
         , [AllowDeleteAPI]
         , [UserViewMaxRows]
         , [__mj_CreatedAt]
         , [__mj_UpdatedAt]
      )
      VALUES (
         '626148ec-40a2-4a28-b4da-7b7564a3ae9c',
         'MJ_BizApps_Contracts: Contract Types',
         'Contract Types',
         'Named defaults for a class of agreement (Standard, MSA, SOW, Membership, Evergreen, Pilot). Configuration as data: the engine READS these columns rather than branching on the type name.',
         NULL,
         'ContractType',
         'vwContractTypes',
         '${flyway:defaultSchema}',
         1,
         1,
         0
         , 1
         , 0
         , 0
         , 0
         , 1
         , 1
         , 1
         , 1000
         , GETUTCDATE()
         , GETUTCDATE()
      );

/* SQL generated to add new entity MJ_BizApps_Contracts: Contract Types to application ID: '2ECBF684-1B0B-46A2-8095-32A486B7E038' */
INSERT INTO [${mjSchema}].[ApplicationEntity]
                                       ([ApplicationID], [EntityID], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                       ('2ECBF684-1B0B-46A2-8095-32A486B7E038', '626148ec-40a2-4a28-b4da-7b7564a3ae9c', (SELECT COALESCE(MAX([Sequence]),0)+1 FROM [${mjSchema}].[ApplicationEntity] WHERE [ApplicationID] = '2ECBF684-1B0B-46A2-8095-32A486B7E038'), GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role UI */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('626148ec-40a2-4a28-b4da-7b7564a3ae9c', 'E0AFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 0, 0, 0, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Developer */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('626148ec-40a2-4a28-b4da-7b7564a3ae9c', 'DEAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL generated to add new permission for entity MJ_BizApps_Contracts: Contract Types for role Integration */
INSERT INTO [${mjSchema}].[EntityPermission]
                                                   ([EntityID], [RoleID], [CanRead], [CanCreate], [CanUpdate], [CanDelete], [__mj_CreatedAt], [__mj_UpdatedAt]) VALUES
                                                   ('626148ec-40a2-4a28-b4da-7b7564a3ae9c', 'DFAFCCEC-6A37-EF11-86D4-000D3A4E707E', 1, 1, 1, 1, GETUTCDATE(), GETUTCDATE());

/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractEvent */
UPDATE [${flyway:defaultSchema}].[ContractEvent] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractEvent___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractEvent */
UPDATE [${flyway:defaultSchema}].[ContractEvent] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractEvent] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractEvent___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
UPDATE [${flyway:defaultSchema}].[ContractBillingSchedule] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractBillingSchedule___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
UPDATE [${flyway:defaultSchema}].[ContractBillingSchedule] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingSchedule */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingSchedule] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractBillingSchedule___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
UPDATE [${flyway:defaultSchema}].[Contract] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD CONSTRAINT [DF___mj_BizAppsContracts_Contract___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
UPDATE [${flyway:defaultSchema}].[Contract] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.Contract */
ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD CONSTRAINT [DF___mj_BizAppsContracts_Contract___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
UPDATE [${flyway:defaultSchema}].[ContractCommitment] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractCommitment___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
UPDATE [${flyway:defaultSchema}].[ContractCommitment] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractCommitment */
ALTER TABLE [${flyway:defaultSchema}].[ContractCommitment] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractCommitment___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
UPDATE [${flyway:defaultSchema}].[ContractType] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractType___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
UPDATE [${flyway:defaultSchema}].[ContractType] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractType */
ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractType___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
UPDATE [${flyway:defaultSchema}].[ContractBillingEvent] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractBillingEvent___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
UPDATE [${flyway:defaultSchema}].[ContractBillingEvent] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractBillingEvent */
ALTER TABLE [${flyway:defaultSchema}].[ContractBillingEvent] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractBillingEvent___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractLine */
UPDATE [${flyway:defaultSchema}].[ContractLine] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractLine___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractLine */
UPDATE [${flyway:defaultSchema}].[ContractLine] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractLine */
ALTER TABLE [${flyway:defaultSchema}].[ContractLine] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractLine___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
UPDATE [${flyway:defaultSchema}].[ContractAmendment] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractAmendment___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
UPDATE [${flyway:defaultSchema}].[ContractAmendment] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractAmendment */
ALTER TABLE [${flyway:defaultSchema}].[ContractAmendment] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractAmendment___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTerm */
UPDATE [${flyway:defaultSchema}].[ContractTerm] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTerm___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTerm */
UPDATE [${flyway:defaultSchema}].[ContractTerm] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractTerm */
ALTER TABLE [${flyway:defaultSchema}].[ContractTerm] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractTerm___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD [__mj_CreatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
UPDATE [${flyway:defaultSchema}].[ContractSequence] SET [__mj_CreatedAt] = GETUTCDATE() WHERE [__mj_CreatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ALTER COLUMN [__mj_CreatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_CreatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractSequence___mj_CreatedAt] DEFAULT GETUTCDATE() FOR [__mj_CreatedAt];
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD [__mj_UpdatedAt] DATETIMEOFFSET NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
UPDATE [${flyway:defaultSchema}].[ContractSequence] SET [__mj_UpdatedAt] = GETUTCDATE() WHERE [__mj_UpdatedAt] IS NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ALTER COLUMN [__mj_UpdatedAt] DATETIMEOFFSET NOT NULL;
GO

/* SQL text to add special date field __mj_UpdatedAt to entity ${flyway:defaultSchema}.ContractSequence */
ALTER TABLE [${flyway:defaultSchema}].[ContractSequence] ADD CONSTRAINT [DF___mj_BizAppsContracts_ContractSequence___mj_UpdatedAt] DEFAULT GETUTCDATE() FOR [__mj_UpdatedAt];
GO

/* SQL text to insert 130 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b9206e37-2d15-460c-bb13-7dc3e3754676' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b9206e37-2d15-460c-bb13-7dc3e3754676',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '14a8802a-5aa6-4bb5-925a-70227ddbe234' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'ContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '14a8802a-5aa6-4bb5-925a-70227ddbe234',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100002,
            'ContractID',
            'Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '82943343-8584-4023-9B36-385482D5DE51',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd2a70eaa-de9d-4d1a-badd-7c3935cc58e3' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd2a70eaa-de9d-4d1a-badd-7c3935cc58e3',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100003,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2f5a984-4b8e-4edf-9e69-473e5000aeb4' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'EventType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e2f5a984-4b8e-4edf-9e69-473e5000aeb4',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100004,
            'EventType',
            'Event Type',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2dcc174-d184-46de-a966-ad5c62d74269' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'EventDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e2dcc174-d184-46de-a966-ad5c62d74269',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100005,
            'EventDate',
            'Event Date',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'sysdatetimeoffset()',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'be299203-dd4e-41a6-8d7c-5d2ae3327fe6' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'Payload')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'be299203-dd4e-41a6-8d7c-5d2ae3327fe6',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100006,
            'Payload',
            'Payload',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6a8312f0-25bb-4c15-87b2-3aecbd71c191' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'PerformedByUserID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6a8312f0-25bb-4c15-87b2-3aecbd71c191',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100007,
            'PerformedByUserID',
            'Performed By User ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'E1238F34-2837-EF11-86D4-6045BDEE16E6',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '04be4cfc-1ad6-4732-8f65-9a714ddd0475' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '04be4cfc-1ad6-4732-8f65-9a714ddd0475',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100008,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f09b9ae2-24fa-4156-9ef0-c35efe93e683' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f09b9ae2-24fa-4156-9ef0-c35efe93e683',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100009,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c054c723-85ee-4c33-91fe-8243a138c2e2' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c054c723-85ee-4c33-91fe-8243a138c2e2',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6378c610-1b62-4a54-a9a5-531b31195e4b' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6378c610-1b62-4a54-a9a5-531b31195e4b',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100002,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f0ca397d-b5db-413a-8b6a-61791c14cf3c' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'ScheduleType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f0ca397d-b5db-413a-8b6a-61791c14cf3c',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100003,
            'ScheduleType',
            'Schedule Type',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7bb3597d-7924-498d-9df1-2c3a65af2506' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'Frequency')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7bb3597d-7924-498d-9df1-2c3a65af2506',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100004,
            'Frequency',
            'Frequency',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5f63b7a6-fa5d-400b-8600-5de84f1a2c8f' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'AnchorDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5f63b7a6-fa5d-400b-8600-5de84f1a2c8f',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100005,
            'AnchorDate',
            'Anchor Date',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '79a127fb-9afa-43a5-8782-2960a639cbbd' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'IsActive')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '79a127fb-9afa-43a5-8782-2960a639cbbd',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100006,
            'IsActive',
            'Is Active',
            NULL,
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4f0a7f4f-bcce-4d14-80a5-ae6886d7255a' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = 'Notes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4f0a7f4f-bcce-4d14-80a5-ae6886d7255a',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100007,
            'Notes',
            'Notes',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5fe903ac-176a-42f3-b9eb-c570a28413cc' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5fe903ac-176a-42f3-b9eb-c570a28413cc',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100008,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'deafec2b-fbd2-4a47-aa01-5f82e49dfc11' OR (EntityID = '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'deafec2b-fbd2-4a47-aa01-5f82e49dfc11',
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', -- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
            100009,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b2bf790c-b5a1-4361-adfc-bbc267fc27c4' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b2bf790c-b5a1-4361-adfc-bbc267fc27c4',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '97f6ed2b-9391-4cb3-a832-7581a5c2a670' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ContractNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '97f6ed2b-9391-4cb3-a832-7581a5c2a670',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100002,
            'ContractNumber',
            'Contract Number',
            'CTR-{seq} from ContractSequence. Unique.',
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1cfd1d47-cbd0-4c4f-9dad-36c794d3e98b' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ContractTypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '1cfd1d47-cbd0-4c4f-9dad-36c794d3e98b',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100003,
            'ContractTypeID',
            'Contract Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9c5a5211-5038-48d2-9469-e5ca293661df' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CompanyID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9c5a5211-5038-48d2-9469-e5ca293661df',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100004,
            'CompanyID',
            'Company ID',
            'The SELLING company (${mjSchema}.Company) — which of our entities holds this agreement. Not the customer.',
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            'D4238F34-2837-EF11-86D4-6045BDEE16E6',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '924b0e51-c6ac-4b7d-a9c8-52796c481635' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CustomerOrganizationID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '924b0e51-c6ac-4b7d-a9c8-52796c481635',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100005,
            'CustomerOrganizationID',
            'Customer Organization ID',
            'The customer, when the customer is an organization. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'C70448F9-9792-41D7-A82C-784B66429D54',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5b103310-2f07-49c4-8566-e086d0af765c' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CustomerPersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5b103310-2f07-49c4-8566-e086d0af765c',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100006,
            'CustomerPersonID',
            'Customer Person ID',
            'The customer, when the customer is an individual. EXACTLY ONE of CustomerOrganizationID / CustomerPersonID is set, enforced by CK_Contract_CustomerXor.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd23140e8-c2b5-4c50-8b26-f88cdf1f84c4' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'PrimaryContactPersonID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd23140e8-c2b5-4c50-8b26-f88cdf1f84c4',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100007,
            'PrimaryContactPersonID',
            'Primary Contact Person ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b94f7e70-60b8-4c36-8a8d-63a1deaee6ee' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'OwnerUserID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b94f7e70-60b8-4c36-8a8d-63a1deaee6ee',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100008,
            'OwnerUserID',
            'Owner User ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'E1238F34-2837-EF11-86D4-6045BDEE16E6',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7c0a299f-2ec0-4027-83ef-c90cd25deec3' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ParentContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7c0a299f-2ec0-4027-83ef-c90cd25deec3',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100009,
            'ParentContractID',
            'Parent Contract ID',
            'Self-FK for MSA -> SOW nesting (D-5). Modelled as a self-reference rather than a distinct Agreement entity until the two genuinely diverge.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '82943343-8584-4023-9B36-385482D5DE51',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a361bbc5-5e49-4760-ba4c-690d681f5193' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'SupersededByContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a361bbc5-5e49-4760-ba4c-690d681f5193',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100010,
            'SupersededByContractID',
            'Superseded By Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '82943343-8584-4023-9B36-385482D5DE51',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2c8eb756-1674-4ce2-803b-6d28ef40e0cc' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2c8eb756-1674-4ce2-803b-6d28ef40e0cc',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100011,
            'Status',
            'Status',
            NULL,
            'nvarchar',
            60,
            0,
            0,
            0,
            'Draft',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9a15d20b-b303-4d41-93e1-4e0da640bcae' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9a15d20b-b303-4d41-93e1-4e0da640bcae',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100012,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd4a5bc73-1ce8-4995-b479-7deaab1749bf' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'EffectiveDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd4a5bc73-1ce8-4995-b479-7deaab1749bf',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100013,
            'EffectiveDate',
            'Effective Date',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4ff9dbd3-400e-4d9a-9626-46e9d5095f58' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ExecutedDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4ff9dbd3-400e-4d9a-9626-46e9d5095f58',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100014,
            'ExecutedDate',
            'Executed Date',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0f6e43f2-695d-4e69-b88e-4bd73d85d759' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'PricedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0f6e43f2-695d-4e69-b88e-4bd73d85d759',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100015,
            'PricedAt',
            'Priced At',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c110f119-3be2-4721-b9ff-aa03f17b21da' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'AutoRenew')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c110f119-3be2-4721-b9ff-aa03f17b21da',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100016,
            'AutoRenew',
            'Auto Renew',
            NULL,
            'bit',
            1,
            1,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2ade150b-8e93-4b91-8184-f4818dcb5aa2' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CancellationWindowDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2ade150b-8e93-4b91-8184-f4818dcb5aa2',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100017,
            'CancellationWindowDays',
            'Cancellation Window Days',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b99f3561-c05c-4944-b588-8601f5fc1d49' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'RenewalNoticeDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b99f3561-c05c-4944-b588-8601f5fc1d49',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100018,
            'RenewalNoticeDays',
            'Renewal Notice Days',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2b84b32c-5c57-4638-a29a-01e5b3274ab0' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'TerminationPolicy')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2b84b32c-5c57-4638-a29a-01e5b3274ab0',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100019,
            'TerminationPolicy',
            'Termination Policy',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a5cd3a5e-15aa-4292-afee-4f92d5e218ed' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ExternalReferenceID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a5cd3a5e-15aa-4292-afee-4f92d5e218ed',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100020,
            'ExternalReferenceID',
            'External Reference ID',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '86d43137-ddf1-4904-bdd3-d863ab791de3' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '86d43137-ddf1-4904-bdd3-d863ab791de3',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100021,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '05a2587b-9ab8-4641-aa44-ecffaa7a182a' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '05a2587b-9ab8-4641-aa44-ecffaa7a182a',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100022,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '40547b03-50b3-4544-8ba9-41909e98877c' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '40547b03-50b3-4544-8ba9-41909e98877c',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3a93db07-4153-4a92-a309-dcf493e2be02' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3a93db07-4153-4a92-a309-dcf493e2be02',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100002,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '13075643-d8d9-4bd2-b3c1-5a9ba7721e56' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'CommitmentType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '13075643-d8d9-4bd2-b3c1-5a9ba7721e56',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100003,
            'CommitmentType',
            'Commitment Type',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '99cf4832-aff4-4767-9883-9514145f4c70' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'CommittedAmount')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '99cf4832-aff4-4767-9883-9514145f4c70',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100004,
            'CommittedAmount',
            'Committed Amount',
            NULL,
            'decimal',
            9,
            19,
            4,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '82402057-8fbb-4b5a-9ea2-73acaa5c10da' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'ConsumedAmount')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '82402057-8fbb-4b5a-9ea2-73acaa5c10da',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100005,
            'ConsumedAmount',
            'Consumed Amount',
            NULL,
            'decimal',
            9,
            19,
            4,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2503dc68-ebed-43c4-bc8f-5be94e86761e' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'PeriodStart')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2503dc68-ebed-43c4-bc8f-5be94e86761e',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100006,
            'PeriodStart',
            'Period Start',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c73a8d68-96f8-43d9-bd60-e39970f2961d' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'PeriodEnd')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c73a8d68-96f8-43d9-bd60-e39970f2961d',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100007,
            'PeriodEnd',
            'Period End',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b4f22c43-094a-42e4-9e93-f390e8f08bd5' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'TrueUpPolicy')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b4f22c43-094a-42e4-9e93-f390e8f08bd5',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100008,
            'TrueUpPolicy',
            'True Up Policy',
            'What happens to an unconsumed minimum at period end: BillShortfall adds the gap to the next bill, Forfeit drops it, Rollover carries it forward.',
            'nvarchar',
            40,
            0,
            0,
            0,
            'BillShortfall',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0ea825c3-1b21-49ed-b115-a5662a68c909' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0ea825c3-1b21-49ed-b115-a5662a68c909',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100009,
            'Status',
            'Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            'Open',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9183dc62-b4a2-4783-816d-65f245a2b9c3' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9183dc62-b4a2-4783-816d-65f245a2b9c3',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100010,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '18c4f45a-f07e-4b69-bfc4-925dacfd07aa' OR (EntityID = '4342D779-6F68-4F94-9067-4F12C8E1D25B' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '18c4f45a-f07e-4b69-bfc4-925dacfd07aa',
            '4342D779-6F68-4F94-9067-4F12C8E1D25B', -- Entity: MJ_BizApps_Contracts: Contract Commitments
            100011,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2e51f970-6edb-4bd3-924c-d91ff9fcb760' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2e51f970-6edb-4bd3-924c-d91ff9fcb760',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ae905c35-92ed-407b-8e21-8fe119c30971' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'Code')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ae905c35-92ed-407b-8e21-8fe119c30971',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100002,
            'Code',
            'Code',
            'Stable machine key, unique. Referenced by CloseWonPolicy in bizapps-sales, so renaming Name is safe and changing Code is not.',
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'aa0c9fe4-73f0-4a7b-a350-cbf3fe90ec54' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'Name')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'aa0c9fe4-73f0-4a7b-a350-cbf3fe90ec54',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100003,
            'Name',
            'Name',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            1,
            1,
            0,
            1,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '30579ad1-85a7-44be-af99-44f69fe898b2' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '30579ad1-85a7-44be-af99-44f69fe898b2',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100004,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2fa118b-c007-4e3e-a667-4bb480ebcb73' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultTermMonths')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e2fa118b-c007-4e3e-a667-4bb480ebcb73',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100005,
            'DefaultTermMonths',
            'Default Term Months',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '573c3eb2-e613-4b4f-87fb-deaebfb9fa48' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultBillingFrequency')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '573c3eb2-e613-4b4f-87fb-deaebfb9fa48',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100006,
            'DefaultBillingFrequency',
            'Default Billing Frequency',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'be7a1604-32fa-4816-a7cd-71cff9287ed7' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultAutoRenew')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'be7a1604-32fa-4816-a7cd-71cff9287ed7',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100007,
            'DefaultAutoRenew',
            'Default Auto Renew',
            NULL,
            'bit',
            1,
            1,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7ea2d3e4-47f0-4690-b129-455be3e3ff4e' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'RequiresSignature')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7ea2d3e4-47f0-4690-b129-455be3e3ff4e',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100008,
            'RequiresSignature',
            'Requires Signature',
            NULL,
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1f8049ac-13ee-42d5-a54b-c67a424cf2af' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultEscalationPercent')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '1f8049ac-13ee-42d5-a54b-c67a424cf2af',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100009,
            'DefaultEscalationPercent',
            'Default Escalation Percent',
            NULL,
            'decimal',
            5,
            7,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '15fd17ad-fa12-4d52-b810-612fb1f5a959' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultMaxEscalationPercent')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '15fd17ad-fa12-4d52-b810-612fb1f5a959',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100010,
            'DefaultMaxEscalationPercent',
            'Default Max Escalation Percent',
            NULL,
            'decimal',
            5,
            7,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5341cd38-ad00-4a3a-8b28-3b4d671ea023' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultRenewalNoticeDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5341cd38-ad00-4a3a-8b28-3b4d671ea023',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100011,
            'DefaultRenewalNoticeDays',
            'Default Renewal Notice Days',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '35b792f0-e6c7-47ee-b12b-0057c0232112' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DefaultCancellationWindowDays')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '35b792f0-e6c7-47ee-b12b-0057c0232112',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100012,
            'DefaultCancellationWindowDays',
            'Default Cancellation Window Days',
            NULL,
            'int',
            4,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b5a05df5-2e80-476e-a97a-311d49f64c11' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'RenewalMode')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b5a05df5-2e80-476e-a97a-311d49f64c11',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100013,
            'RenewalMode',
            'Renewal Mode',
            'How a term of this type renews. Deal = a renewal is a deal (L-18); bizapps-sales calls Contracts.RenewTerm when a renewal deal closes, so renewal gets its own pipeline and win-rate. Auto = the Scheduled Job renews with no deal, for evergreen and B2C. Manual = a human triggers it.',
            'nvarchar',
            40,
            0,
            0,
            0,
            'Deal',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '05344cc0-9151-4868-90f4-f027dab533a6' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'AllowsCoterm')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '05344cc0-9151-4868-90f4-f027dab533a6',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100014,
            'AllowsCoterm',
            'Allows Coterm',
            'Whether a term of this type may absorb a mid-term addition aligned to the term end date (co-terming).',
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '787a0724-a9d0-4143-83d2-57ad23c5b29c' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'DriverClass')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '787a0724-a9d0-4143-83d2-57ad23c5b29c',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100015,
            'DriverClass',
            'Driver Class',
            'OPTIONAL ClassFactory key for a behaviour subclass, following SubscriptionType rather than RevenueRecognitionType: the columns ARE the rules and a base class reads them. Supply a driver only when a customer needs something the columns cannot express.',
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '152e784d-b711-486c-a9f5-6147f9c18fb2' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = 'IsActive')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '152e784d-b711-486c-a9f5-6147f9c18fb2',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100016,
            'IsActive',
            'Is Active',
            NULL,
            'bit',
            1,
            1,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3adb9559-ecb9-4323-b197-97afbf37b105' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3adb9559-ecb9-4323-b197-97afbf37b105',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100017,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b572e926-887e-44f5-95fe-611b3d25c757' OR (EntityID = '626148EC-40A2-4A28-B4DA-7B7564A3AE9C' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b572e926-887e-44f5-95fe-611b3d25c757',
            '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', -- Entity: MJ_BizApps_Contracts: Contract Types
            100018,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a5738892-1375-4ccc-adce-0cf0c19024bb' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a5738892-1375-4ccc-adce-0cf0c19024bb',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7f5704a2-4286-4807-8b3f-4a092ef05498' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'ContractBillingScheduleID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7f5704a2-4286-4807-8b3f-4a092ef05498',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100002,
            'ContractBillingScheduleID',
            'Contract Billing Schedule ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '73fbe2b4-98e6-416e-8a5a-b6ae6bc29997' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '73fbe2b4-98e6-416e-8a5a-b6ae6bc29997',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100003,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '652051a7-0e36-44c1-89f7-10bdf9e275ac' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'ScheduledDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '652051a7-0e36-44c1-89f7-10bdf9e275ac',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100004,
            'ScheduledDate',
            'Scheduled Date',
            NULL,
            'date',
            3,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b75e25a6-9fff-481d-80d4-3722190f2159' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b75e25a6-9fff-481d-80d4-3722190f2159',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100005,
            'Status',
            'Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            'Scheduled',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ddf7f58a-dc1e-4f10-87a6-b605d7d48604' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'OrderID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ddf7f58a-dc1e-4f10-87a6-b605d7d48604',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100006,
            'OrderID',
            'Order ID',
            'The ONE consolidated order this event produced, via Orders.CreateOrderInState. A legal downward reference: contracts sits above orders. Status=Generated requires it, which is what makes the status transition a real idempotency guard.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'B75D0AA7-CE6B-4016-93D7-46963829348C',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '38aba4fa-144d-410f-9668-58b572c0c1b1' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'ComputedAmount')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '38aba4fa-144d-410f-9668-58b572c0c1b1',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100007,
            'ComputedAmount',
            'Computed Amount',
            'A STAMP of the total Orders.PreviewOrder returned — never a figure computed in this app. Contracts decides WHAT to bill and never what it costs.',
            'decimal',
            9,
            19,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '480c93a1-b2c1-4805-9485-7316faee5f10' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'GeneratedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '480c93a1-b2c1-4805-9485-7316faee5f10',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100008,
            'GeneratedAt',
            'Generated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '84efc69f-fdf2-4738-81a4-48b752016bb6' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'FailureReason')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '84efc69f-fdf2-4738-81a4-48b752016bb6',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100009,
            'FailureReason',
            'Failure Reason',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b59c2d0c-74a8-4930-8a00-689edc17c24c' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'Notes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b59c2d0c-74a8-4930-8a00-689edc17c24c',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100010,
            'Notes',
            'Notes',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f41f9fce-9cbe-4654-bc8d-6433c7c9f025' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f41f9fce-9cbe-4654-bc8d-6433c7c9f025',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100011,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f1283e7d-32e3-48bd-ba8f-a659e448d43d' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f1283e7d-32e3-48bd-ba8f-a659e448d43d',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100012,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '0a4eff58-f36c-44a3-a713-4d92dab99fd4' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '0a4eff58-f36c-44a3-a713-4d92dab99fd4',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c5fe0349-06d7-488e-abe1-cfa10fb810bc' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c5fe0349-06d7-488e-abe1-cfa10fb810bc',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100002,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5fc78a64-e9ff-4a0d-9397-2deb59cc4cc9' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'ProductID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5fc78a64-e9ff-4a0d-9397-2deb59cc4cc9',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100003,
            'ProductID',
            'Product ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '568562E1-B52B-4EDD-968F-3F7C6A072826',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8c5c1f32-3614-442f-9494-f873f41ebd15' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'LineType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8c5c1f32-3614-442f-9494-f873f41ebd15',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100004,
            'LineType',
            'Line Type',
            'Subscription | OneTime | Milestone | Usage | Minimum. Usage is present in the value list although usage metering is out of v1, so the schema need not change when metering arrives.',
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd5de614d-e87f-45c2-8722-088ee0ea8332' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'Quantity')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd5de614d-e87f-45c2-8722-088ee0ea8332',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100005,
            'Quantity',
            'Quantity',
            NULL,
            'decimal',
            9,
            18,
            4,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f4c69ed0-48c4-4031-aaab-590c29fdd22a' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'ContractedUnitPrice')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f4c69ed0-48c4-4031-aaab-590c29fdd22a',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100006,
            'ContractedUnitPrice',
            'Contracted Unit Price',
            'The negotiated per-unit price. NULL means RESOLVE NORMALLY — the line is covered by the agreement but priced from the catalog. A non-null value is what ContractPriceResolver returns into orders'' pricing walk; escalation is applied by the resolver at billing time, not stored here.',
            'decimal',
            9,
            19,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9e6ecb73-b692-444c-b871-2ceb4090f7e0' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'DiscountPct')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9e6ecb73-b692-444c-b871-2ceb4090f7e0',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100007,
            'DiscountPct',
            'Discount Pct',
            NULL,
            'decimal',
            5,
            7,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '490fd8be-2e62-4dd3-ab9a-cc3a91150f95' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'StartDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '490fd8be-2e62-4dd3-ab9a-cc3a91150f95',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100008,
            'StartDate',
            'Start Date',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '864fa431-48df-4ad4-bee9-6a26a5815554' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'EndDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '864fa431-48df-4ad4-bee9-6a26a5815554',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100009,
            'EndDate',
            'End Date',
            'Co-term stubs live here: a line added mid-term starts at the amendment date and ends at the TERM''s end date, so the stub prorates on the next billing event. This is the capability standalone subscriptions structurally cannot provide, and the reason the contract owns the calendar.',
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '323ebbb1-20e4-45d7-9cb2-8c0044ca9f2d' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'SubscriptionTypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '323ebbb1-20e4-45d7-9cb2-8c0044ca9f2d',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100010,
            'SubscriptionTypeID',
            'Subscription Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '71C6C278-AE4E-4403-9D6B-CC2B5D66CD0D',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '138d0ec7-3fc8-43ed-82b6-1a28589360fc' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'SubscriptionID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '138d0ec7-3fc8-43ed-82b6-1a28589360fc',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100011,
            'SubscriptionID',
            'Subscription ID',
            'The materialized orders Subscription for a LineType=Subscription line. This linkage lives HERE and points up the graph: orders never learns the word "contract", only that the subscription''s BillingMode is External so SpawnRenewals skips it.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'C3DC9D6D-6023-41DA-95C9-64EFF8D7E594',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8f556fce-3a6f-4941-84c1-2fde7c24221a' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8f556fce-3a6f-4941-84c1-2fde7c24221a',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100012,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6f8b79ea-d041-4178-b135-19ea9cd6a4ec' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'DisplayOrder')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6f8b79ea-d041-4178-b135-19ea9cd6a4ec',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100013,
            'DisplayOrder',
            'Display Order',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            '(0)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '55b4704f-8a55-4dc9-b7e4-ddd5e29d14ee' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '55b4704f-8a55-4dc9-b7e4-ddd5e29d14ee',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100014,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5b46c7d7-b732-4e65-aab6-4a0929899716' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5b46c7d7-b732-4e65-aab6-4a0929899716',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100015,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c200cd09-19d0-446e-bc53-8c5b79a2cb71' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c200cd09-19d0-446e-bc53-8c5b79a2cb71',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '30a7b5fd-7549-4bc1-a9b7-798cad7589c3' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'ContractTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '30a7b5fd-7549-4bc1-a9b7-798cad7589c3',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100002,
            'ContractTermID',
            'Contract Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '7b450c39-30c3-40cd-a67e-811475ea5c5a' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'AmendmentNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '7b450c39-30c3-40cd-a67e-811475ea5c5a',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100003,
            'AmendmentNumber',
            'Amendment Number',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'fc73947d-35a0-4d14-8a11-aff339f7f4a2' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'EffectiveDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'fc73947d-35a0-4d14-8a11-aff339f7f4a2',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100004,
            'EffectiveDate',
            'Effective Date',
            NULL,
            'date',
            3,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '33496713-a2d3-4390-9e5e-3dec9d3d3ad4' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'AmendmentType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '33496713-a2d3-4390-9e5e-3dec9d3d3ad4',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100005,
            'AmendmentType',
            'Amendment Type',
            NULL,
            'nvarchar',
            60,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '684cf642-024a-4ed6-85ba-d5a5ec9e8cae' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'Description')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '684cf642-024a-4ed6-85ba-d5a5ec9e8cae',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100006,
            'Description',
            'Description',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c5a40bd6-4c2b-42c9-943f-d8630abc8875' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c5a40bd6-4c2b-42c9-943f-d8630abc8875',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100007,
            'Status',
            'Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            'Draft',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1a7eac5d-f0cd-46fb-bed8-7ae62c2f5855' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'ApprovalTaskID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '1a7eac5d-f0cd-46fb-bed8-7ae62c2f5855',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100008,
            'ApprovalTaskID',
            'Approval Task ID',
            'The bizapps-tasks Task gating this amendment. Raised for non-standard terms, discounts beyond a rep''s SalesAuthority, and early-termination waivers; TaskType OnComplete/OnReject hooks call back into contracts to advance or reject.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'e2add054-31c8-42d2-8042-117d2870c215' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'e2add054-31c8-42d2-8042-117d2870c215',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100009,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5152ec25-06fe-400c-ad0c-9ad0c22e66e8' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5152ec25-06fe-400c-ad0c-9ad0c22e66e8',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100010,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '5ef200b6-b365-452b-aec5-3826bb50f4c4' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '5ef200b6-b365-452b-aec5-3826bb50f4c4',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100001,
            'ID',
            'ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            'newsequentialid()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '096058ad-c3f3-4de6-a353-7a21e0a03123' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'ContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '096058ad-c3f3-4de6-a353-7a21e0a03123',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100002,
            'ContractID',
            'Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            '82943343-8584-4023-9B36-385482D5DE51',
            'ID',
            0,
            0,
            1,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '523176cc-922f-4a4c-8b61-aa80a9c5450d' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'TermNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '523176cc-922f-4a4c-8b61-aa80a9c5450d',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100003,
            'TermNumber',
            'Term Number',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ae8bcc8c-1b39-4fcd-af56-7ccdd4fec64c' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'StartDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ae8bcc8c-1b39-4fcd-af56-7ccdd4fec64c',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100004,
            'StartDate',
            'Start Date',
            NULL,
            'date',
            3,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ef0de314-992f-47af-85f5-75f55e59e1ad' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'EndDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ef0de314-992f-47af-85f5-75f55e59e1ad',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100005,
            'EndDate',
            'End Date',
            NULL,
            'date',
            3,
            10,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '076b2674-f5c5-4221-a79e-f508ff727085' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'Status')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '076b2674-f5c5-4221-a79e-f508ff727085',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100006,
            'Status',
            'Status',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            'Pending',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd9fb32af-7181-4264-8060-6da4ba6c5d0f' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'RenewalOfTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd9fb32af-7181-4264-8060-6da4ba6c5d0f',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100007,
            'RenewalOfTermID',
            'Renewal Of Term ID',
            'Self-FK chaining back to the term this one renewed, making the renewal history navigable without a separate lineage table.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '47e10e6f-efc8-42c8-9c3b-add59582ef00' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'CommittedAmount')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '47e10e6f-efc8-42c8-9c3b-add59582ef00',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100008,
            'CommittedAmount',
            'Committed Amount',
            NULL,
            'decimal',
            9,
            19,
            4,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '960de48a-99e0-4cff-8d4c-83f383a92118' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'EscalationPercent')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '960de48a-99e0-4cff-8d4c-83f383a92118',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100009,
            'EscalationPercent',
            'Escalation Percent',
            'The rate increase applied at renewal, per EscalationBasis. Applied BY THE RESOLVER at billing time from the term rules — never baked into stored line prices, which then go stale.',
            'decimal',
            5,
            7,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '37a79fa1-3427-4085-aca8-ae791d8287bb' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'EscalationBasis')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '37a79fa1-3427-4085-aca8-ae791d8287bb',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100010,
            'EscalationBasis',
            'Escalation Basis',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ead9163d-1f30-4b55-a47c-adbca80c080c' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'BillingFrequency')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ead9163d-1f30-4b55-a47c-adbca80c080c',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100011,
            'BillingFrequency',
            'Billing Frequency',
            NULL,
            'nvarchar',
            40,
            0,
            0,
            0,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a6639580-3aa8-463f-8118-816c24053dcd' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'BillingAnchorMonth')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a6639580-3aa8-463f-8118-816c24053dcd',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100012,
            'BillingAnchorMonth',
            'Billing Anchor Month',
            NULL,
            'tinyint',
            1,
            3,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '38cd1e0f-9887-4767-8896-55924a391363' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'BillingAnchorDay')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '38cd1e0f-9887-4767-8896-55924a391363',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100013,
            'BillingAnchorDay',
            'Billing Anchor Day',
            NULL,
            'tinyint',
            1,
            3,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '1afa5b6c-0fb7-4692-9eda-1aa510827d8b' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'PaymentTermsTypeID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '1afa5b6c-0fb7-4692-9eda-1aa510827d8b',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100014,
            'PaymentTermsTypeID',
            'Payment Terms Type ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '6715E631-D59E-45FF-8421-F813B720C214',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'dc59fd42-285b-491c-94f1-d4fd0b68cbe0' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'CurrencyID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'dc59fd42-285b-491c-94f1-d4fd0b68cbe0',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100015,
            'CurrencyID',
            'Currency ID',
            'Recorded for forward-compatibility ONLY. Orders defers FX (D24) and nothing in this app converts between currencies. It exists so a term states the currency it was written in, rather than that being inferred from the selling company years later.',
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            '3D32E9E8-6BDB-4FED-B8A2-9AD27714B0FB',
            'ID',
            0,
            0,
            1,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd5078949-adf0-4736-9082-44c44e18b04f' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'EarlyTerminationDate')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd5078949-adf0-4736-9082-44c44e18b04f',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100016,
            'EarlyTerminationDate',
            'Early Termination Date',
            NULL,
            'date',
            3,
            10,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3746d894-d3e0-4ec2-8175-6f7f2971e298' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'RenewalProbability')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3746d894-d3e0-4ec2-8175-6f7f2971e298',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100017,
            'RenewalProbability',
            'Renewal Probability',
            '0..1 likelihood this term renews. Exists because a renewal forecast in bizapps-sales reads it.',
            'decimal',
            5,
            5,
            4,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd0773516-259d-4c44-882f-ed0e8bab8f7a' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'Notes')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd0773516-259d-4c44-882f-ed0e8bab8f7a',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100018,
            'Notes',
            'Notes',
            NULL,
            'nvarchar',
            -1,
            0,
            0,
            1,
            NULL,
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '9d0fc4da-3d63-48a0-bc3d-344033addb59' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '9d0fc4da-3d63-48a0-bc3d-344033addb59',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100019,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '69a4827a-7c79-47ad-b704-c939fd0ef028' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '69a4827a-7c79-47ad-b704-c939fd0ef028',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100020,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'bacf88df-aa56-4020-9910-55f9a17e945f' OR (EntityID = 'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655' AND Name = 'ID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'bacf88df-aa56-4020-9910-55f9a17e945f',
            'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            100001,
            'ID',
            'ID',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            '(1)',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            1,
            0,
            0,
            1,
            1,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6cae07b5-b81b-4ac2-a388-f5b14d3779f9' OR (EntityID = 'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655' AND Name = 'NextSequenceNumber')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6cae07b5-b81b-4ac2-a388-f5b14d3779f9',
            'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            100002,
            'NextSequenceNumber',
            'Next Sequence Number',
            NULL,
            'int',
            4,
            10,
            0,
            0,
            '(1)',
            0,
            1,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f95127da-91b5-4d1b-b5ee-4d3aa8cfb473' OR (EntityID = 'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655' AND Name = '__mj_CreatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f95127da-91b5-4d1b-b5ee-4d3aa8cfb473',
            'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            100003,
            '__mj_CreatedAt',
            'Created At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'c36e471f-a10d-4da6-9fc5-65d5e54809cb' OR (EntityID = 'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655' AND Name = '__mj_UpdatedAt')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'c36e471f-a10d-4da6-9fc5-65d5e54809cb',
            'E2F30CEA-CABB-490C-9FDA-E0F89F1DB655', -- Entity: MJ_BizApps_Contracts: Contract Sequences
            100004,
            '__mj_UpdatedAt',
            'Updated At',
            NULL,
            'datetimeoffset',
            10,
            34,
            7,
            0,
            'getutcdate()',
            0,
            0,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to insert entity field value with ID 6809d913-090f-478f-b613-7b4792d95f2e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('6809d913-090f-478f-b613-7b4792d95f2e', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 1, 'Annual', 'Annual', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b670d9d9-66e5-4e87-8ea9-7789e601b9f3 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b670d9d9-66e5-4e87-8ea9-7789e601b9f3', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 2, 'Custom', 'Custom', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID a273f96a-d9ca-4297-b0a3-8e873d5118d1 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('a273f96a-d9ca-4297-b0a3-8e873d5118d1', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 3, 'Milestone', 'Milestone', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 9dedab50-1fb0-48dd-a24c-75bc67ef3a39 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('9dedab50-1fb0-48dd-a24c-75bc67ef3a39', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 4, 'Monthly', 'Monthly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID e05ded3e-6cb3-4a9a-a8e6-666bac0f7196 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('e05ded3e-6cb3-4a9a-a8e6-666bac0f7196', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 5, 'Quarterly', 'Quarterly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 51e474b7-e022-4a39-a7f4-6c08c93ad13b */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('51e474b7-e022-4a39-a7f4-6c08c93ad13b', '573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48', 6, 'SemiAnnual', 'SemiAnnual', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='573C3EB2-E613-4B4F-87FB-DEAEBFB9FA48';

/* SQL text to insert entity field value with ID 7b49b9be-8b57-4474-8a76-04213b0f4f42 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('7b49b9be-8b57-4474-8a76-04213b0f4f42', 'B5A05DF5-2E80-476E-A97A-311D49F64C11', 1, 'Auto', 'Auto', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID c69eb172-f9ef-434c-9bfd-147f290b92eb */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('c69eb172-f9ef-434c-9bfd-147f290b92eb', 'B5A05DF5-2E80-476E-A97A-311D49F64C11', 2, 'Deal', 'Deal', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 1345430b-ef17-46e6-afaa-b4c6b179f3e6 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('1345430b-ef17-46e6-afaa-b4c6b179f3e6', 'B5A05DF5-2E80-476E-A97A-311D49F64C11', 3, 'Manual', 'Manual', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID B5A05DF5-2E80-476E-A97A-311D49F64C11 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='B5A05DF5-2E80-476E-A97A-311D49F64C11';

/* SQL text to insert entity field value with ID 9d0ec3bd-22ce-47e8-8f84-02ccc00f0ea9 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('9d0ec3bd-22ce-47e8-8f84-02ccc00f0ea9', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 0d9c880c-2161-4710-8a93-4fc86a2f3885 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0d9c880c-2161-4710-8a93-4fc86a2f3885', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 2, 'Draft', 'Draft', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 7ba93156-8139-4695-afb5-a74158e4ba4b */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('7ba93156-8139-4695-afb5-a74158e4ba4b', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 3, 'Expired', 'Expired', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 466277ea-38ce-4456-a909-e26afc23c1f6 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('466277ea-38ce-4456-a909-e26afc23c1f6', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 4, 'PendingSignature', 'PendingSignature', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 3fb09702-c528-4d82-a6ae-a86f8518adb7 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('3fb09702-c528-4d82-a6ae-a86f8518adb7', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 5, 'Superseded', 'Superseded', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID db3d2dcb-f85d-432e-804b-993eb42f3b18 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('db3d2dcb-f85d-432e-804b-993eb42f3b18', '2C8EB756-1674-4CE2-803B-6D28EF40E0CC', 6, 'Terminated', 'Terminated', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 2C8EB756-1674-4CE2-803B-6D28EF40E0CC */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='2C8EB756-1674-4CE2-803B-6D28EF40E0CC';

/* SQL text to insert entity field value with ID f985a157-161c-4c58-94bb-8c9b3843c734 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f985a157-161c-4c58-94bb-8c9b3843c734', '076B2674-F5C5-4221-A79E-F508FF727085', 1, 'Active', 'Active', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 80035210-667e-4b47-91c8-70c2167d556f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('80035210-667e-4b47-91c8-70c2167d556f', '076B2674-F5C5-4221-A79E-F508FF727085', 2, 'Completed', 'Completed', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b3108ac6-010d-42b6-b93e-89845f9ea6f5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b3108ac6-010d-42b6-b93e-89845f9ea6f5', '076B2674-F5C5-4221-A79E-F508FF727085', 3, 'Pending', 'Pending', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 138fe269-c83e-4b8a-8189-64ab8a732eef */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('138fe269-c83e-4b8a-8189-64ab8a732eef', '076B2674-F5C5-4221-A79E-F508FF727085', 4, 'PendingSignature', 'PendingSignature', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID c26f2ac5-9b76-43d2-83a0-3183f9f701f4 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('c26f2ac5-9b76-43d2-83a0-3183f9f701f4', '076B2674-F5C5-4221-A79E-F508FF727085', 5, 'Terminated', 'Terminated', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 076B2674-F5C5-4221-A79E-F508FF727085 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='076B2674-F5C5-4221-A79E-F508FF727085';

/* SQL text to insert entity field value with ID 61357825-c03c-4718-989e-a60b59b8d1a5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('61357825-c03c-4718-989e-a60b59b8d1a5', '37A79FA1-3427-4085-ACA8-AE791D8287BB', 1, 'Index', 'Index', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 0698fbd6-1176-4b34-9baa-63f8a9779f7c */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0698fbd6-1176-4b34-9baa-63f8a9779f7c', '37A79FA1-3427-4085-ACA8-AE791D8287BB', 2, 'ListPrice', 'ListPrice', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 35481033-9b0e-4718-844a-65eb3f71ac84 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('35481033-9b0e-4718-844a-65eb3f71ac84', '37A79FA1-3427-4085-ACA8-AE791D8287BB', 3, 'PriorTerm', 'PriorTerm', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 37A79FA1-3427-4085-ACA8-AE791D8287BB */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='37A79FA1-3427-4085-ACA8-AE791D8287BB';

/* SQL text to insert entity field value with ID 71d3d187-3039-4db0-a5d4-92b097faafe5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('71d3d187-3039-4db0-a5d4-92b097faafe5', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 1, 'Annual', 'Annual', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 7943f518-6b10-4726-ae9f-216bbba276b3 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('7943f518-6b10-4726-ae9f-216bbba276b3', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 2, 'Custom', 'Custom', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 4cbd04dd-20b9-4c06-b832-fa639b3e0849 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('4cbd04dd-20b9-4c06-b832-fa639b3e0849', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 3, 'Milestone', 'Milestone', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 964f8ba4-33e1-48d6-a933-ec674b28ebb3 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('964f8ba4-33e1-48d6-a933-ec674b28ebb3', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 4, 'Monthly', 'Monthly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 84072859-c4db-4c6d-a861-f9c090e42da1 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('84072859-c4db-4c6d-a861-f9c090e42da1', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 5, 'Quarterly', 'Quarterly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b5d74902-8777-4365-8cf2-cc79d59f2dbf */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b5d74902-8777-4365-8cf2-cc79d59f2dbf', 'EAD9163D-1F30-4B55-A47C-ADBCA80C080C', 6, 'SemiAnnual', 'SemiAnnual', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID EAD9163D-1F30-4B55-A47C-ADBCA80C080C */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='EAD9163D-1F30-4B55-A47C-ADBCA80C080C';

/* SQL text to insert entity field value with ID a660aa36-ab33-4dc9-b957-154b74eed071 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('a660aa36-ab33-4dc9-b957-154b74eed071', '8C5C1F32-3614-442F-9494-F873F41EBD15', 1, 'Milestone', 'Milestone', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f51b3d45-0135-4621-bb0e-89474e36e499 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f51b3d45-0135-4621-bb0e-89474e36e499', '8C5C1F32-3614-442F-9494-F873F41EBD15', 2, 'Minimum', 'Minimum', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 0e7a6a5c-74b2-4ccc-8c5e-77292f9e7f24 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0e7a6a5c-74b2-4ccc-8c5e-77292f9e7f24', '8C5C1F32-3614-442F-9494-F873F41EBD15', 3, 'OneTime', 'OneTime', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 58560b95-7906-46be-a11b-aa15029692c7 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('58560b95-7906-46be-a11b-aa15029692c7', '8C5C1F32-3614-442F-9494-F873F41EBD15', 4, 'Subscription', 'Subscription', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 65241ac2-de9c-4538-8a83-b92bd446fe9d */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('65241ac2-de9c-4538-8a83-b92bd446fe9d', '8C5C1F32-3614-442F-9494-F873F41EBD15', 5, 'Usage', 'Usage', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 8C5C1F32-3614-442F-9494-F873F41EBD15 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='8C5C1F32-3614-442F-9494-F873F41EBD15';

/* SQL text to insert entity field value with ID 0a9c4f0b-9abf-4c15-b872-706abe619702 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0a9c4f0b-9abf-4c15-b872-706abe619702', 'F0CA397D-B5DB-413A-8B6A-61791C14CF3C', 1, 'Cadence', 'Cadence', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID c853d2cd-2586-46ea-82ee-1cd3e812f09f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('c853d2cd-2586-46ea-82ee-1cd3e812f09f', 'F0CA397D-B5DB-413A-8B6A-61791C14CF3C', 2, 'Custom', 'Custom', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 9580c5f2-abb5-435f-82e2-d163a812bdc7 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('9580c5f2-abb5-435f-82e2-d163a812bdc7', 'F0CA397D-B5DB-413A-8B6A-61791C14CF3C', 3, 'Milestone', 'Milestone', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID F0CA397D-B5DB-413A-8B6A-61791C14CF3C */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='F0CA397D-B5DB-413A-8B6A-61791C14CF3C';

/* SQL text to insert entity field value with ID 6d8e5629-e848-4d2d-8845-995424eec661 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('6d8e5629-e848-4d2d-8845-995424eec661', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 1, 'Annual', 'Annual', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID c22554b6-dfe3-4213-968b-1accfd821b04 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('c22554b6-dfe3-4213-968b-1accfd821b04', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 2, 'Custom', 'Custom', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 598f8c63-a1d9-4590-adbb-156f33ef754d */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('598f8c63-a1d9-4590-adbb-156f33ef754d', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 3, 'Milestone', 'Milestone', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 8fabd9da-c23e-412d-b3af-fedc5a57fcf1 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('8fabd9da-c23e-412d-b3af-fedc5a57fcf1', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 4, 'Monthly', 'Monthly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 7b203a76-50bb-4454-a547-35ffc0b0c785 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('7b203a76-50bb-4454-a547-35ffc0b0c785', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 5, 'Quarterly', 'Quarterly', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 0948d454-f4e0-4cf7-bc25-8f4945b91012 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0948d454-f4e0-4cf7-bc25-8f4945b91012', '7BB3597D-7924-498D-9DF1-2C3A65AF2506', 6, 'SemiAnnual', 'SemiAnnual', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 7BB3597D-7924-498D-9DF1-2C3A65AF2506 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='7BB3597D-7924-498D-9DF1-2C3A65AF2506';

/* SQL text to insert entity field value with ID ac11790c-906a-461f-8e38-f61062d731d5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ac11790c-906a-461f-8e38-f61062d731d5', 'B75E25A6-9FFF-481D-80D4-3722190F2159', 1, 'Cancelled', 'Cancelled', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 3c71e044-c982-48b1-a90c-8c6e3fd6aa35 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('3c71e044-c982-48b1-a90c-8c6e3fd6aa35', 'B75E25A6-9FFF-481D-80D4-3722190F2159', 2, 'Failed', 'Failed', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b0b8e99f-0199-45c5-83bb-2f611b129420 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b0b8e99f-0199-45c5-83bb-2f611b129420', 'B75E25A6-9FFF-481D-80D4-3722190F2159', 3, 'Generated', 'Generated', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 55980484-7b57-4a6f-89c4-34789319f290 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('55980484-7b57-4a6f-89c4-34789319f290', 'B75E25A6-9FFF-481D-80D4-3722190F2159', 4, 'Scheduled', 'Scheduled', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 9c4178ef-5713-48b9-af3d-d7ee147b5ab5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('9c4178ef-5713-48b9-af3d-d7ee147b5ab5', 'B75E25A6-9FFF-481D-80D4-3722190F2159', 5, 'Skipped', 'Skipped', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID B75E25A6-9FFF-481D-80D4-3722190F2159 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='B75E25A6-9FFF-481D-80D4-3722190F2159';

/* SQL text to insert entity field value with ID ab33df47-c914-456c-9326-b6afde19722f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ab33df47-c914-456c-9326-b6afde19722f', '13075643-D8D9-4BD2-B3C1-5A9BA7721E56', 1, 'Draw', 'Draw', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 23740d1d-674c-40e5-8c57-e629dc53a47b */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('23740d1d-674c-40e5-8c57-e629dc53a47b', '13075643-D8D9-4BD2-B3C1-5A9BA7721E56', 2, 'Minimum', 'Minimum', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f2035df9-9e5d-40ea-a497-5af92aab4840 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f2035df9-9e5d-40ea-a497-5af92aab4840', '13075643-D8D9-4BD2-B3C1-5A9BA7721E56', 3, 'Prepaid', 'Prepaid', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 13075643-D8D9-4BD2-B3C1-5A9BA7721E56 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='13075643-D8D9-4BD2-B3C1-5A9BA7721E56';

/* SQL text to insert entity field value with ID 55d9b540-1c58-4844-8089-ed7bb2c1c288 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('55d9b540-1c58-4844-8089-ed7bb2c1c288', 'B4F22C43-094A-42E4-9E93-F390E8F08BD5', 1, 'BillShortfall', 'BillShortfall', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 5508d1cb-91eb-4689-ab9b-223ad1e0a1e5 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('5508d1cb-91eb-4689-ab9b-223ad1e0a1e5', 'B4F22C43-094A-42E4-9E93-F390E8F08BD5', 2, 'Forfeit', 'Forfeit', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID d711a8ba-41ec-4b10-b5d0-c765f24ce669 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('d711a8ba-41ec-4b10-b5d0-c765f24ce669', 'B4F22C43-094A-42E4-9E93-F390E8F08BD5', 3, 'Rollover', 'Rollover', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID B4F22C43-094A-42E4-9E93-F390E8F08BD5 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='B4F22C43-094A-42E4-9E93-F390E8F08BD5';

/* SQL text to insert entity field value with ID d8f08aa6-0932-4e17-8b70-d2d90e66230a */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('d8f08aa6-0932-4e17-8b70-d2d90e66230a', '0EA825C3-1B21-49ED-B115-A5662A68C909', 1, 'Closed', 'Closed', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID ef35a7fd-27c2-4d18-a259-cc9114792525 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ef35a7fd-27c2-4d18-a259-cc9114792525', '0EA825C3-1B21-49ED-B115-A5662A68C909', 2, 'Forfeited', 'Forfeited', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 92ae2955-5b19-48a7-b09e-17ba1461e755 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('92ae2955-5b19-48a7-b09e-17ba1461e755', '0EA825C3-1B21-49ED-B115-A5662A68C909', 3, 'Open', 'Open', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 60b21aca-0721-496d-8ba1-5248aa6f4c2e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('60b21aca-0721-496d-8ba1-5248aa6f4c2e', '0EA825C3-1B21-49ED-B115-A5662A68C909', 4, 'TruedUp', 'TruedUp', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 0EA825C3-1B21-49ED-B115-A5662A68C909 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='0EA825C3-1B21-49ED-B115-A5662A68C909';

/* SQL text to insert entity field value with ID 2b379a59-d197-49ac-a631-445d57485015 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('2b379a59-d197-49ac-a631-445d57485015', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 1, 'AddProduct', 'AddProduct', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID de6ff9cf-0d6b-40b1-89d1-82921d1a4213 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('de6ff9cf-0d6b-40b1-89d1-82921d1a4213', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 2, 'ChangePrice', 'ChangePrice', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID ba7e3e4c-1c67-41cb-947a-21dd1531803b */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ba7e3e4c-1c67-41cb-947a-21dd1531803b', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 3, 'ChangeQuantity', 'ChangeQuantity', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 914e7d85-d775-4cee-a597-082ca2a8cb75 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('914e7d85-d775-4cee-a597-082ca2a8cb75', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 4, 'Coterm', 'Coterm', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f72ae7c9-a681-49ac-80f3-b021a3676145 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f72ae7c9-a681-49ac-80f3-b021a3676145', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 5, 'Other', 'Other', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID affbd5c4-85cd-43a9-9e5a-442f2119c053 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('affbd5c4-85cd-43a9-9e5a-442f2119c053', '33496713-A2D3-4390-9E5E-3DEC9D3D3AD4', 6, 'PartialTerminate', 'PartialTerminate', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID 33496713-A2D3-4390-9E5E-3DEC9D3D3AD4 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='33496713-A2D3-4390-9E5E-3DEC9D3D3AD4';

/* SQL text to insert entity field value with ID 969a700f-ada5-425f-a605-0374c25a194a */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('969a700f-ada5-425f-a605-0374c25a194a', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 1, 'Applied', 'Applied', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID e904975c-1696-494f-b391-26054c69f9b1 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('e904975c-1696-494f-b391-26054c69f9b1', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 2, 'Approved', 'Approved', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 90cb7b3b-3037-4518-bdf8-f826a1e1744e */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('90cb7b3b-3037-4518-bdf8-f826a1e1744e', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 3, 'Cancelled', 'Cancelled', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID a3bbf5a1-eddf-4b4b-a1de-dbe88bd2472a */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('a3bbf5a1-eddf-4b4b-a1de-dbe88bd2472a', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 4, 'Draft', 'Draft', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b9a21db4-bda4-4bc3-aa4e-4100d0e0bcc0 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b9a21db4-bda4-4bc3-aa4e-4100d0e0bcc0', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 5, 'PendingApproval', 'PendingApproval', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 64ce69df-b618-44d9-99b4-a8c18d72cd80 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('64ce69df-b618-44d9-99b4-a8c18d72cd80', 'C5A40BD6-4C2B-42C9-943F-D8630ABC8875', 6, 'Rejected', 'Rejected', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID C5A40BD6-4C2B-42C9-943F-D8630ABC8875 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='C5A40BD6-4C2B-42C9-943F-D8630ABC8875';

/* SQL text to insert entity field value with ID 671793c3-be06-4a8e-b771-818a70658cc7 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('671793c3-be06-4a8e-b771-818a70658cc7', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 1, 'AmendmentApplied', 'AmendmentApplied', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID ace95264-1bd7-4172-a2c6-581d8ebd07da */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('ace95264-1bd7-4172-a2c6-581d8ebd07da', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 2, 'BillingEventFailed', 'BillingEventFailed', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f754e0ca-4fc6-40b9-adc3-396dff215f95 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f754e0ca-4fc6-40b9-adc3-396dff215f95', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 3, 'BillingEventGenerated', 'BillingEventGenerated', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 02d47a90-ab79-4878-9ac9-64bb031d1ae6 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('02d47a90-ab79-4878-9ac9-64bb031d1ae6', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 4, 'ContractCreated', 'ContractCreated', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID b0edce23-bb5b-49f6-ac1b-351f18c893e9 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('b0edce23-bb5b-49f6-ac1b-351f18c893e9', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 5, 'ContractExecuted', 'ContractExecuted', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 0e061b9e-4412-4b28-94e8-80482c19be59 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('0e061b9e-4412-4b28-94e8-80482c19be59', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 6, 'ContractExpired', 'ContractExpired', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID a9afc1de-3a7f-4a2e-85f8-e598e0e823ad */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('a9afc1de-3a7f-4a2e-85f8-e598e0e823ad', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 7, 'ContractSuperseded', 'ContractSuperseded', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 56530b5c-ebd8-455e-9a88-f4e4643913ad */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('56530b5c-ebd8-455e-9a88-f4e4643913ad', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 8, 'ContractTerminated', 'ContractTerminated', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID e8cac816-caa9-48b8-a5d9-4e564a8db36f */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('e8cac816-caa9-48b8-a5d9-4e564a8db36f', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 9, 'SentForSignature', 'SentForSignature', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 6e7b15fe-b89d-46dc-8c52-d56fa722cf40 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('6e7b15fe-b89d-46dc-8c52-d56fa722cf40', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 10, 'SignatureRejected', 'SignatureRejected', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID f29cee4c-4840-4774-895c-0347854caae3 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('f29cee4c-4840-4774-895c-0347854caae3', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 11, 'TermActivated', 'TermActivated', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 07b88217-d147-4971-9534-701902223568 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('07b88217-d147-4971-9534-701902223568', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 12, 'TermCompleted', 'TermCompleted', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID dda06b3a-9d90-4b2d-8f9c-c0256cf9559d */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('dda06b3a-9d90-4b2d-8f9c-c0256cf9559d', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 13, 'TermRenewed', 'TermRenewed', GETUTCDATE(), GETUTCDATE());

/* SQL text to insert entity field value with ID 8449b47f-e81c-4e5d-ac1a-a74d1258b654 */
INSERT INTO [${mjSchema}].[EntityFieldValue]
                                       ([ID], [EntityFieldID], [Sequence], [Value], [Code], [__mj_CreatedAt], [__mj_UpdatedAt])
                                    VALUES
                                       ('8449b47f-e81c-4e5d-ac1a-a74d1258b654', 'E2F5A984-4B8E-4EDF-9E69-473E5000AEB4', 14, 'TermTerminated', 'TermTerminated', GETUTCDATE(), GETUTCDATE());

/* SQL text to update ValueListType for entity field ID E2F5A984-4B8E-4EDF-9E69-473E5000AEB4 */
UPDATE [${mjSchema}].[EntityField] SET ValueListType='List' WHERE ID='E2F5A984-4B8E-4EDF-9E69-473E5000AEB4';


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Billing Schedules -> MJ_BizApps_Contracts: Contract Billing Events (One To Many via ContractBillingScheduleID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'c3d35d27-5f23-4f53-9303-6a07bf626469'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('c3d35d27-5f23-4f53-9303-6a07bf626469', '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', '57F99C92-591B-4F35-82D9-83F6B330D8F1', 'ContractBillingScheduleID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via SupersededByContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'eddc3589-fb32-4d81-a5d8-c2f7bcbbfe7f'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('eddc3589-fb32-4d81-a5d8-c2f7bcbbfe7f', '82943343-8584-4023-9B36-385482D5DE51', '82943343-8584-4023-9B36-385482D5DE51', 'SupersededByContractID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contracts (One To Many via ParentContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'e5bd2e91-a913-4d7a-aee6-2771fc40c976'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('e5bd2e91-a913-4d7a-aee6-2771fc40c976', '82943343-8584-4023-9B36-385482D5DE51', '82943343-8584-4023-9B36-385482D5DE51', 'ParentContractID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Events (One To Many via ContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '436f83bb-25ff-48ec-9a89-951040deee7b'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('436f83bb-25ff-48ec-9a89-951040deee7b', '82943343-8584-4023-9B36-385482D5DE51', 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', 'ContractID', 'One To Many', 1, 1, 3, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contracts -> MJ_BizApps_Contracts: Contract Terms (One To Many via ContractID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'b29f79aa-617f-4f92-8893-30ec3c184f5e'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('b29f79aa-617f-4f92-8893-30ec3c184f5e', '82943343-8584-4023-9B36-385482D5DE51', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', 'ContractID', 'One To Many', 1, 1, 4, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Orders: Products -> MJ_BizApps_Contracts: Contract Lines (One To Many via ProductID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'f3690364-b894-4839-bf16-3d60f68c3d40'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('f3690364-b894-4839-bf16-3d60f68c3d40', '568562E1-B52B-4EDD-968F-3F7C6A072826', '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', 'ProductID', 'One To Many', 1, 1, 11, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Orders: Order Headers -> MJ_BizApps_Contracts: Contract Billing Events (One To Many via OrderID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '07f91182-8eab-47ef-b03c-7846c0c5c452'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('07f91182-8eab-47ef-b03c-7846c0c5c452', 'B75D0AA7-CE6B-4016-93D7-46963829348C', '57F99C92-591B-4F35-82D9-83F6B330D8F1', 'OrderID', 'One To Many', 1, 1, 10, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Companies -> MJ_BizApps_Contracts: Contracts (One To Many via CompanyID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '32186378-9540-4da4-8bd0-d46a89454c28'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('32186378-9540-4da4-8bd0-d46a89454c28', 'D4238F34-2837-EF11-86D4-6045BDEE16E6', '82943343-8584-4023-9B36-385482D5DE51', 'CompanyID', 'One To Many', 1, 1, 27, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Users -> MJ_BizApps_Contracts: Contract Events (One To Many via PerformedByUserID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '8cd27775-0f3e-4e2e-9edd-7437b286be6f'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('8cd27775-0f3e-4e2e-9edd-7437b286be6f', 'E1238F34-2837-EF11-86D4-6045BDEE16E6', 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', 'PerformedByUserID', 'One To Many', 1, 1, 119, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ: Users -> MJ_BizApps_Contracts: Contracts (One To Many via OwnerUserID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '7233c1d5-4b91-42ae-a836-bef6988b8fee'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('7233c1d5-4b91-42ae-a836-bef6988b8fee', 'E1238F34-2837-EF11-86D4-6045BDEE16E6', '82943343-8584-4023-9B36-385482D5DE51', 'OwnerUserID', 'One To Many', 1, 1, 120, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Orders: Subscriptions -> MJ_BizApps_Contracts: Contract Lines (One To Many via SubscriptionID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '9260f1eb-5124-44d9-8267-b275833131e0'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('9260f1eb-5124-44d9-8267-b275833131e0', 'C3DC9D6D-6023-41DA-95C9-64EFF8D7E594', '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', 'SubscriptionID', 'One To Many', 1, 1, 7, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Common: Organizations -> MJ_BizApps_Contracts: Contracts (One To Many via CustomerOrganizationID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '2147e6e0-ca73-43a7-a432-3eccbb48a468'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('2147e6e0-ca73-43a7-a432-3eccbb48a468', 'C70448F9-9792-41D7-A82C-784B66429D54', '82943343-8584-4023-9B36-385482D5DE51', 'CustomerOrganizationID', 'One To Many', 1, 1, 17, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Types -> MJ_BizApps_Contracts: Contracts (One To Many via ContractTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '58bf965b-3a13-430b-8cca-4cab1624f4a6'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('58bf965b-3a13-430b-8cca-4cab1624f4a6', '626148EC-40A2-4A28-B4DA-7B7564A3AE9C', '82943343-8584-4023-9B36-385482D5DE51', 'ContractTypeID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Accounting: Currencies -> MJ_BizApps_Contracts: Contract Terms (One To Many via CurrencyID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '04e1f75e-66e5-4b18-8753-d94681fb4913'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('04e1f75e-66e5-4b18-8753-d94681fb4913', '3D32E9E8-6BDB-4FED-B8A2-9AD27714B0FB', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', 'CurrencyID', 'One To Many', 1, 1, 7, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Orders: Subscription Types -> MJ_BizApps_Contracts: Contract Lines (One To Many via SubscriptionTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '82d999f0-c3e2-41b7-bf6f-f9bcdc84f726'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('82d999f0-c3e2-41b7-bf6f-f9bcdc84f726', '71C6C278-AE4E-4403-9D6B-CC2B5D66CD0D', '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', 'SubscriptionTypeID', 'One To Many', 1, 1, 4, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Lines (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '31852991-d156-4d28-97df-39d144640659'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('31852991-d156-4d28-97df-39d144640659', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', 'ContractTermID', 'One To Many', 1, 1, 1, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Billing Events (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'fc2ef63b-41bf-4d1e-8f06-4823bc8b6a80'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('fc2ef63b-41bf-4d1e-8f06-4823bc8b6a80', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '57F99C92-591B-4F35-82D9-83F6B330D8F1', 'ContractTermID', 'One To Many', 1, 1, 2, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Commitments (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'cef4beaa-13d7-47be-8d94-289c88596c3b'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('cef4beaa-13d7-47be-8d94-289c88596c3b', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '4342D779-6F68-4F94-9067-4F12C8E1D25B', 'ContractTermID', 'One To Many', 1, 1, 3, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Events (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'c9dbb1a3-8920-48e5-8648-1b514daea2fd'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('c9dbb1a3-8920-48e5-8648-1b514daea2fd', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', 'ContractTermID', 'One To Many', 1, 1, 4, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Billing Schedules (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '91a51bb4-aedf-425b-9a66-3c2657b6d3be'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('91a51bb4-aedf-425b-9a66-3c2657b6d3be', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '2458F4C0-C0EC-4B48-9E5F-2DD8AFA4103F', 'ContractTermID', 'One To Many', 1, 1, 5, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Terms (One To Many via RenewalOfTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'b106715f-7c54-4c1b-834b-4811bf546a90'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('b106715f-7c54-4c1b-834b-4811bf546a90', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', 'RenewalOfTermID', 'One To Many', 1, 1, 6, GETUTCDATE(), GETUTCDATE())
   END;


/* Create Entity Relationship: MJ_BizApps_Contracts: Contract Terms -> MJ_BizApps_Contracts: Contract Amendments (One To Many via ContractTermID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '8eaa355f-e770-463b-93cb-2e4e08583aa5'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('8eaa355f-e770-463b-93cb-2e4e08583aa5', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', '39D1F825-0D1A-4292-A0F2-C168E145C210', 'ContractTermID', 'One To Many', 1, 1, 7, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: People -> MJ_BizApps_Contracts: Contracts (One To Many via PrimaryContactPersonID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'f7b96ed0-f950-40f1-b7de-17d88ff28fe2'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('f7b96ed0-f950-40f1-b7de-17d88ff28fe2', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', '82943343-8584-4023-9B36-385482D5DE51', 'PrimaryContactPersonID', 'One To Many', 1, 1, 21, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Common: People -> MJ_BizApps_Contracts: Contracts (One To Many via CustomerPersonID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = 'cadb32bd-ef72-4277-a8c7-f89b08141d27'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('cadb32bd-ef72-4277-a8c7-f89b08141d27', '7A94ADA9-7880-4FAE-97D8-DB0E934C3F5F', '82943343-8584-4023-9B36-385482D5DE51', 'CustomerPersonID', 'One To Many', 1, 1, 22, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Tasks: Tasks -> MJ_BizApps_Contracts: Contract Amendments (One To Many via ApprovalTaskID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '742ed20a-e850-4f77-b7d4-9470edf02f09'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('742ed20a-e850-4f77-b7d4-9470edf02f09', 'B348FFA2-B1A7-4AC2-B6FD-F4E0C0697466', '39D1F825-0D1A-4292-A0F2-C168E145C210', 'ApprovalTaskID', 'One To Many', 1, 1, 12, GETUTCDATE(), GETUTCDATE())
   END;
                    
/* Create Entity Relationship: MJ_BizApps_Orders: Payment Terms Types -> MJ_BizApps_Contracts: Contract Terms (One To Many via PaymentTermsTypeID) */
   IF NOT EXISTS (
      SELECT 1 FROM [${mjSchema}].[EntityRelationship] WHERE [ID] = '6611b139-b7d6-4465-a473-f997eb80113b'
   )
   BEGIN
      INSERT INTO [${mjSchema}].[EntityRelationship] ([ID], [EntityID], [RelatedEntityID], [RelatedEntityJoinField], [Type], [BundleInAPI], [DisplayInForm], [Sequence], [__mj_CreatedAt], [__mj_UpdatedAt])
                    VALUES ('6611b139-b7d6-4465-a473-f997eb80113b', '6715E631-D59E-45FF-8421-F813B720C214', '317F4FD7-0CDD-4B17-973E-D55944D03DEE', 'PaymentTermsTypeID', 'One To Many', 1, 1, 3, GETUTCDATE(), GETUTCDATE())
   END;

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* Index for Foreign Keys for ContractAmendment */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTermID in table ContractAmendment
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractAmendment_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractAmendment]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractAmendment_ContractTermID ON [${flyway:defaultSchema}].[ContractAmendment] ([ContractTermID]);

-- Index for foreign key ApprovalTaskID in table ContractAmendment
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractAmendment_ApprovalTaskID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractAmendment]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractAmendment_ApprovalTaskID ON [${flyway:defaultSchema}].[ContractAmendment] ([ApprovalTaskID]);

/* SQL text to update entity field related entity name field map for entity field ID 1A7EAC5D-F0CD-46FB-BED8-7AE62C2F5855 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='1A7EAC5D-F0CD-46FB-BED8-7AE62C2F5855', @RelatedEntityNameFieldMap='ApprovalTask';

/* Index for Foreign Keys for ContractBillingEvent */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractBillingScheduleID in table ContractBillingEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractBillingEvent_ContractBillingScheduleID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractBillingEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractBillingEvent_ContractBillingScheduleID ON [${flyway:defaultSchema}].[ContractBillingEvent] ([ContractBillingScheduleID]);

-- Index for foreign key ContractTermID in table ContractBillingEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractBillingEvent_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractBillingEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractBillingEvent_ContractTermID ON [${flyway:defaultSchema}].[ContractBillingEvent] ([ContractTermID]);

-- Index for foreign key OrderID in table ContractBillingEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractBillingEvent_OrderID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractBillingEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractBillingEvent_OrderID ON [${flyway:defaultSchema}].[ContractBillingEvent] ([OrderID]);

/* SQL text to update entity field related entity name field map for entity field ID DDF7F58A-DC1E-4F10-87A6-B605D7D48604 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='DDF7F58A-DC1E-4F10-87A6-B605D7D48604', @RelatedEntityNameFieldMap='Order';

/* Index for Foreign Keys for ContractBillingSchedule */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTermID in table ContractBillingSchedule
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractBillingSchedule_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractBillingSchedule]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractBillingSchedule_ContractTermID ON [${flyway:defaultSchema}].[ContractBillingSchedule] ([ContractTermID]);

/* Index for Foreign Keys for ContractCommitment */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTermID in table ContractCommitment
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractCommitment_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractCommitment]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractCommitment_ContractTermID ON [${flyway:defaultSchema}].[ContractCommitment] ([ContractTermID]);

/* Index for Foreign Keys for ContractEvent */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractID in table ContractEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractEvent_ContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractEvent_ContractID ON [${flyway:defaultSchema}].[ContractEvent] ([ContractID]);

-- Index for foreign key ContractTermID in table ContractEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractEvent_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractEvent_ContractTermID ON [${flyway:defaultSchema}].[ContractEvent] ([ContractTermID]);

-- Index for foreign key PerformedByUserID in table ContractEvent
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractEvent_PerformedByUserID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractEvent]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractEvent_PerformedByUserID ON [${flyway:defaultSchema}].[ContractEvent] ([PerformedByUserID]);

/* SQL text to update entity field related entity name field map for entity field ID 6A8312F0-25BB-4C15-87B2-3AECBD71C191 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='6A8312F0-25BB-4C15-87B2-3AECBD71C191', @RelatedEntityNameFieldMap='PerformedByUser';

/* Base View SQL for MJ_BizApps_Contracts: Contract Billing Schedules */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: vwContractBillingSchedules
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Billing Schedules
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractBillingSchedule
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractBillingSchedules]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractBillingSchedules];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractBillingSchedules]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractBillingSchedule] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractBillingSchedules] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Billing Schedules */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: Permissions for vwContractBillingSchedules
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractBillingSchedules] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Billing Schedules */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: spCreateContractBillingSchedule
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractBillingSchedule
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractBillingSchedule]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractBillingSchedule];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractBillingSchedule]
    @ID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier,
    @ScheduleType nvarchar(20),
    @Frequency_Clear bit = 0,
    @Frequency nvarchar(20) = NULL,
    @AnchorDate_Clear bit = 0,
    @AnchorDate date = NULL,
    @IsActive bit = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractBillingSchedule]
            (
                [ID],
                [ContractTermID],
                [ScheduleType],
                [Frequency],
                [AnchorDate],
                [IsActive],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTermID,
                @ScheduleType,
                CASE WHEN @Frequency_Clear = 1 THEN NULL ELSE ISNULL(@Frequency, NULL) END,
                CASE WHEN @AnchorDate_Clear = 1 THEN NULL ELSE ISNULL(@AnchorDate, NULL) END,
                ISNULL(@IsActive, 1),
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractBillingSchedule]
            (
                [ContractTermID],
                [ScheduleType],
                [Frequency],
                [AnchorDate],
                [IsActive],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTermID,
                @ScheduleType,
                CASE WHEN @Frequency_Clear = 1 THEN NULL ELSE ISNULL(@Frequency, NULL) END,
                CASE WHEN @AnchorDate_Clear = 1 THEN NULL ELSE ISNULL(@AnchorDate, NULL) END,
                ISNULL(@IsActive, 1),
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractBillingSchedules] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractBillingSchedule] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Billing Schedules */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractBillingSchedule] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Billing Schedules */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: spUpdateContractBillingSchedule
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractBillingSchedule
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractBillingSchedule]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractBillingSchedule];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractBillingSchedule]
    @ID uniqueidentifier,
    @ContractTermID uniqueidentifier = NULL,
    @ScheduleType nvarchar(20) = NULL,
    @Frequency_Clear bit = 0,
    @Frequency nvarchar(20) = NULL,
    @AnchorDate_Clear bit = 0,
    @AnchorDate date = NULL,
    @IsActive bit = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractBillingSchedule]
    SET
        [ContractTermID] = ISNULL(@ContractTermID, [ContractTermID]),
        [ScheduleType] = ISNULL(@ScheduleType, [ScheduleType]),
        [Frequency] = CASE WHEN @Frequency_Clear = 1 THEN NULL ELSE ISNULL(@Frequency, [Frequency]) END,
        [AnchorDate] = CASE WHEN @AnchorDate_Clear = 1 THEN NULL ELSE ISNULL(@AnchorDate, [AnchorDate]) END,
        [IsActive] = ISNULL(@IsActive, [IsActive]),
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractBillingSchedules] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractBillingSchedules]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractBillingSchedule] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractBillingSchedule table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractBillingSchedule]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractBillingSchedule];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractBillingSchedule
ON [${flyway:defaultSchema}].[ContractBillingSchedule]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractBillingSchedule]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractBillingSchedule] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Billing Schedules */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractBillingSchedule] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Commitments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: vwContractCommitments
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Commitments
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractCommitment
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractCommitments]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractCommitments];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractCommitments]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractCommitment] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractCommitments] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Commitments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: Permissions for vwContractCommitments
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractCommitments] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Commitments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: spCreateContractCommitment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractCommitment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractCommitment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractCommitment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractCommitment]
    @ID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier,
    @CommitmentType nvarchar(20),
    @CommittedAmount decimal(19, 4),
    @ConsumedAmount decimal(19, 4) = NULL,
    @PeriodStart_Clear bit = 0,
    @PeriodStart date = NULL,
    @PeriodEnd_Clear bit = 0,
    @PeriodEnd date = NULL,
    @TrueUpPolicy nvarchar(20) = NULL,
    @Status nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractCommitment]
            (
                [ID],
                [ContractTermID],
                [CommitmentType],
                [CommittedAmount],
                [ConsumedAmount],
                [PeriodStart],
                [PeriodEnd],
                [TrueUpPolicy],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTermID,
                @CommitmentType,
                @CommittedAmount,
                ISNULL(@ConsumedAmount, 0),
                CASE WHEN @PeriodStart_Clear = 1 THEN NULL ELSE ISNULL(@PeriodStart, NULL) END,
                CASE WHEN @PeriodEnd_Clear = 1 THEN NULL ELSE ISNULL(@PeriodEnd, NULL) END,
                ISNULL(@TrueUpPolicy, 'BillShortfall'),
                ISNULL(@Status, 'Open')
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractCommitment]
            (
                [ContractTermID],
                [CommitmentType],
                [CommittedAmount],
                [ConsumedAmount],
                [PeriodStart],
                [PeriodEnd],
                [TrueUpPolicy],
                [Status]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTermID,
                @CommitmentType,
                @CommittedAmount,
                ISNULL(@ConsumedAmount, 0),
                CASE WHEN @PeriodStart_Clear = 1 THEN NULL ELSE ISNULL(@PeriodStart, NULL) END,
                CASE WHEN @PeriodEnd_Clear = 1 THEN NULL ELSE ISNULL(@PeriodEnd, NULL) END,
                ISNULL(@TrueUpPolicy, 'BillShortfall'),
                ISNULL(@Status, 'Open')
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractCommitments] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractCommitment] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Commitments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractCommitment] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Commitments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: spUpdateContractCommitment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractCommitment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractCommitment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractCommitment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractCommitment]
    @ID uniqueidentifier,
    @ContractTermID uniqueidentifier = NULL,
    @CommitmentType nvarchar(20) = NULL,
    @CommittedAmount decimal(19, 4) = NULL,
    @ConsumedAmount decimal(19, 4) = NULL,
    @PeriodStart_Clear bit = 0,
    @PeriodStart date = NULL,
    @PeriodEnd_Clear bit = 0,
    @PeriodEnd date = NULL,
    @TrueUpPolicy nvarchar(20) = NULL,
    @Status nvarchar(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractCommitment]
    SET
        [ContractTermID] = ISNULL(@ContractTermID, [ContractTermID]),
        [CommitmentType] = ISNULL(@CommitmentType, [CommitmentType]),
        [CommittedAmount] = ISNULL(@CommittedAmount, [CommittedAmount]),
        [ConsumedAmount] = ISNULL(@ConsumedAmount, [ConsumedAmount]),
        [PeriodStart] = CASE WHEN @PeriodStart_Clear = 1 THEN NULL ELSE ISNULL(@PeriodStart, [PeriodStart]) END,
        [PeriodEnd] = CASE WHEN @PeriodEnd_Clear = 1 THEN NULL ELSE ISNULL(@PeriodEnd, [PeriodEnd]) END,
        [TrueUpPolicy] = ISNULL(@TrueUpPolicy, [TrueUpPolicy]),
        [Status] = ISNULL(@Status, [Status])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractCommitments] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractCommitments]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractCommitment] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractCommitment table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractCommitment]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractCommitment];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractCommitment
ON [${flyway:defaultSchema}].[ContractCommitment]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractCommitment]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractCommitment] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Commitments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractCommitment] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Billing Schedules */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Schedules
-- Item: spDeleteContractBillingSchedule
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractBillingSchedule
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractBillingSchedule]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractBillingSchedule];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractBillingSchedule]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractBillingSchedule]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractBillingSchedule] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Billing Schedules */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractBillingSchedule] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Commitments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Commitments
-- Item: spDeleteContractCommitment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractCommitment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractCommitment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractCommitment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractCommitment]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractCommitment]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractCommitment] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Commitments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractCommitment] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Billing Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: vwContractBillingEvents
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Billing Events
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractBillingEvent
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractBillingEvents]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractBillingEvents];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractBillingEvents]
AS
SELECT
    c.*,
    mjBizAppsOrdersOrderHeader_OrderID.[OrderNumber] AS [Order]
FROM
    [${flyway:defaultSchema}].[ContractBillingEvent] AS c
LEFT OUTER JOIN
    [${mjSchema}_BizAppsOrders].[OrderHeader] AS mjBizAppsOrdersOrderHeader_OrderID
  ON
    [c].[OrderID] = mjBizAppsOrdersOrderHeader_OrderID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractBillingEvents] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Billing Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: Permissions for vwContractBillingEvents
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractBillingEvents] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Billing Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: spCreateContractBillingEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractBillingEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractBillingEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractBillingEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractBillingEvent]
    @ID uniqueidentifier = NULL,
    @ContractBillingScheduleID_Clear bit = 0,
    @ContractBillingScheduleID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier,
    @ScheduledDate date,
    @Status nvarchar(20) = NULL,
    @OrderID_Clear bit = 0,
    @OrderID uniqueidentifier = NULL,
    @ComputedAmount_Clear bit = 0,
    @ComputedAmount decimal(19, 4) = NULL,
    @GeneratedAt_Clear bit = 0,
    @GeneratedAt datetimeoffset = NULL,
    @FailureReason_Clear bit = 0,
    @FailureReason nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractBillingEvent]
            (
                [ID],
                [ContractBillingScheduleID],
                [ContractTermID],
                [ScheduledDate],
                [Status],
                [OrderID],
                [ComputedAmount],
                [GeneratedAt],
                [FailureReason],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                CASE WHEN @ContractBillingScheduleID_Clear = 1 THEN NULL ELSE ISNULL(@ContractBillingScheduleID, NULL) END,
                @ContractTermID,
                @ScheduledDate,
                ISNULL(@Status, 'Scheduled'),
                CASE WHEN @OrderID_Clear = 1 THEN NULL ELSE ISNULL(@OrderID, NULL) END,
                CASE WHEN @ComputedAmount_Clear = 1 THEN NULL ELSE ISNULL(@ComputedAmount, NULL) END,
                CASE WHEN @GeneratedAt_Clear = 1 THEN NULL ELSE ISNULL(@GeneratedAt, NULL) END,
                CASE WHEN @FailureReason_Clear = 1 THEN NULL ELSE ISNULL(@FailureReason, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractBillingEvent]
            (
                [ContractBillingScheduleID],
                [ContractTermID],
                [ScheduledDate],
                [Status],
                [OrderID],
                [ComputedAmount],
                [GeneratedAt],
                [FailureReason],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                CASE WHEN @ContractBillingScheduleID_Clear = 1 THEN NULL ELSE ISNULL(@ContractBillingScheduleID, NULL) END,
                @ContractTermID,
                @ScheduledDate,
                ISNULL(@Status, 'Scheduled'),
                CASE WHEN @OrderID_Clear = 1 THEN NULL ELSE ISNULL(@OrderID, NULL) END,
                CASE WHEN @ComputedAmount_Clear = 1 THEN NULL ELSE ISNULL(@ComputedAmount, NULL) END,
                CASE WHEN @GeneratedAt_Clear = 1 THEN NULL ELSE ISNULL(@GeneratedAt, NULL) END,
                CASE WHEN @FailureReason_Clear = 1 THEN NULL ELSE ISNULL(@FailureReason, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractBillingEvents] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractBillingEvent] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Billing Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractBillingEvent] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Billing Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: spUpdateContractBillingEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractBillingEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractBillingEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractBillingEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractBillingEvent]
    @ID uniqueidentifier,
    @ContractBillingScheduleID_Clear bit = 0,
    @ContractBillingScheduleID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier = NULL,
    @ScheduledDate date = NULL,
    @Status nvarchar(20) = NULL,
    @OrderID_Clear bit = 0,
    @OrderID uniqueidentifier = NULL,
    @ComputedAmount_Clear bit = 0,
    @ComputedAmount decimal(19, 4) = NULL,
    @GeneratedAt_Clear bit = 0,
    @GeneratedAt datetimeoffset = NULL,
    @FailureReason_Clear bit = 0,
    @FailureReason nvarchar(MAX) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractBillingEvent]
    SET
        [ContractBillingScheduleID] = CASE WHEN @ContractBillingScheduleID_Clear = 1 THEN NULL ELSE ISNULL(@ContractBillingScheduleID, [ContractBillingScheduleID]) END,
        [ContractTermID] = ISNULL(@ContractTermID, [ContractTermID]),
        [ScheduledDate] = ISNULL(@ScheduledDate, [ScheduledDate]),
        [Status] = ISNULL(@Status, [Status]),
        [OrderID] = CASE WHEN @OrderID_Clear = 1 THEN NULL ELSE ISNULL(@OrderID, [OrderID]) END,
        [ComputedAmount] = CASE WHEN @ComputedAmount_Clear = 1 THEN NULL ELSE ISNULL(@ComputedAmount, [ComputedAmount]) END,
        [GeneratedAt] = CASE WHEN @GeneratedAt_Clear = 1 THEN NULL ELSE ISNULL(@GeneratedAt, [GeneratedAt]) END,
        [FailureReason] = CASE WHEN @FailureReason_Clear = 1 THEN NULL ELSE ISNULL(@FailureReason, [FailureReason]) END,
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractBillingEvents] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractBillingEvents]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractBillingEvent] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractBillingEvent table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractBillingEvent]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractBillingEvent];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractBillingEvent
ON [${flyway:defaultSchema}].[ContractBillingEvent]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractBillingEvent]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractBillingEvent] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Billing Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractBillingEvent] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Billing Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Billing Events
-- Item: spDeleteContractBillingEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractBillingEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractBillingEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractBillingEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractBillingEvent]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractBillingEvent]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractBillingEvent] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Billing Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractBillingEvent] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Amendments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: vwContractAmendments
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Amendments
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractAmendment
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractAmendments]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractAmendments];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractAmendments]
AS
SELECT
    c.*,
    mjBizAppsTasksTask_ApprovalTaskID.[Name] AS [ApprovalTask]
FROM
    [${flyway:defaultSchema}].[ContractAmendment] AS c
LEFT OUTER JOIN
    [${mjSchema}_BizAppsTasks].[Task] AS mjBizAppsTasksTask_ApprovalTaskID
  ON
    [c].[ApprovalTaskID] = mjBizAppsTasksTask_ApprovalTaskID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractAmendments] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Amendments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: Permissions for vwContractAmendments
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractAmendments] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Amendments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: spCreateContractAmendment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractAmendment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractAmendment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractAmendment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractAmendment]
    @ID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier,
    @AmendmentNumber int,
    @EffectiveDate date,
    @AmendmentType nvarchar(30),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(20) = NULL,
    @ApprovalTaskID_Clear bit = 0,
    @ApprovalTaskID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractAmendment]
            (
                [ID],
                [ContractTermID],
                [AmendmentNumber],
                [EffectiveDate],
                [AmendmentType],
                [Description],
                [Status],
                [ApprovalTaskID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTermID,
                @AmendmentNumber,
                @EffectiveDate,
                @AmendmentType,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Draft'),
                CASE WHEN @ApprovalTaskID_Clear = 1 THEN NULL ELSE ISNULL(@ApprovalTaskID, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractAmendment]
            (
                [ContractTermID],
                [AmendmentNumber],
                [EffectiveDate],
                [AmendmentType],
                [Description],
                [Status],
                [ApprovalTaskID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTermID,
                @AmendmentNumber,
                @EffectiveDate,
                @AmendmentType,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@Status, 'Draft'),
                CASE WHEN @ApprovalTaskID_Clear = 1 THEN NULL ELSE ISNULL(@ApprovalTaskID, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractAmendments] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractAmendment] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Amendments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractAmendment] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Amendments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: spUpdateContractAmendment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractAmendment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractAmendment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractAmendment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractAmendment]
    @ID uniqueidentifier,
    @ContractTermID uniqueidentifier = NULL,
    @AmendmentNumber int = NULL,
    @EffectiveDate date = NULL,
    @AmendmentType nvarchar(30) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @Status nvarchar(20) = NULL,
    @ApprovalTaskID_Clear bit = 0,
    @ApprovalTaskID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractAmendment]
    SET
        [ContractTermID] = ISNULL(@ContractTermID, [ContractTermID]),
        [AmendmentNumber] = ISNULL(@AmendmentNumber, [AmendmentNumber]),
        [EffectiveDate] = ISNULL(@EffectiveDate, [EffectiveDate]),
        [AmendmentType] = ISNULL(@AmendmentType, [AmendmentType]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [Status] = ISNULL(@Status, [Status]),
        [ApprovalTaskID] = CASE WHEN @ApprovalTaskID_Clear = 1 THEN NULL ELSE ISNULL(@ApprovalTaskID, [ApprovalTaskID]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractAmendments] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractAmendments]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractAmendment] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractAmendment table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractAmendment]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractAmendment];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractAmendment
ON [${flyway:defaultSchema}].[ContractAmendment]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractAmendment]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractAmendment] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Amendments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractAmendment] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Amendments */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Amendments
-- Item: spDeleteContractAmendment
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractAmendment
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractAmendment]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractAmendment];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractAmendment]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractAmendment]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractAmendment] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Amendments */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractAmendment] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: vwContractEvents
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Events
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractEvent
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractEvents]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractEvents];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractEvents]
AS
SELECT
    c.*,
    MJUser_PerformedByUserID.[Name] AS [PerformedByUser]
FROM
    [${flyway:defaultSchema}].[ContractEvent] AS c
LEFT OUTER JOIN
    [${mjSchema}].[User] AS MJUser_PerformedByUserID
  ON
    [c].[PerformedByUserID] = MJUser_PerformedByUserID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractEvents] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: Permissions for vwContractEvents
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractEvents] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: spCreateContractEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractEvent]
    @ID uniqueidentifier = NULL,
    @ContractID uniqueidentifier,
    @ContractTermID_Clear bit = 0,
    @ContractTermID uniqueidentifier = NULL,
    @EventType nvarchar(50),
    @EventDate datetimeoffset = NULL,
    @Payload_Clear bit = 0,
    @Payload nvarchar(MAX) = NULL,
    @PerformedByUserID_Clear bit = 0,
    @PerformedByUserID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractEvent]
            (
                [ID],
                [ContractID],
                [ContractTermID],
                [EventType],
                [EventDate],
                [Payload],
                [PerformedByUserID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractID,
                CASE WHEN @ContractTermID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTermID, NULL) END,
                @EventType,
                ISNULL(@EventDate, sysdatetimeoffset()),
                CASE WHEN @Payload_Clear = 1 THEN NULL ELSE ISNULL(@Payload, NULL) END,
                CASE WHEN @PerformedByUserID_Clear = 1 THEN NULL ELSE ISNULL(@PerformedByUserID, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractEvent]
            (
                [ContractID],
                [ContractTermID],
                [EventType],
                [EventDate],
                [Payload],
                [PerformedByUserID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractID,
                CASE WHEN @ContractTermID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTermID, NULL) END,
                @EventType,
                ISNULL(@EventDate, sysdatetimeoffset()),
                CASE WHEN @Payload_Clear = 1 THEN NULL ELSE ISNULL(@Payload, NULL) END,
                CASE WHEN @PerformedByUserID_Clear = 1 THEN NULL ELSE ISNULL(@PerformedByUserID, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractEvents] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractEvent] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractEvent] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: spUpdateContractEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractEvent]
    @ID uniqueidentifier,
    @ContractID uniqueidentifier = NULL,
    @ContractTermID_Clear bit = 0,
    @ContractTermID uniqueidentifier = NULL,
    @EventType nvarchar(50) = NULL,
    @EventDate datetimeoffset = NULL,
    @Payload_Clear bit = 0,
    @Payload nvarchar(MAX) = NULL,
    @PerformedByUserID_Clear bit = 0,
    @PerformedByUserID uniqueidentifier = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractEvent]
    SET
        [ContractID] = ISNULL(@ContractID, [ContractID]),
        [ContractTermID] = CASE WHEN @ContractTermID_Clear = 1 THEN NULL ELSE ISNULL(@ContractTermID, [ContractTermID]) END,
        [EventType] = ISNULL(@EventType, [EventType]),
        [EventDate] = ISNULL(@EventDate, [EventDate]),
        [Payload] = CASE WHEN @Payload_Clear = 1 THEN NULL ELSE ISNULL(@Payload, [Payload]) END,
        [PerformedByUserID] = CASE WHEN @PerformedByUserID_Clear = 1 THEN NULL ELSE ISNULL(@PerformedByUserID, [PerformedByUserID]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractEvents] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractEvents]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractEvent] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractEvent table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractEvent]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractEvent];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractEvent
ON [${flyway:defaultSchema}].[ContractEvent]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractEvent]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractEvent] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractEvent] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Events */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Events
-- Item: spDeleteContractEvent
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractEvent
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractEvent]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractEvent];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractEvent]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractEvent]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractEvent] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Events */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractEvent] TO [cdp_Developer], [cdp_Integration];

/* Index for Foreign Keys for ContractLine */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTermID in table ContractLine
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractLine_ContractTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractLine]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractLine_ContractTermID ON [${flyway:defaultSchema}].[ContractLine] ([ContractTermID]);

-- Index for foreign key ProductID in table ContractLine
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractLine_ProductID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractLine]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractLine_ProductID ON [${flyway:defaultSchema}].[ContractLine] ([ProductID]);

-- Index for foreign key SubscriptionTypeID in table ContractLine
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractLine_SubscriptionTypeID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractLine]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractLine_SubscriptionTypeID ON [${flyway:defaultSchema}].[ContractLine] ([SubscriptionTypeID]);

-- Index for foreign key SubscriptionID in table ContractLine
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractLine_SubscriptionID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractLine]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractLine_SubscriptionID ON [${flyway:defaultSchema}].[ContractLine] ([SubscriptionID]);

/* SQL text to update entity field related entity name field map for entity field ID 5FC78A64-E9FF-4A0D-9397-2DEB59CC4CC9 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='5FC78A64-E9FF-4A0D-9397-2DEB59CC4CC9', @RelatedEntityNameFieldMap='Product';

/* Index for Foreign Keys for ContractSequence */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

/* Index for Foreign Keys for ContractTerm */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractID in table ContractTerm
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTerm_ContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTerm]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTerm_ContractID ON [${flyway:defaultSchema}].[ContractTerm] ([ContractID]);

-- Index for foreign key RenewalOfTermID in table ContractTerm
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTerm_RenewalOfTermID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTerm]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTerm_RenewalOfTermID ON [${flyway:defaultSchema}].[ContractTerm] ([RenewalOfTermID]);

-- Index for foreign key PaymentTermsTypeID in table ContractTerm
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTerm_PaymentTermsTypeID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTerm]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTerm_PaymentTermsTypeID ON [${flyway:defaultSchema}].[ContractTerm] ([PaymentTermsTypeID]);

-- Index for foreign key CurrencyID in table ContractTerm
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_ContractTerm_CurrencyID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[ContractTerm]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_ContractTerm_CurrencyID ON [${flyway:defaultSchema}].[ContractTerm] ([CurrencyID]);

/* SQL text to update entity field related entity name field map for entity field ID 1AFA5B6C-0FB7-4692-9EDA-1AA510827D8B */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='1AFA5B6C-0FB7-4692-9EDA-1AA510827D8B', @RelatedEntityNameFieldMap='PaymentTermsType';

/* Index for Foreign Keys for ContractType */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------;

/* Index for Foreign Keys for Contract */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: Index for Foreign Keys
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
-- Index for foreign key ContractTypeID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_ContractTypeID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_ContractTypeID ON [${flyway:defaultSchema}].[Contract] ([ContractTypeID]);

-- Index for foreign key CompanyID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CompanyID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CompanyID ON [${flyway:defaultSchema}].[Contract] ([CompanyID]);

-- Index for foreign key CustomerOrganizationID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CustomerOrganizationID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CustomerOrganizationID ON [${flyway:defaultSchema}].[Contract] ([CustomerOrganizationID]);

-- Index for foreign key CustomerPersonID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_CustomerPersonID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_CustomerPersonID ON [${flyway:defaultSchema}].[Contract] ([CustomerPersonID]);

-- Index for foreign key PrimaryContactPersonID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_PrimaryContactPersonID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_PrimaryContactPersonID ON [${flyway:defaultSchema}].[Contract] ([PrimaryContactPersonID]);

-- Index for foreign key OwnerUserID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_OwnerUserID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_OwnerUserID ON [${flyway:defaultSchema}].[Contract] ([OwnerUserID]);

-- Index for foreign key ParentContractID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_ParentContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_ParentContractID ON [${flyway:defaultSchema}].[Contract] ([ParentContractID]);

-- Index for foreign key SupersededByContractID in table Contract
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IDX_AUTO_MJ_FKEY_Contract_SupersededByContractID' 
    AND object_id = OBJECT_ID('[${flyway:defaultSchema}].[Contract]')
)
CREATE INDEX IDX_AUTO_MJ_FKEY_Contract_SupersededByContractID ON [${flyway:defaultSchema}].[Contract] ([SupersededByContractID]);

/* SQL text to update entity field related entity name field map for entity field ID 1CFD1D47-CBD0-4C4F-9DAD-36C794D3E98B */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='1CFD1D47-CBD0-4C4F-9DAD-36C794D3E98B', @RelatedEntityNameFieldMap='ContractType';

/* Base View SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: vwContractSequences
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Sequences
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractSequence
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractSequences]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractSequences];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractSequences]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractSequence] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractSequences] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: Permissions for vwContractSequences
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractSequences] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spCreateContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractSequence]
    @ID int = NULL,
    @NextSequenceNumber int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO
    [${flyway:defaultSchema}].[ContractSequence]
        (
            [NextSequenceNumber],
                [ID]
        )
    VALUES
        (
            ISNULL(@NextSequenceNumber, 1),
                @ID
        )
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractSequences] WHERE [ID] = @ID
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spUpdateContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractSequence]
    @ID int,
    @NextSequenceNumber int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractSequence]
    SET
        [NextSequenceNumber] = ISNULL(@NextSequenceNumber, [NextSequenceNumber])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractSequences] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractSequences]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractSequence] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractSequence table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractSequence]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractSequence];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractSequence
ON [${flyway:defaultSchema}].[ContractSequence]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractSequence]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractSequence] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractSequence] TO [cdp_Developer], [cdp_Integration];

/* Base View SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: vwContractTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Types
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractType
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTypes]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTypes];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTypes]
AS
SELECT
    c.*
FROM
    [${flyway:defaultSchema}].[ContractType] AS c
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: Permissions for vwContractTypes
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTypes] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spCreateContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractType]
    @ID uniqueidentifier = NULL,
    @Code nvarchar(50),
    @Name nvarchar(100),
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @DefaultTermMonths_Clear bit = 0,
    @DefaultTermMonths int = NULL,
    @DefaultBillingFrequency_Clear bit = 0,
    @DefaultBillingFrequency nvarchar(20) = NULL,
    @DefaultAutoRenew bit = NULL,
    @RequiresSignature bit = NULL,
    @DefaultEscalationPercent_Clear bit = 0,
    @DefaultEscalationPercent decimal(7, 4) = NULL,
    @DefaultMaxEscalationPercent_Clear bit = 0,
    @DefaultMaxEscalationPercent decimal(7, 4) = NULL,
    @DefaultRenewalNoticeDays_Clear bit = 0,
    @DefaultRenewalNoticeDays int = NULL,
    @DefaultCancellationWindowDays_Clear bit = 0,
    @DefaultCancellationWindowDays int = NULL,
    @RenewalMode nvarchar(20) = NULL,
    @AllowsCoterm bit = NULL,
    @DriverClass_Clear bit = 0,
    @DriverClass nvarchar(255) = NULL,
    @IsActive bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractType]
            (
                [ID],
                [Code],
                [Name],
                [Description],
                [DefaultTermMonths],
                [DefaultBillingFrequency],
                [DefaultAutoRenew],
                [RequiresSignature],
                [DefaultEscalationPercent],
                [DefaultMaxEscalationPercent],
                [DefaultRenewalNoticeDays],
                [DefaultCancellationWindowDays],
                [RenewalMode],
                [AllowsCoterm],
                [DriverClass],
                [IsActive]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @Code,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @DefaultTermMonths_Clear = 1 THEN NULL ELSE ISNULL(@DefaultTermMonths, NULL) END,
                CASE WHEN @DefaultBillingFrequency_Clear = 1 THEN NULL ELSE ISNULL(@DefaultBillingFrequency, NULL) END,
                ISNULL(@DefaultAutoRenew, 0),
                ISNULL(@RequiresSignature, 1),
                CASE WHEN @DefaultEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultEscalationPercent, NULL) END,
                CASE WHEN @DefaultMaxEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultMaxEscalationPercent, NULL) END,
                CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, NULL) END,
                CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, NULL) END,
                ISNULL(@RenewalMode, 'Deal'),
                ISNULL(@AllowsCoterm, 1),
                CASE WHEN @DriverClass_Clear = 1 THEN NULL ELSE ISNULL(@DriverClass, NULL) END,
                ISNULL(@IsActive, 1)
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractType]
            (
                [Code],
                [Name],
                [Description],
                [DefaultTermMonths],
                [DefaultBillingFrequency],
                [DefaultAutoRenew],
                [RequiresSignature],
                [DefaultEscalationPercent],
                [DefaultMaxEscalationPercent],
                [DefaultRenewalNoticeDays],
                [DefaultCancellationWindowDays],
                [RenewalMode],
                [AllowsCoterm],
                [DriverClass],
                [IsActive]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @Code,
                @Name,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @DefaultTermMonths_Clear = 1 THEN NULL ELSE ISNULL(@DefaultTermMonths, NULL) END,
                CASE WHEN @DefaultBillingFrequency_Clear = 1 THEN NULL ELSE ISNULL(@DefaultBillingFrequency, NULL) END,
                ISNULL(@DefaultAutoRenew, 0),
                ISNULL(@RequiresSignature, 1),
                CASE WHEN @DefaultEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultEscalationPercent, NULL) END,
                CASE WHEN @DefaultMaxEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultMaxEscalationPercent, NULL) END,
                CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, NULL) END,
                CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, NULL) END,
                ISNULL(@RenewalMode, 'Deal'),
                ISNULL(@AllowsCoterm, 1),
                CASE WHEN @DriverClass_Clear = 1 THEN NULL ELSE ISNULL(@DriverClass, NULL) END,
                ISNULL(@IsActive, 1)
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTypes] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractType] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spUpdateContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractType]
    @ID uniqueidentifier,
    @Code nvarchar(50) = NULL,
    @Name nvarchar(100) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @DefaultTermMonths_Clear bit = 0,
    @DefaultTermMonths int = NULL,
    @DefaultBillingFrequency_Clear bit = 0,
    @DefaultBillingFrequency nvarchar(20) = NULL,
    @DefaultAutoRenew bit = NULL,
    @RequiresSignature bit = NULL,
    @DefaultEscalationPercent_Clear bit = 0,
    @DefaultEscalationPercent decimal(7, 4) = NULL,
    @DefaultMaxEscalationPercent_Clear bit = 0,
    @DefaultMaxEscalationPercent decimal(7, 4) = NULL,
    @DefaultRenewalNoticeDays_Clear bit = 0,
    @DefaultRenewalNoticeDays int = NULL,
    @DefaultCancellationWindowDays_Clear bit = 0,
    @DefaultCancellationWindowDays int = NULL,
    @RenewalMode nvarchar(20) = NULL,
    @AllowsCoterm bit = NULL,
    @DriverClass_Clear bit = 0,
    @DriverClass nvarchar(255) = NULL,
    @IsActive bit = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        [Code] = ISNULL(@Code, [Code]),
        [Name] = ISNULL(@Name, [Name]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [DefaultTermMonths] = CASE WHEN @DefaultTermMonths_Clear = 1 THEN NULL ELSE ISNULL(@DefaultTermMonths, [DefaultTermMonths]) END,
        [DefaultBillingFrequency] = CASE WHEN @DefaultBillingFrequency_Clear = 1 THEN NULL ELSE ISNULL(@DefaultBillingFrequency, [DefaultBillingFrequency]) END,
        [DefaultAutoRenew] = ISNULL(@DefaultAutoRenew, [DefaultAutoRenew]),
        [RequiresSignature] = ISNULL(@RequiresSignature, [RequiresSignature]),
        [DefaultEscalationPercent] = CASE WHEN @DefaultEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultEscalationPercent, [DefaultEscalationPercent]) END,
        [DefaultMaxEscalationPercent] = CASE WHEN @DefaultMaxEscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@DefaultMaxEscalationPercent, [DefaultMaxEscalationPercent]) END,
        [DefaultRenewalNoticeDays] = CASE WHEN @DefaultRenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultRenewalNoticeDays, [DefaultRenewalNoticeDays]) END,
        [DefaultCancellationWindowDays] = CASE WHEN @DefaultCancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@DefaultCancellationWindowDays, [DefaultCancellationWindowDays]) END,
        [RenewalMode] = ISNULL(@RenewalMode, [RenewalMode]),
        [AllowsCoterm] = ISNULL(@AllowsCoterm, [AllowsCoterm]),
        [DriverClass] = CASE WHEN @DriverClass_Clear = 1 THEN NULL ELSE ISNULL(@DriverClass, [DriverClass]) END,
        [IsActive] = ISNULL(@IsActive, [IsActive])
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
    UPDATE
        [${flyway:defaultSchema}].[ContractType]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractType] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractType] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Sequences */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Sequences
-- Item: spDeleteContractSequence
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractSequence
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractSequence]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractSequence];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractSequence]
    @ID int
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractSequence]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Sequences */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractSequence] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Types */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Types
-- Item: spDeleteContractType
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractType
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractType]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractType];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractType]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractType]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Types */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractType] TO [cdp_Developer], [cdp_Integration];

/* SQL text to update entity field related entity name field map for entity field ID 9C5A5211-5038-48D2-9469-E5CA293661DF */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='9C5A5211-5038-48D2-9469-E5CA293661DF', @RelatedEntityNameFieldMap='Company';

/* SQL text to update entity field related entity name field map for entity field ID 323EBBB1-20E4-45D7-9CB2-8C0044CA9F2D */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='323EBBB1-20E4-45D7-9CB2-8C0044CA9F2D', @RelatedEntityNameFieldMap='SubscriptionType';

/* SQL text to update entity field related entity name field map for entity field ID DC59FD42-285B-491C-94F1-D4FD0B68CBE0 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='DC59FD42-285B-491C-94F1-D4FD0B68CBE0', @RelatedEntityNameFieldMap='Currency';

/* Root ID Function SQL for MJ_BizApps_Contracts: Contract Terms.RenewalOfTermID */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: fnContractTermRenewalOfTermID_GetRootID
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
------------------------------------------------------------
----- ROOT ID FUNCTION FOR: [ContractTerm].[RenewalOfTermID]
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[fnContractTermRenewalOfTermID_GetRootID]', 'IF') IS NOT NULL
    DROP FUNCTION [${flyway:defaultSchema}].[fnContractTermRenewalOfTermID_GetRootID];
GO

CREATE FUNCTION [${flyway:defaultSchema}].[fnContractTermRenewalOfTermID_GetRootID]
(
    @RecordID uniqueidentifier,
    @ParentID uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    WITH CTE_RootParent AS (
        SELECT
            [ID],
            [RenewalOfTermID],
            [ID] AS [RootParentID],
            0 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[ContractTerm]
        WHERE
            [ID] = COALESCE(@ParentID, @RecordID)

        UNION ALL

        SELECT
            c.[ID],
            c.[RenewalOfTermID],
            c.[ID] AS [RootParentID],
            p.[Depth] + 1 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[ContractTerm] c
        INNER JOIN
            CTE_RootParent p ON c.[ID] = p.[RenewalOfTermID]
        WHERE
            p.[Depth] < 100
    )
    SELECT TOP 1
        [RootParentID] AS RootID
    FROM
        CTE_RootParent
    WHERE
        [RenewalOfTermID] IS NULL
    ORDER BY
        [RootParentID]
);
GO

/* Base View SQL for MJ_BizApps_Contracts: Contract Terms */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: vwContractTerms
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Terms
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractTerm
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractTerms]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractTerms];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractTerms]
AS
SELECT
    c.*,
    mjBizAppsOrdersPaymentTermsType_PaymentTermsTypeID.[Name] AS [PaymentTermsType],
    mjBizAppsAccountingCurrency_CurrencyID.[Name] AS [Currency],
    root_RenewalOfTermID.RootID AS [RootRenewalOfTermID]
FROM
    [${flyway:defaultSchema}].[ContractTerm] AS c
LEFT OUTER JOIN
    [${mjSchema}_BizAppsOrders].[PaymentTermsType] AS mjBizAppsOrdersPaymentTermsType_PaymentTermsTypeID
  ON
    [c].[PaymentTermsTypeID] = mjBizAppsOrdersPaymentTermsType_PaymentTermsTypeID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsAccounting].[Currency] AS mjBizAppsAccountingCurrency_CurrencyID
  ON
    [c].[CurrencyID] = mjBizAppsAccountingCurrency_CurrencyID.[ID]
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractTermRenewalOfTermID_GetRootID]([c].[ID], [c].[RenewalOfTermID]) AS root_RenewalOfTermID
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTerms] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Terms */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: Permissions for vwContractTerms
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractTerms] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Terms */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: spCreateContractTerm
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractTerm
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractTerm]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractTerm];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractTerm]
    @ID uniqueidentifier = NULL,
    @ContractID uniqueidentifier,
    @TermNumber int,
    @StartDate date,
    @EndDate date,
    @Status nvarchar(20) = NULL,
    @RenewalOfTermID_Clear bit = 0,
    @RenewalOfTermID uniqueidentifier = NULL,
    @CommittedAmount decimal(19, 4),
    @EscalationPercent_Clear bit = 0,
    @EscalationPercent decimal(7, 4) = NULL,
    @EscalationBasis_Clear bit = 0,
    @EscalationBasis nvarchar(20) = NULL,
    @BillingFrequency nvarchar(20),
    @BillingAnchorMonth_Clear bit = 0,
    @BillingAnchorMonth tinyint = NULL,
    @BillingAnchorDay_Clear bit = 0,
    @BillingAnchorDay tinyint = NULL,
    @PaymentTermsTypeID_Clear bit = 0,
    @PaymentTermsTypeID uniqueidentifier = NULL,
    @CurrencyID_Clear bit = 0,
    @CurrencyID uniqueidentifier = NULL,
    @EarlyTerminationDate_Clear bit = 0,
    @EarlyTerminationDate date = NULL,
    @RenewalProbability_Clear bit = 0,
    @RenewalProbability decimal(5, 4) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractTerm]
            (
                [ID],
                [ContractID],
                [TermNumber],
                [StartDate],
                [EndDate],
                [Status],
                [RenewalOfTermID],
                [CommittedAmount],
                [EscalationPercent],
                [EscalationBasis],
                [BillingFrequency],
                [BillingAnchorMonth],
                [BillingAnchorDay],
                [PaymentTermsTypeID],
                [CurrencyID],
                [EarlyTerminationDate],
                [RenewalProbability],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractID,
                @TermNumber,
                @StartDate,
                @EndDate,
                ISNULL(@Status, 'Pending'),
                CASE WHEN @RenewalOfTermID_Clear = 1 THEN NULL ELSE ISNULL(@RenewalOfTermID, NULL) END,
                @CommittedAmount,
                CASE WHEN @EscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@EscalationPercent, NULL) END,
                CASE WHEN @EscalationBasis_Clear = 1 THEN NULL ELSE ISNULL(@EscalationBasis, NULL) END,
                @BillingFrequency,
                CASE WHEN @BillingAnchorMonth_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorMonth, NULL) END,
                CASE WHEN @BillingAnchorDay_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorDay, NULL) END,
                CASE WHEN @PaymentTermsTypeID_Clear = 1 THEN NULL ELSE ISNULL(@PaymentTermsTypeID, NULL) END,
                CASE WHEN @CurrencyID_Clear = 1 THEN NULL ELSE ISNULL(@CurrencyID, NULL) END,
                CASE WHEN @EarlyTerminationDate_Clear = 1 THEN NULL ELSE ISNULL(@EarlyTerminationDate, NULL) END,
                CASE WHEN @RenewalProbability_Clear = 1 THEN NULL ELSE ISNULL(@RenewalProbability, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractTerm]
            (
                [ContractID],
                [TermNumber],
                [StartDate],
                [EndDate],
                [Status],
                [RenewalOfTermID],
                [CommittedAmount],
                [EscalationPercent],
                [EscalationBasis],
                [BillingFrequency],
                [BillingAnchorMonth],
                [BillingAnchorDay],
                [PaymentTermsTypeID],
                [CurrencyID],
                [EarlyTerminationDate],
                [RenewalProbability],
                [Notes]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractID,
                @TermNumber,
                @StartDate,
                @EndDate,
                ISNULL(@Status, 'Pending'),
                CASE WHEN @RenewalOfTermID_Clear = 1 THEN NULL ELSE ISNULL(@RenewalOfTermID, NULL) END,
                @CommittedAmount,
                CASE WHEN @EscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@EscalationPercent, NULL) END,
                CASE WHEN @EscalationBasis_Clear = 1 THEN NULL ELSE ISNULL(@EscalationBasis, NULL) END,
                @BillingFrequency,
                CASE WHEN @BillingAnchorMonth_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorMonth, NULL) END,
                CASE WHEN @BillingAnchorDay_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorDay, NULL) END,
                CASE WHEN @PaymentTermsTypeID_Clear = 1 THEN NULL ELSE ISNULL(@PaymentTermsTypeID, NULL) END,
                CASE WHEN @CurrencyID_Clear = 1 THEN NULL ELSE ISNULL(@CurrencyID, NULL) END,
                CASE WHEN @EarlyTerminationDate_Clear = 1 THEN NULL ELSE ISNULL(@EarlyTerminationDate, NULL) END,
                CASE WHEN @RenewalProbability_Clear = 1 THEN NULL ELSE ISNULL(@RenewalProbability, NULL) END,
                CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractTerms] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTerm] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Terms */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractTerm] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Terms */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: spUpdateContractTerm
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractTerm
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractTerm]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTerm];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractTerm]
    @ID uniqueidentifier,
    @ContractID uniqueidentifier = NULL,
    @TermNumber int = NULL,
    @StartDate date = NULL,
    @EndDate date = NULL,
    @Status nvarchar(20) = NULL,
    @RenewalOfTermID_Clear bit = 0,
    @RenewalOfTermID uniqueidentifier = NULL,
    @CommittedAmount decimal(19, 4) = NULL,
    @EscalationPercent_Clear bit = 0,
    @EscalationPercent decimal(7, 4) = NULL,
    @EscalationBasis_Clear bit = 0,
    @EscalationBasis nvarchar(20) = NULL,
    @BillingFrequency nvarchar(20) = NULL,
    @BillingAnchorMonth_Clear bit = 0,
    @BillingAnchorMonth tinyint = NULL,
    @BillingAnchorDay_Clear bit = 0,
    @BillingAnchorDay tinyint = NULL,
    @PaymentTermsTypeID_Clear bit = 0,
    @PaymentTermsTypeID uniqueidentifier = NULL,
    @CurrencyID_Clear bit = 0,
    @CurrencyID uniqueidentifier = NULL,
    @EarlyTerminationDate_Clear bit = 0,
    @EarlyTerminationDate date = NULL,
    @RenewalProbability_Clear bit = 0,
    @RenewalProbability decimal(5, 4) = NULL,
    @Notes_Clear bit = 0,
    @Notes nvarchar(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTerm]
    SET
        [ContractID] = ISNULL(@ContractID, [ContractID]),
        [TermNumber] = ISNULL(@TermNumber, [TermNumber]),
        [StartDate] = ISNULL(@StartDate, [StartDate]),
        [EndDate] = ISNULL(@EndDate, [EndDate]),
        [Status] = ISNULL(@Status, [Status]),
        [RenewalOfTermID] = CASE WHEN @RenewalOfTermID_Clear = 1 THEN NULL ELSE ISNULL(@RenewalOfTermID, [RenewalOfTermID]) END,
        [CommittedAmount] = ISNULL(@CommittedAmount, [CommittedAmount]),
        [EscalationPercent] = CASE WHEN @EscalationPercent_Clear = 1 THEN NULL ELSE ISNULL(@EscalationPercent, [EscalationPercent]) END,
        [EscalationBasis] = CASE WHEN @EscalationBasis_Clear = 1 THEN NULL ELSE ISNULL(@EscalationBasis, [EscalationBasis]) END,
        [BillingFrequency] = ISNULL(@BillingFrequency, [BillingFrequency]),
        [BillingAnchorMonth] = CASE WHEN @BillingAnchorMonth_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorMonth, [BillingAnchorMonth]) END,
        [BillingAnchorDay] = CASE WHEN @BillingAnchorDay_Clear = 1 THEN NULL ELSE ISNULL(@BillingAnchorDay, [BillingAnchorDay]) END,
        [PaymentTermsTypeID] = CASE WHEN @PaymentTermsTypeID_Clear = 1 THEN NULL ELSE ISNULL(@PaymentTermsTypeID, [PaymentTermsTypeID]) END,
        [CurrencyID] = CASE WHEN @CurrencyID_Clear = 1 THEN NULL ELSE ISNULL(@CurrencyID, [CurrencyID]) END,
        [EarlyTerminationDate] = CASE WHEN @EarlyTerminationDate_Clear = 1 THEN NULL ELSE ISNULL(@EarlyTerminationDate, [EarlyTerminationDate]) END,
        [RenewalProbability] = CASE WHEN @RenewalProbability_Clear = 1 THEN NULL ELSE ISNULL(@RenewalProbability, [RenewalProbability]) END,
        [Notes] = CASE WHEN @Notes_Clear = 1 THEN NULL ELSE ISNULL(@Notes, [Notes]) END
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractTerms] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractTerms]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTerm] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractTerm table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractTerm]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractTerm];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractTerm
ON [${flyway:defaultSchema}].[ContractTerm]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractTerm]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractTerm] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Terms */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractTerm] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Terms */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Terms
-- Item: spDeleteContractTerm
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractTerm
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractTerm]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTerm];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractTerm]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractTerm]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTerm] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Terms */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractTerm] TO [cdp_Developer], [cdp_Integration];

/* SQL text to update entity field related entity name field map for entity field ID 924B0E51-C6AC-4B7D-A9C8-52796C481635 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='924B0E51-C6AC-4B7D-A9C8-52796C481635', @RelatedEntityNameFieldMap='CustomerOrganization';

/* SQL text to update entity field related entity name field map for entity field ID 138D0EC7-3FC8-43ED-82B6-1A28589360FC */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='138D0EC7-3FC8-43ED-82B6-1A28589360FC', @RelatedEntityNameFieldMap='Subscription';

/* SQL text to update entity field related entity name field map for entity field ID 5B103310-2F07-49C4-8566-E086D0AF765C */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='5B103310-2F07-49C4-8566-E086D0AF765C', @RelatedEntityNameFieldMap='CustomerPerson';

/* Base View SQL for MJ_BizApps_Contracts: Contract Lines */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: vwContractLines
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contract Lines
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  ContractLine
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContractLines]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContractLines];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContractLines]
AS
SELECT
    c.*,
    mjBizAppsOrdersProduct_ProductID.[Name] AS [Product],
    mjBizAppsOrdersSubscriptionType_SubscriptionTypeID.[Name] AS [SubscriptionType],
    mjBizAppsOrdersSubscription_SubscriptionID.[SubscriptionNumber] AS [Subscription]
FROM
    [${flyway:defaultSchema}].[ContractLine] AS c
INNER JOIN
    [${mjSchema}_BizAppsOrders].[Product] AS mjBizAppsOrdersProduct_ProductID
  ON
    [c].[ProductID] = mjBizAppsOrdersProduct_ProductID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsOrders].[SubscriptionType] AS mjBizAppsOrdersSubscriptionType_SubscriptionTypeID
  ON
    [c].[SubscriptionTypeID] = mjBizAppsOrdersSubscriptionType_SubscriptionTypeID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsOrders].[Subscription] AS mjBizAppsOrdersSubscription_SubscriptionID
  ON
    [c].[SubscriptionID] = mjBizAppsOrdersSubscription_SubscriptionID.[ID]
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContractLines] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contract Lines */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: Permissions for vwContractLines
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContractLines] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contract Lines */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: spCreateContractLine
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR ContractLine
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContractLine]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContractLine];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContractLine]
    @ID uniqueidentifier = NULL,
    @ContractTermID uniqueidentifier,
    @ProductID uniqueidentifier,
    @LineType nvarchar(20),
    @Quantity decimal(18, 4) = NULL,
    @ContractedUnitPrice_Clear bit = 0,
    @ContractedUnitPrice decimal(19, 4) = NULL,
    @DiscountPct_Clear bit = 0,
    @DiscountPct decimal(7, 4) = NULL,
    @StartDate_Clear bit = 0,
    @StartDate date = NULL,
    @EndDate_Clear bit = 0,
    @EndDate date = NULL,
    @SubscriptionTypeID_Clear bit = 0,
    @SubscriptionTypeID uniqueidentifier = NULL,
    @SubscriptionID_Clear bit = 0,
    @SubscriptionID uniqueidentifier = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @DisplayOrder int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[ContractLine]
            (
                [ID],
                [ContractTermID],
                [ProductID],
                [LineType],
                [Quantity],
                [ContractedUnitPrice],
                [DiscountPct],
                [StartDate],
                [EndDate],
                [SubscriptionTypeID],
                [SubscriptionID],
                [Description],
                [DisplayOrder]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractTermID,
                @ProductID,
                @LineType,
                ISNULL(@Quantity, 1),
                CASE WHEN @ContractedUnitPrice_Clear = 1 THEN NULL ELSE ISNULL(@ContractedUnitPrice, NULL) END,
                CASE WHEN @DiscountPct_Clear = 1 THEN NULL ELSE ISNULL(@DiscountPct, NULL) END,
                CASE WHEN @StartDate_Clear = 1 THEN NULL ELSE ISNULL(@StartDate, NULL) END,
                CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, NULL) END,
                CASE WHEN @SubscriptionTypeID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionTypeID, NULL) END,
                CASE WHEN @SubscriptionID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionID, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@DisplayOrder, 0)
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[ContractLine]
            (
                [ContractTermID],
                [ProductID],
                [LineType],
                [Quantity],
                [ContractedUnitPrice],
                [DiscountPct],
                [StartDate],
                [EndDate],
                [SubscriptionTypeID],
                [SubscriptionID],
                [Description],
                [DisplayOrder]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractTermID,
                @ProductID,
                @LineType,
                ISNULL(@Quantity, 1),
                CASE WHEN @ContractedUnitPrice_Clear = 1 THEN NULL ELSE ISNULL(@ContractedUnitPrice, NULL) END,
                CASE WHEN @DiscountPct_Clear = 1 THEN NULL ELSE ISNULL(@DiscountPct, NULL) END,
                CASE WHEN @StartDate_Clear = 1 THEN NULL ELSE ISNULL(@StartDate, NULL) END,
                CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, NULL) END,
                CASE WHEN @SubscriptionTypeID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionTypeID, NULL) END,
                CASE WHEN @SubscriptionID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionID, NULL) END,
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                ISNULL(@DisplayOrder, 0)
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContractLines] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractLine] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contract Lines */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContractLine] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contract Lines */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: spUpdateContractLine
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR ContractLine
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContractLine]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContractLine];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContractLine]
    @ID uniqueidentifier,
    @ContractTermID uniqueidentifier = NULL,
    @ProductID uniqueidentifier = NULL,
    @LineType nvarchar(20) = NULL,
    @Quantity decimal(18, 4) = NULL,
    @ContractedUnitPrice_Clear bit = 0,
    @ContractedUnitPrice decimal(19, 4) = NULL,
    @DiscountPct_Clear bit = 0,
    @DiscountPct decimal(7, 4) = NULL,
    @StartDate_Clear bit = 0,
    @StartDate date = NULL,
    @EndDate_Clear bit = 0,
    @EndDate date = NULL,
    @SubscriptionTypeID_Clear bit = 0,
    @SubscriptionTypeID uniqueidentifier = NULL,
    @SubscriptionID_Clear bit = 0,
    @SubscriptionID uniqueidentifier = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @DisplayOrder int = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractLine]
    SET
        [ContractTermID] = ISNULL(@ContractTermID, [ContractTermID]),
        [ProductID] = ISNULL(@ProductID, [ProductID]),
        [LineType] = ISNULL(@LineType, [LineType]),
        [Quantity] = ISNULL(@Quantity, [Quantity]),
        [ContractedUnitPrice] = CASE WHEN @ContractedUnitPrice_Clear = 1 THEN NULL ELSE ISNULL(@ContractedUnitPrice, [ContractedUnitPrice]) END,
        [DiscountPct] = CASE WHEN @DiscountPct_Clear = 1 THEN NULL ELSE ISNULL(@DiscountPct, [DiscountPct]) END,
        [StartDate] = CASE WHEN @StartDate_Clear = 1 THEN NULL ELSE ISNULL(@StartDate, [StartDate]) END,
        [EndDate] = CASE WHEN @EndDate_Clear = 1 THEN NULL ELSE ISNULL(@EndDate, [EndDate]) END,
        [SubscriptionTypeID] = CASE WHEN @SubscriptionTypeID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionTypeID, [SubscriptionTypeID]) END,
        [SubscriptionID] = CASE WHEN @SubscriptionID_Clear = 1 THEN NULL ELSE ISNULL(@SubscriptionID, [SubscriptionID]) END,
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [DisplayOrder] = ISNULL(@DisplayOrder, [DisplayOrder])
    WHERE
        [ID] = @ID

    -- Check if the update was successful
    IF @@ROWCOUNT = 0
        -- Nothing was updated, return no rows, but column structure from base view intact, semantically correct this way.
        SELECT TOP 0 * FROM [${flyway:defaultSchema}].[vwContractLines] WHERE 1=0
    ELSE
        -- Return the updated record so the caller can see the updated values and any calculated fields
        SELECT
                                        *
                                    FROM
                                        [${flyway:defaultSchema}].[vwContractLines]
                                    WHERE
                                        [ID] = @ID
                                    
END
GO

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractLine] TO [cdp_Developer], [cdp_Integration]
GO

------------------------------------------------------------
----- TRIGGER FOR __mj_UpdatedAt field for the ContractLine table
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[trgUpdateContractLine]', 'TR') IS NOT NULL
    DROP TRIGGER [${flyway:defaultSchema}].[trgUpdateContractLine];
GO
CREATE TRIGGER [${flyway:defaultSchema}].trgUpdateContractLine
ON [${flyway:defaultSchema}].[ContractLine]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[ContractLine]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[ContractLine] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contract Lines */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContractLine] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contract Lines */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contract Lines
-- Item: spDeleteContractLine
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR ContractLine
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContractLine]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContractLine];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContractLine]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[ContractLine]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractLine] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contract Lines */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContractLine] TO [cdp_Developer], [cdp_Integration];

/* SQL text to update entity field related entity name field map for entity field ID D23140E8-C2B5-4C50-8B26-F88CDF1F84C4 */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='D23140E8-C2B5-4C50-8B26-F88CDF1F84C4', @RelatedEntityNameFieldMap='PrimaryContactPerson';

/* SQL text to update entity field related entity name field map for entity field ID B94F7E70-60B8-4C36-8A8D-63A1DEAEE6EE */
EXEC [${mjSchema}].[spUpdateEntityFieldRelatedEntityNameFieldMap] @EntityFieldID='B94F7E70-60B8-4C36-8A8D-63A1DEAEE6EE', @RelatedEntityNameFieldMap='OwnerUser';

/* Root ID Function SQL for MJ_BizApps_Contracts: Contracts.ParentContractID */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: fnContractParentContractID_GetRootID
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
------------------------------------------------------------
----- ROOT ID FUNCTION FOR: [Contract].[ParentContractID]
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]', 'IF') IS NOT NULL
    DROP FUNCTION [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID];
GO

CREATE FUNCTION [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]
(
    @RecordID uniqueidentifier,
    @ParentID uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    WITH CTE_RootParent AS (
        SELECT
            [ID],
            [ParentContractID],
            [ID] AS [RootParentID],
            0 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract]
        WHERE
            [ID] = COALESCE(@ParentID, @RecordID)

        UNION ALL

        SELECT
            c.[ID],
            c.[ParentContractID],
            c.[ID] AS [RootParentID],
            p.[Depth] + 1 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract] c
        INNER JOIN
            CTE_RootParent p ON c.[ID] = p.[ParentContractID]
        WHERE
            p.[Depth] < 100
    )
    SELECT TOP 1
        [RootParentID] AS RootID
    FROM
        CTE_RootParent
    WHERE
        [ParentContractID] IS NULL
    ORDER BY
        [RootParentID]
);
GO

/* Root ID Function SQL for MJ_BizApps_Contracts: Contracts.SupersededByContractID */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: fnContractSupersededByContractID_GetRootID
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------
------------------------------------------------------------
----- ROOT ID FUNCTION FOR: [Contract].[SupersededByContractID]
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]', 'IF') IS NOT NULL
    DROP FUNCTION [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID];
GO

CREATE FUNCTION [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]
(
    @RecordID uniqueidentifier,
    @ParentID uniqueidentifier
)
RETURNS TABLE
AS
RETURN
(
    WITH CTE_RootParent AS (
        SELECT
            [ID],
            [SupersededByContractID],
            [ID] AS [RootParentID],
            0 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract]
        WHERE
            [ID] = COALESCE(@ParentID, @RecordID)

        UNION ALL

        SELECT
            c.[ID],
            c.[SupersededByContractID],
            c.[ID] AS [RootParentID],
            p.[Depth] + 1 AS [Depth]
        FROM
            [${flyway:defaultSchema}].[Contract] c
        INNER JOIN
            CTE_RootParent p ON c.[ID] = p.[SupersededByContractID]
        WHERE
            p.[Depth] < 100
    )
    SELECT TOP 1
        [RootParentID] AS RootID
    FROM
        CTE_RootParent
    WHERE
        [SupersededByContractID] IS NULL
    ORDER BY
        [RootParentID]
);
GO

/* Base View SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: vwContracts
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- BASE VIEW FOR ENTITY:      MJ_BizApps_Contracts: Contracts
-----               SCHEMA:      ${flyway:defaultSchema}
-----               BASE TABLE:  Contract
-----               PRIMARY KEY: ID
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[vwContracts]', 'V') IS NOT NULL
    DROP VIEW [${flyway:defaultSchema}].[vwContracts];
GO

CREATE VIEW [${flyway:defaultSchema}].[vwContracts]
AS
SELECT
    c.*,
    mjBizAppsContractsContractType_ContractTypeID.[Name] AS [ContractType],
    MJCompany_CompanyID.[Name] AS [Company],
    mjBizAppsCommonOrganization_CustomerOrganizationID.[Name] AS [CustomerOrganization],
    mjBizAppsCommonPerson_CustomerPersonID.[DisplayName] AS [CustomerPerson],
    mjBizAppsCommonPerson_PrimaryContactPersonID.[DisplayName] AS [PrimaryContactPerson],
    MJUser_OwnerUserID.[Name] AS [OwnerUser],
    root_ParentContractID.RootID AS [RootParentContractID],
    root_SupersededByContractID.RootID AS [RootSupersededByContractID]
FROM
    [${flyway:defaultSchema}].[Contract] AS c
INNER JOIN
    [${flyway:defaultSchema}].[ContractType] AS mjBizAppsContractsContractType_ContractTypeID
  ON
    [c].[ContractTypeID] = mjBizAppsContractsContractType_ContractTypeID.[ID]
INNER JOIN
    [${mjSchema}].[Company] AS MJCompany_CompanyID
  ON
    [c].[CompanyID] = MJCompany_CompanyID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsCommon].[Organization] AS mjBizAppsCommonOrganization_CustomerOrganizationID
  ON
    [c].[CustomerOrganizationID] = mjBizAppsCommonOrganization_CustomerOrganizationID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsCommon].[Person] AS mjBizAppsCommonPerson_CustomerPersonID
  ON
    [c].[CustomerPersonID] = mjBizAppsCommonPerson_CustomerPersonID.[ID]
LEFT OUTER JOIN
    [${mjSchema}_BizAppsCommon].[Person] AS mjBizAppsCommonPerson_PrimaryContactPersonID
  ON
    [c].[PrimaryContactPersonID] = mjBizAppsCommonPerson_PrimaryContactPersonID.[ID]
LEFT OUTER JOIN
    [${mjSchema}].[User] AS MJUser_OwnerUserID
  ON
    [c].[OwnerUserID] = MJUser_OwnerUserID.[ID]
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractParentContractID_GetRootID]([c].[ID], [c].[ParentContractID]) AS root_ParentContractID
OUTER APPLY
    [${flyway:defaultSchema}].[fnContractSupersededByContractID_GetRootID]([c].[ID], [c].[SupersededByContractID]) AS root_SupersededByContractID
GO
GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* Base View Permissions SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: Permissions for vwContracts
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

GRANT SELECT ON [${flyway:defaultSchema}].[vwContracts] TO [cdp_UI], [cdp_Developer], [cdp_Integration];

/* spCreate SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spCreateContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- CREATE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spCreateContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spCreateContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spCreateContract]
    @ID uniqueidentifier = NULL,
    @ContractNumber nvarchar(50),
    @ContractTypeID uniqueidentifier,
    @CompanyID uniqueidentifier,
    @CustomerOrganizationID_Clear bit = 0,
    @CustomerOrganizationID uniqueidentifier = NULL,
    @CustomerPersonID_Clear bit = 0,
    @CustomerPersonID uniqueidentifier = NULL,
    @PrimaryContactPersonID_Clear bit = 0,
    @PrimaryContactPersonID uniqueidentifier = NULL,
    @OwnerUserID_Clear bit = 0,
    @OwnerUserID uniqueidentifier = NULL,
    @ParentContractID_Clear bit = 0,
    @ParentContractID uniqueidentifier = NULL,
    @SupersededByContractID_Clear bit = 0,
    @SupersededByContractID uniqueidentifier = NULL,
    @Status nvarchar(30) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @EffectiveDate_Clear bit = 0,
    @EffectiveDate date = NULL,
    @ExecutedDate_Clear bit = 0,
    @ExecutedDate date = NULL,
    @PricedAt_Clear bit = 0,
    @PricedAt date = NULL,
    @AutoRenew bit = NULL,
    @CancellationWindowDays_Clear bit = 0,
    @CancellationWindowDays int = NULL,
    @RenewalNoticeDays_Clear bit = 0,
    @RenewalNoticeDays int = NULL,
    @TerminationPolicy_Clear bit = 0,
    @TerminationPolicy nvarchar(MAX) = NULL,
    @ExternalReferenceID_Clear bit = 0,
    @ExternalReferenceID nvarchar(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @InsertedRow TABLE ([ID] UNIQUEIDENTIFIER)

    IF @ID IS NOT NULL
    BEGIN
        -- User provided a value, use it
        INSERT INTO [${flyway:defaultSchema}].[Contract]
            (
                [ID],
                [ContractNumber],
                [ContractTypeID],
                [CompanyID],
                [CustomerOrganizationID],
                [CustomerPersonID],
                [PrimaryContactPersonID],
                [OwnerUserID],
                [ParentContractID],
                [SupersededByContractID],
                [Status],
                [Description],
                [EffectiveDate],
                [ExecutedDate],
                [PricedAt],
                [AutoRenew],
                [CancellationWindowDays],
                [RenewalNoticeDays],
                [TerminationPolicy],
                [ExternalReferenceID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ID,
                @ContractNumber,
                @ContractTypeID,
                @CompanyID,
                CASE WHEN @CustomerOrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerOrganizationID, NULL) END,
                CASE WHEN @CustomerPersonID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerPersonID, NULL) END,
                CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, NULL) END,
                CASE WHEN @OwnerUserID_Clear = 1 THEN NULL ELSE ISNULL(@OwnerUserID, NULL) END,
                CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, NULL) END,
                CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, NULL) END,
                ISNULL(@Status, 'Draft'),
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, NULL) END,
                CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, NULL) END,
                CASE WHEN @PricedAt_Clear = 1 THEN NULL ELSE ISNULL(@PricedAt, NULL) END,
                ISNULL(@AutoRenew, 0),
                CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, NULL) END,
                CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, NULL) END,
                CASE WHEN @TerminationPolicy_Clear = 1 THEN NULL ELSE ISNULL(@TerminationPolicy, NULL) END,
                CASE WHEN @ExternalReferenceID_Clear = 1 THEN NULL ELSE ISNULL(@ExternalReferenceID, NULL) END
            )
    END
    ELSE
    BEGIN
        -- No value provided, let database use its default (e.g., NEWSEQUENTIALID())
        INSERT INTO [${flyway:defaultSchema}].[Contract]
            (
                [ContractNumber],
                [ContractTypeID],
                [CompanyID],
                [CustomerOrganizationID],
                [CustomerPersonID],
                [PrimaryContactPersonID],
                [OwnerUserID],
                [ParentContractID],
                [SupersededByContractID],
                [Status],
                [Description],
                [EffectiveDate],
                [ExecutedDate],
                [PricedAt],
                [AutoRenew],
                [CancellationWindowDays],
                [RenewalNoticeDays],
                [TerminationPolicy],
                [ExternalReferenceID]
            )
        OUTPUT INSERTED.[ID] INTO @InsertedRow
        VALUES
            (
                @ContractNumber,
                @ContractTypeID,
                @CompanyID,
                CASE WHEN @CustomerOrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerOrganizationID, NULL) END,
                CASE WHEN @CustomerPersonID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerPersonID, NULL) END,
                CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, NULL) END,
                CASE WHEN @OwnerUserID_Clear = 1 THEN NULL ELSE ISNULL(@OwnerUserID, NULL) END,
                CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, NULL) END,
                CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, NULL) END,
                ISNULL(@Status, 'Draft'),
                CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, NULL) END,
                CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, NULL) END,
                CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, NULL) END,
                CASE WHEN @PricedAt_Clear = 1 THEN NULL ELSE ISNULL(@PricedAt, NULL) END,
                ISNULL(@AutoRenew, 0),
                CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, NULL) END,
                CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, NULL) END,
                CASE WHEN @TerminationPolicy_Clear = 1 THEN NULL ELSE ISNULL(@TerminationPolicy, NULL) END,
                CASE WHEN @ExternalReferenceID_Clear = 1 THEN NULL ELSE ISNULL(@ExternalReferenceID, NULL) END
            )
    END
    -- return the new record from the base view, which might have some calculated fields
    SELECT * FROM [${flyway:defaultSchema}].[vwContracts] WHERE [ID] = (SELECT [ID] FROM @InsertedRow)
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] TO [cdp_Developer], [cdp_Integration];

/* spCreate Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spCreateContract] TO [cdp_Developer], [cdp_Integration];

/* spUpdate SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spUpdateContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- UPDATE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spUpdateContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spUpdateContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spUpdateContract]
    @ID uniqueidentifier,
    @ContractNumber nvarchar(50) = NULL,
    @ContractTypeID uniqueidentifier = NULL,
    @CompanyID uniqueidentifier = NULL,
    @CustomerOrganizationID_Clear bit = 0,
    @CustomerOrganizationID uniqueidentifier = NULL,
    @CustomerPersonID_Clear bit = 0,
    @CustomerPersonID uniqueidentifier = NULL,
    @PrimaryContactPersonID_Clear bit = 0,
    @PrimaryContactPersonID uniqueidentifier = NULL,
    @OwnerUserID_Clear bit = 0,
    @OwnerUserID uniqueidentifier = NULL,
    @ParentContractID_Clear bit = 0,
    @ParentContractID uniqueidentifier = NULL,
    @SupersededByContractID_Clear bit = 0,
    @SupersededByContractID uniqueidentifier = NULL,
    @Status nvarchar(30) = NULL,
    @Description_Clear bit = 0,
    @Description nvarchar(MAX) = NULL,
    @EffectiveDate_Clear bit = 0,
    @EffectiveDate date = NULL,
    @ExecutedDate_Clear bit = 0,
    @ExecutedDate date = NULL,
    @PricedAt_Clear bit = 0,
    @PricedAt date = NULL,
    @AutoRenew bit = NULL,
    @CancellationWindowDays_Clear bit = 0,
    @CancellationWindowDays int = NULL,
    @RenewalNoticeDays_Clear bit = 0,
    @RenewalNoticeDays int = NULL,
    @TerminationPolicy_Clear bit = 0,
    @TerminationPolicy nvarchar(MAX) = NULL,
    @ExternalReferenceID_Clear bit = 0,
    @ExternalReferenceID nvarchar(255) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE
        [${flyway:defaultSchema}].[Contract]
    SET
        [ContractNumber] = ISNULL(@ContractNumber, [ContractNumber]),
        [ContractTypeID] = ISNULL(@ContractTypeID, [ContractTypeID]),
        [CompanyID] = ISNULL(@CompanyID, [CompanyID]),
        [CustomerOrganizationID] = CASE WHEN @CustomerOrganizationID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerOrganizationID, [CustomerOrganizationID]) END,
        [CustomerPersonID] = CASE WHEN @CustomerPersonID_Clear = 1 THEN NULL ELSE ISNULL(@CustomerPersonID, [CustomerPersonID]) END,
        [PrimaryContactPersonID] = CASE WHEN @PrimaryContactPersonID_Clear = 1 THEN NULL ELSE ISNULL(@PrimaryContactPersonID, [PrimaryContactPersonID]) END,
        [OwnerUserID] = CASE WHEN @OwnerUserID_Clear = 1 THEN NULL ELSE ISNULL(@OwnerUserID, [OwnerUserID]) END,
        [ParentContractID] = CASE WHEN @ParentContractID_Clear = 1 THEN NULL ELSE ISNULL(@ParentContractID, [ParentContractID]) END,
        [SupersededByContractID] = CASE WHEN @SupersededByContractID_Clear = 1 THEN NULL ELSE ISNULL(@SupersededByContractID, [SupersededByContractID]) END,
        [Status] = ISNULL(@Status, [Status]),
        [Description] = CASE WHEN @Description_Clear = 1 THEN NULL ELSE ISNULL(@Description, [Description]) END,
        [EffectiveDate] = CASE WHEN @EffectiveDate_Clear = 1 THEN NULL ELSE ISNULL(@EffectiveDate, [EffectiveDate]) END,
        [ExecutedDate] = CASE WHEN @ExecutedDate_Clear = 1 THEN NULL ELSE ISNULL(@ExecutedDate, [ExecutedDate]) END,
        [PricedAt] = CASE WHEN @PricedAt_Clear = 1 THEN NULL ELSE ISNULL(@PricedAt, [PricedAt]) END,
        [AutoRenew] = ISNULL(@AutoRenew, [AutoRenew]),
        [CancellationWindowDays] = CASE WHEN @CancellationWindowDays_Clear = 1 THEN NULL ELSE ISNULL(@CancellationWindowDays, [CancellationWindowDays]) END,
        [RenewalNoticeDays] = CASE WHEN @RenewalNoticeDays_Clear = 1 THEN NULL ELSE ISNULL(@RenewalNoticeDays, [RenewalNoticeDays]) END,
        [TerminationPolicy] = CASE WHEN @TerminationPolicy_Clear = 1 THEN NULL ELSE ISNULL(@TerminationPolicy, [TerminationPolicy]) END,
        [ExternalReferenceID] = CASE WHEN @ExternalReferenceID_Clear = 1 THEN NULL ELSE ISNULL(@ExternalReferenceID, [ExternalReferenceID]) END
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
    UPDATE
        [${flyway:defaultSchema}].[Contract]
    SET
        __mj_UpdatedAt = GETUTCDATE()
    FROM
        [${flyway:defaultSchema}].[Contract] AS _organicTable
    INNER JOIN
        INSERTED AS I ON
        _organicTable.[ID] = I.[ID];
END;
GO

/* spUpdate Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spUpdateContract] TO [cdp_Developer], [cdp_Integration];

/* spDelete SQL for MJ_BizApps_Contracts: Contracts */
-----------------------------------------------------------------
-- SQL Code Generation
-- Entity: MJ_BizApps_Contracts: Contracts
-- Item: spDeleteContract
--
-- This was generated by the MemberJunction CodeGen tool.
-- This file should NOT be edited by hand.
-----------------------------------------------------------------

------------------------------------------------------------
----- DELETE PROCEDURE FOR Contract
------------------------------------------------------------
IF OBJECT_ID('[${flyway:defaultSchema}].[spDeleteContract]', 'P') IS NOT NULL
    DROP PROCEDURE [${flyway:defaultSchema}].[spDeleteContract];
GO

CREATE PROCEDURE [${flyway:defaultSchema}].[spDeleteContract]
    @ID uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;

    DELETE FROM
        [${flyway:defaultSchema}].[Contract]
    WHERE
        [ID] = @ID


    -- Check if the delete was successful
    IF @@ROWCOUNT = 0
        SELECT NULL AS [ID] -- Return NULL for all primary key fields to indicate no record was deleted
    ELSE
        SELECT @ID AS [ID] -- Return the primary key values to indicate we successfully deleted the record
END
GO
GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* spDelete Permissions for MJ_BizApps_Contracts: Contracts */

GRANT EXECUTE ON [${flyway:defaultSchema}].[spDeleteContract] TO [cdp_Developer], [cdp_Integration];

/* SQL text to delete unneeded entity fields */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to insert 17 new entity field(s) */

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2c2e8456-c400-4c8b-84d7-bdc857261ad3' OR (EntityID = 'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6' AND Name = 'PerformedByUser')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2c2e8456-c400-4c8b-84d7-bdc857261ad3',
            'F2DDDC7E-A21C-4FCA-96FE-0B73E2C6F2B6', -- Entity: MJ_BizApps_Contracts: Contract Events
            100019,
            'PerformedByUser',
            'Performed By User',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8d12897a-6711-4ebb-aff8-c73ebf2c6786' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'ContractType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8d12897a-6711-4ebb-aff8-c73ebf2c6786',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100045,
            'ContractType',
            'Contract Type',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'a5a289f9-0ba0-4ff7-a37e-e7802ebdc8cf' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'Company')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'a5a289f9-0ba0-4ff7-a37e-e7802ebdc8cf',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100046,
            'Company',
            'Company',
            NULL,
            'nvarchar',
            100,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '2fdd6a07-0e00-4f92-9d49-a650b2b52e9c' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CustomerOrganization')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '2fdd6a07-0e00-4f92-9d49-a650b2b52e9c',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100047,
            'CustomerOrganization',
            'Customer Organization',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '6c52c605-5c20-4e9c-9e5f-95fc14f03249' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'CustomerPerson')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '6c52c605-5c20-4e9c-9e5f-95fc14f03249',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100048,
            'CustomerPerson',
            'Customer Person',
            NULL,
            'nvarchar',
            402,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '3c87fb0f-4620-4076-ad41-35282b12dbca' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'PrimaryContactPerson')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '3c87fb0f-4620-4076-ad41-35282b12dbca',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100049,
            'PrimaryContactPerson',
            'Primary Contact Person',
            NULL,
            'nvarchar',
            402,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'f619db60-e842-4fc7-a113-fc1584743e4d' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'OwnerUser')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'f619db60-e842-4fc7-a113-fc1584743e4d',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100050,
            'OwnerUser',
            'Owner User',
            NULL,
            'nvarchar',
            200,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '8abf5332-efb5-4655-ace4-168d23b37ca6' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'RootParentContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '8abf5332-efb5-4655-ace4-168d23b37ca6',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100051,
            'RootParentContractID',
            'Root Parent Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'ebd3caf2-7c8a-42c0-9e53-473c00cd0d1b' OR (EntityID = '82943343-8584-4023-9B36-385482D5DE51' AND Name = 'RootSupersededByContractID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'ebd3caf2-7c8a-42c0-9e53-473c00cd0d1b',
            '82943343-8584-4023-9B36-385482D5DE51', -- Entity: MJ_BizApps_Contracts: Contracts
            100052,
            'RootSupersededByContractID',
            'Root Superseded By Contract ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'eb5fe377-750c-461c-bdd6-9bcaf20a6ebd' OR (EntityID = '57F99C92-591B-4F35-82D9-83F6B330D8F1' AND Name = 'Order')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'eb5fe377-750c-461c-bdd6-9bcaf20a6ebd',
            '57F99C92-591B-4F35-82D9-83F6B330D8F1', -- Entity: MJ_BizApps_Contracts: Contract Billing Events
            100025,
            'Order',
            'Order',
            NULL,
            'nvarchar',
            80,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'd8aa2019-f3fb-4c1e-a22a-86e7d9c0054e' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'Product')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'd8aa2019-f3fb-4c1e-a22a-86e7d9c0054e',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100031,
            'Product',
            'Product',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            0,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'b8d2a249-082e-4dee-9c4b-802467963152' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'SubscriptionType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'b8d2a249-082e-4dee-9c4b-802467963152',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100032,
            'SubscriptionType',
            'Subscription Type',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '365a7fd8-45d5-4253-8aba-bb7d81cc6d66' OR (EntityID = '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9' AND Name = 'Subscription')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '365a7fd8-45d5-4253-8aba-bb7d81cc6d66',
            '5B88DAFC-A8C4-4554-B1C9-BE4F015140A9', -- Entity: MJ_BizApps_Contracts: Contract Lines
            100033,
            'Subscription',
            'Subscription',
            NULL,
            'nvarchar',
            80,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '58e625ed-297a-4438-94f2-6d418a49d050' OR (EntityID = '39D1F825-0D1A-4292-A0F2-C168E145C210' AND Name = 'ApprovalTask')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '58e625ed-297a-4438-94f2-6d418a49d050',
            '39D1F825-0D1A-4292-A0F2-C168E145C210', -- Entity: MJ_BizApps_Contracts: Contract Amendments
            100021,
            'ApprovalTask',
            'Approval Task',
            NULL,
            'nvarchar',
            510,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '4fa6bedf-f760-4e28-a167-b3bc7bdddd2b' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'PaymentTermsType')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '4fa6bedf-f760-4e28-a167-b3bc7bdddd2b',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100041,
            'PaymentTermsType',
            'Payment Terms Type',
            NULL,
            'nvarchar',
            400,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = 'bcae864f-5e6a-4b21-a4b0-fb1fc00023fc' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'Currency')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            'bcae864f-5e6a-4b21-a4b0-fb1fc00023fc',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100042,
            'Currency',
            'Currency',
            NULL,
            'nvarchar',
            160,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

      IF NOT EXISTS (SELECT 1 FROM [${mjSchema}].[EntityField] WHERE ID = '74d5a2c1-7f97-4426-9dcc-45306d059008' OR (EntityID = '317F4FD7-0CDD-4B17-973E-D55944D03DEE' AND Name = 'RootRenewalOfTermID')) BEGIN
         INSERT INTO [${mjSchema}].[EntityField]
         (
            [ID],
            [EntityID],
            [Sequence],
            [Name],
            [DisplayName],
            [Description],
            [Type],
            [Length],
            [Precision],
            [Scale],
            [AllowsNull],
            [DefaultValue],
            [AutoIncrement],
            [AllowUpdateAPI],
            [IsVirtual],
            [IsComputed],
            [RelatedEntityID],
            [RelatedEntityFieldName],
            [IsNameField],
            [IncludeInUserSearchAPI],
            [IncludeRelatedEntityNameFieldInBaseView],
            [DefaultInView],
            [IsPrimaryKey],
            [IsUnique],
            [RelatedEntityDisplayType],
            [__mj_CreatedAt],
            [__mj_UpdatedAt]
         )
         VALUES
         (
            '74d5a2c1-7f97-4426-9dcc-45306d059008',
            '317F4FD7-0CDD-4B17-973E-D55944D03DEE', -- Entity: MJ_BizApps_Contracts: Contract Terms
            100043,
            'RootRenewalOfTermID',
            'Root Renewal Of Term ID',
            NULL,
            'uniqueidentifier',
            16,
            0,
            0,
            1,
            NULL,
            0,
            0,
            1,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            0,
            0,
            0,
            'Search',
            GETUTCDATE(),
            GETUTCDATE()
         )
      END;

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

-- CodeGen Output — Run #2 (regenerated after `mj sync push` applied metadata config)
/* SQL text to update existing entities from schema */
EXEC [${mjSchema}].[spUpdateExistingEntitiesFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to sync schema info from database schemas */
EXEC [${mjSchema}].[spUpdateSchemaInfoFromDatabase] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to delete unneeded entity fields */
EXEC [${mjSchema}].[spDeleteUnneededEntityFields] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to update existing entity fields from schema */
EXEC [${mjSchema}].[spUpdateExistingEntityFieldsFromSchema] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

/* SQL text to set default column width where needed */
EXEC [${mjSchema}].[spSetDefaultColumnWidthWhereNeeded] @ExcludedSchemaNames='sys,staging,dbo,${mjSchema},${mjSchema}_BizAppsCommon,${mjSchema}_BizAppsTasks,${mjSchema}_BizAppsAccounting,${mjSchema}_BizAppsOrders,${mjSchema}';

