/**
 * fixture.ts — the shared reference data every contracts bundle writes against, plus the
 * transaction discipline that makes the suite re-runnable.
 *
 * ISOLATION MODEL — the reason this package exists at all.
 *
 * The tier-2 `tsx` harnesses this replaces created real rows and deleted them again in an
 * FK-ordered teardown walk. That works right up until a check throws partway through, at which
 * point the walk never runs and the leftovers are real contracts in the demo database. This suite
 * takes the stronger option, the one bizapps-orders already uses:
 *
 *   - The FIXTURE (the contract type, and the company/organization/products it references) is
 *     resolved ONCE per bundle and committed — or, where possible, merely READ. It is inert.
 *   - Every MUTATING check runs inside its own provider transaction and ROLLS BACK. Contracts,
 *     terms, coverage and billing events never reach disk. There is no teardown to forget.
 *
 * The contract entity opens its own transaction for the tree write, and each term opens another
 * inside that; SQL Server turns those into savepoints beneath the check's outer transaction, and
 * they commit and roll back correctly at that depth.
 *
 * THE ONE RULE THAT FOLLOWS: **every query goes through the PROVIDER** ({@link TxQuery}), never
 * `ctx.Pool`. Two independent reasons, either sufficient:
 *   1. The pool is a DIFFERENT connection. Under READ COMMITTED it BLOCKS on the open check
 *      transaction's write locks until the request times out — and the failure reads like a broken
 *      engine rather than like contention.
 *   2. `ctx.Pool` is only populated when the driver owned the bootstrap. Under `mj test` the CLI
 *      installs the instrumented cache first, so it arrives undefined.
 *
 * This matters more here than anywhere: the raw-SQL bypass proofs — the ones that check a rollback
 * really removed the rows — are exactly the queries that would deadlock against themselves if they
 * went out on a second connection.
 *
 * @module @mj-biz-apps/contracts-integration-tests
 */

import { Metadata, RunView, type IMetadataProvider, type UserInfo } from '@memberjunction/core';
import { Assert, type IntegrationCheckContext } from '@memberjunction/testing-integration';

export const CONTRACTS_SCHEMA = '__mj_BizAppsContracts';

export const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
export const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
export const E_LINE = 'MJ_BizApps_Contracts: Contract Lines';
export const E_SCHEDULE = 'MJ_BizApps_Contracts: Contract Billing Schedules';
export const E_COMMITMENT = 'MJ_BizApps_Contracts: Contract Commitments';
export const E_BILLING_EVENT = 'MJ_BizApps_Contracts: Contract Billing Events';
export const E_AMENDMENT = 'MJ_BizApps_Contracts: Contract Amendments';
export const E_EVENT = 'MJ_BizApps_Contracts: Contract Events';
export const E_TYPE = 'MJ_BizApps_Contracts: Contract Types';

/** The reference rows a contract needs to exist. Resolved, never invented. */
export interface ContractsFixture {
    /** The 'Standard' contract type — carries the 5% default escalation ceiling. */
    StandardTypeID: string;
    CompanyID: string;
    OrganizationID: string;
    /** At least two, so a term can carry more than one kind of coverage. */
    ProductIDs: string[];
    SubscriptionTypeID: string;
    User: UserInfo;
}

let cached: ContractsFixture | null = null;

/** The bundle's fixture. Throws rather than returning a half-built one. */
export function Fx(): ContractsFixture {
    if (!cached) {
        throw new Error('ContractsFixture not created — the bundle lifecycle Setup did not run.');
    }
    return cached;
}

const provider = (ctx: IntegrationCheckContext) =>
    ctx.Provider as unknown as IMetadataProvider & {
        BeginTransaction(): Promise<void>;
        RollbackTransaction(): Promise<void>;
        ExecuteSQL(query: string): Promise<unknown>;
    };

/**
 * A query on the SAME connection the check's transaction is open on — so it sees the check's own
 * uncommitted writes, which is precisely what a bypass proof needs.
 */
export async function TxQuery<T = Record<string, unknown>>(
    ctx: IntegrationCheckContext,
    query: string,
): Promise<T[]> {
    const rows = await provider(ctx).ExecuteSQL(query);
    return (Array.isArray(rows) ? rows : []) as T[];
}

/** Single-row form. Throws when the query returns nothing, rather than handing back undefined. */
export async function TxOne<T = Record<string, unknown>>(
    ctx: IntegrationCheckContext,
    query: string,
): Promise<T> {
    const rows = await TxQuery<T>(ctx, query);
    if (rows.length === 0) throw new Error(`Expected one row, got none:\n${query}`);
    return rows[0];
}

/** COUNT(*) as a number — the shape most bypass proofs actually want. */
export async function TxCount(ctx: IntegrationCheckContext, table: string, where: string): Promise<number> {
    const row = await TxOne<{ N: number }>(ctx, `SELECT COUNT(*) AS N FROM ${CONTRACTS_SCHEMA}.${table} WHERE ${where}`);
    return Number(row.N);
}

