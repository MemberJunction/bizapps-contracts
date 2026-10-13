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
import { type BaseEntity, LogError, LogStatus, type UserInfo } from '@memberjunction/core';
import type { mjBizAppsOrdersSubscriptionEntity } from '@mj-biz-apps/orders-entities';

export const E_CONTRACT_ORDER = 'MJ_BizApps_Contracts: Contract Orders';
export const E_ORDER_LINE = 'MJ_BizApps_Orders: Order Lines';
export const E_SUBSCRIPTION = 'MJ_BizApps_Orders: Subscriptions';

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
export type RenewalTermsProvider = Pick<BaseEntity['RunViewProviderToUse'], 'RunView'>;

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

    const lineIDs = await ids(provider, E_ORDER_LINE, `OrderHeaderID IN (${quoted(orderIDs)})`, 'ID', user);
    if (lineIDs.length === 0) return outcome;

    const subs = await provider.RunView<mjBizAppsOrdersSubscriptionEntity>(
        { EntityName: E_SUBSCRIPTION, ExtraFilter: `OrderLineID IN (${quoted(lineIDs)})`, ResultType: 'entity_object' },
        user,
    );
    if (!subs.Success) {
        throw new Error(`Could not load the subscriptions governed by contract ${label(terms)}: ${subs.ErrorMessage}`);
    }

    for (const sub of subs.Results) {
        const increase = terms.AnnualIncreasePercent;
        if (increase != null && increase > SUBSCRIPTION_MAX_INCREASE_PERCENT) {
            outcome.Failed.push({
                SubscriptionNumber: sub.SubscriptionNumber,
                Message:
                    `Contract ${label(terms)} states an annual increase of ${increase}%, above the ` +
                    `${SUBSCRIPTION_MAX_INCREASE_PERCENT}% a subscription accepts. The increase was not copied.`,
            });
        } else if (increase != null && Number(sub.RenewalIncreasePercent) !== Number(increase)) {
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

async function ids(
    provider: RenewalTermsProvider,
    entityName: string,
    filter: string,
    field: string,
    user: UserInfo | undefined,
): Promise<string[]> {
    const result = await provider.RunView<Record<string, string>>(
        { EntityName: entityName, ExtraFilter: filter, Fields: [field], ResultType: 'simple' },
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
