-- =============================================================================
--  BizApps Contracts — schema, SchemaInfo registration, and shared TYPES.
--
--  SPLIT FROM THE MAIN BASELINE ON PURPOSE, following bizapps-orders.
--
--  Migrations run as ONE TRANSACTION PER FILE (skyway wraps each file). A trigger that
--  declares a variable of a user-defined table type must not be COMPILED inside the same
--  transaction that created the type — SQL Server needs a schema lock on the type to compile
--  the trigger body, the creating transaction still holds it, and the statement dies with
--  `Msg 1205 ... deadlocked with another process` on a single-connection run. That reads as
--  server instability rather than an ordering bug, and orders spent real effort diagnosing it.
--
--  This app declares NO table types yet. The file exists anyway so that the first rollup
--  trigger this schema acquires — ContractCommitment.ConsumedAmount is the obvious candidate —
--  has somewhere to put its type without restructuring a baseline that is already applied
--  elsewhere. Splitting later costs a coordinated rebuild; splitting now costs this comment.
--
--  Everything else lives in the sibling V...__Tables_and_Objects.sql.
-- =============================================================================

-- =============================================================================
-- BizApps Contracts — Baseline Schema (v0.1.0)
-- =============================================================================
-- Creates the entire __mj_BizAppsContracts schema: the agreement envelope —
-- commitment, term structure, escalation, renewal, and the BILLING EVENT that
-- consolidates many revenue streams onto one document.
--
-- Design source of truth is NOT this repo. It is
--   BlueCypress/new-products/sales-deal-management/plans/02-bizapps-contracts.md
-- with the parent plan's decision log (L-10..L-12, L-15, L-18) governing.
--
-- WHAT THIS APP DOES NOT DO, restated here because a schema is where the
-- temptation starts: it does not price, tax, prorate, book journal entries, or
-- capture payments. Every number on a contract-generated bill comes back from
-- Orders.PreviewOrder. There is deliberately no computed-total column anywhere
-- in this schema for the engine to "just cache" — ContractBillingEvent.ComputedAmount
-- is a STAMP of what orders returned, not a figure derived here.
--
-- THE REFERENCE THAT MUST NEVER BE ADDED (L-15): there is no Contract.DealID,
-- hard or soft. bizapps-sales sits ABOVE this app, so a reference upward inverts
-- the dependency graph — the same rule that removed Order.ContractID from orders
-- (D44). And the cardinality is one contract to MANY deals: the original sale is
-- a deal, every renewal is another, expansions are more. A single Contract.DealID
-- could only ever name one of them and would silently degrade into "whichever deal
-- we happened to write last". The reverse lookup lives in sales as Deal.ContractID
-- and Deal.RenewsContractID, and correctly returns a SET.
--
-- CROSS-APP REFERENCES ARE REAL FOREIGN KEYS, not soft UUID columns.
-- BizApps install in dependency order, so bizapps-common, bizapps-accounting and
-- bizapps-orders are already present when this migration runs, and the DATABASE —
-- not convention — enforces referential integrity across app schemas. This follows
-- the corrected cross-app hardness standard (Amith 2026-08-03; the prior
-- soft-ref-until-CodeGen-include-mode ruling is withdrawn):
--   * -> __mj.Company / User / File
--       Contract.CompanyID, Contract.OwnerUserID, Contract.DocumentFileID,
--       ContractAmendment.DocumentFileID, ContractEvent.PerformedByUserID
--   * -> __mj_BizAppsCommon.Organization / Person
--       Contract.CustomerOrganizationID, Contract.CustomerPersonID,
--       Contract.PrimaryContactPersonID
--   * -> __mj_BizAppsOrders.Product / Subscription / OrderHeader / PaymentTermsType
--       ContractLine.ProductID, ContractLine.SubscriptionID,
--       ContractBillingEvent.OrderID, ContractTerm.PaymentTermsTypeID
--   * -> __mj_BizAppsAccounting.Currency
--       ContractTerm.CurrencyID (recorded for forward-compatibility only; orders
--       defers FX per D24 and NOTHING in this app converts between currencies)
--
-- ONE reference stays SOFT, and the reason is narrow and temporary:
--   * ContractAmendment.ApprovalTaskID -> bizapps-tasks
--     Soft because the target app IS NOT INSTALLED in this chain yet, exactly the
--     reason orders left Order.ApprovalTaskID soft — NOT because the coupling is
--     unwanted, and NOT the withdrawn tooling-defect rationale. Tasks is a required
--     dependency of this app (approval gates on non-standard terms, discounts beyond
--     a rep's SalesAuthority, early-termination waivers). The day tasks joins the
--     install chain this becomes a hard, nullable FK. See the TODO at §4.B.
--
-- INSTALL-ORDER DEPENDENCY: bizapps-common, bizapps-accounting and bizapps-orders
-- MUST be installed BEFORE bizapps-contracts. Applying this migration without them
-- fails at §4.A — deliberately, as the dependency check.
--
-- CodeGen handles __mj_CreatedAt/__mj_UpdatedAt and FK indexes — do NOT add them here.
-- SQL Server is the source of truth; the PostgreSQL counterpart is produced via
-- @memberjunction/sql-converter.
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
