/**
 * @fileoverview `Contracts.GenerateBillingEvent` — the thing this app exists to do.
 *
 * The master plan defines contracts as "the agreement envelope … and the thing that decides when a
 * bill is produced and what goes on it". Until now the envelope was built and NOTHING produced a
 * bill: the app recorded agreements and had never emitted a single order.
 *
 * ── THE CLAIM, WHICH IS THE PART THAT MUST NOT BE WRONG ─────────────────────────────────────────
 *
 * Two overlapping runs must not bill the same row twice. `CK_ContractBillingEvent_GeneratedHasOrder`
 * is a good invariant — a Generated event must name its order, so a re-run over a Generated row
 * cannot bill again — but it does NOT stop two runs both selecting the same `Scheduled` row and
 * both proceeding. Duplicate billing is the kind of defect a customer discovers before we do.
 *
 * So the event is CLAIMED before any work happens, with a conditional self-assignment:
 *
 *     UPDATE ContractBillingEvent SET Status = Status WHERE ID = @id AND Status = 'Scheduled'
 *
 * Inside the operation's transaction that takes an exclusive lock on the row while changing nothing.
 * A second run's identical statement BLOCKS on that lock; when the first commits, the second
 * re-evaluates its `WHERE` against the now-`Generated` row, matches nothing, and returns
 * "already claimed". `@@ROWCOUNT` is the whole test, and it is decided by the database rather than
 * by anything this process believes.
 *
 * Self-assignment rather than a no-op write to `Notes` because it clobbers nothing a person wrote.
 * A dedicated `Generating` status would be MORE OBSERVABLE — a run that dies mid-flight would leave
 * a visibly stuck row instead of one that silently reverts to Scheduled — and is the better design
 * once there is a migration to spend on it; this is deferred deliberately, not overlooked.
 *
 * ── ALL-OR-NONE ─────────────────────────────────────────────────────────────────────────────────
 *
 * One transaction covers the claim, the draft, the order and the stamping. A failure marks the event
 * `Failed` WITH A REASON in a separate transaction — deliberately outside the rolled-back one, or
 * the record of the failure would roll back with the failure itself and the row would look like it
 * had never been tried.
 *
 * ── WHAT IT DECIDES, AND WHAT IT REFUSES TO DECIDE ──────────────────────────────────────────────
 *
 * It decides WHAT to bill. Every number comes back from orders through the bridge in
 * `BillingDraft.ts`. There is no arithmetic in this file except counting the quantity the contract
 * already states, and the shortfall on a commitment — which is a subtraction between two figures the
 * agreement itself records, not a price.
 *
 * @module @mj-biz-apps/contracts-core-entities-server
 */

import {
    BaseRemotableOperation,
    type DatabaseProviderBase,
    type IMetadataProvider,
    type IRunViewProvider,
    Metadata,
    RunView,
    type UserInfo,
} from '@memberjunction/core';
import { RegisterClass } from '@memberjunction/global';
import type {
    mjBizAppsContractsContractBillingEventEntity,
    mjBizAppsContractsContractEventEntity,
} from '@mj-biz-apps/contracts-entities';
import { ContractEntityServer } from './ContractEntityServer.js';
import type { ContractTermEntityServer } from './ContractTermEntityServer.js';
import {
    GetOrdersBillingBridge,
    type BillingDraft,
    type BillingDraftLine,
} from './BillingDraft.js';

const E_CONTRACT = 'MJ_BizApps_Contracts: Contracts';
const E_TERM = 'MJ_BizApps_Contracts: Contract Terms';
const E_BILLING_EVENT = 'MJ_BizApps_Contracts: Contract Billing Events';
const E_LOG = 'MJ_BizApps_Contracts: Contract Events';
const SCHEMA = '__mj_BizAppsContracts';

export interface GenerateBillingEventInput {
    ContractBillingEventID: string;
    /** Assemble and price the draft, write nothing. What a person approves before it bills. */
    PreviewOnly?: boolean;
}

