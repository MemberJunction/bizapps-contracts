/**
 * contracts-renewal-terms — a contract's renewal terms reach the Orders subscriptions it governs
 * (issue #77).
 *
 * Contract -> ContractOrder -> order lines -> subscriptions. Each check rolls its transaction back.
 *
 * The checks need an Orders install and one subscription that an order line created; this repo's
 * fixture does not build orders (that is Orders' own world). When either is missing every check
 * SKIPS with the reason, rather than passing over nothing.
 */
import { randomUUID } from 'node:crypto';
import {
    Assert,
    AssertEqual,
    IntegrationCheckRegistry,
    type IntegrationCheckContext,
    type NamedCheck,
    SkipCheck,
} from '@memberjunction/testing-integration/registry';
import type { DatabaseProviderBase, RunView } from '@memberjunction/core';
import {
    type ContractEntityServer,
    type ContractOrderEntityServer,
    E_CONTRACT_ORDER,
    OrderLineEntityName,
    SubscriptionEntityName,
    SweepContractRenewalTerms,
} from '@mj-biz-apps/contracts-core-entities-server';
import type { mjBizAppsOrdersSubscriptionEntity } from '@mj-biz-apps/orders-entities';
import {
    CONTRACTS_SCHEMA,
    DestroyFixture,
    FindRows,
    InRolledBackTransaction,
    NewContract,
    ProviderOf,
    RequireSave,
    ResolveContractsFixture,
    View,
    type ContractsFixture,
} from '../fixture.js';

type Ctx = IntegrationCheckContext;

/** A subscription some order line created, and that line's order. */
interface GovernedSubscription {
    SubscriptionID: string;
    OrderID: string;
    RenewalIncreasePercent: number | null;
    CarryDiscountOnRenewal: boolean;
}

/** Skip (with the reason) unless Orders is installed and has a subscription created by an order line. */
async function requireGovernedSubscription(ctx: Ctx): Promise<GovernedSubscription> {
    const entities = ProviderOf(ctx).Entities;
    for (const name of [OrderLineEntityName(), SubscriptionEntityName(), E_CONTRACT_ORDER]) {
        if (!entities.some((e) => e.Name === name)) {
            SkipCheck(`'${name}' is not in this database's metadata: bizapps-orders (5.28 or later) is not installed.`);
        }
    }
    const subs = await FindRows<{ ID: string; OrderLineID: string; RenewalIncreasePercent: number | null; CarryDiscountOnRenewal: boolean }>(
        ctx,
        SubscriptionEntityName(),
        'OrderLineID IS NOT NULL AND ProviderSubscriptionID IS NULL',
        ['ID', 'OrderLineID', 'RenewalIncreasePercent', 'CarryDiscountOnRenewal'],
        'ID',
    );
    for (const sub of subs) {
        const lines = await FindRows<{ OrderHeaderID: string }>(ctx, OrderLineEntityName(), `ID = '${sub.OrderLineID}'`, ['OrderHeaderID']);
        const orderID = lines[0]?.OrderHeaderID;
        if (orderID) {
            return {
                SubscriptionID: sub.ID,
                OrderID: orderID,
                RenewalIncreasePercent: sub.RenewalIncreasePercent == null ? null : Number(sub.RenewalIncreasePercent),
                CarryDiscountOnRenewal: !!sub.CarryDiscountOnRenewal,
            };
        }
    }
    return SkipCheck(
        'No Orders subscription created by an order line exists in this database. Seed Orders first ' +
            "(bizapps-orders' catalog-world integration bundle creates them).",
    );
}

async function reloadSubscription(ctx: Ctx, id: string): Promise<mjBizAppsOrdersSubscriptionEntity> {
    const sub = await ProviderOf(ctx).GetEntityObject<mjBizAppsOrdersSubscriptionEntity>(SubscriptionEntityName(), ctx.User);
    Assert(await sub.Load(id), `subscription ${id} could not be re-read`);
    return sub;
}

/** A saved contract with the given terms; the increase is distinct from the subscription's current one. */
async function contractWithTerms(
    ctx: Ctx,
    f: ContractsFixture,
    increase: number,
    carry: boolean,
): Promise<ContractEntityServer> {
    const contract = (await NewContract(ctx, f, (c) => {
        c.Notes = `IT-RT-${randomUUID()}`;
        c.AnnualIncreasePercent = increase;
        c.CarryDiscountOnRenewal = carry;
    })) as ContractEntityServer;
    await RequireSave(contract, 'contract with renewal terms');
    return contract;
}

async function link(ctx: Ctx, contractID: string, orderID: string): Promise<ContractOrderEntityServer> {
    const row = await ProviderOf(ctx).GetEntityObject<ContractOrderEntityServer>(E_CONTRACT_ORDER, ctx.User);
    row.NewRecord();
    row.ContractID = contractID;
    row.OrderID = orderID;
    await RequireSave(row, 'contract-order link');
    return row;
}

/** An increase guaranteed to differ from what the subscription holds now, so a copy is observable. */
function freshIncrease(current: number | null): number {
    return current === 7.25 ? 6.5 : 7.25;
}

