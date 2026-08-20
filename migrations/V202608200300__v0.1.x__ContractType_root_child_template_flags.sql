-- =============================================================================
-- V202608200300 — ParentStatusRequirement becomes two booleans, and the type gains
--                 TemplateRequired.
-- =============================================================================
-- THIS REWORKS SHIPPED CODE, DELIBERATELY. `ParentStatusRequirement` was merged in PR #10
-- ten days ago -- the column, its CHECK, its metadata seed, the `typeRule()` read and both
-- branches of the server validation. Dropping it is part of this change rather than a
-- follow-up, because two overlapping mechanisms for one rule is worse than either.
--
-- RULED (Marcelo, 2026-08-20): the three-state string was confusing and overly complex, and
-- the transposition argument is the proof -- a column whose values INVERT the rule when read
-- in the wrong order is a column that will eventually be read in the wrong order.
--
--     MustBeRoot  BIT NOT NULL DEFAULT 0   -- may not name a ParentContractID
--     MustBeChild BIT NOT NULL DEFAULT 0   -- must name one
--     CHECK (NOT (MustBeRoot = 1 AND MustBeChild = 1))
--
-- Both false = no restriction on where in the tree this type may sit, which is the honest
-- default and what three of the four seeded types want.
--
-- ⚠ THE MIGRATION THIS SUPERSEDES ARGUED AGAINST EXACTLY THIS CHANGE, and the counter-argument
-- is worth answering rather than ignoring. V202608192100's own header says: *"A bit pair
-- (CanHaveParent / MustHaveParent) would also encode 'neither', which is not a state that means
-- anything."* That objection does not survive contact with the flags actually chosen: the pair
-- here is MustBeRoot / MustBeChild, and "neither" means **unrestricted** -- a real, wanted,
-- and in fact majority state. The objection was aimed at a different pair of flags than the
-- one being adopted.
--
-- WHY THE CHECK IS THE RIGHT TIER. "Only one of these may be true" reads only columns of the
-- same row, so it needs no trigger and no code -- and CodeGen turns it into a TypeScript
-- validator for free, exactly as it does for the two-column
-- CK_Contract_CreatingPairBothOrNeither. No hand-written counterpart; that is the R-2 trap.
--
-- TemplateRequired: whether a contract of this type must carry its own ContractTemplateID.
-- Today only the root type needs one, but it belongs on the TYPE rather than being inferred
-- from the parent flags, because those answer a different question (where in the tree) and a
-- future type could want any combination.
--
-- NO SEED VALUES HERE -- same ruling as V202608192100. `metadata/contract-types/` owns all four
-- rows with fixed UUIDs, so the values arrive via `mj sync push`. A migration that also set
-- them would give one fact two owners and the migration's copy would silently win on a fresh
-- install until the next push.
-- =============================================================================

-- 1. The three new flags. Idempotent per column so a partial re-run completes.
IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'MustBeRoot') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [MustBeRoot] BIT NOT NULL CONSTRAINT [DF_ContractType_MustBeRoot] DEFAULT 0;
GO
IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'MustBeChild') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [MustBeChild] BIT NOT NULL CONSTRAINT [DF_ContractType_MustBeChild] DEFAULT 0;
GO
IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'TemplateRequired') IS NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] ADD [TemplateRequired] BIT NOT NULL CONSTRAINT [DF_ContractType_TemplateRequired] DEFAULT 0;
GO

-- 2. Only one of the two placement flags may be set.
IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE [parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractType]')
       AND [name] = 'CK_ContractType_RootOrChild'
)
BEGIN
    ALTER TABLE [${flyway:defaultSchema}].[ContractType]
        ADD CONSTRAINT [CK_ContractType_RootOrChild]
            CHECK (NOT ([MustBeRoot] = 1 AND [MustBeChild] = 1));
END
GO

EXEC sp_addextendedproperty @name = N'MS_Description',
    @value = N'This type of contract may NOT name a ParentContractID — it is a root agreement. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeChild (CK_ContractType_RootOrChild); both false means no restriction on where in the tree this type may sit, which is the honest default.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractType',
    @level2type = N'COLUMN', @level2name = N'MustBeRoot';
GO
EXEC sp_addextendedproperty @name = N'MS_Description',
    @value = N'This type of contract MUST name a ParentContractID — a Change Order that amends nothing is not a change order, and would never appear in the original agreement''s lineage. Enforced in ContractEntityServer.ValidateAsync. Mutually exclusive with MustBeRoot.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractType',
    @level2type = N'COLUMN', @level2name = N'MustBeChild';
GO
EXEC sp_addextendedproperty @name = N'MS_Description',
    @value = N'This type of contract must carry its own ContractTemplateID — the standard terms it incorporates. On the TYPE rather than inferred from the placement flags, because "where in the tree" and "does it need its own paper" are different questions and a future type could want any combination.',
    @level0type = N'SCHEMA', @level0name = N'${flyway:defaultSchema}',
    @level1type = N'TABLE',  @level1name = N'ContractType',
    @level2type = N'COLUMN', @level2name = N'TemplateRequired';
GO

-- 3. Retire ParentStatusRequirement: its CHECK, then its EntityField metadata row, then the
--    column. The metadata row goes BEFORE the column so MJ is never describing a column that
--    does not exist -- the IsChangeOrder trap, which surfaces as a null-valued field on every
--    form rather than as an error. (CodeGen would also remove it on the next run; doing it here
--    means the database is never in the inconsistent state, even briefly.)
IF EXISTS (
    SELECT 1 FROM sys.check_constraints
     WHERE [parent_object_id] = OBJECT_ID('[${flyway:defaultSchema}].[ContractType]')
       AND [name] = 'CK_ContractType_ParentStatusRequirement'
)
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] DROP CONSTRAINT [CK_ContractType_ParentStatusRequirement];
GO

--    ⚠ EntityFieldValue FIRST. CodeGen rendered `CHECK (ParentStatusRequirement IN ('Required',
--    'Prohibited'))` as VALUE-LIST metadata -- two EntityFieldValue rows -- rather than as a validator
--    (that is R-9's whole subject). Those rows are FK children of the EntityField, so deleting the
--    field without them fails on FK_EntityFieldValue_EntityField. The complete FK-child set of
--    __mj.EntityField was read off sys.foreign_keys rather than discovered one error per attempt;
--    EntityFieldValue is the only one carrying rows here.
DECLARE @psrFieldID UNIQUEIDENTIFIER = (
    SELECT f.[ID]
      FROM [${mjSchema}].[EntityField] f
     INNER JOIN [${mjSchema}].[Entity] e ON e.[ID] = f.[EntityID]
     WHERE e.[SchemaName] = '${flyway:defaultSchema}'
       AND e.[BaseTable]  = 'ContractType'
       AND f.[Name]       = 'ParentStatusRequirement'
);

IF @psrFieldID IS NOT NULL
BEGIN
    DELETE FROM [${mjSchema}].[EntityFieldValue] WHERE [EntityFieldID] = @psrFieldID;
    DELETE FROM [${mjSchema}].[EntityField]      WHERE [ID]            = @psrFieldID;
END
GO

IF COL_LENGTH('${flyway:defaultSchema}.ContractType', 'ParentStatusRequirement') IS NOT NULL
    ALTER TABLE [${flyway:defaultSchema}].[ContractType] DROP COLUMN [ParentStatusRequirement];
GO