export interface GenerateBillingEventOutput {
    Success: boolean;
    Message?: string;
    ContractBillingEventID?: string;
    /** Set when the event was billed. */
    OrderID?: string;
    /** What orders said it comes to. Never computed here. */
    ComputedAmount?: number;
    /** What the run decided to bill, so a preview can show it and a failure can explain it. */
    Draft?: BillingDraft;
    /** True when another run already had this event — not an error, and not a second bill. */
    AlreadyClaimed?: boolean;
}

/** Months per cadence. `Milestone` and `Custom` have no period — a human places those. */
const CADENCE_MONTHS: Readonly<Record<string, number | null>> = {
    Monthly: 1,
    Quarterly: 3,
    SemiAnnual: 6,
    Annual: 12,
    Milestone: null,
    Custom: null,
};

@RegisterClass(BaseRemotableOperation, 'Contracts.GenerateBillingEvent')
export class GenerateBillingEventOperation extends BaseRemotableOperation<
    GenerateBillingEventInput,
    GenerateBillingEventOutput
> {
    public OperationKey = 'Contracts.GenerateBillingEvent';

    protected async InternalExecute(
        input: GenerateBillingEventInput,
        provider: IMetadataProvider,
        user: UserInfo,
    ): Promise<GenerateBillingEventOutput> {
        if (!input?.ContractBillingEventID) {
            return { Success: false, Message: 'ContractBillingEventID is required.' };
        }

        const md = new Metadata();
        const db = Metadata.Provider as unknown as DatabaseProviderBase;
        const eventID = input.ContractBillingEventID;

        const event = await md.GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, user);
        if (!(await event.Load(eventID))) {
            return { Success: false, Message: `Billing event ${eventID} was not found.` };
        }

        // A preview reads and prices; it claims nothing and writes nothing, so two people may
        // preview the same event at once without either blocking the other.
        if (input.PreviewOnly) {
            const built = await this.buildDraft(event, md, user);
            if (!built.Draft) return { Success: false, Message: built.Message };
            const priced = await GetOrdersBillingBridge().PreviewOrder(built.Draft, user);
            return {
                Success: priced.Success,
                Message: priced.Message,
                ContractBillingEventID: eventID,
                ComputedAmount: priced.Total,
                Draft: built.Draft,
            };
        }

        let draft: BillingDraft | undefined;
        try {
            await db.BeginTransaction();

            const claimed = await this.claim(db, eventID);
            if (!claimed) {
                await db.RollbackTransaction();
                // Re-read to say what actually happened, rather than guessing.
                await event.Load(eventID);
                return {
                    Success: false,
                    AlreadyClaimed: true,
                    ContractBillingEventID: eventID,
                    Message:
                        `This billing event is ${event.Status}, not Scheduled — another run has already ` +
                        `worked it, or a person moved it. Nothing was billed.`,
                };
            }

            const built = await this.buildDraft(event, md, user);
            if (!built.Draft) throw new Error(built.Message ?? 'The billing draft could not be assembled.');
            draft = built.Draft;

            if (draft.Lines.length === 0) {
                // NOT a failure. A period during which nothing was due is a real and common outcome —
                // a milestone schedule with no milestone reached, say. Skipped records that the run
                // happened and decided there was nothing to bill, which is different from Failed
                // (something went wrong) and from Scheduled (nobody has looked).
                await this.finishSkipped(event, user);
                await db.CommitTransaction();
                return {
                    Success: true,
                    ContractBillingEventID: eventID,
                    Draft: draft,
                    Message: 'Nothing was due for this period, so the event was skipped rather than billed.',
                };
            }

            const bridge = GetOrdersBillingBridge();

            // PRICE FIRST, WRITE SECOND. A failure to price must not leave a half-materialised order,
            // and pricing is where the contracted-price resolver is exercised.
            const priced = await bridge.PreviewOrder(draft, user);
            if (!priced.Success) throw new Error(priced.Message ?? 'Orders could not price this bill.');

            const materialized = await bridge.CreateOrderInState(draft, user);
            if (!materialized.Success || !materialized.OrderID) {
                throw new Error(materialized.Message ?? 'Orders could not materialise this bill.');
            }

            await this.finishGenerated(event, materialized.OrderID, materialized.Total ?? priced.Total ?? 0, user);
            await this.writeLog(draft, materialized.OrderID, md, user);

            await db.CommitTransaction();
            return {
                Success: true,
                ContractBillingEventID: eventID,
                OrderID: materialized.OrderID,
                ComputedAmount: materialized.Total ?? priced.Total,
                Draft: draft,
            };
        } catch (e) {
            const reason = e instanceof Error ? e.message : String(e);
            try {
                await db.RollbackTransaction();
            } catch {
                // Already rolled back by the server; the failure record below is what matters.
            }
            // OUTSIDE the rolled-back transaction, deliberately. Recording the failure inside it
            // would roll the record back along with the failure, and the row would look as though
            // nothing had ever been tried — which is precisely the state a worklist cannot act on.
            await this.recordFailure(eventID, reason, md, user);
            return { Success: false, ContractBillingEventID: eventID, Message: reason, Draft: draft };
        }
    }

    // ── The claim ───────────────────────────────────────────────────────────────────────────────

    /**
     * Take the event, or discover that somebody else has.
     *
     * The self-assignment is not a trick: it takes the row's exclusive lock for the duration of the
     * transaction while writing nothing a person could notice. Everything about the guarantee comes
     * from the `WHERE` being re-evaluated after the lock is granted.
     */
    private async claim(db: DatabaseProviderBase, eventID: string): Promise<boolean> {
        const rows = await db.ExecuteSQL(
            `UPDATE ${SCHEMA}.ContractBillingEvent
                SET Status = Status
              WHERE ID = '${eventID}' AND Status = 'Scheduled';
             SELECT @@ROWCOUNT AS Claimed;`,
        );
        const claimed = Array.isArray(rows) && rows.length ? Number((rows[0] as { Claimed: number }).Claimed) : 0;
        return claimed === 1;
    }

    // ── Assembly ────────────────────────────────────────────────────────────────────────────────

    /**
     * Decide what this occurrence bills.
     *
     * Reads the term with its coverage and commitments in one hydration, then walks the line types.
     * Everything here is a decision about WHAT, never about what it costs.
     */
    private async buildDraft(
        event: mjBizAppsContractsContractBillingEventEntity,
        md: Metadata,
        user: UserInfo,
    ): Promise<{ Draft?: BillingDraft; Message?: string }> {
        const term = await md.GetEntityObject<ContractTermEntityServer>(E_TERM, user);
        if (!(await term.Load(event.ContractTermID))) {
            return { Message: `The term ${event.ContractTermID} this event belongs to was not found.` };
        }
        await term.LoadChildren(user);

        const contract = await md.GetEntityObject<ContractEntityServer>(E_CONTRACT, user);
        if (!(await contract.Load(term.ContractID))) {
            return { Message: `The contract behind term ${term.TermNumber} was not found.` };
        }

        // A terminated agreement does not bill, whatever its schedule still says. Termination cancels
        // future events, but an event already in flight when the contract ended must not slip through.
        if (contract.Status === 'Terminated' || term.Status === 'Terminated') {
            return { Message: `The agreement is ${contract.Status} and term ${term.TermNumber} is ${term.Status}, so nothing bills.` };
        }

        const period = this.periodFor(event, term);
        const lines: BillingDraftLine[] = [];

        const termStart = GenerateBillingEventOperation.iso(term.StartDate) ?? period.Start;
        for (const line of term.Lines) {
            const drafted = this.draftLine(line, period, termStart);
            if (drafted) lines.push(drafted);
        }

        for (const commitment of term.Commitments) {
            const shortfall = this.draftShortfall(commitment, period);
            if (shortfall) lines.push(shortfall);
        }

        return {
            Draft: {
                ContractID: contract.ID,
                ContractTermID: term.ID,
                ContractBillingEventID: event.ID,
                CompanyID: contract.CompanyID,
                CustomerOrganizationID: contract.CustomerOrganizationID,
                CustomerPersonID: contract.CustomerPersonID,
                CurrencyID: term.CurrencyID,
                PaymentTermsTypeID: term.PaymentTermsTypeID,
                PeriodStart: period.Start,
                PeriodEnd: period.End,
                PricedAt: GenerateBillingEventOperation.iso(contract.PricedAt),
                Lines: lines,
            },
        };
    }

    /**
     * The window this occurrence covers: from its scheduled date to the day before the next one
     * would fall, clamped to the term's end.
     *
     * A cadence with no month count (Milestone, Custom) has no computable window, so the period is
     * the occurrence date itself — the milestone is a point in time, not a span.
     */
    private periodFor(
        event: mjBizAppsContractsContractBillingEventEntity,
        term: ContractTermEntityServer,
    ): { Start: string; End: string } {
        const start = GenerateBillingEventOperation.asDate(event.ScheduledDate) ?? new Date();
        const months = CADENCE_MONTHS[term.BillingFrequency as string] ?? null;
        if (months === null) {
            const day = GenerateBillingEventOperation.iso(start)!;
            return { Start: day, End: day };
        }

        const end = new Date(start);
        end.setUTCMonth(end.getUTCMonth() + months);
        end.setUTCDate(end.getUTCDate() - 1);

        const termEnd = GenerateBillingEventOperation.asDate(term.EndDate);
        const clamped = termEnd && end.getTime() > termEnd.getTime() ? termEnd : end;
        return { Start: GenerateBillingEventOperation.iso(start)!, End: GenerateBillingEventOperation.iso(clamped)! };
    }

    /** Whether one coverage line bills in this window, and as what. */
    private draftLine(
        line: ContractTermEntityServer['Lines'][number],
        period: { Start: string; End: string },
        termStart: string,
    ): BillingDraftLine | null {
        const lineStart = GenerateBillingEventOperation.iso(line.StartDate);
        const lineEnd = GenerateBillingEventOperation.iso(line.EndDate);

        // A line whose own window has closed, or has not opened, does not bill in this period —
        // whatever its type. A null bound means "for the whole term", which always overlaps.
        if (lineEnd && lineEnd < period.Start) return null;
        if (lineStart && lineStart > period.End) return null;

        const base = {
            ContractLineID: line.ID,
            ProductID: line.ProductID,
            Quantity: line.Quantity,
            ContractedUnitPrice: line.ContractedUnitPrice,
            DiscountPct: line.DiscountPct,
            ServicePeriodStart: period.Start,
            ServicePeriodEnd: period.End,
        };

        switch (line.LineType) {
            case 'Subscription':
                // The recurring case: it bills every period the term runs.
                return { ...base, Reason: 'subscription-period', Description: line.Description ?? 'Subscription charge' };

            case 'OneTime': {
                // ONCE, in the period its window OPENS — not every period thereafter.
                //
                // The opening date is the LINE's start when it states one, and otherwise the TERM's
                // start: a one-time charge with no date of its own is due at the beginning of the
                // agreement. Reading a missing date as "opens in whatever period is being billed"
                // made every occurrence its first, so an onboarding fee billed monthly, forever.
                // The tests caught it on the second occurrence.
                const opens = lineStart ?? termStart;
                if (opens < period.Start) return null;
                return { ...base, Reason: 'one-time-window-opened', Description: line.Description ?? 'One-time charge' };
            }

            case 'Milestone':
                // Milestones bill when REACHED, and nothing marks one reached yet — see the gap
                // logged in plans/QUESTIONS.md. Billing every period would be wrong in the expensive
                // direction, so it bills in none until the marker exists.
                return null;

            case 'Usage':
                // Usage metering is out of v1 (plan §9.3): orders ships usage pricing fields but the
                // metering engine is deferred, so there is no quantity to read. The line type stays
                // in the value list so the schema does not change when metering arrives.
                return null;

            case 'Minimum':
                // A minimum is not billed as coverage. It is billed as a SHORTFALL, through the
                // commitment that records what was promised and what was consumed.
                return null;

            default:
                return null;
        }
    }

    /**
     * The shortfall on a commitment, per its true-up policy.
     *
     * This is the one subtraction in the engine, and it is not a price: both figures are recorded on
     * the agreement. What each policy MEANS for which commitment types is question X.13, open with
     * Andrew — so the policies are applied exactly as written and no combination is inferred.
     */
    private draftShortfall(
        commitment: ContractTermEntityServer['Commitments'][number],
        period: { Start: string; End: string },
    ): BillingDraftLine | null {
        if (commitment.Status !== 'Open') return null;

        // A commitment is trued up at the END of its period, not during it. Billing a shortfall
        // mid-period would charge for spend the customer still has time to make.
        const periodEnd = GenerateBillingEventOperation.iso(commitment.PeriodEnd);
        if (periodEnd && periodEnd > period.End) return null;

        const committed = Number(commitment.CommittedAmount ?? 0);
        const consumed = Number(commitment.ConsumedAmount ?? 0);
        const shortfall = committed - consumed;
        if (shortfall <= 0) return null;

        // `Forfeit` means the customer loses the unspent balance rather than being billed for it,
        // and `Rollover` carries it into the next period — neither produces a charge NOW. Only
        // `BillShortfall` does, which is what its name says.
        if (commitment.TrueUpPolicy !== 'BillShortfall') return null;

        return {
            ContractLineID: null,
            // A shortfall has no product of its own; orders resolves the true-up product. Passing a
            // guess here would be contracts deciding what it costs.
            ProductID: '',
            Quantity: 1,
            ContractedUnitPrice: shortfall,
            DiscountPct: null,
            ServicePeriodStart: period.Start,
            ServicePeriodEnd: period.End,
            Reason: 'minimum-shortfall',
            Description:
                `Minimum commitment shortfall: committed ${committed.toFixed(2)}, consumed ` +
                `${consumed.toFixed(2)}.`,
        };
    }

    // ── Outcomes ────────────────────────────────────────────────────────────────────────────────

    private async finishGenerated(
        event: mjBizAppsContractsContractBillingEventEntity,
        orderID: string,
        total: number,
        _user: UserInfo,
    ): Promise<void> {
        event.Status = 'Generated';
        event.OrderID = orderID;
        event.ComputedAmount = total;
        // All three together: the CHECKs require an order AND a timestamp on a Generated row, and
        // stamping them apart is how a row ends up half-explained.
        event.GeneratedAt = new Date();
        if (!(await event.Save())) {
            throw new Error(`Could not stamp the billing event: ${event.LatestResult?.CompleteMessage ?? 'unknown error'}`);
        }
    }

    private async finishSkipped(
        event: mjBizAppsContractsContractBillingEventEntity,
        _user: UserInfo,
    ): Promise<void> {
        event.Status = 'Skipped';
        event.Notes = 'Nothing was due for this period.';
        if (!(await event.Save())) {
            throw new Error(`Could not skip the billing event: ${event.LatestResult?.CompleteMessage ?? 'unknown error'}`);
        }
    }

    /**
     * Record the failure so a person can act on it.
     *
     * Its OWN transaction, because the work that failed has already been rolled back — writing this
     * inside that transaction would roll the explanation back too. A `Failed` event is never
     * auto-retried into a duplicate; it goes to the worklist.
     */
    private async recordFailure(eventID: string, reason: string, md: Metadata, user: UserInfo): Promise<void> {
        try {
            const event = await md.GetEntityObject<mjBizAppsContractsContractBillingEventEntity>(E_BILLING_EVENT, user);
            if (!(await event.Load(eventID))) return;
            event.Status = 'Failed';
            // CK_ContractBillingEvent_FailedHasReason: "Failed" with no reason is a support ticket
            // nobody can answer.
            event.FailureReason = reason.slice(0, 3900);
            await event.Save();
        } catch {
            // A failure to record a failure must not mask the original one, which the caller already
            // has and is about to return.
        }
    }

    /** The audit trail. Append-only by construction — ContractEventEntityServer refuses edits. */
    private async writeLog(draft: BillingDraft, orderID: string, md: Metadata, user: UserInfo): Promise<void> {
        const log = await md.GetEntityObject<mjBizAppsContractsContractEventEntity>(E_LOG, user);
        log.NewRecord();
        log.ContractID = draft.ContractID;
        log.ContractTermID = draft.ContractTermID;
        log.EventType = 'BillingEventGenerated';
        log.EventDate = new Date();
        log.PerformedByUserID = user?.ID ?? null;
        log.Payload = JSON.stringify({
            ContractBillingEventID: draft.ContractBillingEventID,
            OrderID: orderID,
            PeriodStart: draft.PeriodStart,
            PeriodEnd: draft.PeriodEnd,
            LineCount: draft.Lines.length,
            Reasons: draft.Lines.map((l) => l.Reason),
        });
        if (!(await log.Save())) {
            throw new Error(`Could not write the billing audit event: ${log.LatestResult?.CompleteMessage ?? 'unknown error'}`);
        }
    }

    private static asDate(value: Date | string | null | undefined): Date | null {
        if (!value) return null;
        const d = value instanceof Date ? value : new Date(value);
        return Number.isNaN(d.getTime()) ? null : d;
    }

    private static iso(value: Date | string | null | undefined): string | null {
        const d = GenerateBillingEventOperation.asDate(value);
        return d ? d.toISOString().slice(0, 10) : null;
    }
}

