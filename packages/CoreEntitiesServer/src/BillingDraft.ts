/**
 * @fileoverview What a billing run decides to bill — and the seam where orders prices it.
 *
 * THE RULE THIS FILE EXISTS TO ENFORCE: **contracts decides WHAT to bill and never WHAT IT COSTS.**
 *
 * Every number on a bill comes back from orders. A `BillingDraft` therefore carries products,
 * quantities and periods — the agreement's answer to "what is owed for this window" — and carries
 * NO prices except the ones the CONTRACT itself negotiated, which are facts about the agreement
 * rather than calculations. If a change to this file starts doing arithmetic, it is in the wrong
 * file: a second implementation of pricing next to the engine is the thing that eventually
 * disagrees with it, and the disagreement surfaces as an invoice for the wrong amount that nothing
 * downstream can catch.
 *
 * ── THE ORDERS SEAM, AND WHY IT IS A SEAM ───────────────────────────────────────────────────────
 *
 * Two calls are genuinely blocked (plan C0): pricing the draft through `Orders.PreviewOrder`, and
 * materialising it through `Orders.CreateOrderInState`. Both need seams that do not exist in orders
 * yet — without `Subscription.BillingMode` orders double-bills the same subscription, and without
 * the resolver slot it prices at catalog instead of at the contracted price.
 *
 * They are expressed as an INTERFACE with an explicit unavailable default rather than as a `TODO`
 * for two reasons. First, everything ELSE in the engine — the claim, the assembly, the failure
 * semantics, the scheduled driver — is buildable and testable today, and a `TODO` in the middle
 * would make the whole operation untestable. Second, when the seams land, the change is one
 * registration rather than a rewrite: the shape orders must satisfy is already written down here.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import type { UserInfo } from '@memberjunction/core';

/** Why a line appears on a bill. Carried through so a person can be told what they are paying for. */
export type BillingReason =
    | 'subscription-period'
    | 'one-time-window-opened'
    | 'milestone-reached'
    | 'usage-metered'
    | 'minimum-shortfall';

/** One thing to bill. Quantities and periods; no prices except what the contract negotiated. */
export interface BillingDraftLine {
    ContractLineID: string | null;
    ProductID: string;
    Quantity: number;
    /**
     * The price the CONTRACT states, when it states one. Not a calculation — a term of the
     * agreement. Null means "resolve it at the catalog price", which is orders' job.
     */
    ContractedUnitPrice: number | null;
    /** As negotiated, a fraction. Contract discounts OVERRIDE order-level discounting, never stack. */
    DiscountPct: number | null;
    ServicePeriodStart: string | null;
    ServicePeriodEnd: string | null;
    Reason: BillingReason;
    Description: string;
}

/** The whole bill, as the agreement sees it. */
export interface BillingDraft {
    ContractID: string;
    ContractTermID: string;
    ContractBillingEventID: string;
    CompanyID: string;
    CustomerOrganizationID: string | null;
    CustomerPersonID: string | null;
    CurrencyID: string | null;
    PaymentTermsTypeID: string | null;
    /** The window being billed — what the customer is paying FOR. */
    PeriodStart: string;
    PeriodEnd: string;
    /** The as-of date every price resolves from (master plan §12). */
    PricedAt: string | null;
    Lines: BillingDraftLine[];
}

export interface PreviewResult {
    Success: boolean;
    /** What orders says the bill comes to. Contracts never computes this. */
    Total?: number;
    Message?: string;
}

export interface MaterializeResult {
    Success: boolean;
    OrderID?: string;
    Total?: number;
    Message?: string;
}

/**
 * What orders must provide for a contract to produce a bill.
 *
 * Deliberately narrow: two calls, both taking a draft, both returning a result rather than throwing.
 * Anything wider would invite the engine to reach into orders for a number it should have been given.
 */
export interface OrdersBillingBridge {
    /** Price the draft without writing anything. */
    PreviewOrder(draft: BillingDraft, user: UserInfo): Promise<PreviewResult>;
    /** Materialise ONE consolidated order for the whole draft. */
    CreateOrderInState(draft: BillingDraft, user: UserInfo): Promise<MaterializeResult>;
}

/** The exact reason, in one place, so both calls and every test say the same thing. */
const BLOCKED_MESSAGE =
    'Orders cannot price or materialise a contract bill yet: the C0 seams are missing. Without ' +
    'Subscription.BillingMode orders would double-bill a subscription that contracts is also ' +
    'billing, and without the contracted-price resolver slot it would price at catalog instead of ' +
    'at the price the agreement states. Both are open with Amith (plan C0, question D-2).';

/**
 * The default bridge: honest about being unavailable.
 *
 * It REFUSES rather than returning a zero or a guess. A bridge that quietly returned no lines would
 * produce an empty bill and a Generated event, which is worse than a Failed one — the customer is
 * under-billed and the event says everything worked.
 */
export class UnavailableOrdersBridge implements OrdersBillingBridge {
    public async PreviewOrder(): Promise<PreviewResult> {
        return { Success: false, Message: BLOCKED_MESSAGE };
    }

    public async CreateOrderInState(): Promise<MaterializeResult> {
        return { Success: false, Message: BLOCKED_MESSAGE };
    }
}

let bridge: OrdersBillingBridge = new UnavailableOrdersBridge();

/**
 * Install the bridge orders provides.
 *
 * An EXTENSION POINT, not a test hook: when the C0 seams land, orders (or the app bootstrap that
 * wires the two together) registers its implementation here and the engine needs no change. That it
 * also lets a test drive the full state machine today is a consequence of the design, not its
 * purpose — and it is what makes the failure semantics provable before the real seams exist.
 */
export function RegisterOrdersBillingBridge(implementation: OrdersBillingBridge): void {
    bridge = implementation;
}

/** The bridge currently in force. */
export function GetOrdersBillingBridge(): OrdersBillingBridge {
    return bridge;
}

/** Restore the unavailable default. */
export function ResetOrdersBillingBridge(): void {
    bridge = new UnavailableOrdersBridge();
}

export const ORDERS_BRIDGE_UNAVAILABLE_MESSAGE = BLOCKED_MESSAGE;