/** UUID comparison. Casing varies by read path, so never `===`. */
export function SameID(a: string | null | undefined, b: string | null | undefined): boolean {
    if (!a || !b) return false;
    return a.toLowerCase() === b.toLowerCase();
}

/**
 * Run `body` inside a transaction that ALWAYS rolls back — the isolation primitive every mutating
 * check is written against.
 *
 * A check that fails still rolls back (the rollback is in `finally`), so one failure never poisons
 * the checks after it. The body's own error propagates so the driver reports the real failure and
 * not a teardown artifact.
 */
export async function InRolledBackTransaction(
    ctx: IntegrationCheckContext,
    body: () => Promise<void>,
): Promise<void> {
    const p = provider(ctx);
    await p.BeginTransaction();
    try {
        await body();
    } finally {
        try {
            await p.RollbackTransaction();
        } catch (e) {
            // "Transaction has been aborted" means SQL Server already rolled it back — a
            // severity-16 error inside a trigger dooms the whole transaction, savepoints included,
            // so by the time we ask there is nothing left to roll back. Isolation still held. What
            // does NOT hold is the provider's depth counter: RollbackTransaction throws before
            // clearing it, so the next check's BeginTransaction would nest a savepoint onto a dead
            // transaction and cascade failures through the rest of the bundle. Reset it.
            const aborted = /transaction has been aborted|no active transaction/i.test(String((e as Error).message));
            if (!aborted) throw e;
            resetTransactionState(p);
        }
    }
}

/**
 * Clear the provider's transaction bookkeeping after SQL Server killed the transaction underneath
 * it. Reaching into private state is not something to do lightly — it is here because the provider
 * exposes no recovery path for a server-side abort, and the alternative is one doomed transaction
 * poisoning every check after it.
 */
function resetTransactionState(p: unknown): void {
    const internals = p as { _transaction?: unknown; _transactionDepth?: number; _savepointStack?: unknown[] };
    internals._transaction = null;
    internals._transactionDepth = 0;
    internals._savepointStack = [];
}

/**
 * Resolve the reference rows the bundles need.
 *
 * READ-ONLY BY DESIGN. Every row here belongs to something else — a company, an organization, the
 * orders catalog — and a test suite that invents them is a test suite that leaves them behind. If
 * the demo data is not seeded, this fails with the command to seed it rather than papering over it
 * with rows of its own.
 */
export async function CreateContractsFixture(ctx: IntegrationCheckContext): Promise<ContractsFixture> {
    const user = ctx.User;
    Assert(!!user, 'integration context has no User');

    const rv = new RunView();
    const [types, companies, orgs, products, subTypes] = await rv.RunViews(
        [
            { EntityName: E_TYPE, Fields: ['ID', 'Code'], ResultType: 'simple' },
            { EntityName: 'MJ: Companies', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Common: Organizations', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Products', Fields: ['ID'], MaxRows: 2, ResultType: 'simple' },
            { EntityName: 'MJ_BizApps_Orders: Subscription Types', Fields: ['ID'], MaxRows: 1, ResultType: 'simple' },
        ],
        user,
    );

    const standardTypeID = (types?.Results as { ID: string; Code: string }[] | undefined)?.find((t) => t.Code === 'Standard')?.ID;
    const companyID = (companies?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const organizationID = (orgs?.Results as { ID: string }[] | undefined)?.[0]?.ID;
    const productIDs = ((products?.Results as { ID: string }[] | undefined) ?? []).map((p) => p.ID);
    const subscriptionTypeID = (subTypes?.Results as { ID: string }[] | undefined)?.[0]?.ID;

    Assert(
        !!standardTypeID && !!companyID && !!organizationID && productIDs.length >= 2 && !!subscriptionTypeID,
        `fixture rows missing — standardType=${!!standardTypeID} company=${!!companyID} org=${!!organizationID} ` +
            `products=${productIDs.length} subscriptionType=${!!subscriptionTypeID}. ` +
            'Seed the demo data first: demo/seed-demo-contract.sql',
    );

    cached = {
        StandardTypeID: standardTypeID!,
        CompanyID: companyID!,
        OrganizationID: organizationID!,
        ProductIDs: productIDs,
        SubscriptionTypeID: subscriptionTypeID!,
        User: user,
    };
    return cached;
}

/**
 * Nothing to tear down — the fixture is READ, and every mutating check rolls back.
 *
 * Kept as an explicit no-op rather than omitted, so the lifecycle reads symmetrically and nobody
 * later assumes teardown was forgotten and adds a sweep that deletes somebody's demo data.
 */
export async function TeardownContractsFixture(_ctx: IntegrationCheckContext): Promise<void> {
    cached = null;
}

/** The metadata handle every check uses to build entities. */
export function Md(): Metadata {
    return new Metadata();
}
