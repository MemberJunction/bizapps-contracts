/**
 * @fileoverview Copy a contract's renewal terms to the Orders subscriptions it governs (issue #77).
 *
 * Orders reprices a renewal from two fields on the subscription: `RenewalIncreasePercent` and
 * `CarryDiscountOnRenewal`. The negotiated values live on the contract, and Orders cannot read this
 * app (foreign keys point up the install order), so this app writes them across.
 *
 * WHICH SUBSCRIPTIONS. Contract -> `ContractOrder` -> order lines -> the subscriptions those lines
 * created (`Subscription.OrderLineID`). Derived on every call rather than stored, so a subscription
 * Orders creates after the link is found the next time the terms are copied. A renewal reuses its
 * subscription, so it stays covered without a new link.
 *
 * WHAT IS WRITTEN.
 *   · `AnnualIncreasePercent` overwrites the subscription's increase only when the contract states
 *     one. A blank contract leaves the subscription alone, so a value set by hand on a subscription
 *     whose contract is silent survives.
 *   · `CarryDiscountOnRenewal` is a bit with no blank state, so the contract's value always wins on
 *     a linked subscription. The paper is the source of the concession.
 *
 * Each subscription is saved through its own entity, so Orders' rules run. A refusal is reported per
 * subscription and does not stop the others: one bad row should not leave the rest unpriced.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */
import { BaseEntity, LogError, LogStatus, type RunViewParams, type RunViewResult, type UserInfo } from '@memberjunction/core';
import { MJGlobal } from '@memberjunction/global';
import { mjBizAppsOrdersOrderLineEntity, mjBizAppsOrdersSubscriptionEntity } from '@mj-biz-apps/orders-entities';

export const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
export const E_CONTRACT_ORDER = 'MJ_BizApps_Contracts: Contract Orders';

/**
 * The entity name a generated entity class is registered under.
 *
 * Orders' entity names are read from Orders' own classes rather than typed here as strings, so a
 * rename in bizapps-orders surfaces as a failed lookup (and a failed unit test) instead of a view
 * that silently returns nothing. The generated classes register themselves with `@RegisterClass`
 * when `@mj-biz-apps/orders-entities` is imported, which this module does.
 */
export function EntityNameOf(entityClass: abstract new (...args: never[]) => BaseEntity): string {
    const registration = MJGlobal.Instance.ClassFactory.GetAllRegistrations(BaseEntity).find(
        (r) => r.SubClass === entityClass,
    );
    if (!registration?.Key) {
        throw new Error(`${entityClass.name} is not registered as an entity class. Is @mj-biz-apps/orders-entities loaded?`);
    }
    return registration.Key;
}

/** `MJ_BizApps_Orders: Order Lines`, read from Orders' class. */
export function OrderLineEntityName(): string {
    return EntityNameOf(mjBizAppsOrdersOrderLineEntity);
}

/** `MJ_BizApps_Orders: Subscriptions`, read from Orders' class. */
export function SubscriptionEntityName(): string {
    return EntityNameOf(mjBizAppsOrdersSubscriptionEntity);
}

/**
 * The ceiling Orders' `CK_Subscription_RenewalIncreasePercent` enforces. The contract's own column
 * has no ceiling, so a value above it is reported here in words rather than as a constraint name.
 */
export const SUBSCRIPTION_MAX_INCREASE_PERCENT = 100;

/** The terms being copied, read from the contract. */
export interface ContractRenewalTerms {
    ContractID: string;
    ContractNumber: string | null;
    AnnualIncreasePercent: number | null;
    CarryDiscountOnRenewal: boolean;
}

/** What one call did, per subscription. */
export interface RenewalTermsOutcome {
    /** Subscription numbers whose fields changed and saved. */
    Updated: string[];
    /** Subscriptions that already carried the contract's terms. */
    Unchanged: number;
    /** Subscriptions that could not take the terms, with the reason. */
    Failed: Array<{ SubscriptionNumber: string; Message: string }>;
}

/** The slice of an MJ provider this needs, so tests can pass a fake. */
export type RenewalTermsProvider = Pick<BaseEntity['RunViewProviderToUse'], 'RunView'> &
    Partial<Pick<BaseEntity['RunViewProviderToUse'], 'RunViews'>>;