export const RenewalTermsChecks: NamedCheck[] = [
    {
        Id: 'contracts-renewal-terms.RT1',
        Name: "RT1 — linking an order copies the contract's increase and carry-discount flag to its subscriptions",
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const sub = await requireGovernedSubscription(ctx);
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const increase = freshIncrease(sub.RenewalIncreasePercent);
                const carry = !sub.CarryDiscountOnRenewal;
                const contract = await contractWithTerms(ctx, f, increase, carry);
                const row = await link(ctx, contract.ID, sub.OrderID);

                AssertEqual(row.LastRenewalTermsOutcome?.Failed.length ?? -1, 0, 'RT1 the copy reported a refused subscription');
                const after = await reloadSubscription(ctx, sub.SubscriptionID);
                AssertEqual(Number(after.RenewalIncreasePercent), increase, 'RT1 RenewalIncreasePercent was not copied');
                AssertEqual(after.CarryDiscountOnRenewal, carry, 'RT1 CarryDiscountOnRenewal was not copied');
            });
        },
    },
    {
        Id: 'contracts-renewal-terms.RT2',
        Name: "RT2 — editing a linked contract's terms copies the new values",
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const sub = await requireGovernedSubscription(ctx);
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await contractWithTerms(ctx, f, freshIncrease(sub.RenewalIncreasePercent), false);
                await link(ctx, contract.ID, sub.OrderID);

                contract.AnnualIncreasePercent = 3.5;
                contract.CarryDiscountOnRenewal = true;
                await RequireSave(contract, 'RT2 contract edit');
                AssertEqual(contract.LastRenewalTermsOutcome?.Failed.length ?? -1, 0, 'RT2 the copy reported a refused subscription');

                const after = await reloadSubscription(ctx, sub.SubscriptionID);
                AssertEqual(Number(after.RenewalIncreasePercent), 3.5, 'RT2 the edited increase was not copied');
                AssertEqual(after.CarryDiscountOnRenewal, true, 'RT2 the edited flag was not copied');
            });
        },
    },
    {
        Id: 'contracts-renewal-terms.RT3',
        Name: 'RT3 — the sweep reaches a subscription the link-time copy did not',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const sub = await requireGovernedSubscription(ctx);
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const increase = freshIncrease(sub.RenewalIncreasePercent);
                const contract = await contractWithTerms(ctx, f, increase, !sub.CarryDiscountOnRenewal);
                // Written past the entity on purpose: this is the state a subscription Orders creates
                // AFTER the link is in, which the link-time copy never saw.
                await (ctx.Provider as unknown as DatabaseProviderBase).ExecuteSQL(
                    `INSERT INTO ${CONTRACTS_SCHEMA}.ContractOrder (ContractID, OrderID) VALUES ('${contract.ID}', '${sub.OrderID}');`,
                    undefined,
                    { isMutation: true, description: 'RT3 link without the copy' },
                    ctx.User,
                );
                const before = await reloadSubscription(ctx, sub.SubscriptionID);
                Assert(Number(before.RenewalIncreasePercent) !== increase, 'RT3 precondition: the subscription already had the terms');

                const sweep = await SweepContractRenewalTerms(View(ctx) as RunView, ctx.User);
                Assert(sweep.Updated >= 1, `RT3 the sweep updated nothing: ${JSON.stringify(sweep)}`);
                const after = await reloadSubscription(ctx, sub.SubscriptionID);
                AssertEqual(Number(after.RenewalIncreasePercent), increase, 'RT3 the sweep did not copy the increase');
                AssertEqual(after.CarryDiscountOnRenewal, !sub.CarryDiscountOnRenewal, 'RT3 the sweep did not copy the flag');
            });
        },
    },
    {
        Id: 'contracts-renewal-terms.RT4',
        Name: 'RT4 — a contract with a linked order cannot be deleted until the link is removed',
        RequiresMutation: true,
        Fn: async (ctx: Ctx) => {
            const sub = await requireGovernedSubscription(ctx);
            const f = await ResolveContractsFixture(ctx);
            await InRolledBackTransaction(ctx, async () => {
                const contract = await contractWithTerms(ctx, f, freshIncrease(sub.RenewalIncreasePercent), false);
                await link(ctx, contract.ID, sub.OrderID);
                const deleted = await contract.Delete();
                Assert(!deleted, 'RT4 a contract with a linked order was deleted');
                const message = contract.LatestResult?.CompleteMessage ?? contract.LatestResult?.Message ?? '';
                Assert(/governs 1 order/i.test(message), `RT4 the refusal did not name the linked order: ${message}`);
            });
        },
    },
];

for (const check of RenewalTermsChecks) {
    IntegrationCheckRegistry.Instance.Register(check);
}

IntegrationCheckRegistry.Instance.RegisterLifecycle('contracts-renewal-terms', {
    Setup: async () => {
        // Each check resolves its own preconditions so a missing Orders install SKIPS rather than
        // failing setup.
    },
    Teardown: async (ctx) => {
        await DestroyFixture(ctx);
    },
});
