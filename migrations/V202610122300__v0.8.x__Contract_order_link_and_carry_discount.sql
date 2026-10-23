-- =============================================================================
-- V202610122300 — ContractOrder, the link from a contract to the orders it
--                 produced, and Contract.CarryDiscountOnRenewal (issue #77)
-- =============================================================================
-- Orders reprices a renewal from two fields on the subscription:
-- RenewalIncreasePercent and CarryDiscountOnRenewal. The contract is where the
-- negotiated values are recorded, but nothing could carry them over: a contract
-- named its customer and nothing it governs, and Orders cannot reference this
-- app because foreign keys point up the install order, never down.
--
-- WHY THE LINK NAMES ORDERS, NOT SUBSCRIPTIONS. The order a deal produced is
-- known the moment the deal closes. Its subscriptions are created by Orders as
-- the order is processed, so at close they may not exist yet. Each subscription
-- names the order line that created it, so a contract's subscriptions are
-- derived as ContractOrder -> OrderLine -> Subscription whenever the terms are
-- pushed, and a subscription created later is found on the next push. One
-- contract links to many orders (the original sale, expansions, renewals), and
-- an order may be governed by more than one contract.
--
-- CarryDiscountOnRenewal records what the paper says: a first-term discount
-- continues into renewal terms (a multi-year concession). It defaults to 0, the
-- rule finance set for every renewal. The uplift needs no new column:
-- AnnualIncreasePercent already holds it, seeded from the contract type.
--
-- Plain DDL: no existence guards. Migrations run once, in order.
--
-- Install order: this file's foreign key to __mj_BizAppsOrders.OrderHeader is
-- why mj-app.json now depends on mj-bizapps-orders.
-- =============================================================================

CREATE TABLE [${flyway:defaultSchema}].[ContractOrder] (
    [ID] UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT [DF_ContractOrder_ID] DEFAULT NEWSEQUENTIALID(),
    [ContractID] UNIQUEIDENTIFIER NOT NULL,
    [OrderID] UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT [PK_ContractOrder] PRIMARY KEY ([ID]),
    CONSTRAINT [UQ_ContractOrder_ContractOrder] UNIQUE ([ContractID], [OrderID]),
    CONSTRAINT [FK_ContractOrder_Contract]
        FOREIGN KEY ([ContractID]) REFERENCES [${flyway:defaultSchema}].[Contract] ([ID]),
    CONSTRAINT [FK_ContractOrder_OrderHeader]
        FOREIGN KEY ([OrderID]) REFERENCES [${mjSchema}_BizAppsOrders].[OrderHeader] ([ID])
);
GO

-- The unique constraint leads with ContractID, which serves "this contract's
-- orders". The reverse question, "which contracts govern this order", gets its own.
CREATE NONCLUSTERED INDEX [IX_ContractOrder_OrderID]
    ON [${flyway:defaultSchema}].[ContractOrder] ([OrderID]);
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'An order this contract governs. The contract''s renewal terms (annual increase, whether a discount continues) are copied to every subscription the order''s lines created. Written when a deal closes with both a contract and an order, or by hand for an order the contract covers.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'The contract whose terms apply to the order.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder',
    @level2type=N'COLUMN', @level2name=N'ContractID';
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'The order the contract governs. Its subscriptions are found through its lines each time the terms are copied, so subscriptions created after the link still receive them.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'ContractOrder',
    @level2type=N'COLUMN', @level2name=N'OrderID';
GO

ALTER TABLE [${flyway:defaultSchema}].[Contract] ADD
    [CarryDiscountOnRenewal] BIT NOT NULL
        CONSTRAINT [DF_Contract_CarryDiscountOnRenewal] DEFAULT (0);
GO

EXEC sp_addextendedproperty @name=N'MS_Description',
    @value=N'Whether the paper says a first-term discount continues into renewal terms, for example a multi-year concession. Off by default: a discount lapses at renewal. Copied to the subscriptions of every order linked to this contract, where the renewal pass reads it.',
    @level0type=N'SCHEMA', @level0name=N'${flyway:defaultSchema}',
    @level1type=N'TABLE',  @level1name=N'Contract',
    @level2type=N'COLUMN', @level2name=N'CarryDiscountOnRenewal';
GO