/**
 * Copy `terms` to every subscription created by an order linked to the contract.
 *
 * A failed lookup throws: reading "could not find the subscriptions" as "there are none" would report
 * success for a copy that never happened.
 */
export async function ApplyContractRenewalTerms(
    provider: RenewalTermsProvider,
    terms: ContractRenewalTerms,
    user: UserInfo | undefined,
): Promise<RenewalTermsOutcome> {
    const outcome: RenewalTermsOutcome = { Updated: [], Unchanged: 0, Failed: [] };

    const orderIDs = await ids(provider, E_CONTRACT_ORDER, `ContractID='${terms.ContractID}'`, 'OrderID', user);
    if (orderIDs.length === 0) return outcome;

    const lineIDs = await ids(provider, OrderLineEntityName(), `OrderHeaderID IN (${quoted(orderIDs)})`, 'ID', user);
    if (lineIDs.length === 0) return outcome;

    const subs = await provider.RunView<mjBizAppsOrdersSubscriptionEntity>(
        {
            EntityName: SubscriptionEntityName(),
            ExtraFilter: `OrderLineID IN (${quoted(lineIDs)})`,
            ResultType: 'entity_object',
            IgnoreMaxRows: true,
        },
        user,
    );
    if (!subs.Success) {
        throw new Error(`Could not load the subscriptions governed by contract ${label(terms)}: ${subs.ErrorMessage}`);
    }

    return applyTermsToSubscriptions(terms, subs.Results);
}

/**
 * Apply `terms` to an already-loaded list of governed subscriptions, saving only those that change.
 */
async function applyTermsToSubscriptions(
    terms: ContractRenewalTerms,
    subscriptions: readonly mjBizAppsOrdersSubscriptionEntity[],
): Promise<RenewalTermsOutcome> {
    const outcome: RenewalTermsOutcome = { Updated: [], Unchanged: 0, Failed: [] };

    for (const sub of subscriptions) {
        const increase = terms.AnnualIncreasePercent;
        if (increase != null && increase > SUBSCRIPTION_MAX_INCREASE_PERCENT) {
            outcome.Failed.push({
                SubscriptionNumber: sub.SubscriptionNumber,
                Message:
                    `Contract ${label(terms)} states an annual increase of ${increase}%, above the ` +
                    `${SUBSCRIPTION_MAX_INCREASE_PERCENT}% a subscription accepts. The increase was not copied.`,
            });
        } else if (
            increase != null &&
            // A NULL subscription inherits from product, category and company; 0 is a deliberate
            // no-increase. `Number(null)` is 0, so the null case has to be tested on its own.
            (sub.RenewalIncreasePercent == null || Number(sub.RenewalIncreasePercent) !== Number(increase))
        ) {
            sub.RenewalIncreasePercent = increase;
        }
        if (sub.CarryDiscountOnRenewal !== terms.CarryDiscountOnRenewal) {
            sub.CarryDiscountOnRenewal = terms.CarryDiscountOnRenewal;
        }

        if (!sub.Dirty) {
            if (!outcome.Failed.some((f) => f.SubscriptionNumber === sub.SubscriptionNumber)) outcome.Unchanged++;
            continue;
        }
        if (await sub.Save()) {
            outcome.Updated.push(sub.SubscriptionNumber);
        } else {
            outcome.Failed.push({
                SubscriptionNumber: sub.SubscriptionNumber,
                Message: sub.LatestResult?.CompleteMessage ?? 'the subscription refused the save',
            });
        }
    }
    return outcome;
}

/** What one sweep did across every linked contract. */
export interface RenewalTermsSweepOutcome {
    Contracts: number;
    Updated: number;
    Unchanged: number;
    Failed: Array<{ ContractNumber: string; SubscriptionNumber: string; Message: string }>;
}