/** Tree-shaking anchor — called from the server bootstrap so @RegisterClass is retained. */
export function LoadGenerateBillingEventOperation(): void {
    /* intentionally empty */
}

/**
 * The scheduled driver: every event that is due, one at a time.
 *
 * BOUNDED PER RUN and idempotent. Bounded because an unbounded run on a busy tenant is a transaction
 * that never ends; idempotent because each event is claimed individually, so two overlapping runs
 * interleave safely rather than racing — the second simply finds each row already taken.
 *
 * `Failed` events are NOT retried here. The plan is explicit: a failed bill goes to a worklist for a
 * person, never back into the queue, because an automatic retry is exactly how one failure becomes
 * two invoices.
 *
 * Reads through `IX_ContractBillingEvent_Due`, which exists for this query.
 */
export async function RunDueBillingEvents(
    user: UserInfo,
    options?: { AsOf?: Date; MaxEvents?: number },
): Promise<{ Considered: number; Generated: number; Skipped: number; Failed: number; AlreadyClaimed: number; Details: GenerateBillingEventOutput[] }> {
    const asOf = options?.AsOf ?? new Date();
    const max = options?.MaxEvents ?? 100;
    const md = new Metadata();
    const rv = new RunView(Metadata.Provider as unknown as IRunViewProvider);

    const due = await rv.RunView<{ ID: string }>(
        {
            EntityName: E_BILLING_EVENT,
            Fields: ['ID'],
            ExtraFilter: `Status='Scheduled' AND ScheduledDate <= '${asOf.toISOString().slice(0, 10)}'`,
            OrderBy: 'ScheduledDate ASC',
            MaxRows: max,
            ResultType: 'simple',
        },
        user,
    );
    // Loud on failure: a driver that treats an unreadable queue as an empty one bills nothing and
    // reports success, which is the worst possible combination.
    if (!due?.Success) {
        throw new Error(`Could not read the billing queue: ${due?.ErrorMessage ?? 'unknown error'}`);
    }

    const operation = new GenerateBillingEventOperation();
    const details: GenerateBillingEventOutput[] = [];
    let generated = 0, skipped = 0, failed = 0, alreadyClaimed = 0;

    for (const row of due.Results ?? []) {
        const result = await operation.ExecuteServer(
            { ContractBillingEventID: row.ID },
            { provider: Metadata.Provider, user, emitProgress: () => undefined } as never,
        );
        const output = result.Output as GenerateBillingEventOutput | undefined;
        if (!output) { failed++; continue; }
        details.push(output);
        if (output.AlreadyClaimed) alreadyClaimed++;
        else if (!output.Success) failed++;
        else if (output.OrderID) generated++;
        else skipped++;
    }

    return { Considered: due.Results?.length ?? 0, Generated: generated, Skipped: skipped, Failed: failed, AlreadyClaimed: alreadyClaimed, Details: details };
}