/**
 * Re-apply every linked contract's terms (c77.4). Orders creates a subscription when the order is
 * booked, usually after the link was written, so the copy at link time finds nothing and the
 * subscription would otherwise wait for someone to edit the contract. Run daily, ahead of the renewal
 * pass. Safe to repeat: a subscription already carrying the terms is not saved.
 *
 * Uses batched reads across all linked contracts (Contract Orders -> batched `[Contracts, Order Lines]`
 * via `RunViews` -> Subscriptions) instead of a per-contract `3*N` `RunView` waterfall.
 *
 * One lookup failure stops the sweep rather than skipping it, for the same reason a single copy
 * throws: a quiet skip would read as "nothing to do".
 */
export async function SweepContractRenewalTerms(
    provider: RenewalTermsProvider,
    user: UserInfo | undefined,
): Promise<RenewalTermsSweepOutcome> {
    const sweep: RenewalTermsSweepOutcome = { Contracts: 0, Updated: 0, Unchanged: 0, Failed: [] };

    const linksResult = await provider.RunView<{ ContractID: string; OrderID: string }>(
        {
            EntityName: E_CONTRACT_ORDER,
            Fields: ['ContractID', 'OrderID'],
            ResultType: 'simple',
            IgnoreMaxRows: true,
        },
        user,
    );
    if (!linksResult.Success) {
        throw new Error(`Could not read ${E_CONTRACT_ORDER} (): ${linksResult.ErrorMessage}`);
    }
    if (linksResult.Results.length === 0) return sweep;

    const orderIDsByContract = new Map<string, Set<string>>();
    const allContractIDs = new Set<string>();
    const allOrderIDs = new Set<string>();
    for (const link of linksResult.Results) {
        const contractID = String(link.ContractID);
        const orderID = String(link.OrderID);
        allContractIDs.add(contractID);
        allOrderIDs.add(orderID);
        let orderSet = orderIDsByContract.get(contractID.toLowerCase());
        if (!orderSet) {
            orderSet = new Set<string>();
            orderIDsByContract.set(contractID.toLowerCase(), orderSet);
        }
        orderSet.add(orderID.toLowerCase());
    }

    const contractParams: RunViewParams = {
        EntityName: E_CONTRACT,
        ExtraFilter: `ID IN (${quoted([...allContractIDs])})`,
        Fields: ['ID', 'ContractNumber', 'AnnualIncreasePercent', 'CarryDiscountOnRenewal'],
        ResultType: 'simple',
        IgnoreMaxRows: true,
    };
    const lineParams: RunViewParams = {
        EntityName: OrderLineEntityName(),
        ExtraFilter: `OrderHeaderID IN (${quoted([...allOrderIDs])})`,
        Fields: ['ID', 'OrderHeaderID'],
        ResultType: 'simple',
        IgnoreMaxRows: true,
    };

    const [contractsRes, linesRes] = await runViewBatch(provider, [contractParams, lineParams], user);
    if (!contractsRes?.Success) {
        throw new Error(`Could not read the linked contracts: ${contractsRes?.ErrorMessage ?? 'unknown error'}`);
    }
    if (!linesRes?.Success) {
        throw new Error(`Could not read ${OrderLineEntityName()}: ${linesRes?.ErrorMessage ?? 'unknown error'}`);
    }

    const contractRows = contractsRes.Results as Array<{
        ID: string;
        ContractNumber: string | null;
        AnnualIncreasePercent: number | null;
        CarryDiscountOnRenewal: boolean;
    }>;
    const lineRows = linesRes.Results as Array<{ ID: string; OrderHeaderID: string }>;

    const lineIDsByOrder = new Map<string, Set<string>>();
    const allLineIDs = new Set<string>();
    for (const line of lineRows) {
        const lineID = String(line.ID);
        const orderID = String(line.OrderHeaderID).toLowerCase();
        allLineIDs.add(lineID);
        let lineSet = lineIDsByOrder.get(orderID);
        if (!lineSet) {
            lineSet = new Set<string>();
            lineIDsByOrder.set(orderID, lineSet);
        }
        lineSet.add(lineID.toLowerCase());
    }

    const subsByLine = new Map<string, mjBizAppsOrdersSubscriptionEntity[]>();
    if (allLineIDs.size > 0) {
        const subsRes = await provider.RunView<mjBizAppsOrdersSubscriptionEntity>(
            {
                EntityName: SubscriptionEntityName(),
                ExtraFilter: `OrderLineID IN (${quoted([...allLineIDs])})`,
                ResultType: 'entity_object',
                IgnoreMaxRows: true,
            },
            user,
        );
        if (!subsRes.Success) {
            throw new Error(`Could not load the subscriptions governed by linked contracts: ${subsRes.ErrorMessage}`);
        }
        for (const sub of subsRes.Results) {
            const lineKey = String(sub.OrderLineID).toLowerCase();
            let bucket = subsByLine.get(lineKey);
            if (!bucket) {
                bucket = [];
                subsByLine.set(lineKey, bucket);
            }
            bucket.push(sub);
        }
    }

    for (const row of contractRows) {
        const terms: ContractRenewalTerms = {
            ContractID: row.ID,
            ContractNumber: row.ContractNumber,
            AnnualIncreasePercent: row.AnnualIncreasePercent == null ? null : Number(row.AnnualIncreasePercent),
            CarryDiscountOnRenewal: !!row.CarryDiscountOnRenewal,
        };
        const governedOrders = orderIDsByContract.get(row.ID.toLowerCase());
        const governedSubs: mjBizAppsOrdersSubscriptionEntity[] = [];
        if (governedOrders) {
            for (const orderKey of governedOrders) {
                const orderLines = lineIDsByOrder.get(orderKey);
                if (!orderLines) continue;
                for (const lineKey of orderLines) {
                    const lineSubs = subsByLine.get(lineKey);
                    if (lineSubs) governedSubs.push(...lineSubs);
                }
            }
        }
        const outcome = await applyTermsToSubscriptions(terms, governedSubs);
        sweep.Contracts++;
        sweep.Updated += outcome.Updated.length;
        sweep.Unchanged += outcome.Unchanged;
        for (const f of outcome.Failed) sweep.Failed.push({ ContractNumber: label(terms), ...f });
    }
    return sweep;
}

async function runViewBatch(
    provider: RenewalTermsProvider,
    params: RunViewParams[],
    user: UserInfo | undefined,
): Promise<RunViewResult[]> {
    if (typeof provider.RunViews === 'function') {
        return provider.RunViews(params, user);
    }
    return Promise.all(params.map((p) => provider.RunView(p, user)));
}

/** One sentence for a log line or a caller's message. */
export function DescribeRenewalTermsOutcome(terms: ContractRenewalTerms, outcome: RenewalTermsOutcome): string {
    const parts = [`Contract ${label(terms)}: ${outcome.Updated.length} subscription(s) updated, ${outcome.Unchanged} already current`];
    for (const f of outcome.Failed) parts.push(`${f.SubscriptionNumber} not updated: ${f.Message}`);
    return parts.join('; ');
}

/**
 * Log what a copy did. A refused subscription is an error in the log rather than a refused save: the
 * contract or link is still right, and the subscription's own rules decided against the value.
 */
export function ReportRenewalTermsOutcome(terms: ContractRenewalTerms, outcome: RenewalTermsOutcome): void {
    const message = DescribeRenewalTermsOutcome(terms, outcome);
    if (outcome.Failed.length > 0) LogError(message);
    else if (outcome.Updated.length > 0) LogStatus(message);
}

/**
 * Every row, past the entity's `UserViewMaxRows`. Without `IgnoreMaxRows` the provider adds a `TOP`
 * from that setting (1000 for Contract Orders), and the sweep would stop there without a warning.
 */
async function ids(
    provider: RenewalTermsProvider,
    entityName: string,
    filter: string,
    field: string,
    user: UserInfo | undefined,
): Promise<string[]> {
    const result = await provider.RunView<Record<string, string>>(
        { EntityName: entityName, ExtraFilter: filter || undefined, Fields: [field], ResultType: 'simple', IgnoreMaxRows: true },
        user,
    );
    if (!result.Success) {
        throw new Error(`Could not read ${entityName} (${filter}): ${result.ErrorMessage}`);
    }
    return result.Results.map((r) => String(r[field]));
}

/** IDs come from the database, never from a caller, so quoting is all the interpolation needs. */
function quoted(values: readonly string[]): string {
    return values.map((v) => `'${v}'`).join(',');
}

function label(terms: ContractRenewalTerms): string {
    return terms.ContractNumber ?? terms.ContractID;
}
